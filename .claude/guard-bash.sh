#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.command // ""')

block() {
  jq -n --arg reason "$1" '{"decision":"block","reason":$reason}'
  exit 2
}

# rm -rf in any form
if echo "$CMD" | grep -qiE 'rm\s+(-[a-zA-Z]*[rR][a-zA-Z]*[fF]|-[fF][a-zA-Z]*[rR]|--recursive\s+--force|--force\s+--recursive)'; then
  block "rm -rf is prohibited. This is a hard safety rule. Delete files manually or request explicit developer permission."
fi

# .env reads via bash — match any .env access, then exclude .env.example
if echo "$CMD" | grep -qE '(cat|head|tail|less|more|grep|sed|awk)\s+[^|]*\.env'; then
  if ! echo "$CMD" | grep -qE '\.env\.example'; then
    block ".env files must not be read. They contain secrets. Use .env.example for reference."
  fi
fi

# Direct DB connection
if echo "$CMD" | grep -qE '(psql|pg_dump|pg_restore|pg_basebackup)\b'; then
  block "Direct database connections are prohibited. Never run psql/pg_dump/pg_restore autonomously, even with found credentials."
fi

# Database migrations
if echo "$CMD" | grep -qE 'drizzle-kit\s+(push|generate|drop|migrate)\b|bun\s+run\s+db:(push|generate|drop|migrate)\b'; then
  block "Database migrations are prohibited. Migrations are the developer's exclusive responsibility. Do not run db:push, db:generate, or drizzle-kit commands."
fi

# Lockfile reads
if echo "$CMD" | grep -qE '(cat|head|tail|less|more)\s+[^|]*(bun\.lock|bun\.lockb|package-lock\.json|yarn\.lock|pnpm-lock\.yaml)'; then
  block "Lockfiles must not be read. bun.lock/bun.lockb are managed by the package manager."
fi

# node_modules exploration
if echo "$CMD" | grep -qE '(find|ls)\s+[^|]*node_modules'; then
  block "Exploring node_modules is not allowed. Use package documentation instead."
fi

# git add -A / git add . — prohibited, always stage specific files
if echo "$CMD" | grep -qE 'git\s+add\s+(-A|\.)\s*($|\s)'; then
  block "git add -A and git add . are prohibited. Stage specific files by name: git add <file1> <file2>"
fi

# Conventional commits validation (only when -m "..." is present)
if echo "$CMD" | grep -qE 'git\s+(commit)'; then
  MSG=""
  # Try -m "..." pattern
  if echo "$CMD" | grep -qE '\-m\s+"'; then
    MSG=$(echo "$CMD" | grep -oP '(?<=-m ")[^"]+' | head -1)
  fi
  # Try -m '...' pattern
  if [ -z "$MSG" ] && echo "$CMD" | grep -qE "\-m\s+'"; then
    MSG=$(echo "$CMD" | grep -oP "(?<=-m ')[^']+" | head -1)
  fi

  # HEREDOC form — cannot parse at hook time, allow it
  if echo "$MSG" | grep -qE '^\$\(cat\s*<<'; then
    MSG=""
  fi

  if [ -n "$MSG" ]; then
    FIRST_LINE=$(echo "$MSG" | head -1)
    LINE_LEN=${#FIRST_LINE}

    if [ "$LINE_LEN" -gt 72 ]; then
      block "Commit message too long: $LINE_LEN chars (max 72). Shorten: \"$FIRST_LINE\""
    fi

    if ! echo "$FIRST_LINE" | grep -qE '^(feat|fix|chore|refactor|test|docs|style|perf|ci|build|revert)(\([a-z0-9/\-]+\))?: .+'; then
      block "Commit must follow Conventional Commits: type(scope): description (max 72 chars). Valid types: feat|fix|chore|refactor|test|docs|style|perf|ci|build|revert. Example: fix(auth): correct bearer token extraction"
    fi
  fi
fi

exit 0
