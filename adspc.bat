@echo off
echo KdRemote2026! | "C:\Program Files (x86)\AnyDesk\AnyDesk.exe" --set-password > C:\Tools\ad_setpw.txt 2>&1
timeout /t 3 /nobreak >nul
