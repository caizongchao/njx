#include <stdio.h>
#include <stdlib.h>

int main() {
    int rnd = 0;

    int r = getentropy(&rnd, sizeof(rnd));

    printf("r: %d, rnd: %d\n", r, rnd);

    return 0;
}