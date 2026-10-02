# plan-phase — pre-plan gates (steps 4.6, 5.5–5.65 and 7.5–7.9)

Lazy block of `workflows/plan-phase.md`. Part 0 is read from §4.6 only when the `drift` gate is active (run it and return to §5). Read the rest on arrival at step 5.5 when `nyquist_validation_enabled` is true or `PLAN_PRE_HOOKS_JSON.activeHooks` lists any hook besides `research`; a project with no plan:pre capability and no Nyquist skips the whole file. Run the first half (5.5, 5.55, 5.6, 5.65) at that point and the second half (7.5, 7.8, 7.9) right after step 7 — the core says where. When `activeHooks` has a `ui` entry, Read `~/.claude/gad-core/references/ui-brand.md` before running 5.6 — it is the brand/visual contract the UI-SPEC gate refers to; without a UI hook it is never opened.

## Part 0 — before research reuse is decided (step 4.6)

## 4.6. Context Drift Pre-Check (drift plan:pre gate)

Runs only when `PLAN_PRE_HOOKS_JSON.activeHooks` has the `drift` gate with `check.query == "verify.context-drift"` (`workflow.context_drift_precheck` on) — before either the research-reuse decision (§5.1) or the pattern-mapper reuse decision (§7.8) can fire; both would otherwise silently reuse a stale artifact with zero signal.

```bash
DRIFT=$(gad_run verify context-drift "${PHASE}" 2>/dev/null || echo '{"skipped":true}')
```

If `skipped` is true, continue silently to §5 — nothing to compare (no CONTEXT.md yet, no
upstream artifacts yet, or the phase directory did not resolve).

If `stale_artifacts` is a non-empty array, print `message` verbatim (it names each stale
artifact and the command to regenerate it). Then:

- If `DRIFT.block` is `false` (the default, `workflow.context_drift_action: warn`): continue to
  §5 — this is advisory only, exactly like the codebase-drift pre-check at §5.65.
- If `DRIFT.block` is `true` (opt-in `workflow.context_drift_action: block`): **exit the
  plan-phase workflow** rather than continuing. Do not spawn the researcher, the planner, or the
  pattern mapper against a premise the user has not yet reconciled. Point the user at re-running
  `/gad-plan-phase {X}` once the named artifacts are regenerated, or at disabling the check with
  `gad_run query config-set workflow.context_drift_action warn` if the flag was a false positive.

If `stale_artifacts` is empty, continue silently to §5 — nothing to report.

## Part A — before existing plans are checked (steps 5.5–5.65)

## 5.5. Create Validation Strategy

Skip if `nyquist_validation_enabled` is false OR `research_enabled` is false.

If `research_enabled` is false and `nyquist_validation_enabled` is true: warn "Nyquist validation enabled but research disabled — VALIDATION.md cannot be created without RESEARCH.md. Plans will lack validation requirements (Dimension 8)." Continue to step 6.

**But Nyquist is not applicable for this run** when all of the following are true:
- `research_enabled` is false
- `has_research` is false
- no `--research` flag was provided

In that case: **skip validation-strategy creation entirely**. Do **not** expect `RESEARCH.md` or `VALIDATION.md` for this run, and continue to Step 6.

```bash
grep -l "## Validation Architecture" "${PHASE_DIR}"/*-RESEARCH.md 2>/dev/null || true
```

**If found:**
1. Read template: `$HOME/.claude/gad-core/templates/VALIDATION.md`
2. Write to `${PHASE_DIR}/${PADDED_PHASE}-VALIDATION.md` (use Write tool)
3. Fill frontmatter: `{N}` → phase number, `{phase-slug}` → slug, `{date}` → current date
4. Verify:
```bash
test -f "${PHASE_DIR}/${PADDED_PHASE}-VALIDATION.md" && echo "VALIDATION_CREATED=true" || echo "VALIDATION_CREATED=false"
```
5. If `VALIDATION_CREATED=false`: STOP — do not proceed to Step 6
6. If `commit_docs`: `commit "docs(phase-${PHASE}): add validation strategy"`

**If not found:** Warn and continue — plans may fail Dimension 8.

## 5.55. Security Threat Model Gate

> Capability-driven dispatch. Resolves active `plan:pre` hooks via the capability registry; the security hook's `when` condition is evaluated by the registry.

```bash
PLAN_PRE_HOOKS_JSON=$(gad_run loop render-hooks plan:pre --raw)
```

