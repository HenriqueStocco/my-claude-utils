# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` in the repo root is the canonical deep-dive (schema, routers, flows, infra). Read it when you need detail beyond what's here. This file captures the load-bearing facts and the rules that aren't obvious from the code.

## Stack & tooling

- **Package manager**: Bun `1.1.43` (pinned via `mise.toml` and `engines`). Do not switch to npm/pnpm/yarn — `pnpm-workspace.yaml` exists only for Turborepo's workspace globs.
- **Lint/format**: Biome `1.9.4` (`biome.json` — 2-space, 120 cols, double quotes, semicolons)
- **TypeScript**: `5.9.3`.
- **Local Postgres**: `docker compose up -d` brings up Postgres on `localhost:5432` (postgres/postgres/postgres).

## Safety Rules — O que Claude nunca deve fazer

As regras abaixo são enforced por hooks em `.claude/hooks/`. Violar qualquer uma é um erro de segurança.

- **`rm -rf`** em qualquer forma — proibido. Deletar arquivos requer permissão explícita do desenvolvedor.
- **Ler arquivos `.env*`** (exceto `.env.example`) — contêm secrets. Nunca ler via Read tool ou bash.
- **Executar deploys autônomos** (`wrangler deploy`, `sst deploy`, `wrangler publish`) — requer execução manual do desenvolvedor.
- **`git add`, `git commit`, `git stash`, `git rebase`, `git pull`, `git push`, `git reset`** — nunca sem permissão explícita do usuário. Sempre adicionar arquivos específicos por nome, nunca `git add -A` ou `git add .`.
- **Explorar `node_modules/`** sem permissão — usar documentação dos pacotes.
- **Ler `bun.lock` / `bun.lockb`** sem permissão — são gerenciados pelo package manager.
- **Adicionar ou remover arquivos/diretórios** sem permissão explícita.
- **Usar MCP ou plugins** sem permissão do usuário.
- **Conectar ao banco de dados** (produção, desenvolvimento ou local) — proibido executar `psql`, `pg_dump`, `pg_restore` ou scripts que usem `DATABASE_URL` diretamente.
- **Executar migrations de banco** — proibido rodar `drizzle-kit push/generate/drop/migrate` ou `bun run db:push/generate/drop`. Migrations são responsabilidade exclusiva do desenvolvedor.

## TypeScript Rules

- Sem `any` explícito ou implícito — usar tipos estritos ou `unknown` com type guards.
- Funções não-triviais devem ter retorno tipado explicitamente.
- Tipos de domínio em arquivos dedicados (`types.ts`) — nunca inline no componente.
- Schemas Zod em `schema.ts` — nunca inline no componente.
- Usar `z.infer<typeof schema>` em vez de tipos manuais quando Zod está presente.
- Evitar `undefined` em assinaturas — preferir `| null` ou valores default explícitos.
- Proibido: `as any`, `@ts-ignore`, `@ts-expect-error` sem comentário explicativo do motivo.

Regras — DRY + SOLID + Clean Code:

- **DRY**: lógica idêntica em 2+ lugares → extrair para `path` ou hook compartilhado.
- **Single responsibility** (SOLID S): um hook/componente/função = uma responsabilidade.
- **Componentes puros**: sem lógica de negócio inline — delegar para hooks e utils.
- **Ícones**: sempre Lucide React.
- **Componentes**: sempre `path` antes de criar do zero.
- **Clean Code — Nomes significativos**: evitar abreviações (`usr`, `d`, `tmp`) — preferir `user`, `delivery`, `tempValue`.
- **Clean Code — Funções pequenas**: se a função precisa de comentário para explicar o que faz, deve ser extraída.
- **Clean Code — Sem código morto**: remover imports, variáveis e funções não usadas imediatamente.
- **Clean Code — Comentários apenas para o WHY**: nunca comentar o que o código faz — apenas decisões não-óbvias.
- **Clean Code — Erro explícito**: nunca silenciar com `catch(() => {})` vazio.
- **KISS**: solução mais simples que funciona. Sem abstrações prematuras.

## Conventional Commits

Formato obrigatório: `type(scope): descrição curta` — **máximo 72 caracteres total**.

Tipos válidos: `feat | fix | chore | refactor | test | docs | style | perf | ci | build | revert`

Referência: https://www.conventionalcommits.org/en/v1.0.0/

Enforcement: hook `guard-bash.sh` bloqueia commits que violam formato ou tamanho.

Exemplos válidos:
- `fix(auth): correct bearer token extraction`
- `feat(demand): add attachment upload to demand form`
- `chore(harness): add enforcement hooks and project settings`

## SDD — mandatory development workflow

Every non-trivial feature, business logic change, or bug fix must follow these four phases **in order**. No phase may begin without explicit user approval ("approved", "go ahead", "yes", or equivalent).

### Phase 1 — Spec
Detailed prose explanation **only** — no code snippets, no diffs. Cover:
- Expected behaviour and acceptance criteria
- Inputs, outputs, edge cases
- Which layers are affected (tRPC router, DB query, UI component, etc.)
- Open questions and non-scope

The spec must be exhaustive in describing *what* and *why*. The *how* (code) belongs in Phase 2.

> **Self-review obrigatório**: após gerar spec ou plano, realize 2-3 revisões buscando inconsistências, placeholders não resolvidos, ambiguidades e gaps. Corrija inline antes de apresentar ao usuário.

**Stop. Wait for explicit approval before continuing.**

### Phase 2 — Plan
Implementation plan with **all the code**, production and tests:
- Files to create or modify
- Full code snippets for every change (not "diff fragments" or hand-waves)
- Complete test list with each test's negative-case scenario written out (see Phase 3 for the focus)
- Migration scripts when applicable

The plan should be specific enough that Phase 4 is mechanical execution.

> **Self-review obrigatório**: após gerar spec ou plano, realize 2-3 revisões buscando inconsistências, placeholders não resolvidos, ambiguidades e gaps. Corrija inline antes de apresentar ao usuário.

**Stop. Wait for explicit approval before continuing.**

### Phase 3 — Tests (red, negative-focused)
Write all tests first, before any production code. **Focus: negative testing** — the goal is to find failures, errors, and incoherences in the plan as early as possible:
- Adversarial cases first: unauthorized callers, missing/invalid input, forged payloads, NOT_FOUND, conflict resolution, idempotency.
- Happy path is the floor, not the ceiling — every endpoint/component must have at least one negative test before any positive test.
- **Unit tests**: pure functions, helpers, validators, isolated business logic.
- **Integration tests**: tRPC routers, DB queries against a real database (no DB mocks — see the real-incident note in AGENTS.md).
- Tests must **fail** at this point (red phase).

Catching plan incoherences here is the whole point — it's cheaper to fix the plan than to rework production code.

> **Self-review obrigatório**: após gerar spec ou plano, realize 2-3 revisões buscando inconsistências, placeholders não resolvidos, ambiguidades e gaps. Corrija inline antes de apresentar ao usuário.

**Stop. Wait for explicit approval before continuing.**

### Phase 4 — Implementation (green → refactor)
Write the minimum production code to make tests pass. Cycle: write → `bun test` → fix → repeat until all green. Refactor while keeping tests green. Only mark done when all tests pass.

---

**This applies even when the user says "implement X" directly.** Respond with the spec first and wait for approval. No exceptions.

## Rules

- Use TypeScript strict mode
- Follow existing patterns in the codebase
- Ask questions if necessary
- Create Git commits that are less than 72 characters long
- Create commits in Git following the commit convention
- Use the existing components in the code bases before creating a component from scratch
