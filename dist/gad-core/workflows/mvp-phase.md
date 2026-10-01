<purpose>
Guide the user through MVP-mode planning for a phase. Prompts for an "As a / I want to / So that" user story, runs SPIDR splitting check on the story, writes the result to ROADMAP.md, and delegates to `/gad plan-phase` (which auto-detects MVP via the roadmap mode field shipped in PRD Phase 1).
</purpose>

<required_reading>
@~/.claude/gad-core/references/user-story-template.md
@~/.claude/gad-core/references/spidr-splitting.md
@~/.claude/gad-core/references/planner-mvp-mode.md
</required_reading>

<runtime_note>
**TEXT_MODE fallback:** Set TEXT_MODE=true if `--text` is present in `$ARGUMENTS` OR `text_mode` from init JSON is true. When TEXT_MODE is active, replace every AskUserQuestion call with a plain-text numbered list and ask the user to type their choice number.
</runtime_note>

<process>

## 1. Parse and validate phase argument

Extract the phase number from `$ARGUMENTS` (integer or decimal like `2.1`). Optional flag: `--force` (allow operating on `in_progress` / `completed` phases).

If no argument:
```
ERROR: Phase number required
Usage: /gad mvp-phase <phase-number>
Example: /gad mvp-phase 1
Example: /gad mvp-phase 2.1
```
Exit.

Normalize per `@~/.claude/gad-core/references/phase-argument-parsing.md` (zero-pad integer phases to two digits).

## 2. Validate phase exists and check status

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
RESPONSE_LANGUAGE=$(gad_run query config-get response_language --raw --default "" 2>/dev/null || echo "")
PHASE_INFO=$(gad_run query roadmap.get-phase "${PHASE}")
PHASE_FOUND=$(echo "$PHASE_INFO" | jq -r '.found')
PHASE_NAME=$(echo "$PHASE_INFO" | jq -r '.phase_name')
PHASE_GOAL=$(echo "$PHASE_INFO" | jq -r '.goal')
PHASE_MODE=$(echo "$PHASE_INFO" | jq -r '.mode // ""')
ANALYZE=$(gad_run query roadmap.analyze)
if [[ "$ANALYZE" == @file:* ]]; then ANALYZE=$(cat "${ANALYZE#@file:}"); fi
DISK_STATUS=$(echo "$ANALYZE" | jq -r --arg p "$PHASE" '.phases[] | select((.phase_number|tostring)==$p) | .disk_status' | head -1)
# ADR-3180 §7.4 (issue #3186, disk-strict, #2957): DISK_STATUS alone decides
# completion — a ROADMAP checkbox carries no machine authority and is never
# ORed in here. `roadmap.analyze`'s `disk_status` already routes through the
# canonical owner (`isPhaseComplete`), so this is the same predicate the read
# and write paths both use.
if [[ "$DISK_STATUS" == "complete" ]]; then
  STATUS="completed"
elif [[ "$DISK_STATUS" == "planned" || "$DISK_STATUS" == "partial" ]]; then
  STATUS="in_progress"
else
  STATUS="not_started"
fi
```

**If `response_language` is set:** All user-facing output of this workflow — narration between tool calls, status updates, progress notes, findings, questions, prompts, and explanations — MUST be presented in `{response_language}`. Technical terms, code, file paths, and subagent prompts stay in English — only user-facing output is translated.

If `PHASE_FOUND` is `false`: error and exit. Suggest `/gad add-phase` or `/gad insert-phase` to create the phase first.

**Status guard.** If the phase is `in_progress` (has plans but not complete) or `completed`, refuse unless `--force` is in `$ARGUMENTS`:

```text
ERROR: Phase ${PHASE} is currently ${STATUS}.
Converting an active or completed phase to MVP mode mid-flight will
invalidate any existing plans and summaries.

To proceed anyway: /gad mvp-phase ${PHASE} --force
```

**Already-MVP guard.** If `PHASE_MODE` is already `mvp`, surface this and ask whether to re-prompt the user story or abort:

> "Phase ${PHASE} is already in MVP mode with goal: «${PHASE_GOAL}». Re-run user-story prompts and SPIDR check?"

Use `AskUserQuestion` with options [Re-prompt / Abort]. On Abort, exit cleanly. On Re-prompt, proceed.

## 3. User story prompts

Run three sequential `AskUserQuestion` calls. Each is free-text. After all three, assemble into the canonical sentence per `@~/.claude/gad-core/references/user-story-template.md`:

**Prompt 1 — As a:**
> "As a [user role]?"
> (Examples: "new user", "admin", "signed-in customer", "API consumer")

**Prompt 2 — I want to:**
> "I want to [capability]?"
> (Examples: "register and log in", "upload a CSV", "see my dashboard")

**Prompt 3 — So that:**
> "So that [outcome]?"
> (Examples: "I can access my account", "I can bulk-import contacts", "I can see at a glance what needs attention")

Assemble:

```
USER_STORY="As a ${ROLE}, I want to ${CAPABILITY}, so that ${OUTCOME}."
```

If any of the three answers is empty or whitespace-only, error and re-prompt that single field. Do NOT proceed with a partial story.

**Validate via the centralized User Story validator.** The verb owns the canonical regex `/^As a .+, I want to .+, so that .+\.$/` and surfaces per-error guidance:

```bash
USER_STORY_RESULT=$(gad_run query user-story.validate --story "$USER_STORY")
if [ "$(echo "$USER_STORY_RESULT" | jq -r '.valid')" != "true" ]; then
  echo "$USER_STORY_RESULT" | jq -r '.errors[]' >&2
  # Re-prompt the offending field(s) per surfaced errors, then re-run validation.
  # Do not abort the workflow on first invalid draft.
  RE_PROMPT_USER_STORY=true
