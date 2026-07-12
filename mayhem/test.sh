#!/usr/bin/env bash
#
# mayhem/test.sh — behavioral known-answer oracle for the mac-improved VM (build-oracle/mac, built by
# mayhem/build.sh with normal flags). RUNS only; never compiles.
#
# UPSTREAM SUITE: felixangell/mac ships NO runnable functional test suite. Its Makefile `test` target
# is just `./mac` on the toy root VM (hardcoded program, prints "done"), with no assertions; mac-improved
# has no test target at all. So there is nothing to wire (tests_found = 0). We author a known-answer
# oracle instead: feed the VM small programs whose arithmetic results we compute by hand and assert the
# exact `a op b = c` lines eval() prints. A no-op / exit(0) sabotage of the program prints nothing and
# FAILS every assertion (anti-reward-hack: the sabotage gate neuters the binary to _exit(0)).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "${SRC:-/mayhem}"

MAC=build-oracle/mac
passed=0; failed=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   - $1"; passed=$((passed+1)); else echo "  FAIL - $1"; failed=$((failed+1)); fi; }

emit_ctrf() {
  local tool="$1" p="$2" f="$3" s="${4:-0}"; local tests=$(( p + f + s ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": { "tests": $tests, "passed": $p, "failed": $f, "pending": 0, "skipped": $s, "other": 0 }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":0,"skipped":%d,"other":0}}}\n' \
    "$tool" "$tests" "$p" "$f" "$s"
  [ "$f" -eq 0 ]
}

if [ ! -x "$MAC" ]; then
  echo "test.sh: oracle binary $MAC missing — build.sh must build it (not rebuilding here)" >&2
  emit_ctrf mac-knownanswer 0 1; exit 1
fi

TD="$(mktemp -d)"
# Each program: PSH a, PSH b, <op>. eval() prints "<b> <op> <a> = <result>" (b is the first-pushed
# operand, a the second). Opcodes: PSH=1 ADD=3 MUL=4 DIV=5 SUB=6.
printf '1 7 1 8 3\n'   > "$TD/add.mac"   # 7 + 8 = 15
printf '1 3 1 4 4\n'   > "$TD/mul.mac"   # 3 * 4 = 12
printf '1 10 1 3 6\n'  > "$TD/sub.mac"   # 10 - 3 = 7
printf '1 20 1 4 5\n'  > "$TD/div.mac"   # 20 / 4 = 5

assert_line() { # <name> <program-file> <expected-line>
  local out; out="$("$MAC" "$2" 2>&1)"
  if grep -qF -- "$3" <<<"$out"; then check "$1 -> '$3'" 0; else check "$1 -> '$3'" 1; fi
}

assert_line "ADD" "$TD/add.mac" "7 + 8 = 15"
assert_line "MUL" "$TD/mul.mac" "3 * 4 = 12"
assert_line "SUB" "$TD/sub.mac" "10 - 3 = 7"
assert_line "DIV" "$TD/div.mac" "20 / 4 = 5"

rm -rf "$TD"
echo "test.sh: passed=$passed failed=$failed"
emit_ctrf mac-knownanswer "$passed" "$failed"
