#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.file_path // ""')

block() {
  jq -n --arg reason "$1" '{"decision":"block","reason":$reason}'
  exit 2
}

# .env files (allow .env.example)
if echo "$FILE" | grep -qE '(^|/)\.env([^a-zA-Z.]|$|\..+)' && ! echo "$FILE" | grep -qE '\.env\.example$'; then
  block ".env files must not be read — they contain secrets. Use .env.example for non-secret reference."
fi

# Lockfiles
if echo "$FILE" | grep -qE '(^|/)(bun\.lock|bun\.lockb|package-lock\.json|yarn\.lock|pnpm-lock\.yaml)$'; then
  block "Lockfiles must not be read without explicit permission."
fi

# node_modules
if echo "$FILE" | grep -qE '/node_modules/'; then
  block "node_modules must not be read without explicit permission. Use package documentation."
fi

exit 0
