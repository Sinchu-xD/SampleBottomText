import subprocess, time, socket, ssl, os, sys
log = open(r"C:\Tools\mesh_fix_log.txt", "w")
def L(m): log.write(str(m) + "\n"); log.flush()

L("kill idle agents")
subprocess.run("taskkill /f /im meshagent.exe >nul 2>&1", shell=True)
time.sleep(2)

# 1. probe tunnel endpoint from target
L("probe 127.0.0.1:44330")
try:
    s = socket.create_connection(("127.0.0.1", 44330), timeout=10)
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    ts = ctx.wrap_socket(s, server_hostname="127.0.0.1")
    ts.sendall(b"GET /agent.ashx HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
    time.sleep(1)
    d = ts.recv(2048)
    L("TLS OK, response head: %r" % d[:120])
    ts.close()
except Exception as e:
    L("TUNNEL PROBE FAILED: %r" % e)

# 2. relaunch agent with -connect (foreground dial)
meshdir = r"C:\Tools\mesh"
exe = os.path.join(meshdir, "meshagent.exe")
L("launch agent -connect")
DET = 0x00000008 | 0x00000200
subprocess.Popen([exe, "-connect"], cwd=meshdir, creationflags=DET,
                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(15)
r = subprocess.run("netstat -ano | findstr 44330", shell=True, capture_output=True, text=True)
L("netstat 44330:\n%s" % r.stdout[:500])
r = subprocess.run("tasklist | findstr /i meshagent", shell=True, capture_output=True, text=True)
L("procs: %r" % r.stdout[:200])
L("done")