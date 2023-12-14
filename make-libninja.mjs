import child_process from 'child_process';
import fs from 'fs';

function run(cmd) {
    return new Promise((resolve, reject) => {
        child_process.exec(cmd, (error, stdout, stderr) => {
            // if (error) console.log(error);
            if (stderr) console.log(stderr);
            // if (stdout) console.log(stdout);
        }).on('exit', (code) => {
            if (code != 0) reject(false); else resolve(true);
        });
    });
}

var src = [
    'deps/ninja/src/build.cc',
    'deps/ninja/src/build_log.cc',
    'deps/ninja/src/clean.cc',
    'deps/ninja/src/clparser.cc',
    'deps/ninja/src/debug_flags.cc',
    'deps/ninja/src/depfile_parser.cc',
    'deps/ninja/src/depfile_parser.in.cc',
    'deps/ninja/src/deps_log.cc',
    'deps/ninja/src/disk_interface.cc',
    'deps/ninja/src/dyndep.cc',
    'deps/ninja/src/dyndep_parser.cc',
    'deps/ninja/src/edit_distance.cc',
    'deps/ninja/src/eval_env.cc',
    'deps/ninja/src/getopt.c',
    'deps/ninja/src/graph.cc',
    'deps/ninja/src/graphviz.cc',
    'deps/ninja/src/hash_collision_bench.cc',
    'deps/ninja/src/json.cc',
    'deps/ninja/src/lexer.cc',
    'deps/ninja/src/lexer.in.cc',
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

var build_dir = 'build/ninja/'; {
    if (!fs.existsSync(build_dir)) fs.mkdirSync(build_dir);
}


var cc = 'cosmoc++ -O2 -c -Ideps/ninja/src '

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

    for (var i = 0; i < src.length; i++) {
        var s = src[i];

        // extract file name of src
        var fname = s.substring(s.lastIndexOf('/') + 1);

        var d = build_dir + fname + '.o'; {
            objs.push(d);
        }

        if (is_up_to_date(s, d)) continue;

        console.log('cc ' + s);

        var r = await run(cc + s + ' -o ' + d); if (!r) {
            console.log('compile ' + s + ' failed'); return;
        }

        dirty = true;
    }

    if (!dirty) { console.log('libninja.a up to date'); return; }

    await run('cosmoar build/libninja.a ' + objs.join(' '));

    console.log('make libninja.a done');
}

make_libninja();
