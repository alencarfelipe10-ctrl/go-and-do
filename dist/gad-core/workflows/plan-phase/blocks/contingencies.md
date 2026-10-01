# plan-phase — contingencies (steps 9a–9c and 11a)

Lazy block of `workflows/plan-phase.md` for the branches a normal run never takes. Read it only when step 4 finds no CONTEXT.md, when a planner or checker return is not the plain success marker (empty/truncated return — 9a, 11a; `## PHASE SPLIT RECOMMENDED` — 9b; `## ⚠ Source Audit` — 9c), or when a coverage gate fails (13, 13a). Before deciding that a return "has no recognized marker", Read `~/.claude/gad-core/references/agent-contracts.md` — it is the marker table and the regexes the orchestrator matches against; a marker that is present but formatted differently is not a fallback case.

### Step 4 — no CONTEXT.md exists

**If `context_path` is null (no CONTEXT.md exists):**

Read discuss mode for context gate label:
```bash
DISCUSS_MODE=$(gad_run query config-get workflow.discuss_mode --raw 2>/dev/null || echo "discuss")
```

If `TEXT_MODE` is true, present as a plain-text numbered list:
```
No CONTEXT.md found for Phase {X}. Plans will use research and requirements only — your design preferences won't be included.

1. Continue without context — Plan using research + requirements only
[If DISCUSS_MODE is "assumptions":]
2. Gather context (assumptions mode) — Analyze codebase and surface assumptions before planning
[If DISCUSS_MODE is "discuss" or unset:]
2. Run discuss-phase first — Capture design decisions before planning

Enter number:
```

Otherwise use AskUserQuestion:
- header: "No context"
- question: "No CONTEXT.md found for Phase {X}. Plans will use research and requirements only — your design preferences won't be included. Continue or capture context first?"
- options:
  - "Continue without context" — Plan using research + requirements only
  If `DISCUSS_MODE` is `"assumptions"`:
  - "Gather context (assumptions mode)" — Analyze codebase and surface assumptions before planning
  If `DISCUSS_MODE` is `"discuss"` (or unset):
  - "Run discuss-phase first" — Capture design decisions before planning

