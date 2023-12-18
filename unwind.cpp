#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

extern "C" {
int lj_err_unwind_dwarf(int version, int actions, uint64_t uexclass, void * uex, void * ctx) {
    printf("unwind disabled\n"); exit(-1); return 0;
}
}