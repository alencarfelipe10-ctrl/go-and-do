## 8.5. Chunked Planning Mode

**Skip if `CHUNKED_MODE` is `false`.**

Chunked mode splits the single planner run into a short outline run + N short per-plan
runs (~3–5 min each), committing each plan individually for crash resilience. Rerunning
`/gad-plan-phase {N} --chunked` resumes from the last committed plan.

For recovering plans from a prior *non-chunked* run, use step 6's "Add more plans" or
proceed to `/gad-execute-phase` — don't start a fresh chunked run over them.

Set `CHUNKED_PARALLEL` from config, here rather than in `plan-phase.md`, so the two extra
`gad_run` calls it costs are paid only on a run that already reached this section (#3777) —
`CHUNKED_MODE` is `true` at this point, per the skip-check above. STRICT equality on `"true"`
is deliberate, matching `review.parallel_lanes` (#3034): a mistyped or non-canonical value
(`"1"`, `"yes"`, `"TRUE"`) gets the conservative behavior, and any tooling failure
(`config-get`/`dispatch-capacity` erroring or printing nothing) fails safe to serial — never the
opposite polarity, since firing concurrent Agent() dispatch is the risky direction here, not the
safe default. `dispatch-capacity` is the same negotiated dispatch-capability query
`quick-batch-dispatch.cts` already consults (#3673) — a host that declares no `maxConcurrency`
(reason `missing`/`undocumented`) resolves to the fail-closed floor of `1`, which degrades this
flag to serial regardless of the config value:
```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; _gad_id_ok() { case "$("$1" runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') return 0;; *) return 1;; esac; }; _gad_homes() { _gad_at "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; elif _gad_homes; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; _gad_id_ok gad_run && GAD_IDENTITY_STATUS=ok; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
CHUNKED_PARALLEL_CFG=$(gad_run query config-get planning.chunked_parallel --raw 2>/dev/null || echo "false")
DISPATCH_CAPACITY=$(gad_run query dispatch-capacity --raw 2>/dev/null || echo "1")
CHUNKED_PARALLEL=false
if [[ "$CHUNKED_PARALLEL_CFG" == "true" ]] && [[ "${DISPATCH_CAPACITY:-1}" -gt 1 ]] 2>/dev/null; then
  CHUNKED_PARALLEL=true
fi
```

### 8.5.1 Outline Phase (outline-only mode, ~2 min)

**Resume detection:** If `${PHASE_DIR}/${PADDED_PHASE}-PLAN-OUTLINE.md` exists and contains
the `## OUTLINE COMPLETE` marker (written by the outline agent — #2762), skip to 8.5.2.

```bash
OUTLINE_FILE="${PHASE_DIR}/${PADDED_PHASE}-PLAN-OUTLINE.md"
if [[ -f "$OUTLINE_FILE" ]] && grep -q "^## OUTLINE COMPLETE" "$OUTLINE_FILE"; then
  : # reuse existing outline — skip to 8.5.2
fi
```

Display:
```text
◆ Chunked mode: spawning outline planner... (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze)
```

Spawn the planner in **outline-only** mode — it must write only the outline manifest, not any
PLAN.md files:

**Dispatch/wait gate — `PLANNER_STALL_DETECTION_ENABLED`:**
- **`true` (default):** use `run_in_background=true` in the Agent() call below, then use `gad_stall_watch` after it.

```javascript
Agent(
  prompt="{same planning_context as step 8, plus:}

  **Chunked mode: outline-only.**
  Do NOT write any PLAN.md files in this Task.
  Write only: {PHASE_DIR}/{PADDED_PHASE}-PLAN-OUTLINE.md

  The outline must be a markdown table with columns:
  Plan ID | Objective | Wave | Depends On | Requirements

  End the file with a final line `## OUTLINE COMPLETE` — §8.5.1's resume-check greps
  the file for it, so it MUST be written here, not just returned.
  Return: ## OUTLINE COMPLETE with plan count.",
  subagent_type="gad-planner",
  model="{planner_model}",
  description="Outline Phase {phase} (chunked)",
  run_in_background=true
)
```

**ORCHESTRATOR RULE — ALL RUNTIMES (when `PLANNER_STALL_DETECTION_ENABLED` is `true`):** `TS=$(date +%s)`; repeat `PLANNER_STALL_RESULT=$(gad_stall_watch "$TS" "{outputFile}" "$OUTLINE_FILE" "## OUTLINE COMPLETE")` while waiting/active.

- **`false`:** issue the same Agent() call but omit `run_in_background`; await its ordinary runtime-native completion and consume the real returned result. Skip `gad_stall_watch` entirely and treat a recognized `## OUTLINE COMPLETE` return exactly like `marker_received`; empty or unrecognized returns keep the existing Retry/Stop path.

Handle return:
- **`marker_received`:** Read `PLAN-OUTLINE.md`, extract plan list. Continue to 8.5.2.
- **`stalled` / any other return or empty:** Display error. Offer: 1) Retry outline, 2) Stop.

### 8.5.2 Per-Plan Tasks (single-plan mode, ~3-5 min each)

Plans are dispatched **wave by wave**, in ascending Wave order (a blank/missing Wave value on a
row is treated as Wave `1` — see §8.5.1's example table). Within one Wave, dispatch is either
serial (today's behavior, always used when `CHUNKED_PARALLEL` is `false`) or concurrent
(`CHUNKED_PARALLEL` is `true` — resolved above from `planning.chunked_parallel` gated on
`dispatch-capacity`, #3777). A Wave containing only one runnable entry always takes the serial
path regardless of `CHUNKED_PARALLEL` — there is nothing to batch.

**For each Wave, in order:**

1. **Build the batch's plan-ID list** from the outline rows sharing this Wave value, in outline
   row order, deduplicated defensively — a malformed outline naming the same Plan ID twice must
   never produce two concurrent Agent() calls targeting the same `{plan_id}-PLAN.md` output path
   (mirrors `review.md`'s `DISPATCH_SLUGS` dedup, #3034):
   ```bash
   # Rewrapped through unquoted command substitution, not consumed as a bare
   # `$WAVE_PLAN_IDS`: bash word-splits an unquoted scalar on IFS by default,
   # but zsh does not, so a bare re-split collapses every Plan ID onto one
   # iteration under zsh (gad-core#4109 — same fix review.md's DISPATCH_SLUGS
   # loop already applies). Unquoted `$(...)` re-splits identically under
   # both shells regardless of `SH_WORD_SPLIT`.
   BATCH_PLAN_IDS=""
   for PLAN_ID in $(printf '%s' "$WAVE_PLAN_IDS"); do
     case " $BATCH_PLAN_IDS " in
       *" $PLAN_ID "*) continue ;;
     esac
     BATCH_PLAN_IDS="$BATCH_PLAN_IDS $PLAN_ID"
   done
   ```
   `WAVE_PLAN_IDS` is the space-separated Plan ID list for this Wave, in outline row order — the
   orchestrator (already reading the outline table to extract plan entries, per §8.5.1) populates
   it directly from the table before this block runs.

2. **Resume check, per entry:** for each `plan_id` in `BATCH_PLAN_IDS`, skip it (remove it from
   this batch's runnable set) if `${PHASE_DIR}/{plan_id}-PLAN.md` exists with valid frontmatter —
   UNLESS `--reviews` is set, whose purpose is to REPLAN with review feedback (§6), so existing
   plans are overwritten, not skipped (#2762). Unchanged from before this change, applied per entry
   before dispatch rather than immediately before each individual spawn:
   ```bash
   PLAN_FILE="${PHASE_DIR}/${plan_id}-PLAN.md"
   if [[ -f "$PLAN_FILE" ]] && head -1 "$PLAN_FILE" | grep -q '^---' && [[ "$ARGUMENTS" != *"--reviews"* ]]; then
     : # resume safety — skip this plan, remove from the batch's runnable set — NOT under --reviews (replan)
   fi
   ```
   If every entry in the Wave is resumed (runnable set empty), skip straight to the next Wave —
   nothing to dispatch, nothing to wait on.

3. Display:
   ```text
   ◆ Chunked mode: planning {plan_id} ({k}/{N})... (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze)
   ```
   Serial dispatch (`CHUNKED_PARALLEL` is `false`, or the runnable set has exactly one entry):
   print one line per plan, immediately before that plan's own Agent() call, exactly as before.
   Concurrent dispatch: print one line per plan in the runnable set, immediately before issuing
   the batch's Agent() calls together.

4. Spawn the planner in **single-plan** mode — it must write exactly one PLAN.md file. The prompt
   is unchanged per plan; what changes is whether the runnable set's Agent() calls are issued one
   at a time (serial) or together in one message (concurrent, every call still carrying
   `run_in_background=true` exactly as today when `PLANNER_STALL_DETECTION_ENABLED` is `true`
   (default)):
   ```javascript
   Agent(
     prompt="{same planning_context as step 8, plus:}

     **Chunked mode: single-plan.**
     Write exactly ONE plan file: {PHASE_DIR}/{plan_id}-PLAN.md
     Plan to write: {plan_id} — {objective}
     Wave: {wave} | Depends on: {depends_on}
     Phase requirement IDs to cover in this plan: {plan_requirements}

     Return: ## PLAN COMPLETE with the plan ID.",
     subagent_type="gad-planner",
     model="{planner_model}",
     description="Plan {plan_id} (chunked {k}/{N})",
     run_in_background=true
   )
   ```
   **Serial dispatch:** issue one Agent() call, wait for it (step 5), verify and commit it
   (steps 6-7), THEN move to the next entry in the runnable set — byte-identical to the
   pre-#3777 loop.
   **Concurrent dispatch:** issue every runnable entry's Agent() call together, in this one
   message, before waiting on any of them.

5. **ORCHESTRATOR RULE — ALL RUNTIMES, per batch (when `PLANNER_STALL_DETECTION_ENABLED` is `true`):** for every entry dispatched in this round,
   `TS=$(date +%s)`; repeat `PLANNER_STALL_RESULT=$(gad_stall_watch "$TS" "{outputFile}" "$PLAN_FILE" "## PLAN COMPLETE")`
   while waiting/active for THAT entry. Serial dispatch waits on one entry at a time (unchanged).
   Concurrent dispatch waits on every entry issued in step 4 before proceeding — this is the
   "per-batch" join the config makes possible: nothing in step 6 runs until every plan dispatched
   this round has reached `marker_received` or `stalled`. A `stalled` entry falls into step 7's
   Retry/Stop recovery for that one plan; it does not block verifying/committing sibling entries
   in the same batch that already reached `marker_received`.

   - **`false`:** when `PLANNER_STALL_DETECTION_ENABLED` is `false`, omit `run_in_background`
     from every call, skip `gad_stall_watch`, and await each real returned result through the
     ordinary runtime-native completion mechanism. A concurrent batch still issues the runnable
     calls together and awaits all of their ordinary results before step 6. Treat each recognized
     `## PLAN COMPLETE` return exactly like `marker_received`; empty or unrecognized returns keep
     step 8's existing Retry/Stop path. This is never fire-and-forget.

6. **Verify disk, per entry:** check `${PHASE_DIR}/{plan_id}-PLAN.md` exists for each entry that
   reached `marker_received`. Unchanged per-plan check.

7. **Commit, per entry, in outline row order (not completion order):** for each verified entry —
   never one combined commit for the batch — preserving crash resilience: an interrupt mid-batch
   leaves every already-verified entry committed, exactly as a mid-loop interrupt did before this
   change.
```bash
gad_run query commit "docs(${PADDED_PHASE}): plan ${plan_id} (chunked)" --files "${PHASE_DIR}/${plan_id}-PLAN.md"
```

8. **Recovery:** any entry that did not reach `marker_received` (missing file in step 6, or
   `stalled` in step 5) offers 1) Retry, 2) Stop — scoped to that one plan. Sibling entries in the
   same batch that already verified and committed keep their commits either way; only the
   failed/stalled plan is retried or the run stopped.

Move to the next Wave only once every entry in the current Wave is committed or the run was
stopped. After every Wave's plans are written and committed, treat this as `## PLANNING COMPLETE`
and continue to step 9.
