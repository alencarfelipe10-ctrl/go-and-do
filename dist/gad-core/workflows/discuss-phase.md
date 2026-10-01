<!-- gad:loop-host
step: discuss
points: discuss:pre, discuss:post
agent-roles: orchestrator
produces: CONTEXT.md
consumes:
-->
<!-- Fork gen5-patches (tarefa 3b; recorte P08, 01/09/2026): everything deterministic (checks, SPEC
extraction, prior context, refs, checkpoint, CONTEXT frame, guard, index) is done by bin/nosso/ scripts;
the model reads, judges and writes free text. Interview material lives in modes/default.md. -->
<purpose>
Extract the implementation decisions that downstream agents need: analyze the phase, identify gray areas, resolve each selected one, and record every decision through the checkpoint writer. The user is the visionary and you are the builder — capture what guides research and planning; do not design the implementation.

CONTEXT.md feeds `gad-phase-researcher` (what to research) and `gad-planner` (which decisions are locked). Capture decisions clearly enough that neither needs to ask the user again; how to implement is their job.
</purpose>

<gray_area_identification>
Gray areas are implementation decisions the user cares about — things that could go multiple ways and would change the result.

1. Start from `PHASE_GOAL` / `PHASE_CRITERIA` (from `initialize` — do not re-read ROADMAP.md).
2. Understand the domain — something users see / call / run / read, or something being organized — and let that drive which decisions matter.
3. Generate phase-specific gray areas, not generic category labels (UI, UX, Behavior):

```
Phase: "User authentication"     → Session handling, Error responses, Multi-device policy, Recovery flow
Phase: "CLI for database backups"→ Output format, Flag design, Progress reporting, Error recovery
```

Anchor every area to the SPEC: each area declares `anchor: <id>` with a literal id from `REQ_IDS` (`R1`, `R2`…) or `anchor: none`. Without a SPEC, anchor to the ROADMAP success criterion index (`SC1`, `SC2`… from `PHASE_CRITERIA`). An area with `anchor: none` is not discussed — it becomes one line under "Claude's Discretion" with the reason. No numeric cap on areas (audited phases have a median of 7): the anchor is the filter, not a count. Group areas by object (`modes/auto.md`).

Claude handles these without asking: technical implementation details, architecture patterns, performance optimization, scope (the roadmap defines it).
</gray_area_identification>

<process>

**Express path:** with a PRD or acceptance criteria in hand, `/gad-plan-phase {phase} --prd path/to/prd.md` skips this discussion.

<step name="initialize" priority="first">
Phase number from argument (required). One bash call resolves gad-tools and runs `bin/nosso/discuss-init.sh`, which does everything deterministic: init, phase entry, check-batch (steps 2–4), SPEC data (reqs in 3 states, scope, files, regression surface), ROADMAP refs, advisor detection, pre-hooks, PRE-SPEC (autodetected in `<phase_dir>`; its `gad:decisoes` block becomes `$PRE_SPEC_BATCH` — never pass a flag, never open the PRE-SPEC), prior context (`$T/prior.txt`), config keys — and persists the scalars and `gad_run` in `.planning/.discuss-tmp/env.sh` for every later block.

```bash
GAD_TOOLS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/gad-tools.cjs"
[ -n "$GAD_TOOLS" ] && [ -f "$GAD_TOOLS" ] || { echo "ERROR: gad-tools not found. Run the go-and-do installer (`go-and-do install`)" >&2; exit 1; }
NOSSO="$(dirname "$(readlink -f "$GAD_TOOLS")")/nosso"; [ -d "$NOSSO" ] || NOSSO="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/nosso"
GAD_TOOLS="$GAD_TOOLS" ARGUMENTS="$ARGUMENTS" bash "$NOSSO/discuss-init.sh" "${PHASE}"
```

Parse INIT for the 12 fields used here: `phase_found`, `phase_dir`, `expected_phase_dir`, `phase_number`, `phase_name`, `phase_slug`, `padded_phase`, `has_context`, `has_plans`, `plan_count`, `response_language`, `commit_docs`. Keep `PHASE_GOAL`, `PHASE_CRITERIA`, `CHECKS`, the `SPEC:` line (its `pre_spec=<state> n=<N>` tail is the PRE-SPEC trail), the `PRE_SPEC:` line, `PRIOR:` and `ROADMAP_REFS` — they replace every later "read ROADMAP.md" / `ls` instruction. Every later bash block starts with `. .planning/.discuss-tmp/env.sh`; never re-paste the cascade.