If "Continue without context": Proceed to step 5.
If "Run discuss-phase first":
  **IMPORTANT:** Do NOT invoke discuss-phase as a nested Skill/Task call — AskUserQuestion
  does not work correctly in nested subcontexts (#1009). Instead, display the command
  and exit so the user runs it as a top-level command:
  ```
  Run this command first, then re-run /gad-plan-phase {X} ${GAD_WS}:

  /gad-discuss-phase {X} ${GAD_WS}
  ```
  **Exit the plan-phase workflow. Do not continue.**

## 9a. Filesystem Fallback (Planner)

**Triggered when:** Agent() returns but the return contains no recognized marker (`## PLANNING COMPLETE`, `## PHASE SPLIT RECOMMENDED`, `## ⚠ Source Audit`, `## CHECKPOINT REACHED`, `## PLANNING INCONCLUSIVE`).

```bash
# #3218: this asks "did the planner write files to disk at all" — a
# planner-produced-nothing check, not outstanding-work counting — so it
# takes the PHYSICAL set (`plan_count_all`, status:superseded INCLUDED): a
# superseded plan is still a file the planner wrote, and this check must not
# read "nothing written" just because every plan happens to be superseded.
DISK_PLANS=$(gad_run query find-phase "${PHASE_NUMBER}" | jq -r '.plan_count_all // 0')
```

**If `DISK_PLANS` > 0:** The planner wrote plans to disk but the Agent() return was empty or
truncated (the Windows stdio hang pattern — the subagent finished but the return never
arrived). Display:

```text
◆ Planner wrote {DISK_PLANS} plan(s) to disk but did not emit a PLANNING COMPLETE marker.
  This is a known Windows stdio hang pattern — work is likely recoverable.

  Plans found on disk:
  {ls output of *-PLAN.md}
```

Offer 3 options:
1. **Accept plans** — treat as `## PLANNING COMPLETE` and continue through step 9 `## PLANNING COMPLETE` handling (so `--skip-verify` / `plan_checker_enabled=false` are honored — may skip to step 13 rather than step 10)
2. **Retry planner** — re-spawn the planner with the same prompt (return to step 8)
3. **Stop** — exit; user can re-run `/gad-plan-phase {N}` to resume

**If `DISK_PLANS` is 0 and no marker:** The planner produced no output. Treat as
`## PLANNING INCONCLUSIVE` and handle accordingly.

## 9b. Handle Phase Split Recommendation

When the planner returns `## PHASE SPLIT RECOMMENDED`, it means the phase's source items exceed the context budget for full-fidelity implementation. The planner proposes groupings.

**Extract from planner return:**
- Proposed sub-phases (e.g., "17a: processing core (D-01 to D-19)", "17b: billing + config UX (D-20 to D-27)")
- Which source items (REQ-IDs, D-XX decisions, RESEARCH items) go in each sub-phase
- Why the split is necessary (context cost estimate, file count)

**Present to user:**
```
## Phase {X} exceeds context budget for full-fidelity implementation

The planner found {N} source items that exceed the context budget when
planned at full fidelity. Instead of reducing scope, we recommend splitting:

**Option 1: Split into sub-phases**
- Phase {X}a: {name} — {items} ({N} source items, ~{P}% context)
- Phase {X}b: {name} — {items} ({M} source items, ~{Q}% context)

**Option 2: Proceed anyway** (planner will attempt all, quality may degrade past 50% context)

**Option 3: Prioritize** — you choose which items to implement now,
rest become a follow-up phase
```

Use AskUserQuestion with these 3 options.

**If "Split":** Use `/gad-phase --insert` to create the sub-phases, then replan each.
**If "Proceed":** Return to planner with instruction to attempt all items at full fidelity, accepting more plans/tasks.
**If "Prioritize":** Use AskUserQuestion (multiSelect) to let user pick which items are "now" vs "later". Create CONTEXT.md for each sub-phase with the selected items.

## 9c. Handle Source Audit Gaps

When the planner returns `## ⚠ Source Audit: Unplanned Items Found`, it means items from REQUIREMENTS.md, RESEARCH.md, ROADMAP goal, or CONTEXT.md decisions have no corresponding plan.

**Extract from planner return:**
- Each unplanned item with its source artifact and section
- The planner's suggested options (A: add plan, B: split phase, C: defer with confirmation)

**Present each gap to user.** For each unplanned item:

```
## ⚠ Unplanned: {item description}

Source: {RESEARCH.md / REQUIREMENTS.md / ROADMAP goal / CONTEXT.md}
Details: {why the planner flagged this}

Options:
1. Add a plan to cover this item (recommended)
2. Split phase — move to a sub-phase with related items
3. Defer — add to backlog (developer confirms this is intentional)
```

Use AskUserQuestion for each gap (or batch if multiple gaps).

**If "Add plan":** Return to planner (step 8) with instruction to add plans covering the missing items, preserving existing plans.
**If "Split":** Use `/gad-phase --insert` for overflow items, then replan.
**If "Defer":** Record in CONTEXT.md `## Deferred Ideas` with developer's confirmation. Proceed to step 10.

## 11a. Filesystem Fallback (Checker)

**Triggered when:** Checker Agent() returns but the return contains neither `## VERIFICATION PASSED` nor `## ISSUES FOUND`.

```bash
# #3218: this asks "did the planner write files to disk at all" — a
# planner-produced-nothing check, not outstanding-work counting — so it
# takes the PHYSICAL set (`plan_count_all`, status:superseded INCLUDED): a
# superseded plan is still a file the planner wrote, and this check must not
# read "nothing written" just because every plan happens to be superseded.
DISK_PLANS=$(gad_run query find-phase "${PHASE_NUMBER}" | jq -r '.plan_count_all // 0')
```

**If `DISK_PLANS` > 0:** Plans exist on disk; the checker return was empty or truncated (the
Windows stdio hang pattern — the subagent finished but the return never arrived). Display:

```text
◆ Checker return was empty or truncated. {DISK_PLANS} plan(s) exist on disk.
  This is a known Windows stdio hang pattern — checker may have completed without returning.
```

Offer 3 options:
1. **Accept verification** — treat as `## VERIFICATION PASSED` and continue to step 13
2. **Retry checker** — re-spawn the checker with the same prompt (return to step 10)
3. **Stop** — exit; user can re-run `/gad-plan-phase {N}` to resume

**If `DISK_PLANS` is 0:** No plans on disk — something is seriously wrong. Display error and stop.

### Step 13 — requirements coverage gap

If gaps were found in step 13:

```
## ⚠ Requirements Coverage Gap

{M} of {N} phase requirements are not assigned to any plan:

| REQ-ID | Description | Plans |
|--------|-------------|-------|
| {id} | {from REQUIREMENTS.md} | None |

{K} CONTEXT.md features not found in plan objectives:
- {feature_name} — described in CONTEXT.md but no plan covers it

Options:
1. Re-plan to include missing requirements (recommended)
2. Move uncovered requirements to next phase
3. Proceed anyway — accept coverage gaps
```

If `TEXT_MODE` is true, present as a plain-text numbered list (options already shown in the block above). Otherwise use AskUserQuestion to present the options.

### Step 13a — uncovered decisions

**If `passed` is false:** Display the handler's `message` block. It already
names each uncovered decision (`D-NN | category | text`) and tells the user
what to do — cite the id in a relevant plan's `must_haves` / `truths`, or
move the decision under `### Claude's Discretion` / tag it `[informational]`
if it should not be tracked. Then offer:

```text
Options:
1. Re-plan to cover missing decisions (recommended)
2. Edit CONTEXT.md to mark dropped decisions as [informational] / Discretion
3. Proceed anyway — accept the coverage gap
```

If `TEXT_MODE` is true, present as a plain-text numbered list. Otherwise use
AskUserQuestion. Selecting "Proceed anyway" continues to step 13b but
records the override in STATE.md so verify-phase can re-surface it.

**Why this gate blocks:** failing here is cheap. The plans are the contract
between discuss-phase and execute-phase; if a decision isn't visible in any
plan, no executor will implement it. Catching that now beats discovering it
after thousands of dollars of execution.

