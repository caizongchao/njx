local jit_v = require("jit.v"); jit_v.on()

require('ninja')

local options1 = {
    'aaa', 'bbb', ccc = 'ddd'
}

local options2 = {
    'xxx', ccc = OFF, {yyy= 'zzz', public = false}
}

print(options.to_string(options1))
print(options.to_string(options.public_merge(options1, options2)))


