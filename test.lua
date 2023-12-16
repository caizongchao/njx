ffi = require('ffi')

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

    void ninja_initialize();
    ninja_config_t * ninja_config();
    const char * ninja_builddir_get();
    //void ninja_builddir_set(const char * path);
    void ninja_builddir_set(gcptr path);
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
    void ninja_build(gcptr path);
    
]]

local config = ffi.C.ninja_config()
local build_dir = ffi.string(ffi.C.ninja_builddir_get())

print('start')

print(config.dry_run, config.parallelism, build_dir)

ffi.C.ninja_build({"foo"})

print('done')
