import ctypes, time, os
try:
    ctypes.WinDLL(r"C:\Tools\ctrldll.dll")
    print("loaded ok")
except Exception as e:
    print("load fail:", e)
time.sleep(2)
print("ctrl_log exists:", os.path.exists(r"C:\Tools\ctrl_log.txt"))
if os.path.exists(r"C:\Tools\ctrl_log.txt"):
    print(open(r"C:\Tools\ctrl_log.txt").read())