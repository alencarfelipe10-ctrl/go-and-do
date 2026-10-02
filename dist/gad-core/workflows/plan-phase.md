<!-- gad:loop-host
step: plan
points: plan:pre, plan:post
agent-roles: researcher, planner, checker
produces: PLAN.md
consumes: CONTEXT.md
-->
<purpose>
Create executable phase prompts (PLAN.md files) for a roadmap phase with integrated research and verification. Default flow: Research (if needed) -> Plan -> Verify -> Done. Orchestrates gad-phase-researcher, gad-planner, and gad-plan-checker agents with a revision loop (max 3 iterations).
</purpose>

<required_reading>
Read all files referenced by the invoking prompt's execution_context before starting.

The `references/*.md` once loaded here are read by the block that uses them (fork gen5-patches, P14): `ui-brand.md` in `blocks/pre-plan-gates.md`; `revision-loop.md`, `gate-prompts.md`, `gates.md` in `blocks/checker.md`; `agent-contracts.md` in `blocks/contingencies.md`. Lazy blocks live in `workflows/plan-phase/blocks/` (same path resolution as this file); the core says `Read` at each border — read a block once and keep it.
</required_reading>

<available_agent_types>
Valid GAD subagent types (use exact names — do not fall back to 'general-purpose'):
- gad-phase-researcher — Researches technical approaches for a phase
- gad-pattern-mapper — Analyzes codebase for existing patterns, produces PATTERNS.md
- gad-planner — Creates detailed plans from phase scope
- gad-plan-checker — Reviews plan quality before execution
</available_agent_types>

<runtime_compatibility>
**Subagent spawning — top-level Claude Code:**
The Agent tool IS available in a top-level Claude Code session. Always spawn
gad-phase-researcher, gad-planner, and gad-plan-checker as separate Agent() calls.
Never absorb these roles inline. Role separation is required regardless of `--chain`
or `--auto` — those options suppress interactive prompts only; they NEVER authorize
collapsing plan roles into the orchestrator context.

**Backgrounded Claude Code (via manager/autonomous):**
The calling workflow (manager.md / autonomous.md) already runs plan-phase inline via
Skill() on Claude Code so that the plan-checker subagent can still spawn. plan-phase
itself does not need to detect this case.

**#1009 caveat (discuss-phase early-exit):**
The "display the command and exit" instruction near `## 4` applies only to the
discuss-phase early-exit path. It does NOT authorize inline role performance for any
plan-phase agents.

**Other runtimes:**
Do not pre-judge Agent availability by introspection. Always attempt the actual
Agent() call for gad-phase-researcher, gad-planner, and gad-plan-checker. Only
a real tool-unavailable error returned by Agent() is a reliable absence signal —
never stop based on a self-assessed "I think Agent is unavailable." If the call
fails with a tool-unavailable error, log the gap and stop — do NOT collapse
researcher/planner/checker roles inline. Independent agent contexts are required
for the plan-checker gate to be meaningful.
</runtime_compatibility>

<process>

## 0. Git Branch Invariant

**Do not create, rename, or switch git branches during plan-phase.** Branch identity is established at discuss-phase and is owned by the user's git workflow. A phase rename in ROADMAP.md is a plan-level change only — it does not mutate git branch names. If `phase_slug` in the init JSON differs from the current branch name, that is expected and correct; leave the branch unchanged.

## 1. Initialize

