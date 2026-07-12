#!/usr/bin/env bash
#
# mayhem/build.sh — build the mac VM fuzz target + its behavioral oracle.
#
#   build/fuzz_mac             sanitized + libFuzzer  -> target `mac` (in-process VM harness)
#   build/fuzz_mac-standalone  sanitized              -> run-once reproducer for the same harness
#   build-oracle/mac           normal flags           -> the mac-improved VM, used by mayhem/test.sh
#
# The original fork fuzzed the mac-improved binary as a raw file-input target (`/mac @@`). That code
# path is preserved by driving the exact same fscanf-parse + eval loop from an in-process libFuzzer
# harness (mayhem/fuzz_mac.c) — more edges, no waiting on a batch process per input. No upstream edits.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "${SRC:-/mayhem}"

mkdir -p build build-oracle

# 1) Fuzz target: in-process libFuzzer harness. It #includes mac-improved/mac.c, so the *fuzzed VM
#    code* is compiled with $SANITIZER_FLAGS + $DEBUG_FLAGS (instrumented, DWARF < 4).
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE -w -std=c11 \
    mayhem/fuzz_mac.c -o build/fuzz_mac

# 2) Standalone (non-fuzzer) reproducer: same harness linked against the run-once driver. Compile the
#    driver separately so the -D rename inside fuzz_mac.c can't touch the driver's own main().
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -w -std=c11 \
    mayhem/fuzz_mac.c /tmp/standalone_main.o -o build/fuzz_mac-standalone

# 3) Behavioral oracle: the mac-improved VM built with NORMAL flags (no sanitizers) so mayhem/test.sh
#    is an honest known-answer oracle over the VM's arithmetic. $COVERAGE_FLAGS is empty by default.
# shellcheck disable=SC2086
$CC -O2 -std=c11 -w $COVERAGE_FLAGS mac-improved/mac.c -o build-oracle/mac

echo "build.sh: built build/fuzz_mac, build/fuzz_mac-standalone, build-oracle/mac"
