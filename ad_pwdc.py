import subprocess, time
out = open(r"C:\Tools\ad_pwd_log.txt", "w")
def L(m): out.write(str(m) + "\n"); out.flush()

exe = r"C:\Program Files (x86)\AnyDesk\AnyDesk.exe"
L("id: %r" % subprocess.run([exe, "--get-id"], capture_output=True, text=True, timeout=30).stdout.strip())

# set password via stdin
p = subprocess.run([exe, "--set-password"], input=b"KdRemote2026!\n", capture_output=True, timeout=60)
L("set-pw rc=%s out=%r err=%r" % (p.returncode, p.stdout[:200], p.stderr[:200]))
time.sleep(3)

r = subprocess.run('cmd.exe /c findstr /C:_unattended_access C:\\ProgramData\\AnyDesk\\system.conf',
                   shell=True, capture_output=True, text=True)
L("unattended cfg: %r" % r.stdout)

# also allow unattended via service.cfg feature flags
r = subprocess.run('cmd.exe /c findstr /C:ad.security.unattended C:\\ProgramData\\AnyDesk\\system.conf',
                   shell=True, capture_output=True, text=True)
L("unattended flag: %r" % r.stdout)
L("done")