Load all context in one call (paths only to minimize orchestrator context):

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; _gad_id_ok() { case "$("$1" runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') return 0;; *) return 1;; esac; }; _gad_homes() { _gad_at "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; elif _gad_homes; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; _gad_id_ok gad_run && GAD_IDENTITY_STATUS=ok; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
GRAN_PARAM=""; if [[ "$ARGUMENTS" =~ (^|[[:space:]])--granularity[[:space:]]+([^[:space:]-][^[:space:]]*) ]]; then GRAN_PARAM="--granularity ${BASH_REMATCH[2]}"; fi
PRD_PARAM=""; if [[ "$ARGUMENTS" =~ (^|[[:space:]])--prd[[:space:]]+([^[:space:]-][^[:space:]]*) ]]; then PRD_PARAM="--prd ${BASH_REMATCH[2]}"; fi
INGEST_PARAM=""; if [[ "$ARGUMENTS" =~ (^|[[:space:]])--ingest[[:space:]]+([^[:space:]-][^[:space:]]*) ]]; then INGEST_PARAM="--ingest ${BASH_REMATCH[2]}"; fi
RESEARCH_PHASE_PARAM=""; if [[ "$ARGUMENTS" =~ (^|[[:space:]])--research-phase[[:space:]]+([^[:space:]-][^[:space:]]*) ]]; then RESEARCH_PHASE_PARAM="--research-phase ${BASH_REMATCH[2]}"; fi
REVIEWS_PARAM=""; if [[ "$ARGUMENTS" =~ (^|[[:space:]])--reviews([[:space:]]|$) ]]; then REVIEWS_PARAM="--reviews"; fi
CHUNKED_PARAM=""; if [[ "$ARGUMENTS" =~ (^|[[:space:]])--chunked([[:space:]]|$) ]]; then CHUNKED_PARAM="--chunked"; fi
# Project the just-completed planning mode onto the execute-phase follow-up (#3297):
# a --gaps run creates gap_closure plans, so the Next Up handoff must point at
# execute-phase's matching --gaps-only scope rather than the whole-phase run.
# Standard and --reviews runs leave GAPS_EXEC_FLAG empty → their Next Up is unchanged.
GAPS_MODE=false
if [[ "$ARGUMENTS" =~ (^|[[:space:]])--gaps([[:space:]]|$) ]]; then GAPS_MODE=true; fi
GAPS_EXEC_FLAG=""
if [ "$GAPS_MODE" = "true" ]; then GAPS_EXEC_FLAG="--gaps-only"; fi
INIT=$(gad_run query init.plan-phase "$PHASE" $GRAN_PARAM $PRD_PARAM $INGEST_PARAM $RESEARCH_PHASE_PARAM $REVIEWS_PARAM $CHUNKED_PARAM)
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
# Parse the init JSON with argv, never with `echo`. Under zsh the builtin `echo` expands
# backslash escapes, so a legitimately escaped "\n" inside a string (prior_verify_commands
# harvests multi-line <verify> commands) becomes a raw newline and JSON.parse dies with
# "Bad control character in string literal". Reproduced 2026-09-11: zsh+echo fails at the
# same column bash+echo and zsh+printf both parse. Use this helper everywhere below.
_gad_field() { node -e "const o=JSON.parse(process.argv[1]); const v=o[process.argv[2]]; process.stdout.write(v==null?'':String(v))" "$1" "$2"; }
AGENT_SKILLS_RESEARCHER=$(gad_run query agent-skills gad-phase-researcher)
AGENT_SKILLS_PLANNER=$(gad_run query agent-skills gad-planner)
AGENT_SKILLS_CHECKER=$(gad_run query agent-skills gad-plan-checker)
CONTEXT_WINDOW=$(gad_run query config-get context_window --raw 2>/dev/null || echo "200000")
MVP_MODE_CFG=$(gad_run query config-get workflow.mvp_mode --raw 2>/dev/null || echo "false")
```

When the tdd capability's `workflow.tdd_mode` is active (resolved via the plan:pre render-hooks), the planner agent is instructed to apply `type: tdd` to eligible tasks using heuristics from `gad-core/references/tdd.md`. The TDD guidance is injected via the tdd capability's contribution hook at §5.6; no inline config-get is needed.

When `CONTEXT_WINDOW >= 500000`, the planner prompt includes the 3 most recent prior-phase CONTEXT.md/SUMMARY.md files plus any phases in the current phase's `Depends on:` field (explicit deps load regardless of recency).

**#2401 — `prior_verify_commands` is NOT part of that enrichment and is never gated on `CONTEXT_WINDOW`.** It is a handful of one-line `<automated>` commands harvested from the nearest prior phase that had any; the payload is tiny and its absence at 200k is exactly what made the planner re-invent a verify command and author an unrunnable path. Surface it at every context window.

**How to read the JSON (#gad-46l).** Use `_gad_field "$INIT" <key>` (defined in the block
above — it passes the JSON through `argv`, untouched by the shell). If you need the whole
object in node, pipe it with `printf '%s' "$INIT" | node -e …` — **never `echo "$INIT"`**:
under zsh the builtin `echo` expands `\n` and corrupts any string field that contains a
newline. On 2026-09-09 that cost the F24.5 host a workaround — it wrote the 5 contributions
and 20 verify commands into a 24.9 KB side file and passed the path to the planner, against
this workflow's own "inline inputs" rule.

Parse JSON for: `researcher_model`, `planner_model`, `checker_model`, `research_enabled`, `plan_checker_enabled`, `nyquist_validation_enabled`, `commit_docs`, `text_mode`, `phase_found`, `phase_dir`, `phase_number`, `phase_name`, `phase_slug`, `padded_phase`, `has_research`, `has_context`, `has_reviews`, `has_plans`, `plan_count`, `phase_status` (#3569), `planning_exists`, `roadmap_exists`, `phase_req_ids`, `response_language`, `granularity`, `prior_verify_commands` (#2401 — array of `{phase, plan, task, command}`, possibly empty; emitted at every context window), `threat_id_duplicates` + `threat_id_duplicate_count` (#4683 — cross-plan threat-ID collisions; consumed at step 5.55).

**#2517:** omit the `model=` param from an `Agent()` call when its `researcher`/`planner`/`checker`_model is `"inherit"` or empty — passing `model=""` 404s on non-Claude runtimes; omitting inherits the orchestrator model (mirrors execute-phase).

**If `response_language` is set:** All user-facing orchestrator output — narration between tool calls, status updates, progress notes, findings, questions, prompts, and explanations — MUST be in `{response_language}`; technical terms, code, paths, and subagent prompts stay in English. Pass `response_language: {value}` into every spawned subagent prompt.

**File paths (for <required_reading> blocks):** `state_path`, `roadmap_path`, `requirements_path`, `context_path`, `research_path`, `verification_path`, `uat_path`, `reviews_path`. These are null if files don't exist.

**If `planning_exists` is false:** Error — run `/gad-new-project` first.

## 1.5. Closed-Phase Gate (#3569)

Read and execute `gad-core/workflows/plan-phase/steps/closed-phase-gate.md` — it parses `phase_status` from the init JSON, sets `FORCE_REPLAN` from `$ARGUMENTS`, and hard-stops replanning a `Complete` phase: `--reviews` on a closed phase is never overridable (exit 1), and replanning otherwise requires `--force` (else exit 1, pointing at `${verification_path}`); under `--force` it continues but emits a WARNING banner. Only `Complete` is gated — `Executed` / `Needs Review` are legitimate replans.

## 2. Parse and Normalize Arguments

Extract from $ARGUMENTS: phase number (integer or decimal like `2.1`), flags (`--research`, `--skip-research`, `--research-phase <N>`, `--gaps`, `--skip-verify`, `--skip-ui`, `--prd <filepath>`, `--ingest <path-or-glob>`, `--ingest-format <auto|nygard|madr|narrative>`, `--reviews`, `--text`, `--bounce`, `--skip-bounce`, `--chunked`, `--mvp`, `--no-tracer`, `--no-reversibility-gates`, `--tdd`, `--granularity <coarse|standard|fine>`, `--force` (override closed-phase gate, see §1.5)).

**`--research-phase <N>` — research-only mode (#3042 + #3044).** When this flag is present, parse `<N>` as the phase number (overrides any positional phase argument), set `RESEARCH_ONLY=true`, and treat the rest of this workflow as a research-dispatch only — the planner spawn (step 8), plan-checker, verification, gaps, bounce, and post-planning-gaps blocks all skip on `RESEARCH_ONLY`. Use this for cross-phase research, doc review before committing to a planning approach, and correction-without-replanning loops. Replaces the deleted `/gad-research-phase` command.

In research-only mode, two modifiers control behavior when `RESEARCH.md` already exists:

- **`--research`** — force-refresh re-research without prompting. Re-spawns the researcher unconditionally and overwrites the existing RESEARCH.md. (This is the existing `--research` flag's standard "force re-research" semantics, reused here.)
- **`--view`** — view-only: print existing `RESEARCH.md` to stdout, do **not** spawn the researcher. Sets `VIEW_ONLY=true`. Cheapest mode for the correction-without-replanning loop. If `RESEARCH.md` does not exist, error with a hint to drop `--view`.

```bash
RESEARCH_ONLY=false
VIEW_ONLY=false
if [[ "$ARGUMENTS" =~ --research-phase[[:space:]]+([0-9]+[A-Z]?(\.[0-9]+)*) ]]; then
  RESEARCH_ONLY=true
  PHASE="${BASH_REMATCH[1]}"
fi
if $RESEARCH_ONLY && [[ "$ARGUMENTS" =~ (^|[[:space:]])--view([[:space:]]|$) ]]; then
  VIEW_ONLY=true
fi
```

**`--granularity <coarse|standard|fine>` — CLI override (#703).** When present, this value is the resolved granularity passed to the planner — it wins over any per-phase `granularities.<type>` config, top-level `granularity` config, or project defaults. The init JSON always includes a `granularity` field reflecting the resolved value; read it from there. Invalid values (anything other than `coarse`, `standard`, `fine`) cause an error at the CLI boundary.

Set `TEXT_MODE=true` if `--text` is present in $ARGUMENTS OR `text_mode` from init JSON is `true`. When `TEXT_MODE` is active, replace every `AskUserQuestion` call with a plain-text numbered list and ask the user to type their choice number. This is required for Claude Code remote sessions (`/rc` mode) where TUI menus don't work through the Claude App.

**MVP_MODE resolution.** Resolve `MVP_MODE` once via the centralized `phase.mvp-mode` query verb. Precedence (first hit wins): CLI flag → ROADMAP.md `**Mode:** mvp` → `workflow.mvp_mode` config → false. The verb is the single source of truth — do not re-implement the chain.

```bash
MVP_FLAG_ARG=""
if [[ "$ARGUMENTS" =~ (^|[[:space:]])--mvp([[:space:]]|$) ]]; then MVP_FLAG_ARG="--cli-flag"; fi
if [[ "$ARGUMENTS" =~ (^|[[:space:]])--tdd([[:space:]]|$) ]]; then
  gad_run query config-set workflow.tdd_mode true 2>/dev/null || true
fi
# Tracer-first is the default; --no-tracer opts back into the legacy horizontal-layer shape.
TRACER_MODE=true
if [[ "$ARGUMENTS" =~ (^|[[:space:]])--no-tracer([[:space:]]|$) ]]; then TRACER_MODE=false; fi
REVERSIBILITY_GATES=true
if [[ "$ARGUMENTS" =~ (^|[[:space:]])--no-reversibility-gates([[:space:]]|$) ]]; then REVERSIBILITY_GATES=false; fi
```

**Baseline-discipline flags.** `TRACER_MODE` and `REVERSIBILITY_GATES` default to `true`; neither is persisted per-phase nor read from config.

Defer the `phase.mvp-mode` query until `PHASE` is finalized (after explicit argument parsing/fallback phase detection + validation). The verb returns `true|false`; full result also exposes `source` (`cli_flag` | `roadmap` | `config` | `none`) for diagnostics. Mode is **all-or-nothing per phase** (PRD decision Q1).

**Walking Skeleton gate.** When `MVP_MODE=true` AND `phase_number == "01"` AND there are zero prior phase summaries (new project), the planner runs in **Walking Skeleton mode** (per PRD decision Q2 — new projects only). Detect with:

```bash
WALKING_SKELETON=false
if [ "$MVP_MODE" = "true" ] && [ "$padded_phase" = "01" ]; then
  PRIOR_SUMMARIES=$(gad_run query phases.list --type summaries --pick count 2>/dev/null)
  if [ "$PRIOR_SUMMARIES" = "0" ]; then WALKING_SKELETON=true; fi
fi
```

When `WALKING_SKELETON=true`:
- Planner is instructed to produce `SKELETON.md` in the phase directory alongside `PLAN.md`. The template lives at `$HOME/.claude/gad-core/references/skeleton-template.md` — the planner reads it when producing SKELETON.md (lazy; not loaded on non-skeleton runs).
- The plan must scaffold project + routing + one real DB read/write + one real UI interaction + dev deployment — the thinnest possible end-to-end working slice.

**Interaction with `--prd <filepath>`.** `--mvp` and `--prd` compose. The PRD express path (Step 3.5) creates `CONTEXT.md` from the PRD file and continues to research; the Walking Skeleton gate fires independently from the conditions above. When both are active on Phase 1 of a new project, the planner receives `WALKING_SKELETON=true` and PRD-derived context simultaneously — the PRD informs *what the skeleton should prove*. No precedence is needed; the two signals are orthogonal. See [`gad-core/references/mvp-concepts.md`](../references/mvp-concepts.md) for the broader interaction map.

Extract express-path args from $ARGUMENTS: `PRD_FILE` (`--prd <filepath>`), `INGEST_PATH` (`--ingest <path-or-glob>`), and optional `INGEST_FORMAT` (`--ingest-format <auto|nygard|madr|narrative>`, default `auto`).

`--prd` and `--ingest` are mutually exclusive. If both are present, error and exit:
`Invalid arguments: cannot combine \`--prd\` with \`--ingest\`.`

**If no phase number:** Auto-detect it — `query init.plan-phase` and `query roadmap.get-phase` require an explicit number, so this is an orchestrator step. Run `gad_run query roadmap.analyze` and read `next_phase` (first phase with `disk_status` of `no_directory`, `empty`, `discussed`, or `researched`). If `next_phase` is `null`, read ROADMAP.md's `### Phase N:` headers and ask the user which phase to plan. Set `PHASE` to the result before step 1's `query init.plan-phase "$PHASE"` call.

**If `phase_found` is false:** Validate phase exists in ROADMAP.md. If valid, create the directory using `expected_phase_dir` from init (includes `project_code` prefix when set):
```bash
mkdir -p "${expected_phase_dir}"
```

Set `phase_dir="${expected_phase_dir}"` after creation.

**Existing artifacts from init:** `has_research`, `has_plans`, `plan_count`.

Set `CHUNKED_MODE` from flag or config:
```bash
CHUNKED_CFG=$(gad_run query config-get workflow.plan_chunked --raw 2>/dev/null || echo "false")
CHUNKED_MODE=false
if [[ "$ARGUMENTS" =~ --chunked ]] || [[ "$CHUNKED_CFG" == "true" ]]; then
  CHUNKED_MODE=true
fi
```

If `section_manifest` is `null` or `"reviews-prerequisite"` is in its `included` list: read and execute `gad-core/workflows/plan-phase/steps/reviews-prerequisite.md`. Otherwise skip — do not read the file.

## 3. Validate Phase

```bash
PHASE_INFO=$(gad_run query roadmap.get-phase "${PHASE}")
```

**If `found` is false:** Error with available phases. **If `found` is true:** Extract `phase_number`, `phase_name`, `goal` from JSON.

Now that `PHASE` is finalized, resolve MVP mode:
```bash
MVP_MODE=$(gad_run query phase.mvp-mode "${PHASE}" $MVP_FLAG_ARG --pick active)
```

If `section_manifest` is `null` or `"prd-express-gate"` is in its `included` list: read and execute `gad-core/workflows/plan-phase/steps/prd-express-gate.md`. Otherwise skip — do not read the file.

If `section_manifest` is `null` or `"adr-ingest-express-path"` is in its `included` list: read and execute `gad-core/workflows/plan-phase/steps/adr-ingest-express-path.md`. Otherwise skip — do not read the file.

## 4. Load CONTEXT.md

**Skip if:** PRD express path or ADR ingest express path was used (CONTEXT.md already created in step 3.5/3.6).

Check `context_path` from init JSON.

If `context_path` is not null, display: `Using phase context from: ${context_path}`

**If `context_path` is null (no CONTEXT.md exists):** **Read** `workflows/plan-phase/blocks/contingencies.md` and run its "Step 4 — no CONTEXT.md" branch (it either continues to step 5 or exits the workflow so the user runs discuss-phase first).

## 4.5. Resolve AI-SPEC Artifact

AI integration activation is owned by the `ai-integration` capability's `plan:pre` step hook. The plan-phase host only discovers existing artifacts here so the planner can consume them; it must not read the capability's config key directly.

```bash
AI_SPEC_FILE=$(ls "${PHASE_DIR}"/*-AI-SPEC.md 2>/dev/null | head -1)
AI_SPEC_PATH="${AI_SPEC_FILE}"
FRAMEWORK_LINE=""
if [ -n "$AI_SPEC_FILE" ]; then
  FRAMEWORK_LINE=$(grep "Selected Framework:" "${AI_SPEC_FILE}" | head -1)
fi
```

If `AI_SPEC_FILE` is non-empty, pass `AI_SPEC_PATH` and `FRAMEWORK_LINE` to the planner in step 8 so it can reference the AI design contract. If it is empty, the active `ai-integration` capability hook in step 5.6 handles any AI-system nudge or `/gad-ai-integration-phase` dispatch.

**4.6 (#4147):** if `PLAN_PRE_HOOKS_JSON` (lazy-init `gad_run loop render-hooks plan:pre --raw`, kept for §5.5) lists the `drift` gate `verify.context-drift`, **Read** Part 0 of `workflows/plan-phase/blocks/pre-plan-gates.md` and run it now.

## 5. Handle Research

**Skip if:** `--gaps` flag or `--skip-research` flag or `--reviews` flag.

If `section_manifest` is `null` or `"research-only-modifiers"` is in its `included` list: read and execute `gad-core/workflows/plan-phase/steps/research-only-modifiers.md`. Otherwise skip — do not read the file.

### 5.1. Standard Research Decision

**Skip if** `RESEARCH_ONLY=true` (the research-only mode in 5.0 already determined the path: spawn or exit). Without this guard, an LLM following the workflow could fall through into "use existing, skip to step 6" → planner spawn, violating the research-only contract. **CR #3045 finding: this gate makes the early-exit unreachable from any non-research-only branch.**

**If `has_research` is true (from init) AND no `--research` flag:** Use existing, skip to step 6.

**If RESEARCH.md missing OR `--research` flag:**

**If no explicit flag (`--research` or `--skip-research`) and not `--auto`:**
Ask the user whether to research, with a contextual recommendation based on the phase:
The question (TUI and `TEXT_MODE` forms) is the first part of `workflows/plan-phase/blocks/research.md` — **Read** it now; "Skip research" goes to step 6.

**If `--auto` and `research_enabled` is false:** Skip research silently (preserves automated behavior).

**If research runs:** execute the dispatch half of `blocks/research.md` (banner, `gad-phase-researcher` spawn, return handling, research-only early exit), then continue at step 5.5.

**Steps 5.5–5.65 (Nyquist strategy, security threat model, plan:pre dispatch with the UI gate, drift) are Part A of `workflows/plan-phase/blocks/pre-plan-gates.md`.** Resolve the hooks first — the block's condition depends on them:

```bash
PLAN_PRE_HOOKS_JSON=$(gad_run loop render-hooks plan:pre --raw)
```

**Read** the block when `nyquist_validation_enabled` is true or `activeHooks` lists any hook besides `research`, and run Part A now; otherwise skip to step 6. Keep `PLAN_PRE_HOOKS_JSON` — step 8 injects its planner contributions.

**Threat-ID uniqueness (#4683) holds even when the block is skipped** (full text: block §5.55): if `threat_id_duplicate_count` is non-zero, step 8's planner prompt lists `threat_id_duplicates` as already claimed; whenever `has_plans` is true it states that new `T-{phase}-NN` registers continue after the phase's highest in-use ID.

## 6. Check Existing Plans

```bash
ls "${PHASE_DIR}"/*-PLAN.md 2>/dev/null || true
```

**If exists AND no `--reviews` flag:** Offer: 1) Add more plans, 2) View existing, 3) Replan from scratch.

