local jit_v = require("jit.v"); jit_v.on()

require('ninja')

local target = ninja.target('gcc', 'foo', 'binary', {
    srcs = 'test/*.cpp'
})

target:prepare()
target:build()

