#ifndef ljxx_ac444ba0f14f422f9e50be80caa40bca
#define ljxx_ac444ba0f14f422f9e50be80caa40bca

#include <string>
#include <array>
#include <vector>

extern "C" {
#define Node TNode
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <lj_obj.h>
#include <lj_tab.h>
#include <lj_str.h>
#include <lj_buf.h>
#include <lj_udata.h>
#include <lj_cdata.h>
#include <lj_state.h>
#undef Node
}

#include "ljx.h"
#include "function.h"

struct tvalue {
    double value;

    int to_int() const { return (int)value; }
};

struct lua_table;
struct lua_gcptr;

struct lua_value {
    TValue value {(uint64_t)-1};

    lua_value() = default;

    lua_value(TValue const & x) : value(x) {}

    lua_value(lua_value const &) = default;

    lua_value(std::nullptr_t) { setnilV(&value); }

    lua_value(const void * x);

    lua_value(bool b) { setboolV(&value, b); }

    lua_value(double x) { setnumV(&value, x); }

    lua_value(int32_t x) { setnumV(&value, x); }
    lua_value(uint32_t x) { setnumV(&value, x); }

    lua_value(int64_t x) { setnumV(&value, x); }
    lua_value(uint64_t x) { setnumV(&value, x); }

    lua_value(const char *);

    lua_value(GCtab * t);
    lua_value(lua_table t);

    lua_value(GCcdata * c);

    lua_value(std::string_view const & s);

    lua_value(lua_CFunction f);

    template<of_invokable F>
    lua_value(F && f);

    int type() const { return itype(&value); }

    lua_value & operator=(lua_value const & x) { value = x.value; return *this; }

    bool operator==(std::nullptr_t) const { return tvisnil(&value); }

    operator TValue() const { return value; }

    operator TValue *() const { return (TValue *)&value; }

    TValue * operator->() const { return (TValue *)&value; }

    operator bool() const { return !(tvisnil(&value) || tvisfalse(&value)); }

    operator int32_t() const { return numV(&value); }

    operator int64_t() const { return numV(&value); }

    operator double() const { return numV(&value); }

    operator std::string_view() const {
        if(tvisnil(&value)) return {}; else { auto str = strV(&value); return {strdata(str), str->len}; }
    }

    operator const char *() const { return tvisnil(&value) ? nullptr : strVdata(&value); }

    operator void *() const;

    bool is_nil() const { return tvisnil(&value); }
    bool is_table() const { return tvistab(&value); }
    bool is_number() const { return tvisnum(&value); }
    bool is_string() const { return tvisstr(&value); }
    bool is_cdata() const { return tviscdata(&value); }
    bool is_lightud() const { return tvislightud(&value); }
    bool is_function() const { return tvisfunc(&value); }
    bool is_boolean() const { return tvisbool(&value); }
    bool is_gcobj() const { return tvisgcv(&value); }

    int32_t to_int(int32_t defvalue = 0) const { return tvisnum(&value) ? numV(&value) : defvalue; }
    int32_t to_int32(int32_t defvalue = 0) const { return tvisnum(&value) ? numV(&value) : defvalue; }
    int64_t to_int64(int64_t defvalue = 0) const { return tvisnum(&value) ? numV(&value) : defvalue; }
    double to_double(double defvalue = 0) const { return tvisnum(&value) ? numV(&value) : defvalue; }
    std::string_view to_string(std::string_view defvalue = {}) const { return tvisstr(&value) ? std::string_view(strVdata(&value), strV(&value)->len) : defvalue; }
    const char * to_cstr(const char * defvalue = nullptr) const { return tvisstr(&value) ? strVdata(&value) : defvalue; }

    lua_gcptr to_gcptr() const;

    const char * c_str() const { return strVdata(&value); }
};

inline lua_value lua_nil;

struct lua_table {
    GCtab * value {nullptr};

    lua_table() = default;

    lua_table(GCtab * value) : value(value) {}

    lua_table(lua_value const & t) { this->value = tvistab(t) ? tabV(t) : nullptr; }

    lua_table(lua_table const &) = default;

    static lua_table make();
    static lua_table make(size_t asize, size_t hbits);

    lua_value * array() const { return mref(value->array, lua_value); }

    size_t asize() const { return value->asize; }

    lua_table & reasize(size_t asize);

    size_t ensure_asize(size_t asize) {
        if(value->asize >= asize) return -1;

        size_t nasize = value->asize; while(nasize < asize) {
            nasize *= 2;
        }

        reasize(nasize); return nasize;
    }

