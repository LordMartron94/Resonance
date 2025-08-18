#include <stdio.h>
#include <stdlib.h>
#include "resonance/resonance.h"

int main(void) {
    int ok = 1;

    if (resonance_add(2, 3) != 5) {
        fprintf(stderr, "add(2,3) != 5\n");
        ok = 0;
    }

    if (resonance_version_string() == NULL) {
        fprintf(stderr, "version_string() returned NULL\n");
        ok = 0;
    }

    if (!ok) {
        return EXIT_FAILURE;
    }

    puts("basic test passed");
    return EXIT_SUCCESS;
}
