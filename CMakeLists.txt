cmake_minimum_required(VERSION 3.28)
cmake_policy(SET CMP0077 NEW) # honor cache var overrides in subprojects

project(resonance
        VERSION 0.0.0
        DESCRIPTION "C library: resonance"
        LANGUAGES C
)

# C standard
set(CMAKE_C_STANDARD 90)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

# Options
option(resonance_BUILD_APP   "Build demo console app (src/main.c)" ON)
option(resonance_BUILD_TESTS "Build tests in /tests"               ON)
option(BUILD_SHARED_LIBS     "Build shared instead of static"      OFF)

# Superproject toggle: use submodules here, or consume installed packages
option(RESONANCE_USE_BUNDLED_SUBMODULES "Add submodules from external/*" ON)

include(GNUInstallDirs)

# ------------------- Dependencies (discover & select) -------------------
# Accumulate dependency targets here; we link them after add_library().
set(RESONANCE_PUBLIC_DEPS  "")
set(RESONANCE_PRIVATE_DEPS "")

# --- Cache definitions that Projects depend on ---
set(NEXUS_DOUBLE_PRECISION ON CACHE BOOL "" FORCE)

if(RESONANCE_USE_BUNDLED_SUBMODULES)
  set(nexus_BUILD_APP   OFF CACHE BOOL "" FORCE)
  set(nexus_BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(blaze_BUILD_APP   OFF CACHE BOOL "" FORCE)
  set(blaze_BUILD_TESTS OFF CACHE BOOL "" FORCE)

  # Add the submodules exactly once (order ensures transitive targets exist)
  add_subdirectory(external/nexus)  # defines nexus::nexus
  add_subdirectory(external/blaze)  # blaze should PUBLIC-link nexus
else()
  # Fallback to installed packages (or provided by a parent superproject)
  if(NOT TARGET nexus::nexus)
    find_package(nexus CONFIG REQUIRED)
  endif()
  if(NOT TARGET blaze::blaze)
    find_package(blaze CONFIG REQUIRED)
  endif()
endif()

# Decide visibility for resonance's direct deps:
list(APPEND RESONANCE_PUBLIC_DEPS  blaze::blaze)
list(APPEND RESONANCE_PUBLIC_DEPS  nexus::nexus)

# ------------------------------------------------------------------------

# ------------------- Resonance library -------------------
# Sources (exclude app entry from the library)
file(GLOB_RECURSE resonance_SOURCES CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/src/*.c"
)
list(FILTER resonance_SOURCES EXCLUDE REGEX "/main\\.c$")

add_library(resonance ${resonance_SOURCES})
add_library(resonance::resonance ALIAS resonance)

set_target_properties(resonance PROPERTIES
        POSITION_INDEPENDENT_CODE ON
        VERSION   0.0.0
        SOVERSION 0
)

target_include_directories(resonance
        PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)

# ---- Apply dependency link interfaces (must be after add_library) ----
target_link_libraries(resonance
        PUBLIC  ${RESONANCE_PUBLIC_DEPS}
        PRIVATE ${RESONANCE_PRIVATE_DEPS}
)

# Warnings on MSVC/clang-cl
if (CMAKE_C_COMPILER_ID STREQUAL "Clang")
  target_compile_options(resonance PRIVATE /W4)
elseif (MSVC)
  target_compile_options(resonance PRIVATE /W4)
endif()

# ------------------- Demo app (optional) -------------------
if(resonance_BUILD_APP)
  add_executable(resonance_app src/main.c)
  target_link_libraries(resonance_app PRIVATE resonance::resonance)
endif()

# ------------------- Tests (optional) -------------------
if(resonance_BUILD_TESTS)
  enable_testing()
  add_executable(resonance_tests tests/entry.c)
  target_link_libraries(resonance_tests PRIVATE resonance::resonance)
  add_test(NAME resonance.basic COMMAND resonance_tests)
endif()

# ------------------- Install & export -------------------
# If this repo is an umbrella only, you can disable install by default:
option(RESONANCE_ENABLE_INSTALL "Install resonance package from this superproject" ON)

if(RESONANCE_ENABLE_INSTALL)
  include(CMakePackageConfigHelpers)

  install(TARGETS resonance
          EXPORT resonanceTargets
          ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
          LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
          RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
  )

  install(DIRECTORY include/ DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})

  configure_package_config_file(
          ${CMAKE_CURRENT_SOURCE_DIR}/cmake/resonance-config.cmake.in
          ${CMAKE_CURRENT_BINARY_DIR}/resonance-config.cmake
          INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/resonance
  )

  write_basic_package_version_file(
          ${CMAKE_CURRENT_BINARY_DIR}/resonance-config-version.cmake
          VERSION 0.0.0
          COMPATIBILITY SameMajorVersion
  )

  install(FILES
          ${CMAKE_CURRENT_BINARY_DIR}/resonance-config.cmake
          ${CMAKE_CURRENT_BINARY_DIR}/resonance-config-version.cmake
          DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/resonance
  )

  install(EXPORT resonanceTargets
          NAMESPACE resonance::
          DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/resonance
  )

  # Build-tree export for add_subdirectory consumers
  export(EXPORT resonanceTargets
          NAMESPACE resonance::
          FILE ${CMAKE_CURRENT_BINARY_DIR}/resonanceTargets.cmake
  )
endif()
