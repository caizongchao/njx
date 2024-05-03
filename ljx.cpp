#include "ljx.h"
#include "ljxx.h"
#include "ioxx.h"
#include "spawn.h"
#include "fnmatch.h"

#include <chrono>
#include <filesystem>

namespace fs = std::filesystem;

void ninja_initialize();
void ninja_finalize();

struct ninja_initializer {
    ninja_initializer() {
        ninja_initialize();
    }

    ~ninja_initializer() {
        ninja_finalize();
    }
};

extern fs::path $build_script;
extern bool $reload_build_script;

extern "C" char * GetProgramExecutableName(void);

int main(int argc, char ** argv) {
    { static ninja_initializer _; }

    $L([&]() {
        lua_table package = $L["package"]; {
            package.def("path", "./?.lua;/zip/?.lua");
        }

        auto _G = $L._G();

        _G
            .def("__registry", $L._R())
            .def(
                "clock", (lua_CFunction)[](lua_State * L)->int {
                    lua_pushinteger(L, std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count()); return 1;
                })
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
                        // ok = posix_spawnattr_setflags(&attrs, POSIX_SPAWN_SETSIGMASK);
                        // ok = posix_spawnattr_setsigmask(&attrs, nullptr);
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
                })
            .def(
                "cexec", (lua_CFunction)[](lua_State * L)->int {
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
                        // ok = posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0);
                        // ok = posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
                    }

                    posix_spawnattr_t attrs; {
                        ok = posix_spawnattr_init(&attrs);
                        // ok = posix_spawnattr_setflags(&attrs, POSIX_SPAWN_SETSIGMASK);
                        // ok = posix_spawnattr_setsigmask(&attrs, nullptr);
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

        lua_table($L["table"])
            .def(
                "tag", (lua_CFunction)[](lua_State * L) {
                    int argc = $L.argc();

                    if(argc == 0) return 0;

                    lua_table t = $L.argv(0); if(argc > 1) {
                        t->tag = $L.argv(1); $L.push(t);
                    }
                    else {
                        $L.push(t->tag);
                    }

                    return 1;
                });

        $L.load("ljx", "ninja");

        lua_table($L["path"])
            .def("fnmatch", [](const char * pattern, const char * path) {
                return fnmatch(pattern, path, 0) == 0;
            })
            .def("ifnmatch", [](const char * pattern, const char * path) {
                return fnmatch(pattern, path, FNM_CASEFOLD) == 0;
            });

        lua_table($L["fs"])
            .def("is_uptodate", [](const char * dst, const char * src) {
                std::error_code ec;

                if(!file_exists(dst)) return false;

                auto dst_time = std::filesystem::last_write_time(dst, ec);

                if(ec) fatal("failed to get last write time of '%s': %s", dst, ec.message().c_str());

                auto src_time = std::filesystem::last_write_time(src, ec);

                if(ec) fatal("failed to get last write time of '%s': %s", src, ec.message().c_str());

                return src_time == dst_time;
            })
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
            .def("copy_file", [](const char * dst, const char * src) {
                std::error_code ec;

                std::filesystem::copy_file(src, dst, std::filesystem::copy_options::overwrite_existing, ec);

                if(ec) fatal("failed to copy '%s' to '%s': %s", src, dst, ec.message().c_str());
            })
            .def("update_file", [](const char * dst, const char * src) {
                std::error_code ec;

                std::filesystem::copy_file(src, dst, std::filesystem::copy_options::update_existing, ec);

                if(ec) fatal("failed to update '%s' with '%s': %s", dst, src, ec.message().c_str());
            })
            .def("update_mtime", [](const char * dst, const char * src) {
                std::error_code ec;

                auto src_time = std::filesystem::last_write_time(src, ec);

                if(ec) fatal("failed to get last write time of '%s': %s", src, ec.message().c_str());

                std::filesystem::last_write_time(dst, src_time, ec);

                if(ec) fatal("failed to update last write time of '%s': %s", dst, ec.message().c_str());
            })
            .def("copy_dir", [](const char * dst, const char * src) {
                std::error_code ec;

                std::filesystem::copy(src, dst, std::filesystem::copy_options::none, ec);

                if(ec) fatal("failed to copy '%s' to '%s': %s", src, dst, ec.message().c_str());
            })
            .def("copy_dir_recursive", [](const char * dst, const char * src) {
                std::error_code ec;

                std::filesystem::copy(src, dst, std::filesystem::copy_options::recursive, ec);

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

    $build_script = (argc > 1) ? argv[1] : "build.lua"; if(!$build_script.is_absolute()) {
        $build_script = fs::current_path() / $build_script;
    }
    
    $build_script = $build_script.lexically_normal();

    fs::exists($build_script) || fatal("%s not found\n", $build_script.c_str());

    $L.run(afile($build_script.c_str()).read());

    if($reload_build_script) {
        char ** xargv = (char **)alloca((argc + 1) * sizeof(char *)); {
            for(int i = 0; i < argc; i++) {
                xargv[i] = argv[i];
            }

            xargv[argc] = nullptr;
        }

        execvp(GetProgramExecutableName(), xargv);

        printf("failed to reload build script: %d\n", errno);
    }

    return 0;
}