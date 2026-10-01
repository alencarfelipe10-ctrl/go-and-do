# plan-phase — plan checker, revision loop and bounce (steps 10, 12, 12.5)

Lazy block of `workflows/plan-phase.md`. Read it on arrival at step 10 — only when the checker runs (`plan_checker_enabled` true and no `--skip-verify`); a `--skip-verify` run goes from step 9 straight to 13 and never opens this file. It holds the checker spawn with its two deterministic probes (10), the revision loop (12) and the optional bounce (12.5); step 11 (handling the checker return) stays in the core. Before running step 12 the first time, Read `~/.claude/gad-core/references/revision-loop.md` (the check-revise-escalate pattern the loop follows), `~/.claude/gad-core/references/gate-prompts.md` (the option wording of the escalation prompts) and `~/.claude/gad-core/references/gates.md` (which gate type each stop is) — they only matter once issues come back, which is why they are not read at workflow start.

## 10. Spawn gad-plan-checker Agent

Display banner:
```
### GAD ► VERIFYING PLANS

◆ Spawning plan checker... (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze)
```

**Verify-command probes (#2401, #3172).** Before spawning, run both deterministic probes and
hand their JSON to the checker. The first resolves each `<automated>` command's target; the
second reports which runnable commands carry a `<fails_when>` statement naming their failure
signal. Neither executes command text, and neither prescribes a replacement — the first reports
which `<automated>` targets resolve, which do not, and which it refused to guess at; the second
reports which commands state a failure signal and never authors one. Handing both over is what
stops the checker hand-reasoning the filesystem or the plans.

```bash
VERIFY_PATHS=$(gad_run check verify-command-paths "${PHASE}" --raw)
FAILING_DIRECTIONS=$(gad_run check verify-failure-directions "${PHASE}" --raw)
# Fork gen5-patches (P14): the two probes grow with the number of <automated> commands (179 KB on an
# 11-plan phase), so they are always written to a file and only pasted inline when small.
# go-and-do v2.10.1 (57): fase no formato novo (`.gad/FORMATO`) guarda a trilha em `.gad/plan-checker/`;
# detecção inline — o fork não depende da lib da skill.
if [ -f "${PHASE_DIR}/.gad/FORMATO" ]; then PROBES_DIR="${PHASE_DIR}/.gad/plan-checker"; else PROBES_DIR="${PHASE_DIR}/.plan-checker"; fi
mkdir -p "$PROBES_DIR"
PROBES_FILE="$PROBES_DIR/probes.json"
jq -n --argjson vp "${VERIFY_PATHS:-null}" --argjson fd "${FAILING_DIRECTIONS:-null}" \
  '{verify_command_paths: $vp, verify_failure_directions: $fd}' > "$PROBES_FILE"
PROBES_BYTES=$(wc -c < "$PROBES_FILE")
if [ "$PROBES_BYTES" -gt 8192 ]; then
  VERIFY_PATHS="@file:${PROBES_FILE}#verify_command_paths"
  FAILING_DIRECTIONS="@file:${PROBES_FILE}#verify_failure_directions"
fi
# Fork gen5-patches (plano 4 / B4): terceira sonda — lastro das arestas depends_on, razão ondas/planos,
# largura máxima e arquivos-hub, pelo mesmo script do §13a-bis. Mesma regra de tamanho.
NOSSO="$(dirname "$(readlink -f "$GAD_TOOLS")")/nosso"; [ -d "$NOSSO" ] || NOSSO="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/nosso"
gad_run query phase-plan-index "${PHASE}" --raw > "$PROBES_DIR/plan-index.json"
LASTRO_FILE="$PROBES_DIR/lastro.json"
python3 "$NOSSO/plan-gate.py" "${PHASE_DIR}" "$PROBES_DIR/plan-index.json" --probe-lastro > "$LASTRO_FILE" 2>/dev/null || echo '{"arestas":[],"erro":"sonda de lastro não rodou"}' > "$LASTRO_FILE"
LASTRO=$(cat "$LASTRO_FILE"); [ "$(wc -c < "$LASTRO_FILE")" -le 8192 ] || LASTRO="@file:${LASTRO_FILE}"
# Fork gen5-patches (tarefa 48/h, 23/09/2026): quarta sonda — varredura par a par por onda,
# direto dos *-PLAN.md (não depende do phase-plan-index acima). Roda aqui porque este passo
# roda de novo a cada correção (step 12 respawna o checker chamando este mesmo step 10) —
# "antes do 1º checker e após cada correção" cai de graça. Nunca bloqueia: é sino, não gate.
PARES_FILE="$PROBES_DIR/pares.json"
python3 "$NOSSO/varre-pares.py" "${PHASE_DIR}" --no-out > "$PARES_FILE" 2>/dev/null || echo '{"pares":[],"erro":"varredura par a par não rodou"}' > "$PARES_FILE"
PARES=$(cat "$PARES_FILE"); [ "$(wc -c < "$PARES_FILE")" -le 8192 ] || PARES="@file:${PARES_FILE}"
```

`{VERIFY_PATHS}` and `{FAILING_DIRECTIONS}` below receive either the JSON itself (file ≤ 8 KB) or the
`@file:<path>#<key>` line (file larger than that); the checker prompt says what to do in each case.
`{LASTRO}` receives the ballast probe JSON, or `@file:<path>` above 8 KB. `{PARES}` receives the
pairwise conflict probe JSON, or `@file:<path>` above 8 KB.

Checker prompt:

```markdown
<verification_context>
**Phase:** {phase_number}
**Phase Goal:** {goal from ROADMAP}
**Mode:** {standard | gap_closure | reviews}

<required_reading>
- {PHASE_DIR}/*-PLAN.md (Plans to verify)
- {roadmap_path} (Roadmap)
- {requirements_path} (Requirements)
- {context_path} (USER DECISIONS from /gad-discuss-phase)
- {research_path} (Technical Research — includes Validation Architecture)
- {reviews_path} (Cross-AI Review Feedback - if --reviews; verify actionable findings are represented in PLAN.md)
</required_reading>

${AGENT_SKILLS_CHECKER}

<verify_command_path_probe>
**Deterministic verify-command path probe (#2401)** — already run; do NOT re-derive these
verdicts by reading the filesystem yourself. The block below is either the probe JSON or a single
line `@file:<path>#verify_command_paths` — in that case `Read` the file and use that key's value
(the file is JSON with the two probes as top-level keys; it lives in the phase directory). Act on
`severity` per the "Verify Command Path Resolvability" dimension: `blocker` → BLOCKER, `warning` →
WARNING, `none` → silent. `status: pending_creation` is not a finding. A non-empty `readError`
means the probe could not look — a WARNING, not a pass. Report the failing target verbatim; never
prescribe a replacement path.

```json
{VERIFY_PATHS}
```
</verify_command_path_probe>

<failing_direction_probe>
**Deterministic failing-direction probe (#3172)** — already run; do NOT re-derive these verdicts
by re-reading the plans yourself. Same delivery as above: JSON inline, or one line
`@file:<path>#verify_failure_directions` to `Read` and pick that key. Act on `severity` per
check 8f: `blocker` → BLOCKER, `warning` → WARNING, `none` → silent. `status: sentinel` is a Wave-0
`MISSING` placeholder and is not a finding. A non-empty `readError` means the probe could not look —
a WARNING, not a pass. Quote the command that has no stated failure mode; never author the
statement for the planner.

```json
{FAILING_DIRECTIONS}
```
</failing_direction_probe>

<dependency_ballast_probe>
**Deterministic dependency-ballast probe (fork gen5-patches, plan 4 / B4)** — already run; do NOT
re-derive these verdicts by reading the plans yourself. Same delivery: JSON inline, or one line
`@file:<path>` to `Read`. Each `arestas[]` entry says whether the dependent plan names something the
prerequisite creates (`lastro: true` with `evidencia`, or `false`). Act per Dimension 3c: an edge with
`lastro: false` is a WARNING `dependencia_sem_lastro`, never a blocker — the fix is "remove the edge or
name what you read from the prerequisite". `razao` (waves/plans) above 0.7 promotes "could split for
better parallelization" from info to warning; `hubs[]` lists files in 3+ plans (report once each, as
info, with the foundation-plan hint). An `erro` key means the probe could not look — say so, do not guess.

```json
{LASTRO}
```
</dependency_ballast_probe>

<pair_conflict_probe>
**Deterministic pairwise file probe (fork gen5-patches, tarefa 48/h, 23/09/2026)** — already run;
do NOT re-derive these verdicts by reading the plans yourself. Same delivery: JSON inline, or one
line `@file:<path>` to `Read`. Each `pares[]` entry names two same-wave plans that touch the same
file: `tipo: "modifica-modifica"` (both plans modify/delete it — the same fact §13a-bis's
`SOBREPOSICAO-NA-ONDA` will fail on later; flagging it here lets you catch it before that gate
bounces the phase) or `tipo: "<id>-modifica-<id>-le"` (one plan modifies the file, the other reads
it via `<read_first>` or a bare citation in its body — never a blocker on its own, a WARNING
`par_conflitante`: the reading plan may be assuming a state the modifying plan hasn't written yet
in execution order). `planos_sem_wave[]` lists plans the probe could not place (no `wave:` in
frontmatter) — report them as info, do not guess their wave. An `erro` key means the probe could
not look — say so, do not guess.

```json
{PARES}
```
</pair_conflict_probe>

<review_incorporation_verification>
**If Mode is reviews:** Read REVIEWS.md and verify each current actionable review finding is visible in executable PLAN.md content or explicitly deferred/rejected in the relevant PLAN.md. A finding remains actionable if it requires a concrete plan task, `<action>`, `<acceptance_criteria>`, `<verify>`, `must_haves`, threat-model item, stale-path correction, or execution contract change before /gad-execute-phase runs.

If an actionable finding remains only in REVIEWS.md and would be invisible to /gad-execute-phase, return `## ISSUES FOUND`. Use WARNING by default; use BLOCKER when the missing incorporation can prevent the phase goal, create unsafe execution, or invalidate verification.
</review_incorporation_verification>

**Phase requirement IDs (MUST ALL be covered):** {phase_req_ids}

**Project instructions:** Read ./CLAUDE.md or ./.claude/CLAUDE.md if either exists — verify plans honor project guidelines
**Project skills:** Check .claude/skills/ or .agents/skills/ directory (if either exists) — verify plans account for project skill rules
</verification_context>

<expected_output>
- ## VERIFICATION PASSED — all checks pass
- ## ISSUES FOUND — structured issue list
</expected_output>
```

```
Agent(
  prompt=checker_prompt,
  subagent_type="gad-plan-checker",
  model="{checker_model}",
  description="Verify Phase {phase} plans",
  run_in_background=true
)
```

**ORCHESTRATOR RULE — ALL RUNTIMES:** `TS=$(date +%s)`; repeat `CHECKER_STALL_RESULT=$(gad_stall_watch "$TS" "{outputFile}" "${PHASE_DIR}"'/*-PLAN.md' "## VERIFICATION PASSED" "## ISSUES FOUND")` while waiting/active.

### Step 11 — thinking partner for architectural tradeoffs (conditional)

**Thinking partner for architectural tradeoffs (conditional):**
If `features.thinking_partner` is enabled, scan the checker's issues for architectural tradeoff keywords
("architecture", "approach", "strategy", "pattern", "vs", "alternative"). If found:

```
The plan-checker flagged an architectural decision point:
{issue description}

Brief analysis:
- Option A: {approach_from_plan} — {pros/cons}
- Option B: {alternative_approach} — {pros/cons}
- Recommendation: {choice} aligned with {phase_goal}

Apply this to the revision? [Yes] / [No, I'll decide]
```

If yes: include the recommendation in the revision prompt. If no: proceed to revision loop as normal.
If thinking_partner disabled: skip this block entirely.

## 12. Revision Loop (Max 3 Iterations)

Track `iteration_count` (starts at 1 after initial plan + check).
Track `prev_issue_count` (initialized to `Infinity` before the loop begins).
Track `stall_reentry_count` (starts at 0; incremented each time "Adjust approach" re-enters step 8).

**If iteration_count < 3:**

Parse issue count from checker return: count BLOCKER + WARNING entries in the YAML issues block (structured output from gad-plan-checker); an entry whose severity is missing or unrecognized counts as a BLOCKER (fail closed). If the checker's return contains no YAML issues block (i.e., the plan was approved with no issues), treat `issue_count` as 0 and skip the stall check — the plan passed. Proceed to step 13 — likewise when every entry in the block is explicitly INFO (display them as advisories). Advisory format: `ℹ advisory — {dimension}: {description}` per INFO entry, listed once before the step-13 output.

Display (only when entering the revision loop — skip if the paragraph above already proceeded to step 13): `Revision iteration {N}/3 -- {blocker_count} blockers, {warning_count} warnings`

**Stall detection:** If `issue_count >= prev_issue_count`:
  Display: `Revision loop stalled — issue count not decreasing ({issue_count} issues remain after {N} iterations)`

  **If `stall_reentry_count < 2`:**
    Ask user:
      Question: "Issues remain after {N} revision attempts with no progress. Proceed with current output?"
      Options: "Proceed anyway" | "Adjust approach"
    If "Proceed anyway": accept current plans and continue to step 13.
    If "Adjust approach": increment `stall_reentry_count`, open freeform discussion, then re-enter step 8 (full replanning). Note: re-entry resets `iteration_count` and `prev_issue_count` but `stall_reentry_count` persists across re-entries and is capped at 2.

  **If `stall_reentry_count >= 2`:**
    Display: `Stall persists after 2 re-planning attempts. The following issues could not be resolved automatically:`
    List the remaining issues from the checker.
    Suggest: "Consider resolving these issues manually or running `/gad-debug` to investigate root causes."
    Options: "Proceed anyway" | "Abandon"
    If "Proceed anyway": accept current plans and continue to step 13.
    If "Abandon": stop workflow.

Set `prev_issue_count = issue_count`.

Revision prompt:

```markdown
<revision_context>
**Phase:** {phase_number}
**Mode:** revision

<required_reading>
- {PHASE_DIR}/*-PLAN.md (Existing plans)
- {context_path} (USER DECISIONS from /gad-discuss-phase)
</required_reading>

${AGENT_SKILLS_PLANNER}

**Checker issues:** {structured_issues_from_checker}
</revision_context>

<instructions>
`required_property` + evidence + severity BIND. `fix_hint` is ONE non-binding example route: a
smaller or different mechanism reaching the same property resolves it — say which. Re-check CONTEXT.md's locked decisions, capability guidance, and existing plan constraints
BEFORE editing; if a hint would contradict one, or the
property is unreachable without breaking one, return `## REVISION_CONFLICT` with the conflict and
the alternatives rather than applying or working around it. Full contract:
`gad-core/references/planner-revision.md`.

Do NOT replan from scratch unless fundamental. Return what changed.
</instructions>
```

```
Agent(
  prompt=revision_prompt,
  subagent_type="gad-planner",
  model="{planner_model}",
  description="Revise Phase {phase} plans",
  run_in_background=true
)
```

**ORCHESTRATOR RULE — ALL RUNTIMES:** (7.99; no marker, mtimes only) `TS=$(date +%s)`; repeat `PLANNER_STALL_RESULT=$(gad_stall_watch "$TS" "{outputFile}" "${PHASE_DIR}"'/*-PLAN.md' "## REVISION_CONFLICT")` while waiting/active — `stalled` -> 1) Accept as revised, to step 13, 2) Retry, 3) Stop. (Marker added: a `## REVISION_CONFLICT` return edits no PLAN.md, so the mtime-only path would report a healthy conflict return as stalled.)

**If the planner returns `## REVISION_CONFLICT`:** follow the shared Conflict Return protocol in
`gad-core/references/revision-loop.md`, with this workflow's bindings:

```bash
if ! CONVERGENCE_ENABLED=$(gad_run query config-get workflow.plan_review_convergence --raw 2>/dev/null); then
  echo "BLOCKED: cannot read workflow.plan_review_convergence." >&2
  exit 1
fi
REVIEWS_FILE="${REVIEWS_PATH}"
if [ "${CONVERGENCE_ENABLED}" = "true" ] && [ -n "${REVIEWS_FILE}" ] && [ ! -f "${REVIEWS_FILE}" ]; then
  echo "BLOCKED: cannot persist plan-revision conflict -- REVIEWS_PATH not a regular file: ${REVIEWS_FILE}" >&2
  exit 1
fi
```

- Counter not spent: `iteration_count`.
- Record channel: `$REVIEWS_FILE`'s `## Plan-Revision Conflicts` section. plan-phase wrote the
  line, so plan-phase closes it.
- After re-spawning, return to this step, not the checker.
- Escalates via the iteration cap on repeated `required_property`, and on the THIRD conflict
  return of this loop whatever property it names.
- Sanitize-then-insert is real shell; fields reach `awk` via `ENVIRON`, never `-v` (decodes
  literal `\n` as a real newline). Export the row's
  `CONFLICT_DIMENSION/_PLAN/_PROPERTY/_CONSTRAINT/_ALTERNATIVES`, then run:

```bash
if [ "${CONVERGENCE_ENABLED}" = "true" ] && [ -n "${REVIEWS_FILE}" ]; then
  san() { printf '%s' "$1" | tr '\r\n\t' '   ' | sed -E 's/^[[:space:]]*[#|`-]+[[:space:]]*//'; }
  LINE="- [ ] REVISION_CONFLICT $(san "${CONFLICT_DIMENSION}")/$(san "${CONFLICT_PLAN}") — required_property: $(san "${CONFLICT_PROPERTY}") | conflicts with: $(san "${CONFLICT_CONSTRAINT}") | alternatives: $(san "${CONFLICT_ALTERNATIVES}")"
  END='<!-- gad:plan-revision-conflicts:end -->'
  TMP=$(mktemp "${REVIEWS_FILE}.XXXXXX")
  if ! LINE="$LINE" END="$END" awk '
    { cur = $0; sub(/\r$/, "", cur) }
    cur == ENVIRON["LINE"] { seen = 1 }
    cur == ENVIRON["END"] && !ins { if (!seen) print ENVIRON["LINE"]; ins = 1 }
    { print }
    END { if (!ins) exit 2 }
  ' "${REVIEWS_FILE}" > "${TMP}"; then
    rm -f "${TMP}"
    echo "BLOCKED: no end delimiter in '${REVIEWS_FILE}'." >&2
    exit 1
  fi
  mv "${TMP}" "${REVIEWS_FILE}"
fi
```

**Otherwise (revised plans, not `## REVISION_CONFLICT`):** if this re-spawn followed a
resolved conflict, close its record — nothing persists across fences, so export `REVIEWS_FILE`,
the same `CONFLICT_DIMENSION`/`CONFLICT_PLAN` used to open it, and `CONFLICT_RESOLUTION` (a
one-line summary). Then run:

```bash
if [ "${CONVERGENCE_ENABLED}" = "true" ] && [ -n "${REVIEWS_FILE}" ]; then
  san() { printf '%s' "$1" | tr '\r\n\t' '   ' | sed -E 's/^[[:space:]]*[#|`-]+[[:space:]]*//'; }
  PREFIX="- [ ] REVISION_CONFLICT $(san "${CONFLICT_DIMENSION}")/$(san "${CONFLICT_PLAN}") — "
  RES=$(printf '%s' "${CONFLICT_RESOLUTION}" | tr '\r\n\t' '   ')
  TMP=$(mktemp "${REVIEWS_FILE}.XXXXXX")
  if ! PREFIX="$PREFIX" RES="$RES" awk '
    { cur = $0; sub(/\r$/, "", cur) }
    !d && index(cur, ENVIRON["PREFIX"]) == 1 { print "- [x]" substr(cur, 6) " | resolved: " ENVIRON["RES"]; d = 1; next }
    { print }
    END { if (!d) exit 2 }
  ' "${REVIEWS_FILE}" > "${TMP}"; then
    rm -f "${TMP}"
    echo "BLOCKED: no open conflict '${CONFLICT_DIMENSION}/${CONFLICT_PLAN}' in '${REVIEWS_FILE}'." >&2
    exit 1
  fi
  mv "${TMP}" "${REVIEWS_FILE}"
fi
```

Spawn checker again (step 10), then increment `iteration_count`.

**If iteration_count >= 3:**

Recount BLOCKER + WARNING by the same rule — an entry whose severity is missing or unrecognized counts as a BLOCKER (fail closed). If `issue_count` is 0 — PASSED, or every entry in the block is explicitly INFO — display any advisories and proceed to step 13; the gate below fires on everything else (#3724).

Display: `Max iterations reached. {N} issues remain:` + issue list

Offer: 1) Force proceed, 2) Provide guidance and retry, 3) Abandon

## 12.5. Plan Bounce (Optional External Refinement)

**Skip if:** `--skip-bounce` flag, `--gaps` flag, or bounce is not activated.

**Activation:** Bounce runs when `--bounce` flag is present OR `workflow.plan_bounce` config is `true`. The `--skip-bounce` flag always wins (disables bounce even if config enables it). The `--gaps` flag also disables bounce (gap-closure mode should not modify plans externally).

**Prerequisites:** `workflow.plan_bounce_script` must be set to a valid script path. If bounce is activated but no script is configured, display warning and skip:
```
⚠ Plan bounce activated but no script configured.
Set workflow.plan_bounce_script to the path of your refinement script.
Skipping bounce step.
```

**Read pass count:**
```bash
BOUNCE_PASSES=$(gad_run query config-get workflow.plan_bounce_passes --raw 2>/dev/null || echo "2")
BOUNCE_SCRIPT=$(gad_run query config-get workflow.plan_bounce_script --raw 2>/dev/null || true)
```

Display banner:
```
### GAD ► BOUNCING PLANS (External Refinement)

Script: ${BOUNCE_SCRIPT}
Max passes: ${BOUNCE_PASSES}
```

**For each PLAN.md file in the phase directory:**

1. **Backup:** Copy `*-PLAN.md` to `*-PLAN.pre-bounce.md`
```bash
cp "${PLAN_FILE}" "${PLAN_FILE%.md}.pre-bounce.md"
```

2. **Invoke bounce script:**
```bash
"${BOUNCE_SCRIPT}" "${PLAN_FILE}" "${BOUNCE_PASSES}"
```

3. **Validate bounced plan — YAML frontmatter integrity:**
After the script returns, check that the bounced file still has valid YAML frontmatter (opening and closing `---` delimiters with parseable content between them). If the bounced plan breaks YAML frontmatter validation, restore the original from the pre-bounce.md backup and continue to the next plan:
```
⚠ Bounced plan ${PLAN_FILE} has broken YAML frontmatter — restoring original from pre-bounce backup.
```

4. **Handle script failure:** If the bounce script exits non-zero, restore the original plan from the pre-bounce.md backup and continue to the next plan:
```
⚠ Bounce script failed for ${PLAN_FILE} (exit code ${EXIT_CODE}) — restoring original from pre-bounce backup.
```

**After all plans are bounced:**

5. **Re-run plan checker on bounced plans:** Spawn gad-plan-checker (same as step 10) on all modified plans. If a bounced plan fails the checker, restore original from its pre-bounce.md backup:
```
⚠ Bounced plan ${PLAN_FILE} failed checker validation — restoring original from pre-bounce backup.
```

6. **Commit surviving bounced plans:** If at least one plan survived both the frontmatter validation and the checker re-run, commit the changes:
```bash
gad_run query commit "refactor(${padded_phase}): bounce plans through external refinement" --files "${PHASE_DIR}/*-PLAN.md"
```

Display summary:
```
Plan bounce complete: {survived}/{total} plans refined
```

**Clean up:** Remove all `*-PLAN.pre-bounce.md` backup files after the bounce step completes (whether plans survived or were restored).

**`--reviews` replans:** when plans exist and `--reviews` is set, the orchestrator scans `REVIEWS_PATH` for open plan-revision conflicts inside the writer-owned delimiter pair, replans with those records included, and flips the matching line to `- [x]` once the chosen resolution is applied — using the SAME close gate as step 12 above (upstream 1.13.0 step 7, #3916).
