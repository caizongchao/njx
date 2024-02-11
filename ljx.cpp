#include "ljx.h"
#include "ljxx.h"
#include "ioxx.h"
#include "spawn.h"

#include <filesystem>

void ninja_initialize();

int main(int argc, char ** argv) {
    ninja_initialize();

    $L([&]() {
        lua_table package = $L["package"]; {
            package.def("path", "./?.lua;/zip/?.lua");
        }

        auto _G = $L._G();

        _G
            .def("__registry", $L._R())
            .def(
                "exec", (lua_CFunction)[](lua_State * L)->int {
                    int argc = lua_gettop(L); {
                        if(argc < 1) {
                            fatal("exec: expected at least 1 argument, got %d", argc); return 0;
                        }
                    }

                    auto argv = (const char **)alloca((argc + 1) * sizeof(char *)); {
                        for(int i = 0; i < argc; i++) {
                            argv[i] = (char *)luaL_checkstring(L, i + 1);
                        }

                        argv[argc] = nullptr;
                    }

                    pid_t pid {-1};

                    posix_spawn_file_actions_t actions; {
                        ok = posix_spawn_file_actions_init(&actions);
                        ok = posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0);
                        ok = posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
                    }

                    posix_spawnattr_t attrs; {
                        ok = posix_spawnattr_init(&attrs);
                        ok = posix_spawnattr_setflags(&attrs, POSIX_SPAWN_SETSIGMASK);
                        ok = posix_spawnattr_setsigmask(&attrs, nullptr);
                    }

                    int r = posix_spawnp(&pid, argv[0], &actions, &attrs, (char * const *)argv, nullptr); {
                        if(r != 0) {
                            fatal("failed to spawn '%s': %s", argv[0], strerror(r)); return 0;
                        }
                    }

                    int status;

                    waitpid(pid, &status, 0);

                    lua_pushinteger(L, status);

                    return 1;
                });

        $L.load("ljx", "ninja");

        lua_table($L["fs"])
            .def("touch", [](const char * path) {
                std::error_code ec;

                if(file_exists(path)) {
                    // update the file's last write time
                    std::filesystem::file_time_type now = std::filesystem::file_time_type::clock::now();

                    std::filesystem::last_write_time(path, now, ec);

                    if(ec) fatal("failed to update file '%s': %s", path, ec.message().c_str());
                }

                std::filesystem::create_directories(std::filesystem::path(path).parent_path(), ec);

                if(ec) fatal("failed to create directory '%s': %s", path, ec.message().c_str());

                auto f = fopen(path, "w"); {
                    if(!f) fatal("failed to create file '%s'", path);
                }

                fclose(f);
            })
            .def("copy", [](const char * dst, const char * src, const char * opts) {
                std::filesystem::copy_options flags = std::filesystem::copy_options::none; {
                    if(opts) {
                        for(const char * p = opts; *p; p++) {
                            switch(*p) {
                                case 'f': flags |= std::filesystem::copy_options::overwrite_existing; break;
                                case 'd': flags |= std::filesystem::copy_options::directories_only; break;
                                case 'i': flags |= std::filesystem::copy_options::skip_symlinks; break;
                                case 'l': flags |= std::filesystem::copy_options::create_symlinks; break;
                                case 'k': flags |= std::filesystem::copy_options::copy_symlinks; break;
                                case 'u': flags |= std::filesystem::copy_options::update_existing; break;
                                case 'r': flags |= std::filesystem::copy_options::recursive; break;
                                default: fatal("invalid option '%c'", *p);
                            }
                        }
                    }
                }

                std::error_code ec;

                std::filesystem::copy(src, dst, flags, ec);

                if(ec) fatal("failed to copy '%s' to '%s': %s", src, dst, ec.message().c_str());
            })
            .def("mkdir", [](const char * path) {
                std::error_code ec;

                std::filesystem::create_directories(path, ec);

                if(ec) fatal("failed to create directory '%s': %s", path, ec.message().c_str());
            })
            .def("rmdir", [](const char * path) {
                std::error_code ec;

                std::filesystem::remove_all(path, ec);

                if(ec) fatal("failed to remove directory '%s': %s", path, ec.message().c_str());
            })
            .def("remove_all_in", [](const char * path) {
                std::error_code ec;

                std::filesystem::directory_iterator it(path, ec); {
                    if(ec) return;
                }

                for(auto & p : it) {
                    std::filesystem::remove_all(p, ec);

                    if(ec) fatal("failed to remove '%s': %s", p.path().c_str(), ec.message().c_str());
                }
            })
            .def("rm", [](const char * path) {
                std::error_code ec;

                std::filesystem::remove(path, ec);

                if(ec) fatal("failed to remove file '%s': %s", path, ec.message().c_str());
            });
    }).open();

    const char * script = (argc > 1) ? argv[1] : "build.lua";

    file_exists(script) || fatal("script '%s' not found", script);

    $L.run(afile(script).read());

    return 0;
}