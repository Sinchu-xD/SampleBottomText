import subprocess, time, os
out = open(r"C:\Tools\rd_cfg2_log.txt", "w")
def L(m): out.write(str(m) + "\n"); out.flush()

cfg = r"C:\Users\admin\AppData\Roaming\RustDesk\config\RustDesk2.toml"
content = ('[options]\n'
           'custom-rendezvous-server = "127.0.0.1"\n'
           'relay-server = "127.0.0.1"\n'
           'key = "MjdaG2lpsrzw9D6kBdc7AU0kst0pkDfb5Ke3VnKOKgg="\n'
           'access-mode = "full"\n')
open(cfg, "w", encoding="utf-8").write(content)
L("config written")
L(open(cfg).read())

subprocess.run("taskkill /f /im rustdesk.exe >nul 2>&1", shell=True)
time.sleep(3)
exe = r"C:\Users\admin\AppData\Local\rustdesk\rustdesk.exe"
subprocess.Popen([exe], cwd=os.path.dirname(exe),
                 creationflags=0x00000008 | 0x00000200,
                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
L("tray relaunched")
time.sleep(20)
r = subprocess.run("netstat -ano | findstr ESTABLISHED", shell=True, capture_output=True, text=True)
L("estab lines: %d" % len(r.stdout.strip().splitlines()))
L("done")