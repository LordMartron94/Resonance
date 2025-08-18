# resonance

Small C library.

## Build

```bash
cmake -S . -B build -Dresonance_BUILD_APP=ON -Dresonance_BUILD_TESTS=ON
cmake --build build
ctest --test-dir build
```
