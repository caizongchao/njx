#include <state.h>
#include <eval_env.h>
#include <build.h>
#include <clean.h>
#include <disk_interface.h>
#include <build_log.h>
#include <deps_log.h>
#include <status.h>
#include <metrics.h>
#include <util.h>

#include "ljx.h"
#include "ljxx.h"

#include <filesystem>

#include <ftw.h>

namespace fs = std::filesystem;

struct reftable {
    static constexpr uint32_t NOFREE_REF = (uint32_t)-1;

    uint32_t size; uint32_t flist; lua_value table[0];

    static reftable * from(lua_table t) { return (reftable *)t.array(); }

    int ref(lua_value const & x) {
        int r; if(flist == NOFREE_REF) {
            r = size; table[size++] = x;
        }
        else {
            r = flist; flist = (uintptr_t &)(table[flist]); table[r] = x;
        }
        return r + 1;
    }

    void unref(uint32_t i) {
        --i; ((uintptr_t &)(table[i])) = flist; flist = i;
    }

    lua_value & operator[](uint32_t i) const { return (lua_value &)table[i - 1]; }
};

lua_gcptr reftable_new(uint32_t size) {
    auto t = lua_table::make(size, 0);
    
    auto rtab = reftable::from(t); rtab->size = 0; rtab->flist = reftable::NOFREE_REF;
    
    return {t.value};
}

int reftable_ref(lua_table t, lua_gcptr x) {
    auto rtab = reftable::from(t); return rtab->ref(x.tvalue());
}

void reftable_unref(lua_table t, int r) {
    auto rtab = reftable::from(t); return rtab->unref(r);
}

static const char * DEFAULT_BUILD_DIR = "build";

struct NinjaMain : public BuildLogUser {
    /// Command line used to run Ninja.
    const char * ninja_command_;

    /// Build configuration set from flags (e.g. parallelism).
    const BuildConfig & config_;

    /// Loaded state (rules, nodes).
    State state_;

    /// Functions for accessing the disk.
    RealDiskInterface disk_interface_;

    /// The build directory, used for storing the build log etc.
    std::string build_dir_;

    BuildLog build_log_;
    DepsLog deps_log_;

    int64_t start_time_millis_;

    NinjaMain(const char * ninja_command, const BuildConfig & config);

    /// Get the Node for a given command-line path, handling features like
    /// spell correction.
    Node * CollectTarget(const char * cpath, std::string * err);

    /// CollectTarget for all command-line arguments, filling in \a targets.
    bool CollectTargetsFromArgs(int argc, char * argv[],
        std::vector<Node *> * targets, std::string * err);

    /// Open the build log.
    /// @return false on error.
    bool OpenBuildLog(bool recompact_only = false);

    /// Open the deps log: load it, then open for writing.
    /// @return false on error.
    bool OpenDepsLog(bool recompact_only = false);

    /// Ensure the build directory exists, creating it if necessary.
    /// @return false on error.
    bool EnsureBuildDirExists();

    /// Rebuild the manifest, if necessary.
    /// Fills in \a err on error.
    /// @return true if the manifest was rebuilt.
    bool RebuildManifest(const char * input_file, std::string * err, Status * status);

    /// Build the targets listed on the command line.
    /// @return an exit code.
    int RunBuild(int argc, char ** argv, Status * status);

    /// Dump the output requested by '-d stats'.
    void DumpMetrics();

    virtual bool IsPathDead(StringPiece s) const;
};

static std::string $buf;
static BuildConfig $config;

static NinjaMain $ninja(nullptr, $config);

static State & $state = $ninja.state_;
static BindingEnv * $env = &$state.bindings_;

static bool ninja_evalstring_read(const char * s, EvalString * eval, bool path);

extern int GuessParallelism();

