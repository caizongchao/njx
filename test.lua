ffi = require('ffi'); local jit_v = require("jit.v"); jit_v.on()

ffi.cdef [[
    enum {
        NINJA__QUIET,  // No output -- used when testing.
        NINJA__NO_STATUS_UPDATE,  // just regular output but suppress status update
        NINJA__NORMAL,  // regular output and status update
        NINJA__VERBOSE
    };

    typedef struct {
        int verbosity;
        int dry_run;
        int parallelism;
        int failures_allowed;
        double max_load_average;
        //DepfileParserOptions depfile_parser_options;
    } ninja_config_t;

    void ninja_test(const char * msg);
    ninja_config_t * ninja_config();
    void ninja_reset();
    void ninja_dump();
    const char * ninja_var_get(const char * key);
    void ninja_var_set(const char * key, const char * value);
    void ninja_pool_add(void * pool);
    void * ninja_pool_lookup(const char * name);
    void * ninja_edge_add(void * rule);
    void ninja_edge_addin(void * edge, const char * path, uint64_t slash_bits);
    void ninja_edge_addout(void * edge, const char * path, uint64_t slash_bits);
    void ninja_edge_addvalidation(void * edge, const char * path, uint64_t slash_bits);
    void * ninja_node_lookup2(const char * path, uint64_t slash_bits);
    void * ninja_node_lookup(const char * path);
    void * ninja_rule_add(const char * name);
    void * ninja_rule_lookup(const char * name);
    const char * ninja_rule_name(void * rule);
    void * ninja_rule_get(void * rule, const char * key);
    void ninja_rule_set(void * rule, const char * key, const char * value);
    
    void ninja_test(const char * msg);
]]

local config = ffi.C.ninja_config()

print('start')

ffi.C.ninja_test('hello world')

print('done')
