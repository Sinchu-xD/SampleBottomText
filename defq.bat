@echo off
wevtutil qe "Microsoft-Windows-Windows Defender/Operational" /c:8 /rd:true /f:text > C:\Tools