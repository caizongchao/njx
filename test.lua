ffi = require('ffi')

ffi.cdef[[
    typedef void * ninja_state_t;

    ninja_state_t ninja_state();
]]

ffi.C.printf("hello from ffi: %f\n", 123.0)

print('done')