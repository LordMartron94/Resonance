#include <stdio.h>
#include <stdlib.h>
#include <nexus/nexus.h>

static const char *token;

int main(void) {
    nexus_u32 randomSeed = nexus_randomness_seed_per_run(token);
    nexus_u32 randomInt = nexus_randomness_integer_random(randomSeed);

    printf("Random seed: %u\n", randomInt);

    return EXIT_SUCCESS;
}
