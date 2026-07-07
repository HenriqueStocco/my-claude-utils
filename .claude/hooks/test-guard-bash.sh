#!/usr/bin/env bash
set -euo pipefail

HOOK="$(dirname "$0")/guard-bash.sh"
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
    echo "  FAIL: $desc (expected exit $expect_exit, got $actual_exit)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== guard-bash.sh tests ==="

# --- Must BLOCK (exit 2) ---
run_test "rm -rf"              '{"command":"rm -rf /tmp/test"}'                  2
run_test "rm -rf variant"      '{"command":"rm -Rf /home/user"}'                 2
run_test "cat .env"            '{"command":"cat .env"}'                          2
run_test "tail .env.local"     '{"command":"tail .env.local"}'                   2
run_test "psql"                '{"command":"psql postgres://user:pass@host/db"}' 2
run_test "pg_dump"             '{"command":"pg_dump -h localhost mydb"}'         2
run_test "cat bun.lock"        '{"command":"cat bun.lock"}'                      2
run_test "find node_modules"   '{"command":"find . -name node_modules"}'         2
run_test "bad commit format"   '{"command":"git commit -m \"fix stuff\""}'       2
run_test "commit too long"     '{"command":"git commit -m \"fix(auth): this message is way too long and exceeds the seventy two character limit here\""}'  2
run_test "git add -A"          '{"command":"git add -A"}'                          2
run_test "git add ."           '{"command":"git add ."}'                           2

# --- Validate JSON output ---
desc="rm -rf: JSON output is valid block decision"
output=""
actual_exit=0
output=$(echo '{"command":"rm -rf /tmp/test"}' | bash "$HOOK" 2>/dev/null) || actual_exit=$?
if [ "$actual_exit" -ne 2 ]; then
  echo "  FAIL: $desc (expected exit 2, got $actual_exit)"
  FAIL=$((FAIL + 1))
elif ! echo "$output" | grep -qE '"decision"\s*:\s*"block"'; then
  echo "  FAIL: $desc (expected JSON decision:block in output)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: $desc"
  PASS=$((PASS + 1))
fi

# --- Must ALLOW (exit 0) ---
run_test "git diff"            '{"command":"git diff HEAD"}'                     0
run_test "git status"          '{"command":"git status"}'                        0
run_test "bun run dev"         '{"command":"bun run dev"}'                       0
run_test "cat .env.example"    '{"command":"cat .env.example"}'                  0
run_test "valid commit"        '{"command":"git commit -m \"fix(auth): correct bearer token extraction\""}'  0
run_test "commit no -m"        '{"command":"git commit"}'                        0
run_test "git add specific"    '{"command":"git add src/components/Button.tsx"}'  0
run_test "heredoc commit"      '{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nfix(auth): correct bearer token\nEOF\n)\""}'  0

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
