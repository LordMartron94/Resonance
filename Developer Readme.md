# Adding Dependencies (C89 template)

This project is designed to work in two modes:

1. **Superproject (bundled)** – submodules under `external/` are added via `add_subdirectory`.
2. **Installed packages** – dependencies are found with `find_package(... CONFIG)`.

---

## When you add a new dependency “Foo”

### 1) In this library (repo)
- **Link it on the target with correct visibility**
    - `PUBLIC` if your public headers include `<foo/...>` or expose Foo types.
    - `PRIVATE` if it’s only used in `.c` files.
  ```cmake
  target_link_libraries(${PROJECT_NAME}
    PUBLIC  foo::foo   # or PRIVATE, as appropriate
  )
  
- **If Foo is PUBLIC/INTERFACE, update your package config**
  - Edit c`make/${PROJECT_NAME}-config.cmake.in`:
    ```text
    @PACKAGE_INIT@
    include(CMakeFindDependencyMacro)
    find_dependency(foo CONFIG REQUIRED)  # optionally: find_dependency(foo 1.2 CONFIG REQUIRED)
    include("${CMAKE_CURRENT_LIST_DIR}/${PROJECT_NAME}Targets.cmake")
    ```
  - This ensures consumers of your installed package get Foo too.
- **Keep includes namespaced**
  - Place public headers under `include/${PROJECT_NAME}/`.
  - Include dependencies as `#include <foo/foo.h>` (never with repo-relative paths).
### 2) In the superproject (orchestrator)
- **Add the submodule once** under `external/` (only in the superproject; libs don’t vendor deps):
    ```
    external/foo/   # submodule
    ```
- **Before** `add_subdirectory(external/foo)`, disable Foo’s demos/tests if you don’t need them:
    ```text
    set(foo_BUILD_APP   OFF CACHE BOOL "" FORCE)
    set(foo_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    add_subdirectory(external/foo)
    ```
- **Order matters**: add Foo before any lib that depends on it.
- **Don’t duplicate**: ensure only one add_subdirectory for each dependency.
### 3) Visibility quick guide
- `PUBLIC` → dependency is part of your API surface (in headers or link interface).
- `PRIVATE` → implementation detail (only in `.c`).
- `INTERFACE` → header-only propagation (rare for C libs, but possible).

### 4) Common pitfalls to avoid
- **Recursive submodules**: submodule deps only in the superproject, not inside libs.
- **Wrong include style**: always `#include <foo/...>;` never relative paths to `external/foo`.
- **Missing find_dependency**: if you PUBLIC-link a dep, consumers of your installed package need it.
### 5) Optional: version pinning
If you rely on features introduced in Foo 1.3:
```
find_dependency(foo 1.3 CONFIG REQUIRED)
```
### 6) Testing in both modes
- Superproject:
```bash
cmake --preset clangcl-debug
cmake --build --preset clangcl-debug
```
- Installed:
```bash
cmake -S foo -B foo/build && cmake --build foo/build && cmake --install foo/build --prefix out
cmake -S mylib -B mylib/build -D CMAKE_PREFIX_PATH=foo/out
cmake --build mylib/build
```
