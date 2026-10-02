import subprocess, time, json, sys
log = open(r"C:\Tools\fpx_log.txt", "w")
def L(m): log.write(str(m) + "\n"); log.flush()
L("step1: taskkill")
subprocess.run("taskkill /f /im msedge.exe >nul 2>&1", shell=True)
time.sleep(2)
L("step2: start headless edge")
subprocess.Popen([r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                  "--headless=new", "--remote-debugging-port=9222",
                  "--user-data-dir=C:\\Tools\\edgedbg", "--no-first-run", "--disable-gpu", "about:blank"],
                 shell=None)
for i in range(15):
    time.sleep(2)
    try:
        import urllib.request
        r = urllib.request.urlopen("http://127.0.0.1:9222/json/version", timeout=3)
        L("dbg up after %ds" % ((i+1)*2))
        break
    except Exception as e:
        L("wait %d: %r" % (i, e))
else:
    L("FAILED: debug port never came up")
    log.close(); sys.exit(1)
L("done")