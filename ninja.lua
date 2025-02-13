---@diagnostic disable: deprecated, undefined-field

local as_list = _G['as_list']

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
    void reload();
    const char * build_script();
    bool is_build_script(const char * x);

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
    void ninja_exit_on_error(int b);
    int ninja_build(gcptr targets);
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
    TARGET_EXTENSION['phony'] = ''
end

local TARGET_DEFAULT_TYPE = 'phony'

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

local function public(t)
    return table.tag(t, 'public')
end; _G.public = public

local function private(t)
    return table.tag(t, 'private')
end; _G.private = private

local function implicit(t)
    return table.tag(t, 'implicit')
end; _G.implicit = implicit

local function files_in(t)
    local r, c = {}, #t; if c > 1 then
        local dir = t[1]; for i = 2, c do
            table.insert(r, path.combine(dir, t[i]))
        end
    end
    for k, v in pairs(t) do
        if type(k) ~= 'number' then
            r[k] = v
        end
    end
    return r
end; _G.files_in = files_in

local function options_foreach(t, fx)
    for k, x in pairs(as_list(t)) do
        if type(k) == 'number' then
            if type(x) == 'table' then
                options_foreach(x, fx)
            else
                fx(nil, x)
            end
        else
            if type(x) == 'boolean' then
                if x then
                    fx(nil, k)
                end
            else
                fx(k, x)
            end
        end
    end
    return t
end

local function options_map(t, fx)
    local r = {}; options_foreach(t, function(k, x)
        k, x = fx(k, x); if k == nil then
            table.insert(r, x)
        elseif x == nil then
            table.insert(r, k)
        else
            r[k] = x
        end
    end)
    return r
end

local function options_merge(tout, ...)
    vargs_foreach(function(tin)
        options_foreach(tin, function(k, x)
            if k == nil then
                table.insert(tout, x)
            elseif x == nil then
                table.insert(tout, k)
            else
                tout[k] = x
            end
        end)
    end, ...)
    return tout
end

local function options_public_merge(tout, ...)
    vargs_foreach(function(tin)
        if type(tin) == 'table' then
            if xtype(tin) == 'public' then
                options_merge(tout, tin)
            else
                for k, x in pairs(tin) do
                    if type(k) == 'number' then
                        options_public_merge(tout, x)
                    elseif type(x) == 'boolean' and x then
                        options_public_merge(tout, k)
                    end
                end
            end
        end
    end, ...)
    return tout
end

local function options_tobuf(buf, t)
    options_foreach(t, function(k, x)
        if k == nil then
            buf:put(x, x == '' and '' or ' ')
        elseif x == nil then
            buf:put(k, k == '' and '' or ' ')
        else
            buf:put(k, '=', x, ' ')
        end
    end)
    return buf
end

local function options_tostring(...)
    local buf = __buf:reset()
    vargs_foreach(function(x)
        options_tobuf(buf, x)
    end, ...)
    return buf:tostring()
end; _G.options_tostring = options_tostring

local function options_pick(t, ...)
    local r, c = {}, select('#', ...)
    for i = 1, c do
        local x = select(i, ...); if x then
            local a = t[x]; if a then
                table.insert(r, a)
            end
        end
    end
    return r
end

local function option_from_kv(k, v)
    return (k == nil) and v or (k .. '=' .. v)
end

local function option_isflag(k)
    return string.starts_with(k, '-') or string.starts_with(k, '/')
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

local DEFAULT_CCACHE = 'sccache'
local NO_CCACHE = ''; _G.NO_CCACHE = NO_CCACHE

ninja.ccache = NO_CCACHE

local function ccache()
    return ninja.ccache or DEFAULT_CCACHE
end

