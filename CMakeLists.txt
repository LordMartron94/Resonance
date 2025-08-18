cmake_minimum_required(VERSION 3.28)

# --- Project meta (filled by your generator) ---
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
option(BUILD_SHARED_LIBS           "Build shared instead of static"      OFF)

include(GNUInstallDirs)

# ---- Sources (recursively, exclude app entry from the lib) ----
file(GLOB_RECURSE resonance_SOURCES CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/src/*.c"
)
list(FILTER resonance_SOURCES EXCLUDE REGEX "/main\\.c$")

# ---- Library ----
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

# (Optional) warnings on MSVC/clang-cl
if (CMAKE_C_COMPILER_ID STREQUAL "Clang")
  target_compile_options(resonance PRIVATE /W4)
elseif (MSVC)
  target_compile_options(resonance PRIVATE /W4)
endif()

# ---- Demo app (optional) ----
if(resonance_BUILD_APP)
  add_executable(resonance_app src/main.c)
  target_link_libraries(resonance_app PRIVATE resonance::resonance)
endif()

# ---- Tests (optional & minimal) ----
if(resonance_BUILD_TESTS)
  enable_testing()
  add_executable(resonance_tests tests/entry.c)
  target_link_libraries(resonance_tests PRIVATE resonance::resonance)
  add_test(NAME resonance.basic COMMAND resonance_tests)
endif()

# ---- Install & export (find_package support) ----
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

export(EXPORT resonanceTargets
  NAMESPACE resonance::
  FILE ${CMAKE_CURRENT_BINARY_DIR}/resonanceTargets.cmake
)
