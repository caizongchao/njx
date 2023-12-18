#include <state.h>
#include <eval_env.h>
#include <build.h>
#include <clean.h>
#include <disk_interface.h>
#include <build_log.h>
#include <deps_log.h>
#include <status.h>
#include <util.h>

#include "ljx.h"
#include "ljxx.h"

#include <filesystem>

namespace fs = std::filesystem;

extern lua_State * __L;

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

static std::string $builddir = "build";
static std::string $logpath = ".ninja_log";
static std::string $depspath = ".ninja_deps";

static std::string $buf;

// static State $state;
static BuildConfig $config;
// static RealDiskInterface $disk_interface;
// static BuildLog $build_log;
// static DepsLog $deps_log;

static NinjaMain $ninja(nullptr, $config);

static bool ninja_evalstring_read(const char * s, EvalString * eval, bool path);

extern "C" {
void ninja_initialize() { $config.parallelism = GetProcessorCount(); }
void * ninja_config() { return (void *)&$config; }
const char * ninja_builddir_get() { return $builddir.c_str(); }
void ninja_builddir_set(const char * path) { $builddir = path; }
void ninja_reset(void * state) { ((State *)state)->Reset(); }
void ninja_dump(void * state) { ((State *)state)->Dump(); }
const char * ninja_var_get(void * state, const char * key) { $buf = ((State *)state)->bindings_.LookupVariable(key); return $buf.c_str(); }
void ninja_var_set(void * state, const char * key, const char * value) { ((State *)state)->bindings_.AddBinding(key, value); }
void ninja_pool_add(void * state, void * pool) { ((State *)state)->AddPool((Pool *)pool); }
void * ninja_pool_lookup(void * state, const char * name) { return ((State *)state)->LookupPool(name); }
void * ninja_edge_add(void * state, void * rule) { return ((State *)state)->AddEdge((Rule *)rule); }
void ninja_edge_addin(void * state, void * edge, const char * path, uint64_t slash_bits) { ((State *)state)->AddIn((Edge *)edge, path, slash_bits); }
void ninja_edge_addout(void * state, void * edge, const char * path, uint64_t slash_bits) { ((State *)state)->AddOut((Edge *)edge, path, slash_bits, 0); }
void ninja_edge_addvalidation(void * state, void * edge, const char * path, uint64_t slash_bits) { ((State *)state)->AddValidation((Edge *)edge, path, slash_bits); }
void * ninja_node_get(void * state, const char * path, uint64_t slash_bits) { return ((State *)state)->GetNode(path, slash_bits); }
void * ninja_node_lookup(void * state, const char * path) { return ((State *)state)->LookupNode(path); }
void * ninja_rule_add(void * state, const char * name) { auto r = new Rule(name); ((State *)state)->bindings_.AddRule(r); return r; }
void * ninja_rule_lookup(void * state, const char * name) { return (void *)((State *)state)->bindings_.LookupRule(name); }
const char * ninja_rule_name(void * rule) { return ((Rule *)rule)->name().c_str(); }
void * ninja_rule_get(void * rule, const char * key) { return (void *)((Rule *)rule)->GetBinding(key); }
void ninja_rule_set(void * rule, const char * key, const char * value) { EvalString es; ninja_evalstring_read(value, &es, false); ((Rule *)rule)->AddBinding(key, es); }
bool ninja_rule_isreserved(void * rule, const char * key) { return ((Rule *)rule)->IsReservedBinding(key); }

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

    $ninja.RunBuild(paths.size(), (char **)paths.data(), &status);
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
            ++p;
            {
                fatal("unexpected EOF");
            }
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
