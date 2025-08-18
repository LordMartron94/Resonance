#include <stdio.h>
#include "resonance/resonance.h"

int main(void) {
    printf("[resonance] Hello from demo app!\n");
    printf("[resonance] add(2, 3) = %d\n", resonance_add(2, 3));
    printf("[resonance] version = %s\n", resonance_version_string());
    return 0;
}
