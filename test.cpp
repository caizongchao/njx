#include "ljx.h"
#include <assert.h>

int foo() { return 0; }

int main() {
    task t([]() {
        printf("hello world\n");
        return 0;
    });

    t.resume();

    printf("foo bar\n");

    return 0;
}