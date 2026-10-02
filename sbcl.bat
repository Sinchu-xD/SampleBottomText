@echo off
:loop
python C:\Tools\sbc.py
timeout /t 10 /nobreak >nul
goto loop
