import socket, time
out = open(r"C:\Tools\egress_test.txt", "w")
try:
    s = socket.create_connection(("api.ipify.org", 80), timeout=10)
    s.sendall(b"GET / HTTP/1.1\r\nHost: api.ipify.org\r\nConnection: close\r\n\r\n")
    d = s.recv(4096)
    out.write("HTTP OK: %r\n" % d[:200])
    s.close()
except Exception as e:
    out.write("HTTP FAIL: %r\n" % e)
try:
    s = socket.create_connection(("api.ipify.org", 443), timeout=10)
    out.write("443 connect OK\n")
    s.close()
except Exception as e:
    out.write("443 FAIL: %r\n" % e)
try:
    s = socket.create_connection(("103.124.157.61", 53178), timeout=10)
    out.write("VPS 53178 OK\n")
    s.close()
except Exception as e:
    out.write("VPS 53178 FAIL: %r\n" % e)
out.close()