## 7. Use Context Paths from INIT

Extract from INIT JSON:

```bash
_gad_field() { node -e "const o=JSON.parse(process.argv[1]); const v=o[process.argv[2]]; process.stdout.write(v==null?'':String(v))" "$1" "$2"; }
STATE_PATH=$(_gad_field "$INIT" state_path)
ROADMAP_PATH=$(_gad_field "$INIT" roadmap_path)
REQUIREMENTS_PATH=$(_gad_field "$INIT" requirements_path)
RESEARCH_PATH=$(_gad_field "$INIT" research_path)
VERIFICATION_PATH=$(_gad_field "$INIT" verification_path)
UAT_PATH=$(_gad_field "$INIT" uat_path)
CONTEXT_PATH=$(_gad_field "$INIT" context_path)
REVIEWS_PATH=$(_gad_field "$INIT" reviews_path)
PATTERNS_PATH=$(_gad_field "$INIT" patterns_path)

# Detect spike/sketch findings skills (project-local)
SPIKE_FINDINGS_PATH=$(ls ./.claude/skills/spike-findings-*/SKILL.md 2>/dev/null | head -1 || true)
SKETCH_FINDINGS_PATH=$(ls ./.claude/skills/sketch-findings-*/SKILL.md 2>/dev/null | head -1 || true)

# Resolve the phase SPEC (## Edge Coverage source). UNCONDITIONAL — not in §4.5 (skipped on
# non-AI phases; gating it there starves the planner, #550). Excludes -AI/-UI/-PRE-SPEC.md.
PHASE_DIR_FOR_SPEC=$(_gad_field "$INIT" phase_dir)
SPEC_FILE=$(ls "${PHASE_DIR_FOR_SPEC}"/*-SPEC.md 2>/dev/null | grep -Ev -- '-(AI|UI|PRE)-SPEC\.md$' | head -1)   # PRE-SPEC = insumo da /go-and-do, não é o SPEC
SPEC_PATH="${SPEC_FILE}"
# Resolve the phase UI-SPEC separately (the glob above excludes -UI-SPEC.md); it carries the
# ## UI Considerations section the planner lifts by the same rule as ## Edge Coverage (#1867).
UI_SPEC_FILE=$(ls "${PHASE_DIR_FOR_SPEC}"/*-UI-SPEC.md 2>/dev/null | head -1)
UI_SPEC_PATH="${UI_SPEC_FILE}"
```

