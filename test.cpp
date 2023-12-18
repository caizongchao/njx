#include "ljx.h"
#include <assert.h>

#ifdef __x86_64__
int a = 1;
#else
int a = 2;
#endif

int foo() { return 0; }

int main() {
    task t([]() {
        printf("hello world\n");
        return 0;
    });

    t.resume();

    printf("foo bar: %d\n", a);

    return 0;
}