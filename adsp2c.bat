@echo off
echo password123 | "C:\Program Files (x86)\AnyDesk\AnyDesk.exe" --set-password > C:\Tools\ad_pw2.txt 2>&1
timeout /t 10 /nobreak >nul
findstr /C:unattended_access C:\ProgramData\AnyDesk\system.conf >> C:\Tools\ad_pw2.txt
findstr /C:full_access.pwd C:\ProgramData\AnyDesk\system.conf >> C:\Tools\ad_pw2.txt
