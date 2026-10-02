import subprocess, time, os, glob
out = open(r"C:\Tools\rd_svc_log.txt", "w")
def L(m): out.write(str(m) + "\n"); out.flush()

# dump existing logs
for pat in [r"C:\Users\admin\AppData\Roaming\RustDesk\log\*.log",
            r"C:\Users\admin\AppData\Local\RustDesk\log\*.log",
            r"C:\Users\admin\AppData\Roaming\RustDesk\log\server\*.log"]:
    for f in glob.glob(pat):
        try:
            L("=== %s ===" % f)
            L(open(f, encoding="utf-8", errors="replace").read()[-1500:])
        except Exception as e:
            L("ERR %s %r" % (f, e))

L("kill all rustdesk")
subprocess.run("taskkill /f /im rustdesk.exe >nul 2>&1", shell=True)
time.sleep(3)

exe = r"C:\Users\admin\AppData\Local\rustdesk\rustdesk.exe"
DETACHED = 0x00000008 | 0x00000200
kw = dict(cwd=os.path.dirname(exe), creationflags=DETACHED,
          stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.Popen([exe, "--service"], **kw)
L("launched --service")
for i in range(6):
    time.sleep(4)
    r = subprocess.run("netstat -ano | findstr 21118", shell=True, capture_output=True, text=True)
    L("t+%ds netstat: %r" % ((i+1)*4, r.stdout[:150]))
    r = subprocess.run("tasklist | findstr /i rustdesk", shell=True, capture_output=True, text=True)
    L("t+%ds procs: %r" % ((i+1)*4, r.stdout[:150]))
    if "21118" in r.stdout or "LISTEN" in str(subprocess.run("netstat -ano | findstr 21118", shell=True, capture_output=True, text=True).stdout):
        break
L("done")