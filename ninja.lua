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
    void ninja_clear();
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

local EXTENSION_NAME = {}; do
    if ffi.os == 'Windows' then
        EXTENSION_NAME['binary'] = '.exe'
        EXTENSION_NAME['shared'] = '.dll'
        EXTENSION_NAME['static'] = '.lib'
    elseif ffi.os == 'Linux' then
        EXTENSION_NAME['binary'] = ''
        EXTENSION_NAME['shared'] = '.so'
        EXTENSION_NAME['static'] = '.a'
    else
        fatal('unsupported platform: %s', ffi.os)
    end
end

local ninja = {}; _G.ninja = ninja

ninja.targets = {}; ninja.toolchains = {}

function ninja.config(fx)
    if fx(C.ninja_config()) ~= false then C.ninja_config_apply() end
end

function ninja.build_dir(dir)
    if not dir then
        return C.ninja_var_get('builddir')
    else
        C.ninja_var_set('builddir', dir)
    end
end

local function ensure_field(t, field, default)
    local x = t[field]; if x == nil then
        x = default; t[field] = x
    end; return x
end

local function as_list(x)
    if type(x) == 'table' then return x else return { x } end
end

local function options_merge(tout, tin, ...)
    if not tin then return tout end
    for k, x in pairs(as_list(tin)) do
        if k == 'public' then
            goto continue
        elseif type(k) == 'number' then
            if type(x) == 'table' then
                options_merge(tout, x)
            else
                table.insert(tout, x)
            end
        elseif x == false then
            tout[k] = nil
        else
            tout[k] = x
        end
        ::continue::
    end
    return options_merge(tout, ...)
end

local function options_public_merge(tout, tin, ...)
    if not tin then return tout end
    if type(tin) == 'table' then
        if tin.public then
            options_merge(tout, tin)
        else
            for k, x in pairs(tin) do
                if type(k) == 'number' then
                    if type(x) == 'table' then
                        options_public_merge(tout, x)
                    end
                elseif type(k) == 'table' and x then
                    options_public_merge(tout, k)
                end
            end
        end
    end
    return options_public_merge(tout, ...)
end

local function options_to_buf(buf, t)
    for k, x in pairs(t) do
        if k == 'public' then
            goto continue
        elseif type(k) == 'number' then
            if type(x) == 'table' then
                options_to_buf(buf, x)
            else
                buf:put(x, ' ')
            end
        elseif type(x) == 'boolean' then
            if x == true then
                buf:put(k, ' ')
            end
        else
            buf:put(k, '=', x, ' ')
        end
        ::continue::
    end
    return buf
end

local function options_to_string(t)
    return options_to_buf(__buf:reset(), t):tostring()
end

-- local function symgen(prefix)
--     __buf:reset(); __buf:put(prefix); randbuf(__buf, 16); return __buf:tostring()
-- end

local function symgen(prefix)
    return prefix .. tostring(__counter_next())
end

local basic_cc_toolchain; basic_cc_toolchain = object({
    target = {
        new = function(name, type, opts)
            local target = inherits(basic_cc_toolchain.target.basic, {
                name = name, type = type, opts = opts or {},
            })
            ninja.targets[name] = target
            return target
        end,

        basic = {
            deps = function(self, xs)
                local deps = ensure_field(self.opts, 'deps', {})
                for _, x in ipairs(as_list(xs)) do table.insert(deps, x) end
                return self
            end,

            src = function(self, src)
                local srcs = ensure_field(self.opts, 'srcs', {})
                for _, s in ipairs(as_list(src)) do table.insert(srcs, s) end
                return self
            end,

            include_dir = function(self, dir)
                local dirs = ensure_field(self.opts, 'include_dirs', {})
                for _, d in ipairs(as_list(dir)) do
                    if not d:starts_with('-I') then
                        d = '-I' .. d
                    end
                    table.insert(dirs, d)
                end
                return self
            end,

            include = function(self, inc)
                local incs = ensure_field(self.opts, 'includes', {})
                for _, i in ipairs(as_list(inc)) do
                    if not i:starts_with('-include ') then
                        i = '-include ' .. i
                    end
                    table.insert(incs, i)
                end
                return self
            end,

            lib_dir = function(self, dir)
                local dirs = ensure_field(self.opts, 'lib_dirs', {})
                for _, d in ipairs(as_list(dir)) do
                    if not d:starts_with('-L') then
                        d = '-L' .. d
                    end
                    table.insert(dirs, d)
                end
                return self
            end,

            lib = function(self, lib)
                local libs = ensure_field(self.opts, 'libs', {})
                for _, l in ipairs(as_list(lib)) do
                    if not l:starts_with('-l') then
                        l = '-l' .. l
                    end
                    table.insert(libs, l)
                end
                return self
            end,

            define = function(self, def)
                local defs = ensure_field(self.opts, 'defines', {})
                for _, d in ipairs(as_list(def)) do
                    if not def:starts_with('-D') then
                        d = '-D' .. d
                    end
                    table.insert(defs, d)
                end
                return self
            end,

            c_flags = function(self, flags)
                local xs = ensure_field(self.opts, 'c_flags', {})
                for _, f in ipairs(as_list(flags)) do table.insert(xs, f) end
                return self
            end,

            cx_flags = function(self, flags)
                local xs = ensure_field(self.opts, 'cx_flags', {})
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
        }
    },
});

