local ffi = require('ffi'); local jit_v = require("jit.v"); jit_v.on()

local c = ffi.C

ffi.cdef [[
    int reftable_ref(gcptr t, gcptr v);
]]

local config = ffi.C.ninja_config()

print('start')



print('done')
