import child_process from 'child_process';
import fs from 'fs';
import Watcher from 'watcher';

function run(cmd) {
    return new Promise((resolve, reject) => {
        let rc = 0; child_process.exec(cmd, (error, stdout, stderr) => {
            if (stdout) console.log(stdout);
            if (stderr) console.log(stderr);

            resolve(rc == 0);
        }).on('exit', (code) => { rc = code; });
    });
}

var OPT = "-O2"

var ninja_src = [
    'deps/ninja/src/build.cc',
    'deps/ninja/src/build_log.cc',
    'deps/ninja/src/clean.cc',
    'deps/ninja/src/clparser.cc',
    'deps/ninja/src/debug_flags.cc',
    'deps/ninja/src/depfile_parser.cc',
    'deps/ninja/src/deps_log.cc',
    'deps/ninja/src/disk_interface.cc',
    'deps/ninja/src/dyndep.cc',
    'deps/ninja/src/dyndep_parser.cc',
    'deps/ninja/src/edit_distance.cc',
    'deps/ninja/src/eval_env.cc',
    'deps/ninja/src/getopt.c',
    'deps/ninja/src/graph.cc',
    'deps/ninja/src/graphviz.cc',
    'deps/ninja/src/json.cc',
    'deps/ninja/src/lexer.cc',
    'deps/ninja/src/line_printer.cc',
    'deps/ninja/src/manifest_parser.cc',
    'deps/ninja/src/metrics.cc',
    'deps/ninja/src/missing_deps.cc',
    'deps/ninja/src/ninja.cc',
    'deps/ninja/src/parser.cc',
    'deps/ninja/src/state.cc',
    'deps/ninja/src/status.cc',
    'deps/ninja/src/string_piece_util.cc',
    'deps/ninja/src/subprocess-posix.cc',
    'deps/ninja/src/util.cc',
    'deps/ninja/src/version.cc',
    // 'deps/ninja/src/includes_normalize-win32.cc',
    // 'deps/ninja/src/minidump-win32.cc',
    // 'deps/ninja/src/msvc_helper-win32.cc',
    // 'deps/ninja/src/msvc_helper_main-win32.cc',
    // 'deps/ninja/src/subprocess-win32.cc',
];

var ninja_build_dir = 'build/ninja/'; {
    if (!fs.existsSync(ninja_build_dir)) fs.mkdirSync(ninja_build_dir);
}

var ninja_cc = `cosmoc++ -std=c++20 ${OPT} -Ideps/ninja/src -D__BUILD_LIB__ -c `

function is_up_to_date(src, dst) {
    try {
        var src_mtime = fs.statSync(src).mtimeMs;
        var dst_mtime = fs.statSync(dst).mtimeMs;

        return src_mtime < dst_mtime;
    }
    catch (e) {
        return false;
    }
}

async function make_libninja() {
    var dirty = false;

    var objs = [];

    for (var i = 0; i < ninja_src.length; i++) {
        var s = ninja_src[i];

        // extract file name of src
        var fname = s.substring(s.lastIndexOf('/') + 1);

        var d = ninja_build_dir + fname + '.o'; {
            objs.push(d);
        }

        if (is_up_to_date(s, d)) continue;

        console.log('cc ' + s);

        var r = await run(ninja_cc + s + ' -o ' + d); if (!r) {
            console.log('compile ' + s + ' failed'); return r;
        }

        dirty = true;
    }

    if (dirty) {
        await run('cosmoar build/libninja.a ' + objs.join(' '));
        console.log('make libninja.a done');
    }

    return dirty;
}

var luajit_src = [
    "deps/luajit/src/lj_assert.c",
    "deps/luajit/src/lj_gc.c",
    "deps/luajit/src/lj_err.c",
    "deps/luajit/src/lj_char.c",
    "deps/luajit/src/lj_bc.c",
    "deps/luajit/src/lj_obj.c",
    "deps/luajit/src/lj_buf.c",
    "deps/luajit/src/lj_str.c",
    "deps/luajit/src/lj_tab.c",
    "deps/luajit/src/lj_func.c",
    "deps/luajit/src/lj_udata.c",
    "deps/luajit/src/lj_meta.c",
    "deps/luajit/src/lj_debug.c",
    "deps/luajit/src/lj_prng.c",
    "deps/luajit/src/lj_state.c",
    "deps/luajit/src/lj_dispatch.c",
    "deps/luajit/src/lj_vmevent.c",
    "deps/luajit/src/lj_vmmath.c",
    "deps/luajit/src/lj_strscan.c",
    "deps/luajit/src/lj_strfmt.c",
    "deps/luajit/src/lj_strfmt_num.c",
    "deps/luajit/src/lj_serialize.c",
    "deps/luajit/src/lj_api.c",
    "deps/luajit/src/lj_profile.c",
    "deps/luajit/src/lj_lex.c",
    "deps/luajit/src/lj_parse.c",
    "deps/luajit/src/lj_bcread.c",
    "deps/luajit/src/lj_bcwrite.c",
    "deps/luajit/src/lj_load.c",
    "deps/luajit/src/lj_ctype.c",
    "deps/luajit/src/lj_cdata.c",
    "deps/luajit/src/lj_cconv.c",
    "deps/luajit/src/lj_ccall.c",
    "deps/luajit/src/lj_ccallback.c",
    "deps/luajit/src/lj_carith.c",
    "deps/luajit/src/lj_clib.c",
    "deps/luajit/src/lj_cparse.c",
    "deps/luajit/src/lj_lib.c",
    "deps/luajit/src/lj_ir.c",
    "deps/luajit/src/lj_opt_mem.c",
    "deps/luajit/src/lj_opt_fold.c",
    "deps/luajit/src/lj_opt_narrow.c",
    "deps/luajit/src/lj_opt_dce.c",
    "deps/luajit/src/lj_opt_loop.c",
    "deps/luajit/src/lj_opt_split.c",
    "deps/luajit/src/lj_opt_sink.c",
    "deps/luajit/src/lj_mcode.c",
    "deps/luajit/src/lj_snap.c",
    "deps/luajit/src/lj_record.c",
    "deps/luajit/src/lj_crecord.c",
    "deps/luajit/src/lj_ffrecord.c",
    "deps/luajit/src/lj_asm.c",
    "deps/luajit/src/lj_trace.c",
    "deps/luajit/src/lj_gdbjit.c",
    "deps/luajit/src/lj_alloc.c",
    "deps/luajit/src/lib_aux.c",
    "deps/luajit/src/lib_base.c",
    "deps/luajit/src/lib_math.c",
    "deps/luajit/src/lib_string.c",
    "deps/luajit/src/lib_table.c",
    "deps/luajit/src/lib_io.c",
    "deps/luajit/src/lib_os.c",
    "deps/luajit/src/lib_package.c",
    "deps/luajit/src/lib_debug.c",
    "deps/luajit/src/lib_bit.c",
    "deps/luajit/src/lib_jit.c",
    "deps/luajit/src/lib_ffi.c",
    "deps/luajit/src/lib_buffer.c",
    "deps/luajit/src/lib_init.c",
    // "deps/luajit/src/luajit.c",
];

