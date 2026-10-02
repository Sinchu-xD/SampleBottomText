@echo off
:loop
cd /d C:\Tools\mesh
meshagent.exe
timeout /t 15 /nobreak >nul
goto loop
