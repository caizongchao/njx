local jit_v = require("jit.v"); jit_v.on()

require('ninja')

local options1 = {
    'aaa', 'bbb', ccc = 'ddd'
}

local options2 = {
    'xxx', ccc = OFF, {yyy= 'zzz', public = false}
}

local options3 = table.mapk(options2, function(x)
    if x == 'public' then return x end
    return '-I' .. x
end)

print(options.to_string(options1))
print(options.to_string(options.public_merge(options1, options2)))
print(options.to_string(options3))
print(inspect(options3))


