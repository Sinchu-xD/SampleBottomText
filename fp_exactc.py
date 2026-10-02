#!/usr/bin/env python3
"""Minimal raw-WebSocket CDP client. Collects the exact fingerprint of the
target's Edge from a headless instance running on the target itself."""
import json, socket, struct, base64, os, hashlib, time, subprocess, urllib.request

OUT = r"C:\Tools\fp_exact.json"
DBG = 9222

def http_json(path):
    r = urllib.request.urlopen("http://127.0.0.1:%d%s" % (DBG, path), timeout=5)
    return json.loads(r.read().decode())

class WS:
    def __init__(self, url):
        assert url.startswith("ws://")
        rest = url[5:]
        host, path = rest.split("/", 1)
        path = "/" + path
        self.sock = socket.create_connection((host.split(":")[0], int(host.split(":")[1]) if ":" in host else 80), timeout=10)
        key = base64.b64encode(os.urandom(16)).decode()
        req = ("GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % (path, host, key))
        self.sock.sendall(req.encode())
        resp = b""
        while b"\r\n\r\n" not in resp:
            resp += self.sock.recv(4096)
        assert b"101" in resp.split(b"\r\n")[0], resp
    def send(self, data):
        p = data.encode()
        n = len(p)
        hdr = bytearray([0x81])
        if n < 126: hdr.append(0x80 | n)
        elif n < 65536: hdr.append(0x80 | 126); hdr += struct.pack(">H", n)
        else: hdr.append(0x80 | 127); hdr += struct.pack(">Q", n)
        mask = os.urandom(4)
        hdr += mask
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(p))
        self.sock.sendall(bytes(hdr) + masked)
    def recv(self):
        def rd(n):
            d = b""
            while len(d) < n:
                c = self.sock.recv(n - len(d))
                if not c: raise EOFError
                d += c
            return d
        b1, b2 = rd(2)
        op = b1 & 0x0F
        n = b2 & 0x7F
        if n == 126: n = struct.unpack(">H", rd(2))[0]
        elif n == 127: n = struct.unpack(">Q", rd(8))[0]
        payload = rd(n)
        if op == 8: raise EOFError
        return payload.decode("utf-8", errors="replace")

JS = """
(() => {
  const nav = window.navigator, scr = window.screen;
  let gl_vendor = null, gl_renderer = null;
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
    webdriver: nav.webdriver,
    screen: {w: scr.width, h: scr.height, aw: scr.availWidth, ah: scr.availHeight,
             cd: scr.colorDepth, pd: scr.pixelDepth, dpr: window.devicePixelRatio,
             ix: scr.availLeft, iy: scr.availTop},
    innerW: window.innerWidth, innerH: window.innerHeight,
    outerW: window.outerWidth, outerH: window.outerHeight,
    gl_vendor: gl_vendor, gl_renderer: gl_renderer,
    tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
    locale: Intl.DateTimeFormat().resolvedOptions().locale,
    voices: voices,
    audioRate: null
  });
})()
"""

def main():
    # kill any stale debug edge, start headless with debug port
    subprocess.run("taskkill /f /im msedge.exe >nul 2>&1", shell=True)
    time.sleep(2)
    subprocess.run(r'start "" /b "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --headless=new --disable-gpu-sandbox --remote-debugging-port=9222 --user-data-dir=C:\Tools\edgedbg --no-first-run about:blank', shell=True)
    time.sleep(6)
    ver = http_json("/json/version")
    t = http_json("/json/new?about:blank")
    ws_url = t["webSocketDebuggerUrl"]
    ws = WS(ws_url)
    ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate",
                        "params": {"expression": JS, "returnByValue": True}}))
    deadline = time.time() + 15
    result = None
    while time.time() < deadline:
        msg = json.loads(ws.recv())
        if msg.get("id") == 1:
            result = msg["result"]["result"]["value"]
            break
    open(OUT, "w").write(result)
    print("OK")

if __name__ == "__main__":
    main()