var luajit_build_dir = 'build/luajit/'; {
    if (!fs.existsSync(luajit_build_dir)) fs.mkdirSync(luajit_build_dir);
}

var luajit_cc = `cosmocc ${OPT} -c -Ideps/luajit/src -DLUAJIT_OS=5 -DLUAJIT_NO_UNWIND -DLJ_TARGET_HAS_GETENTROPY=1 `


async function make_libluajit() {
    var dirty = false;

    var objs = [];

    for (var i = 0; i < luajit_src.length; i++) {
        var s = luajit_src[i];

        // extract file name of src
        var fname = s.substring(s.lastIndexOf('/') + 1);

        var d = luajit_build_dir + fname + '.o'; {
            objs.push(d);
        }

        if (is_up_to_date(s, d)) continue;

        console.log('cc ' + s);

        var r = await run(luajit_cc + s + ' -o ' + d); if (!r) {
            console.log('compile ' + s + ' failed'); return r;
        }

        dirty = true;
    }

    if (dirty) {
        await run('cosmoar build/libluajit.a ' + objs.join(' '));
        console.log('make libluajit.a done');
    }

    return dirty;
}

var ljx_src = [
    "ninja_api.cpp",
    "unwind.cpp",
    "ljx.cpp"
]

var libljx_build_dir = 'build/ljx/'; {
    if (!fs.existsSync(libljx_build_dir)) fs.mkdirSync(libljx_build_dir);
}

var libljx_cc = `cosmoc++ -std=c++20 ${OPT} -c -Ideps/luajit/src -Ideps/ninja/src -DLUAJIT_OS=5 `

async function make_libljx() {
    var dirty = false;

    var objs = [];

    for (var i = 0; i < ljx_src.length; i++) {
        var s = ljx_src[i];

        // extract file name of src
        var fname = s.substring(s.lastIndexOf('/') + 1);

        var d = libljx_build_dir + fname + '.o'; {
            objs.push(d);
        }

        if (is_up_to_date(s, d)) continue;

        console.log('cc ' + s);

        var r = await run(libljx_cc + s + ' -o ' + d); if (!r) {
            console.log('compile ' + s + ' failed'); return r;
        }

        dirty = true;
    }

    if (dirty) {
        await run('cosmoar build/libljx.a ' + objs.join(' '));
        console.log('make libljx.a done');
    }

    return dirty;
}

var ljx_build_dir = 'bin/'; {
    if (!fs.existsSync(ljx_build_dir)) fs.mkdirSync(ljx_build_dir);
}

async function make_ljx() {
    var b1 = await make_libninja();
    var b2 = await make_libluajit();
    var b3 = await make_libljx();

    if (b1 || b2 || b3) {
        console.log('linking ljx.exe');
        
        let r = await run('cosmoc++ -Wl,--start-group -u ninja_initialize -L build lj_vm.o -lluajit -lljx -lninja -Wl,--end-group -o ' + ljx_build_dir + 'ljx.exe');

        if(r) {
            await run('zip bin/ljx.exe ljx.lua ninja.lua')
        }
    }
}

const watcher = new Watcher('./', { recursive: true, debounce: 300 });

var compiling = false;

watcher.on('change', async (fpath) => {
    if (compiling) return;

    if (fpath.endsWith('.c') || fpath.endsWith('.cpp') || fpath.endsWith('.cc') || fpath.endsWith('.h')) {
        compiling = true;

        await make_ljx();

        console.log('done');

        compiling = false;
    }
});

async function main() {
    await make_ljx();
}

main()
    .then(() => {
        console.log('Watching...');
    })
    .catch((e) => { console.log(e); });