local gcc_toolchain; gcc_toolchain = object({
    target = {
        new = function(...)
            return extends(basic_cc_toolchain.target.new(...), gcc_toolchain.target.basic)
        end,

        basic = {
            prepare = function(self)
                local build_dir = ninja.build_dir()

                local output = path.combine(build_dir, self.name .. EXTENSION_NAME[self.type])

                local opts = self.opts

                local c_options = options_merge({
                    '-c', '-o', output,
                }, opts.c_flags, opts.cx_flags, opts.defines, opts.includes, opts.include_dirs)

                if opts.deps then
                    for _, dep in ipairs(opts.deps) do
                        local opts = dep.opts
                        options_public_merge(c_options, opts.c_flags, opts.cx_flags, opts.defines, opts.includes, opts.include_dirs)
                    end
                end

                local cxx_options = options_merge({
                    '-c', '-o', output,
                }, opts.cxx_flags, opts.cx_flags, opts.defines, opts.includes, opts.include_dirs)

                if opts.deps then
                    for _, dep in ipairs(opts.deps) do
                        local opts = dep.opts
                        options_public_merge(cxx_options, opts.cxx_flags, opts.cx_flags, opts.defines, opts.includes, opts.include_dirs)
                    end
                end

                local ld_options = options_merge({
                    '-o', output,
                }, opts.ld_flags, opts.libs, opts.lib_dirs)

                if opts.deps then
                    for _, dep in ipairs(opts.deps) do
                        local opts = dep.opts
                        options_public_merge(ld_options, opts.ld_flags, opts.libs, opts.lib_dirs)
                    end
                end
            end,
        },
    },
}); ninja.toolchains.gcc = gcc_toolchain

local cosmocc_toolchain; cosmocc_toolchain = object({
    target = {
        new = function(...)
            return extends(basic_cc_toolchain.target.new(...), cosmocc_toolchain.target.basic)
        end,

        basic = {
        },
    },
}); ninja.toolchains.cosmocc = cosmocc_toolchain

local clang_toolchain; clang_toolchain = object({
    target = {
        new = function(...)
            return extends(basic_cc_toolchain.target.new(...), clang_toolchain.target.basic)
        end,

        basic = {
        },
    },
}); ninja.toolchains.clang = clang_toolchain

local msvc_toolchain; msvc_toolchain = object({
    target = {
        new = function(...)
            return extends(basic_cc_toolchain.target.new(...), msvc_toolchain.target.basic)
        end,

        basic = {
        },
    },
}); ninja.toolchains.msvc = msvc_toolchain

function ninja.target(toolchain, name, type, opts)
    return ninja[toolchain].target.new(name, type, opts)
end

local function target_walk(target, fx)
    if target.visited then return end
    if target.opts.deps then
        for _, dep in ipairs(target.opts.deps) do target_walk(dep, fx) end
    end
    target.visited = true; fx(target)
end

function ninja.target_foreach(fx)
    -- walk all targets
    for _, target in pairs(ninja.targets) do
        target_walk(target, fx)
    end
    -- clear visited flag
    for _, target in pairs(ninja.targets) do target.visited = nil end
end
