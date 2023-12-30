local jit_v = require("jit.v"); jit_v.on()

require('ninja')

local target = ninja.target('foo', {
    toolchain = 'cosmocc',
    srcs = 'test/*.cpp'
})

print(inspect(target))

-- target:prepare()
-- target:build()

