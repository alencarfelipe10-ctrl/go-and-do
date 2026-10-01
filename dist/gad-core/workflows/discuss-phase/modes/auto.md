Apply response_language to all user-facing prose — narration between tool calls, status updates, progress notes, and findings included; preserve code, paths, and identifiers.

# --auto: autonomous discuss

> Lazy-loaded from `workflows/discuss-phase.md` when `--auto` is in `$ARGUMENTS`.
> `--auto` alone does not chain to plan-phase: the run ends after `finalize` (commit) →
> `confirm_creation` (2 lines) → `auto_advance`, which reads `modes/chain.md` only with
> `--chain`, `workflow.auto_advance: true` or `workflow._auto_chain_active: true`.

No question reaches the user. For every area, pick the option you would recommend (the first, or the one marked "recommended"), record it with `--origin auto` (`--origin pre-spec` only when the PRE-SPEC locked it), and cite `file:line` in `--evidence` whenever the answer states a fact about the code — verify it first (Read/Grep). In audited phases every uncited code fact picked by default turned out to be wrong; the citation is what forces the check. `--evidence none` only when the decision asserts no code fact. Alternatives and the reason go in `options`/`prose`; the renderer emits them under the bullet. `answer` states what must be true and how a failure shows; `evidence` proves it is true today, never where to change it. How you would implement it, if you want to suggest, goes in `nota`: it renders under "Implementation Notes", the planner reads it as a suggestion and no gate asks for it.

## What changes per step

- `initialize`: `ADVISOR_MODE` is forced to `false` even with `USER-PROFILE.md` (logged as `[auto] advisor disabled`) — the advisor dispatches one agent per area and asks questions; neither belongs in an autonomous run.
- `check_existing`: CONTEXT.md present → `reconcile_existing` (the file is immutable; only new todos are appended under `### Folded Todos`; no re-discussion, re-render or renumbering of D-NN). Log `[auto] CONTEXT exists — reconciling, not re-discussing`. Interrupted checkpoint → "Resume". Existing plans → "Continue and replan after". Log each of these choices so the user can audit them.
- `cross_reference_todos`: fold every match with `score >= TODO_THRESHOLD` (`features.todo_fold_threshold`, default 0.4) and log the selection.
- `analyze_phase`: every area carries `anchor: <R-id | SC-id | none>`; `none` areas are not discussed — one line in `discretion.txt` with the reason. No numeric cap. The checkpoint `init` runs always (also on skip) and structured, `--area "<name>|<anchor1>[,anchor2]"`, so the anchors live in the checkpoint (`areas: [{name, anchors, anchors_remaining}]`) and not only in the prose log — `map-pre-spec` matches against the checkpoint, never against prose. Before `init`, group the areas by the object they change — the file, the collection, the contract, the artifact — not by the doubt that raised them: one area per object with every anchor that falls in it (`--area "<object>|R2,R4"`), one decision per area. Two areas changing the same object give the planner two versions of one choice to reconcile. No numeric target: twenty objects, twenty areas.
- `present_gray_areas`: no banner; one log line `[auto] areas: <A> (R1), <B> (R2), …`; all areas selected.
- Objective skip (`[9.2]`): when `spec_loaded` and the number of anchored areas with substance is ≤ 1 and `REGRESSION_EMPTY=true` → log `[auto] skip: no substantive gray areas (spec-locked phase)`, skip `discuss_areas`, Read `workflows/discuss-phase/blocks/finish.md` and go to `write_context`. The rendered CONTEXT is the minimal one (domain + spec_lock + canonical_refs with the SPEC + code_context + decisions with only "Claude's Discretion" + empty deferred). "Claude's Discretion" explains why zero decisions is valid here, and the coverage gate's `no trackable decisions` is declared expected in the log. A default you did pick for anything is a D-NN decision (`origin auto`), not discretion.
- Mandatory gray areas for new committed artifacts (R5): when the init reported `GRAY_AREAS_ARTEFATOS: <N>` with N > 0, the SPEC commits new artifacts (baseline, golden, fixture, snapshot, seed) and each one is its own decision — the lines are in `$GRAY_ARTEFATOS`. Decide, and say so in the `answer`: final path · lands in a mirrored/public directory? · carries personal data? · what precedent it sets. Cite the artifact path verbatim in the decision text: that literal is how `context-guard.sh` matches the D-NN to the artifact, and a missing one is `GUARD_EXIT=2`, not a warning.
- A measurement showing a locked requirement cannot be satisfied is not a decision: report it to the host with a pointer to the requirement and move on. The SPEC is where acceptance is decided.
- After all areas are resolved: no "Explore more gray areas" prompt. Read `workflows/discuss-phase/blocks/finish.md` and go to `write_context` (the objective skip needs the same Read).
- `confirm_creation`: two lines — CONTEXT path and decision count. No "Next Up" block, no ROADMAP re-read.
- `finalize`: no DISCUSSION-LOG in auto (the opt-in key is ignored here).

## Checkpoint order (D3 · D5 · R5)

The commands and their examples are in the core's `analyze_phase` and `discuss_areas`; this file fixes only the order, because a decision recorded before `init` is lost on resume and a PRE-SPEC entry sent through `--batch` is refused by the writer:

1. `init`, structured (one `--area "<name>|<anchors>"` per area).
2. `map-pre-spec` — only when `PRE_SPEC_STATE=ok` (`discuss-init.sh` autodetected `<phase_dir>/*-PRE-SPEC.md` and wrote `$PRE_SPEC_BATCH`; `ausente` means no PRE-SPEC or no `gad:decisoes` block, and the step is skipped). It is the single owner of the PRE-SPEC decisions; `fato_medido` never arrives here — the init filtered it out, it belongs to the briefing/SPEC as `[medido:PS-nn]`.
3. The auto decisions — one `add-decision --batch` with every decision of the run in `$T/decisoes-auto.json` (example in the core), instead of one process per decision.
4. `complete-area` — one call per area the batch marked as finished that `map-pre-spec` did not already close.

Every block starts with `. .planning/.discuss-tmp/env.sh` and spells the script out as `python3 "$NOSSO/checkpoint-write.py" …`. Do not define an alias of your own (`CW=…`): it is gone in the next bash block and does not expand under zsh, so the call silently runs the wrong thing.

## Pass cap

One pass: after `write_context` rendered and the guard passed, go to `finalize`. Do not re-read your own CONTEXT.md looking for gaps — each pass generates references the next pass treats as gaps, without end. The only second pass is the single guard correction in `write_context` (`GUARD_EXIT=2`). If CONTEXT.md is already committed, the step is complete.

## Combination rules

- `--auto --text` / `--auto --batch`: the text/batch overlays are no-ops (no user prompts to render).
- `--auto --analyze`: trade-off tables can still be logged (in `prose`); selection still uses the recommended option.
- `--auto --power`: `--power` wins (power mode generates files for offline answering — incompatible with autonomous selection).
- `--auto --chain`: discussion autonomous, then `auto_advance` reads `modes/chain.md`.
