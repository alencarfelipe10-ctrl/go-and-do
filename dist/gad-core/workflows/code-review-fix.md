@~/.claude/gad-core/references/response-language-directive.md

<purpose>
Auto-fix issues from REVIEW.md. Validates phase, checks config gate, verifies REVIEW.md exists and has fixable issues, spawns gad-code-fixer agent, handles --auto iteration loop (capped at 3), commits REVIEW-FIX.md once at the end, and presents results.
</purpose>

<required_reading>
Read all files referenced by the invoking prompt's execution_context before starting.
</required_reading>

<available_agent_types>
- gad-code-fixer: Applies fixes to code review findings
- gad-code-reviewer: Reviews source files for bugs and issues
</available_agent_types>

<process>

<step name="initialize">
Parse arguments and load project state:

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; _gad_id_ok() { case "$("$1" runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') return 0;; *) return 1;; esac; }; _gad_homes() { _gad_at "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; elif _gad_homes; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; _gad_id_ok gad_run && GAD_IDENTITY_STATUS=ok; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
PHASE_ARG="${1}"
INIT=$(gad_run query init.phase-op "${PHASE_ARG}")
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
AGENT_SKILLS_FIXER=$(gad_run query agent-skills gad-code-fixer)
AGENT_SKILLS_REVIEWER=$(gad_run query agent-skills gad-code-reviewer)
# #2072: resolve the routed models so model_overrides / models.<phaseType> are honored
# (gad-code-reviewer → "verification", gad-code-fixer → "execution"); thread them below.
REVIEWER_MODEL=$(gad_run query resolve-model gad-code-reviewer --raw)
FIXER_MODEL=$(gad_run query resolve-model gad-code-fixer --raw)
```

Parse from init JSON: `phase_found`, `phase_dir`, `phase_number`, `phase_name`, `padded_phase`, `commit_docs`.

**Input sanitization (defense-in-depth):**
```bash
# Validate PADDED_PHASE matches the canonical phase-number grammar (src/phase-id.cts): digits,
# an optional single uppercase letter, then dotted segments (e.g., "02", "03.1", "23.1.2", "12A")
if ! [[ "$PADDED_PHASE" =~ ^[0-9]+[A-Z]?(\.[0-9]+)*$ ]]; then
  echo "Error: Invalid phase number format: '${PADDED_PHASE}'. Expected digits with an optional letter suffix (e.g., 02, 03.1, 23.1.2, 12A)."
  # Exit workflow
fi
```

**Phase validation (before config gate):**
If `phase_found` is false, report error and exit:
```
Error: Phase ${PHASE_ARG} not found. Run /gad-progress to see available phases.
```

This runs BEFORE config gate check so user errors are surfaced immediately regardless of config state.

Parse optional flags from $ARGUMENTS:

```bash
FIX_ALL=false
AUTO_MODE=false
for arg in "$@"; do
  if [[ "$arg" == "--all" ]]; then FIX_ALL=true; fi
  if [[ "$arg" == "--auto" ]]; then AUTO_MODE=true; fi
done
```

Compute scope variable:

```bash
if [ "$FIX_ALL" = "true" ]; then
  FIX_SCOPE="all"
else
  FIX_SCOPE="critical_warning"
fi
```

Compute review and fix report paths:

```bash
REVIEW_PATH="${PHASE_DIR}/${PADDED_PHASE}-REVIEW.md"
FIX_REPORT_PATH="${PHASE_DIR}/${PADDED_PHASE}-REVIEW-FIX.md"
```
</step>

<step name="check_config_gate">
Check if code review is active via the capability registry:

```bash
EXECUTE_POST_HOOKS_JSON=$(gad_run loop render-hooks execute:post --raw)
```

Resolve active step hooks from `EXECUTE_POST_HOOKS_JSON` where `kind == "step"` and `ref.skill == "code-review"`.

If no active code-review step hook exists:
```
Code review fix skipped (code-review capability inactive)
```
Exit workflow.

Default is active through the Capability Registry schema — only skip when the registry resolves no active code-review step hook. This check runs AFTER phase validation so invalid phase errors are shown first.

Note: This reuses the code-review capability activation rather than introducing a separate code-review-fix capability. Rationale: fixes are meaningless without review, so a single activation boundary makes sense. If independent control is needed later, a separate key can be added in v2.
</step>

<step name="check_review_exists">
Verify that REVIEW.md exists:

```bash
if [ ! -f "${REVIEW_PATH}" ]; then
  echo "Error: No REVIEW.md found for Phase ${PHASE_ARG}. Run /gad-code-review ${PHASE_ARG} first."
  exit 1
fi
```

Do NOT auto-run code-review. Require explicit user action to ensure review intent is clear.
</step>

<step name="check_review_status">
Parse REVIEW.md frontmatter to check status and extract context for --auto loop:

```bash
# Parse status field
REVIEW_STATUS=$(REVIEW_PATH="${REVIEW_PATH}" node -e "
  const fs = require('fs');
  const content = fs.readFileSync(process.env.REVIEW_PATH, 'utf-8');
  const match = content.replace(/\r\n/g, '\n').match(/^---\n([\s\S]*?)\n---/);
  if (match && /status:\s*(\S+)/.test(match[1])) {
    console.log(match[1].match(/status:\s*(\S+)/)[1]);
  } else {
    console.log('unknown');
  }
" 2>/dev/null)
```

If status is "clean" or "skipped":
```
No issues to fix in Phase ${PHASE_ARG} REVIEW.md (status: ${REVIEW_STATUS}).
```
Exit workflow.

If status is "unknown":
```
Warning: Could not parse REVIEW.md status. Proceeding with fix attempt.
```

Extract review depth for --auto re-review:

```bash
REVIEW_DEPTH=$(REVIEW_PATH="${REVIEW_PATH}" node -e "
  const fs = require('fs');
  const content = fs.readFileSync(process.env.REVIEW_PATH, 'utf-8');
  const match = content.replace(/\r\n/g, '\n').match(/^---\n([\s\S]*?)\n---/);
  if (match && /depth:\s*(\S+)/.test(match[1])) {
    console.log(match[1].match(/depth:\s*(\S+)/)[1]);
  } else {
    console.log('standard');
  }
" 2>/dev/null)
```

Extract original review file list for --auto re-review scope persistence:

```bash
# Extract review file list — portable bash 3.2+ (no mapfile, handles spaces in paths)
REVIEW_FILES_ARRAY=()
while IFS= read -r line; do
  [ -n "$line" ] && REVIEW_FILES_ARRAY+=("$line")
done < <(REVIEW_PATH="${REVIEW_PATH}" node -e "
  const fs = require('fs');
  const content = fs.readFileSync(process.env.REVIEW_PATH, 'utf-8');
  const match = content.replace(/\r\n/g, '\n').match(/^---\n([\s\S]*?)\n---/);
  if (match) {
    const fm = match[1];
    // Try YAML array format: files_reviewed_list: [file1, file2]
    const bracketMatch = fm.match(/files_reviewed_list:\s*\[([^\]]+)\]/);
    if (bracketMatch) {
      bracketMatch[1].split(',').map(f => f.trim()).filter(Boolean).forEach(f => console.log(f));
    } else {
      // Try YAML list format: files_reviewed_list:\n  - file1\n  - file2
      let inList = false;
      for (const line of fm.split('\n')) {
        if (/files_reviewed_list:/.test(line)) { inList = true; continue; }
        if (inList && /^\s+-\s+(.+)/.test(line)) { console.log(line.match(/^\s+-\s+(.+)/)[1].trim()); }
        else if (inList && /^\S/.test(line)) { break; }
      }
    }
  }
" 2>/dev/null)
```

If REVIEW.md contains a `files_reviewed_list` frontmatter field, use that as the re-review scope. If not present, fall back to re-reviewing the full phase (same behavior as initial code-review).
</step>

<step name="spawn_fixer">
Spawn the gad-code-fixer agent with config (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze):

```bash
# Build config for agent
echo "Applying fixes from ${REVIEW_PATH}..."
echo "Fix scope: ${FIX_SCOPE}"
```

Use Agent() to spawn agent:

<!-- #2508 runtime-aware-dispatch -->

> **Runtime-aware dispatch (#2508 Phase 4).** GAD workflows dispatch specialized subagents by role. Before dispatching on a built-in-only runtime (kimi-code — three built-ins only), resolve the role to a built-in via `gad_run query resolve-dispatch-type --requested <role> --raw`. On named-dispatch runtimes (Claude/OpenCode/…) the role is returned unchanged; on kimi-code it maps to `coder`/`explore`/`plan` by role-suffix. The persona rides `${AGENT_SKILLS_<ROLE>}` (Phase 3) regardless. See @gad-core/references/runtime-aware-dispatch.md.

<!-- #2517 model-omit-on-inherit -->

> **Model omission (#2517).** Omit the `model` parameter entirely when the value it would carry (`FIXER_MODEL`, `REVIEWER_MODEL`) is `"inherit"` or empty. An empty value 404s on runtimes without native tier aliases — the default on non-Claude runtimes. Omitting it inherits the orchestrator's model. See @gad-core/references/model-profile-resolution.md.

```text
Agent(subagent_type="gad-code-fixer", model="{FIXER_MODEL}", prompt="
<required_reading>
${REVIEW_PATH}
</required_reading>

<config>
phase_dir: ${PHASE_DIR}
padded_phase: ${PADDED_PHASE}
review_path: ${REVIEW_PATH}
fix_scope: ${FIX_SCOPE}
fix_report_path: ${FIX_REPORT_PATH}
iteration: 1
</config>

Read REVIEW.md findings, apply fixes, commit each atomically, write REVIEW-FIX.md. Do NOT commit REVIEW-FIX.md (orchestrator handles that).
${AGENT_SKILLS_FIXER}")
```

> **ORCHESTRATOR RULE — CODEX RUNTIME**: After calling Agent() above, stop working on this task immediately. Do not read more files, edit code, or run tests related to this task while the subagent is active. Wait for the subagent to return its result. This prevents duplicate work, conflicting edits, and wasted context. Only resume when the subagent result is available.

**Agent failure handling:**

If Agent() fails:
```
Error: Code fix agent failed: ${error_message}
```

Check if FIX_REPORT_PATH exists:
- If yes: "Partial success — some fixes may have been committed."
- If no: "No fixes applied."

Either way:
```
Some fix commits may already exist in git history — check git log for fix(${PADDED_PHASE}) commits.
You can retry with /gad-code-review ${PHASE_ARG} --fix.
```

Exit workflow (skip auto loop).
</step>

<step name="auto_iteration_loop">
Only runs if AUTO_MODE is true. If AUTO_MODE is false, skip this step entirely.

```bash
if [ "$AUTO_MODE" = "true" ]; then
  # Iteration semantics: the initial fix pass (step 5) is iteration 1.
  # This loop runs iterations 2..MAX_ITERATIONS (re-review + re-fix cycles).
  # Total fix passes = MAX_ITERATIONS. Loop uses -lt (not -le) intentionally.
  ITERATION=1
  MAX_ITERATIONS=3
  # #3190's convergence-vs-degradation distinction still governs whether the .iterN.md backups are
  # spent scratch or a post-mortem trail — but the removal moved to `cleanup_iteration_backups`,
  # after `record_disposition` has read them, so nothing in THIS loop consumes the flag any more.
  # It is re-derived there from the final REVIEW.md's status, which is exactly the condition the
  # `break` below fires on. A variable set here and read nowhere would just be a decoy.

  while [ $ITERATION -lt $MAX_ITERATIONS ]; do
    ITERATION=$((ITERATION + 1))
    
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  --auto: Starting iteration ${ITERATION}/${MAX_ITERATIONS}"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    
    # Re-review using same depth and file scope as original review
    echo "Re-reviewing phase ${PHASE_ARG} at ${REVIEW_DEPTH} depth..."
    
    # Backup previous REVIEW.md and REVIEW-FIX.md before overwriting
    if [ -f "${REVIEW_PATH}" ]; then
      cp "${REVIEW_PATH}" "${REVIEW_PATH%.md}.iter${ITERATION}.md" 2>/dev/null || true
    fi
    if [ -f "${FIX_REPORT_PATH}" ]; then
      cp "${FIX_REPORT_PATH}" "${FIX_REPORT_PATH%.md}.iter${ITERATION}.md" 2>/dev/null || true
    fi
    
    # If original review had explicit file list, pass it safely to re-review agent
    FILES_CONFIG=""
    if [ ${#REVIEW_FILES_ARRAY[@]} -gt 0 ]; then
      FILES_CONFIG="files:"
      for f in "${REVIEW_FILES_ARRAY[@]}"; do
        FILES_CONFIG="${FILES_CONFIG}
  - ${f}"
      done
    fi
    
    # Spawn gad-code-reviewer agent to re-review (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze)
    # (This overwrites REVIEW_PATH with latest review state)
    Agent(subagent_type="gad-code-reviewer", model="{REVIEWER_MODEL}", prompt="
<config>
depth: ${REVIEW_DEPTH}
phase_dir: ${PHASE_DIR}
review_path: ${REVIEW_PATH}
${FILES_CONFIG}
</config>

Re-review the phase at ${REVIEW_DEPTH} depth. Write findings to ${REVIEW_PATH}.
Do NOT commit the output — the orchestrator handles that.
${AGENT_SKILLS_REVIEWER}")
    # ORCHESTRATOR RULE — CODEX RUNTIME: After calling Agent() above, stop working on this task immediately. Do not read more files, edit code, or run tests related to this task while the subagent is active. Wait for the subagent to return its result before proceeding.
    
    # Check new REVIEW.md status
    NEW_STATUS=$(REVIEW_PATH="${REVIEW_PATH}" node -e "
      const fs = require('fs');
      const content = fs.readFileSync(process.env.REVIEW_PATH, 'utf-8');
      const match = content.replace(/\r\n/g, '\n').match(/^---\n([\s\S]*?)\n---/);
      if (match && /status:\s*(\S+)/.test(match[1])) {
        console.log(match[1].match(/status:\s*(\S+)/)[1]);
      } else {
        console.log('unknown');
      }
    " 2>/dev/null)
    
    if [ "$NEW_STATUS" = "clean" ]; then
      # Convergence: the re-review came back clean. This leaves REVIEW.md at `status: clean`, which
      # is what `cleanup_iteration_backups` re-derives the decision from.
      echo ""
      echo "✓ All issues resolved after iteration ${ITERATION}."
      break
    fi
    
    # Still has issues — spawn fixer again (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze)
    echo "Issues remain. Applying fixes for iteration ${ITERATION}..."
    
    Agent(subagent_type="gad-code-fixer", model="{FIXER_MODEL}", prompt="
<required_reading>
${REVIEW_PATH}
</required_reading>

<config>
phase_dir: ${PHASE_DIR}
padded_phase: ${PADDED_PHASE}
review_path: ${REVIEW_PATH}
fix_scope: ${FIX_SCOPE}
fix_report_path: ${FIX_REPORT_PATH}
iteration: ${ITERATION}
</config>

Read REVIEW.md findings, apply fixes, commit each atomically, write REVIEW-FIX.md (overwrite previous). Do NOT commit REVIEW-FIX.md.
${AGENT_SKILLS_FIXER}")
    # ORCHESTRATOR RULE — CODEX RUNTIME: After calling Agent() above, stop working on this task immediately. Do not read more files, edit code, or run tests related to this task while the subagent is active. Wait for the subagent to return its result before proceeding.
    
    # Check if fixer succeeded
    if [ ! -f "${FIX_REPORT_PATH}" ]; then
      echo "Warning: Iteration ${ITERATION} fixer failed to produce fix report. Stopping auto-loop."
      break
    fi
  done
  
  # After loop completes. The iteration COUNTER alone does not distinguish degradation from success:
  # a loop that converges on the final iteration exits with ITERATION == MAX_ITERATIONS and printed
  # "Reached maximum iterations. Remaining issues documented in REVIEW-FIX.md" over a run in which
  # every finding was fixed — telling the operator the opposite of what happened, on the one path
  # where the cap and convergence coincide. Convergence is re-derived from the review the loop left
  # behind, the same signal cleanup_iteration_backups reads, so the two cannot disagree.
  if [ $ITERATION -ge $MAX_ITERATIONS ]; then
    LOOP_END_STATUS=$(REVIEW_PATH="${REVIEW_PATH}" node -e "
      const fs = require('fs');
      try {
        const content = fs.readFileSync(process.env.REVIEW_PATH, 'utf-8');
        const match = content.replace(/\r\n/g, '\n').match(/^---\n([\s\S]*?)\n---/);
        console.log(match && /status:\s*(\S+)/.test(match[1]) ? match[1].match(/status:\s*(\S+)/)[1] : 'unknown');
      } catch (e) { console.log('unknown'); }
    " 2>/dev/null)
    if [ "$LOOP_END_STATUS" = "clean" ]; then
      # SILENT on convergence, deliberately. The loop's own break already printed "All issues
      # resolved after iteration N" on its way out, and reaching the cap does not make that less
      # true — adding a second success line here printed both, which is noise the first cut shipped.
      # What this branch exists for is to NOT print the degradation warning; saying nothing is the
      # whole behaviour.
      :
    else
      echo ""
      echo "⚠ Reached maximum iterations (${MAX_ITERATIONS}). Remaining issues documented in REVIEW-FIX.md."
    fi
  fi

  # #3190's cleanup of the .iterN.md backups now runs in `cleanup_iteration_backups`, AFTER
  # `record_disposition` — see that step for why. Removing them here deleted the only record of
  # what the earlier iterations fixed before anything had read it.
fi
```

Key design decisions for --auto (addresses ALL review HIGH concerns):
1. **Re-review scope**: Uses REVIEW_FILES_ARRAY from original REVIEW.md frontmatter, falling back to full phase scope. Scope is NOT lost between iterations. Uses portable while-read loop (bash 3.2+ compatible, handles spaces in paths).
2. **Artifact semantics**: REVIEW.md is overwritten by each re-review (latest review state). REVIEW-FIX.md is overwritten by each fixer iteration (latest fix state with iteration count). There is ONE final version of each artifact, not per-iteration copies.
   Backup files (.iterN.md) preserve history for post-mortem analysis if iterations degrade. On successful convergence (#3190) the backups are spent scratch and removed; on degradation (hit MAX_ITERATIONS / fixer failure) they are retained for post-mortem. The removal happens in `cleanup_iteration_backups`, after `record_disposition` has read them — they are the only surviving record of what an earlier iteration fixed, since this artifact keeps one final version rather than per-iteration copies.
3. **Commit timing**: Fix commits happen per-finding inside the agent. REVIEW-FIX.md is NOT committed until step 7 (after ALL iterations complete). Only ONE docs commit, not one per iteration. In --auto that single commit also stages the converged REVIEW.md alongside REVIEW-FIX.md (#3190), so the two committed artifacts agree — the initial code-review commit held iteration-1 REVIEW.md content, and the --auto re-review loop overwrote it each iteration.
</step>

<step name="commit_fix_report">
After ALL iterations complete (or single pass in non-auto mode), validate and commit REVIEW-FIX.md:

```bash
if [ -f "${FIX_REPORT_PATH}" ]; then
  # Validate REVIEW-FIX.md has valid YAML frontmatter with status field
  # #3190: export FIX_REPORT_PATH (the var the body reads), not REVIEW_PATH.
  HAS_STATUS=$(FIX_REPORT_PATH="${FIX_REPORT_PATH}" node -e "
    const fs = require('fs');
    const content = fs.readFileSync(process.env.FIX_REPORT_PATH, 'utf-8');
    const match = content.replace(/\r\n/g, '\n').match(/^---\n([\s\S]*?)\n---/);
    if (match && /status:/.test(match[1])) { console.log('valid'); } else { console.log('invalid'); }
  " 2>/dev/null)
  
  if [ "$HAS_STATUS" = "valid" ]; then
    echo "REVIEW-FIX.md created at ${FIX_REPORT_PATH}"
    
    if [ "$COMMIT_DOCS" = "true" ]; then
      # #3190: --auto's re-review loop overwrote REVIEW.md each iteration
      # (auto_iteration_loop), but the only prior REVIEW.md commit is the
      # initial code-review pass (iteration-1 content). Stage the converged
      # REVIEW.md alongside REVIEW-FIX.md in this single docs commit so the two
      # committed artifacts agree. Non-auto single-pass runs never rewrite
      # REVIEW.md, so it is left untouched (guarded on AUTO_MODE).
      COMMIT_FILES=("${FIX_REPORT_PATH}")
      if [ "$AUTO_MODE" = "true" ] && [ -f "${REVIEW_PATH}" ]; then
        COMMIT_FILES+=("${REVIEW_PATH}")
      fi
      gad_run query commit \
        "docs(${PADDED_PHASE}): add code review fix report" \
        --files "${COMMIT_FILES[@]}"
    fi
  else
    echo "Warning: REVIEW-FIX.md has invalid frontmatter (no status field). Not committing."
    echo "Agent may have produced malformed output. Review manually: ${FIX_REPORT_PATH}"
  fi
else
  echo "Warning: REVIEW-FIX.md not found at ${FIX_REPORT_PATH}."
  echo "Agent may have failed before writing report."
  echo "Check git log for any fix(${PADDED_PHASE}) commits that were applied."
fi
```

This commit happens ONCE at the end of the workflow, after all iterations (if --auto) complete. Not per-iteration.
</step>

<step name="record_disposition">
**Reconcile the per-finding disposition ledger, now that REVIEW-FIX.md exists.** Read and execute
`gad-core/workflows/execute-phase/steps/code-review-disposition.md`. It consumes `PHASE_DIR` and
`PHASE_NUMBER` and derives everything else, and it is advisory throughout: it never blocks.

This is the step's second and final call site, and without it REQ-REVIEW-10 is unreachable in every
shipped path. `execute-phase.md`'s `code_review_gate` runs the same step immediately after review,
where `<NN>-REVIEW-FIX.md` cannot yet exist — the gate invokes review with neither `--fix` nor
`--auto` — so every row it writes is `open` by construction. The reconciliation logic that turns
those rows into `fixed` / `skipped` is reachable only once a fix report is on disk, which is here.
Wired anywhere earlier and it reads a report that has not been written; wired into `code-review.md`
instead, it is unreachable — that workflow delegates through `code-review/steps/dispatch-fix.md`,
which exits the workflow after invoking this one, so there is no point in it that is after
REVIEW-FIX.md exists. Placing it here also covers a direct invocation of this workflow, which a
wiring in `code-review.md` would miss.

Placed AFTER `commit_fix_report` deliberately: the fix report must be on disk and committed before
the ledger claims anything about it, and the step's own reconciliation reads
`${PHASE_DIR}/${PADDED_PHASE}-REVIEW-FIX.md` directly.

Safe to run twice. The step is idempotent — a re-render that changes nothing reports `unchanged` and
rewrites no file — so a phase that reaches the gate and then a fix run ends with one ledger reflecting
both, not two competing ones.
</step>

<step name="cleanup_iteration_backups">
Only runs if AUTO_MODE is true. If AUTO_MODE is false, skip this step entirely.

**Removes the `.iterN.md` scratch — deliberately AFTER `record_disposition`, not at the end of the
loop.** #3190's rule is unchanged: on convergence the backups are spent scratch and go; on degradation
they are retained for post-mortem. What changed is the timing, and it was load-bearing. This workflow
keeps ONE final version of `REVIEW.md` and `REVIEW-FIX.md` rather than per-iteration copies, so the
backups are the only surviving record of what an earlier iteration fixed — and the re-review drops a
finding once it is fixed, so the final review does not carry it either. Deleting them inside the loop
meant the disposition ledger reached a converged `--auto` run with every early fix already erased, and
recorded those findings as `open (not in the current review)`: indistinguishable from never triaged,
which is the one distinction #3829 exists to make.

Convergence is re-derived here rather than carried. Shell state does not survive the loop's fence, so
a flag set there would be gone by this step — and once nothing in the loop consumed it, keeping it
would have left a variable set in one place and read in none. The loop breaks on exactly one
condition, a re-review returning clean, and that leaves `REVIEW.md` at `status: clean`: the final
review's status IS the converged case. Hitting `MAX_ITERATIONS` leaves the last re-review non-clean,
and the backups are kept.

```bash
if [ "$AUTO_MODE" = "true" ]; then
  FINAL_STATUS=$(REVIEW_PATH="${REVIEW_PATH}" node -e "
    const fs = require('fs');
    try {
      const content = fs.readFileSync(process.env.REVIEW_PATH, 'utf-8');
      const match = content.replace(/\r\n/g, '\n').match(/^---\n([\s\S]*?)\n---/);
      console.log(match && /status:\s*(\S+)/.test(match[1]) ? match[1].match(/status:\s*(\S+)/)[1] : 'unknown');
    } catch (e) { console.log('unknown'); }
  " 2>/dev/null)
  # Anything but a proven-clean final review RETAINS the backups. An unreadable or unparseable
  # review is not evidence of convergence, and retaining costs a few scratch files where deleting
  # costs the post-mortem trail the retention rule exists for.
  if [ "$FINAL_STATUS" = "clean" ]; then
    rm -f "${REVIEW_PATH%.md}.iter"*.md "${FIX_REPORT_PATH%.md}.iter"*.md 2>/dev/null || true
  else
    echo "Iteration backups retained (final review status: ${FINAL_STATUS}) — post-mortem trail."
  fi
fi
```
</step>

<step name="present_results">
Parse REVIEW-FIX.md frontmatter and present formatted summary to user.

First check if fix report exists:

```bash
if [ ! -f "${FIX_REPORT_PATH}" ]; then
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "  ⚠ No fix report generated"
  echo ""
  echo "───────────────────────────────────────────────────────────────"
  echo ""
  echo "The fixer agent may have failed before completing."
  echo "Check git log for any fix(${PADDED_PHASE}) commits."
  echo ""
  echo "Retry: /gad-code-review ${PHASE_ARG} --fix"
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  exit 1
fi
```

Extract frontmatter fields:

```bash
# Extract only the YAML frontmatter block (between first two --- lines)
# #3190: export FIX_REPORT_PATH (the var the body reads), not REVIEW_PATH.
FIX_FRONTMATTER=$(FIX_REPORT_PATH="${FIX_REPORT_PATH}" node -e "
  const fs = require('fs');
  const content = fs.readFileSync(process.env.FIX_REPORT_PATH, 'utf-8');
  const match = content.replace(/\r\n/g, '\n').match(/^---\n([\s\S]*?)\n---/);
  if (match) process.stdout.write(match[1]);
" 2>/dev/null)

# Parse fields from frontmatter only (not full file)
FIX_STATUS=$(echo "$FIX_FRONTMATTER" | grep "^status:" | cut -d: -f2 | xargs)
FINDINGS_IN_SCOPE=$(echo "$FIX_FRONTMATTER" | grep "^findings_in_scope:" | cut -d: -f2 | xargs)
FIXED_COUNT=$(echo "$FIX_FRONTMATTER" | grep "^fixed:" | cut -d: -f2 | xargs)
SKIPPED_COUNT=$(echo "$FIX_FRONTMATTER" | grep "^skipped:" | cut -d: -f2 | xargs)
ITERATION_COUNT=$(echo "$FIX_FRONTMATTER" | grep "^iteration:" | cut -d: -f2 | xargs)
```

Display formatted inline summary:

```bash
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Code Review Fix Complete: Phase ${PHASE_NUMBER} (${PHASE_NAME})"
echo ""
echo "───────────────────────────────────────────────────────────────"
echo ""
echo "  Fix Scope:       ${FIX_SCOPE}"
echo "  Findings:        ${FINDINGS_IN_SCOPE}"
echo "  Fixed:           ${FIXED_COUNT}"
echo "  Skipped:         ${SKIPPED_COUNT}"
if [ "$AUTO_MODE" = "true" ]; then
  echo "  Iterations:      ${ITERATION_COUNT}"
fi
echo "  Status:          ${FIX_STATUS}"
echo ""
echo "───────────────────────────────────────────────────────────────"
echo ""
```

If status is "all_fixed":
```bash
if [ "$FIX_STATUS" = "all_fixed" ]; then
  echo "✓ All issues resolved."
  echo ""
  echo "Full report: ${FIX_REPORT_PATH}"
  echo ""
  echo "Next step:"
  echo "  /gad-verify-work  — Verify phase completion"
  echo ""
fi
```

If status is "partial" or "none_fixed":
```bash
if [ "$FIX_STATUS" = "partial" ] || [ "$FIX_STATUS" = "none_fixed" ]; then
  echo "⚠ Some issues could not be fixed automatically."
  echo ""
  echo "Full report: ${FIX_REPORT_PATH}"
  echo ""
  echo "Next steps:"
  echo "  cat ${FIX_REPORT_PATH}                     — View fix report"
  echo "  /gad-code-review ${PHASE_NUMBER}           — Re-review code"
  echo "  /gad-verify-work                           — Verify phase completion"
  echo ""
fi
```

```bash
echo "═══════════════════════════════════════════════════════════════"
```
</step>

</process>

<platform_notes>
**Windows:** This workflow uses bash features (arrays, variable expansion, while loops). On Windows, it requires Git Bash or WSL. Native PowerShell is not supported. The CI matrix (Ubuntu/macOS/Windows) runs under Git Bash on Windows runners, which provides bash compatibility.
</platform_notes>

<success_criteria>
- [ ] Phase validated before config gate check
- [ ] Capability gate checked (execute:post code-review hook)
- [ ] REVIEW.md existence verified (error if missing)
- [ ] REVIEW.md status checked (skip if clean/skipped)
- [ ] Agent spawned with correct config (review_path, fix_scope, fix_report_path)
- [ ] Agent failure handled with partial-success awareness (some fix commits may exist)
- [ ] --auto iteration loop respects 3-iteration cap
- [ ] --auto re-review uses persisted file scope (not lost between iterations)
- [ ] REVIEW-FIX.md committed ONCE after all iterations (not per-iteration)
- [ ] Missing fix report handled with explicit error message in present_results
- [ ] Results presented inline with next step suggestion
</success_criteria>