**If plans exist AND `--reviews`:** replan straight away (conflict ledger: step 12, `blocks/checker.md`).

**Steps 7.5–7.9 (Nyquist artifacts, pattern mapper, API surface) are Part B of `blocks/pre-plan-gates.md`** — run it now if the block was read at step 5.5; if it was skipped there none of these applies (`PATTERNS_PATH` stays as resolved above, `API_SURFACE_PATH` empty). Continue at step 7.95.

## 7.95. Spec-less Probe Fallback (gate)

When the SPEC did not supply `## Edge Coverage` / `## Prohibitions`, plan-phase runs the probe protocol
and authors the predicates into PLAN.md `must_haves` (ADR-857 Phase 6 — the *else branch* of the
`<downstream_consumer>` lift below). Core workflow-body substrate, not a capability rail (D-03). Runs
after `$SPEC_FILE` (Step 7), before the gad-planner spawn (Step 8).

**Read and run** the gate + edge probe in `$HOME/.claude/gad-core/references/specless-probe-fallback.md`
(§0 default-ON toggle + per-section absence via the `spec-section` helper, visibly skipping when
disabled or no requirement IDs; §A deterministic edge probe → `$COVERAGE` when `EDGE_ABSENT`; §B
prohibition recall in the planner). Pass `$COVERAGE` and `$SPECLESS_FALLBACK_DISABLED` into Step 8.

