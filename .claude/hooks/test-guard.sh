#!/usr/bin/env bash
# Testes do guard-paths.sh. Cada caso roda o hook num projeto temporário
# e compara o código de saída: 0 = permitido, 2 = bloqueado.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guard="$here/guard-paths.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

project="$tmp/project"
mkdir -p "$project/src" "$project/secrets"
printf '.env\n.env.*\n!.env.example\n*.pem\n.ssh/\nsecrets/\n' > "$project/.claudeignore"
printf 'SECRET=1\n' > "$project/.env"
printf 'SECRET=1\n' > "$project/.env.example"
printf 'x\n' > "$project/src/app.ts"
printf 'x\n' > "$project/src/key.pem"
printf 'x\n' > "$project/secrets/token.txt"
head -c 300000 /dev/zero > "$project/big.log"

failures=0

# run <código esperado> <nome> <ferramenta> <tool_input em JSON>
run() {
  local want="$1"
  local name="$2"
  local tool="$3"
  local input="$4"
  local got=0

  jq -nc --arg tool "$tool" --arg cwd "$project" --argjson input "$input" \
    '{tool_name: $tool, cwd: $cwd, tool_input: $input}' \
    | CLAUDE_PROJECT_DIR="$project" "$guard" >/dev/null 2>&1 || got=$?

  if [[ "$got" == "$want" ]]; then
    echo "ok    $name"
  else
    echo "FAIL  $name (esperado $want, obtido $got)"
    failures=$((failures + 1))
  fi
}

run 2 "Read bloqueia .env"                 Read "{\"file_path\":\"$project/.env\"}"
run 0 "Read permite .env.example (negação)" Read "{\"file_path\":\"$project/.env.example\"}"
run 0 "Read permite arquivo comum"          Read "{\"file_path\":\"$project/src/app.ts\"}"
run 2 "Read bloqueia *.pem em subpasta"     Read "{\"file_path\":\"$project/src/key.pem\"}"
run 2 "Read bloqueia diretório secrets/"    Read "{\"file_path\":\"$project/secrets/token.txt\"}"
run 2 "Read bloqueia caminho com .. escapando"  Read "{\"file_path\":\"$project/src/../.env\"}"
run 2 "Read bloqueia caminho relativo"      Read "{\"file_path\":\".env\"}"
run 2 "Read sem limit em arquivo grande"    Read "{\"file_path\":\"$project/big.log\"}"
run 0 "Read com limit em arquivo grande"    Read "{\"file_path\":\"$project/big.log\",\"limit\":100}"
run 2 "Grep bloqueia path ignorado"         Grep "{\"pattern\":\"x\",\"path\":\"$project/.env\"}"
run 2 "Glob bloqueia path ignorado"         Glob "{\"pattern\":\"*\",\"path\":\"$project/secrets\"}"
run 2 "Write bloqueia .env"                 Write "{\"file_path\":\"$project/.env\",\"content\":\"A=1\"}"
run 0 "Write permite arquivo comum"         Write "{\"file_path\":\"$project/src/app.ts\",\"content\":\"ok\"}"
run 2 "Write bloqueia chave privada"        Write "{\"file_path\":\"$project/src/novo.ts\",\"content\":\"-----BEGIN RSA PRIVATE KEY-----\"}"
run 2 "Edit bloqueia token AWS em new_string" Edit "{\"file_path\":\"$project/src/app.ts\",\"old_string\":\"x\",\"new_string\":\"AKIAABCDEFGHIJKLMNOP\"}"
run 2 "MultiEdit bloqueia token GitHub"     MultiEdit "{\"file_path\":\"$project/src/app.ts\",\"edits\":[{\"old_string\":\"x\",\"new_string\":\"ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJ\"}]}"
run 2 "Bash bloqueia cat .env"              Bash "{\"command\":\"cat .env\"}"
run 2 "Bash bloqueia redirecionamento <.env" Bash "{\"command\":\"grep A<.env\"}"
run 2 "Bash bloqueia --file=.env"          Bash "{\"command\":\"tool --file=.env\"}"
run 2 "Bash bloqueia encadeado com &&"     Bash "{\"command\":\"ls && cat .env\"}"
run 0 "Bash permite .env.example"          Bash "{\"command\":\"cat .env.example\"}"
run 0 "Bash permite comando sem caminho sensível" Bash "{\"command\":\"git status --short\"}"
run 0 "Ferramenta não coberta passa"        Skill "{\"skill\":\"x\"}"

# JSON inválido precisa bloquear (fail closed), não permitir
bad_json_got=0
echo 'não é json' | CLAUDE_PROJECT_DIR="$project" "$guard" >/dev/null 2>&1 || bad_json_got=$?

if [[ "$bad_json_got" == 2 ]]; then
  echo "ok    JSON inválido bloqueia (fail closed)"
else
  echo "FAIL  JSON inválido bloqueia (esperado 2, obtido $bad_json_got)"
  failures=$((failures + 1))
fi

echo
if (( failures > 0 )); then
  echo "$failures teste(s) falharam."
  exit 1
fi

echo "Todos os testes passaram."
