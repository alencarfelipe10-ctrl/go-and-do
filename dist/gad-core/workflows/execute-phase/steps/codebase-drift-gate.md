Apply response_language to all user-facing prose — narration between tool calls, status updates, progress notes, and findings included; preserve code, paths, and identifiers.

# Step: codebase_drift_gate

Post-execution structural drift detection (#2003). Runs after the last wave
commits, before verification. **Non-blocking by contract:** any internal
error here MUST fall through and continue to `verify_phase_goal`. The phase
is never failed by this gate.

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
# Resolve gad-tools through the runtime shim launcher, NOT the bare PATH binary. On a
# shim-only install (gad-tools.cjs present, `gad-tools` not on PATH) the bare call exits
# 127, `2>/dev/null` hides it, and this non-blocking gate would silently skip drift
# detection forever (#619). The canonical launcher preamble is defined once here — the
# always-run drift check, the file's first launcher block — and the conditional auto-remap
# block below reuses the launcher function from this shared shell scope (the single-preamble
# pattern established by discuss-phase #614, enforced by tests/runtime-launcher-parity.test.cjs).
# Non-blocking is preserved: an internal drift-command failure still falls through to the
# skip JSON via the `|| echo` below.
DRIFT=$(gad_run verify codebase-drift 2>/dev/null || echo '{"skipped":true,"reason":"sdk-failed"}')
```

Parse JSON for: `skipped`, `reason`, `action_required`, `directive`,
`spawn_mapper`, `affected_paths`, `elements`, `threshold`, `action`,
`last_mapped_commit`, `message`.

**If `skipped` is true (no STRUCTURE.md, missing git, or any internal error):**
Log one line — `Codebase drift check skipped: {reason}` — and continue to
`verify_phase_goal`. Do NOT prompt the user. Do NOT block.

**If `action_required` is false:** Continue silently to `verify_phase_goal`.

**If `action_required` is true AND `directive` is `warn`:**
Print the `message` field verbatim. The format is:

```text
Codebase drift detected: {N} structural element(s) since last mapping.

New directories:
  - {path}
New barrel exports:
  - {path}
New migrations:
  - {path}
New route modules:
  - {path}

Run /gad-map-codebase --paths {affected_paths} to refresh planning context.
```

Then continue to `verify_phase_goal`. Do NOT block. Do NOT spawn anything.

**If `action_required` is true AND `directive` is `auto-remap`:**

First load the mapper agent's skill bundle (the executor's `AGENT_SKILLS`
from step `init_context` is for `gad-executor`, not the mapper):

```bash
# gad_run is defined by the canonical preamble in the drift-check block above and reused
# here via the workflow's shared shell scope — defining it once keeps the file compliant
# with the single-canonical-preamble parity invariant (#619). This block only runs on the
# `auto-remap` directive, which is always reached after the drift check above has run.
AGENT_SKILLS_MAPPER=$(gad_run query agent-skills gad-codebase-mapper)
```

Then spawn `gad-codebase-mapper` agents with the `--paths` hint (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze):

<!-- #2508 runtime-aware-dispatch -->

> **Runtime-aware dispatch (#2508 Phase 4).** GAD workflows dispatch specialized subagents by role. Before dispatching on a built-in-only runtime (kimi-code — three built-ins only), resolve the role to a built-in via `gad_run query resolve-dispatch-type --requested <role> --raw`. On named-dispatch runtimes (Claude/OpenCode/…) the role is returned unchanged; on kimi-code it maps to `coder`/`explore`/`plan` by role-suffix. The persona rides `${AGENT_SKILLS_<ROLE>}` (Phase 3) regardless. See @gad-core/references/runtime-aware-dispatch.md.

```text
Agent(
  subagent_type="gad-codebase-mapper",
  description="Incremental codebase remap (drift)",
  prompt="Focus: arch
Today's date: {date}
--paths {affected_paths joined by comma}

Refresh STRUCTURE.md and ARCHITECTURE.md scoped to the listed paths only.
${AGENT_SKILLS_MAPPER}"
)
```

> **ORCHESTRATOR RULE — CODEX RUNTIME**: After calling Agent() above, stop working on this task immediately. Do not read more files, edit code, or run tests related to this task while the subagent is active. Wait for the subagent to return its result. This prevents duplicate work, conflicting edits, and wasted context. Only resume when the subagent result is available.

If the spawn fails or the agent reports an error: log `Codebase drift
auto-remap failed: {reason}` and continue to `verify_phase_goal`. The phase
is NOT failed by a remap failure.

If the remap succeeds, stamp the new baseline into the two documents the
mapper just refreshed:

```bash
gad_run stamp-codebase-map --files STRUCTURE.md,ARCHITECTURE.md
```

The stamp is a shell step, not a line in the mapper's prompt. An agent that
concludes its work is already done skips a prose instruction silently, and the
stamp is the one marker no human reviewing the documents would notice missing
(#3418). `--files` is scoped to what this step actually refreshed -- the other
five documents were not remapped and must not claim currency at HEAD.

Only stamp on success: stamping after a failed remap would record a baseline
the map never reached.

Then log `Codebase drift auto-remap completed for paths: {affected_paths}` and
continue to `verify_phase_goal`.

The two relevant config keys (continue on error / failure if either is invalid):
- `workflow.drift_threshold` (integer, default 3) — minimum drift elements before action
- `workflow.drift_action` — `warn` (default) or `auto-remap`

This step is fully non-blocking — it never fails the phase, and any
exception path returns control to `verify_phase_goal`.
