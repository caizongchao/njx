#pragma once

#include <stdint.h>
#include <time.h>

#include <map>
#include <memory>
#include <vector>
#include <chrono>

// now() in milliseconds
static inline uint64_t now() {
    timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

template<typename T>
struct basic_reftable {
    typedef T value_type;
    typedef std::vector<value_type> table_type;

    table_type table; int flist {-1};

    int ref(value_type const & x) {
        int r; if(flist < 0) {
            r = table.size(); table.push_back(x);
        }
        else {
            r = flist; flist = (int &)(table[flist]); table[r] = x;
        }
        return r;
    }

    void unref(int i) {
        table[i].~value_type(); ((int &)(table[i])) = flist; flist = i;
    }

    value_type & operator[](int i) const { return (value_type &)table[i]; }
};

template<typename T>
struct auto_ptr {
    T * ptr;

    auto_ptr() : ptr(nullptr) {}

    auto_ptr(T * ptr) : ptr(ptr) {}

    auto_ptr(auto_ptr const &) = delete;

    auto_ptr(auto_ptr && x) : ptr(x.ptr) { x.ptr = nullptr; }

    template<typename... Args>
    static auto_ptr make(Args &&... args) { return auto_ptr(new T(std::forward<Args>(args)...)); }

    ~auto_ptr() { if(ptr) delete ptr; }

    operator T *() { return ptr; }

    operator bool() { return ptr != nullptr; }

    T * detach() { auto ptr = this->ptr; this->ptr = nullptr; return ptr; }

    auto_ptr & operator=(auto_ptr const &) = delete;

    auto_ptr & operator=(auto_ptr && x) { ptr = x.ptr; x.ptr = nullptr; return *this; }

    T * operator->() const { return (T *)ptr; }
};

template<typename T>
struct dtag {};

template<typename T, typename... Args>
struct defer_ptr {
    T * ptr {nullptr}; std::tuple<Args...> args;

    defer_ptr(dtag<T> tag, Args &&... args) : args(std::forward<Args>(args)...) {}

    ~defer_ptr() { if(ptr) delete ptr; }

    defer_ptr(defer_ptr const &) = delete;

    defer_ptr(defer_ptr && x) = delete;

    operator T *() { return get(); }

    operator bool() { return ptr != nullptr; }

    T * get() { if(!ptr) ptr = new T(std::get<Args>(args)...); return ptr; }

    T * detach() { auto p = ptr; ptr = nullptr; return p; }

    T * operator->() { return get(); }

    defer_ptr & operator=(defer_ptr const &) = delete;

    defer_ptr & operator=(defer_ptr && x) = delete;
};

template<typename T, typename... Args>
defer_ptr(dtag<T>, Args &&...) -> defer_ptr<T, Args...>;

template<typename T, typename F>
struct dget {
    F getter;

    dget(dtag<T>, F && getter) : getter(std::forward<F>(getter)) {}

    operator T() { return (T)getter(); }

    T operator->() { return (T)getter(); }
};

template<typename T, typename F>
dget(dtag<T>, F &&) -> dget<T, F>;

struct dtimer {
    struct timer_data {
        bool repeat; int id; int t; intptr_t value;

        timer_data(bool repeat, int id, int t, intptr_t value) : repeat(repeat), id(id), t(t), value(value) {}
    };

    typedef auto_ptr<timer_data> timer_data_ptr;

    typedef std::multimap<uint64_t, timer_data_ptr> timers_type;

    timers_type timers;
    std::vector<timer_data_ptr> tdtable;
    basic_reftable<timers_type::iterator> idtable;

    int add(int t, intptr_t v, bool r) {
        auto it = timers.emplace(t + now(), timer_data_ptr::make(r, 0, t, v));

        int id = idtable.ref(it); it->second->id = id;

        return id;
    }

    void remove(int id) {
        auto const & it = idtable[id]; timers.erase(it); idtable.unref(id);
    }

    template<typename F>
    void update(F && f) {
        auto t_now = now();

        auto it_begin = timers.begin(), it_end = timers.upper_bound(t_now); if(it_begin != it_end) {
            f(it_begin, it_end);

            for(auto it = it_begin; it != it_end; ++it) {
                auto & data = it->second; if(data->repeat) {
                    tdtable.push_back(std::move(data));
                }
                else {
                    idtable.unref(data->id);
                }
            }

            timers.erase(it_begin, it_end); if(!tdtable.empty()) {
                for(auto & td : tdtable) {
                    auto id = td->id; idtable[id] = timers.emplace(td->t + t_now, std::move(td));
                }

                tdtable.clear();
            }
        }
    }
};

static inline struct $more_t { } $more;

template<typename T>
struct dvector {
    uint32_t capacity; uint32_t size; T * data;

    dvector() : size(0), capacity(0), data(0) {}

    dvector(size_t c) : dvector() { require(c); }

    dvector(dvector const & x) : dvector() {
        resize(x.size); for(size_t i = 0; i < x.size; i++) new(data + i) T(x[i]);
    }

    dvector(dvector && x) : size(x.size), capacity(x.capacity), data(x.data) {
        x.size = 0; x.capacity = 0; x.data = 0;
    }

    dvector(T && x) : size(1), capacity(1) { data = (T *)malloc(sizeof(T)); new(data) T(std::move(x)); }

    template<size_t N>
    dvector(T(&&x)[N]) : size(N), capacity(N), data(0) {
        if(N > 0) {
            data = (T *)malloc(N * sizeof(T)); {
                for(size_t i = 0; i < N; i++) new(data + i) T(std::move(x[i]));
            }
        }
    }

    ~dvector() { if(data) { clear(); free(data); } }

    void clear() { for(size_t i = 0; i < size; i++) data[i].~T(); ; size = 0; }

    dvector & require(size_t c) {
        if(c > capacity) {
            if(!capacity) capacity = 1; ; while(capacity < c) capacity *= 2; {
                data = (T *)realloc(data, capacity * sizeof(T));
            }
        }

        return *this;
    }

    dvector & require($more_t, size_t c) { return require(size + c); }

    dvector & resize(size_t c) {
        if(c > size) {
            require(c); {
                for(size_t i = size; i < c; i++) new(data + i) T();
            }

            size = c;
        }
        else if(c < size) {
            for(size_t i = size; i < c; i++) data[i].~T(); ; size = c;
        }

        return *this;
    }

    T & operator[](size_t i) const { return (T &)(data[i]); }

    T * begin() const { return data; }

    T * end() const { return data + size; }

    T & back() const { return (T &)(data[size - 1]); }

    T & front() const { return (T &)(data[0]); }

    template<typename X>
    T & push(X && x) {
        require(size + 1); auto a = new(data + size) T(std::forward<X>(x)); ++size; return *a;
    }

    template<typename X>
    T & push_back(X && x) { return push(std::forward<X>(x)); }

    dvector & pop() { data[--size].~T(); return *this; }

    bool empty() const { return size == 0; }
};
