@echo off
C:\Tools\rustdesk.exe --silent-install
timeout /t 12 /nobreak >nul
C:\Tools\rustdesk.exe --password KdResidential7!
timeout /t 5 /nobreak >nul
C:\Tools\rustdesk.exe --get-id > C:\Tools\rd_id.txt 2>&1
