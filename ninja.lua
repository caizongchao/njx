local ffi = require('ffi'); local C = ffi.C

local ON, OFF = true, false
local YES, NO = true, false

local function object(x)
    x = x or {}; x.__index = x; return x
end

local function extends(base, x)
    x = x or {}; setmetatable(x, base); return x
end

local ok, yes = assert, assert

local buffer = require('string.buffer')

local __buf = buffer.new()

local function buffer_rep(buf, str, n)
    for i = 1, n do
        buf:put(str)
    end
    return buf
end

local function buffer_indent(buf, indent)
    return buffer_rep(buf, ' ', indent)
end

local function string_split(str, sep)
    local list = {}; for s in str:gmatch('[^' .. sep .. ']+') do
        table.insert(list, s)
    end
    return list
end

local function string_startswith(str, prefix)
    return str:find(prefix, 1) == 1
end

local function string_endswith(str, suffix)
    return str:find(suffix, -#suffix) ~= nil
end

local function stacktrace(...)
    local msg; if select('#', ...) > 0 then
        msg = string.format(...)
    end
    print(debug.traceback(msg, 2))
end

local function fatal(code, ...)
    if type(code) == 'string' then
        stacktrace(code, ...); code = 1
    else
        stacktrace(...)
    end
    os.exit(code)
end

local function table_isempty(t)
    return next(t) == nil
end

local function table_append(t, v)
    if type(v) == 'table' then
        for _, v in ipairs(v) do
            t[#t + 1] = v
        end
    else
        t[#t + 1] = v
    end
    return t
end

local function table_merge(t, x, ...)
    if x then
        if type(x) == 'table' then
            for k, v in pairs(x) do
                t[k] = v
            end
        else
            t[#t + 1] = x
        end
        return table_merge(t, ...)
    else
        return t
    end
end

local function table_push(t, v)
    return table_append(t, v)
end

local function table_pop(t)
    local v = t[#t]; t[#t] = nil; return v
end

local function table_map(t, fx)
    local r = {}; for k, v in pairs(t) do
        r[k] = fx(v)
    end
    return r
end

local function flags_merge(t, flags, ...)
    if flags then
        if type(flags) == 'table' then
            for flag, value in ipairs(flags) do
                if type(flag) == 'number' then
                    t[value] = ON
                else
                    t[flag] = value
                end
            end
        else
            t[flags] = ON
        end
        return flags_merge(t, ...)
    else
        return t
    end
end

local TAB_SIZE = 4
local TAB = '    '
local LF = '\n'

local function inspect_to(buf, o, indent)
    indent = indent or 0; local t = type(o); if t == 'table' then
        buf:put('{\n'); for k, v in pairs(o) do
            buffer_rep(buf, ' ', indent + TAB_SIZE)
            if type(k) ~= 'number' then
                buf:put('["', k, '"]')
            else
                buf:put('[', k, ']')
            end
            buf:put(' = '); inspect_to(buf, v, indent + TAB_SIZE); buf:put(',', LF)
        end
        buffer_rep(buf, ' ', indent); buf:put('}');
    elseif t == 'string' then
        buf:put('"', o, '"')
    elseif t == 'userdata' then
        buf:put('[userdata]')
    else
        buf:put(tostring(o))
    end
    return buf
end

local function inspect(o, indent)
    indent = indent or 0; local t = type(o); if t == 'table' then
        local buf = buffer.new(); inspect_to(buf, o, indent); return buf:tostring()
    elseif t == 'string' then
        return string.format('"%s"', o)
    else
        return tostring(o)
    end
end

local function as_list(x)
    if x == nil then
        return {}
    elseif type(x) == 'table' then
        return x
    else
        return { x }
    end
end

ffi.cdef [[
    typedef void* HANDLE;
    typedef unsigned int UINT;
    typedef wchar_t WCHAR;
    typedef WCHAR* LPWSTR;
    typedef const WCHAR* LPCWSTR;
    typedef char* LPSTR;
    typedef const char* LPCSTR;
    typedef uint32_t DWORD;
    typedef int BOOL;
    typedef BOOL* LPBOOL;
    typedef struct {
        DWORD dwLowDateTime;
        DWORD dwHighDateTime;
    } FILETIME;

    typedef struct {
        DWORD dwFileAttributes;
        FILETIME ftCreationTime;
        FILETIME ftLastAccessTime;
        FILETIME ftLastWriteTime;
        DWORD nFileSizeHigh;
        DWORD nFileSizeLow;
        DWORD dwReserved0;
        DWORD dwReserved1;
        wchar_t cFileName[260];
        wchar_t cAlternateFileName[14];
    } WIN32_FIND_DATAW;

    static const int CSTR_EQUAL = 2;

    UINT MultiByteToWideChar(UINT CodePage, DWORD dwFlags, LPCSTR lpMultiByteStr, int cbMultiByte, LPWSTR lpWideCharStr, int cchWideChar);
    UINT WideCharToMultiByte(UINT CodePage, DWORD dwFlags, LPCWSTR lpWideCharStr, int cchWideChar, LPSTR lpMultiByteStr, int cbMultiByte, LPCSTR lpDefaultChar, LPBOOL lpUsedDefaultChar);

    HANDLE FindFirstFileW(const wchar_t* lpFileName, WIN32_FIND_DATAW* lpFindFileData);
    int FindNextFileW(HANDLE hFindFile, WIN32_FIND_DATAW* lpFindFileData);
    int FindClose(HANDLE hFindFile);

    DWORD GetFileAttributesA(LPCSTR lpFileName);
    DWORD GetFileAttributesW(LPCWSTR lpFileName);

    int CompareStringW(DWORD Locale, DWORD dwCmpFlags, LPWSTR lpString1, int cchCount1, LPWSTR lpString2, int cchCount2);

    int MessageBoxA(void* hWnd, LPCSTR lpText, LPCSTR lpCaption, UINT uType);
    int MessageBoxW(void* hWnd, LPCWSTR lpText, LPCWSTR lpCaption, UINT uType);
]]

local $wstr = ffi.new('WCHAR[?]', 16 * 1024)
local $str = ffi.new('char[?]', 16 * 1024)

local function u82w(str)
    local len = C.MultiByteToWideChar(65001, 0, str, -1, nil, 0)
    C.MultiByteToWideChar(65001, 0, str, -1, $wstr, len)
    return $wstr
end

local function w2u8(wstr)
    local len = C.WideCharToMultiByte(65001, 0, wstr, -1, nil, 0, nil, nil)
    C.WideCharToMultiByte(65001, 0, wstr, -1, $str, len, nil, nil)
    return ffi.string($str)
end

local INVALID_HANDLE_VALUE = ffi.cast('HANDLE', -1)
local find_dataw = ffi.new('WIN32_FIND_DATAW[1]')

local function path_quote(path)
    return '"' .. path .. '"'
end

local function path_try_quote(path)
    if path:find('[ \t]') then
        return path_quote(path)
    else
        return path
    end
end

local function path_unquote(path)
    return path:gsub('^"(.*)"$', '%1')
end

local function path_is_wildcard(path)
    return path:find('[*?]') ~= nil
end

local function path_wildcard_to_pattern(wildcard)
    return __buf:reset():put('^', wildcard:gsub('%.', '%%.'):gsub('%*', '.*'):gsub('%?', '.'), '$'):tostring()
end

local function path_add_backslash_to_drive(path)
    if path:match(':', -1) then return path .. '/' else return path end
end

local function path_remove_backslash(path)
    if path:match('[/\\]', -1) then
        return path:sub(1, -2)
    else
        return path
    end
end

local function path_parent(path)
    local i = path:find('[/\\][^/\\]*$')
    if i then
        return path_add_backslash_to_drive(path:sub(1, i - 1))
    else
        return path_add_backslash_to_drive(path)
    end
end

local function path_fname(path)
    local i = path:find('[/\\][^/\\]*$')
    if i then
        return path:sub(i + 1)
    else
        return nil
    end
end

local function path_dfname(path)
    local i = path:find('[/\\][^/\\]*$')
    if i then
        return path_add_backslash_to_drive(path:sub(1, i - 1)), path:sub(i + 1)
    else
        return path_add_backslash_to_drive(path), nil
    end
end

local function path_extension(path)
    local i = path:find('[.]%w+$')
    if i then
        return path:sub(i)
    else
        return ''
    end
end

local function path_remove_extension(path)
    local i = path:find('[.]%w+$'); if i then
        return path:sub(1, i - 1)
    else
        return path
    end
end

local function path_exclusions(path)
    local it = path:gmatch('[^|]+')

    local path = it()

    local exclusions; for exclusion in it do
        exclusions = exclusions or {}

        table.insert(exclusions, exclusion)
    end

    return path, exclusions
end

local function path_combine(path1, path2, ...)
    if not path2 then return path1 end

    if not path1 then
        return path_combine(path2, ...)
    elseif path1:match('[/\\]', -1) then
        return path_combine(path1 .. path2, ...)
    else
        return path_combine(path1 .. '/' .. path2, ...)
    end
end

local function path_ftype(path)
    local attrs = C.GetFileAttributesW(u82w(path))
    if attrs ~= 0xFFFFFFFF then
        if bit.band(attrs, 0x10) ~= 0 then
            return 'directory'
        else
            return 'file'
        end
    else
        return nil
    end
end

local function directory_walk(path, opts)
    local fx, recursive, wildcard, exclusions

    if type(opts) == 'table' then
        fx = opts[1]

        recursive = opts.recursive; wildcard = opts.wildcard

        if opts.exclusions then
            exclusions = table_map(opts.exclusions, function(exclusion)
                return path_wildcard_to_pattern(exclusion)
            end)
        end
    else
        fx = opts
    end

    wildcard = wildcard or '*'

    local stack = { path }; while #stack > 0 do
        local dir = stack[#stack]; stack[#stack] = nil
        local handle = C.FindFirstFileW(u82w(path_combine(dir, wildcard)), find_dataw)
        if handle ~= INVALID_HANDLE_VALUE then
            repeat
                local filename = w2u8(find_dataw[0].cFileName)
                if filename ~= '.' and filename ~= '..' then
                    if exclusions then
                        for _, exclusion in ipairs(exclusions) do
                            if filename:match(exclusion) then
                                goto next
                            end
                        end
                    end

                    local full_path = dir .. '/' .. filename
                    if bit.band(find_dataw[0].dwFileAttributes, 0x10) ~= 0 then
                        -- directory
                        if recursive then
                            stack[#stack + 1] = full_path
                        end
                    else
                        -- file
                        if fx then
                            local r = fx(full_path); if r then
                                return r
                            end
                        end
                    end

                    ::next::
                end
            until C.FindNextFileW(handle, find_dataw) == 0
            C.FindClose(handle)
        end
    end
end

local function file_exists(path)
    return path_ftype(path) == 'file'
end

local function directory_exists(path)
    return path_ftype(path) == 'directory'
end

local function files_foreach(path, fx)
    local opts; if type(path) == 'string' then
        local ap, exclusions = path_exclusions(path)

        if path_is_wildcard(ap) then
            local dir, wildcard = path_dfname(ap)
            path = dir; opts = {wildcard = wildcard, exclusions = exclusions, fx}
        else
            local ftype = path_ftype(ap); if ftype == 'file' then
                return fx(ap)
            else
                path = ap; opts = {exclusions = exclusions, fx}
            end
        end
    else
        path = path[1]; opts = path
    end

    return directory_walk(path, opts)
end

local ninja = {
    inspect = inspect,
    os = ffi.os:lower(),
    mode = 'debug', -- or 'release'
    targets = {},
    outdir = 'build',
    script = buffer.new(),

    escape = function(s)
        return s:gsub('%$', '$$ '):gsub(' ', '$ '):gsub(':', '$:')
    end,
}

function ninja:tostring()
    return self.script:tostring()
end

function ninja:line(...)
    self.script:put(...); self.script:put(LF); return self
end

function ninja:endl()
    self.script:put(LF); return self
end

function ninja:comment(text)
    self.script:put('# ', text, LF); return self
end

function ninja:variable(key, value, indent)
    if value == nil then
        return self
    end
    if type(value) == 'table' then
        value = table.concat(as_list(value), ' ')
    end
    buffer_indent(self.script); self.script:put(key, ' = ', value, LF); return self
end

function ninja:pool(name, depth)
    self.script:put('pool ', name, LF); self:variable('depth', depth, TAB_SIZE); return self
end

function ninja:rule(name, command, opts)
    self:line('rule ', name)

    self:variable('command', command, TAB_SIZE)

    if opts then
        if type(opts) == 'table' then
            for key, val in pairs(opts) do
                if type(key) == 'number' then
                    self:line(TAB, val)
                else
                    self:variable(key, val, TAB_SIZE)
                end
            end
        else
            self:line(TAB, val)
        end
    end
    return self
end

function ninja:build(outputs, rule, inputs, opts)
    local all_outputs = {}; for _, output in ipairs(as_list(outputs)) do
        table.insert(all_outputs, ninja.escape(output))
    end

    local all_inputs = {}; for _, input in ipairs(as_list(inputs)) do
        table.insert(all_inputs, ninja.escape(input))
    end

    if opts then
        if type(opts) == 'table' then
            for key, val in pairs(opts) do
                if type(key) == 'number' then
                    self:line(TAB, val)
                end
            end

            if opts.implicit then
                local implicit_list = {}
                for _, input in ipairs(as_list(opts.implicit)) do
                    table.insert(implicit_list, ninja.escape(input))
                end
                table.insert(all_inputs, '|')
                for _, input in ipairs(implicit_list) do
                    table.insert(all_inputs, input)
                end
            end

            if opts.order_only then
                local order_only_list = {}
                for _, input in ipairs(as_list(opts.order_only)) do
                    table.insert(order_only_list, ninja.escape(input))
                end
                table.insert(all_inputs, '||')
                for _, input in ipairs(order_only_list) do
                    table.insert(all_inputs, input)
                end
            end

            if opts.implicit_outputs then
                local implicit_outputs_list = {}
                for _, output in ipairs(as_list(opts.implicit_outputs)) do
                    table.insert(implicit_outputs_list, ninja.escape(output))
                end
                table.insert(all_outputs, '|')
                for _, output in ipairs(implicit_outputs_list) do
                    table.insert(all_outputs, output)
                end
            end
        else
            self:line(TAB, val)
        end
    end

    self:line('build ', table.concat(all_outputs, ' '), ': ', rule, ' ', table.concat(all_inputs, ' '))

    if opts then
        self:variable('pool', opts.pool, TAB_SIZE)
        self:variable('dyndep', opts.dyndep, TAB_SIZE)
    end

    if opts.variables then
        if type(opts.variables) == 'table' then
            for key, val in pairs(opts.variables) do
                if type(key) == 'number' then
                    self:line(TAB, val)
                else
                    self:variable(key, val, TAB_SIZE)
                end
            end
        else
            self:line(TAB, val)
        end
    end

    return self
end

function ninja:include(path)
    self:line('include ', path); return self
end

function ninja:subninja(path)
    self:line('subninja ', path); return self
end

function ninja:default(paths)
    self:line('default ', table.concat(as_list(paths), ' ')); return self
end

local basic_target = object({
    vars = function(self)
        self.toolchain.vars(self)
    end,

    rule = function(self)
        self.toolchain.rule(self)
    end,

    build = function(self)
        self.toolchain.build(self)
    end,
})

local toolchain_cc = object({
    target_new = function(self)
        return extends(basic_target, {
            toolchain = self,
            name = 'a',
            kind = 'binary',
            default = false,
            cstandard = nil,
            cflags = {},
            ldflags = {},
            defines = {},
            includes = {},
            include_dirs = {},
            libs = {},
            lib_dirs = {},
            files = {},
            objs = {},
            deps = {},
            crt = nil,
            subsystem = nil,
            pch = nil,
        })
    end,

    name = function(tgt, name)
        tgt.name = name
    end,

    kind = function(tgt, k)
        tgt.kind = k
    end,

    default = function(tgt, d)
        tgt.default = d
    end,

    cstandard = function(tgt, std)
        tgt.cstandard = std
    end,

    cflags = function(tgt, flags)
        flags_merge(tgt.cflags, flags)
    end,

    ldflags = function(tgt, flags)
        flags_merge(tgt.ldflags, flags)
    end,

    defines = function(tgt, defs)
        flags_merge(tgt.defines, defs)
    end,

    includes = function(tgt, incs)
        table_append(tgt.includes, incs)
    end,

    include_dirs = function(tgt, incs)
        table_append(tgt.include_dirs, incs)
    end,

    libs = function(tgt, libs)
        table_append(tgt.libs, libs)
    end,

    lib_dirs = function(tgt, dirs)
        table_append(tgt.lib_dirs, dirs)
    end,

    files = function(tgt, files)
        table_append(tgt.files, files)
    end,

    objs = function(tgt, objs)
        table_append(tgt.objs, objs)
    end,

    deps = function(tgt, deps)
        table_append(tgt.deps, deps)
    end,

    crt = function(tgt, crt)
        tgt.crt = crt
    end,

    subsystem = function(tgt, subsystem)
        tgt.subsystem = subsystem
    end,

    pch = function(tgt, pch)
        tgt.pch = pch
    end,
})

local msvc = extends(toolchain_cc, {
    vars = function(tgt)
    end,

    rule = function(tgt)
        ninja:rule('msvc_cc', 'cl $cflags $defines /showIncludes /c /Fo$out $in', {
            deps = 'msvc',
        })

        ninja:rule('msvc_link', 'link $ldflags $in /out:$out $libs')

        ninja:rule('msvc_lib', 'lib $in /out:$out')
    end,

    build = function(tgt)
        local outdir = path_combine(ninja.outdir, ninja.mode)
        local bindir = path_combine(outdir, 'bin')
        local tgtdir = path_combine(outdir, tgt.name)

        local tgt_fname; if tgt.kind == 'binary' then
            tgt_fname = tgt.name .. '.exe'
        elseif tgt.kind == 'static' then
            tgt_fname = tgt.name .. '.lib'
        elseif tgt.kind == 'shared' then
            tgt_fname = tgt.name .. '.dll'
        end

        local tgt_fpath = path_combine(bindir, tgt_fname)
        local objs_dir = path_combine(tgtdir, 'objs')

        local cflags = {}; do
            local cstandard = tgt.cstandard or 'c++20'

            if cstandard then
                table_append(cflags, '/std:' .. cstandard)
            end

            if string_startswith(cstandard, 'c++') then
                table_append(cflags, '/EHsc')
            elseif cstandard == 'c89' then
                table_append(cflags, '/TC')
            end

            if ninja.mode == 'debug' then
                table_append(cflags, '/Od', '/Zi', '/Fd' .. path_combine(bindir, tgt.name .. '.pdb'))

                if (not tgt.crt) or tgt.crt == 'static' then
                    table_append(cflags, '/MTd')
                elseif tgt.crt == 'dynamic' then
                    table_append(cflags, '/MDd')
                end
            elseif ninja.mode == 'release' then
                table_append(cflags, '/O2')

                if (not tgt.crt) or tgt.crt == 'static' then
                    table_append(cflags, '/MT')
                elseif tgt.crt == 'dynamic' then
                    table_append(cflags, '/MD')
                end
            end
        end

        local ldflags = {}; do
            if ninja.mode == 'debug' then
                table_append(ldflags, '/DEBUG')
            elseif ninja.mode == 'release' then
                table_append(ldflags, '/OPT:REF', '/OPT:ICF')
            end

            if tgt.kind == 'binary' then
                local subsystem = tgt.subsystem or 'console'

                if subsystem ~= 'console' then
                    table_append(ldflags, '/SUBSYSTEM:' .. subsystem)
                end
            elseif tgt.kind == 'shared' then
                table_append(ldflags, '/DLL')
            end

            if #tgt.lib_dirs > 0 then
                for _, dir in ipairs(tgt.lib_dirs) do
                    table_append(ldflags, '/LIBPATH:' .. path_try_quote(dir))
                end
            end
        end

        local defines = nil; if #tgt.defines > 0 then
            __buf:reset(); for _, def in ipairs(tgt.defines) do
                __buf:put('/D', def, ' ')
            end
            defines = __buf:tostring()
        end

        local includes = nil; if #tgt.includes > 0 then
            __buf:reset(); for _, inc in ipairs(tgt.includes) do
                __buf:put('/FI', path_try_quote(inc), ' ')
            end
            includes = __buf:tostring()
        end

        local include_dirs = nil; if #tgt.include_dirs > 0 then
            include_dirs = table.concat('/I' .. tgt.include_dirs, ' ')
        end

        local cflags_pch_create, cflags_pch_use; if tgt.pch then
            local pch_fname = path_remove_extension(tgt.pch) .. '.pch'

            cflags_pch_create = cflags .. ' /Yc' .. pch_fname
            cflags_pch_use = cflags .. ' /Yu' .. pch_fname
        end

        local src = {}; do
            if tgt.pch then
                table_append(src, tgt.pch)
            end

            for _, path in ipairs(tgt.files) do
                files_foreach(path, function(fname)
                    if (not tgt.pch) or (fname ~= tgt.pch) then
                        table_append(src, fname)
                    end
                end)
            end
        end

        local objs, libs = {}, {}; for _, fname in ipairs(src) do
            local ext = path_extension(fname); do
                if ext == '.obj' then
                    table_append(objs, fname); goto next
                elseif ext == '.lib' then
                    table_append(libs, fname); goto next
                end
            end

            local obj_fname = path_fname(fname) .. '.obj'
            local obj_fpath = path_combine(objs_dir, obj_fname)

            table_append(objs, obj_fpath)

            ninja:build(obj_fpath, 'msvc_cc', fname, {
                cflags = tgt.pch and ((fname == tgt.pch) and cflags_pch_create or cflags_pch_use) or cflags,
                defines = defines,
                includes = includes,
                include_dirs = include_dirs,
            })
        end

        for _, obj in ipairs(tgt.objs) do
            table_append(objs, obj)
        end

        for _, lib in ipairs(tgt.libs) do
            table_append(libs, lib)
        end

        if tgt.kind == 'static' then
            ninja:build(tgt_fpath, 'msvc_lib', objs)
        else
            ninja:build(tgt_fpath, 'msvc_link', objs, {
                ldflags = ldflags,
                libs = (#libs > 0) and table.concat(libs, ' ') or nil,
            })
        end

        return tgt_fpath
    end,
})

local DEFAULT_TOOLCHAIN = (ninja.os == 'windows') and msvc or gcc

function ninja:target(name, opts)
    local toolchain = opts[1] or opts.toolchain or DEFAULT_TOOLCHAIN
    local tgt = toolchain:target_new()

    toolchain.name(tgt, name); if opts then
        for key, val in pairs(opts) do
            local fx = toolchain[key]; if fx then
                fx(tgt, val)
            end
        end
    end

    table_append(ninja.targets, tgt); return self
end

local function target_walk(tgt, fx)
    if tgt.touched then
         return
    else
        tgt.touched = true
    end

    for _, dep in ipairs(tgt.deps) do
        target_walk(dep, fx)
    end

    fx(tgt)
end

function ninja:configure()
    for _, tgt in ipairs(self.targets) do
        target_walk(tgt, function(tgt)
            tgt:vars()
        end)
    end

    for _, tgt in ipairs(self.targets) do
        tgt.touched = false
    end

    for _, tgt in ipairs(self.targets) do
        target_walk(tgt, function(tgt)
            tgt:rule()
        end)
    end

    for _, tgt in ipairs(self.targets) do
        tgt.touched = false
    end

    local defaults = {};

    for _, tgt in ipairs(self.targets) do
        target_walk(tgt, function(tgt)
            local fpath = tgt:build(); if tgt.default then
                table_append(defaults, fpath)
            end
        end)
    end

    self:default(defaults)

    -- write output to build.ninja
    local f = io.open('build.ninja', 'w'); if not f then
        fatal('failed to open build.ninja for writing')
    end

    f:write(self.script:tostring()); f:close()

    print('build.ninja configured')

    return self
end

return ninja

