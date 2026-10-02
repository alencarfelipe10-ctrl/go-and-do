@~/.claude/gad-core/references/response-language-directive.md

<purpose>
Autonomous audit-to-fix pipeline. Runs an audit, parses findings, classifies each as
auto-fixable vs manual-only, spawns executor agents for fixable issues, runs tests
after each fix, and commits atomically with finding IDs for traceability.
</purpose>

<available_agent_types>
- gad-executor — executes a specific, scoped code change
</available_agent_types>

<process>

<step name="parse-arguments">
Extract flags from the user's invocation:

- `--max N` — maximum findings to fix (default: **5**)
- `--severity high|medium|all` — minimum severity to process (default: **medium**)
- `--dry-run` — classify findings without fixing (shows classification table only)
- `--source <audit>` — which audit to run (default: **audit-uat**)

Validate `--source` is a supported audit. Currently supported:
- `audit-uat`

If `--source` is not supported, stop with an error:
```
Error: Unsupported audit source "{source}". Supported sources: audit-uat
```
</step>

<step name="run-audit">
Invoke the source audit command and capture output.

For `audit-uat` source:
```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; _gad_id_ok() { case "$("$1" runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') return 0;; *) return 1;; esac; }; _gad_homes() { _gad_at "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; elif _gad_homes; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; _gad_id_ok gad_run && GAD_IDENTITY_STATUS=ok; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
INIT=$(gad_run query audit-uat 2>/dev/null || echo "{}")
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
```

Read existing UAT and verification files to extract findings:
- Glob: `.planning/phases/*/*-UAT.md`
- Glob: `.planning/phases/*/*-VERIFICATION.md`

Parse each finding into a structured record:
- **ID** — sequential identifier (F-01, F-02, ...)
- **description** — concise summary of the issue
- **severity** — high, medium, or low
- **file_refs** — specific file paths referenced in the finding
</step>

<step name="classify-findings">
For each finding, classify as one of:

- **auto-fixable** — clear code change, specific file referenced, testable fix
- **manual-only** — requires design decisions, ambiguous scope, architectural changes, user input needed
- **skip** — severity below the `--severity` threshold

**Classification heuristics** (err on manual-only when uncertain):

Auto-fixable signals:
- References a specific file path + line number
- Describes a missing test or assertion
- Missing export, wrong import path, typo in identifier
- Clear single-file change with obvious expected behavior

Manual-only signals:
- Uses words like "consider", "evaluate", "design", "rethink"
- Requires new architecture or API changes
- Ambiguous scope or multiple valid approaches
- Requires user input or design decisions
- Cross-cutting concerns affecting multiple subsystems
- Performance or scalability issues without clear fix

**When uncertain, always classify as manual-only.**
</step>

<step name="present-classification">
Display the classification table:

```
## Audit-Fix Classification

| # | Finding | Severity | Classification | Reason |
|---|---------|----------|---------------|--------|
| F-01 | Missing export in index.ts | high | auto-fixable | Specific file, clear fix |
| F-02 | No error handling in payment flow | high | manual-only | Requires design decisions |
| F-03 | Test stub with 0 assertions | medium | auto-fixable | Clear test gap |
```

If `--dry-run` was specified, **stop here and exit**. The classification table is the
final output — do not proceed to fixing.
</step>

<step name="fix-loop">
For each **auto-fixable** finding (up to `--max`, ordered by severity desc):

<!-- #2508 runtime-aware-dispatch -->

