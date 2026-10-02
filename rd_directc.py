import subprocess, time, os

paths = [
    r"C:\Users\admin\AppData\Roaming\RustDesk\config",
    r"C:\Windows\System32\config\systemprofile\AppData\Roaming\RustDesk\config",
]
out = open(r"C:\Tools\rd_cfg_log.txt", "w")
def L(m): out.write(str(m) + "\n"); out.flush()

content = '[options]\ndirect-ip-access = "Y"\naccess-mode = "full"\nstop-service = "N"\n'

L("stop rustdesk service + processes")
subprocess.run("net stop RustDesk >nul 2>&1", shell=True)
subprocess.run("taskkill /f /im rustdesk.exe >nul 2>&1", shell=True)
time.sleep(2)

for p in paths:
    try:
        os.makedirs(p, exist_ok=True)
        fp = os.path.join(p, "RustDesk2.toml")
        # merge: keep existing content if file exists
        old = ""
        if os.path.exists(fp):
            old = open(fp, "r", encoding="utf-8", errors="replace").read()
        if "direct-ip-access" not in old:
            new = old + "\n" + content if old else content
            open(fp, "w", encoding="utf-8").write(new)
            L("wrote " + fp)
        else:
            L("already has direct-ip-access: " + fp)
        L("--- %s ---" % fp)
        L(open(fp, encoding="utf-8", errors="replace").read()[:300])
    except Exception as e:
        L("ERR %s: %r" % (p, e))

L("start service")
subprocess.run("net start RustDesk >nul 2>&1", shell=True)
subprocess.run("sc query RustDesk >nul 2>&1", shell=True)
time.sleep(3)
r = subprocess.run("netstat -ano | findstr 21118", shell=True, capture_output=True, text=True)
L("netstat 21118: %r" % r.stdout)
r = subprocess.run("sc query RustDesk", shell=True, capture_output=True, text=True)
L("service: %s" % r.stdout[:200])
L("done")