    operator GCtab *() const { return value; }

    operator bool() const { return value != nullptr; }

    bool empty() const { return !value || (lj_tab_len(value) == 0); }

    lua_table & clear() { lj_tab_clear(value); return *this; }

    lua_table & operator=(lua_table const & x) { value = x.value; return *this; }

    lua_table & operator=(GCtab * x) { value = x; return *this; }

    bool operator==(std::nullptr_t) const { return value == nullptr; }

    lua_value operator[](size_t idx) const;

    lua_value operator[](const GCstr * name) const;

    lua_value operator[](std::string_view const & name) const;

    lua_value operator[](const char * name) const { return operator[](std::string_view(name)); }

    lua_value operator()(std::string_view const & name) const;

    lua_value operator()(const char * name) const { return operator()(std::string_view(name)); }

    lua_table & push(lua_value const & x);

    lua_table & push_back(lua_value const & x) { return push(x); }

    lua_table & def(size_t idx, lua_value const & x);

    lua_table & def(std::string_view const & name, lua_value const & x);

    lua_table & def(const GCstr * name, lua_value const & x);

    typedef void (*gcfx)(lua_table t);

    lua_table & ongc(gcfx f) { value->gcfx = (lua_CFunction)f; return *this; }

    template<typename F>
    void for_pairs(F && f) const {
        typedef function_traits<F> fx_traits;

        const bool no_return = std::is_same_v<typename fx_traits::result, void>;

        GCtab * t = value; TValue * tv = tvref(t->array); auto c = t->asize;

        for(size_t i = 0; i < c; ++i) {
            if(!tvisnil(tv + i)) {
                lua_value k = i; if constexpr(no_return) {
                    f(k, (lua_value &)(tv[i]));
                }
                else {
                    if(!f(k, (lua_value &)(tv[i]))) return;
                }
            }
        }

        TNode * n = mref(t->node, TNode); TNode * ne = n + t->hmask + 1;

        for(; n < ne; n++) {
            if(!tvisnil(&n->val)) {
                if constexpr(no_return) {
                    f((lua_value &)n->key, (lua_value &)n->val);
                }
                else {
                    if(!f((lua_value &)n->key, (lua_value &)n->val)) return;
                }
            }
        }
    }

    template<typename F>
    void for_ipairs(F && f) const {
        typedef function_traits<F> fx_traits;

        const bool no_return = std::is_same_v<typename fx_traits::result, void>;

        GCtab * t = value; TValue * tv = tvref(t->array); auto c = t->asize;

        for(size_t i = 0; i < c; ++i) {
            if(!tvisnil(tv + i)) {
                if constexpr(no_return) {
                    f(i, (lua_value &)(tv[i]));
                }
                else {
                    if(!f(i, (lua_value &)(tv[i]))) return;
                }
            }
        }
    }
};

struct lua_string {
    GCstr * value {nullptr};

    lua_string() = default;

    lua_string(GCstr * value) : value(value) {}

    lua_string(const char * s) : lua_string(lua_value(s)) {}

    lua_string(const char * s, size_t len) : lua_string(lua_value(std::string_view(s, len))) {}

    lua_string(lua_value const & t) { this->value = tvisstr(t) ? strV(t) : nullptr; }

    lua_string(lua_string const &) = default;

    operator GCstr *() const { return value; }

    operator GCobj *() const { return (GCobj *)value; }

    operator bool() const { return value != nullptr; }

    lua_string & operator=(lua_string const & x) { value = x.value; return *this; }

    bool operator==(std::nullptr_t) const { return value == nullptr; }

    bool operator==(lua_string const & x) const { return value == x.value; }

    operator std::string_view() const { return {strdata(value), value->len}; }

    operator const char *() const { return strdata(value); }

    const char * c_str() const { return strdata(value); }
};

struct lua_gcptr {
    GCobj * value {nullptr};

    lua_gcptr() = default;

    lua_gcptr(GCobj * value) : value(value) {}

    lua_gcptr(lua_value const & t) { this->value = tvisgcv(t) ? gcV(t) : nullptr; }

    lua_gcptr(lua_gcptr const &) = default;

    operator GCobj *() const { return value; }

    operator bool() const { return value != nullptr; }

    lua_gcptr & operator=(lua_gcptr const & x) { value = x.value; return *this; }

    bool operator==(std::nullptr_t) const { return value == nullptr; }