**If `response_language` is set:** All user-facing output of this workflow — narration between tool calls, status updates, progress notes, findings, questions, prompts, and explanations — MUST be presented in `{response_language}`. Technical terms, code, file paths, and subagent prompts stay in English — only user-facing output is translated.

If `phase_found` is false: print `Phase [X] not found in roadmap. Use /gad-progress ${GAD_WS} to see available phases.` and exit. If the `[fallback] roadmap get-phase not found` line appeared, read the phase entry from ROADMAP.md manually.

Mode files are read once, at the step that needs them:

| Flag | Read | At |
|---|---|---|
| `--power` | `workflows/discuss-phase/modes/power.md`, execute it end-to-end and stop (none of the steps below) | now |
| `--auto` | `modes/auto.md` (`ADVISOR_MODE` is already false; auto-advance is not implied) | now |
| interactive (no `--auto`) | `modes/default.md` — base of every interactive overlay; holds the questions of `check_existing`/`present_gray_areas` | now |
| `--all` · `--text` (or `workflow.text_mode: true`) · `--batch` · `--analyze` | `modes/all.md` · `text.md` · `batch.md` · `analyze.md` | `--all`: before `present_gray_areas`; `--text`: before any AskUserQuestion; the other two: before `discuss_areas` |
| `ADVISOR_MODE = true` | `modes/advisor.md` | before `analyze_phase` |
| `--chain` | `modes/chain.md` | at `auto_advance` |

`templates/context.md` and `templates/checkpoint.json` are never read at runtime — `bin/nosso/context-render.py` and `bin/nosso/checkpoint-write.py` are their executable form. Files under `references/` are read only where a step below says so.

Continue to `check_blocking_antipatterns`.
</step>

<step name="check_blocking_antipatterns" priority="first">
Decision over `CHECKS.blocking` — no bash. If `blocking` = 0 (file absent or no blocking rows): do not open the file; proceed to `check_spec`. If `blocking > 0`: Read `~/.claude/gad-core/references/universal-anti-patterns.md` (only now — with zero blocking rows it has nothing to add) and `${phase_dir}/.continue-here.md`; parse its "Critical Anti-Patterns" table rows with `severity` = `blocking` and, for each one, answer inline: (1) What is this anti-pattern? (2) How did it manifest? (3) What structural mechanism (not acknowledgment) prevents it? If one cannot be answered from the file, stop and ask the user.
</step>

<step name="check_spec">
Decision over `CHECKS.spec` and the `SPEC:` line. If `SPEC_PATH` is set: Read the SPEC.md (prose is the input for HOW-areas). The count is not your job: `REQ_STATE=valid` → `REQ_COUNT`/`REQ_IDS` are authoritative; `absent` → count numbered items under `## Requirements` yourself (log `[fallback] counted from prose`); `invalid` → same, and keep the `[warn]` visible. Display `Found SPEC.md — {N} requirements locked. Focusing on implementation decisions.` and set `spec_loaded = true`. Requirements, boundaries and acceptance criteria are `<locked_requirements>` — they flow into CONTEXT.md via `<spec_lock>` (rendered by script from `scope-in/out.txt`) without re-asking. If no SPEC: `spec_loaded = false` and Read `~/.claude/gad-core/references/domain-probes.md` — with a SPEC the domain probes already ran in the spec-phase and their result is in the SPEC.
</step>

<step name="check_existing">
Decision over `has_context`, `CHECKS.checkpoint`, `has_plans` (all from `initialize`) — no bash. The interactive prompts are in `modes/default.md`; here is the rule and the `--auto` answer.

