import ctypes, json
u = ctypes.windll.user32
if not u.GetSystemMetrics(0):
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
w, h = u.GetSystemMetrics(0), u.GetSystemMetrics(1)
vw, vh = u.GetSystemMetrics(78), u.GetSystemMetrics(79)
open(r"C:\Tools\res.json", "w").write(json.dumps({"w": w, "h": h, "vw": vw, "vh": vh}))
print("OK")