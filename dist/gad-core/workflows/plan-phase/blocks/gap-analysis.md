# plan-phase — post-planning gap analysis (step 13e)

Lazy block of `workflows/plan-phase.md`. Read it on arrival at step 13e only when `workflow.post_planning_gaps` is not `false` (default on) — the step itself still checks `plan:post` `activeHooks` and skips silently when there is none.

## 13e. Post-Planning Gap Analysis (plan:post capability gate dispatch)

Proactive, non-blocking coverage report gated on `workflow.post_planning_gaps`
(default `true`). Dispatched via the `plan:post` capability gate owned by the
`gap-analysis` capability (ADR-857 §53). Reads REQUIREMENTS.md and CONTEXT.md
`<decisions>` and cross-references each REQ-ID / D-ID against `${PHASE_DIR}/*-PLAN.md`.

```bash
PLAN_POST_HOOKS_JSON=$(gad_run loop render-hooks plan:post --raw)
PHASE_REQ_IDS=$(gad_run query init.plan-phase "$PHASE" --pick phase_req_ids 2>/dev/null)
PHASE_REQ_IDS="${PHASE_REQ_IDS:-TBD}"
```

Read the `activeHooks` array from `PLAN_POST_HOOKS_JSON` in-context. If
`activeHooks` is empty or absent, skip this step silently — do NOT key the skip
on any one capability's gate being absent (#3606: that skip silently dropped
every other registered hook at this point).

**Step and contribution dispatch:** dispatch every `kind == "step"` hook and inject every `kind == "contribution"` fragment per @gad-core/references/loop-hook-dispatch.md (skip each kind silently when none), before gate evaluation below.

⚠ **Validate `check` before shell use** (third-party manifest input) — `loop-hook-dispatch.md` § `gate`.

**For each active entry where `kind == "gate"`** (process in array order). **Dispatch by check shape** (the registry validates exactly one of `query`/`predicate`/`agentVerdict`):

```bash
# named-query gate:
GATE_RESULT=$(gad_run check ${hook.check.query} "${PHASE_DIR}" "${PHASE_REQ_IDS}" --raw)
CHECK_EXIT=$?
```
OR, for a generic `predicate` gate (ADR-2008 / #2008), inline the predicate as compact JSON (note the `--phase-dir`/`--phase-req-ids` flags feed `${PHASE_DIR}`/`${PHASE_REQ_IDS}` interpolation):
```bash
GATE_RESULT=$(gad_run check predicate --predicate '<hook.check.predicate as JSON>' --phase-dir "${PHASE_DIR}" --phase-req-ids "${PHASE_REQ_IDS}" --raw)
CHECK_EXIT=$?
```
(Read the hook's `check` object in-context to pick the branch; a gate with neither is a malformed registry entry — skip with a warning.)

**Step 1 — did the CHECK COMMAND itself succeed?**
If the check command failed (non-zero `CHECK_EXIT`, empty output, or unparseable JSON):
- `onError == "halt"` → halt and surface command error.
- `onError == "skip"` → log a warning and continue to the next hook.

**Step 2 — read `GATE_RESULT.block` (boolean).** Only reached when command succeeded.

- If `hook.blocking == true` and `GATE_RESULT.block == true`: halt. (gap-analysis is always `blocking: false` so this branch is informational only.)
- If `hook.blocking == false` (advisory): if `GATE_RESULT.block == true` or non-empty `table`/`summary`, output the gap table and continue. Advisory gates never block phase completion.
- If `hook.blocking == true` and `GATE_RESULT.block == false`: continue silently.

