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

    void * ninja_config_get();
    void ninja_config_apply();
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

ninja.targets = {}
ninja.toolchains = {}

function ninja.config(fx)
    if fx(C.ninja_config()) ~= false then C.ninja_config_apply() end
end

local function ensure_field(t, field, default)
    local x = t[field]; if x == nil then
        x = default; t[field] = x
    end; return x
end

local function as_list(x)
    if type(x) == 'table' then return x else return { x } end
end

local basic_cc_toolchain; basic_cc_toolchain = object({
    target = {
        new = function (name, type, opts)
            local target = extends(basic_cc_toolchain, {
                name = name, type = type, opts = opts or {},
            })
            ninja.targets[name] = target
            return target
        end
    },

    src = function(self, src)
        local srcs = ensure_field(self.opts, 'srcs', {})
        for _, s in ipairs(as_list(src)) do table.insert(srcs, s) end
        return self
    end,

    include_dir = function(self, dir)
        local dirs = ensure_field(self.opts, 'include_dirs', {})
        for _, d in ipairs(as_list(dir)) do table.insert(dirs, d) end
        return self
    end,

    include = function(self, inc)
        local incs = ensure_field(self.opts, 'includes', {})
        for _, i in ipairs(as_list(inc)) do table.insert(incs, i) end
        return self
    end,

    lib_dir = function(self, dir)
        local dirs = ensure_field(self.opts, 'lib_dirs', {})
        for _, d in ipairs(as_list(dir)) do table.insert(dirs, d) end
        return self
    end,

    lib = function(self, lib)
        local libs = ensure_field(self.opts, 'libs', {})
        for _, l in ipairs(as_list(lib)) do table.insert(libs, l) end
        return self
    end,

    define = function(self, def)
        local defs = ensure_field(self.opts, 'defines', {})
        for _, d in ipairs(as_list(def)) do table.insert(defs, d) end
        return self
    end,

    c_flags = function(self, flags)
        local xs = ensure_field(self.opts, 'c_flags', {})
        for _, f in ipairs(as_list(flags)) do table.insert(xs, f) end
        return self
    end,

    cc_flags = function(self, flags)
        local xs = ensure_field(self.opts, 'cc_flags', {})
        for _, f in ipairs(as_list(flags)) do table.insert(xs, f) end
        return self
    end,

    cxx_flags = function(self, flags)
        local xs = ensure_field(self.opts, 'cxx_flags', {})
        for _, f in ipairs(as_list(flags)) do table.insert(xs, f) end
        return self
    end,

    ld_flags = function(self, flags)
        local xs = ensure_field(self.opts, 'ld_flags', {})
        for _, f in ipairs(as_list(flags)) do table.insert(xs, f) end
        return self
    end,
});

local toolchain_cosmocc = {
}

function ninja.target(name, type, opts)
    local target = extends(basic_target, {
        name = name, type = type, opts = opts or {},
    })

    ninja.targets[name] = target

    return target
end
