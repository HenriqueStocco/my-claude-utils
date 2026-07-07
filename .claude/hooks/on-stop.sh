#!/usr/bin/env bash

MODIFIED=$(git status --short 2>/dev/null)

if [ -n "$MODIFIED" ]; then
  echo "=== Modified files this session ==="
  echo "$MODIFIED"
else
  echo "=== No modified files ==="
fi

exit 0
