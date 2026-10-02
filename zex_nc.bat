@echo off
cd /d C:\Windows\Temp\ziti
set ZEX_TOKEN=zex-217
set ASPNETCORE_URLS=http://127.0.0.1:7910
zex-server.exe > C:\Tools\zex_n.log 2>&1
