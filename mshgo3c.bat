@echo off
:loop
cd /d C:\Tools\mesh
meshagent.exe connect
timeout /t 15 /nobreak >nul
goto loop
