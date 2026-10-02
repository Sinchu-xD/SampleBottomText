import subprocess, time, os
out = open(r"C:\Tools\rd_final_log.txt", "w")
def L(m): out.write(str(m) + "\n"); out.flush()

# 1. kill old ssh tunnel(s)
subprocess.run("taskkill /f /im ssh.exe >nul 2>&1", shell=True)
time.sleep(2)

# 2. new tunnel: -L forwards to VPS relay stack
L("start -L tunnel to VPS relay")
subprocess.Popen([
    r"C:\Windows\System32\OpenSSH\ssh.exe", "-N",
    "-L", "21115:127.0.0.1:21115", "-L", "21116:127.0.0.1:21116",
    "-L", "21117:127.0.0.1:21117", "-L", "21119:127.0.0.1:21119",
    "-o", "StrictHostKeyChecking=no", "-o", "ServerAliveInterval=30",
    "-i", r"C:\Tools\rdtunnel.key", "-p", "52976", "root@103.124.157.61"],
    creationflags=0x00000008 | 0x00000200,
    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(6)
r = subprocess.run("netstat -ano | findstr 2111", shell=True, capture_output=True, text=True)
L("local listeners: %r" % r.stdout[:400])

# 3. point rustdesk at our relay + key
cfg = r"C:\Users\admin\AppData\Roaming\RustDesk\config\RustDesk2.toml"
content = ('[options]\n'
           'custom-rendezvous-server = "127.0.0.1"\n'
           'relay-server = "127.0.0.1"\n'
           'key = "MjdaG2lpsrzw9D6kBdc7AU0kst0pkDfb5Ke3VnKOKgg="\n'
           'access-mode = "full"\n')
open(cfg, "w", encoding="utf-8").write(content)
L("wrote config")

# 4. restart rustdesk tray
subprocess.run("taskkill /f /im rustdesk.exe >nul 2>&1", shell=True)
time.sleep(2)
exe = r"C:\Users\admin\AppData\Local\rustdesk\rustdesk.exe"
subprocess.Popen([exe], cwd=os.path.dirname(exe),
                 creationflags=0x00000008 | 0x00000200,
                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
L("tray relaunched")
time.sleep(15)
r = subprocess.run(["tasklist"], shell=True, capture_output=True, text=True)
L("procs: %r" % ("rustdesk" in r.stdout))
r = subprocess.run("netstat -ano | findstr 21116", shell=True, capture_output=True, text=True)
L("21116 activity: %r" % r.stdout[:300])
L("done")