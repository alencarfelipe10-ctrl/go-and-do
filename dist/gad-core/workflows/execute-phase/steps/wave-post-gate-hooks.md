# Wave-Post Gate Hook Evaluation (execute:wave:post)

Detail for the `kind == "gate"` dispatch at the execute:wave:post hook point, extracted from the host step 5.7 (#3606 — the host file carries a frozen pre-phase-6 byte ceiling, #1168; evaluation detail lives here).

⚠ **Validate `check` before shell use** (third-party manifest input) — `gad-core/references/loop-hook-dispatch.md` § `gate`.

**For each active entry where `kind == "gate"`** (process in array order), run the gate check — a `predicate` gate (ADR-2008 / #2008) uses the check CLI's `predicate` form with the predicate JSON and phase number (shown in the block below):

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; _gad_id_ok() { case "$("$1" runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') return 0;; *) return 1;; esac; }; _gad_homes() { _gad_at "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; elif _gad_homes; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; _gad_id_ok gad_run && GAD_IDENTITY_STATUS=ok; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
GATE_RESULT=$(gad_run check ${hook.check.query} "${PHASE_NUMBER}" --raw)
CHECK_EXIT=$?
```

**Step 1 — did the CHECK COMMAND itself succeed?**

If the check command failed (non-zero `CHECK_EXIT`, empty output, or unparseable JSON):
- `onError == "halt"` → treat as a fatal error: stop wave completion, do NOT proceed to step 5.8, and surface: `⚠ Gate check command failed ({hook.capId}): command error. Resolve before continuing.`
- `onError == "skip"` → log a warning and continue to the next hook. Do NOT read `GATE_RESULT.block`.

**Step 2 — read `GATE_RESULT.block` (boolean).** This step is only reached when the command succeeded.

- **Blocking gate (`hook.blocking == true`) AND `GATE_RESULT.block == true`:** HALT — stop wave completion, do NOT proceed to step 5.8, and present:

  ```
  ⚠ Wave {N} blocked by capability gate ({hook.capId}): {GATE_RESULT.message}
  Resolve before continuing to next wave.
  ```

  This halt is **not** bypassed by `onError` — `onError` only covers command errors (step 1 above), not the gate's block decision.

- **Non-blocking gate (`hook.blocking == false`):** never halts. If `GATE_RESULT.block` is `true` (or non-empty `message`), print `⚠ {hook.capId} advisory (wave {N}): {GATE_RESULT.message}`, then:
  - If `GATE_RESULT.spawn_mapper == true` OR `GATE_RESULT.directive == "auto-remap"`: spawn `gad-codebase-mapper` per `execute-phase/steps/codebase-drift-gate.md`; pass `--paths {GATE_RESULT.affected_paths}`. Continue regardless (wave NOT failed by remap failure).
  - Otherwise: continue after advisory.
  - If block `false` and no `message`: continue silently.

- **Blocking gate (`hook.blocking == true`) AND `GATE_RESULT.block == false`:** continue silently.

**When all active gates are processed without a blocking halt:** continue to step 5.8.
