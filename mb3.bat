@echo off
set LOG=C:\Tools\cabe\manual_build.log
echo === MANUAL BUILD START === > %LOG%

set "VCTOOLS=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207"
set "WINSDK=C:\Program Files (x86)\Windows Kits\10"
set "SDKVER=10.0.26100.0"

set "PATH=%VCTOOLS%\bin\Hostx64\x64;%WINSDK%\bin\%SDKVER%\x64;%PATH%"
set "INCLUDE=%VCTOOLS%\include;%WINSDK%\Include\%SDKVER%\ucrt;%WINSDK%\Include\%SDKVER%\shared;%WINSDK%\Include\%SDKVER%\um;%WINSDK%\Include\%SDKVER%\winrt;%WINSDK%\Include\%SDKVER%\cppwinrt"
set "LIB=%VCTOOLS%\lib\x64;%WINSDK%\Lib\%SDKVER%\ucrt\x64;%WINSDK%\Lib\%SDKVER%\um\x64"

echo --- cl version --- >> %LOG%
cl 2>&1 | findstr Microsoft >> %LOG%
echo --- sdk dirs --- >> %LOG%
dir "%WINSDK%\Include\%SDKVER%" /b >> %LOG% 2>&1

cd /d C:\Tools\cabe
echo --- running make.bat --- >> %LOG%
call make2.bat >> %LOG% 2>&1
echo === MAKE EXIT %ERRORLEVEL% === >> %LOG%
echo --- build dir --- >> %LOG%
dir build >> %LOG% 2>&1