- `has_context` true — `--auto`: the existing CONTEXT.md is immutable in this run (re-entry guard, `[C2-23]`): log `[auto] CONTEXT exists — reconciling, not re-discussing`, skip `load_prior_context`→`discuss_areas`, then `Read(workflows/discuss-phase/blocks/finish.md)` and jump to its `reconcile_existing`. Interactive: ask Update / View / Skip; "Update it" → Read the CONTEXT.md, then `Read(workflows/discuss-phase/blocks/finish.md)` and go to its `reconcile_existing` (edits by `Edit`, never renumbering D-NN); "View it" → show it, then offer Update/Skip; "Skip" → exit.
- `CHECKS.checkpoint` true (interrupted discussion) — `--auto`: "Resume". Interactive: ask Resume / Start fresh. On "Resume": `python3 "$NOSSO/checkpoint-write.py" show "$CKPT"` gives `areas_completed`/`areas_remaining`/ids — continue to `present_gray_areas` with only the remaining areas; new decisions continue the D-NN sequence. On "Start fresh": `rm` the checkpoint and continue.
- `has_plans` true — `--auto`: log `[auto] Plans exist — continuing with context capture, will replan after.` Interactive: ask Continue and replan / View plans / Cancel.

Continue to `load_prior_context`.
</step>

