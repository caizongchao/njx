---@diagnostic disable: deprecated, undefined-field
require('table.new'); require('table.clear')

local ffi = require('ffi'); local C = ffi.C
-- local jit_v = require("jit.v"); jit_v.on()

_G.ffi = ffi; _G.C = C

ffi.cdef [[
    void debug(gcptr x);

    void printf(const char* fmt, ...);

    void buffer_pathappend(gcptr buf, gcptr path);
    gcstr buffer_tostring(gcptr buf);

    gctab reftable_new(uint32_t size);
    int reftable_ref(gcptr t, gcptr x);
    void reftable_unref(gcptr t, int r);

    int timer_add(int ms, int fx, int repeat);
    void timer_remove(int id);
    int timer_update(gcptr xs);
]]

local printf = C.printf

local ON, OFF = true, false; _G.ON = ON; _G.OFF = OFF
local YES, NO = true, false; _G.YES = YES; _G.NO = NO

local ok, yes = assert, assert; _G.ok = ok; _G.yes = yes

local function vargs_foreach(fx, ...)
    local c = select('#', ...); if c == 0 then
        return
    end

    for i = 1, c do
        local v = select(i, ...); if v ~= nil then
            fx(v)
        end
    end
end; _G.vargs_foreach = vargs_foreach

local __counter = -1

local function __counter_next()
    __counter = __counter + 1; return __counter
end; _G.__counter_next = __counter_next

local rand = math.random

-- seeding the random number generator
local seed = os.time(); math.randomseed(seed)

local buffer = require('string.buffer'); _G.buffer = buffer
local __buf = buffer.new(); _G.__buf = __buf

local buffer_pathappend = C.buffer_pathappend
local buffer_tostring = C.buffer_tostring

local function buffer_rep(buf, str, n)
    for i = 1, n do
        buf:put(str)
    end
    return buf
end

local function buffer_indent(buf, indent)
    return buffer_rep(buf, ' ', indent)
end

local function pick(cond, a, b)
    if cond then return a else return b end
end; _G.pick = pick

local function uuid(len)
    local buf = __buf:reset(); len = len or 32
    for i = 1, len do
        buf:putf('%x', rand(0, 15))
    end
    return buf:tostring()
end; _G.uuid = uuid

local function randbuf(buf, len)
    len = len or 32
    for i = 1, len do
        buf:putf('%x', rand(0, 15))
    end
    return buf
end; _G.randbuf = randbuf

local function randstr(len)
    __buf:reset(); return randbuf(__buf, len):tostring()
end; _G.randstr = randstr

ffi.cdef [[
    gcptr reftable_new(uint32_t size);
    int reftable_ref(gcptr t, gcptr v);
    void reftable_unref(gcptr t, int r);
]]

local __mixin = '__mixin'

local function object(x)
    x = x or {}; x.__index = function(self, key)
        local mx = rawget(self, __mixin); if mx then
            for _, m in ipairs(mx) do
                local v = m[key]; if v then
                    self[key] = v; return v
                end
            end
        end
        return nil
    end;
    setmetatable(x, x); return x
end; _G.object = object

local function inherits(base, x)
    x = (x and x.__index) and x or object(x)
    local m = rawget(x, __mixin); if not m then
        m = {}; rawset(x, __mixin, m)
    end
    table.insert(m, 1, base)
    return x
end; _G.inherits = inherits

local function extends(x, ...)
    vargs_foreach(function(base)
        inherits(base, x)
    end, ...)
    return x
end; _G.extends = extends

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
                if type(k) == 'number' then
                    table.insert(t, v)
                else
                    t[k] = v
                end
            end
        else
            table.insert(t, x)
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

local function table_mapk(t, fx)
    local r = {}; for k, v in pairs(t) do
        if type(k) == 'number' then
            if type(v) == 'table' then
                v = table_mapk(v, fx)
            else
                v = fx(v)
            end

            if v ~= nil then
                r[k] = v
            end
        else
            k = fx(k); if k ~= nil then
                r[k] = v
            end
        end
    end
    return r
end

local function table_deepcopy(t)
    local r = {}; for k, v in pairs(t) do
        if type(v) == 'table' then
            v = table_deepcopy(v)
        end
        r[k] = v
    end
    return r
end

local function table_foreach(t, fx)
    for k, v in pairs(t) do
        if fx(k, v) == false then break end
    end
end

local function table_iforeach(t, fx)
    for i, v in ipairs(t) do
        if fx(v, i) == false then break end
    end
