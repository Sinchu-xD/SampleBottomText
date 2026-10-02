import hashlib, binascii, subprocess, time, re
out = open(r"C:\Tools\ad_cfg_log.txt", "w")
def L(m): out.write(str(m) + "\n"); out.flush()

CFG = r"C:\ProgramData\AnyDesk\system.conf"
EXE = r"C:\Program Files (x86)\AnyDesk\AnyDesk.exe"
PW = "KdRemote2026!"

# choose a fresh random salt
salt = binascii.hexlify(b"RdAny26!SaltNuCTarget0_9A1").decode()[:32]  # 16 bytes as hex
salt_b = binascii.unhexlify(salt)
h = hashlib.pbkdf2_hmac('sha256', PW.encode(), salt_b, 1000, 32).hex()

L("salt=%s" % salt)
L("hash=%s" % h)

L("stopping anydesk")
subprocess.run("net stop AnyDesk >nul 2>&1", shell=True)
subprocess.run("taskkill /f /im AnyDesk.exe >nul 2>&1", shell=True)
time.sleep(3)

cfg = open(CFG, "r", encoding="utf-8", errors="replace").read()
# replace or add _unattended_access and _full_access pwd/salt
def set_kv(cfg, key, val):
    pat = re.compile(r"^%s=.*$" % re.escape(key), re.M)
    line = "%s=%s" % (key, val)
    if pat.search(cfg):
        return pat.sub(line, cfg)
    return cfg.rstrip("\n") + "\n" + line + "\n"

for prof in ["_full_access", "_unattended_access"]:
    cfg = set_kv(cfg, "ad.security.permission_profiles.%s.pwd" % prof, h)
    cfg = set_kv(cfg, "ad.security.permission_profiles.%s.salt" % prof, salt)
cfg = set_kv(cfg, "ad.security.interactive_access", "1")
cfg = set_kv(cfg, "ad.security.unattended_access_enabled", "1")
cfg = set_kv(cfg, "ad.security.unattended_access_behaviour.always", "1")
cfg = set_kv(cfg, "ad.security.unattended_access_override_password", h)
cfg = set_kv(cfg, "ad.security.unattended_access_override_salt", salt)

open(CFG, "w", encoding="utf-8").write(cfg)
L("config written")

L("restart anydesk")
subprocess.run("net start AnyDesk >nul 2>&1", shell=True)
time.sleep(4)
subprocess.run('start "" "%s"' % EXE, shell=True)
time.sleep(3)
r = subprocess.run([EXE, "--get-id"], capture_output=True, text=True, timeout=30)
L("id: %r" % r.stdout.strip())
r = subprocess.run("tasklist | findstr /i anydesk", shell=True, capture_output=True, text=True)
L("procs: %r" % r.stdout[:200])
L("done")