## 7.99. Bounded Stall-Detection Helpers (#2650)

Read+execute `gad-core/workflows/plan-phase/steps/stall-detection-helpers.md` (defines
`gad_stall_should_recover`/`gad_stall_watch`, and how `{outputFile}` below is bound;
independent of the teams-status guard above, AC2).

## 8. Spawn gad-planner Agent

Display banner:
```
### GAD ► PLANNING PHASE {X}

◆ Spawning planner... (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze)
```

Planner prompt:

**Read** `workflows/plan-phase/blocks/planner-prompt.md` now (`<planning_context>` … `</quality_gate>`, with the `<downstream_consumer>`, `<deep_work_rules>` and `<quality_gate>` contracts) and fill every `{placeholder}` and `${…}` expression from the init JSON and the variables of steps 1–7 — the block's header lists them. The filled text is `filled_prompt`. Division of labour the prompt fixes and this side enforces: the planner writes only `*-PLAN.md` (`wave:` is computed from `depends_on` by the index, checked in step 13a-bis; `Do not edit ROADMAP.md` — step 13c annotates it).

**If `CHUNKED_MODE` is `false` (default):** Spawn the planner as a single long-lived Agent:

**Dispatch/wait gate — `PLANNER_STALL_DETECTION_ENABLED`:**
- **`true` (default):** use `run_in_background=true` in the Agent() call shown below, then use `gad_stall_watch` as specified after it.