local basic_toolchain; basic_toolchain = object({
    target = {
        basic = {
            new = function(self, opts)
                local t = xtype(object(), 'target')

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
local cxx_file_extensions = { '.cpp', '.cxx', '.cc', '.cu' }
local asm_file_extensions = { '.s', '.S', '.asm' }

local c_option_fields = { 'c_flags', 'cx_flags', 'defines', 'includes', 'include_dirs' }
local cxx_option_fields = { 'cxx_flags', 'cx_flags', 'defines', 'includes', 'include_dirs' }
local ld_option_fields = { 'ld_flags', 'libs', 'lib_dirs' }

local function table_is_option(t)
    for k, _ in pairs(t) do
        if type(k) ~= 'number' then
            return true
        end
    end
end

local function table_as_option(t)
    return table_is_option(t) and t or {}
end

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
                name = name, opts = table.merge({ type = TARGET_DEFAULT_TYPE }, opts)
            }, 'target')), basic_cc_toolchain.target.basic, basic_toolchain.target.basic)

            if name ~= nil then
                ninja.targets[name] = target
            end

            return target
        end,

        basic = {
            make_flag = function(self, k, v)
                if k == nil and v ~= nil then
                    k, v = v, k
                end

                -- if string.starts_with(k, self.flag_switch) then
                if option_isflag(k) then
                    return (v == nil) and k or (k .. v)
                else
                    local x = self.flag_map[k]; if x == nil then
                        if v ~= nil then
                            return v
                        else
                            x = self.flag_switch .. k
                        end
                    end

                    if type(x) == 'function' then
                        return x(v)
                    else
                        return (v == nil) and x or (x .. v)
                    end
                end
            end,

            deps = function(self, ...)
                local deps = ensure_field(self.opts, 'deps', {})
                vargs_foreach(function(x)
                    table.insert(deps, x)
                end, ...)
                return self
            end,

            type = function(self, type, flags)
                self.opts.type = type; if type == 'shared' then
                    self:ld_flags(self:make_flag(flags or 'shared'))
                end
                return self
            end,

            extension = function(self, ext)
                self.opts.extension = ext; return self
            end,

            cxx_pch = function(self, pch_header)
                self.opts.pch_header = pch_header; return self
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
                    table.insert(dirs, dir)
                end, ...)
                return self
            end,

            include = function(self, ...)
                local incs = ensure_field(self.opts, 'includes', {})
                vargs_foreach(function(inc)
                    table.insert(incs, inc)
                end, ...)
                return self
            end,

            lib_dir = function(self, ...)
                local dirs = ensure_field(self.opts, 'lib_dirs', {})
                vargs_foreach(function(dir)
                    table.insert(dirs, dir)
                end, ...)
                return self
            end,

            lib = function(self, ...)
                local libs = ensure_field(self.opts, 'libs', {})
                vargs_foreach(function(lib)
                    table.insert(libs, lib)
                end, ...)
                return self
            end,

            debug = function(self, b)
                if b then
                    self:cx_flags(self:make_flag('debug_cc'))
                    self:ld_flags(self:make_flag('debug_ld'))
                end
                return self
            end,

            define = function(self, ...)
                local defs = ensure_field(self.opts, 'defines', {})
                vargs_foreach(function(def)
                    table.insert(defs, def)
                end, ...)
                return self
            end,

            c_flags = function(self, ...)
                local xs = ensure_field(self.opts, 'c_flags', {})
                vargs_foreach(function(flags)
                    table.insert(xs, flags)
                end, ...)
                return self
            end,

            cx_flags = function(self, ...)
                local xs = ensure_field(self.opts, 'cx_flags', {})
                vargs_foreach(function(flags)
                    table.insert(xs, flags)
                end, ...)
                return self
            end,

            cxx_flags = function(self, ...)
                local xs = ensure_field(self.opts, 'cxx_flags', {})
                vargs_foreach(function(flags)
                    table.insert(xs, flags)
                end, ...)
                return self
            end,

            as_flags = function(self, ...)
                local xs = ensure_field(self.opts, 'as_flags', {})
                vargs_foreach(function(flags)
                    table.insert(xs, flags)
                end, ...)
                return self
            end,

            ld_flags = function(self, ...)
                local xs = ensure_field(self.opts, 'ld_flags', {})
                vargs_foreach(function(flags)
                    table.insert(xs, flags)
                end, ...)
                return self
            end,

            ar_flags = function(self, ...)
                local xs = ensure_field(self.opts, 'ar_flags', {})
                vargs_foreach(function(flags)
                    table.insert(xs, flags)
                end, ...)
                return self
            end,

            after_build = function(self, ...)
                local fxs = ensure_field(self, 'after_build_actions', {})
                vargs_foreach(function(fx)
                    table.merge(fxs, as_list(fx))
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

                if not self.name then self.name = symgen('dummy_target_') end
                if not opts.type then opts.type = TARGET_DEFAULT_TYPE end

                local build_dir = path.combine(ninja.build_dir(), self.name); do
                    self.build_dir = build_dir
                end

                local output; if opts.type == 'phony' then
                    output = symgen(self.name .. '_phony_')
                else
                    output = path.combine(ninja.build_dir(), self.name .. (opts.extension or TARGET_EXTENSION[opts.type]))
                end
                self.output = output

                local defines, include_dirs, include, lib_dirs, libs = {}, {}, {}, {}, {}
                local c_flags, cx_flags, cxx_flags, as_flags, ld_flags, ar_flags = {}, {}, {}, {}, {}, {}

                ninja.deps_foreach(self, function(dep)
                    local mergefx = (dep == self) and options_merge or options_public_merge

                    mergefx(defines, dep.opts.defines)
                    mergefx(include_dirs, dep.opts.include_dirs)
                    mergefx(include, dep.opts.includes)
                    mergefx(lib_dirs, dep.opts.lib_dirs)
                    mergefx(libs, dep.opts.libs)
                    mergefx(c_flags, dep.opts.c_flags)
                    mergefx(cx_flags, dep.opts.cx_flags)
                    mergefx(cxx_flags, dep.opts.cxx_flags)
                    mergefx(as_flags, dep.opts.as_flags)
                    mergefx(ld_flags, dep.opts.ld_flags)
                    mergefx(ar_flags, dep.opts.ar_flags)
                end)

                local srcs = {}; ninja.deps_foreach(self, function(dep)
                    local dsrcs = dep.opts.srcs

                    if (dsrcs == nil) or ((dep ~= self) and (xtype(dsrcs) ~= 'public')) then
                        goto skip
                    end

                    for _, src in ipairs(dsrcs) do
                        table.insert(srcs, src)
                    end

                    ::skip::
                end)

                local defines_options = options_map(defines, function(k, v)
                    return self:make_flag('define', option_from_kv(k, v))
                end)

                local include_dirs_options = options_map(include_dirs, function(k, v)
                    return self:make_flag('include_dir', option_from_kv(k, v))
                end)

                local include_options = options_map(include, function(k, v)
                    return self:make_flag('include', option_from_kv(k, v))
                end)

                local lib_dirs_options = options_map(lib_dirs, function(k, v)
                    return self:make_flag('lib_dir', option_from_kv(k, v))
                end)

                local libs_options = options_map(libs, function(k, v)
                    return self:make_flag('lib', option_from_kv(k, v))
                end)

                local cx_options = options_merge({}, options_map(cx_flags, function(k, v)
                    return self:make_flag(k, v)
                end), defines_options, include_dirs_options, include_options)

                local c_options = options_merge({}, cx_options, options_map(c_flags, function(k, v)
                    return self:make_flag(k, v)
                end))
                self.c_options = c_options

                local cxx_options = options_merge({}, cx_options, options_map(cxx_flags, function(k, v)
                    return self:make_flag(k, v)
                end))
                self.cxx_options = cxx_options

                local as_options = options_map(as_flags, function(k, v)
                    return self:make_flag(k, v)
                end)
                self.as_options = as_options

                local ld_options = options_merge({}, options_map(ld_flags, function(k, v)
                    return self:make_flag(k, v)
                end), lib_dirs_options, libs_options)
                self.ld_options = ld_options

                local ar_options = options_map(ar_flags, function(k, v)
                    return self:make_flag(k, v)
                end)
                self.ar_options = ar_options

                local rules = {}

                if opts.tools then
                    for ext, tool in pairs(opts.tools) do
                        local tool_rulename = symgen(self.name .. '_tool_' .. ext); do
                            C.ninja_rule_add(tool_rulename, {
                                command = tool.fx(extends({}, tool.opts, opts)),
                                description = 'BUILD $out',
                            })
                        end

                        if tool.opts.output then
                            rules[ext] = { tool_rulename, tool }
                        else
                            rules[ext] = tool_rulename
                        end
                    end
                end

                local rule_postfix = self.rule_postfix
                local dep_type = self.dep_type

                local cc_rule_name = symgen(self.name .. '_cc_'); do
                    C.ninja_rule_add(cc_rule_name, {
                        command = options_tostring(ccache(), self.cc, c_options),
                        depfile = '$out.d',
                        deps = dep_type,
                        description = 'CC $out',
                    })
                end
                table.iforeach(c_file_extensions, function(ext)
                    rules[ext] = cc_rule_name
                end)

                if opts.pch_header then
                    opts.pch = path.combine(build_dir, path.fname(path.remove_extension(opts.pch_header)) .. '.pch')

                    local pch_command = options_tostring(self.cxx,
                        self:make_flag('pch',
                            { cxx = cxx_options }),
                        self:make_flag('pch',
                            { create = { pch_header = opts.pch_header, pch = opts.pch } }))

                    local pch_rule_name = symgen(self.name .. '_pch_'); do
                        C.ninja_rule_add(pch_rule_name, {
                            command = pch_command,
                            deps = dep_type,
                            description = 'PCH ' .. opts.pch_header,
                        })
                    end

                    C.ninja_edge_add(
                        self:make_flag('pch', { output = { pch = opts.pch } }),
                        pch_rule_name,
                        self:make_flag('pch', { input = { pch_header = opts.pch_header, pch = opts.pch } }),
                        nil
                    )
                end

                local cxx_rule_name = symgen(self.name .. '_cxx_'); do
                    local pch_options = opts.pch_header and
                        self:make_flag('pch', { use = { pch_header = opts.pch_header, pch = opts.pch } }) or ''

                    C.ninja_rule_add(cxx_rule_name, {
                        command = options_tostring(ccache(), self.cxx, cxx_options, pch_options),
                        depfile = '$out.d',
                        deps = dep_type,
                        description = 'CXX $out',
                    })
                end
                table.iforeach(cxx_file_extensions, function(ext)
                    rules[ext] = cxx_rule_name
                end)

                local as_rule_name = symgen(self.name .. '_as_'); do
                    C.ninja_rule_add(as_rule_name, {
                        command = options_tostring(self.as, as_options),
                        description = 'AS $out',
                    })
                end
                table.iforeach(asm_file_extensions, function(ext)
                    rules[ext] = as_rule_name
                end)

                local objs = {}; do
                    local function add_src(src, xrules, xopts)
                        xopts = xopts or {};

                        local ext = path.extension(src); if ext == '.obj' or ext == '.o' then
                            table.insert(objs, src); return
                        end

                        local rule = xrules[ext]; if rule == nil then
                            -- fatal('no rule for file: %s', src); return
                            table.insert(objs, src); return
                        end

                        local obj, vars; if type(rule) == 'string' then
                            obj = path.combine(build_dir, src .. '.o')
                        else
                            local tool = rule[2]; rule = rule[1]
                            obj, vars = tool.fx(extends({}, xopts, tool.opts), src)
                        end

                        table.insert(objs, obj)

                        if opts.pch_header and file_is_typeof(src, cxx_file_extensions) then
                            src = { src, implicit = opts.pch }
                        end

                        C.ninja_edge_add(obj, rule, src, vars)
                    end

                    for _, src in ipairs(srcs) do
                        if type(src) == 'table' then
                            local src_opts = table_as_option(src)

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
                                            t = { fx = xopts.tool, opts = {} }
                                        else
                                            t = xopts.tool
                                        end
                                    end
                                end

                                local topts = extends({}, src_opts, t.opts, xopts, opts)

                                local tool_rulename = symgen(self.name .. '_tool_' .. n); do
                                    C.ninja_rule_add(tool_rulename, {
                                        command = t.fx(topts),
                                        description = 'BUILD $out',
                                    })
                                end

                                source_foreach(src, function(f)
                                    local obj, vars = t.fx(topts, f)

                                    table.insert(objs, obj)
                                    C.ninja_edge_add(obj, tool_rulename, f, vars)
                                end)
                            else
                                xtarget:configure()

                                local xc_options, xcxx_options, xas_options = xtarget.c_options, xtarget.cxx_options,
                                    xtarget.as_options

                                if file_is_typeof(src, c_file_extensions) then
                                    local cc_rule_name = symgen(self.name .. '_cc_'); do
                                        C.ninja_rule_add(cc_rule_name, {
                                            command = options_tostring(ccache(), self.cc,
                                                options_merge({}, c_options, xc_options)),
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
                                            command = options_tostring(ccache(), self.cxx,
                                                options_merge({}, cxx_options, xcxx_options)),
                                            depfile = '$out.d',
                                            deps = dep_type,
                                            description = 'CXX $out',
                                        })
                                    end
                                    table.iforeach(cxx_file_extensions, function(ext)
                                        xrules[ext] = cxx_rule_name
                                    end)
                                end

                                if file_is_typeof(src, asm_file_extensions) then
                                    local as_rule_name = symgen(self.name .. '_as_'); do
                                        C.ninja_rule_add(as_rule_name, {
                                            command = options_tostring(self.as,
                                                options_merge({}, as_options, xas_options)),
                                            description = 'AS $out',
                                        })
                                    end
                                    table.iforeach(asm_file_extensions, function(ext)
                                        xrules[ext] = as_rule_name
                                    end)
                                end

                                if opts.tools then
                                    for ext, tool in pairs(opts.tools) do
                                        local topts = extends({}, src_opts, tool.opts, opts)

                                        local tool_rulename = symgen(self.name .. '_tool_' .. ext); do
                                            C.ninja_rule_add(tool_rulename, {
                                                command = tool.fx(topts),
                                                description = 'BUILD $out',
                                            })
                                        end

                                        if topts.output then
                                            rules[ext] = { tool_rulename, tool }
                                        else
                                            rules[ext] = tool_rulename
                                        end
                                    end
                                end

                                source_foreach(src, function(f)
                                    add_src(f, xrules, src_opts)
                                end)
                            end
                        else
                            source_foreach(src, function(f)
                                add_src(f, rules)
                            end)
                        end
                    end
                end; self.objs = objs

                if opts.type == 'phony' then
                    if table.isempty(objs) then
                        self.output = nil
                    else
                        C.ninja_edge_add(output, 'phony', objs, nil)
                    end
                elseif not table.isempty(objs) then
                    local deplibs, implicits = {}, {}; if opts.type == 'shared' or opts.type == 'binary' then
                        ninja.deps_foreach(self, function(tdep)
                            if tdep ~= self and tdep.output ~= nil then
                                local topts = tdep.opts; if (topts.type == 'shared') or (topts.type == 'static') then
                                    table.insert(deplibs, tdep.output)
                                elseif topts.type == 'phony' then
                                    table.insert(implicits, tdep.output)
                                end
                            end
                        end)
                    end

                    local inputs = options_merge({}, objs, deplibs); if not table.isempty(implicits) then
                        inputs.implicit = implicits
                    end

                    local ld_rule_name, ld_cmd, ld_desc, ld_vars; if opts.type == 'static' then
                        ld_rule_name = symgen(self.name .. '_ar_')
                        ld_cmd = options_tostring(self.ar, ar_options)
                        ld_desc = 'AR $out'
                    else
                        ld_rule_name = symgen(self.name .. '_ld_')
                        ld_cmd = options_tostring(self.ld, ld_options, self.default_libs)
                        ld_desc = 'LD $out'
                    end

                    do
                        local c = 0; for _, obj in ipairs(objs) do
                            c = c + string.len(obj)
                        end

                        if c > 1024 then
                            ld_cmd = string.replace(ld_cmd, '$in', '@$out.rsp'); ld_vars = {
                                rspfile = '$out.rsp',
                                rspfile_content = '$in'
                            }
                        end
                    end

                    C.ninja_rule_add(ld_rule_name, table.merge({
                        command = ld_cmd,
                        description = ld_desc,
                    }, ld_vars))

                    C.ninja_edge_add(output, ld_rule_name, inputs, nil)

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
                    if C.ninja_build(self.output) == 0 then
                        if self.after_build_actions then
                            for _, fx in ipairs(self.after_build_actions) do
                                fx(self)
                            end
                        end
                    end
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
            end
            return t
        end,

        basic = {
            cc = 'gcc',
            cxx = 'g++',
            as = 'as -o $out $in',
            ar = 'ar rcs $out $in',
            ld = 'g++ $in -o $out',

            dep_type = 'gcc',

            flag_switch = '-',

            flag_map = {
                std = '-std=',
                define = '-D',
                include_dir = '-I',
                include = '-include ',
                lib_dir = '-L',
                lib = '-l',
                shared = '-shared',
                debug_cc = '-g',
                debug_ld = '-g',
                pch_create = function(pch_header)
                    return '-include ' .. pch_header
                end,
                pch_use = function(pch_header)
                    return '-include ' .. pch_header
                end,
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
            ar = 'cosmoar rcs $out $in',
            ld = 'cosmoc++ $in -o $out',
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
            ar = 'llvm-ar rcs $out $in',
            ld = 'clang++ $in -o $out',

            flag_map = extends({}, gcc_toolchain.target.basic.flag_map, {
                debug_cc = '-g -gcodeview',
            }),
        },
    },
}); ninja.toolchains.clang = clang_toolchain

