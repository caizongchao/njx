local jit_v = require("jit.v"); jit_v.on()

print(__counter_next())
print(__counter_next())
print(__counter_next())
print(__counter_next())
print('hello' .. __counter_next())