    bool operator==(lua_gcptr const & x) const { return value == x.value; }

    int type() const { return ~(value->gch.gct); }

    bool is_string() const { return value->gch.gct == ~LJ_TSTR; }
    bool is_table() const { return value->gch.gct == ~LJ_TTAB; }

    lua_table & as_table() const { return *(lua_table *)this; }
    lua_string & as_string() const { return *(lua_string *)this; }

    lua_value tvalue() const {
        int64_t t = ~value->gch.gct;
        int64_t a = ((int64_t)value) | (t << 47);
        lua_value r; r.value.u64 = a; return r;
    }

    operator lua_value() const { return tvalue(); }

    operator SBuf *() const { return (SBuf *)uddata(&value->ud); }

    operator SBufExt *() const { return (SBufExt *)uddata(&value->ud); }

    operator lua_string() const { return as_string(); }

    template<typename F>
    void for_pairs(F && f) const {
        if(!is_table()) f(lua_value(1), tvalue()); else as_table().for_pairs(std::forward<F>(f));
    }

    template<typename F>
    void for_ipairs(F && f) const {
        if(!is_table()) f(1, tvalue()); else as_table().for_ipairs(std::forward<F>(f));
    }
};

inline lua_gcptr lua_value::to_gcptr() const { return {gcval(&value)}; }

struct lua_state;

struct lua_initialize_t {
    std::vector<function<void()>> initializers;

    template<typename F>
    lua_initialize_t & operator()(F && f) { initializers.emplace_back(std::forward<F>(f)); return *this; }
};

inline lua_initialize_t $lua_initialize;

struct lua_state {
    lua_State * L {nullptr}; std::vector<function<void()>> initializers;

    template<typename F>
    lua_state & on_initialize(F && f) { initializers.emplace_back(std::forward<F>(f)); return *this; }

    template<of_invokable F>
    lua_state & operator()(F && f) { return on_initialize(std::forward<F>(f)); }

    lua_state & open() {
        L = luaL_newstate(); luaL_openlibs(L); {
            for(auto & f : $lua_initialize.initializers) f();
            for(auto & f : initializers) { f(); initializers.clear(); }
        }

        return *this;
    }

    ~lua_state() { if(L) lua_close(L); }

    operator lua_State *() const { return L; }

    // global
    lua_table _G() const { return {tabref(L->env)}; }

    // registry
    lua_table & _R() const { static auto x = lua_table::make(1024, 0); return x; }

    lua_value operator[](std::string_view const & name) const { return _G()[name]; }

    lua_value operator()(std::string_view const & name) const { return _G()(name); }

    lua_State * operator()() const { return L; }

    lua_State * operator->() const { return L; }

    lua_state & push(lua_value const & x) { *L->top = x.value; incr_top(L); return *this; }

    lua_state & pop(int n = 1) { L->top -= n; return *this; }

    int ref(lua_value const & x) { push(x); return luaL_ref(L, LUA_REGISTRYINDEX); }

    lua_state & unref(int x) { luaL_unref(L, LUA_REGISTRYINDEX, x); return *this; }

    lua_value require(std::string_view const & name) {
        lua_getglobal(L, "require"); lua_pushlstring(L, name.data(), name.size()); lua_call(L, 1, 1); lua_value r = *--L->top; return r;
    }

    template<typename... T>
    lua_state & load(T &&... args) {
        (require(std::forward<T>(args)), ...); return *this;
    }

    lua_state & run(std::string_view const & code) {
        luaL_loadbuffer(L, code.data(), code.size(), "=(lua_state::run)"); lua_call(L, 0, 0); return *this;
    }
};

inline thread_local lua_state $L;

inline lua_value::lua_value(const void * x) { setrawlightudV(&value, lj_lightud_intern($L, (void *)x)); }

inline lua_value::lua_value(const char * s) { setstrV($L, &value, lj_str_newz($L, s)); }

inline lua_value::lua_value(std::string_view const & s) { setstrV($L, &value, lj_str_new($L, s.data(), s.size())); }

inline lua_value::lua_value(lua_CFunction f) {
    lua_State * L = $L; lua_pushcclosure(L, f, 0); value = *--L->top;
}

inline lua_value::lua_value(GCtab * t) { settabV($L, &value, t); }

inline lua_value::lua_value(lua_table t) : lua_value(t.value) {}

inline lua_value::lua_value(GCcdata * c) { setcdataV($L, &value, c); }

