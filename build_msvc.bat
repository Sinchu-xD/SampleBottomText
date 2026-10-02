@echo off
set LOG=C:\Tools\cabe\msvc_build.log
echo === BUILD START %DATE% %TIME% === > %LOG%
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >> %LOG% 2>&1
echo === VCVARS EXIT %ERRORLEVEL% === >> %LOG%
cd /d C:\Tools\cabe
dir >> %LOG% 2>&1
call make.bat >> %LOG% 2>&1
echo === MAKE EXIT %ERRORLEVEL% === >> %LOG%
dir build >> %LOG% 2>&1
