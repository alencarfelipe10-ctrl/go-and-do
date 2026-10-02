@~/.claude/gad-core/references/response-language-directive.md

<purpose>
Detect current project state and automatically advance to the next logical GAD workflow step.
Reads project state to determine: discuss → plan → execute → verify → complete progression.
</purpose>

<required_reading>
Read all files referenced by the invoking prompt's execution_context before starting.
</required_reading>

<process>

<step name="detect_state">
Read project state to determine current position:

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; _gad_id_ok() { case "$("$1" runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') return 0;; *) return 1;; esac; }; _gad_homes() { _gad_at "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; elif _gad_homes; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; _gad_id_ok gad_run && GAD_IDENTITY_STATUS=ok; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
# Get state snapshot
gad_run query state.json 2>/dev/null || echo "{}"
```

Also read:
- `.planning/STATE.md` — current phase, progress, plan counts
- `.planning/ROADMAP.md` — milestone structure and phase list

Extract:
- `current_phase` — which phase is active
- `plan_of` / `plans_total` — plan execution progress
- `progress` — overall percentage
- `status` — active, paused, etc.

If no `.planning/` directory exists:
```
No GAD project detected. Run `/gad-new-project` to get started.
```
Exit.
</step>

<step name="safety_gates">
Run hard-stop checks before routing. Exit on first hit unless `--force` was passed.

If `--force` flag was passed, skip all gates, Route 0, and the prior-phase completeness prompt.
Print a one-line warning: `⚠ --force: skipping safety gates`
Then proceed directly to `determine_next_action`. (Route 0 and `prior_phase_completeness` are NOT reached under `--force`.)

**Gate 1: Unresolved checkpoint**
Check if `.planning/.continue-here.md` exists:
```bash
[ -f .planning/.continue-here.md ]
```
If found:
```
⛔ Hard stop: Unresolved checkpoint

`.planning/.continue-here.md` exists — a previous session left
unfinished work that needs manual review before advancing.

Read the file, resolve the issue, then delete it to continue.
Use `--force` to bypass this check.
```
Exit (do not route).

**Gate 2: Error state**
Check if STATE.md contains `status: error` or `status: failed`:
If found:
```
⛔ Hard stop: Project in error state

STATE.md shows status: {status}. Resolve the error before advancing.
Run `/gad-health` to diagnose, or manually fix STATE.md.
Use `--force` to bypass this check.
```
Exit.

**Gate 3: Unchecked verification**
Check if the current phase has a VERIFICATION.md with any `FAIL` items that don't have overrides:
If found:
```
⛔ Hard stop: Unchecked verification failures

VERIFICATION.md for phase {N} has {count} unresolved FAIL items.
Address the failures or add overrides before advancing to the next phase.
Use `--force` to bypass this check.
```
Exit.

After all three hard-stop gates pass, continue to `resume_incomplete_phase`.
</step>

<step name="resume_incomplete_phase">
**Hard invariant: any phase with PLAN.md files lacking matching SUMMARY.md files must be completed before `/gad-progress --next` routes to any forward action.**

This catches the common failure mode where a session died mid-execution (hang, token exhaustion, API connection drop) and STATE.md's `current_phase` got advanced past the phase that actually has unfinished work. Without this gate, `/gad-progress --next` would route by `current_phase` and silently skip the partially-executed phase.

**Skip if `--no-resume` was passed** (fall through to `prior_phase_completeness`). (`--force` already bypassed all gates and Route 0 at `safety_gates` — it never reaches this step.)

**Why Route 0 runs here (after Gates 1-3, before the prior-phase defer prompt):** This step is a hard invariant independent of `current_phase`'s value — it must run before any routing rule that reads `current_phase`. Gates 1-3 are cheap repo/state validity checks that must always run — skipping them on the resume path would risk advancing into a broken-state project. The prior-phase completeness-scan DEFER PROMPT, however, must NOT run in the default (no-flag) case when Route 0 is about to resume the phase automatically: that would force a double-decision (prompt first, then resume anyway), overriding the user's choice. Route 0 placed here means: default = resume silently (no defer prompt); `--no-resume` = skip Route 0 and fall through to the prior-phase defer prompt in `prior_phase_completeness`; `--force` = jump straight to `determine_next_action` at `safety_gates` (never reaches Route 0 or `prior_phase_completeness` at all).

Scan ALL phases in ROADMAP order (lowest-numbered to highest) for incomplete-execution state. Use `gad_run query roadmap.analyze` to get the phase list, then for each phase number `N` query `gad_run query find-phase <N>` JSON and inspect its `plans` and `summaries` arrays. A phase is **incomplete-execution** when `plans.length > summaries.length` (at least one PLAN.md has no matching SUMMARY.md).

Stop at the first such phase. Record its phase number as `INCOMPLETE_PHASE`. This is the lowest-numbered phase that needs continued execution.

Illustrative bash:

```bash
INCOMPLETE_PHASE=""
ROADMAP_JSON=$(gad_run query roadmap.analyze)
ROADMAP_SCOPE=$(echo "$ROADMAP_JSON" | jq -r '.scope // "complete"')
if [ $? -ne 0 ] || [ -z "$ROADMAP_JSON" ]; then
  echo "⚠ WARNING: resume-incomplete-phase scan could not run (roadmap.analyze failed)." >&2
  echo "  The incomplete-phase invariant (#160) could not be verified." >&2
  echo "  Proceeding to prior-phase completeness check — review project state carefully." >&2
  # Fall through to prior_phase_completeness rather than silently skipping
elif [ "$ROADMAP_SCOPE" != "complete" ]; then
  # #3184/#3165: roadmap.analyze succeeded and returned a well-formed document,
  # but its milestone window did not see all of its input, so `.phases[]` is a
  # NON-answer rather than a real empty. Looping it would run the invariant over
  # a phase list the scan could not populate and report "clean" — the silent
  # disarm #3165 reports. Treated as scan-failed, same as an outright failure.
  echo "⚠ WARNING: resume-incomplete-phase scan could not be scoped (roadmap.analyze scope: $ROADMAP_SCOPE)." >&2
  echo "  The milestone window did not cover the whole ROADMAP, so the phase list is incomplete." >&2
  echo "  The incomplete-phase invariant (#160) could not be verified — review project state carefully." >&2
  # Fall through to prior_phase_completeness rather than silently passing
else
  for PHASE_NUM in $(echo "$ROADMAP_JSON" | jq -r '.phases[] | (.number // .phase_number // empty)'); do
    PHASE_JSON=$(gad_run query find-phase "$PHASE_NUM")
    if [ $? -ne 0 ] || [ -z "$PHASE_JSON" ]; then
      echo "⚠ WARNING: Could not query phase $PHASE_NUM — skipping in resume scan." >&2
      continue
    fi
    PLAN_COUNT=$(echo "$PHASE_JSON" | jq '(.plans // []) | length')
    SUMMARY_COUNT=$(echo "$PHASE_JSON" | jq '(.summaries // []) | length')
    if [ "${PLAN_COUNT:-0}" -gt "${SUMMARY_COUNT:-0}" ]; then
      INCOMPLETE_PHASE="$PHASE_NUM"
      break
    fi
  done
fi
```

**If `INCOMPLETE_PHASE` is non-empty:** route to `/gad-execute-phase $INCOMPLETE_PHASE` and exit. Display a one-line notice before invoking:

```
▶ Resuming incomplete Phase ${INCOMPLETE_PHASE} (plans without summaries detected)
  /gad-execute-phase ${INCOMPLETE_PHASE}
  (use --no-resume to skip this check and defer via the prior-phase prompt)
```

Then invoke via SlashCommand. Do not continue to subsequent steps.

**If `INCOMPLETE_PHASE` is empty:** continue to `prior_phase_completeness`.
</step>

<step name="prior_phase_completeness">
**Prior-phase completeness scan (runs when `--no-resume` was passed and Route 0 was skipped, or when Route 0 found no incomplete-execution phases in the default case). NOT reached under `--force` — that flag jumps directly to `determine_next_action` at `safety_gates`.**

**Prior-phase completeness scan:**
Scan all phases that precede the current phase in ROADMAP.md order for incomplete work. For each prior phase number `N`, use `gad_run query find-phase <N>` JSON (plans, summaries, incomplete_plans, etc.) to inspect that phase.

Detect three categories of incomplete work:
1. **Plans without summaries** — a PLAN.md exists in a prior phase directory but no matching SUMMARY.md exists (execution started but not completed).
2. **Verification failures not overridden** — a prior phase has a VERIFICATION.md with `FAIL` items that have no override annotation.
3. **CONTEXT.md without plans** — a prior phase directory has a CONTEXT.md but no PLAN.md files (discussion happened, planning never ran).

If no incomplete prior work is found, continue to `determine_next_action` silently with no interruption.

If incomplete prior work is found, show a structured completeness report:
```
⚠ Prior phase has incomplete work

Phase {N} — "{name}" has unresolved items:
  • Plan {N}-{M} ({slug}): executed but no SUMMARY.md
  [... additional items ...]

Advancing before resolving these may cause:
  • Verification gaps — future phase verification won't have visibility into what prior phases shipped
  • Context loss — plans that ran without summaries leave no record for future agents

Options:
  [C] Continue and defer these items to backlog
  [S] Stop and resolve manually (recommended)
  [F] Force advance without recording deferral

Choice [S]:
```

**If the user chooses "Stop" (S or Enter/default):** Exit without routing.

**If the user chooses "Continue and defer" (C):**
1. For each incomplete item, create a backlog entry in `ROADMAP.md` under `## Backlog` using the existing `999.x` numbering scheme:
```markdown
### Phase 999.{N}: Follow-up — Phase {src} incomplete plans (BACKLOG)

**Goal:** Resolve plans that ran without producing summaries during Phase {src} execution
**Source phase:** {src}
**Deferred at:** {date} during /gad-progress --next advancement to Phase {dest}
**Plans:**
- [ ] {N}-{M}: {slug} (ran, no SUMMARY.md)
```
2. Commit the deferral record:
```bash
gad_run query commit "docs: defer incomplete Phase {src} items to backlog" \
  --files .planning/ROADMAP.md
```
3. Continue routing to `determine_next_action` immediately — no second prompt.

**If the user chooses "Force" (F):** Continue to `determine_next_action` without recording deferral.
</step>

<step name="spike_sketch_notice">
Check for pending spike/sketch work and surface a notice (does not change routing):

```bash
# Check for pending spikes (verdict: PENDING in any README)
PENDING_SPIKES=$(grep -rl 'verdict: PENDING' .planning/spikes/*/README.md 2>/dev/null | wc -l | tr -d ' ')

# Check for pending sketches (winner: null in any README)
PENDING_SKETCHES=$(grep -rl 'winner: null' .planning/sketches/*/README.md 2>/dev/null | wc -l | tr -d ' ')
```

If either count is > 0, display before routing:
```
⚠ Pending exploratory work:
  {PENDING_SPIKES} spike(s) with unresolved verdicts in .planning/spikes/
  {PENDING_SKETCHES} sketch(es) without a winning variant in .planning/sketches/

  Resume with `/gad-spike` or `/gad-sketch`, or continue with phase work below.
```

Only show lines for non-zero counts. If both are 0, skip this notice entirely.
</step>

<step name="determine_next_action">
Apply routing rules based on state:

**Route 1: No phases exist yet → discuss**
If ROADMAP has phases but no phase directories exist on disk:
→ Next action: `/gad-discuss-phase <first-phase>`

**Route 2: Phase exists but has no CONTEXT.md or RESEARCH.md → discuss**
If the current phase directory exists but has neither CONTEXT.md nor RESEARCH.md:
→ Next action: `/gad-discuss-phase <current-phase>`

**Route 3: Phase has context but no plans → plan**
If the current phase has CONTEXT.md (or RESEARCH.md) but no PLAN.md files:
→ Next action: `/gad-plan-phase <current-phase>` (or `/gad-plan-review-convergence <current-phase>` when `PLAN_STRATEGY=converge`)

**Route 4: Phase has plans but incomplete summaries → execute**
If plans exist but not all have matching summaries:
→ Next action: `/gad-execute-phase <current-phase>`

**Route 5: All plans have summaries → verify and complete**
If all plans in the current phase have summaries:
→ Next action: `/gad-verify-work`

**Route 6: Phase complete, next phase exists → advance**
If the current phase is complete and the next phase exists in ROADMAP:
→ Next action: `/gad-discuss-phase <next-phase>`

**Route 7: All phases complete → complete milestone**
If all phases are complete:
→ Next action: `/gad-complete-milestone`

**Route 8: Paused → resume**
If STATE.md shows paused_at:
→ Next action: `/gad-resume-work`
</step>

<step name="show_and_execute">
Parse the arguments passed to this workflow to detect the plan strategy and build convergence pass-through args:

```bash
PLAN_STRATEGY="local"
if echo "$ARGUMENTS" | grep -qE '(^|[[:space:]])\-\-(converge|cross-ai)([[:space:]]|$)'; then
  PLAN_STRATEGY="converge"
fi

CONVERGENCE_ARGS=""
# Lane flags derived from the declared roster (#2800/#2272); --all and --text are convergence
# controls, not reviewer lanes, so they stay literal.
for REVIEW_FLAG in $(gad_run review-lane flags) --all --text; do
  if echo "$ARGUMENTS" | grep -qE "(^|[[:space:]])${REVIEW_FLAG}([[:space:]]|$)"; then
    CONVERGENCE_ARGS="${CONVERGENCE_ARGS} ${REVIEW_FLAG}"
  fi
done

MAX_CYCLES_ARG=""
if echo "$ARGUMENTS" | grep -qE '\-\-max-cycles\s+[0-9]+'; then
  MAX_CYCLES_ARG=$(echo "$ARGUMENTS" | grep -oE '\-\-max-cycles\s+[0-9]+' | awk '{print $2}')
  CONVERGENCE_ARGS="${CONVERGENCE_ARGS} --max-cycles ${MAX_CYCLES_ARG}"
fi
```

If `PLAN_STRATEGY` is `converge`, fail fast unless the convergence feature gate is enabled:

```bash
if [ "$PLAN_STRATEGY" = "converge" ]; then
  CONVERGENCE_ENABLED=$(gad_run query config-get workflow.plan_review_convergence --raw 2>/dev/null || echo "false")
  if [ "$CONVERGENCE_ENABLED" != "true" ]; then
    printf '%s\n' \
      '/gad-progress --next --converge is disabled (workflow.plan_review_convergence=false).' \
      '' \
      'Enable plan convergence with:' \
      '' \
      '  gad config-set workflow.plan_review_convergence true' \
      '' \
      'Then re-run with --converge.'
    exit 1
  fi
fi
```

Display the determination:

```
## GAD Next

**Current:** Phase [N] — [name] | [progress]%
**Status:** [status description]

▶ **Next step:** `/gad-[command] [args]`
  [One-line explanation of why this is the next step]
```

Then immediately invoke the determined command via SlashCommand.
Do not ask for confirmation — the whole point of `/gad-progress --next` is zero-friction advancement.

**Route 3 convergence override:** When the routing decision is Route 3 (plan) and `PLAN_STRATEGY=converge`, invoke `/gad-plan-review-convergence <current-phase> ${CONVERGENCE_ARGS}` instead of `/gad-plan-phase <current-phase>`.

**If `--auto` was passed:** after the determined command completes, automatically re-invoke `/gad-progress --next --auto` (forwarding `--converge`/`--cross-ai` and any reviewer flags if they were originally passed) to continue chaining to the next step. Repeat until one of:
- A milestone completes (`/gad-complete-milestone` is reached)
- A blocking decision is required (safety gate triggers, prior-phase completeness prompt, user input needed)
- An error or paused state is detected

When stopping due to a blocker, display:
```
⛔ Auto-chain stopped: [reason — e.g. safety gate, blocking decision required]

Resume with: `/gad-progress --next --auto` once resolved.
```
</step>

</process>

<success_criteria>
- [ ] Project state correctly detected
- [ ] Gates 1-3 (repo/state validity) run first — always, even on the resume path
- [ ] Route 0 (resume_incomplete_phase) runs AFTER Gates 1-3 and BEFORE the prior-phase defer prompt — no double-decision in the default (no-flag) case
- [ ] Default (no flag): Route 0 resumes incomplete phase silently, exits — user never sees the prior-phase defer prompt
- [ ] `--no-resume`: Route 0 skipped, prior_phase_completeness defer prompt runs as before
- [ ] `--force`: everything skipped (Gates, Route 0, prior_phase_completeness) → straight to `determine_next_action`
- [ ] Scan uses `gad_run` (canonical resolver form); errors are surfaced rather than suppressed
- [ ] A `roadmap.analyze` result whose `scope` is not `complete` is treated as scan-failed (warn + fall through), never as a clean empty scan (#3184/#3165)
- [ ] Predicate is plans-without-summaries (`plans.length > summaries.length`) — consistent with `determine_next_action` Route 4
- [ ] Next action correctly determined from routing rules
- [ ] Command invoked immediately without user confirmation
- [ ] Clear status shown before invoking
- [ ] `--converge` routes Route 3 planning through `gad-plan-review-convergence`
- [ ] `--cross-ai` is accepted as an alias for `--converge`
- [ ] `--converge` fails fast with enable instructions when `workflow.plan_review_convergence=false`
- [ ] `--converge` forwards reviewer selector flags and `--max-cycles N`
- [ ] Default planning remains `gad-plan-phase` when convergence is not requested
</success_criteria>
