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

    void * ninja_config();
    void ninja_reset();
    void ninja_dump();
    const char * ninja_var_get(const char * key);
    void ninja_var_set(const char * key, const char * value);
    void ninja_pool_add(const char * name, int depth);
    void * ninja_rule_add(const char * name, gcptr vars);
    void ninja_edge_add(gcptr outputs, const char * rule_name, gcptr inputs, gcptr vars);
    void ninja_default_add(gcptr defaults);
    void ninja_build(gcptr targets);
    void ninja_clean();
]]

local ninja = {}; _G.ninja = ninja



