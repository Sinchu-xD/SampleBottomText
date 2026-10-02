@echo off
echo KdRemote2026! | "C:\Program Files (x86)\AnyDesk\AnyDesk.exe" --set-password _unattended_access > C:\Tools\ad_pw3.txt 2>&1
timeout /t 8 /nobreak >nul
findstr /C:.pwd= C:\ProgramData\AnyDesk\system.conf > C:\Tools\ad_pw3_cfg.txt
