@echo off
set "VCTOOLS=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207"
set "WINSDK=C:\Program Files (x86)\Windows Kits\10"
set "SDKVER=10.0.26100.0"
set "PATH=%VCTOOLS%\bin\Hostx64\x64;%WINSDK%\bin\%SDKVER%\x64;%PATH%"
set "INCLUDE=%VCTOOLS%\include;%WINSDK%\Include\%SDKVER%\ucrt;%WINSDK%\Include\%SDKVER%\shared;%WINSDK%\Include\%SDKVER%\um;%WINSDK%\Include\%SDKVER%\winrt"
set "LIB=%VCTOOLS%\lib\x64;%WINSDK%\Lib\%SDKVER%\ucrt\x64;%WINSDK%\Lib\%SDKVER%\um\x64"
cd /d C:\Tools
cl /nologo /O1 /LD /MT /GS- /utf-8 em7c.c /Fe:edgedll.dll /link ole32.lib crypt32.lib advapi32.lib user32.lib > C:\Tools\em_build.log 2>&1
dir edgedll.dll >> C:\Tools\em_build.log 2>&1
