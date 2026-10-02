import subprocess, time, os
log = open(r"C:\Tools\mesh_run_log.txt", "w")
def L(m): log.write(str(m) + "\n"); log.flush()

subprocess.run("taskkill /f /im meshagent.exe >nul 2>&1", shell=True)
time.sleep(2)

meshdir = r"C:\Tools\mesh"
# verify msh content on disk
L("msh head: %r" % open(os.path.join(meshdir, "meshagent.msh"), "rb").read()[:200])

exe = os.path.join(meshdir, "meshagent.exe")
DET = 0x00000008 | 0x00000200
p = subprocess.Popen([exe, "-connect"], cwd=meshdir, creationflags=DET,
                     stdin=subprocess.DEVNULL,
                     stdout=open(os.path.join(meshdir, "agent_stdout.txt"), "wb"),
                     stderr=open(os.path.join(meshdir, "agent_stderr.txt"), "wb"))
L("spawned pid=%d" % p.pid)
for i in range(6):
    time.sleep(5)
    r = subprocess.run("netstat -ano | findstr 44330 | findstr ESTABLISHED", shell=True, capture_output=True, text=True)
    alive = (p.poll() is None)
    L("t+%ds alive=%s estab=%r" % ((i+1)*5, alive, r.stdout[:150]))
    if not alive:
        L("agent EXITED code=%s" % p.returncode)
        break
L("stdout: %r" % open(os.path.join(meshdir, "agent_stdout.txt"), "rb").read()[:300])
L("stderr: %r" % open(os.path.join(meshdir, "agent_stderr.txt"), "rb").read()[:300])
# list any log files agent made
for f in os.listdir(meshdir):
    L("file: %s (%d)" % (f, os.path.getsize(os.path.join(meshdir, f))))
L("done")