template<of_invokable F>
lua_value::lua_value(F && f) {
    typedef std::remove_reference_t<F> fx_type; typedef function_traits<fx_type> fx_traits;

    const size_t fx_size = sizeof(fx_type); const bool no_return = std::is_same_v<typename fx_traits::result, void>;

    lua_State * L = $L;

    auto argc = lua_gettop(L); yes = (argc == fx_traits::arity);

    typedef std::array<lua_value, fx_traits::arity> argv_type;

    auto argvp = (argv_type *)(L->top - fx_traits::arity); argv_type & argv = *argvp;

    if constexpr((std::is_function_v<fx_type> || (fx_size == 1))) {
        lua_CFunction cf = [](lua_State * L) {
            if constexpr(no_return) {
                std::apply(((fx_type *)nullptr), argv); return 0;
            }
            else {
                lua_value r = std::apply(((fx_type *)nullptr), argv); {
                    $L.push(r);
                }

                return 1;
            }
        };

        lua_pushcclosure(L, cf, 0);
    }
    else {
        lua_CFunction cf = [](lua_State * L) {
            auto uv = (uint64_t *)curr_func(L)->c.upvalue;

            fx_type * f = (fx_type *)uv[1];

            if constexpr(no_return) {
                std::apply(*f, argv); return 0;
            }
            else {
                lua_value r = std::apply(*f, argv); {
                    $L.push(r);
                }

                return 1;
            }
        };

        const bool is_trivial = std::is_trivially_destructible_v<fx_type>;

        if constexpr(is_trivial) lua_pushcclosure(L, cf, 2); else lua_pushcclosure(L, cf, 3);
    }

    value = *--L->top;

    GCfunc * gcf = funcV(&value); auto uvc = gcf->c.nupvalues; auto uv = (uint64_t *)gcf->c.upvalue;

    if(uvc > 0) {
        uv[0] = 0x55AA55AA55AA55AAULL;
        uv[1] = (uint64_t)(new fx_type(std::forward<F>(f)));

        if(uvc > 2) {
            typedef void (*dtor_type)(void *);

            auto dtor = [](void * p) { delete(fx_type *)p; };

            uv[2] = (uint64_t)(dtor);
        }
    }
}

inline lua_value::operator void *() const { return tvisnil(&value) ? nullptr : (void *)lightudV(G($L.L), &value); }

inline lua_table lua_table::make() { return {lj_tab_new($L, 0, 0)}; }

inline lua_table lua_table::make(size_t asize, size_t hbits) { return {lj_tab_new($L, asize, hbits)}; }

inline lua_value lua_table::operator[](size_t idx) const {
    auto xp = lj_tab_getint(value, idx); return xp ? lua_value {*xp} : lua_nil;
}

inline lua_value lua_table::operator[](const GCstr * name) const {
    auto xp = lj_tab_getstr(value, name); return xp ? lua_value {*xp} : lua_nil;
}

inline lua_value lua_table::operator[](std::string_view const & name) const {
    return operator[](lj_str_new($L, name.data(), name.size()));
}

inline lua_value lua_table::operator()(std::string_view const & name) const {
    lua_value r {value}; GCtab * t {tabV(r)};

    char sep = '.'; size_t i = 0; while(true) {
        size_t j = name.find(sep, i); if(j == std::string_view::npos) j = name.size();

        std::string_view s {name.data() + i, j - i}; if(s.empty()) break;

        auto xp = lj_tab_getstr(t, lj_str_new($L, s.data(), s.size())); if(!xp) {
            r = lua_nil; break;
        }

        r = *xp; if((j < name.size()) && !tvistab(r)) {
            r = lua_nil; break;
        }

        t = tabV(r); i = j + 1;
    }

    return r;
}

inline lua_table & lua_table::def(size_t idx, lua_value const & x) {
    *lj_tab_setint($L, value, idx) = x.value; return *this;
}

inline lua_table & lua_table::def(std::string_view const & name, lua_value const & x) {
    return def(lj_str_new($L, name.data(), name.size()), x);
}

inline lua_table & lua_table::def(const GCstr * name, lua_value const & x) {
    *lj_tab_setstr($L, value, name) = x.value; return *this;
}

inline lua_table & lua_table::push(lua_value const & x) { *lj_tab_setint($L, value, lj_tab_len(value) + 1) = x.value; return *this; }

inline lua_table & lua_table::reasize(size_t asize) { lj_tab_reasize($L, value, asize); return *this; }

#endif // ljxx_ac444ba0f14f422f9e50be80caa40bca
