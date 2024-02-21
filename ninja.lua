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

ninja.targets = {}
ninja.toolchains = {}

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
    return table.mapk(t, function(k)
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
    return (prefix or '') .. tostring(__counter_next())
end

ninja.action = {
    mkdir = {
        build = function(...)
            vargs_foreach(function(dir)
                fs.mkdir(dir)
            end, ...)
        end,

        clean = function(...)
            vargs_foreach(function(dir)
                fs.rmdir(dir)
            end, ...)
        end,
    },

    rmdir = {
        build = function(...)
            vargs_foreach(function(dir)
                fs.rmdir(dir)
            end, ...)
        end,

        clean = function(dir)
        end,
    },

    copy_file = {
        build = function(dst, src)
            fs.copy_file(dst, src)
        end,

        clean = function(dst)
            fs.rm(dst)
        end,
    },

    update_file = {
        build = function(dst, src)
            fs.update_file(dst, src)
        end,

        clean = function(dst)
            fs.rm(dst)
        end,
    },

    copy_dir = {
        build = function(dst, src)
            fs.copy_dir(dst, src)
        end,

        clean = function(dst)
            fs.rmdir(dst)
        end,
    },

    copy_dir_recursive = {
        build = function(dst, src)
            fs.copy_dir_recursive(dst, src)
        end,

        clean = function(dst)
            fs.rmdir(dst)
        end,
    },

    touch = {
        build = function(...)
            vargs_foreach(function(path)
                fs.touch(path)
            end, ...)
        end,

        clean = function(...)
            vargs_foreach(function(path)
                fs.rm(path)
            end, ...)
        end,
    },

    exec = {
        build = function(...)
            _G.exec(...)
        end,

        clean = function(...)
            _G.exec(...)
        end,
    },
}

local function is_action(x)
    local t = type(x); if t == 'function' or t == 'string' then
        return true
    elseif t == 'table' then
        local a = x[1]; if a == nil or type(a) == 'string' then
            return true
        end
    end
    return false
end

local function setupaction_foreach(x, fx)
    if is_action(x) then
        fx(x)
    elseif type(x) == 'table' then
        for _, a in ipairs(x) do
            setupaction_foreach(a, fx)
        end
    end
end

local function setupaction_run(x, stage)
    setupaction_foreach(x, function(action)
        local t = type(action); if t == 'function' then
            action(stage); return
        end

        local a; if t == 'string' then
            a = ninja.action[action]; if a and a[stage] then
                a[stage]()
            end
        elseif t == 'table' then
            if action[1] == nil then
                a = action; if a and a.stage then
                    a.stage()
                end
            else
                a = ninja.action[action[1]]; if a and a[stage] then
                    a[stage](unpack(action, 2))
                end
            end
        end
    end)
end

ninja.tool = {
}

local basic_toolchain; basic_toolchain = object({
    target = {
        basic = {
            new = function(self, opts)
                local t = object()

                table.iforeach(self.__mixin, function(v, i)
                    t.__mixin[i] = v
                end)

                t.opts = opts or {}

                return t
            end,

            use = function(self, tool, file_type, opts)
                local tools = ensure_field(self.opts, 'tools', {})

                local name; if type(tool) == 'string' then
                    name = tool; tool = ninja.tool[name]
                end

                local t = {
                    fx = tool, opts = opts or {}
                }

                if name then tools[name] = t end

                for _, ext in ipairs(as_list(file_type)) do
                    tools[ext] = t
                end

                return self
            end,

            setup = function(self, ...)
                local actions = ensure_field(self.opts, 'setup', {})
                vargs_foreach(function(action)
                    table.insert(actions, action)
                end, ...)
                return self
            end,
        },
    }
})

local function file_is_typeof(files, extensions)
    for _, file in ipairs(as_list(files)) do
        local x = path.extension(file)

        for _, ext in ipairs(as_list(extensions)) do
            if path.ifnmatch(x, ext) then
                return true
            end
        end
    end

    return false
end

local c_file_extensions = { '.c' }
local cxx_file_extensions = { '.cpp', '.cxx', '.cc' }

local c_option_fields = { 'c_flags', 'cx_flags', 'defines', 'includes', 'include_dirs' }
local cxx_option_fields = { 'cxx_flags', 'cx_flags', 'defines', 'includes', 'include_dirs' }
local ld_option_fields = { 'ld_flags', 'libs', 'lib_dirs' }

local function source_foreach(srcs, fx)
    for _, x in ipairs(as_list(srcs)) do
        if path.is_wildcard(x) then
            fs.foreach(x, function(f)
                fx(f)
            end)
        else
            fx(x)
        end
    end
end

local basic_cc_toolchain; basic_cc_toolchain = object({
    target = {
        new = function(name, opts)
            local target = extends(object(xtype({
                name = name, opts = table.merge({ type = 'binary' }, opts)
            }, 'target')), basic_toolchain.target.basic, basic_cc_toolchain.target.basic)

            if name ~= nil then
                ninja.targets[name] = target
            end

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

            deps = function(self, ...)
                local deps = ensure_field(self.opts, 'deps', {})
                vargs_foreach(function(x)
                    if type(x) == 'string' then
                        x = ninja.targets[x]; if x == nil then
                            fatal('target not found: %s', x)
                        end
                    end
                    table.insert(deps, x)
                end, ...)
                return self
            end,

            type = function(self, type)
                self.opts.type = type; if type == 'shared' then
                    self:ld_flags(self:make_flag('shared'))
                end
                return self
            end,

            std = function(self, ...)
                vargs_foreach(function(x)
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
                end, ...)
                return self
            end,

            src = function(self, ...)
                local srcs = ensure_field(self.opts, 'srcs', {})
                vargs_foreach(function(src)
                    table.insert(srcs, src)
                end, ...)
                return self
            end,

            include_dir = function(self, ...)
                local dirs = ensure_field(self.opts, 'include_dirs', {})
                vargs_foreach(function(dir)
                    table.merge(dirs, options_map(as_list(dir), function(x)
                        if not x:starts_with('-I') then
                            x = '-I' .. x
                        end
                        return x
                    end))
                end, ...)
                return self
            end,

            include = function(self, ...)
                local incs = ensure_field(self.opts, 'includes', {})
                vargs_foreach(function(inc)
                    table.merge(incs, options_map(as_list(inc), function(x)
                        if not x:starts_with('-include ') then
                            x = '-include ' .. x
                        end
                        return x
                    end))
                end, ...)
                return self
            end,

            lib_dir = function(self, ...)
                local dirs = ensure_field(self.opts, 'lib_dirs', {})
                vargs_foreach(function(dir)
                    table.merge(dirs, options_map(as_list(dir), function(x)
                        if not x:starts_with('-L') then
                            x = '-L' .. x
                        end
                        return x
                    end))
                end, ...)
                return self
            end,

            lib = function(self, ...)
                local libs = ensure_field(self.opts, 'libs', {})
                vargs_foreach(function(lib)
                    table.merge(libs, options_map(as_list(lib), function(x)
                        if not x:starts_with('-l') then
                            x = '-l' .. x
                        end
                        return x
                    end))
                end, ...)
                return self
            end,

            define = function(self, ...)
                local defs = ensure_field(self.opts, 'defines', {})
                vargs_foreach(function(def)
                    table.merge(defs, options_map(as_list(def), function(x)
                        if not x:starts_with('-D') then
                            x = '-D' .. x
                        end
                        return x
                    end))
                end, ...)
                return self
            end,

            c_flags = function(self, ...)
                local xs = ensure_field(self.opts, 'c_flags', {})
                vargs_foreach(function(flags)
                    table.merge(xs, as_list(flags))
                end, ...)
                return self
            end,

            cx_flags = function(self, ...)
                local xs = ensure_field(self.opts, 'cx_flags', {})
                vargs_foreach(function(flags)
                    table.merge(xs, as_list(flags))
                end, ...)
                return self
            end,

            cxx_flags = function(self, ...)
                local xs = ensure_field(self.opts, 'cxx_flags', {})
                vargs_foreach(function(flags)
                    table.merge(xs, as_list(flags))
                end, ...)
                return self
            end,

            ld_flags = function(self, ...)
                local xs = ensure_field(self.opts, 'ld_flags', {})
                vargs_foreach(function(flags)
                    table.merge(xs, as_list(flags))
                end, ...)
                return self
            end,

            ar_flags = function(self, ...)
                local xs = ensure_field(self.opts, 'ar_flags', {})
                vargs_foreach(function(flags)
                    table.merge(xs, as_list(flags))
                end, ...)
                return self
            end,

            default_libs = {},

            rule_postfix = '',

            dep_type = '',

            configured = false,

            configure = function(self)
                if self.configured then return end

                local s; local opts = self.opts

                local build_dir = path.combine(ninja.build_dir(), self.name); do
                    self.build_dir = build_dir
                end

                local output = path.combine(ninja.build_dir(), self.name .. TARGET_EXTENSION[opts.type]); do
                    self.output = output
                end

                local rules = {}

                if opts.tools then
                    for ext, tool in pairs(opts.tools) do
                        local tool_rulename = symgen(self.name .. '_tool_' .. ext); do
                            C.ninja_rule_add(tool_rulename, {
                                command = tool.fx(tool.opts),
                                description = 'BUILD $out',
                            })
                        end
                        rules[ext] = tool_rulename
                    end
                end

                local c_options = options_merge({}, options_pick(opts, unpack(c_option_fields)))

                if opts.deps then
                    for _, dep in ipairs(opts.deps) do
                        local dopts = dep.opts
                        options_public_merge(c_options, options_pick(dopts, unpack(c_option_fields)))
                    end
                end

                local cxx_options = options_merge({}, options_pick(opts, unpack(cxx_option_fields)))

                if opts.deps then
                    for _, dep in ipairs(opts.deps) do
                        local dopts = dep.opts
                        options_public_merge(cxx_options, options_pick(dopts, unpack(cxx_option_fields)))
                    end
                end

                local ld_options = options_merge({}, options_pick(opts, unpack(ld_option_fields)))

                if opts.deps then
                    for _, dep in ipairs(opts.deps) do
                        local dopts = dep.opts
                        options_public_merge(ld_options, options_pick(dopts, unpack(ld_option_fields)))
                    end
                end

                local ar_options = options_merge({}, options_pick(opts, 'ar_flags'))

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
                table.iforeach(c_file_extensions, function(ext)
                    rules[ext] = cc_rule_name
                end)

                local cxx_rule_name = symgen(self.name .. '_cxx_'); do
                    C.ninja_rule_add(cxx_rule_name, {
                        command = options_tostring(self.cxx, cxx_options),
                        depfile = '$out.d',
                        deps = dep_type,
                        description = 'CXX $out',
                    })
                end
                table.iforeach(cxx_file_extensions, function(ext)
                    rules[ext] = cxx_rule_name
                end)

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
                    local function add_src(src, xrules)
                        local rule = xrules[path.extension(src)]; if rule == nil then
                            fatal('no rule for file: %s', src)
                        end

                        local obj = path.combine(build_dir, src .. '.o'); do
                            table.insert(objs, obj)
                        end

                        C.ninja_edge_add(obj, rule, src, nil)
                    end

                    for _, src in ipairs(srcs) do
                        if type(src) == 'table' then
                            local xtarget = self:new(); for k, v in pairs(src) do
                                if type(k) == 'number' then
                                    goto continue
                                else
                                    local a = xtarget[k]; if a then
                                        if type(a) == 'function' then
                                            a(xtarget, unpack(as_list(v)))
                                        else
                                            xtarget[k] = v
                                        end
                                    else
                                        xtarget.opts[k] = v
                                    end
                                end
                                ::continue::
                            end

                            local xopts = xtarget.opts
                            local xrules = extends({}, rules)

                            if xopts.tool then
                                local n, t; do
                                    local x = type(xopts.tool); if x == 'string' then
                                        n = xopts.tool; t = ninja.tool[n]
                                    else
                                        n = symgen(); if x == 'function' then
                                            t = { fx = x, opts = {} }
                                        else
                                            t = xopts.tool
                                        end
                                    end
                                end

                                local topts = extends({}, xopts, t.opts)

                                local tool_rulename = symgen(self.name .. '_tool_' .. n); do
                                    C.ninja_rule_add(tool_rulename, {
                                        command = t.fx(topts),
                                        description = 'BUILD $out',
                                    })
                                end

                                source_foreach(src, function(f)
                                    C.ninja_edge_add(t.fx(topts, f), tool_rulename, f, nil)
                                end)
                            else
                                if file_is_typeof(src, c_file_extensions) then
                                    local cc_rule_name = symgen(self.name .. '_cc_'); do
                                        C.ninja_rule_add(cc_rule_name, {
                                            command = options_tostring(self.cc,
                                                options_merge({}, c_options, options_pick(xopts, unpack(c_option_fields)))),
                                            depfile = '$out.d',
                                            deps = dep_type,
                                            description = 'CC $out',
                                        })
                                    end
                                    table.iforeach(c_file_extensions, function(ext)
                                        xrules[ext] = cc_rule_name
                                    end)
                                end

                                if file_is_typeof(src, cxx_file_extensions) then
                                    local cxx_rule_name = symgen(self.name .. '_cxx_'); do
                                        C.ninja_rule_add(cxx_rule_name, {
                                            command = options_tostring(self.cxx,
                                                options_merge({}, cxx_options,
                                                    options_pick(xopts, unpack(cxx_option_fields)))),
                                            depfile = '$out.d',
                                            deps = dep_type,
                                            description = 'CXX $out',
                                        })
                                    end
                                    table.iforeach(cxx_file_extensions, function(ext)
                                        xrules[ext] = cxx_rule_name
                                    end)
                                end

                                source_foreach(src, function(f)
                                    add_src(f, xrules)
                                end)
                            end
                        else
                            source_foreach(src, function(f)
                                add_src(f, rules)
                            end)
                        end
                    end
                end; self.objs = objs

                if not table.isempty(objs) then
                    local deplibs = {}; table.iforeach(opts.deps, function(tdep)
                        local topts = tdep.opts
                        if (topts.type == 'shared') or (topts.type == 'static') then
                            table.insert(deplibs, tdep.output)
                        end
                    end)

                    C.ninja_edge_add(output, pick(opts.type == 'static', ar_rule_name, ld_rule_name),
                        options_merge({}, objs, deplibs), nil)

                    if opts.default ~= false then
                        C.ninja_default_add(output)
                    end
                else
                    self.output = nil
                end

                self.configured = true
            end,

            build = function(self)
                if not self.configured then
                    self:configure()
                end

                setupaction_run(self.opts.setup, 'build')

                if self.output then
                    C.ninja_build(self.output)
                end
            end,

            clean = function(self)
                fs.remove_all_in(self.build_dir)
                setupaction_run(self.opts.setup, 'clean')
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

function ninja.toolchain_of(x)
    if type(x) == 'string' then
        return ninja.toolchains[x]
    elseif x == nil then
        return ninja.toolchain
    else
        return x
    end
end

function ninja.target_of(x)
    local t = xtype(x); if t == 'string' then
        local a = ninja.targets[x]; if a == nil then
            fatal('target not found: %s', x)
        end
        return a
    elseif t == 'target' then
        return x
    elseif t == 'table' then
        local a = {}; table.iforeach(x, function(v)
            table.insert(a, ninja.target_of(v))
        end)
        return unpack(a)
    else
        fatal('invalid target: %s', x)
    end
end

function ninja.target(name, opts)
    opts = opts or {}; if not opts.toolchain then
        opts.toolchain = ninja.toolchain
    end
    return ninja.toolchain_of(opts.toolchain).target.new(name, opts)
end

local function target_walk(target, fx, ctx)
    if ctx[target] then return end
    if target.opts.deps then
        table.iforeach(target.opts.deps, function(dep)
            target_walk(dep, fx, ctx)
        end)
    end
    fx(target); ctx[target] = true
end

function ninja.targets_foreach(targets, fx)
    local t = xtype(targets); if t == 'function' then
        fx = targets; targets = ninja.targets;
    elseif t == 'string' then
        local a = ninja.targets[targets]; if a == nil then
            fatal('target not found: %s', targets)
        end
        targets = { a }
    elseif t == 'target' then
        targets = { targets }
    else
        fatal('invalid targets: %s', targets)
    end

    table.iforeach(targets, function(target)
        target_walk(target, fx, {})
    end)
end

function ninja.build(...)
    vargs_foreach(function(target)
        vargs_foreach(function(t)
            ninja.targets_foreach(t, function(x)
                x:build()
            end)
        end, ninja.target_of(target))
    end, ...)
end

function ninja.clean(...)
    vargs_foreach(function(target)
        vargs_foreach(function(t)
            ninja.targets_foreach(t, function(x)
                x:clean()
            end)
        end, ninja.target_of(target))
    end, ...)
end

function ninja.watch(dir, ...)
    local targets = {}; vargs_foreach(function(target)
        vargs_foreach(function(t)
            table.insert(targets, t)
        end, ninja.target_of(target))
    end, ...)

    fs.watch(dir, function()
        ninja.build(unpack(targets))
    end)
end

return ninja
