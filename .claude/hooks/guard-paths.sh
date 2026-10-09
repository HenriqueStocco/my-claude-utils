#!/usr/bin/env bash
# Hook PreToolUse: aplica .claudeignore às ferramentas de arquivo e ao Bash,
# bloqueia leitura sem limite de arquivos grandes e conteúdo com segredos.
# Exit 2 bloqueia a chamada; o texto em stderr chega ao modelo.
# Qualquer erro interno também bloqueia (fail closed).
set -euo pipefail

readonly ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
readonly IGNORE_FILE="$ROOT/.claudeignore"
readonly MAX_READ_BYTES=262144

die() {
  echo "[guard] BLOQUEADO: $*" >&2
  exit 2
}

trap 'die "erro interno do guard (linha $LINENO)"' ERR

if ! command -v jq >/dev/null 2>&1; then
  die "jq não encontrado. Instale-o para o guard funcionar."
fi

# Resolve "." e ".." textualmente e devolve o caminho sem barra inicial.
normalize() {
  local -a parts=()
  local -a stack=()
  local part

  IFS=/ read -ra parts <<< "$1" || true

  for part in ${parts[@]+"${parts[@]}"}; do
    case "$part" in
      ''|.) ;;
      ..) if (( ${#stack[@]} > 0 )); then unset 'stack[-1]'; fi ;;
      *) stack+=("$part") ;;
    esac
  done

  (IFS=/; printf '%s' "${stack[*]:-}")
}

input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<< "$input")"
BASE="$(jq -r '.cwd // ""' <<< "$input")"
[[ -n "$BASE" ]] || BASE="$ROOT"
readonly ROOT_N="$(normalize "$ROOT")"

# Imprime o caminho relativo à raiz do projeto. Retorna 1 se estiver fora dela.
to_root_relative() {
  local abs

  if [[ "$1" == /* ]]; then
    abs="$(normalize "$1")"
  else
    abs="$(normalize "$BASE/$1")"
  fi

  if [[ "$abs" == "$ROOT_N" ]]; then
    printf '.'
  elif [[ "$abs" == "$ROOT_N"/* ]]; then
    printf '%s' "${abs#"$ROOT_N"/}"
  else
    return 1
  fi
}

# Verdadeiro se o caminho relativo casa com um padrão no formato gitignore.
# Aproximação: `*` também casa `/`, então o resultado erra para o lado seguro.
matches_pattern() {
  local rel="$1"
  local pat="$2"
  local anchored=0

  pat="${pat%/}"

  if [[ "$pat" == /* ]]; then
    pat="${pat#/}"
    anchored=1
  elif [[ "$pat" == */* && "$pat" != \*\*/* ]]; then
    anchored=1
  fi

  pat="${pat#\*\*/}"

  if (( anchored )); then
    [[ "$rel" == $pat || "$rel" == $pat/* ]]
  else
    [[ "$rel" == $pat || "$rel" == */$pat || "$rel" == $pat/* || "$rel" == */$pat/* ]]
  fi
}

# Verdadeiro se o caminho relativo está listado em .claudeignore.
is_ignored() {
  local rel="$1"
  local line
  local ignored=0

  [[ -f "$IGNORE_FILE" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"

    if [[ -z "$line" || "$line" == \#* ]]; then
      continue
    fi

    if [[ "$line" == !* ]]; then
      if matches_pattern "$rel" "${line#!}"; then
        ignored=0
      fi
    elif matches_pattern "$rel" "$line"; then
      ignored=1
    fi
  done < "$IGNORE_FILE"

  (( ignored ))
}

check_path() {
  local rel

  if rel="$(to_root_relative "$1")" && is_ignored "$rel"; then
    die "\"$rel\" está listado em .claudeignore. Não leia, altere nem use esse caminho. Se ele for indispensável, peça ao usuário."
  fi
}

# Bloqueia leitura sem `limit` de arquivos acima de MAX_READ_BYTES.
check_read_size() {
  local file
  local size

  if [[ -n "$(jq -r '.tool_input.limit // empty' <<< "$input")" ]]; then
    return 0
  fi

  if [[ "$1" == /* ]]; then
    file="$1"
  else
    file="$BASE/$1"
  fi

  [[ -f "$file" ]] || return 0

  size="$(wc -c < "$file")"

  if (( size > MAX_READ_BYTES )); then
    die "arquivo com ${size} bytes excede o limite de leitura. Use offset e limit para ler trechos."
  fi
}

# Bloqueia escrita de conteúdo que parece segredo (chave privada, chave AWS, token GitHub).
check_secrets() {
  local text

  text="$(jq -r '[.tool_input.content?, .tool_input.new_string?, .tool_input.edits[]?.new_string?] | map(select(type == "string")) | .[]' <<< "$input")"

  if grep -Eq -e '-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----' -e 'AKIA[0-9A-Z]{16}' -e 'gh[pousr]_[A-Za-z0-9]{36}' <<< "$text"; then
    die "o conteúdo parece conter segredo. Remova o valor e use variável de ambiente ou um arquivo já ignorado."
  fi
}

# Verifica cada palavra do comando Bash como possível caminho (best effort).
check_bash() {
  local cmd
  local tok
  local -a tokens=()

  cmd="$(jq -r '.tool_input.command // ""' <<< "$input" | tr '\n\t;&|()<>`' '          ')"
  read -ra tokens <<< "$cmd" || true

  for tok in ${tokens[@]+"${tokens[@]}"}; do
    tok="${tok//[\'\"]/}"
    tok="${tok##*=}"

    if [[ -n "$tok" ]]; then
      check_path "$tok"
    fi
  done
}

case "$tool" in
  Read|Edit|Write|MultiEdit|Grep|Glob)
    file_path="$(jq -r '.tool_input.file_path // .tool_input.path // ""' <<< "$input")"

    if [[ -n "$file_path" ]]; then
      check_path "$file_path"
    fi

    if [[ "$tool" == Read && -n "$file_path" ]]; then
      check_read_size "$file_path"
    fi

    if [[ "$tool" == Write || "$tool" == Edit || "$tool" == MultiEdit ]]; then
      check_secrets
    fi
    ;;
  Bash)
    check_bash
    ;;
esac

exit 0
