#ifndef __ljx_326793b9ae35409dad7f48b241b79c8f
#define __ljx_326793b9ae35409dad7f48b241b79c8f

#include <stdint.h>

const int success = 0;

constexpr bool failed(bool x) { return !x; }

template<typename T>
constexpr bool failed(T * x) { return x == nullptr; }

template<typename T>
constexpr bool failed(T && x) { return x < 0; }

static inline void fatal(const char * msg) { printf("[fatal] %s\n", msg); exit(-1); }
static inline void fatal(const std::string & msg) { fatal(msg.c_str()); }

static inline struct {
    template<typename T>
    void operator=(T && x) { if(failed(x)) fatal("operation failed"); }

    template<typename T>
    constexpr bool operator==(T && x) { return failed(x); }

    template<typename T>
    auto operator()(T && x) { (*this) = std::forward<T>(x); return std::forward<T>(x); }
} ok, yes;

#endif // __ljx_326793b9ae35409dad7f48b241b79c8f
