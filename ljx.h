#ifndef __ljx_326793b9ae35409dad7f48b241b79c8f
#define __ljx_326793b9ae35409dad7f48b241b79c8f

#include <stdio.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdlib.h>

#include <utility>

const int success = 0;

constexpr bool failed(bool x) { return !x; }

template<typename T>
constexpr bool failed(T * x) { return x == nullptr; }

template<typename T>
constexpr bool failed(T && x) { return x < 0; }

static inline bool fatal(const char * fmt, ...) {
    va_list args; va_start(args, fmt); vprintf(fmt, args); va_end(args); exit(-1); return true;
}

static inline bool info(const char * fmt, ...) {
    va_list args; va_start(args, fmt); vprintf(fmt, args); va_end(args); return true;
}

static inline bool halt() { exit(-1); return true; }

static inline struct {
    template<typename T>
    void operator=(T && x) { if(failed(x)) fatal("operation failed"); }

    template<typename T>
    constexpr bool operator==(T && x) { return !failed(x); }

    template<typename T>
    auto operator()(T && x) { (*this) = std::forward<T>(x); return std::forward<T>(x); }
} ok, yes;

#endif // __ljx_326793b9ae35409dad7f48b241b79c8f
