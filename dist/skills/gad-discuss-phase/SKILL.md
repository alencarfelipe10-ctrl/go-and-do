---
name: gad-discuss-phase
description: "Gather phase context through adaptive questioning before planning."
argument-hint: "<phase> [--all] [--auto] [--chain] [--batch] [--analyze] [--text] [--power] [--assumptions]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
  - mcp__context7__resolve-library-id
  - mcp__context7__query-docs
---


<objective>
Extract implementation decisions that downstream agents need — researcher and planner will use CONTEXT.md to know what to investigate and what choices are locked.

**How it works:**
1. Load prior context (PROJECT.md, REQUIREMENTS.md, STATE.md, prior CONTEXT.md files)
2. Scout codebase for reusable assets and patterns
3. Analyze phase — skip gray areas already decided in prior phases
4. Present remaining gray areas — user selects which to discuss
5. Deep-dive each selected area until satisfied
6. Create CONTEXT.md with decisions that guide research and planning

**Output:** `{phase_num}-CONTEXT.md` — decisions clear enough that downstream agents can act without asking the user again
</objective>

<execution_context>
Workflow files are loaded on-demand in the <process> section below — not upfront.
Do not pre-load any workflow files before reading the mode routing instructions.
</execution_context>

<runtime_note>
**Copilot (VS Code):** Use `vscode_askquestions` wherever this workflow calls `AskUserQuestion`. They are equivalent — `vscode_askquestions` is the VS Code Copilot implementation of the same interactive question API.
</runtime_note>

<context>
Phase number: $ARGUMENTS (required)

Context files are resolved in-workflow using `init phase-op` and roadmap/state tool calls.
</context>

<process>
**Mode routing:**
```bash
# Fast path: reuse the gad-tools location resolved earlier this session (state file namespaced per config-home [C2-31][C3-39]; never PATH) before the full cascade.
GAD_TOOLS=""; _GAD_STATE=""; _GAD_HOME=""
for _c in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/gad-tools.cjs"; do [ -n "$_c" ] && [ -f "$_c" ] && _GAD_HOME="$(readlink -f "$(dirname "$(dirname "$(dirname "$(readlink -f "$_c")")")")" 2>/dev/null)" && break; done
[ -n "$_GAD_HOME" ] && _GAD_STATE="${TMPDIR:-/tmp}/gad-tools-path.$(id -u).$(printf '%s' "$_GAD_HOME" | md5sum | cut -c1-8)"
if [ -n "$_GAD_STATE" ] && [ -f "$_GAD_STATE" ]; then _GAD_CAND="$(cat "$_GAD_STATE" 2>/dev/null)"; case "$(readlink -f "$_GAD_CAND" 2>/dev/null)" in "$_GAD_HOME"/*) [ -f "$_GAD_CAND" ] && GAD_TOOLS="$_GAD_CAND" ;; esac; fi
if [ -n "$GAD_TOOLS" ]; then case "$GAD_TOOLS" in *.cjs) gad_run() { node "$GAD_TOOLS" "$@"; } ;; *) gad_run() { "$GAD_TOOLS" "$@"; } ;; esac; else
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
fi
[ -n "$_GAD_STATE" ] && { printf '%s\n' "$GAD_TOOLS" > "$_GAD_STATE" 2>/dev/null || true; }
DISCUSS_MODE=$(gad_run query config-get workflow.discuss_mode --raw 2>/dev/null || echo "discuss")
```

If `--assumptions` is in $ARGUMENTS:
Read and execute `$HOME/.claude/gad-core/workflows/list-phase-assumptions.md` end-to-end.
Stop here.

Otherwise, if `DISCUSS_MODE` is `"assumptions"`:
Read and execute `$HOME/.claude/gad-core/workflows/discuss-phase-assumptions.md` end-to-end.

Otherwise (`"discuss"` / unset / any other value):
Read and execute `$HOME/.claude/gad-core/workflows/discuss-phase.md` end-to-end.

Read the appropriate workflow file first — it is the source of truth. The objective section in this command file is a summary; the workflow file contains the complete step-by-step process with all required behaviors, config checks, and interaction patterns.

**Lazy loading:** `templates/context.md` is loaded inside the `write_context` step of the active workflow. `discuss-phase-power.md` is loaded inside `discuss-phase.md` when `--power` is detected. Do not load either here.
</process>