**Contribution dispatch (#3606):** inject every `kind == "contribution"` fragment from `PLAN_PRE_HOOKS_JSON` per @gad-core/references/loop-hook-dispatch.md, in array order, into the role each entry's `into` names — planner-targeted ones land in the prompt block below, orchestrator-targeted ones in your working context. The security specialization below is one such contribution, not a replacement for the generic dispatch.

Resolve active contribution hooks from `PLAN_PRE_HOOKS_JSON` where `kind == "contribution"` and `capId == "security"`.

**Threat-ID uniqueness (#4683 — applies whether or not the security hook is active):** if the init payload's `threat_id_duplicate_count` is non-zero, init reports `threat_id_duplicates` — each `T-{phase}-NN` ID claimed by more than one live PLAN file in this phase. Surface the list to the planner spawn prompt in step 8 — "these threat IDs are already claimed by earlier plans in this phase: {list}; number new registers continuing after the phase's highest in-use `T-{phase}-NN`". Regardless of the count, include the numbering rule in the planner spawn prompt whenever this phase already has PLAN files: threat IDs are unique within a phase, and new registers continue after the highest in-use `T-{phase}-NN` — the count only reports an EXISTING collision, it cannot prevent the first one. The reserved `T-{phase}-SC` row is never listed. execute-phase hard-stops on a non-empty list regardless of what happened here.

**If no active security contribution hook exists:** Skip to step 5.6.

If an active security contribution hook exists, read `SECURITY_ASVS` from the hook's `configValues.security_asvs_level` (default: `1`) and `SECURITY_BLOCK` from `configValues.security_block_on` (default: `"high"`). These values are resolved by the capability registry from user config using the same four-level precedence as hook activation — no inline `config-get` is needed.

Display banner:

```
### GAD ► SECURITY THREAT MODEL REQUIRED (ASVS L{SECURITY_ASVS})

Each PLAN.md must include a <threat_model> block.
Block on: {SECURITY_BLOCK} severity threats.
Opt out: set security_enforcement: false in .planning/config.json
```

Continue to step 5.6. Security config is passed to the planner in step 8.

## 5.6. Plan:Pre Capability Dispatch and UI Design Contract Gate

> Capability-driven dispatch. Resolves active `plan:pre` hooks via the capability registry; each hook's `when` condition is evaluated by the registry — no inline config-get needed. This section handles skill-based planning preflights such as `ai-integration`, agent-backed hooks through `ref.agent`, and the UI gate whose deterministic check comes from `check.query`.
>
> **Config semantics (cutover fix):** `workflow.ui_phase` gates UI-SPEC *generation* (step); `workflow.ui_safety_gate` gates the *planning block* (gate). Both-on = identical to OLD §5.6. Intended change: `{ui_phase:true, ui_safety_gate:false}` now auto-generates in pipelines but does NOT block manual planning (each key controls exactly what its description says).

```bash
PLAN_PRE_HOOKS_JSON=${PLAN_PRE_HOOKS_JSON:-$(gad_run loop render-hooks plan:pre --raw)}
HOOKS_JSON="$PLAN_PRE_HOOKS_JSON"
```

Read the `activeHooks` array directly from `PLAN_PRE_HOOKS_JSON` / `HOOKS_JSON` (in-context — do NOT invoke a shell pipeline).

**Branch 1 — all plan:pre hooks inactive (`activeHooks` is empty or absent):** Skip to step 6.

**Generic step hook dispatch contract:** For each active entry where `kind == "step"`:
- If `ref.skill` is set, dispatch with `Skill(skill="gad-${ref.skill}", args="${PHASE} --auto ${GAD_WS}")` when pipeline mode allows auto-chaining. Prepend `gad-` to `ref.skill` — `ui-phase` → `gad-ui-phase`.
- If `ref.agent` is set, dispatch with `Agent(prompt=filled_hook_fragment, subagent_type=ref.agent, model="{researcher_model}")`. Use the hook's `fragment.inline` as the prompt body and fill phase fields before spawning.
- The `research` hook is handled by §5.1's research decision. The `pattern-mapper` hook is handled by §7.8 after `RESEARCH_PATH` is known. Future plan:pre agent hooks use the same `ref.agent` fragment contract.

**AI integration capability:** If the active `ai-integration` step hook is present, `AI_SPEC_PATH` is empty, and the phase goal contains AI keywords (`agent`, `llm`, `rag`, `chatbot`, `embedding`, `langchain`, `llamaindex`, `crewai`, `langgraph`, `openai`, `anthropic`, `vector`, `llm eval`), then:
- In pipeline / `--auto` mode, invoke the hook's `ref.skill` via `Skill(skill="gad-${ref.skill}", args="${PHASE} --auto ${GAD_WS}")`.
- In manual mode, display the existing non-blocking `/gad-ai-integration-phase {N}` recommendation and let the user continue planning without AI-SPEC or stop to run the capability workflow first.

Run the UI deterministic gate whenever **any** `plan:pre` UI hook is active — including the step-only case (`workflow.ui_safety_gate` off). (`check.query` = `"ui.plan-gate"`; router normalizes dots→hyphens.)

```bash
GATE=$(gad_run check ui-plan-gate "${PHASE}" --raw)
```

Read `frontend`, `hasUiSpec`, and `block` from `GATE`.

**Branch 2 — no frontend indicators (`frontend` is `false`):** Skip silently to step 6.

**Branch 3 — UI-SPEC already exists (`hasUiSpec` is `true`):**

```bash
UI_SPEC_FILE=$(ls "${PHASE_DIR}"/*-UI-SPEC.md 2>/dev/null | head -1)
UI_SPEC_PATH="${UI_SPEC_FILE}"
```

Display: `Using UI design contract: ${UI_SPEC_PATH}`. Continue to step 6.

**Branch 4 — `--skip-ui` in `$ARGUMENTS`:** Skip silently to step 6.

**Branches 5 & 6 — frontend detected, UI-SPEC missing, no `--skip-ui`.**

Read the ephemeral auto-chain flag:

```bash
AUTO_CHAIN=$(gad_run query check auto-mode --pick auto_chain_active 2>/dev/null)
AUTO_CHAIN="${AUTO_CHAIN:-false}"
```

**Branch 5 — `AUTO_CHAIN` is `true` (pipeline / `--auto`):** Fire each active UI **step** hook — runs independently of whether a gate is active (covers `{ui_phase:true,ui_safety_gate:false}`). For each entry in `activeHooks` (in array order) where `kind == "step"` and `ref.skill` is set:

```
Skill(skill="gad-${ref.skill}", args="${PHASE} --auto ${GAD_WS}")
```

After all UI step hooks return, re-read:

```bash
UI_SPEC_FILE=$(ls "${PHASE_DIR}"/*-UI-SPEC.md 2>/dev/null | head -1)
UI_SPEC_PATH="${UI_SPEC_FILE}"
```

Continue to step 6.

**Branch 6 — `AUTO_CHAIN` is `false` (manual): generic gate handling.** For each entry in `activeHooks` where `kind == "gate"` and `blocking` is `true`: if `block:true` (from `GATE`), output the block below and **EXIT the plan-phase workflow**. If no active blocking gate (e.g. `workflow.ui_safety_gate` is off), continue to step 6 — no block.

Output this markdown directly (not as a code block):

```
## ⚠ UI-SPEC.md missing for Phase {N}
▶ Recommended next step:
`/gad-ui-phase {N} ${GAD_WS}` — generate UI design contract before planning

---
Also available:
- `/gad-plan-phase {N} --skip-ui ${GAD_WS}` — plan without UI-SPEC (not recommended for frontend phases)
```

**Exit the plan-phase workflow. Do not continue.**

## 5.65. Codebase Map Freshness Pre-Check (drift plan:pre gate)

If `activeHooks` (from `PLAN_PRE_HOOKS_JSON`, §5.6) has a `kind == "gate"`, `capId == "drift"`,
`check.query == "verify.codebase-drift"` entry (`workflow.plan_drift_precheck` on), run the same check the
execute gate uses; otherwise skip to step 6:

```bash
DRIFT=$(gad_run verify codebase-drift 2>/dev/null || echo '{"skipped":true}')
```

This gate is **non-blocking** and **never blocks, never spawns** the mapper at plan time. If `skipped` or
`action_required` is false, continue silently to step 6. If `action_required` is true, print `message`
verbatim (it ends with a `/gad-map-codebase` pointer) and continue — planning proceeds whether or not the
map is refreshed first. (`drift_action: auto-remap` stays at `execute:wave:post`.)


## Part B — after the context paths are resolved (steps 7.5–7.9)

## 7.5. Verify Nyquist Artifacts

Skip if `nyquist_validation_enabled` is false OR `research_enabled` is false.

Also skip if all of the following are true:
- `research_enabled` is false
- `has_research` is false
- no `--research` flag was provided

In that no-research path, Nyquist artifacts are **not required** for this run.

```bash
VALIDATION_EXISTS=$(ls "${PHASE_DIR}"/*-VALIDATION.md 2>/dev/null | head -1)
```

If missing and Nyquist is still enabled/applicable — ask user:
1. Re-run: `/gad-plan-phase {PHASE} --research ${GAD_WS}`
2. Disable Nyquist with the exact command:
   `gad_run query config-set workflow.nyquist_validation false`
3. Continue anyway (plans fail Dimension 8)

Proceed to Step 7.8 (or Step 8 if pattern mapper is disabled) only if user selects 2 or 3.

## 7.8. Spawn gad-pattern-mapper Agent (Optional)

Pattern mapper activation is owned by the `pattern-mapper` capability's `plan:pre` step hook. Read `PLAN_PRE_HOOKS_JSON` and skip if no active step hook has `capId == "pattern-mapper"` and `ref.agent == "gad-pattern-mapper"`. Also skip if no CONTEXT.md and no RESEARCH.md exist for this phase (nothing to extract file lists from).

**If PATTERNS.md already exists** (`PATTERNS_PATH` is non-empty from step 7): Skip to step 8 (use existing).

Display banner:
```
### GAD ► PATTERN MAPPING PHASE {X}

◆ Spawning pattern mapper... (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze)
```

Use the active `pattern-mapper` hook's `fragment.inline` as the prompt template and substitute the phase fields below before spawning its declared `ref.agent`.

```markdown
{pattern_mapper_hook.fragment.inline}
```

Spawn with:
```
Agent(
  prompt=filled_pattern_mapper_hook_fragment,
  subagent_type=pattern_mapper_hook.ref.agent,
  model="{researcher_model}",
)
```

> **ORCHESTRATOR RULE — ALL RUNTIMES**: After calling Agent() above, stop working on this task immediately. Do not read more files, edit code, or run tests related to this task while the subagent is active. Wait for the subagent to return its result. This prevents duplicate work, conflicting edits, and wasted context. Only resume when the subagent result is available. Never call `ScheduleWakeup` or any host wake/sleep-scheduling tool to literalize this wait (#4079) — the Agent() call returns on its own; a partial-args wake call surfaces a red validation error.

**Handle return:**
- **`## PATTERN MAPPING COMPLETE`:** Update `PATTERNS_PATH` to the created file path, continue to step 8.
- **Any error or empty return:** Log warning, continue to step 8 without patterns (non-blocking).

After pattern mapper completes, update the path variable:
```bash
PATTERNS_PATH="${PHASE_DIR}/${PADDED_PHASE}-PATTERNS.md"
```

## 7.9. Regenerate API-SURFACE.md (intel gate)

> Capability-driven dispatch. Resolves active `plan:pre` step hooks via the capability registry; the intel hook's `when: intel.enabled` condition is evaluated by the registry — no inline config-get needed.

Read the active intel step hook from `PLAN_PRE_HOOKS_JSON` where `kind == "step"` and `capId == "intel"`.

**If no active intel step hook exists:** `API_SURFACE_PATH` stays empty; skip to step 8. The step-8 planner entry for API Surface is omitted when `API_SURFACE_PATH` is empty.

**If an active intel step hook exists:**
```bash
gad_run intel api-surface
API_SURFACE_PATH="$(dirname "$STATE_PATH")/intel/API-SURFACE.md"
# #gad-46p: an empty index is a silent lie — the planner gets a HINT pointing at a file
# with no symbols and plans against nothing. Fail loud instead (F24.5, 2026-09-09).
# The ruler is the renderer's own shape (gad-core/bin/lib/intel.cjs): every symbol is a
# `## \`name\`` section, and an empty api-map.json yields only the title plus the
# `> **Incomplete:** api-map.json has no entries` banner. So "has symbols" == "has a `## `
# heading" — counting `-`/`*`/`#` lines would always find the `# API Surface` title and
# never fire.
API_SURFACE_SYMBOLS=$(grep -c '^## ' "$API_SURFACE_PATH" 2>/dev/null || true)
if [ ! -s "$API_SURFACE_PATH" ] || [ "${API_SURFACE_SYMBOLS:-0}" -eq 0 ]; then
  echo "ERROR: intel api-surface produced an empty index at ${API_SURFACE_PATH} — the planner HINT would be false. Fix the intel capability or disable it in config (workflow: set the intel capability to disabled), then re-run." >&2
  API_SURFACE_PATH=""
  exit 1
fi
echo "✓ API surface regenerated: ${API_SURFACE_PATH}"  # injected into step 8 as HINT
```

Continue to step 8.

