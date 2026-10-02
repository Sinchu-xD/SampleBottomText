import json, os, socket, struct, base64, time, urllib.request

OUT = r"C:\Tools\fp_exact.json"

def http_json(path):
    r = urllib.request.urlopen("http://127.0.0.1:9222%s" % path, timeout=5)
    return json.loads(r.read().decode())

class WS:
    def __init__(self, url):
        rest = url[5:]
        hostport, path = rest.split("/", 1)
        path = "/" + path
        hp = hostport.split(":")
        self.sock = socket.create_connection((hp[0], int(hp[1])), timeout=10)
        key = base64.b64encode(os.urandom(16)).decode()
        req = ("GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % (path, hostport, key))
        self.sock.sendall(req.encode())
        resp = b""
        while b"\r\n\r\n" not in resp:
            resp += self.sock.recv(4096)
        assert b"101" in resp.split(b"\r\n")[0]
    def send(self, data):
        p = data.encode(); n = len(p)
        hdr = bytearray([0x81])
        if n < 126: hdr.append(0x80 | n)
        elif n < 65536: hdr.append(0x80 | 126); hdr += struct.pack(">H", n)
        else: hdr.append(0x80 | 127); hdr += struct.pack(">Q", n)
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
        b1, b2 = rd(2)
        op = b1 & 0x0F; n = b2 & 0x7F
        if n == 126: n = struct.unpack(">H", rd(2))[0]
        elif n == 127: n = struct.unpack(">Q", rd(8))[0]
        return rd(n).decode("utf-8", errors="replace")

JS = """
(() => {
  const nav = window.navigator, scr = window.screen;
  let gl_vendor = null, gl_renderer = null, gl_err = null;
  try {
    const c = document.createElement('canvas');
    const gl = c.getContext('webgl2') || c.getContext('webgl');
    const ext = gl.getExtension('WEBGL_debug_renderer_info');
    gl_vendor = gl.getParameter(ext.UNMASKED_VENDOR_WEBGL);
    gl_renderer = gl.getParameter(ext.UNMASKED_RENDERER_WEBGL);
  } catch (e) { gl_err = String(e); }
  let voices = [];
  try { voices = speechSynthesis.getVoices().map(v => v.name + ':' + v.lang + (v.localService ? ':local' : ':remote')); } catch (e) {}
  return JSON.stringify({
    userAgent: nav.userAgent,
    platform: nav.platform,
    hardwareConcurrency: nav.hardwareConcurrency,
    deviceMemory: nav.deviceMemory,
    languages: Array.from(nav.languages),
    language: nav.language,
    maxTouchPoints: nav.maxTouchPoints,
    screen: {w: scr.width, h: scr.height, aw: scr.availWidth, ah: scr.availHeight,
             cd: scr.colorDepth, pd: scr.pixelDepth, dpr: window.devicePixelRatio,
             ix: scr.availLeft, iy: scr.availTop},
    innerW: window.innerWidth, innerH: window.innerHeight,
    outerW: window.outerWidth, outerH: window.outerHeight,
    gl_vendor: gl_vendor, gl_renderer: gl_renderer, gl_err: gl_err,
    tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
    locale: Intl.DateTimeFormat().resolvedOptions().locale,
    voices: voices
  });
})()
"""

ver = http_json("/json/version")
print("Browser:", ver.get("Browser"), ver.get("Protocol-Version"))
try:
    t = http_json("/json/new?about:blank")
except Exception:
    t = http_json("/json/list")[0]
ws = WS(t["webSocketDebuggerUrl"])
ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate",
                    "params": {"expression": JS, "returnByValue": True}}))
deadline = time.time() + 15
while time.time() < deadline:
    msg = json.loads(ws.recv())
    if msg.get("id") == 1:
        val = msg["result"]["result"]["value"]
        open(OUT, "w").write(val)
        print("OK", len(val))
        break