fi
```

This guarantees the goal stored in ROADMAP.md will satisfy the same guard the verifier applies later.
If `RE_PROMPT_USER_STORY=true`, re-run only the offending prompt field(s), rebuild `USER_STORY`, and validate again before continuing.

## 4. SPIDR splitting check

Run the SPIDR rules from `@~/.claude/gad-core/references/spidr-splitting.md`. Briefly:

**Trigger evaluation.** Check the assembled `USER_STORY` against the four size signals from the reference (compound capabilities, multi-actor, length > 120 chars, vague capability). If none fire, **skip SPIDR** entirely — go to step 5.

**If SPIDR triggers.**

a) Restate the story to the user:

> "Your story: «${USER_STORY}»
>
> This story has [signal description, e.g., 'two compound capabilities joined by and']. Splitting it into multiple phases will produce a cleaner Walking Skeleton and reduce the risk of mid-phase scope creep.
>
> Want to walk through SPIDR splitting?"

Use `AskUserQuestion` with options [Yes, walk through SPIDR / No, proceed with the story as-is].

If "No": skip SPIDR, go to step 5.

If "Yes": continue to (b).

b) Ask which SPIDR axis fits best:

> "Which axis best fits how to split this story?"

Use `AskUserQuestion` with the five options from `spidr-splitting.md` (Spike / Paths / Interfaces / Data / Rules). Each option includes its targeted question as the description so the user can pick by understanding what each axis means.

c) Walk through the chosen axis with **one** targeted question (not all five). For example, if the user picked "Paths":

> "Does this feature have a happy path and one or more error/edge paths?"

Free-text response. Workflow parses to identify the split.

d) Produce a split proposal. Example:

> "Proposed split (Paths axis):
> - **Phase ${PHASE} (this one):** Happy path — ${HAPPY_STORY}
> - **Phase ${PHASE+1} (new):** Edge case — ${EDGE_STORY}
>
> Accept this split?"

Use `AskUserQuestion` [Accept / Modify / Reject].

- **Accept**: `USER_STORY` becomes the first split's story (`${HAPPY_STORY}` in the example). Surface the remaining splits as a list of `/gad add-phase` invocations the user can run after this command completes — do NOT auto-create the new phases (preserve user control over numbering).
- **Modify**: re-prompt the splits one more time, then accept or reject.
- **Reject**: revert `USER_STORY` to the original, proceed without splitting.

## 5. Update ROADMAP.md

Read `ROADMAP.md`. Find the section for `Phase ${PHASE}`. Apply two edits:

**Edit 1 — Update Goal line.**

Find: `**Goal:** ${OLD_GOAL_TEXT}`
Replace with: `**Goal:** ${USER_STORY}`

**Edit 2 — Insert Mode line.**

If `**Mode:**` already exists in the section (replacing or re-running), update it to `**Mode:** mvp`.
If `**Mode:**` does not exist, insert `**Mode:** mvp` on the line immediately after `**Goal:**`.

Show the user a unified diff (lines being changed) and ask:

> "Apply these changes to ROADMAP.md?"

Use `AskUserQuestion` [Apply / Cancel]. On Cancel, exit without writing.

On Apply, write the updated `ROADMAP.md` atomically (read-edit-write).

## 6. Verify the write

```bash
NEW_MODE=$(gad_run query roadmap.get-phase "${PHASE}" --pick mode)
NEW_GOAL=$(gad_run query roadmap.get-phase "${PHASE}" --pick goal)
```

Assert:
- `NEW_MODE` equals `mvp`
- `NEW_GOAL` equals the assembled user story

If either assertion fails, surface the discrepancy to the user and exit. Do not proceed to plan-phase delegation with a half-applied write.

## 7. Delegate to /gad plan-phase

Invoke `/gad plan-phase ${PHASE}` (no flags). Phase 1's MVP_MODE resolution chain (CLI flag → roadmap mode → config → false) will detect the new `**Mode:** mvp` line and run plan-phase in vertical-slice mode automatically.

The Walking Skeleton gate (also from Phase 1) will fire automatically if `${PHASE} == "01"` and there are zero prior phase summaries.

## 8. Surface deferred phase splits (if any)

If SPIDR produced a split in step 4, append a final user-facing message:

> "**SPIDR split deferred phases.**
>
> Your original story was split. The first slice is now planned via plan-phase.
> To create the remaining slice(s) as new phases, run:
>
> - `/gad add-phase` — for the next slice: «${SPLIT_2_STORY}»
> - `/gad add-phase` — for the next slice: «${SPLIT_3_STORY}»
>
> Each will be added to the end of the current milestone. You can then run
> `/gad mvp-phase <new-phase-number>` on each to plan them as MVP slices."

## 9. Exit

Workflow ends. The phase is now in MVP mode with a planned PLAN.md, optionally with deferred follow-up phases surfaced for the user.

</process>
