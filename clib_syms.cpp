#include <stdio.h>
#include <stdint.h>

#include <libc/nt/runtime.h>
#include <libc/nt/dll.h>
#include <libc/nt/messagebox.h>

#define _t(x) ((const char16_t *)(u ## x))

typedef __attribute__((__ms_abi__)) int (* PMessageBoxA)(int64_t hWnd, const char *lpText, const char *lpCaption, uint32_t mbType);

static int64_t hmod_user32 = GetModuleHandleW(_t("user32"));

static PMessageBoxA __imp_MessageBoxA = (PMessageBoxA)GetProcAddress(hmod_user32, "MessageBoxA");

int MessageBoxA(int64_t hWnd, const char *lpText, const char *lpCaption, uint32_t mbType) {
    return __imp_MessageBoxA(hWnd, lpText, lpCaption, mbType);
}

void foo() {
    printf("%p, %p\n", __imp_MessageBoxA, hmod_user32);

    // printf("%p, %d\n", hmod_user32, GetLastError());

    // PMessageBoxA MessageBoxA = (PMessageBoxA)GetProcAddress(hmod_user32, "MessageBoxA");

    // printf("%p, %p, %p\n", LoadLibrary, hmod_user32, MessageBox);
    MessageBoxA(0, "hello world", "hello", 0);
    
    // std::u16string s = u"hello world";


    MessageBox(0, _t("aaaa"), _t("bbbbb"), 0);
}

struct clib_sym_t {
  const char * name; void *sym;
};

#define CLIB_SYM(name) {#name, (void *)(&name)}

clib_sym_t clib_syms[] = {
    CLIB_SYM(printf),
    CLIB_SYM(foo),
    CLIB_SYM(MessageBoxA),
    {0, 0}
};
