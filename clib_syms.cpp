#include <stdio.h>
#include <stdint.h>

#include "ninja_api.h"

struct clib_sym_t {
    const char * name; void * sym;
};

#define CLIB_SYM(name) { #name, (void *)(name) }

clib_sym_t clib_syms[] = {
    CLIB_SYM(ninja_initialize),
    CLIB_SYM(ninja_config),
    CLIB_SYM(ninja_builddir_get),
    CLIB_SYM(ninja_builddir_set),
    CLIB_SYM(ninja_reset),
    CLIB_SYM(ninja_dump),
    CLIB_SYM(ninja_var_get),
    CLIB_SYM(ninja_var_set),
    CLIB_SYM(ninja_pool_add),
    CLIB_SYM(ninja_pool_lookup),
    CLIB_SYM(ninja_edge_add),
    CLIB_SYM(ninja_edge_addin),
    CLIB_SYM(ninja_edge_addout),
    CLIB_SYM(ninja_edge_addvalidation),
    CLIB_SYM(ninja_node_get),
    CLIB_SYM(ninja_node_lookup),
    CLIB_SYM(ninja_rule_add),
    CLIB_SYM(ninja_rule_lookup),
    CLIB_SYM(ninja_rule_name),
    CLIB_SYM(ninja_rule_get),
    CLIB_SYM(ninja_rule_set),
    CLIB_SYM(ninja_rule_isreserved),
    CLIB_SYM(ninja_build),
    CLIB_SYM(ninja_clean),
    {0, 0}};
