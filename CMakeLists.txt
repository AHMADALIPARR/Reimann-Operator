# SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
# Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
cmake_minimum_required(VERSION 3.21)
project(reimann_operator VERSION 0.1.0 LANGUAGES C Fortran)

set(CMAKE_C_STANDARD 23)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# No FMA contraction: the ports reproduce the Python's IEEE operation order.
set(RO_C_FLAGS -Wall -Wextra -Wpedantic -Wshadow -Wstrict-prototypes -ffp-contract=off)
set(RO_F_FLAGS -Wall -ffp-contract=off)

add_library(ro_kernels STATIC kernels/ro_kernels.f90)
target_compile_options(ro_kernels PRIVATE ${RO_F_FLAGS})

add_library(ro_core STATIC src/ro_json.c src/ro_sha256.c src/ro_numpy_rng.c)
target_include_directories(ro_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_compile_options(ro_core PRIVATE ${RO_C_FLAGS})

add_executable(ro src/ro_main.c)
target_link_libraries(ro PRIVATE ro_core ro_kernels m)
target_compile_options(ro PRIVATE ${RO_C_FLAGS})
set_target_properties(ro PROPERTIES LINKER_LANGUAGE Fortran)

install(TARGETS ro RUNTIME DESTINATION bin)

include(CTest)
if(BUILD_TESTING)
  set(RO_ROOT ${CMAKE_CURRENT_SOURCE_DIR})
  # Golden cases: tests/golden/<name>.out was produced by the Python sources.
  file(STRINGS ${RO_ROOT}/tests/cases.txt RO_CASES)
  foreach(line IN LISTS RO_CASES)
    if(line MATCHES "^#" OR line STREQUAL "")
      continue()
    endif()
    separate_arguments(parts UNIX_COMMAND "${line}")
    list(GET parts 0 name)
    add_test(NAME golden_${name}
             COMMAND bash ${RO_ROOT}/tests/run_case.sh $<TARGET_FILE:ro> ${parts}
             WORKING_DIRECTORY ${RO_ROOT})
  endforeach()
  # SoA pack: same bytes as the Python (SHA-256 of its blob), and unpack matches the Python's unpack.
  add_test(NAME golden_pack_unpack
           COMMAND bash -c "set -e; b=${CMAKE_CURRENT_BINARY_DIR}/cands.bin; $<TARGET_FILE:ro> pack tests/fixtures/cands.json $b > /dev/null; test \"$(sha256sum $b | cut -d' ' -f1)\" = \"$(cat tests/golden/cands.bin.sha256)\"; bash tests/run_case.sh $<TARGET_FILE:ro> unpack_cands 0 0 unpack $b"
           WORKING_DIRECTORY ${RO_ROOT})
  # Every zero in the oracle (data/zeta_zeros_oracle.txt) recomputed by the Fortran kernel.
  add_test(NAME oracle_zeros
           COMMAND $<TARGET_FILE:ro> oracle-check data/zeta_zeros_oracle.txt
           WORKING_DIRECTORY ${RO_ROOT})
  set_tests_properties(oracle_zeros PROPERTIES TIMEOUT 600)
endif()