local zig_toolchain; zig_toolchain = object({
    target = {
        new = function(...)
            return extends(clang_toolchain.target.new(...), zig_toolchain.target.basic)
        end,

        basic = {
            cc = 'zig cc',
            cxx = 'zig c++',
            ar = 'zig lib $out $in',
            ld = 'zig cc $in -o $out',
        },
    },
}); ninja.toolchains.zig = zig_toolchain

local nvcc_toolchain; nvcc_toolchain = object({
    target = {
        new = function(...)
            local t = extends(basic_cc_toolchain.target.new(...), nvcc_toolchain.target.basic); do
                t:cx_flags('-c -o $out --generate-dependencies-with-compile -MF $out.d $in')
                t:ld_flags('-link $in -o $out')
                t:ar_flags('-lib $in -o $out')
            end
            return t
        end,

        basic = {
            cc = 'nvcc',
            cxx = 'nvcc',
            ar = 'nvcc',
            ld = 'nvcc',

            dep_type = 'gcc',

            -- default_libs = { 'kernel32.lib' },

            flag_switch = '-',

            flag_map = {
                std = '-std',
                define = '-D',
                include_dir = '-I',
                include = '-include',
                lib_dir = '-L',
                lib = '',
                shared = '-shared',
                debug_cc = '-g',
                debug_ld = '-g',
            },
        },
    },
}); ninja.toolchains.nvcc = nvcc_toolchain

