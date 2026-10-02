import subprocess, time, json, sys, os, socket, base64, struct, urllib.request

log = open(r"C:\Tools\live_ck_log.txt", "w")
def L(m): log.write(str(m) + "\n"); log.flush()

L("kill edge")
subprocess.run("taskkill /f /im msedge.exe >nul 2>&1", shell=True)
time.sleep(2)
L("start REAL profile edge, off-screen, cdp 9223")
subprocess.Popen([r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                  "--profile-directory=Default",
                  "--window-position=-32000,-32000", "--window-size=1920,1080",
                  "--remote-debugging-port=9223", "--no-first-run", "about:blank"], shell=None)
dbg = 9223
for i in range(20):
    time.sleep(2)
    try:
        urllib.request.urlopen("http://127.0.0.1:%d/json/version" % dbg, timeout=3)
        L("cdp up"); break
    except Exception:
        L("wait %d" % i)
else:
    L("FAILED cdp"); log.close(); sys.exit(1)
time.sleep(3)

def http_json(path):
    return json.loads(urllib.request.urlopen("http://127.0.0.1:%d%s" % (dbg, path), timeout=8).read().decode())

class WS:
    def __init__(self, url):
        rest = url[5:]; hostport, path = rest.split("/", 1); path = "/" + path
        hp = hostport.split(":")
        self.sock = socket.create_connection((hp[0], int(hp[1])), timeout=10)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall(("GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                           "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % (path, hostport, key)).encode())
        resp = b""
        while b"\r\n\r\n" not in resp:
            resp += self.sock.recv(4096)
        assert b"101" in resp.split(b"\r\n")[0]
    def send(self, data):
        p = data.encode(); n = len(p)
        hdr = bytearray([0x81])
        if n < 126: hdr.append(0x80 | n)
        else: hdr.append(0x80 | 126); hdr += struct.pack(">H", n)
        mask = os.urandom(4); hdr += mask
        self.sock.sendall(bytes(hdr) + bytes(b ^ mask[i % 4] for i, b in enumerate(p)))
    def recv(self):
        def rd(n):
            d = b""
            while len(d) < n:
                c = self.sock.recv(n - len(d))
                if not c: raise EOFError
                d += c
            return d
        b1, b2 = rd(2); n = b2 & 0x7F
        if n == 126: n = struct.unpack(">H", rd(2))[0]
        elif n == 127: n = struct.unpack(">Q", rd(8))[0]
        return rd(n).decode("utf-8", errors="replace")

t = http_json("/json/new?https://www.youtube.com/")
ws = WS(t["webSocketDebuggerUrl"])
mid = 0
def cmd(method, params=None):
    global mid
    mid += 1
    ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    deadline = time.time() + 20
    while time.time() < deadline:
        msg = json.loads(ws.recv())
        if msg.get("id") == mid:
            return msg
    return {}

page.wait = None
time.sleep(8)

r = cmd("Runtime.evaluate", {"expression": "JSON.stringify({url: location.href, avatar: !!document.querySelector('img#avatar-btn, button#avatar-btn'), title: document.title})",
                             "returnByValue": True})
L("page state: %s" % r.get("result", {}).get("result", {}).get("value"))

r = cmd("Network.getCookies", {"urls": ["https://www.youtube.com", "https://www.google.com", "https://accounts.google.com"]})
cks = r.get("result", {}).get("cookies", [])
L("live cookies: %d" % len(cks))
out = {c["name"] + "@" + c.get("domain", ""): c["value"] for c in cks}
# key auth values
for k in ["SID@.google.com", "__Secure-1PSID@.google.com", "__Secure-1PSIDTS@.google.com",
          "SAPISID@.google.com", "SID@.youtube.com", "__Secure-1PSID@.youtube.com",
          "__Secure-1PSIDTS@.youtube.com"]:
    v = out.get(k, "MISSING")
    L("%s = %s" % (k, v[:60]))
json.dump(out, open(r"C:\Tools\live_cookies.json", "w"))
subprocess.run("taskkill /f /im msedge.exe >nul 2>&1", shell=True)
L("done")