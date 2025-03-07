cosmocc -c deps/luajit/src/lib_aux.c -I deps/luajit/src -o build/lib_aux.o
cosmocc -c deps/luajit/src/lib_base.c -I deps/luajit/src -o build/lib_base.o
cosmocc -c deps/luajit/src/lib_bit.c -I deps/luajit/src -o build/lib_bit.o
cosmocc -c deps/luajit/src/lib_buffer.c -I deps/luajit/src -o build/lib_buffer.o
cosmocc -c deps/luajit/src/lib_debug.c -I deps/luajit/src -o build/lib_debug.o
cosmocc -c deps/luajit/src/lib_ffi.c -I deps/luajit/src -o build/lib_ffi.o
cosmocc -c deps/luajit/src/lib_init.c -I deps/luajit/src -o build/lib_init.o
cosmocc -c deps/luajit/src/lib_io.c -I deps/luajit/src -o build/lib_io.o
cosmocc -c deps/luajit/src/lib_jit.c -I deps/luajit/src -o build/lib_jit.o
cosmocc -c deps/luajit/src/lib_math.c -I deps/luajit/src -o build/lib_math.o
cosmocc -c deps/luajit/src/lib_os.c -I deps/luajit/src -o build/lib_os.o
cosmocc -c deps/luajit/src/lib_package.c -I deps/luajit/src -o build/lib_package.o
cosmocc -c deps/luajit/src/lib_string.c -I deps/luajit/src -o build/lib_string.o
cosmocc -c deps/luajit/src/lib_table.c -I deps/luajit/src -o build/lib_table.o
cosmocc -c deps/luajit/src/lj_alloc.c -I deps/luajit/src -o build/lj_alloc.o
cosmocc -c deps/luajit/src/lj_api.c -I deps/luajit/src -o build/lj_api.o
cosmocc -c deps/luajit/src/lj_asm.c -I deps/luajit/src -o build/lj_asm.o
cosmocc -c deps/luajit/src/lj_assert.c -I deps/luajit/src -o build/lj_assert.o
cosmocc -c deps/luajit/src/lj_bc.c -I deps/luajit/src -o build/lj_bc.o
cosmocc -c deps/luajit/src/lj_bcread.c -I deps/luajit/src -o build/lj_bcread.o
cosmocc -c deps/luajit/src/lj_bcwrite.c -I deps/luajit/src -o build/lj_bcwrite.o
cosmocc -c deps/luajit/src/lj_buf.c -I deps/luajit/src -o build/lj_buf.o
cosmocc -c deps/luajit/src/lj_carith.c -I deps/luajit/src -o build/lj_carith.o
cosmocc -c deps/luajit/src/lj_ccall.c -I deps/luajit/src -o build/lj_ccall.o
cosmocc -c deps/luajit/src/lj_ccallback.c -I deps/luajit/src -o build/lj_ccallback.o
cosmocc -c deps/luajit/src/lj_cconv.c -I deps/luajit/src -o build/lj_cconv.o
cosmocc -c deps/luajit/src/lj_cdata.c -I deps/luajit/src -o build/lj_cdata.o
cosmocc -c deps/luajit/src/lj_char.c -I deps/luajit/src -o build/lj_char.o
cosmocc -c deps/luajit/src/lj_clib.c -I deps/luajit/src -o build/lj_clib.o
cosmocc -c deps/luajit/src/lj_cparse.c -I deps/luajit/src -o build/lj_cparse.o
cosmocc -c deps/luajit/src/lj_crecord.c -I deps/luajit/src -o build/lj_crecord.o
cosmocc -c deps/luajit/src/lj_ctype.c -I deps/luajit/src -o build/lj_ctype.o
cosmocc -c deps/luajit/src/lj_debug.c -I deps/luajit/src -o build/lj_debug.o
cosmocc -c deps/luajit/src/lj_dispatch.c -I deps/luajit/src -o build/lj_dispatch.o
cosmocc -c deps/luajit/src/lj_err.c -I deps/luajit/src -o build/lj_err.o
cosmocc -c deps/luajit/src/lj_ffrecord.c -I deps/luajit/src -o build/lj_ffrecord.o
cosmocc -c deps/luajit/src/lj_func.c -I deps/luajit/src -o build/lj_func.o
cosmocc -c deps/luajit/src/lj_gc.c -I deps/luajit/src -o build/lj_gc.o
cosmocc -c deps/luajit/src/lj_gdbjit.c -I deps/luajit/src -o build/lj_gdbjit.o
cosmocc -c deps/luajit/src/lj_ir.c -I deps/luajit/src -o build/lj_ir.o
cosmocc -c deps/luajit/src/lj_lex.c -I deps/luajit/src -o build/lj_lex.o
cosmocc -c deps/luajit/src/lj_lib.c -I deps/luajit/src -o build/lj_lib.o
cosmocc -c deps/luajit/src/lj_load.c -I deps/luajit/src -o build/lj_load.o
cosmocc -c deps/luajit/src/lj_mcode.c -I deps/luajit/src -o build/lj_mcode.o
cosmocc -c deps/luajit/src/lj_meta.c -I deps/luajit/src -o build/lj_meta.o
cosmocc -c deps/luajit/src/lj_obj.c -I deps/luajit/src -o build/lj_obj.o
cosmocc -c deps/luajit/src/lj_opt_dce.c -I deps/luajit/src -o build/lj_opt_dce.o
cosmocc -c deps/luajit/src/lj_opt_fold.c -I deps/luajit/src -o build/lj_opt_fold.o
cosmocc -c deps/luajit/src/lj_opt_loop.c -I deps/luajit/src -o build/lj_opt_loop.o
cosmocc -c deps/luajit/src/lj_opt_mem.c -I deps/luajit/src -o build/lj_opt_mem.o
cosmocc -c deps/luajit/src/lj_opt_narrow.c -I deps/luajit/src -o build/lj_opt_narrow.o
cosmocc -c deps/luajit/src/lj_opt_sink.c -I deps/luajit/src -o build/lj_opt_sink.o
cosmocc -c deps/luajit/src/lj_opt_split.c -I deps/luajit/src -o build/lj_opt_split.o
cosmocc -c deps/luajit/src/lj_parse.c -I deps/luajit/src -o build/lj_parse.o
cosmocc -c deps/luajit/src/lj_prng.c -I deps/luajit/src -o build/lj_prng.o
cosmocc -c deps/luajit/src/lj_profile.c -I deps/luajit/src -o build/lj_profile.o
cosmocc -c deps/luajit/src/lj_record.c -I deps/luajit/src -o build/lj_record.o
cosmocc -c deps/luajit/src/lj_serialize.c -I deps/luajit/src -o build/lj_serialize.o
cosmocc -c deps/luajit/src/lj_snap.c -I deps/luajit/src -o build/lj_snap.o
cosmocc -c deps/luajit/src/lj_state.c -I deps/luajit/src -o build/lj_state.o
cosmocc -c deps/luajit/src/lj_str.c -I deps/luajit/src -o build/lj_str.o
cosmocc -c deps/luajit/src/lj_strfmt.c -I deps/luajit/src -o build/lj_strfmt.o
cosmocc -c deps/luajit/src/lj_strfmt_num.c -I deps/luajit/src -o build/lj_strfmt_num.o
cosmocc -c deps/luajit/src/lj_strscan.c -I deps/luajit/src -o build/lj_strscan.o
cosmocc -c deps/luajit/src/lj_tab.c -I deps/luajit/src -o build/lj_tab.o
cosmocc -c deps/luajit/src/lj_trace.c -I deps/luajit/src -o build/lj_trace.o
cosmocc -c deps/luajit/src/lj_udata.c -I deps/luajit/src -o build/lj_udata.o
cosmocc -c deps/luajit/src/lj_vmevent.c -I deps/luajit/src -o build/lj_vmevent.o
cosmocc -c deps/luajit/src/lj_vmmath.c -I deps/luajit/src -o build/lj_vmmath.o
cosmocc -c deps/luajit/src/luajit.c -I deps/luajit/src -o build/luajit.o