extern "C" {

void ninja_test(const char * msg) {
    printf("test done\n");
}

void * ninja_config_get() { return (void *)&$config; }

void ninja_config_apply() {
    if($config.parallelism == 0) $config.parallelism = GuessParallelism();
}

void ninja_reset() { $state.Reset(); }

void ninja_dump() { $state.Dump(); }

const char * ninja_var_get(const char * key) { $buf = $state.bindings_.LookupVariable(key); return $buf.c_str(); }

void ninja_var_set(const char * key, const char * value) { $state.bindings_.AddBinding(key, value); }

void ninja_pool_add(const char * name, int depth) {
    ($state.LookupPool(name) != nullptr) || fatal("duplicate pool '%s'", name);
    (depth >= 0) || fatal("invalid pool depth %d", depth);

    $state.AddPool(new Pool(name, depth));
}

void * ninja_rule_add(const char * name, lua_table vars) {
    ($env->LookupRuleCurrentScope(name) == nullptr) || fatal("duplicate rule '%s'", name);

    auto r = new Rule(name);

    vars.for_pairs([&](lua_value const & k, lua_value const & v) {
        if(k.is_string() && v.is_string()) {
            Rule::IsReservedBinding(k.c_str()) || fatal("unexpected variable '%s'", k.c_str());

            EvalString es; {
                ninja_evalstring_read(v.c_str(), &es, false);
            }

            r->AddBinding(k.c_str(), es);
        }
    });

    $state.bindings_.AddRule(r); return r;
}

std::string ninja_path_read(BindingEnv * env, const char * s, uint64_t * slash_bits = 0) {
    EvalString es; ninja_evalstring_read(s, &es, true);

    std::string path = es.Evaluate(env); if(path.empty()) {
        fatal("empty path");
    }

    uint64_t bits;

    CanonicalizePath(&path, slash_bits ? slash_bits : &bits);

    return path;
}

void ninja_edge_add(lua_gcptr outputs, const char * rule_name, lua_gcptr inputs, lua_table vars) {
    (rule_name != nullptr) || fatal("missing rule name");

    const Rule * rule = $env->LookupRule(rule_name); {
        (rule != nullptr) || fatal("unknown rule '%s'", rule_name);
    }

    BindingEnv * env = vars.empty() ? $env : new BindingEnv($env); if(!vars.empty()) {
        vars.for_pairs([&](lua_value const & k, lua_value const & v) {
            if(k.is_string() && v.is_string()) {
                env->AddBinding(k.c_str(), v.c_str());
            }
        });
    }

    Edge * edge = $state.AddEdge(rule); edge->env_ = env;

    std::string pool_name = edge->GetBinding("pool"); if(!pool_name.empty()) {
        Pool * pool = $state.LookupPool(pool_name); {
            (pool != nullptr) || fatal("unknown pool name '%s'", pool_name.c_str());
        }

        edge->pool_ = pool;
    }

    std::string err; int c;

    // outputs
    outputs.for_ipairs([&](int, lua_value const & v) {
        if(v.is_string()) {
            uint64_t slash_bits;
            std::string path = ninja_path_read(edge->env_, v.c_str(), &slash_bits);
            $state.AddOut(edge, path, slash_bits, &err) || fatal("%s", err.c_str());
        }
    });

    lua_value implicit_outs; if(outputs.is_table()) {
        implicit_outs = outputs.as_table()["implicit"];
    }

    c = 0; if(implicit_outs && implicit_outs.is_gcobj()) {
        implicit_outs.to_gcptr().for_ipairs([&](int, lua_value const & v) {
            if(v.is_string()) {
                uint64_t slash_bits;
                std::string path = ninja_path_read(edge->env_, v.c_str(), &slash_bits);
                $state.AddOut(edge, path, slash_bits, &err) || fatal("%s", err.c_str());
                ++c;
            }
        });
    }

    !edge->outputs_.empty() || fatal("build does not have any outputs");

    edge->implicit_outs_ = c;

    // inputs
    inputs.for_ipairs([&](int, lua_value const & v) {
        if(v.is_string()) {
            uint64_t slash_bits;
            std::string path = ninja_path_read(edge->env_, v.c_str(), &slash_bits);
            $state.AddIn(edge, path, slash_bits);
        }
    });

    !edge->inputs_.empty() || fatal("build does not have any inputs");

    lua_value implicit_ins; if(inputs.is_table()) {
        implicit_ins = inputs.as_table()["implicit"];
    }

    c = 0; if(implicit_ins && implicit_ins.is_gcobj()) {
        implicit_ins.to_gcptr().for_ipairs([&](int, lua_value const & v) {
            if(v.is_string()) {
                uint64_t slash_bits;
                std::string path = ninja_path_read(edge->env_, v.c_str(), &slash_bits);
                $state.AddIn(edge, path, slash_bits);
                ++c;
            }
        });
    }

    edge->implicit_deps_ = c;

    lua_value order_only; if(inputs.is_table()) {
        order_only = inputs.as_table()["order_only"];
    }

    c = 0; if(order_only && order_only.is_gcobj()) {
        order_only.to_gcptr().for_ipairs([&](int, lua_value const & v) {
            if(v.is_string()) {
                uint64_t slash_bits;
                std::string path = ninja_path_read(edge->env_, v.c_str(), &slash_bits);
                $state.AddIn(edge, path, slash_bits);
                ++c;
            }
        });
    }

    edge->order_only_deps_ = c;

    lua_value validations; if(inputs.is_table()) {
        validations = inputs.as_table()["validations"];
    }

    if(validations && validations.is_gcobj()) {
        validations.to_gcptr().for_ipairs([&](int, lua_value const & v) {
            if(v.is_string()) {
                uint64_t slash_bits;
                std::string path = ninja_path_read(edge->env_, v.c_str(), &slash_bits);
                $state.AddValidation(edge, path, slash_bits);
                ++c;
            }
        });
    }

    // phony cycle check
    {
        auto x = edge->outputs_[0];
        (std::find(edge->inputs_.begin(), edge->inputs_.end(), x) != edge->inputs_.end()) || fatal("phony target '%s' names itself as an input; ", x->path().c_str());
    }

    // dyndep
    {
        std::string dyndep = edge->GetUnescapedDyndep(); if(!dyndep.empty()) {
            uint64_t slash_bits;
            CanonicalizePath(&dyndep, &slash_bits);
            edge->dyndep_ = $state.GetNode(dyndep, slash_bits);
            edge->dyndep_->set_dyndep_pending(true);

            (std::find(edge->inputs_.begin(), edge->inputs_.end(), edge->dyndep_) != edge->inputs_.end()) || fatal("dyndep '%s' is not an input", dyndep.c_str());
            (!edge->dyndep_->generated_by_dep_loader()) || fatal("dyndep '%s' is already an output", dyndep.c_str());
        }
    }
}

void ninja_default_add(lua_gcptr defaults) {
    std::string e;

    if(defaults.is_string()) {
        ok == $state.AddDefault(ninja_path_read($env, defaults.as_string().c_str()), &e) || fatal("%s", e.c_str());
    }
    else if(defaults.is_table()) {
        lua_table const & t = defaults.as_table();

        t.for_ipairs([&](int, lua_value const & v) {
            if(v.is_string()) {
                ok == $state.AddDefault(ninja_path_read($env, v.c_str()), &e) || fatal("%s", e.c_str());
            }
        });
    }
}

void ninja_build(lua_gcptr targets) {
    StatusPrinter status($config); std::vector<const char *> paths;

    if(targets) {
        if(targets.is_string()) {
            paths.push_back(targets.as_string().c_str());
        }
        else if(targets.is_table()) {
            lua_table const & t = targets.as_table();

            t.for_ipairs([&](int, lua_value const & v) {
                if(v.is_string()) paths.push_back(v.c_str());
            });
        }
    }

    if(paths.empty()) {
        status.Info("no targets to build"); return;
    }

    $ninja.start_time_millis_ = GetTimeMillis();

    ok == $ninja.EnsureBuildDirExists() || fatal("failed to create build directory");
    ok == $ninja.OpenBuildLog() || fatal("failed to open build log");
    ok == $ninja.OpenDepsLog() || fatal("failed to open deps log");

    if($ninja.RunBuild(paths.size(), (char **)paths.data(), &status) == 0) {
        $ninja.DumpMetrics();
    }

    $ninja.build_log_.Close(); $ninja.deps_log_.Close();
}

void ninja_clean() {
    Cleaner cleaner(&$ninja.state_, $config, &$ninja.disk_interface_); cleaner.CleanAll(true);
}
}

