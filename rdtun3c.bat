@echo off
:loop
C:\Windows\System32\OpenSSH\ssh.exe -N -L 21115:127.0.0.1:21115 -L 21116:127.0.0.1:21116 -L 21117:127.0.0.1:21117 -L 21119:127.0.0.1:21119 -L 44330:127.0.0.1:44330 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -i C:\Tools\rdtunnel.key -p 52976 root@103.124.157.61
timeout /t 10 /nobreak >nul
goto loop
