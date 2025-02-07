#pragma once

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/mman.h>

#include <string>

#include "ljx.h"

struct autofp {
    FILE * fp {nullptr};

    autofp(FILE * fp) : fp(fp) {}

    autofp(autofp const &) = delete;

    autofp(autofp && x) : fp(x.fp) { x.fp = nullptr; }

    ~autofp() { if(fp) fclose(fp); }

    operator FILE *() { return fp; }

    operator int() { return fileno(fp); }

    operator bool() { return fp != nullptr; }

    FILE * detach() { auto fp = this->fp; this->fp = nullptr; return fp; }
};

struct autofd {
    int value {-1};

    autofd(int fd) : value(fd) {}

    autofd(autofd const &) = delete;

    autofd(autofd && x) : value(x.value) { x.value = -1; }

    ~autofd() { if(value >= 0) close(value); }

    operator int() { return value; }

    operator bool() { return value >= 0; }

    int detach() { auto fd = this->value; this->value = -1; return fd; }
};

static inline bool file_exists(const char * fname) {
    autofd fd(open(fname, O_RDONLY)); {
        if(!fd) return false;
    }

    return true;
}

struct mfile {
    char * data {nullptr}; size_t size {0};

    mfile(const char * fname, bool write = false) {
        autofd fd(open(fname, write ? O_RDWR : O_RDONLY)); {
            fd || fatal("failed to open file %s", fname);
        }

        struct stat st; fstat(fd, &st);

        data = (char *)mmap(0, size = st.st_size, PROT_READ | (write ? PROT_WRITE : 0), MAP_SHARED, fd, 0);

        (((intptr_t)data) != -1) || fatal("failed to mmap file %s", fname);
    }

    mfile(mfile const &) = delete;

    mfile(mfile && x) : data(x.data), size(x.size) { x.data = nullptr; }

    ~mfile() { if(data) munmap(data, size); }

    operator char *() const { return (char *)data; }

    operator std::string_view() const { return std::string_view(data, size); }

    // F: int(char * start, char * end)
    template<typename F>
    void each_line(F && f) {
        char *p = data, *q = data + size;

        char * start = p; while(p < q) {
            if(*p == '\n') {
                const char * end = (p > start && p[-1] == '\r') ? (p - 1) : p;

                if constexpr(std::is_void_v<decltype(f(start, end))>) f(start, end); else {
                    if(f(start, end) != 0) return;
                }

                start = p + 1;
            }

            ++p;
        }
    }
};

struct afile {
    autofd fd {-1};

    afile(const char * fname, int mode = O_RDONLY) : fd {open(fname, mode)} {
        !!fd || fatal("failed to open file %s", fname);
    }

    afile(afile const &) = delete;

    afile(afile && x) : fd(x.fd.detach()) {}

    size_t size() {
        struct stat st; fstat(fd, &st); return st.st_size;
    }

    std::string read(size_t toread = -1) {
        std::string s;

        s.resize(toread = std::min(toread, size()));

        ::read(fd, (char *)s.c_str(), toread);

        return s;
    }
};