end

setmetatable(table, {
    __index = {
        isempty = table_isempty,
        append = table_append,
        merge = table_merge,
        push = table_push,
        pop = table_pop,
        map = table_map,
        mapk = table_mapk,
        deepcopy = table_deepcopy,
        foreach = table_foreach,
        iforeach = table_iforeach,
    }
})

local function string_concat(...)
    local c = select('#', ...)
    local buf = __buf:reset(); for i = 1, c do
        local s = select(i, ...); if s ~= nil then
            buf:put(s)
        end
    end
    return buf:tostring()
end

local function string_split(str, sep)
    local list = {}; for s in str:gmatch('[^' .. sep .. ']+') do
        table.insert(list, s)
    end
    return list
end

local function string_starts_with(str, prefix)
    return str:find(prefix, 1) == 1
end

local function string_ends_with(str, suffix)
    return str:find(suffix, - #suffix) ~= nil
end

setmetatable(string, {
    __index = {
        concat = string_concat,
        split = string_split,
        starts_with = string_starts_with,
        ends_with = string_ends_with,
    }
})

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

local function trace(...)
    local c = select('#', ...); for i = 1, c do
        local v = select(i, ...); print(inspect(v))
    end
end; _G.trace = trace

ffi.cdef [[
    typedef void* HANDLE;
    typedef void* LPVOID;
    typedef unsigned int UINT;
    typedef wchar_t WCHAR;
    typedef WCHAR* LPWSTR;
    typedef const WCHAR* LPCWSTR;
    typedef char* LPSTR;
    typedef const char* LPCSTR;
    typedef uint32_t DWORD;
    typedef DWORD* LPDWORD;
    typedef int BOOL;
    typedef BOOL* LPBOOL;
    typedef uint32_t ULONG;
    typedef ULONG * ULONG_PTR;
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

    typedef struct _OVERLAPPED {
        ULONG_PTR Internal;
        ULONG_PTR InternalHigh;
        union {
          struct {
            DWORD Offset;
            DWORD OffsetHigh;
          } DUMMYSTRUCTNAME;
          LPVOID Pointer;
        } DUMMYUNIONNAME;
        HANDLE    hEvent;
        int data;
    } OVERLAPPED, *LPOVERLAPPED;

    typedef struct _FILE_NOTIFY_INFORMATION {
        DWORD NextEntryOffset;
        DWORD Action;
        DWORD FileNameLength;
        WCHAR FileName[1];
    } FILE_NOTIFY_INFORMATION, *PFILE_NOTIFY_INFORMATION;

    typedef void (* LPOVERLAPPED_COMPLETION_ROUTINE)(DWORD dwErrorCode, DWORD dwNumberOfBytesTransfered, LPOVERLAPPED lpOverlapped);

    int GetLastError();

    UINT MultiByteToWideChar(UINT CodePage, DWORD dwFlags, LPCSTR lpMultiByteStr, int cbMultiByte, LPWSTR lpWideCharStr, int cchWideChar);
    UINT WideCharToMultiByte(UINT CodePage, DWORD dwFlags, LPCWSTR lpWideCharStr, int cchWideChar, LPSTR lpMultiByteStr, int cbMultiByte, LPCSTR lpDefaultChar, LPBOOL lpUsedDefaultChar);

    int CreateEventW(LPVOID lpEventAttributes, BOOL bManualReset, BOOL bInitialState, LPCWSTR lpName);

    int CreateFileW(LPCWSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, LPVOID lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, int hTemplateFile);
    BOOL CloseHandle(int hObject);

    int FindFirstFileW(const wchar_t* lpFileName, WIN32_FIND_DATAW* lpFindFileData);
    int FindNextFileW(int hFindFile, WIN32_FIND_DATAW* lpFindFileData);
    int FindClose(int hFindFile);

    DWORD GetFileAttributesA(LPCSTR lpFileName);
    DWORD GetFileAttributesW(LPCWSTR lpFileName);

    BOOL ReadDirectoryChangesW(
        int hDirectory,
        LPVOID lpBuffer,
        DWORD nBufferLength,
        BOOL bWatchSubtree,
        DWORD dwNotifyFilter,
        LPDWORD lpBytesReturned,
        LPOVERLAPPED lpOverlapped,
        LPOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine);

    int CreateIoCompletionPort(intptr_t FileHandle, intptr_t ExistingCompletionPort, intptr_t CompletionKey, int NumberOfConcurrentThreads);
    int GetQueuedCompletionStatus(int CompletionPort, intptr_t * lpNumberOfBytes, intptr_t * lpCompletionKey, LPOVERLAPPED * lpOverlapped, int dwMilliseconds);
    int PostQueuedCompletionStatus(int CompletionPort, intptr_t dwNumberOfBytesTransferred, intptr_t dwCompletionKey, intptr_t lpOverlapped);
]]

local kernel32 = ffi.load('kernel32')

local INVALID_HANDLE_VALUE = -1

local GetLastError = kernel32.GetLastError

local MultiByteToWideChar = kernel32.MultiByteToWideChar
local WideCharToMultiByte = kernel32.WideCharToMultiByte

local CreateEventW = kernel32.CreateEventW

local FILE_ATTRIBUTE_DIRECTORY = 0x00000010

local CreateFileW = kernel32.CreateFileW
local CloseHandle = kernel32.CloseHandle

local GetFileAttributesA = kernel32.GetFileAttributesA
local GetFileAttributesW = kernel32.GetFileAttributesW

local find_dataw = ffi.new('WIN32_FIND_DATAW[1]')

local FindFirstFileW = kernel32.FindFirstFileW
local FindNextFileW = kernel32.FindNextFileW
local FindClose = kernel32.FindClose

local FILE_NOTIFY_CHANGE_LAST_WRITE = 0x00000010
local ReadDirectoryChangesW = kernel32.ReadDirectoryChangesW

local CreateIoCompletionPort = kernel32.CreateIoCompletionPort
local GetQueuedCompletionStatus = kernel32.GetQueuedCompletionStatus
local PostQueuedCompletionStatus = kernel32.PostQueuedCompletionStatus

local __wstr = ffi.new('WCHAR[?]', 16 * 1024)
local __str = ffi.new('char[?]', 16 * 1024)

local function u82w(str)
    local len = MultiByteToWideChar(65001, 0, str, -1, nil, 0)
    MultiByteToWideChar(65001, 0, str, -1, __wstr, len)
    return __wstr
end

local function w2u8(wstr)
    local len = WideCharToMultiByte(65001, 0, wstr, -1, nil, 0, nil, nil)
    WideCharToMultiByte(65001, 0, wstr, -1, __str, len, nil, nil)
    return ffi.string(__str)
end

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

local function path_do_pathappend(path)
    buffer_pathappend(__buf, path)
end

local function path_do_compbine(buf, ...)
    __buf:reset(); do
        vargs_foreach(path_do_pathappend, ...)
    end
    return buffer_tostring(__buf)
end

local function path_combine(...)
    return path_do_compbine(__buf:reset(), ...)
end

local function path_ftype(path)
    local attrs = GetFileAttributesW(u82w(path))
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
        local handle = FindFirstFileW(u82w(path_combine(dir, wildcard)), find_dataw)
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
            until FindNextFileW(handle, find_dataw) == 0
            FindClose(handle)
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
            path = dir; opts = { wildcard = wildcard, exclusions = exclusions, fx }
        else
            local ftype = path_ftype(ap); if ftype == 'file' then
                return fx(ap)
            else
                path = ap; opts = { exclusions = exclusions, fx }
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

local reftable_new = C.reftable_new
local reftable_ref = C.reftable_ref
local reftable_unref = C.reftable_unref

-- registry
local registry; registry = object({
    new = function(size)
        local t = reftable_new(size or 1024); setmetatable(t, { __index = registry }); return t
    end,

    register = function(self, x)
        return reftable_ref(self, x)
    end,

    unregister = function(self, i)
        reftable_unref(self, i)
    end,
}); _G.registry = registry

-- events
local __events = {}

local function on(name, fx)
    local x = __events[name]; if x == nil then
        __events[name] = fx; return 1
    else
        if type(x) == 'table' then
            table.insert(x, fx); return #x
        else
            __events[name] = { x, fx }; return 2
        end
    end
end; _G.on = on

local function off(name, i)
    if (i == 0) or type(__events[name] ~= 'table') then
        __events[name] = nil; return
    end
    __events[name][i] = nil
end; _G.off = off

local function emit(name, ...)
    local x = __events[name]; if x ~= nil then
        if type(x) ~= 'table' then
            x(...)
        else
            for _, fx in ipairs(x) do
                fx(...)
            end
        end
    end
end; _G.emit = emit

-- timer
local timer_add = C.timer_add
local timer_remove = C.timer_remove
local timer_update = C.timer_update

local timer_registry = registry.new()

local function set_timeout(ms, fx)
    local i; i = timer_registry:register(function()
        fx(); timer_registry:unregister(i);
    end)
    return timer_add(ms, i, 0)
end; _G.set_timeout = set_timeout

local function set_interval(ms, fx)
    return timer_add(ms, timer_registry:register(fx), 1)
end; _G.set_interval = set_interval

local function clear_timeout(id)
    timer_remove(id); timer_registry:unregister(id)
end; _G.clear_timeout = clear_timeout

local __timeouts = table.new(32, 0)

local function update_timer()
    local c = timer_update(__timeouts); if c == 0 then
        return
    end
    for i = 0, c - 1 do
        timer_registry[__timeouts[i]]()
    end
end

-- IOCP
local IOCP = CreateIoCompletionPort(-1, 0, 0, 0); ok(IOCP ~= 0)

local iocp_registry = registry.new()

local function iocp_on_complete(completionKey, overlapped)
    local i; if overlapped ~= nil then
        i = overlapped.data
    else
        i = tonumber(completionKey)
    end

    local x = iocp_registry[i]; if type(x) == "function" then
        x()
    else -- t == "table"
        emit(x[1], unpack(x, 2))
    end

    iocp_registry:unregister(i)
end

local iocp_lpNumberOfBytes = ffi.new("intptr_t[1]")
local iocp_lpCompletionKey = ffi.new("intptr_t[1]")
local iocp_lpOverlapped = ffi.new("LPOVERLAPPED[1]")

local function run()
    local timeout = 8; while true do
        if (GetQueuedCompletionStatus(IOCP, iocp_lpNumberOfBytes, iocp_lpCompletionKey, iocp_lpOverlapped, timeout) ~= 0) then
            iocp_on_complete(iocp_lpCompletionKey[0], iocp_lpOverlapped[0]);
        else
            update_timer()
        end
    end
end; _G.run = run

local function post(x)
    local i = iocp_registry:register(x); PostQueuedCompletionStatus(IOCP, 0, i, 0)
end; _G.post = post

local function poll()
    while (GetQueuedCompletionStatus(IOCP, iocp_lpNumberOfBytes, iocp_lpCompletionKey, iocp_lpOverlapped, 0) ~= 0) do
        iocp_on_complete(iocp_lpCompletionKey[0], iocp_lpOverlapped[0]);
    end
    update_timer()
end; _G.poll = poll

-- fs watch file changes
local function fs_watch(dir, fx)
    local hdir = CreateFileW(u82w(dir), 0x0001, 0x0007, nil, 3, 0x42000000, 0); ok(hdir ~= INVALID_HANDLE_VALUE)
    local h = CreateIoCompletionPort(hdir, IOCP, 0, 0); ok(h == IOCP)

    local BUFFER_SIZE = 16 * 1024

    local buf = ffi.new("char[?]", BUFFER_SIZE)
    local lpBytesReturned = ffi.new("DWORD[1]")
    local lpOverlapped = ffi.new("OVERLAPPED[1]")

    local overlapped = lpOverlapped[0]

    local on_change; on_change = function()
        local p = buf; while true do
            local info = ffi.cast("FILE_NOTIFY_INFORMATION*", p)
            local filename = w2u8(info.FileName)
            if filename ~= '.' and filename ~= '..' then
                fx(path.combine(dir, filename))
            end
            if info.NextEntryOffset == 0 then
                break
            end
            p = p + info.NextEntryOffset
        end

        overlapped.data = iocp_registry:register(on_change)

        ok(ReadDirectoryChangesW(hdir, buf, BUFFER_SIZE, 1, FILE_NOTIFY_CHANGE_LAST_WRITE, lpBytesReturned, lpOverlapped,
            nil) ~= 0)
    end

    overlapped.data = iocp_registry:register(on_change)

    ok(ReadDirectoryChangesW(hdir, buf, BUFFER_SIZE, 1, FILE_NOTIFY_CHANGE_LAST_WRITE, lpBytesReturned, lpOverlapped, nil) ~=
        0)
end; fs.watch = fs_watch

-- fs_watch('r:/temp', function(fname)
--     printf('file changed-->: %s\n', fname)
-- end)

-- post(function()
--     print('hello world')
-- end)

-- set_interval(1000, function()
--     C.printf('tick\n')
-- end)

-- C.printf('===> %s\n', 'hello world')

-- run()
