#include <stdio.h>
#include <stdint.h>

struct clib_sym_t {
    const char * name; void * sym;
};

#define CLIB_SYM(name) { #name, (void *)(name) }

extern "C" {
extern void ninja_test();

extern void ninja_config();
extern void ninja_reset();
extern void ninja_dump();
extern void ninja_var_get();
extern void ninja_var_set();
extern void ninja_pool_add();
extern void ninja_pool_lookup();
extern void ninja_edge_add();
extern void ninja_edge_addin();
extern void ninja_edge_addout();
extern void ninja_edge_addvalidation();
extern void ninja_node_lookup2();
extern void ninja_node_lookup();
extern void ninja_rule_add();
extern void ninja_rule_lookup();
extern void ninja_rule_name();
extern void ninja_rule_get();
extern void ninja_rule_set();
extern void ninja_build();
extern void ninja_clean();
}

clib_sym_t clib_syms[] = {
    CLIB_SYM(ninja_test),
    CLIB_SYM(ninja_config),
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
    CLIB_SYM(ninja_node_lookup2),
    CLIB_SYM(ninja_node_lookup),
    CLIB_SYM(ninja_rule_add),
    CLIB_SYM(ninja_rule_lookup),
    CLIB_SYM(ninja_rule_name),
    CLIB_SYM(ninja_rule_get),
    CLIB_SYM(ninja_rule_set),
    CLIB_SYM(ninja_build),
    CLIB_SYM(ninja_clean),
    {0, 0}};
