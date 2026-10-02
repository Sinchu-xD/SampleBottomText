import subprocess, time, os
out = open(r"C:\Tools\rd_public_log.txt", "w")
def L(m): out.write(str(m) + "\n"); out.flush()

cfg = r"C:\Users\admin\AppData\Roaming\RustDesk\config\RustDesk2.toml"
# revert to public rustdesk servers: just access-mode + direct-ip-access stay
content = ('[options]\n'
           'direct-ip-access = "Y"\n'
           'access-mode = "full"\n')
open(cfg, "w", encoding="utf-8").write(content)
L("config reverted to public")

subprocess.run("taskkill /f /im rustdesk.exe >nul 2>&1", shell=True)
time.sleep(2)
exe = r"C:\Users\admin\AppData\Local\rustdesk\rustdesk.exe"
subprocess.Popen([exe], cwd=os.path.dirname(exe),
                 creationflags=0x00000008 | 0x00000200,
                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
L("tray relaunched")
for i in range(5):
    time.sleep(5)
    r = subprocess.run([exe, "--get-id"], capture_output=True, text=True, cwd=os.path.dirname(exe))
    L("id: %r err: %r" % (r.stdout.strip(), r.stderr.strip()[:100]))
    # check online via netstat: established to public rustdesk
    r2 = subprocess.run("netstat -ano | findstr ESTABLISHED | findstr rustdesk", shell=True, capture_output=True, text=True)
    L("estab: %r" % r2.stdout[:200])
    if r.stdout.strip().isdigit():
        L("READY")
        break
L("done")