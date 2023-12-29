---@diagnostic disable: deprecated, undefined-field
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

    const char * host_os();
    void * ninja_config_get();
    void ninja_config_apply();
    void ninja_reset();
    void ninja_clear();
    void ninja_dump();
    const char * ninja_var_get(const char * key);
    void ninja_var_set(const char * key, const char * value);
    void ninja_pool_add(const char * name, int depth);
    void ninja_rule_add(const char * name, gcptr vars);
    void ninja_edge_add(gcptr outputs, const char * rule_name, gcptr inputs, gcptr vars);
    void ninja_default_add(gcptr defaults);
    void ninja_build(gcptr targets);
    void ninja_clean();
]]

local HOST_OS = ffi.string(C.host_os())

local TARGET_EXTENSION = {}; do
    if HOST_OS == 'Windows' then
        TARGET_EXTENSION['binary'] = '.exe'
        TARGET_EXTENSION['shared'] = '.dll'
        TARGET_EXTENSION['static'] = '.lib'
    elseif HOST_OS == 'Linux' then
        TARGET_EXTENSION['binary'] = ''
        TARGET_EXTENSION['shared'] = '.so'
        TARGET_EXTENSION['static'] = '.a'
    else
        fatal('unsupported platform: %s', HOST_OS)
    end
end

local ninja = {}; _G.ninja = ninja

ninja.targets = {}; ninja.toolchains = {}

function ninja.config(fx)
    if fx(C.ninja_config()) ~= false then C.ninja_config_apply() end
end

function ninja.build_dir(dir)
    if not dir then
        return ffi.string(C.ninja_var_get('builddir'))
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

local function options_map(t, fx)
    table.mapk(t, function(k)
        if k == 'public' then return k else return fx(k) end
    end)
end

local function options_foreach(t, fx)
    if t == nil then return end

    for k, x in pairs(t) do
        if k == 'public' then goto continue end

        if type(k) == 'number' then
            if type(x) == 'table' then
                options_foreach(x, fx)
            else
                fx(x)
            end
        else
            if x ~= false then
                fx(k, x)
            end
        end

        ::continue::
    end
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

local function options_of(t, ...)
    local c = select('#', ...)
    local r = {}

    for i = 1, c do
        local x = select(i, ...)
        if x then
            local a = t[x]; if a then
                table.insert(r, a)
            end
        end
    end
end

