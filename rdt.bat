@echo off
C:\Windows\System32\OpenSSH\ssh.exe -N -R 21118:127.0.0.1:21118 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -i C:\Tools\rdtunnel.key -p 52976 root@103.124.157.61
