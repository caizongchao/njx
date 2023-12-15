// using node watcher moduel to monitor the file changes of the project
// while .dpr file is changed, the build.js will be triggered to compile
// the .dpr file by invoking dcc32.exe

import Watcher from 'watcher';
import { exec } from 'child_process';

const watcher = new Watcher('./', {recursive: true, debounce: 500});

var compiling = false;

watcher.on('change', fpath => {
    if (compiling) return;

    if (fpath.endsWith('.c') || fpath.endsWith('.cpp') || fpath.endsWith('.h') || fpath.endsWith('.cmd')) {
        compiling = true; console.log('making...');

        const child = exec(`make.cmd`, (error, stdout, stderr) => {
            // if (error) { console.log(error); return; }
            if (stdout) console.log(stdout);
            if (stderr) console.log(stderr);

            console.log('done'); compiling = false;
        });
    }
});

console.log('Watching...');