local ffi = require('ffi')
local C = ffi

_G.ffi = ffi
_G.C = C

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
end; _G.fatal = fatal

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

setmetatable(table, {
    __index = {
        isempty = table_isempty,
        append = table_append,
        merge = table_merge,
        push = table_push,
        pop = table_pop,
        map = table_map,
    }
})

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
    return str:find(suffix, - #suffix) ~= nil
end

setmetatable(string, {
    __index = {
        split = string_split,
        starts_with = string_startswith,
        ends_with = string_endswith,
    }
})

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
end; _G.inspect_to = inspect_to

local function inspect(o, indent)
    indent = indent or 0; local t = type(o); if t == 'table' then
        local buf = buffer.new(); inspect_to(buf, o, indent); return buf:tostring()
    elseif t == 'string' then
        return string.format('"%s"', o)
    else
        return tostring(o)
    end
end; _G.inspect = inspect

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
]]

local kernel32 = ffi.load('kernel32')

local __wstr = ffi.new('WCHAR[?]', 16 * 1024)
local __str = ffi.new('char[?]', 16 * 1024)

local function u82w(str)
    local len = kernel32.MultiByteToWideChar(65001, 0, str, -1, nil, 0)
    kernel32.MultiByteToWideChar(65001, 0, str, -1, __wstr, len)
    return __wstr
end

local function w2u8(wstr)
    local len = kernel32.WideCharToMultiByte(65001, 0, wstr, -1, nil, 0, nil, nil)
    kernel32.WideCharToMultiByte(65001, 0, wstr, -1, __str, len, nil, nil)
    return ffi.string(__str)
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
    local attrs = kernel32.GetFileAttributesW(u82w(path))
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

do
    local path = {}; do
        path.quote = path_quote
        path.try_quote = path_try_quote
        path.unquote = path_unquote
        path.is_wildcard = path_is_wildcard
        path.wildcard_to_pattern = path_wildcard_to_pattern
        path.add_backslash_to_drive = path_add_backslash_to_drive
        path.remove_backslash = path_remove_backslash
        path.parent = path_parent
        path.fname = path_fname
        path.dfname = path_dfname
        path.extension = path_extension
        path.remove_extension = path_remove_extension
        path.exclusions = path_exclusions
        path.combine = path_combine
        path.ftype = path_ftype
    end
    _G.path = path
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
        local handle = kernel32.FindFirstFileW(u82w(path_combine(dir, wildcard)), find_dataw)
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
            until kernel32.FindNextFileW(handle, find_dataw) == 0
            kernel32.FindClose(handle)
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

do
    local fs = {}; do
        fs.walk = directory_walk
        fs.file_exists = file_exists
        fs.directory_exists = directory_exists
        fs.foreach = files_foreach
    end
    _G.fs = fs
end
