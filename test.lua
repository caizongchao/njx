local ffi = require('ffi'); local jit_v = require("jit.v"); jit_v.on()

local c = ffi.C

ffi.cdef [[
    gcptr reftable_new(uint32_t size);
    int reftable_ref(gcptr t, gcptr v);
    void reftable_unref(gcptr t, int r);
]]

print('start')

local t = c.reftable_new(1024)

trace(t)

for i = 1, 100 do
local r = c.reftable_ref(t, 'hello')
print(i, r, t[r])

c.reftable_unref(t, r)
-- trace(t)

end

trace(t)

print('done')
