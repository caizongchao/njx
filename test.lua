local jit_v = require("jit.v"); jit_v.on()

require('ninja')

local target = ninja.target('foo', {
    toolchain = 'gcc',
    srcs = 'test/*.cpp'
})

-- print(inspect(target))

target:build()

