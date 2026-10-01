---
name: gad:import
description: Ingest external plans with conflict detection against project decisions before writing anything.
argument-hint: "--from <filepath> | --from-gsd2"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
---

<objective>
Import external plan files into the GAD planning system with conflict detection against PROJECT.md decisions.

- **--from**: Import an external plan file, detect conflicts, write as GAD PLAN.md, validate via gad-plan-checker.
- **--from-gsd2**: Reverse-migrate a GSD-2 project (`.gsd/` directory) back to GAD v1 (`.planning/`) format. Runs `gad_run from-gsd2`. Pass `--path <dir>` to migrate a project at a different path.
</objective>

<execution_context>
@~/.claude/gad-core/workflows/import.md
@~/.claude/gad-core/references/ui-brand.md
@~/.claude/gad-core/references/gate-prompts.md
@~/.claude/gad-core/references/doc-conflict-engine.md
</execution_context>

<context>
$ARGUMENTS
</context>

<process>
If `--from-gsd2` is in $ARGUMENTS:
Run the reverse-migration (append `--path <dir>` if provided):
```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }
gad_run from-gsd2
```
Present the migration result to the user.
Stop here (do not run the standard import workflow).

Otherwise, execute the import workflow end-to-end.
</process>