static bool ninja_evalstring_read(const char * s, EvalString * eval, bool path) {
    const char * p = s;
    const char * q;
    const char * start;
    for(;;) {
        start = p;
        {
            unsigned char yych;
            static const unsigned char yybm[] = {
                0, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 0, 16, 16, 0, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                32, 16, 16, 16, 0, 16, 16, 16,
                16, 16, 16, 16, 16, 208, 144, 16,
                208, 208, 208, 208, 208, 208, 208, 208,
                208, 208, 0, 16, 16, 16, 16, 16,
                16, 208, 208, 208, 208, 208, 208, 208,
                208, 208, 208, 208, 208, 208, 208, 208,
                208, 208, 208, 208, 208, 208, 208, 208,
                208, 208, 208, 16, 16, 16, 16, 208,
                16, 208, 208, 208, 208, 208, 208, 208,
                208, 208, 208, 208, 208, 208, 208, 208,
                208, 208, 208, 208, 208, 208, 208, 208,
                208, 208, 208, 16, 0, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 16, 16, 16, 16, 16, 16,
            };
            yych = *p;
            if(yybm[0 + yych] & 16) {
                goto yy102;
            }
            if(yych <= '\r') {
                if(yych <= 0x00) goto yy100;
                if(yych <= '\n') goto yy105;
                goto yy107;
            } else {
                if(yych <= ' ') goto yy105;
                if(yych <= '$') goto yy109;
                goto yy105;
            }
        yy100:
            break;
        yy102:
            yych = *++p;
            if(yybm[0 + yych] & 16) {
                goto yy102;
            }
            {
                eval->AddText(StringPiece(start, p - start));
                continue;
            }
        yy105:
            ++p;
            {
                if(path) {
                    p = start;
                    break;
                } else {
                    if(*start == '\n')
                        break;
                    eval->AddText(StringPiece(start, 1));
                    continue;
                }
            }
        yy107:
            yych = *++p;
            if(yych == '\n') goto yy110;
            {
                fatal("bad eval string");
            }
        yy109:
            yych = *++p;
            if(yybm[0 + yych] & 64) {
                goto yy122;
            }
            if(yych <= ' ') {
                if(yych <= '\f') {
                    if(yych == '\n') goto yy114;
                    goto yy112;
                } else {
                    if(yych <= '\r') goto yy117;
                    if(yych <= 0x1F) goto yy112;
                    goto yy118;
                }
            } else {
                if(yych <= '/') {
                    if(yych == '$') goto yy120;
                    goto yy112;
                } else {
                    if(yych <= ':') goto yy125;
                    if(yych <= '`') goto yy112;
                    if(yych <= '{') goto yy127;
                    goto yy112;
                }
            }
        yy110:
            ++p;
            {
                if(path)
                    p = start;
                break;
            }
        yy112:
            ++p;
        yy113 : {
            fatal("bad $-escape (literal $ must be written as $$)");
        }
        yy114:
            yych = *++p;
            if(yybm[0 + yych] & 32) {
                goto yy114;
            }
            {
                continue;
            }
        yy117:
            yych = *++p;
            if(yych == '\n') goto yy128;
            goto yy113;
        yy118:
            ++p;
            {
                eval->AddText(StringPiece(" ", 1));
                continue;
            }
        yy120:
            ++p;
            {
                eval->AddText(StringPiece("$", 1));
                continue;
            }
        yy122:
            yych = *++p;
            if(yybm[0 + yych] & 64) {
                goto yy122;
            }
            {
                eval->AddSpecial(StringPiece(start + 1, p - start - 1));
                continue;
            }
        yy125:
            ++p;
            {
                eval->AddText(StringPiece(":", 1));
                continue;
            }
        yy127:
            yych = *(q = ++p);
            if(yybm[0 + yych] & 128) {
                goto yy131;
            }
            goto yy113;
        yy128:
            yych = *++p;
            if(yych == ' ') goto yy128;
            {
                continue;
            }
        yy131:
            yych = *++p;
            if(yybm[0 + yych] & 128) {
                goto yy131;
            }
            if(yych == '}') goto yy134;
            p = q;
            goto yy113;
        yy134:
            ++p;
            {
                eval->AddSpecial(StringPiece(start + 2, p - start - 3));
                continue;
            }
        }
    }
    // if(path) EatWhitespace();
    // Non-path strings end in newlines, so there's no whitespace to eat.
    return true;
}

