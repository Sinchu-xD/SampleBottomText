import json, os, platform, time, tempfile, socket, traceback

OUT = r"C:\Tools\fp.json"
EDGE = r"C:\Users\admin\AppData\Local\Microsoft\Edge\User Data"
APPDIR = r"C:\Program Files (x86)\Microsoft\Edge\Application"

def rj(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}

fp = {}
fp["browser"] = "Edge"
fp["executable_path"] = os.path.join(APPDIR, "msedge.exe")
fp["user_data_path"] = EDGE

ls = rj(os.path.join(EDGE, "Local State"))
osc = ls.get("os_crypt", {})

# version: highest dir under Application matching N.N.N.N
ver = None
if os.path.isdir(APPDIR):
    vers = [d for d in os.listdir(APPDIR) if d[0].isdigit() and d.count(".") == 3]
    if vers:
        ver = sorted(vers, key=lambda s: [int(x) for x in s.split(".")])[-1]
fp["browser_version"] = ver

# profile cache
pinfo = ls.get("profile", {}).get("info_cache", {})
fp["profile_count"] = len(pinfo) if pinfo else (1 if os.path.isdir(os.path.join(EDGE, "Default")) else 0)
profiles = list(pinfo.keys()) if pinfo else ["Default"]

# extensions across profiles
ext_ids = []
for p in profiles:
    prefs = rj(os.path.join(EDGE, p, "Preferences"))
    exts = prefs.get("extensions", {}).get("settings", {})
    for eid, meta in exts.items():
        if eid not in ext_ids and meta.get("state", 1) != 0:
            ext_ids.append(eid)
fp["installed_extensions_count"] = len(ext_ids)
fp["extension_ids"] = ext_ids

# extension names
names = {}
for p in profiles:
    edir = os.path.join(EDGE, p, "Extensions")
    if not os.path.isdir(edir):
        continue
    for eid in ext_ids:
        if eid in names:
            continue
        pdir = os.path.join(edir, eid)
        if not os.path.isdir(pdir):
            continue
        for sub in sorted(os.listdir(pdir), reverse=True):
            mf = os.path.join(pdir, sub, "manifest.json")
            m = rj(mf)
            if m.get("name"):
                names[eid] = m.get("name")
                break
fp["extension_names"] = names

# main profile prefs (Default or first)
main = profiles[0] if profiles else "Default"
prefs = rj(os.path.join(EDGE, main, "Preferences"))
sec = prefs.get("credentials_enable_service")
fp["sync_enabled"] = bool(prefs.get("signin", {}).get("allowed") or pinfo.get(main, {}).get("user_name"))
fp["account_email"] = pinfo.get(main, {}).get("user_name")
fp["enterprise_managed"] = bool(
    ls.get("enterprise", {}).get("enrolled", False)
    or os.path.exists(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge_proxy.exe") is False and False
    or prefs.get("browser", {}).get("has_seen_welcome_page") is None and False
)
# check policies registry-free: Local State browser.enabled flags or adm presence
fp["enterprise_managed"] = bool(ls.get("enterprise")) or bool(pinfo.get(main, {}).get("is_managed", False)) or bool(prefs.get("edge", {}).get("managed", False))

fp["update_channel"] = "stable"
fp["hardware_acceleration"] = prefs.get("hardware_acceleration_mode", {}).get("enabled", True)
fp["metrics_enabled"] = ls.get("user_experience_metrics", {}).get("metrics_enabled", False) or ls.get("usage_stats", False)
fp["autofill_enabled"] = prefs.get("autofill", {}).get("profile_enabled", True)
fp["password_manager_enabled"] = prefs.get("credentials_enable_service", True)
fp["password_manager_on"] = prefs.get("credentials_enable_autosignin", False)
fp["safe_browsing_enabled"] = prefs.get("safebrowsing", {}).get("enabled", True)
fp["do_not_track"] = prefs.get("enable_do_not_track", False)
fp["third_party_cookies_blocked"] = prefs.get("profile", {}).get("cookie_controls_mode", 0) == 1
fp["translate_enabled"] = prefs.get("translate", {}).get("enabled", True)
fp["default_search"] = (prefs.get("default_search_provider_data", {}).get("template_url_data", {}) or {}).get("short_name")
fp["homepage"] = prefs.get("homepage")
fp["startup_urls"] = prefs.get("session", {}).get("restore_on_startup_urls", [])
fp["browser_signin"] = prefs.get("signin", {}).get("allowed", None)
fp["edge_collections"] = prefs.get("collections", {}).get("enabled", None)
fp["tracking_prevention"] = prefs.get("tracking_prevention", {}).get("level")
fp["smartscreen"] = prefs.get("smart_actions", {}).get("enabled", None)

fp["computer_name"] = socket.gethostname()
fp["windows_user"] = os.environ.get("USERNAME")
fp["os_version"] = platform.version()
fp["architecture"] = platform.machine()
fp["cpu"] = platform.processor()
try:
    import ctypes
    buf = ctypes.create_unicode_buffer(260)
    ctypes.windll.kernel32.GetSystemInfo
    fp["total_ram_gb"] = None
    class MS(ctypes.Structure):
        _fields_ = [("dwLength", ctypes.c_ulong)]*1
    ms = ctypes.create_string_buffer(64)
    ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(ms)) if False else None
except Exception:
    pass

try:
    import ctypes
    from ctypes import wintypes
    class MEMORYSTATUSEX(ctypes.Structure):
        _fields_ = [("dwLength", wintypes.DWORD), ("dwMemoryLoad", wintypes.DWORD),
                    ("ullTotalPhys", ctypes.c_uint64), ("ullAvailPhys", ctypes.c_uint64),
                    ("ullTotalPageFile", ctypes.c_uint64), ("ullAvailPageFile", ctypes.c_uint64),
                    ("ullTotalVirtual", ctypes.c_uint64), ("ullAvailVirtual", ctypes.c_uint64),
                    ("ullAvailExtendedVirtual", ctypes.c_uint64)]
    m = MEMORYSTATUSEX(); m.dwLength = ctypes.sizeof(m)
    ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
    fp["ram_total_gb"] = round(m.ullTotalPhys / 2**30, 1)
    fp["ram_load_pct"] = m.dwMemoryLoad
except Exception:
    pass

fp["last_config_update"] = int(os.path.getmtime(os.path.join(EDGE, main, "Preferences")))
fp["extraction_timestamp"] = int(time.time())
fp["extraction_complete"] = True

# os_crypt status (ABE posture)
fp["os_crypt_app_bound"] = "app_bound_encrypted_key" in osc
fp["v20_encrypted"] = True

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(fp, f, indent=1, default=str)
print("OK")