local msvc_toolchain; msvc_toolchain = object({
    target = {
        new = function(...)
            local t = extends(basic_cc_toolchain.target.new(...), msvc_toolchain.target.basic); do
                t:cx_flags({ '/nologo /showIncludes', '/c $in', '/Fo$out' })
                -- t:cx_flags('/nologo /showIncludes /c $in /Fo$out')
                t:as_flags('/nologo /c /Fo$out $in')
                t:ld_flags('/nologo $in /OUT:$out')
                t:ar_flags('/nologo /OUT:$out $in')
            end
            return t
        end,

        basic = {
            cc = 'cl',
            cxx = 'cl',
            as = 'ml64',
            ar = 'lib',
            ld = 'link',

            dep_type = 'msvc',

            -- default_libs = { 'kernel32.lib' },

            flag_switch = '/',

            flag_map = {
                std = '/std:',
                define = '/D',
                include_dir = '/I',
                include = '/FI',
                lib_dir = '/LIBPATH:',
                lib = '',
                shared = '/DLL',
                debug_cc = '/Zi',
                debug_ld = '/DEBUG /INCREMENTAL:NO',
                pch = function(opts)
                    if opts.cxx then
                        opts = opts.cxx; return options_map(opts, function(k, v)
                            if v == '/c $in' then return nil end
                            if v == '/Fo$out' then return nil end

                            return k, v
                        end)
                    elseif opts.input then
                        opts = opts.input; return { path.remove_extension(opts.pch_header) .. '.cpp' }
                    elseif opts.output then
                        opts = opts.output; return { opts.pch, { implicit = path.remove_extension(opts.pch) .. '.o' } }
                        -- opts = opts.output; return { opts.pch, path.remove_extension(opts.pch) .. '.o' }
                    elseif opts.create then
                        opts = opts.create; return '/Yc' .. opts.pch_header ..
                            ' /Fp' .. opts.pch ..
                            ' /Fo' .. path.remove_extension(opts.pch) .. '.o' ..
                            ' /c ' .. path.remove_extension(opts.pch_header) .. '.cpp'
                    elseif opts.use then
                        opts = opts.use; return '/Yu' .. opts.pch_header .. ' /Fp' .. opts.pch
                    end

                    return nil;
                end,
            },
        },
    },
}); ninja.toolchains.msvc = msvc_toolchain