```text
Agent(
  prompt=filled_prompt,
  subagent_type="gad-planner",
  model="{planner_model}",
  description="Plan Phase {phase}",
  run_in_background=true
)
```

**ORCHESTRATOR RULE — ALL RUNTIMES (when `PLANNER_STALL_DETECTION_ENABLED` is `true`):** `TS=$(date +%s)`; repeat `PLANNER_STALL_RESULT=$(gad_stall_watch "$TS" "{outputFile}" "${PHASE_DIR}"'/*-PLAN.md' "## PLANNING COMPLETE" "## PHASE SPLIT RECOMMENDED" "## ⚠ Source Audit" "## CHECKPOINT REACHED" "## PLANNING INCONCLUSIVE")` while waiting/active — `marker_received` -> step 9; `stalled` -> 9a.

- **`false`:** issue the same Agent() call but omit `run_in_background`; await its ordinary runtime-native completion and pass the real returned result to step 9. Skip `gad_stall_watch` entirely. This is not fire-and-forget; empty, truncated, or unrecognized returns still use step 9a.

**If `CHUNKED_MODE` is `true`:** Skip the Agent() call above — proceed to step 8.5 instead.

If `section_manifest` is `null` or `"chunked-planning-mode"` is in its `included` list: read and execute `gad-core/workflows/plan-phase/steps/chunked-planning-mode.md`. Otherwise skip — do not read the file.

## 9. Handle Planner Return

- **`## PLANNING COMPLETE`:** Display plan count. If `--skip-verify` or `plan_checker_enabled` is false (from init): skip to step 13. Otherwise: step 10.
- **`## PHASE SPLIT RECOMMENDED`:** The planner determined the phase exceeds the context budget for full-fidelity implementation of all source items. Handle in step 9b.
- **`## ⚠ Source Audit: Unplanned Items Found`:** The planner's multi-source coverage audit found items from REQUIREMENTS.md, RESEARCH.md, ROADMAP goal, or CONTEXT.md decisions that are not covered by any plan. Handle in step 9c.
- **`## CHECKPOINT REACHED`:** Present to user, get response, spawn continuation (step 12)
- **`## PLANNING INCONCLUSIVE`:** Show attempts, offer: Add context / Retry / Manual
- **Empty / truncated / no recognized marker:** → Filesystem fallback (step 9a).

Steps 9a–9c are in `workflows/plan-phase/blocks/contingencies.md` — **Read** it only when the return is one of those cases.

**Steps 10 (checker spawn with its two probes), 12 (revision loop) and 12.5 (bounce) are in `workflows/plan-phase/blocks/checker.md`.** **Read** it on arrival at step 10 — never on `--skip-verify` or `plan_checker_enabled` false, which go straight to step 13. It fills `{VERIFY_PATHS}` and `{FAILING_DIRECTIONS}` inline while `${PHASE_DIR}/.plan-checker/probes.json` is at most 8 KB, by path above that. After each spawn come back to step 11.

## 11. Handle Checker Return

- **`marker_received` + `## VERIFICATION PASSED`:** Display confirmation, proceed to step 13.
- **`marker_received` + `## ISSUES FOUND`:** Display issues, check iteration count, proceed to step 12.
- **`stalled`:** Automatically surface 11a's recovery choice (Accept verification / Retry checker / Stop) — no manual interrupt needed.
- **Empty / truncated / no recognized marker:** → Filesystem fallback (step 11a).

Step 11a (checker filesystem fallback) is in `workflows/plan-phase/blocks/contingencies.md`. The optional thinking-partner pass over the issues and step 12 are in `blocks/checker.md` (already read at step 10).

## 13. Requirements Coverage Gate

After plans pass the checker (or checker is skipped), verify that all phase requirements are covered by at least one plan.

**Skip if:** `phase_req_ids` is null or TBD (no requirements mapped to this phase).

**Step 1: Extract requirement IDs claimed by plans**
```bash
# Collect all requirement IDs from plan frontmatter
PLAN_REQS=$(grep -h "requirements_addressed\|requirements:" ${PHASE_DIR}/*-PLAN.md 2>/dev/null | tr -d '[]' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sort -u)
```

**Step 2: Compare against phase requirements from ROADMAP**

For each REQ-ID in `phase_req_ids`:
- If REQ-ID appears in `PLAN_REQS` → covered ✓
- If REQ-ID does NOT appear in any plan → uncovered ✗

