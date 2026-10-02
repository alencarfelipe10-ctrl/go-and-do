<purpose>
GAD smart entry — the state-aware front door. Detect the current project situation via `gad_run smart-entry --json`, present a short menu of the right next actions, and dispatch to exactly one existing GAD command. This is a launcher/router only; it never does the work itself.

This is a *menu* front door, not a second router. For in-project forward motion (planning → executing → verify-pending) the recommended action is `/gad-progress --next`, which delegates to the single gated advancement engine (`workflows/next.md`: Route 0 resume-incomplete-phase + Gates 1-3). smart-entry adds value only where `--next` cannot reach: pre-project, remediation (paused/blocked/verify-failed), and lifecycle exits (idle-stranded/complete). See `docs/adr/1787-gad-next-smart-entry.md`.
</purpose>

<required_reading>
Read all files referenced by the invoking prompt's `execution_context` before starting.
</required_reading>

<process>

<step name="text_mode">
**TEXT_MODE handling (non-Claude runtimes).**

Set `TEXT_MODE=true` if `--text` is present in `$ARGUMENTS` OR `text_mode` from init JSON is `true`. When TEXT_MODE is active, replace every `AskUserQuestion` call with a plain-text numbered list and ask the user to type their choice number. This is required for non-Claude runtimes (OpenAI Codex, Antigravity, etc.) where `AskUserQuestion` is not available.
</step>

<step name="resolve">
**Resolve the gad_run shim.**

Run this resolver block exactly. It locates `gad-tools.cjs` across every supported runtime home and defines a `gad_run` function. If it cannot find the tool, it prints the standard install hint and exits non-zero.

```bash
```
</step>

<step name="detect">
**Detect the situation.**

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; _gad_id_ok() { case "$("$1" runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') return 0;; *) return 1;; esac; }; _gad_homes() { _gad_at "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; elif _gad_homes; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; _gad_id_ok gad_run && GAD_IDENTITY_STATUS=ok; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
RESPONSE_LANGUAGE=$(gad_run query config-get response_language --raw --default "" 2>/dev/null || echo "")
SNAPSHOT=$(gad_run smart-entry --json 2>/dev/null)
```

**If `response_language` is set:** All user-facing output of this workflow — narration between tool calls, status updates, progress notes, findings, questions, prompts, and explanations — MUST be presented in `{response_language}`. Technical terms, code, file paths, and subagent prompts stay in English — only user-facing output is translated.

Parse `SNAPSHOT` as JSON. It has the shape:

```json
{
  "situation": "executing",
  "recommended": "progress-next",
  "summary": "Phase 2 of 5 · 60% · executing",
  "signals": { "...": "..." },
  "actions": [
    { "id": "progress-next", "label": "Advance to the next step", "command": "/gad-progress --next", "recommended": true },
    { "id": "execute-phase", "label": "Continue executing phase 2", "command": "/gad-execute-phase", "recommended": false }
  ]
}
```

`situation` is one of: `no-project`, `paused`, `blocked`, `verify-failed`, `needs-first-phase`, `planning`, `executing`, `verify-pending`, `idle-stranded`, `complete`, `unknown`.

**Fallback (never strand the user):** `smart-entry --json` can fail for two reasons, and each has a different recovery. Parse `SNAPSHOT`; if it is empty, not valid JSON, or missing `actions`, apply the first matching recovery below — do NOT error.

1. **`gad-tools` itself is broken** (the failure is a `Cannot find module ...` / Node crash, not just an empty result). Probe by running `gad_run state-snapshot` — if THAT also errors, the whole tool layer is down and routing to `/gad-progress` would dead-end too (it also needs gad-tools). **Recover by reading state directly:**
   - Read `.planning/STATE.md` (frontmatter + body) with the Read tool. Extract: `status` (frontmatter `status:` or body `**Status:**`), `Phase:` from the body, `total_phases`/`percent` from a nested `progress:` frontmatter object if present, and any `## Blockers` items.
   - Synthesize a minimal result: `situation` = your best guess from the status text (`executing`/`verifying`/`planning`/`complete`/`paused`), `summary` = a one-line read ("Phase N of M · status"), and an `actions` list built from status (e.g. verifying → `/gad-verify-work`, executing → `/gad-execute-phase`, else `/gad-progress`), always including `/gad-quick` and `/gad-help`.
   - Print one line first: `smart-entry unavailable (gad-tools error) — reading state directly. The gad-tools layer may need a rebuild (rm tsconfig.build.tsbuildinfo && npm run build).`
   - Proceed to the `present` step with this synthesized result.

2. **Only `smart-entry` is unavailable** (e.g. older gad-core without the subcommand; `state-snapshot` still works). Run `/gad-progress` and stop. Print one line first: `smart-entry unavailable — showing progress.`
</step>

<step name="present">
**Present the menu.**

Show the `summary` line to orient the user, then offer the actions.

**If TEXT_MODE is false:** call `AskUserQuestion` with:
- `header`: a short label derived from `situation` (e.g. `executing` → "Continue work", `blocked` → "Unblock", `no-project` → "Get started", `complete` → "What next?").
- `question`: the `summary` line, then "What would you like to do?"
- `options`: the first 4 entries of `actions[]` in order. For each, `label` = the action's `label`, `description` = the action's `command`. The recommended action is already first; surface it as the first option. The user may also type a custom command (handled automatically).

**If TEXT_MODE is true:** print the `summary`, then a numbered list of ALL `actions[]` (not capped to 4 — text has no limit), then ask the user to type the number of their choice:

```
{summary}

  1. {actions[0].label}  ({actions[0].command})
  2. {actions[1].label}  ({actions[1].command})
  ...

Type a number, or describe what you want to do.
```

Wait for the user's response before continuing. Map the chosen number to the corresponding action.
</step>

<step name="display">
**Show the routing decision.**

```
### GAD ► SMART ENTRY

**Situation:** {situation}
**Routing to:** {chosen command}
```
</step>

<step name="dispatch">
**Dispatch and stop.**

Invoke the chosen action's `command`. If the user typed a free-form response instead of picking an action, treat it as freeform intent and route via `/gad-progress --do "<their text>"`.

After invoking the command, **stop**. The dispatched command owns everything from here. Do not continue, do not chain, do not re-enter this workflow.
</step>

</process>

<success_criteria>
- [ ] Situation detected via `gad_run smart-entry --json`
- [ ] Summary shown to orient the user
- [ ] Menu offered (AskUserQuestion, or numbered list under TEXT_MODE)
- [ ] Routing decision displayed before dispatch
- [ ] Exactly one command dispatched
- [ ] Any detection failure falls back to /gad-progress (never strands the user)
- [ ] No work done directly — launcher only
</success_criteria>
