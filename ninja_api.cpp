#include <state.h>
#include <eval_env.h>
#include <build.h>
#include <disk_interface.h>
#include <build_log.h>
#include <deps_log.h>
#include <util.h>

#include "ljx.h"
#include "ljxx.h"

#include <filesystem>

namespace fs = std::filesystem;

static std::string $buf;

static State $state;
static BuildConfig $config;
static std::string $builddir = "build";
static RealDiskInterface $disk_interface;
static BuildLog $build_log;
static DepsLog $deps_log;

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

extern lua_State * __L;

void * ninja_build(lua_value a) {
    // lua_value x; memcpy(&x, &a, sizeof(tvalue));

    printf("i: %d\n", a.to_int());

    return lj_str_newz(__L, "ret string");
}

// void * ninja_build(lua_value x) {
//     lua_table t = x;

//     auto & args = t.array<4>();

//     auto [_, a, b, c] = args;

//     printf("gctab: %d, %d, %d\n", (int)a, (int)b, (int)c);

//     return lj_str_newz(__L, "ret string");
// }

// void * ninja_build(lua_table t) {
//     auto & args = t.array<4>();

//     auto [_, a, b, c] = args;

//     printf("gctab: %d, %d, %d\n", (int)a, (int)b, (int)c);

//     return lj_str_newz(__L, "ret string");
// }

// void * ninja_build(lua_value what) {
//     printf("ninja_build ===> %s\n", what.c_str());

//     return lj_str_newz(__L, "ret string");
// }

// void ninja_build(lua_gcobj what) {
// void ninja_build(lua_string what) {
//     printf("ninja_build ===> %s\n", what.c_str());
// if(!what) return;

// int type = what.type();

// std::vector<std::string> paths; if(type == LJ_TSTR) {
//     printf("%s\n", what.as_string().c_str());
//     paths.push_back(what.as_string().c_str());
// }
// else if(type == LJ_TTAB) {
//     lua_table const & t = what.as_table(); t.for_ipairs([&](int, lua_value const & v) {
//         if(v.is_string()) {
//             printf("%s\n", v.c_str());
//             paths.push_back(v.c_str());
//         }
//         else {
//             fatal("invalid argument to ninja_build");
//         }
//     });
// }
// else {
//     fatal("invalid argument to ninja_build");
// }

// ensure builddir exists
// if(!fs::exists($builddir)) fs::create_directories($builddir);
// if(!fs::is_directory($builddir)) fatal("cannot create build directory: ");
// }

void ninja_clean(lua_gcobj what) {}
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