**Step 3: Check CONTEXT.md features against plan objectives**

Read CONTEXT.md `<decisions>` section. Extract feature/capability names. Check each against plan `<objective>` blocks. Features not mentioned in any plan objective → potentially dropped.

**Step 4: Report**

If all requirements covered and no dropped features:
```
✓ Requirements coverage: {N}/{N} REQ-IDs covered by plans
```
→ Proceed to step 14.

If gaps are found: **Read** `workflows/plan-phase/blocks/contingencies.md` and run its "Step 13 — requirements coverage gap" branch.

## 13a. Decision Coverage Gate

Verify every trackable decision in CONTEXT.md `<decisions>` is referenced by at
least one plan. This **translation gate** (#2492) refuses to mark a phase planned
when a discuss-phase decision silently dropped.

**Skip if** `workflow.context_coverage_gate` is `false` (absent = enabled), or
no CONTEXT.md exists for this phase, or its `<decisions>` block is empty.

```bash
GATE_CFG=$(gad_run query config-get workflow.context_coverage_gate --raw 2>/dev/null || echo "true")
if [ "$GATE_CFG" != "false" ]; then
  # #2770: CONTEXT_PATH from step-1 init doesn't survive into this Bash block;
  # recompute it. Only run when a CONTEXT.md exists (handler fails closed on an
  # empty arg, so an unguarded empty glob would halt a context-less phase).
  CONTEXT_PATH=$(ls "${PHASE_DIR}"/*-CONTEXT.md 2>/dev/null | head -1)
  if [ -n "$CONTEXT_PATH" ]; then
    GATE_RESULT=$(gad_run query check.decision-coverage-plan "${PHASE_DIR}" "${CONTEXT_PATH}")
    # BLOCKING: refuse to mark phase planned when a trackable decision is uncovered.
    # `passed: true` covers both real-pass and skipped cases (gate disabled / no CONTEXT.md /
    # no trackable decisions). Verify-phase counterpart deliberately omits this exit-1 — that
    # gate is non-blocking by design (review finding F15).
    echo "$GATE_RESULT" | jq -e '(.passed // .data.passed) == true' >/dev/null || {
      echo "$GATE_RESULT" | jq -r '(.message // .data.message // "Decision coverage gate failed.")'
      exit 1
    }
  fi
fi
```

The handler returns JSON:
```json
{ "passed": true, "skipped": false, "total": 2, "covered": 2,
  "uncovered": [{ "id": "D-01", "text": "...", "category": "..." }], "message": "..." }
```

**If `passed` is true (or `skipped` is true):** Display
`✓ Decision coverage: {M}/{N} decisions covered` (or `(skipped)`) and proceed
to step 13b.

**If `passed` is false:** the failure report and its options are the "Step 13a — uncovered decisions" branch of `workflows/plan-phase/blocks/contingencies.md` — **Read** it and run that branch.

## 13a-bis. Plan Shape Gate

Mechanical check of the plans' shape, read from the same index the executor
consumes (`phase-plan-index`), so the gate and the executor cannot disagree.
Eight clauses, each with a code: `SOBREPOSICAO-NA-ONDA` (two same-wave plans
touch the same file), `FILES-MODIFIED-VAZIO` (execute plan with no files in the
index), `DEPENDENCIA-NAO-RESOLVE`, `WAVE-DECLARADA-DIVERGE` (`wave:` disagrees
with the DAG), `CADEIA-QUASE-SERIAL` (waves/plans ≥ 0.6 with 4+ plans, unless
every link's `depends_on_rationale:` names a file or symbol of its prerequisite),
`ONE-WAY-SEM-CHECKPOINT` / `TAREFA-SEM-RATING` (reversibility without a
checkpoint or a rating), and two advisory codes: `ARQUIVO-HUB` (file in 3+ plans
— wave-1 foundation plan, or one symbol per plan in successive waves) and
`LARGURA-MAXIMA-1` (4+ plans, no wave with 2+). Fork gen5-patches (P13, plan 4):
`bin/nosso/plan-gate.py`; `--probe-lastro` is the checker's 3rd probe.

```bash
NOSSO="$(dirname "$(readlink -f "$GAD_TOOLS")")/nosso"; [ -d "$NOSSO" ] || NOSSO="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/nosso"
T=$(mktemp -d "${TMPDIR:-/tmp}/gad-plan-gate.XXXXXX")
gad_run query phase-plan-index "${PHASE}" --raw > "$T/plan-index.json"
REV_FLAG=""; [ "${REVERSIBILITY_GATES:-true}" = "false" ] && REV_FLAG="--no-reversibility-gates"
SHAPE_RESULT=$(python3 "$NOSSO/plan-gate.py" "${PHASE_DIR}" "$T/plan-index.json" $REV_FLAG) || true
rm -rf "$T"
# BLOCKING, same contract as 13a: refuse to mark the phase planned while a shape defect stands.
echo "$SHAPE_RESULT" | jq -e '.passed == true' >/dev/null || {
  echo "Plan shape gate failed. Fix these in the plans and re-run the checker (step 12):"
  echo "$SHAPE_RESULT" | jq -r '.falhas[] | "  \(.codigo) \(.planos | join(",")): \(.detalhe)"'
  exit 1
}
echo "$SHAPE_RESULT" | jq -r '.avisos[]? | "  aviso \(.codigo) \(.planos | join(",")): \(.detalhe)"'
```

The script also writes the same JSON to `.planning/.gad/last-plan-gate.json`
for the go-and-do to read at the end of its planning stage.

**If `passed` is true:** display `✓ Plan shape: {planos} plans in {ondas} waves,
max width {largura_max}` (from `.resumo`) plus any `avisos`, and proceed to
step 13b.

**If `passed` is false:** the `falhas` list is the issue list. Return to step 12
with it as the checker issues (`Revision iteration` counts as usual): the
planner must fix each `codigo` in the named plans — recompute or drop `wave:`,
declare `files_modified`, fix or justify the dependency chain, put a
`checkpoint:decision` before the `one-way` task and set `autonomous: false`,
or rate the flagged task. Do not ask the user: every clause is a defect the
planner can repair alone. `--no-reversibility-gates` turns the reversibility
clause into a warning; the other five always block.

## 13b. Record Planning Completion in STATE.md

After plans pass all gates, record that planning is complete so STATE.md reflects the new phase status:

```bash
gad_run query state.planned-phase --phase "${PHASE_NUMBER}" --name "${PHASE_NAME}" --plans "${PLAN_COUNT}"
```

This updates STATUS to "Ready to execute", sets the correct plan count, and timestamps Last Activity.

## 13c. Annotate ROADMAP with Wave Dependencies and Cross-cutting Constraints

After plans are finalized, annotate the ROADMAP.md plan list for this phase with:
- **Wave dependency notes** — a bold header before each wave group ("Wave 2 *(blocked on Wave 1 completion)*")
- **Cross-cutting constraints** — a "Cross-cutting constraints:" subsection listing `must_haves.truths` entries that appear in 2 or more plans

This step is derived entirely from existing PLAN frontmatter — no extra LLM pass is required.

```bash
gad_run query roadmap.annotate-dependencies "${PHASE_NUMBER}"
```

This operation is idempotent: if wave headers or cross-cutting constraints already exist in the ROADMAP phase section, the command returns without modifying the file. Skip this step if `plan_count` is 0.

## 13d. Commit Plans if commit_docs is true

If `commit_docs` is true (from the init JSON parsed in step 1), commit the generated plan artifacts (including any ROADMAP.md annotations from step 13c):

```bash
gad_run query commit "docs(${PADDED_PHASE}): create phase plan" --files "${PHASE_DIR}"/*-PLAN.md .planning/STATE.md .planning/ROADMAP.md
```

This commits all PLAN.md files for the phase plus the updated STATE.md and ROADMAP.md to version-control the planning artifacts. Skip this step if `commit_docs` is false.

Step 13e (post-planning gap analysis over the `plan:post` hooks) is in `workflows/plan-phase/blocks/gap-analysis.md` — **Read** it now unless `workflow.post_planning_gaps` is `false`. Then step 14.

## 14. Present Final Status

Route to `<offer_next>` OR `auto_advance` depending on flags/config.

From `$ARGUMENTS` and the init JSON of step 1 (no extra `config-get`): if `--auto` or `--chain` is present, or `auto_chain_active` or `auto_advance` is true, **Read** `workflows/plan-phase/blocks/auto-advance.md` and run step 15. Otherwise clear a chain flag left by an interrupted `--auto` run (`workflow.auto_advance`, the user's preference, is untouched) and route to `<offer_next>`:

```bash
gad_run query config-set workflow._auto_chain_active false || true
```

</process>

<offer_next>
Output this markdown directly (not as a code block):

`${GAPS_EXEC_FLAG}` projects the just-completed planning mode onto the follow-up execute command (#3297): it expands to `--gaps-only` for a `--gaps` planning run (so the handoff points at execute-phase's gap-closure scope — only the newly created `gap_closure: true` plans — not the whole phase) and to empty for a standard or `--reviews` run (whole-phase scope, unchanged). Substitute it verbatim; when empty, collapse the extra space.

### GAD ► PHASE {X} PLANNED ✓

**Phase {X}: {Name}** — {N} plan(s) in {M} wave(s)

| Wave | Plans | What it builds |
|------|-------|----------------|
| 1    | 01, 02 | [objectives] |
| 2    | 03     | [objective]  |

Research: {Completed | Used existing | Skipped}
Verification: {Passed | Passed with override | Skipped}

---

## ▶ Next Up — [${PROJECT_CODE}] ${PROJECT_TITLE}

**Execute Phase {X}** — run all {N} plans

/clear then:

/gad-execute-phase {X} ${GAPS_EXEC_FLAG} ${GAD_WS}

---

**Also available:**
- cat .planning/phases/{phase-dir}/*-PLAN.md — review plans
- /gad-plan-phase {X} --research — re-research first
- /gad-review --phase {X} --all — peer review plans with external AIs
- /gad-plan-phase {X} --reviews — replan incorporating review feedback

---
</offer_next>

<windows_troubleshooting>
Read `gad-core/workflows/plan-phase/steps/windows-troubleshooting.md` if plan-phase freezes on Windows during agent spawning (stdio deadlocks with MCP servers, anthropics/claude-code#28126) — it covers force-kill, orphaned-node cleanup, stale task-dir cleanup, reducing the MCP server count, and the `--skip-research` fallback.
</windows_troubleshooting>

<success_criteria>
- [ ] .planning/ directory validated
- [ ] Phase validated against roadmap
- [ ] Phase directory created if needed
- [ ] CONTEXT.md loaded early (step 4) and passed to ALL agents
- [ ] Research completed (unless --skip-research or --gaps or exists)
- [ ] gad-phase-researcher spawned with CONTEXT.md
- [ ] Existing plans checked
- [ ] gad-planner spawned with CONTEXT.md + RESEARCH.md
- [ ] Plans created (PLANNING COMPLETE or CHECKPOINT handled)
- [ ] gad-plan-checker spawned with CONTEXT.md
- [ ] Verification passed OR user override OR max iterations with user decision
- [ ] User sees status between agent spawns
- [ ] User knows next steps
</success_criteria>
