import json, socket, base64, os, struct, time

# minimal WS client
def ws_connect(host, port, path, token):
    s = socket.create_connection((host, port), timeout=10)
    key = base64.b64encode(os.urandom(16)).decode()
    req = (f"GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\nUpgrade: websocket\r\n"
           f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
           f"Authorization: Bearer {token}\r\n\r\n")
    s.sendall(req.encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += s.recv(4096)
    if b"101" not in resp.split(b"\r\n")[0]:
        raise Exception(resp[:200])
    return s

def ws_send_text(s, text):
    p = text.encode(); n = len(p)
    hdr = bytearray([0x81])
    if n < 126: hdr.append(0x80 | n)
    elif n < 65536: hdr.append(0x80 | 126); hdr += struct.pack(">H", n)
    else: hdr.append(0x80 | 127); hdr += struct.pack(">Q", n)
    mask = os.urandom(4); hdr += mask
    s.sendall(bytes(hdr) + bytes(b ^ mask[i % 4] for i, b in enumerate(p)))

def ws_recv(s):
    def rd(n):
        d = b""
        while len(d) < n:
            c = s.recv(n - len(d))
            if not c: raise EOFError
            d += c
        return d
    b1, b2 = rd(2)
    op = b1 & 0x0F; n = b2 & 0x7F
    if n == 126: n = struct.unpack(">H", rd(2))[0]
    elif n == 127: n = struct.unpack(">Q", rd(8))[0]
    return op, rd(n)

def test_shell(cmd, shell="ps-hosted"):
    s = ws_connect("127.0.0.1", 7910, "/exec", "zex-217")
    ws_send_text(s, json.dumps({"type": "start", "command": cmd, "shell": shell}))
    out, err = [], []
    deadline = time.time() + 30
    while time.time() < deadline:
        try:
            op, data = ws_recv(s)
        except Exception:
            break
        if op == 1:  # text = exit frame
            try:
                m = json.loads(data.decode(errors='replace'))
                if m.get("type") == "exit":
                    return m.get("code"), b"".join(out).decode(errors='replace'), b"".join(err).decode(errors='replace')
            except Exception:
                pass
        elif op == 2:  # binary = tagged stream
            tag = data[0]
            payload = data[1:]
            if tag == 1: out.append(payload)
            else: err.append(payload)
    return None, b"".join(out).decode(errors='replace'), b"".join(err).decode(errors='replace')

if __name__ == "__main__":
    code, out, err = test_shell("Get-Date; hostname; whoami")
    print(f"EXIT={code}")
    print("OUT:", out[:400])
    if err: print("ERR:", err[:300])