struct clib_sym_t {
    const char * name; void * sym;
};

#define CLIB_SYM(name) { #name, (void *)(name) }

static clib_sym_t __clib_syms[] = {
    CLIB_SYM(reftable_new),
    CLIB_SYM(reftable_ref),
    CLIB_SYM(reftable_unref),
    CLIB_SYM(ninja_config_get),
    CLIB_SYM(ninja_config_apply),
    CLIB_SYM(ninja_reset),
    CLIB_SYM(ninja_dump),
    CLIB_SYM(ninja_var_get),
    CLIB_SYM(ninja_var_set),
    CLIB_SYM(ninja_pool_add),
    CLIB_SYM(ninja_edge_add),
    CLIB_SYM(ninja_rule_add),
    CLIB_SYM(ninja_default_add),
    CLIB_SYM(ninja_build),
    CLIB_SYM(ninja_clean),
    {0, 0}};

extern "C" {
extern clib_sym_t * clib_syms;

static void clib_init() {
    printf("clib_syms init\n");
    clib_syms = __clib_syms;
}

__attribute__((constructor)) void ninja_initialize() {
    printf("ninja init\n");
    clib_init();

    $config.parallelism = GetProcessorCount();
    ninja_var_set("builddir", DEFAULT_BUILD_DIR);
}
}