> **Runtime-aware dispatch (#2508 Phase 4).** GAD workflows dispatch specialized subagents by role. Before dispatching on a built-in-only runtime (kimi-code — three built-ins only), resolve the role to a built-in via `gad_run query resolve-dispatch-type --requested <role> --raw`. On named-dispatch runtimes (Claude/OpenCode/…) the role is returned unchanged; on kimi-code it maps to `coder`/`explore`/`plan` by role-suffix. The persona rides `${AGENT_SKILLS_<ROLE>}` (Phase 3) regardless. See @gad-core/references/runtime-aware-dispatch.md.

```bash
EXECUTOR_MODEL=$(gad_run query resolve-model gad-executor --raw)
```

<!-- #2517 model-omit-on-inherit -->

> **Model omission (#2517).** Omit the `model` parameter entirely when the value it would carry (`EXECUTOR_MODEL`) is `"inherit"` or empty. An empty value 404s on runtimes without native tier aliases — the default on non-Claude runtimes. Omitting it inherits the orchestrator's model. See @gad-core/references/model-profile-resolution.md.

**a. Spawn executor agent** (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze)**:**
```
Agent(
  prompt="Fix finding {ID}: {description}. Files: {file_refs}. Make the minimal change to resolve this specific finding. Do not refactor surrounding code.",
  subagent_type="gad-executor",
  model="{EXECUTOR_MODEL}"
)
```

> **ORCHESTRATOR RULE — CODEX RUNTIME**: After calling Agent() above, stop working on this task immediately. Do not read more files, edit code, or run tests related to this task while the subagent is active. Wait for the subagent to return its result. This prevents duplicate work, conflicting edits, and wasted context. Only resume when the subagent result is available.

**b. Run tests:**
```bash
AUDIT_TEST_CMD=$(gad_run query config-get workflow.test_command --default "" --raw 2>/dev/null || true)
if [ -z "$AUDIT_TEST_CMD" ]; then
  if [ -f "Makefile" ] && grep -q "^test:" Makefile; then
    AUDIT_TEST_CMD="make test"
  elif [ -f "Justfile" ] || [ -f "justfile" ]; then
    AUDIT_TEST_CMD="just test"
  elif [ -f "package.json" ]; then
    AUDIT_TEST_CMD="npm test"
  elif [ -f "Cargo.toml" ]; then
    AUDIT_TEST_CMD="cargo test"
  elif [ -f "go.mod" ]; then
    AUDIT_TEST_CMD="go test ./..."
  elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
    AUDIT_TEST_CMD="python -m pytest -x -q --tb=short"
  else
    AUDIT_TEST_CMD="true"
  fi
fi
# #1857: normalize to one-shot (defeat vitest/jest watch mode) + bound with a
# timeout so a watch-mode runner cannot hang the audit gate indefinitely.
AUDIT_TEST_CMD=$(gad_run query normalize-test-command "$AUDIT_TEST_CMD" --cwd . 2>/dev/null || echo "$AUDIT_TEST_CMD")
TEST_GATE_TIMEOUT=$(gad_run query config-get workflow.test_gate_timeout --raw 2>/dev/null || echo "600")
gad_run run-with-timeout "$TEST_GATE_TIMEOUT" -- bash -c "$AUDIT_TEST_CMD" 2>&1 | tail -20
AUDIT_TEST_EXIT=${PIPESTATUS[0]}
if [ "$AUDIT_TEST_EXIT" -eq 124 ]; then
  echo "✗ Audit test gate timed out after ${TEST_GATE_TIMEOUT}s — likely stuck in watch/dev mode (e.g. vitest without 'run'). Run tests one-shot (e.g. 'vitest run') or raise workflow.test_gate_timeout."
fi
```

**c. If tests pass** — commit atomically:
```bash
git add {changed_files}
git commit -m "fix({scope}): resolve {ID} — {description}"
```
The commit message **must** include the finding ID (e.g., F-01) for traceability.

**d. If tests fail** — revert changes, mark finding as `fix-failed`, and **stop the pipeline**:
```bash
git checkout -- {changed_files} 2>/dev/null
```
Log the failure reason and stop processing — do not continue to the next finding.
A test failure indicates the codebase may be in an unexpected state, so the pipeline
must halt to avoid cascading issues. Remaining auto-fixable findings will appear in the
report as `not-attempted`.
</step>

<step name="report">
Present the final summary:

```
## Audit-Fix Complete

**Source:** {audit_command}
**Findings:** {total} total, {auto} auto-fixable, {manual} manual-only
**Fixed:** {fixed_count}/{auto} auto-fixable findings
**Failed:** {failed_count} (reverted)

| # | Finding | Status | Commit |
|---|---------|--------|--------|
| F-01 | Missing export | Fixed | abc1234 |
| F-03 | Test stub | Fix failed | (reverted) |

### Manual-only findings (require developer attention):
- F-02: No error handling in payment flow — requires design decisions
```
</step>

</process>

<success_criteria>
- Auto-fixable findings processed sequentially until --max reached or a test failure stops the pipeline
- Tests pass after each committed fix (no broken commits)
- Failed fixes are reverted cleanly (no partial changes left)
- Pipeline stops after the first test failure (no cascading fixes)
- Every commit message contains the finding ID
- Manual-only findings are surfaced for developer attention
- --dry-run produces a useful standalone classification table
</success_criteria>
