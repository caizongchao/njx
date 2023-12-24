#include "ljx.h"
#include "ljxx.h"
#include "ioxx.h"

void ninja_initialize();

int main(int argc, char ** argv) {
    ninja_initialize();
    
    $L([&]() {
        lua_table package = $L["package"]; {
            package.def("path", "./?.lua;/zip/?.lua");
        }

        auto _G = $L._G(); {
            _G.def("__registry", $L._R());
        }
    }).open();

    $L.require("ljx");
    
    const char * script = (argc > 1) ? argv[1] : "build.lua";

    file_exists(script) || fatal("script '%s' not found", script);
       
    $L.run(afile(script).read());

    return 0;
}