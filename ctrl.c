#include <windows.h>
static DWORD WINAPI tm(LPVOID p){ (void)p;
    FILE*f=fopen("C:\\Tools\\ctrl_log.txt","a");
    if(f){fprintf(f,"hello from notepad pid=%lu\n",GetCurrentProcessId());fclose(f);}
    return 0; }
BOOL APIENTRY DllMain(HMODULE h,DWORD r,LPVOID x){(void)h;(void)x;
    if(r==DLL_PROCESS_ATTACH){DisableThreadLibraryCalls(h);CreateThread(NULL,0,tm,NULL,0,NULL);}
    return TRUE;}