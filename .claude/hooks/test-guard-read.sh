#!/usr/bin/env bash
set -euo pipefail

HOOK="$(dirname "$0")/guard-read.sh"
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

echo "=== guard-read.sh tests ==="

# BLOCK
run_test ".env"                '{"file_path":"/project/.env"}'                  2
run_test ".env.local"          '{"file_path":"/project/.env.local"}'             2
run_test ".env.production"     '{"file_path":"/project/.env.production"}'        2
run_test "bun.lock"            '{"file_path":"/project/bun.lock"}'               2
run_test "bun.lockb"           '{"file_path":"/project/bun.lockb"}'              2
run_test "package-lock.json"   '{"file_path":"/project/package-lock.json"}'      2
run_test "yarn.lock"           '{"file_path":"/project/yarn.lock"}'              2
run_test "pnpm-lock.yaml"      '{"file_path":"/project/pnpm-lock.yaml"}'         2
run_test "node_modules file"   '{"file_path":"/project/node_modules/react/index.js"}'  2

# ALLOW
run_test ".env.example"        '{"file_path":"/project/.env.example"}'           0
run_test "src file"            '{"file_path":"/project/src/index.ts"}'            0
run_test "CLAUDE.md"           '{"file_path":"/project/CLAUDE.md"}'              0
run_test "package.json"        '{"file_path":"/project/package.json"}'           0

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
