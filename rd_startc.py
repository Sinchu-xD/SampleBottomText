import subprocess, time, os
out = open(r"C:\Tools\rd_start_log.txt", "w")
def L(m): out.write(str(m) + "\n"); out.flush()

exe = r"C:\Users\admin\AppData\Local\rustdesk\rustdesk.exe"
L("exists: %s" % os.path.exists(exe))
if not os.path.exists(exe):
    # portable extraction dir
    for cand in [r"C:\Tools\rustdesk.exe"]:
        L("alt exists %s: %s" % (cand, os.path.exists(cand)))

DETACHED = 0x00000008
CREATE_NEW_PROCESS_GROUP = 0x00000200

for tag, arg in [("service", "--service"), ("tray", None)]:
    try:
        kw = dict(cwd=os.path.dirname(exe), creationflags=DETACHED | CREATE_NEW_PROCESS_GROUP,
                  stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        args = [exe] + ([arg] if arg else [])
        subprocess.Popen(args, **kw)
        L("launched %s (%s)" % (tag, arg))
        time.sleep(6)
        r = subprocess.run("tasklist | findstr /i rustdesk", shell=True, capture_output=True, text=True)
        L("procs after %s: %r" % (tag, r.stdout[:200]))
        r = subprocess.run("netstat -ano | findstr 21118", shell=True, capture_output=True, text=True)
        L("netstat: %r" % r.stdout[:200])
        if "21118" in r.stdout:
            L("LISTENER UP")
            break
    except Exception as e:
        L("ERR %s: %r" % (tag, e))
L("done")