local options = {
    merge = options_merge,
    public_merge = options_public_merge,
    to_string = options_to_string,
    of = options_of,
}; _G.options = options

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
                table.merge(deps, as_list(xs))
                return self
            end,

            src = function(self, src)
                local srcs = ensure_field(self.opts, 'srcs', {})
                table.merge(srcs, as_list(src))
                return self
            end,

            include_dir = function(self, dir)
                local dirs = ensure_field(self.opts, 'include_dirs', {})
                table.merge(dirs, options_map(as_list(dir), function(x)
                    if not x:starts_with('-I') then
                        x = '-I' .. x
                    end
                    return x
                end))
                return self
            end,

            include = function(self, inc)
                local incs = ensure_field(self.opts, 'includes', {})
                table.merge(incs, options_map(as_list(inc), function(x)
                    if not x:starts_with('-include ') then
                        x = '-include ' .. x
                    end
                    return x
                end))
                return self
            end,

            lib_dir = function(self, dir)
                local dirs = ensure_field(self.opts, 'lib_dirs', {})
                table.merge(dirs, options_map(as_list(dir), function(x)
                    if not x:starts_with('-L') then
                        x = '-L' .. x
                    end
                    return x
                end))
                return self
            end,

            lib = function(self, lib)
                local libs = ensure_field(self.opts, 'libs', {})
                table.merge(libs, options_map(as_list(lib), function(x)
                    if not x:starts_with('-l') then
                        x = '-l' .. x
                    end
                    return x
                end))
                return self
            end,

            define = function(self, def)
                local defs = ensure_field(self.opts, 'defines', {})
                table.merge(defs, options_map(as_list(def), function(x)
                    if not x:starts_with('-D') then
                        x = '-D' .. x
                    end
                    return x
                end))
                return self
            end,

            c_flags = function(self, flags)
                local xs = ensure_field(self.opts, 'c_flags', {})
                table.merge(xs, as_list(flags))
                return self
            end,

            cx_flags = function(self, flags)
                local xs = ensure_field(self.opts, 'cx_flags', {})
                table.merge(xs, as_list(flags))
                return self
            end,

            cxx_flags = function(self, flags)
                local xs = ensure_field(self.opts, 'cxx_flags', {})
                table.merge(xs, as_list(flags))
                return self
            end,

            ld_flags = function(self, flags)
                local xs = ensure_field(self.opts, 'ld_flags', {})
                table.merge(xs, as_list(flags))
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
            cc = 'gcc',
            cxx = 'g++',
            ar = 'ar',
            ld = 'g++',
            defaultlibs = {},

            prepare = function(self)
                local s

                local build_dir = path.combine(ninja.build_dir(), self.name); self.build_dir = build_dir
                local output = path.combine(build_dir, self.name .. TARGET_EXTENSION[self.type]); self.output = output

                local opts = self.opts

                local c_option_fields = { 'c_flags', 'cx_flags', 'defines', 'includes', 'include_dirs' }

                local c_options = options_merge({}, options_of(opts, unpack(c_option_fields)))

                if opts.deps then
                    for _, dep in ipairs(opts.deps) do
                        local opts = dep.opts
                        options_public_merge(c_options, options_of(opts, unpack(c_option_fields)))
                    end
                end

                local cxx_option_fields = { 'cxx_flags', 'cx_flags', 'defines', 'includes', 'include_dirs' }

                local cxx_options = options_merge({}, options_of(opts, unpack(cxx_option_fields)))

                if opts.deps then
                    for _, dep in ipairs(opts.deps) do
                        local opts = dep.opts
                        options_public_merge(cxx_options, options_of(opts, unpack(cxx_option_fields)))
                    end
                end

                local ld_option_fields = { 'ld_flags', 'libs', 'lib_dirs' }

                local ld_options = options_merge({}, options_of(opts, unpack(ld_option_fields)))

                if opts.deps then
                    for _, dep in ipairs(opts.deps) do
                        local opts = dep.opts
                        options_public_merge(ld_options, options_of(opts, unpack(ld_option_fields)))
                    end
                end

                local rules = {}

                local rule_txt_output = '-MMD -MF $out.d -c $in -o $out'

                local cc_rule_name = symgen(self.name .. '_cc_'); do
                    s = string.concat(self.cc, ' ', options_to_string(c_options), rule_txt_output)
                    C.ninja_rule_add(cc_rule_name, {
                        command = s,
                        depfile = '$out.d',
                        deps = 'gcc',
                        description = 'CC $out',
                    })
                end
                rules['.c'] = cc_rule_name

                local cxx_rule_name = symgen(self.name .. '_cxx_'); do
                    s = string.concat(self.cxx, ' ', options_to_string(cxx_options), rule_txt_output)
                    C.ninja_rule_add(cxx_rule_name, {
                        command = s,
                        depfile = '$out.d',
                        deps = 'gcc',
                        description = 'CXX $out',
                    })
                end
                rules['.cpp'] = cxx_rule_name
                rules['.cxx'] = cxx_rule_name
                rules['.cc'] = cxx_rule_name

                local ld_rule_name = symgen(self.name .. '_ld_'); do
                    s = string.concat(self.ld, pick(self.type == 'shared', ' -shared ', ' '), options_to_string(ld_options), ' $in -o $out')
                    C.ninja_rule_add(ld_rule_name, {
                        command = s,
                        description = 'LD $out',
                    })
                end

                local ar_rule_name = symgen(self.name .. '_ar_'); do
                    s = string.concat(self.ar, ' ', ' rcs $out $in')
                    C.ninja_rule_add(ar_rule_name, {
                        command = s,
                        description = 'AR $out',
                    })
                end

                local objs = {}; local srcs = as_list(opts.srcs); do
                    local function add_src(src, rules)
                        local obj = path.combine(build_dir, src .. '.o')

                        table.insert(objs, obj)

                        C.ninja_edge_add(obj, rules[path.extension(src)], src, nil)
                    end

                    for _, src in ipairs(srcs) do
                        if type(src) == 'table' then
                            local opts = {}
                            for k, v in pairs(src) do
                                if type(k) == 'number' then
                                    goto continue
                                else
                                    opts[k] = v
                                end
                                ::continue::
                            end

                            local rules = {}

                            local cc_rule_name = symgen(self.name .. '_cc_'); do
                                s = string.concat(self.cc, ' ',
                                    options_to_string(options_merge({}, c_options,
                                        options_of(opts, unpack(c_option_fields)))), rule_txt_output)
                                C.ninja_rule_add(cc_rule_name, {
                                    command = s,
                                    depfile = '$out.d',
                                    deps = 'gcc',
                                    description = 'CC $out',
                                })
                            end
                            rules['.c'] = cc_rule_name

                            local cxx_rule_name = symgen(self.name .. '_cxx_'); do
                                s = string.concat(self.cxx, ' ',
                                    options_to_string(options_merge({}, cxx_options,
                                        options_of(opts, unpack(cxx_option_fields)))), rule_txt_output)
                                C.ninja_rule_add(cxx_rule_name, {
                                    command = s,
                                    depfile = '$out.d',
                                    deps = 'gcc',
                                    description = 'CXX $out',
                                })
                            end
                            rules['.cpp'] = cxx_rule_name
                            rules['.cxx'] = cxx_rule_name
                            rules['.cc'] = cxx_rule_name

                            for _, x in ipairs(src) do
                                if path.is_wildcard(x) then
                                    fs.foreach(x, function(f)
                                        add_src(f, rules)
                                    end)
                                else
                                    add_src(x, rules)
                                end
                            end
                        else
                            if path.is_wildcard(src) then
                                fs.foreach(src, function(f)
                                    add_src(f, rules)
                                end)
                            else
                                add_src(src, rules)
                            end
                        end
                    end
                end; self.objs = objs

                local deplibs = {}; options_foreach(self.opts.deps, function(dep)
                    local tdep = ninja.targets[dep]

                    if (tdep.type == 'shared') or (tdep.type == 'static') then
                        table.insert(deplibs, tdep.output)
                    end
                end)

                local libs = table.merge({}, self.defaultlibs, deplibs)

                C.ninja_edge_add(output, pick(self.type == 'static', ar_rule_name, ld_rule_name), options_merge({}, objs, self.defaultlibs, deplibs), nil)
            end,

            build = function(self)
                C.ninja_build(self.output)
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
    return ninja.toolchains[toolchain].target.new(name, type, opts)
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
