#!/usr/bin/env bash

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.file_path // ""')

# Only run for .ts and .tsx files
if ! echo "$FILE" | grep -qE '\.(ts|tsx)$'; then
  exit 0
fi

# Run biome check --write silently — never block on failure
bunx biome check --write "$FILE" > /dev/null 2>&1 || true

exit 0
