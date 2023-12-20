#include "ljx.h"
#include "ljxx.h"
#include "ioxx.h"

int main(int argc, char ** argv) {
    $L([&]() {
        lua_table package = $L["package"]; {
            // package.path
            std::string s = (const char *)package["path"]; {
                s += "*/?.lua;";
            }
            package.def("path", s.c_str());
        }

        auto _G = $L._G(); {
            _G.def("registry", $L._R());

            _G.def("arguments", $L.arguments());

            _G.def(
                "register", (lua_CFunction)[](lua_State * L)->int {
                    lua_pushinteger(L, luaL_ref(L, -2)); return 1;
                });

            _G.def(
                "unregister", (lua_CFunction)[](lua_State * L)->int {
                    luaL_unref(L, -2, lua_tointeger(L, -1)); return 0;
                });
        }
    });

    // $L([&]() {
    //     lua_table package = $L["package"]; {
    //         // package.path
    //         std::string s = (const char *)package["path"]; {
    //             s += "*/?.lua;";
    //         }
    //         package.def("path", s.c_str());
    //     }

    //     auto _G = $L._G(); {
    //         _G.def("registry", $L._R());

    //         _G.def("arguments", $L.arguments());

    //         _G.def(
    //             "register", (lua_CFunction)[](lua_State * L)->int {
    //                 lua_pushinteger(L, luaL_ref(L, -2)); return 1;
    //             });

    //         _G.def(
    //             "unregister", (lua_CFunction)[](lua_State * L)->int {
    //                 luaL_unref(L, -2, lua_tointeger(L, -1)); return 0;
    //             });
    //     }
    // }).open();

    // $L.run(dfile("a.lua"));

    printf("done\n");

    return 0;
}