#include <stdio.h>
#include <stdint.h>

#include "ljxx.h"

extern lua_State * __L;

struct clib_sym_t {
    const char * name; void * sym;
};

#define CLIB_SYM(name) { #name, (void *)(name) }

int reftable_ref(lua_table t, lua_gcptr x) {
    printf("reftable\n");
    __L->top->u64 = ((uint64_t)t.value) | (((uint64_t)LJ_TTAB) << 47); incr_top(__L);
    __L->top->u64 = x.tvalue().value.u64; incr_top(__L);
    int r = luaL_ref(__L, -2);
    lua_pop(__L, 2);
    return r;
}

void reftable_unref(lua_table t, int r) {
    __L->top->u64 = ((uint64_t)t.value) | (((uint64_t)LJ_TTAB) << 47); incr_top(__L);
    luaL_unref(__L, -1, r);
    lua_pop(__L, 1);
}

extern "C" {
extern void ninja_test();
extern void ninja_config_get();
extern void ninja_config_apply();
extern void ninja_reset();
extern void ninja_dump();
extern void ninja_var_get();
extern void ninja_var_set();
extern void ninja_pool_add();
extern void ninja_edge_add();
extern void ninja_rule_add();
extern void ninja_default_add();
extern void ninja_build();
extern void ninja_clean();
}

static clib_sym_t __clib_syms[] = {
    CLIB_SYM(reftable_ref),
    CLIB_SYM(reftable_unref),
    CLIB_SYM(ninja_config_get),
    CLIB_SYM(ninja_config_apply),
    CLIB_SYM(ninja_reset),
    CLIB_SYM(ninja_dump),
    CLIB_SYM(ninja_var_get),
    CLIB_SYM(ninja_var_set),
    CLIB_SYM(ninja_pool_add),
    CLIB_SYM(ninja_edge_add),
    CLIB_SYM(ninja_rule_add),
    CLIB_SYM(ninja_default_add),
    CLIB_SYM(ninja_build),
    CLIB_SYM(ninja_clean),
    {0, 0}};

extern "C" {
    extern clib_sym_t * clib_syms;
}

__attribute__((constructor)) static void clib_init() {
    printf("clib_syms init\n");
    clib_syms = __clib_syms;
}
