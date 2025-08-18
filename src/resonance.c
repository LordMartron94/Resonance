#include <stdio.h>
#include "resonance/resonance.h"

/* Simple example API impl */
int resonance_add(int a, int b) {
    return a + b;
}

const char* resonance_version_string(void) {
    /* Keep this tiny and compile-time only */
    return "0.0.0";
}
