#pragma once

#ifdef __cplusplus
extern "C" {
#endif

struct lua_gcobj;

// extern void * ninja_state;
void ninja_initialize();
void * ninja_config();
const char * ninja_builddir_get();
void ninja_builddir_set(const char * path);
void ninja_reset(void * state);
void ninja_dump(void * state);
const char * ninja_var_get(void * state, const char * key);
void ninja_var_set(void * state, const char * key, const char * value);
void ninja_pool_add(void * state, void * pool);
void * ninja_pool_lookup(void * state, const char * name);
void * ninja_edge_add(void * state, void * rule);
void ninja_edge_addin(void * state, void * edge, const char * path, uint64_t slash_bits);
void ninja_edge_addout(void * state, void * edge, const char * path, uint64_t slash_bits);
void ninja_edge_addvalidation(void * state, void * edge, const char * path, uint64_t slash_bits);
void * ninja_node_get(void * state, const char * path, uint64_t slash_bits);
void * ninja_node_lookup(void * state, const char * path);
void * ninja_rule_add(void * state, const char * name);
void * ninja_rule_lookup(void * state, const char * name);
const char * ninja_rule_name(void * rule);
void * ninja_rule_get(void * rule, const char * key);
void ninja_rule_set(void * rule, const char * key, const char * value);
bool ninja_rule_isreserved(void * rule, const char * key);
void * ninja_build(void *);
void ninja_clean(void *);

#ifdef __cplusplus
}
#endif
