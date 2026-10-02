@echo off
set LOG2=C:\Tools\cabe\probe.log
echo START > %LOG2%
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >> %LOG2% 2>&1
echo VCVARS_DONE %ERRORLEVEL% >> %LOG2%
echo SDK: >> %LOG2%
dir "C:\Program Files (x86)\Windows Kits\10\Include" /b >> %LOG2% 2>&1
echo MSVC: >> %LOG2%
dir "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC" /b >> %LOG2% 2>&1
