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
    ninja_config_t * ninja_config_get();
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
    if fx(C.ninja_config_get()) ~= false then C.ninja_config_apply() end
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

local function options_tobuf(buf, t)
    if type(t) ~= 'table' then
        buf:put(t, ' ')
    else
        for k, x in pairs(t) do
            if k == 'public' then
                goto continue
            elseif type(k) == 'number' then
                if type(x) == 'table' then
                    options_tobuf(buf, x)
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
    end
    return buf
end

local function options_tostring(...)
    local buf = __buf:reset(); vargs_foreach(function(x)
        options_tobuf(buf, x)
    end, ...)
    return buf:tostring()
end

local function options_pick(t, ...)
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

    return r
end

local options = {
    merge = options_merge,
    public_merge = options_public_merge,
    to_string = options_tostring,
    pick = options_pick,
}; _G.options = options

local function symgen(prefix)
    return prefix .. tostring(__counter_next())
end

local basic_cc_toolchain; basic_cc_toolchain = object({
    target = {
        new = function(name, opts)
            local target = inherits(basic_cc_toolchain.target.basic, {
                name = name, opts = table.merge({ type = 'binary' }, opts)
            })
            ninja.targets[name] = target
            return target
        end,

        basic = {
            make_flag = function(self, k, v)
                local x = self.flag_map[k]; if x == nil then
                    x = self.flag_switch .. k
                else
                    if type(x) == 'function' then
                        return x(v)
                    end
                end
                return (v == nil) and x or (x .. v)
            end,

            deps = function(self, xs)
                local deps = ensure_field(self.opts, 'deps', {})
                table.merge(deps, as_list(xs))
                return self
            end,

            type = function(self, type)
                self.opts.type = type; if type == 'shared' then
                    self:ld_flags(self:make_flag('shared'))
                end
                return self
            end,

            std = function(self, x)
                local cstd, cxxstd

                if type(x) == 'string' then
                    if x:starts_with('c++') then
                        cxxstd = x
                    else
                        cstd = x
                    end
                else
                    if x.c then
                        cstd = x.c
                    elseif x.cxx then
                        cxxstd = x.cxx
                    end
                end

                if cstd then
                    self:c_flags(self:make_flag('std', cstd))
                end

                if cxxstd then
                    self:cxx_flags(self:make_flag('std', cxxstd))
                end

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

            ar_flags = function(self, flags)
                local xs = ensure_field(self.opts, 'ar_flags', {})
                table.merge(xs, as_list(flags))
                return self
            end,

            default_libs = {},

            rule_postfix = '',

            dep_type = '',

            configured = false,

            configure = function(self)
                if self.configured then return end

                local s; local opts = self.opts

                local build_dir = path.combine(ninja.build_dir(), self.name); self.build_dir = build_dir
                
                -- local output = path.combine(build_dir, self.name .. TARGET_EXTENSION[opts.type]); self.output = output
                local output = path.combine(ninja.build_dir(), self.name .. TARGET_EXTENSION[opts.type]); self.output = output

                local c_option_fields = { 'c_flags', 'cx_flags', 'defines', 'includes', 'include_dirs' }

                local c_options = options_merge({}, options_pick(opts, unpack(c_option_fields)))

                if opts.deps then
                    for _, dep in ipairs(opts.deps) do
                        local opts = dep.opts
                        options_public_merge(c_options, options_pick(opts, unpack(c_option_fields)))
                    end
                end

                local cxx_option_fields = { 'cxx_flags', 'cx_flags', 'defines', 'includes', 'include_dirs' }

                local cxx_options = options_merge({}, options_pick(opts, unpack(cxx_option_fields)))

                if opts.deps then
                    for _, dep in ipairs(opts.deps) do
                        local opts = dep.opts
                        options_public_merge(cxx_options, options_pick(opts, unpack(cxx_option_fields)))
                    end
                end

                local ld_option_fields = { 'ld_flags', 'libs', 'lib_dirs' }

                local ld_options = options_merge({}, options_pick(opts, unpack(ld_option_fields)))

                if opts.deps then
                    for _, dep in ipairs(opts.deps) do
                        local opts = dep.opts
                        options_public_merge(ld_options, options_pick(opts, unpack(ld_option_fields)))
                    end
                end

                local ar_options = options_merge({}, options_pick(opts, 'ar_flags'))

                local rules = {}

                local rule_postfix = self.rule_postfix
                local dep_type = self.dep_type

                local cc_rule_name = symgen(self.name .. '_cc_'); do
                    C.ninja_rule_add(cc_rule_name, {
                        command = options_tostring(self.cc, c_options),
                        depfile = '$out.d',
                        deps = dep_type,
                        description = 'CC $out',
                    })
                end
                rules['.c'] = cc_rule_name

                local cxx_rule_name = symgen(self.name .. '_cxx_'); do
                    C.ninja_rule_add(cxx_rule_name, {
                        command = options_tostring(self.cxx, cxx_options),
                        depfile = '$out.d',
                        deps = dep_type,
                        description = 'CXX $out',
                    })
                end
                rules['.cpp'] = cxx_rule_name
                rules['.cxx'] = cxx_rule_name
                rules['.cc'] = cxx_rule_name

                local ld_rule_name = symgen(self.name .. '_ld_'); do
                    C.ninja_rule_add(ld_rule_name, {
                        command = options_tostring(self.ld, ld_options, self.default_libs),
                        description = 'LD $out',
                    })
                end

                local ar_rule_name = symgen(self.name .. '_ar_'); do
                    C.ninja_rule_add(ar_rule_name, {
                        command = options_tostring(self.ar, ar_options),
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
                                C.ninja_rule_add(cc_rule_name, {
                                    command = options_tostring(self.cc, options_merge({}, c_options, options_pick(opts, unpack(c_option_fields)))),
                                    depfile = '$out.d',
                                    deps = dep_type,
                                    description = 'CC $out',
                                })
                            end
                            rules['.c'] = cc_rule_name

                            local cxx_rule_name = symgen(self.name .. '_cxx_'); do
                                C.ninja_rule_add(cxx_rule_name, {
                                    command = options_tostring(self.cxx, options_merge({}, cxx_options, options_pick(opts, unpack(cxx_option_fields)))),
                                    depfile = '$out.d',
                                    deps = dep_type,
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

                local deplibs = {}; options_foreach(opts.deps, function(dep)
                    local tdep = ninja.targets[dep]

                    if (tdep.type == 'shared') or (tdep.type == 'static') then
                        table.insert(deplibs, tdep.output)
                    end
                end)

                C.ninja_edge_add(output, pick(opts.type == 'static', ar_rule_name, ld_rule_name),
                    options_merge({}, objs, deplibs), nil)

                if opts.default ~= false then
                    C.ninja_default_add(output)
                end

                self.configured = true
            end,

            build = function(self)
                if not self.configured then
                    self:configure()
                end
                if self.output then
                    C.ninja_build(self.output)
                end
            end,
        }
    },
});

local gcc_toolchain; gcc_toolchain = object({
    target = {
        new = function(...)
            local t = extends(basic_cc_toolchain.target.new(...), gcc_toolchain.target.basic); do
                t:cx_flags('-MMD -MF $out.d -o $out -c $in')
                t:ld_flags('$in -o $out')
                t:ar_flags('rcs $out $in')
            end
            return t
        end,

        basic = {
            cc = 'gcc',
            cxx = 'g++',
            ar = 'ar',
            ld = 'g++',

            dep_type = 'gcc',

            flag_switch = '-',

            flag_map = {
                std = '-std=',
                include_dir = '-I',
                include = '-include ',
                lib_dir = '-L',
                lib = '-l',
                shared = '-shared',
            },
        },
    },
}); ninja.toolchains.gcc = gcc_toolchain

local cosmocc_toolchain; cosmocc_toolchain = object({
    target = {
        new = function(...)
            return extends(gcc_toolchain.target.new(...), cosmocc_toolchain.target.basic)
        end,

        basic = {
            cc = 'cosmocc',
            cxx = 'cosmoc++',
            ar = 'cosmoar',
            ld = 'cosmoc++',
        },
    },
}); ninja.toolchains.cosmocc = cosmocc_toolchain

local clang_toolchain; clang_toolchain = object({
    target = {
        new = function(...)
            return extends(gcc_toolchain.target.new(...), clang_toolchain.target.basic)
        end,

        basic = {
            cc = 'clang',
            cxx = 'clang++',
            ar = 'llvm-ar',
            ld = 'clang++',
        },
    },
}); ninja.toolchains.clang = clang_toolchain

local msvc_toolchain; msvc_toolchain = object({
    target = {
        new = function(...)
            local t = extends(basic_cc_toolchain.target.new(...), msvc_toolchain.target.basic); do
                t:cx_flags('/showIncludes /nologo /c /Fo$out /Fd$out.pdb /TP $in')
                t:ld_flags('$in /OUT:$out')
                t:ar_flags('/OUT:$out $in')
            end
            return t
        end,

        basic = {
            cc = 'cl',
            cxx = 'cl',
            ar = 'lib',
            ld = 'link',

            dep_type = 'msvc',

            default_libs = { 'kernel32.lib' },

            flag_switch = '/',

            flag_map = {
                std = '/std:',
                include_dir = '/I',
                include = '/FI',
                lib_dir = '/LIBPATH:',
                lib = '',
                shared = '/DLL',
            },
        },
    },
}); ninja.toolchains.msvc = msvc_toolchain

if HOST_OS == 'Windows' then
    ninja.toolchain = 'msvc'
else
    ninja.toolchain = 'gcc'
end

local function toolchain_of(x)
    if type(x) == 'string' then
        return ninja.toolchains[x]
    elseif x == nil then
        return ninja.toolchain
    else
        return x
    end
end; ninja.toolchain_of = toolchain_of

function ninja.target(name, opts)
    opts = opts or {}; if not opts.toolchain then
        opts.toolchain = ninja.toolchain
    end
    return ninja.toolchain_of(opts.toolchain).target.new(name, opts)
end

local function target_walk(target, fx, ctx)
    if ctx[target] then return end
    if target.opts.deps then
        options_foreach(target.opts.deps, function(dep)
            target_walk(dep, fx, ctx)
        end)
    end
    ctx[target] = true; fx(target)
end

function ninja.targets_foreach(targets, fx)
    if type(targets) == 'function' then
        fx = targets; targets = ninja.targets
    end
    options_foreach(targets, function(target)
        target_walk(target, fx, {})
    end)
end

function ninja.build(targets, opts)
    local configure = opts and opts.configure

    if targets == nil then
        targets = ninja.targets
    end
    
    ninja.targets_foreach(targets, function(target)
        if configure then
            target:configure()
        end
        target:build()
    end)
end

function ninja.watch(dir, targets, opts)
    fs.watch(dir, function ()
        ninja.build(targets, opts)
    end)
end

return ninja