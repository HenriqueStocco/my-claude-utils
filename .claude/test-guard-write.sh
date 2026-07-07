#!/usr/bin/env bash
set -euo pipefail

HOOK="$(dirname "$0")/guard-write.sh"
PASS=0
FAIL=0

run_test() {
  local desc="$1"
  local input="$2"
  local expect_exit="$3"

  actual_exit=0
  echo "$input" | bash "$HOOK" > /dev/null 2>&1 || actual_exit=$?

  if [ "$actual_exit" -eq "$expect_exit" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected $expect_exit, got $actual_exit)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== guard-write.sh tests ==="

# BLOCK
run_test ".env"                '{"file_path":"/project/.env"}'                  2
run_test ".env.local"          '{"file_path":"/project/.env.local"}'             2
run_test "node_modules"        '{"file_path":"/project/node_modules/x/y.js"}'   2
run_test "bun.lock"            '{"file_path":"/project/bun.lock"}'               2
run_test "bun.lockb"           '{"file_path":"/project/bun.lockb"}'              2

# ALLOW
run_test ".env.example"        '{"file_path":"/project/.env.example"}'           0
run_test "src file"            '{"file_path":"/project/src/component.tsx"}'      0
run_test "CLAUDE.md"           '{"file_path":"/project/CLAUDE.md"}'              0

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
