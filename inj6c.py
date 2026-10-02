import ctypes, ctypes.wintypes as wt, time, os, sys, subprocess

psapi = ctypes.windll.psapi
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
k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]

def w(x): open(r"C:\Tools\inj_log.txt","a").write(str(x)+"\n")

TARGET = sys.argv[1]
DLL = sys.argv[2]
ARGS = sys.argv[3] if len(sys.argv) > 3 else ""

w("=== enum-based injection: " + TARGET)
p = subprocess.Popen([TARGET] + ([ARGS] if ARGS else []))
time.sleep(3)
pid = p.pid
w("pid=%d" % pid)

h = k32.OpenProcess(0x1F0FFF, False, pid)
if not h:
    w("OpenProcess failed gle=%d" % k32.GetLastError()); sys.exit(1)

# enumerate remote modules
LIST_MODULES_ALL = 0x03
needed = wt.DWORD()
psapi.EnumProcessModulesEx(h, None, 0, ctypes.byref(needed), LIST_MODULES_ALL)
count = needed.value // ctypes.sizeof(wt.HMODULE)
mods = (wt.HMODULE * count)()
names = (wt.LPWSTR * count)()
if psapi.EnumProcessModulesEx(h, ctypes.byref(mods), ctypes.sizeof(mods), ctypes.byref(needed), LIST_MODULES_ALL):
    real = needed.value // ctypes.sizeof(wt.HMODULE)
    for i in range(real):
        n = ctypes.create_unicode_buffer(512)
        psapi.GetModuleFileNameExW(h, mods[i], n, 512)
        if "kernel32" in n.value.lower():
            remote_k32 = ctypes.cast(mods[i], ctypes.c_void_p).value
            w("remote kernel32 base=0x%X" % remote_k32)
else:
    w("EnumProcessModulesEx failed")
    sys.exit(1)

local_k32 = ctypes.cast(k32.GetModuleHandleW("kernel32.dll"), ctypes.c_void_p).value
local_loadlib = k32.GetProcAddress(k32.GetModuleHandleW("kernel32.dll"), b"LoadLibraryW")
w("local  kernel32 base=0x%X" % local_k32)
w("local  LoadLibraryW  =0x%X" % local_loadlib)
offset = local_loadlib - local_k32
remote_loadlib = remote_k32 + offset
w("remote LoadLibraryW  =0x%X" % remote_loadlib)

dll_path = ctypes.create_unicode_buffer(DLL)
alloc = k32.VirtualAllocEx(h, None, ctypes.sizeof(dll_path), 0x3000, 0x40)
if not alloc:
    w("VirtualAllocEx failed"); sys.exit(1)
wrote = ctypes.c_size_t()
k32.WriteProcessMemory(h, alloc, dll_path, ctypes.sizeof(dll_path), ctypes.byref(wrote))
w("wrote %d bytes" % wrote.value)

tid = wt.DWORD()
hthread = k32.CreateRemoteThread(h, None, 0, remote_loadlib, alloc, 0, ctypes.byref(tid))
if not hthread:
    w("CreateRemoteThread failed gle=%d" % k32.GetLastError()); sys.exit(1)
w("remote tid=%d waiting..." % tid.value)
k32.WaitForSingleObject(hthread, 15000)
ec = wt.DWORD()
k32.GetExitCodeThread(hthread, ctypes.byref(ec))
w("thread exit: 0x%X" % ec.value)
time.sleep(2)
try:
    print("KEY: " + open(r"C:\Tools\key_out.txt").read())
except Exception:
    try:
        print(open(r"C:\Tools\ctrl_log.txt").read())
    except Exception:
        print("no evidence file")
p.kill()