local clangcl_toolchain; clangcl_toolchain = object({
    target = {
        new = function(...)
            return extends(msvc_toolchain.target.new(...), clangcl_toolchain.target.basic)
        end,

        basic = {
            cc = 'clang-cl',
            cxx = 'clang-cl',
            ar = 'llvm-lib',
            ld = 'lld-link',

            -- flag_map = extends({}, msvc_toolchain.target.basic.flag_map, {
            --     debug_cc = '/Zi',
            -- }),
        },
    },
}); ninja.toolchains.clangcl = clangcl_toolchain

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

-- walk through the target dependencies
local function target_walk(target, fx, ctx, depth)
    target = ninja.target_of(target); if target == nil then
        return
    end

    if ctx[target] then return end

    if target.opts.deps then
        depth = depth or 0
        table.iforeach(target.opts.deps, function(dep)
            if (type(dep) == 'table') and (xtype(dep) ~= 'target') then
                if (xtype(dep) ~= 'private') or ((xtype(dep) == 'private') and (depth == 0)) then
                    table.iforeach(dep, function(d)
                        target_walk(d, fx, ctx, depth + 1)
                    end)
                end
            else
                target_walk(dep, fx, ctx, depth + 1)
            end
        end)
    end

    fx(target); ctx[target] = true
