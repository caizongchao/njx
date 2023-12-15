@REM cosmocc -c deps/luajit/src/lj_vm.S -o build/lj_vm.o
@REM cosmocc -c unwind.c -o build/unwind.o

@REM cosmocc -O2 -c deps/luajit/src/ljamalg.c -I deps/luajit/src -o build/ljamalg.o -DLUAJIT_OS=5 -DLUAJIT_NO_UNWIND -DLUA_USE_ASSERT -DLJ_TARGET_HAS_GETENTROPY=1 -fno-expensive-optimizations -fno-caller-saves

@REM cosmocc -O -c deps/luajit/src/ljamalg.c -I deps/luajit/src -o build/ljamalg.o -DLUAJIT_OS=5 -DLUAJIT_NO_UNWIND -DLUA_USE_ASSERT -DLJ_TARGET_HAS_GETENTROPY=1
@REM cosmocc -O    deps/luajit/src/luajit.c -I deps/luajit/src -o luajit.exe  -DLUAJIT_OS=5 -DLUAJIT_NO_UNWIND -DLUA_USE_ASSERT -DLJ_TARGET_HAS_GETENTROPY=1 build/ljamalg.o build/unwind.o deps/luajit/src/lj_vm.o

@REM cosmocc -c deps/luajit/src/ljamalg.c -I deps/luajit/src -o build/ljamalg.o -DLUAJIT_OS=5 -DLUAJIT_NO_UNWIND -DLJ_TARGET_HAS_GETENTROPY=1
@REM cosmocc deps/luajit/src/luajit.c -I deps/luajit/src -o luajit.exe  -DLUAJIT_OS=5 -DLUAJIT_NO_UNWIND -DLJ_TARGET_HAS_GETENTROPY=1 build/ljamalg.o build/unwind.o deps/luajit/src/lj_vm.o

@REM cosmocc -O2 -c deps/luajit/src/ljamalg.c -I deps/luajit/src -o build/ljamalg.o -DLUAJIT_OS=5 -DLUAJIT_NO_UNWIND -DLJ_TARGET_HAS_GETENTROPY=1
@REM cosmocc -O2 -c deps/luajit/src/luajit.c -I deps/luajit/src -o build/luajit.o  -DLUAJIT_OS=5

cosmoc++ -c clib_syms.cpp -o build/clib_syms.o
cosmoc++ -c ninja_api.cpp -o build/ninja_api.o -Ideps/ninja/src  -Ideps/LuaJIT/src -std=c++20
cosmoc++ -o luajit.exe build/luajit.o build/clib_syms.o build/ljamalg.o build/unwind.o build/ninja_api.o deps/luajit/src/lj_vm.o -L build -lninja