<step name="load_prior_context">
Read `.planning/.discuss-tmp/prior.txt` (size in the init's `PRIOR:` line): `discuss-init.sh` already sliced STATE.md sections, PROJECT.md (Core Value / Key Decisions / Constraints), REQUIREMENTS.md (integral), the prior decisions (`DECISIONS-INDEX.md`, or the last 3 CONTEXT.md files), spikes/sketches and TODO matches into it. It is the only source of prior context — do not re-read those files whole.

Findings skills listed under `SPIKES/SKETCHES`: Read the SKILL.md and reference files; extract validated patterns, landmines, constraints. Raw spikes/sketches without a findings skill: note `⚠ Unpackaged spikes/sketches detected — run /gad-spike --wrap-up or /gad-sketch --wrap-up.`

Build internal `<prior_decisions>` (Project-Level / From Prior Phases / From Spike/Sketch Findings): `analyze_phase` skips already-decided gray areas, `present_gray_areas` annotates options ("You chose X in Phase 5"), `discuss_areas` pre-fills or flags conflicts. No prior context → continue (expected early on).
</step>

<step name="cross_reference_todos">
From the `TODO MATCHES` JSON in `prior.txt` (`todo_count`, `matches[]` with `file`, `title`, `area`, `score`, `reasons`). Empty → skip silently. Otherwise present each match and AskUserQuestion (multiSelect) asking which to fold. Folded → `folded_todos` (rendered under `### Folded Todos` in `<decisions>`); reviewed but not folded → `reviewed_todos` (rendered under `<deferred>`). `--auto`: fold every match with `score >= TODO_THRESHOLD` (`features.todo_fold_threshold`, default 0.4) and log the selection.
</step>

<step name="scout_codebase">
One bash call replaces the manual scan (the funnel it applies is documented in `references/scout-codebase.md`; do not read it):

```bash
. .planning/.discuss-tmp/env.sh
bash "$NOSSO/scout.sh" "$PHASE" ${SPEC_PATH:+--spec "$SPEC_PATH"} --out "$T/scout.md"
```

Read `$T/scout.md` (≤ 8 KB: origin `grafo <commit>` or `grep`, relevant files with symbols and neighbours, existing tests, and the `## reusable` / `## patterns` / `## integration` skeleton) and build internal `<codebase_context>` from it. With a SPEC, open only the paths in `spec-files.txt` a gray area needs. Beyond that, when the host handed you an exploration file, read the conclusion there instead of the source; otherwise confirm the fact yourself and log it. Every file you open is re-read on every later turn of this window.
</step>

<step name="dispatch_discuss_pre_hooks">
`PRE_HOOKS` was rendered in `initialize`. If `activeHooks` is non-empty, apply each entry per @~/.claude/gad-core/references/loop-hook-dispatch.md (contribution fragments read inline; `step` hooks with `ref.skill`/`ref.agent` are dispatched via the Skill/Agent tool and awaited). Empty → continue.
</step>

<step name="analyze_phase">
Analyze the phase to identify gray areas. Use `prior_decisions` and `codebase_context` to ground the analysis.

1. **Domain boundary** — what capability this phase delivers (from `PHASE_GOAL`). Write it as free text to `.planning/.discuss-tmp/goal-domain.txt` with `Write` (1–3 sentences; it becomes `<domain>`).
2. **Canonical refs accumulator** — five sources, union + dedup by path: (1) ROADMAP (`ROADMAP_REFS`, script-resolved — `MISSING` entries stay listed with the `<!-- ref not found on disk -->` note the renderer adds; never invent a path); (2) the SPEC (always, when loaded — the renderer inserts it first); (3) ADRs/specs cited in PROJECT.md/REQUIREMENTS.md (from `prior.txt`, 1 line each); (4) docs the scout found in code; (5) anything the user references during discussion (added immediately — often the most important). Write the list to `.planning/.discuss-tmp/refs.txt`, one per line, `path|topic|note`.
3. **Check prior decisions** — mark already-decided gray areas pre-answered.
4. **SPEC awareness** — if `spec_loaded`: `<locked_requirements>` are pre-answered (Goal, Boundaries, Constraints, Acceptance Criteria). Do not generate gray areas about WHAT or WHY — only HOW. When presenting, say "Requirements are locked by SPEC.md — discussing implementation decisions only."
5. **Gray areas** — 1–2 specific ambiguities per relevant category that would change implementation, each with `anchor:` (see `<gray_area_identification>`), annotated with code context. Log the list as `area → anchor`.
6. **Existing-test reconciliation** — when `REGRESSION_EMPTY=false` (or the scout found assertions on values the phase changes), include the area "Reconciliation of existing tests/goldens" with options per assertion (invert / re-anchor / remove).
7. **Skip assessment** — if no anchored gray area remains (pure infrastructure, all decided), the phase may not need discussion (rule in `modes/auto.md`). When that objective skip fires, **`Read(workflows/discuss-phase/blocks/finish.md)`** and continue at its `write_context`.
8. **Code context** — write `.planning/.discuss-tmp/code-context.txt` (`## reusable` / `## patterns` / `## integration` sections, bullets) from `<codebase_context>`, and `.planning/.discuss-tmp/discretion.txt` (one line per `anchor: none` area and per "you decide" so far).

Then create the checkpoint — always, before deciding skip or discuss (`[C3-43]`), because a checkpoint created after the first decision loses that decision on resume:

```bash
. .planning/.discuss-tmp/env.sh
SPEC_ARGS=(); [ -n "$SPEC_PATH" ] && SPEC_ARGS=(--spec "$SPEC_PATH" --req-ids "$REQ_IDS" --scope-in-file "$T/scope-in.txt" --scope-out-file "$T/scope-out.txt")
python3 "$NOSSO/checkpoint-write.py" init "$CKPT" --phase "${padded_phase}" --phase-name "$phase_name" --goal-file "$T/goal-domain.txt" "${SPEC_ARGS[@]}" --refs-file "$T/refs.txt" --code-context-file "$T/code-context.txt" --discretion-file "$T/discretion.txt" --area "<Area 1>|R1,R2" --area "<Area 2>|SC3"
```

One `--area "<name>|<anchors>"` per anchored gray area, in the order you will discuss them (`--area "<name>"` when it has none); the anchors in the checkpoint are what `map-pre-spec` matches against. On resume the checkpoint already exists — `init` is a no-op.

If `ADVISOR_MODE` is true, follow `modes/advisor.md` for the rest of analyze/discuss (`advisor_research`, table-first selection); it still persists decisions through the writer.
</step>

<step name="present_gray_areas">
`--auto`: no banner — one log line `[auto] areas: A (R1), B (R2), …` and continue to `discuss_areas` with all areas. `--all`: log `[--all] Auto-selected all gray areas: […]` and continue. Otherwise present the domain boundary, carried-forward decisions and gray areas, then ask which to discuss (the question is in `modes/default.md`); continue to `discuss_areas` with the selected areas (or `advisor_research` per `modes/advisor.md`).
</step>

<step name="discuss_areas">
Discussion behaviour is defined by the active mode file(s): `modes/advisor.md`, `modes/auto.md` (recommended option, no AskUserQuestion, single pass) or `modes/default.md` (4 single-question turns per area, then check whether to continue). Overlays combine outer→inner in fixed order `--analyze` → `--batch` → `--text`. Universal rules (every mode):
- **Every decision is persisted through the writer** — never a heredoc, never a hand-written JSON. Free text goes to files written with `Write` in `.planning/.discuss-tmp/` (no escaping needed); scalars go as arguments. One call per decision, then `complete-area` when the area is resolved:
  ```bash
  . .planning/.discuss-tmp/env.sh
  python3 "$NOSSO/checkpoint-write.py" add-decision "$CKPT" --area "<Area>" --origin <owner|pre-spec|auto|prior-phase|todo> --anchor <R2|SC1|none> --evidence "<path:line|none>" [--reversibility <reversible|costly|one-way> --reversibility-rationale-file "$T/<area>-rev.txt"] --question-file "$T/<area>-q1.txt" --answer-file "$T/<area>-a1.txt" [--prose-file "$T/<area>-p1.txt"] [--option-file "$T/<area>-o1.txt" --option-file "$T/<area>-o2.txt" --chosen-option <index>]
  python3 "$NOSSO/checkpoint-write.py" complete-area "$CKPT" --area "<Area>"
  ```
  `answer` = the decision itself (one line); `prose` = rationale, discarded alternatives, cycle corrections (free form; the renderer neutralizes what the parser would misread); `nota` = suggestion; `evidence` = `file:line` when the answer asserts a codebase fact (mandatory in `--auto`); `origin` = who decided (`owner` the user, `pre-spec`, `auto`, `prior-phase`, `todo`); `reversibility` needs its rationale file when `costly`/`one-way`. The id is assigned by the script, never reused.
- **Batch** (`--auto`: all the auto decisions of the run in one call). `$T/decisoes-auto.json` carries the CLI fields as literals (`question`, `prose`, `options` list, `chosen_option`/`chosen_label`, `reversibility_rationale`, the `*_file` forms; `complete_area: true` closes the area). The writer validates the whole array first — one bad entry, nothing written; a valid batch of N equals N unitary calls:
  ```json
  [
    {"area":"Área A","origin":"auto","anchor":"R1","evidence":"src/x.py:1","answer":"resposta 1"},
    {"area":"Área A","origin":"auto","anchor":"R1","evidence":"src/x.py:2","answer":"resposta 2"},
    {"area":"Área A","origin":"auto","anchor":"R1","evidence":"src/x.py:3","answer":"resposta 3","complete_area":true}
  ]
  ```
  ```bash
  . .planning/.discuss-tmp/env.sh
  python3 "$NOSSO/checkpoint-write.py" add-decision "$CKPT" --batch "$T/decisoes-auto.json"
  ```
- **PRE-SPEC decisions** (`PRE_SPEC_STATE=ok`) enter only through `map-pre-spec` — two positionals, no flags — right after `init`, before any `add-decision`. It inserts them with `origin pre-spec`, subtracts each covered anchor and closes an area when its `anchors_remaining` empties; `--batch` refuses them, and you never re-type them:
  ```bash
  . .planning/.discuss-tmp/env.sh
  [ "$PRE_SPEC_STATE" = ok ] && python3 "$NOSSO/checkpoint-write.py" map-pre-spec "$CKPT" "$PRE_SPEC_BATCH"
  ```
- **Canonical ref accumulation** — when the user references a doc/spec/ADR, immediately Read it (or confirm it exists) and append `path|topic|note` to `$T/refs-more.txt`; before `write_context` it is merged with `set --field canonical_refs --append`.
- **Scope creep** — capture as deferred idea (`$T/deferred.txt`, one per line) and redirect (`modes/default.md` has the wording).
- **Discussion log** — only when `LOG_ON=true` and not `--auto`: accumulate options/selection/notes for `finalize`.

**End of the area loop:** when every selected area is resolved, **`Read(workflows/discuss-phase/blocks/finish.md)`** and continue at its `write_context`.
</step>

<step name="finish_block">
Everything from `write_context` onwards lives in `workflows/discuss-phase/blocks/finish.md` (lazy block, D6): `write_context`, `write_for_humans`, `dispatch_discuss_post_hooks`, `finalize`, `reconcile_existing`, `confirm_creation`, `auto_advance`. Read it at the border that sent you here and execute from the step named there — not earlier, because most runs read it exactly once, at the end.
</step>

</process>

<success_criteria>
Verifiable by `bin/nosso/context-guard.sh` (structure, tag order, SPEC in refs, parser, anchors, refs on disk) and by the `finalize` block (index generated, single commit or policy skip, STATE updated). The three that remain judgment calls:
- CONTEXT.md captures actual decisions, not vague vision — each with evidence when it asserts a code fact
- The planner can act without re-asking the user (no "TBD", no pointer to a doc that does not exist)
- Scope respected: nothing outside `<domain>`/`<spec_lock>` became a decision; creep went to `<deferred>`
</success_criteria>