end

function ninja.targets_foreach(targets, fx)
    if not targets then return end

    local t = xtype(targets); if t == 'function' then
        fx = targets; targets = ninja.targets;
    elseif t == 'string' then
        local a = ninja.targets[targets]; if a == nil then
            fatal('target not found: %s', targets)
        end
        targets = { a }
    elseif t == 'target' then
        targets = { targets }
    end

    local ctx = {}; table.foreach(targets, function(_, target)
        target_walk(target, fx, ctx)
    end)
end

function ninja.deps_foreach(target, fx)
    target = ninja.target_of(target)

    local ctx = {}; target_walk(target, function(t)
        if t ~= target then fx(t) end
    end, ctx)

    fx(target)
end

function ninja.defaults_foreach(fx)
    ninja.targets_foreach(ninja.targets, function(target)
        if target.opts.default ~= false then
            fx(target)
        end
    end)
end

function ninja.build(...)
    if select('#', ...) == 0 then
        ninja.defaults_foreach(function(target)
            target:build()
        end); return
    end

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

function ninja.reset()
    C.ninja_reset()
end

function ninja.exit_on_error(b)
    C.ninja_exit_on_error(b)
end

function ninja.watch(dir, wildcard, ...)
    local targets = {}; vargs_foreach(function(target)
        if type(target) == 'function' then
            targets = target
        else
            vargs_foreach(function(t)
                table.insert(targets, t)
            end, ninja.target_of(target))
        end
    end, ...)

    local is_building = false; local last_build_time = 0; fs.watch(dir, function(fpath)
        if C.is_build_script(fpath) then
            C.reload(); quit(); return 'break'
        end

        if (last_build_time + 0.3) > os.clock() then
            return 'break'
        end

        local xmatch; do
            local fname = path.fname(fpath)
            for _, w in ipairs(as_list(wildcard)) do
                if path.ifnmatch(w, fname) then
                    xmatch = true; break
                end
            end
        end

        if xmatch then
            if is_building == false then
                is_building = true; ninja.reset()

                local now = _G.clock()

                if type(targets) == 'function' then
                    targets(fpath)
                else
                    ninja.build(unpack(targets))
                end

                is_building = false; last_build_time = os.clock()

                return 'break'
            end
        end
    end)

    ninja.exit_on_error(false); _G.run()
end

return ninja
