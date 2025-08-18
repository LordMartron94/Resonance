# Resolve LLVM root (env var preferred, fallback default)
if(DEFINED ENV{LLVM_HOME})
  set(LLVM_HOME "$ENV{LLVM_HOME}")
else()
  set(LLVM_HOME "C:/CLang")
endif()

set(CMAKE_C_COMPILER   "${LLVM_HOME}/bin/clang-cl.exe" CACHE FILEPATH "" FORCE)
set(CMAKE_CXX_COMPILER "${LLVM_HOME}/bin/clang-cl.exe" CACHE FILEPATH "" FORCE)

# MSVC/COFF toolchain pieces
set(CMAKE_LINKER       "${LLVM_HOME}/bin/lld-link.exe"  CACHE FILEPATH "" FORCE)
set(CMAKE_AR           "${LLVM_HOME}/bin/llvm-lib.exe"  CACHE FILEPATH "" FORCE)
set(CMAKE_RANLIB       ""                               CACHE STRING  "" FORCE)
set(CMAKE_RC_COMPILER  "${LLVM_HOME}/bin/llvm-rc.exe"   CACHE FILEPATH "" FORCE)
set(CMAKE_MT           "${LLVM_HOME}/bin/llvm-mt.exe"   CACHE FILEPATH "" FORCE)

# Make try-compile inherit these (prevents RC/MT 'NOTFOUND' issues)
set(CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
    CMAKE_C_COMPILER CMAKE_CXX_COMPILER
    CMAKE_LINKER CMAKE_AR CMAKE_RANLIB
    CMAKE_RC_COMPILER CMAKE_MT)
