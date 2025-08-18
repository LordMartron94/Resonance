#include <stdio.h>
#include <blaze/blaze.h>
#include "resonance/resonance.h"

int main(void) {
    printf("[resonance] Hello from demo app!\n");
    printf("[resonance] version = %s\n", resonance_version_string());

    printf("[blaze] multiply (5, 5) = %d\n", blaze_int_multiply(5, 5));
    return 0;
}
