@~/.claude/gad-core/references/response-language-directive.md

<purpose>
Edit any field of an existing phase in ROADMAP.md in place. The phase number and position are always preserved. Guarded against in-progress and completed phases unless --force is passed. Validates depends_on references before writing. Shows a diff and requests confirmation before writing.
</purpose>

<required_reading>
Read all files referenced by the invoking prompt's execution_context before starting.
</required_reading>

<process>

<step name="parse_arguments">
Parse the command arguments:
- First argument: phase number to edit (integer or decimal)
- Optional flag: --force (allow editing in_progress/completed phases)

Examples:
  `/gad-edit-phase 5`       → phase = 5, force = false
  `/gad-edit-phase 5 --force` → phase = 5, force = true
  `/gad-edit-phase 12.1`    → phase = 12.1, force = false

If no argument provided:

```
ERROR: Phase number required
Usage: /gad-edit-phase <phase-number> [--force]
Example: /gad-edit-phase 5
Example: /gad-edit-phase 5 --force
```

Exit.
</step>

<step name="init_context">
Load phase operation context:

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
INIT=$(gad_run query init.phase-op "${target}")
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
```

Check `roadmap_exists` from init JSON. If false:
```
ERROR: No roadmap found (.planning/ROADMAP.md)
Run /gad-new-project to initialize.
```
Exit.
</step>

<step name="load_phase">
Read the current phase section from ROADMAP.md:

```bash
PHASE_DATA=$(gad_run query roadmap get-phase "${target}")
```

Parse the JSON result. If `found` is false:

```
ERROR: Phase {target} not found in ROADMAP.md

Available phases can be seen with /gad-progress.
```

Exit.

Extract from the result:
- `phase_name` — the phase title
- `goal` — the phase goal/description
- `success_criteria` — array of criteria
- `section` — full raw section text (preserves depends_on, requirements, plans, etc.)

Also parse the full section text to extract additional fields not in the SDK result:
- `depends_on` — from `**Depends on:** ...` or `**Depends on**: ...` line
- `requirements` — from `**Requirements:** ...` block if present
</step>

<step name="check_phase_status">
Determine the phase status from disk. Compare against STATE.md current phase:

```bash
ANALYZE=$(gad_run query roadmap analyze)
```

Find the phase entry in the `phases` array. Extract `disk_status`.

Map disk_status to a user-friendly status:
- `complete` → status = `completed`
- `planned` or `partial` → status = `in_progress`
- `empty`, `no_directory`, `discussed`, `researched` → status = `future`

If status is `in_progress` or `completed` AND `--force` was NOT passed:

```
ERROR: Cannot edit Phase {target} — status is {status}

Editing an in-progress or completed phase may invalidate executed plans.

To edit anyway, run:
  /gad-edit-phase {target} --force
```

Exit.

If `--force` was passed and status is `in_progress` or `completed`, continue with a warning printed to the user:

```
WARNING: Editing Phase {target} which is {status}. Proceeding due to --force.
```
</step>

<step name="present_current_values">
Display the current phase fields clearly:

```
Current values for Phase {target}: {phase_name}

Title:            {phase_name}
Goal:             {goal}
Depends on:       {depends_on or "(none)"}
Requirements:     {requirements or "(none)"}
Success Criteria:
  1. {criterion_1}
  2. {criterion_2}
  ...
```

Then ask the user what they want to change:

```
What would you like to do?

  [1] Edit specific fields (title, goal, depends_on, requirements, success_criteria)
  [2] Regenerate all fields from a clarified intent
  [3] Cancel

Enter choice (1, 2, or 3):
```

Wait for user input.
</step>

<step name="collect_edits">

**If user chose [3] Cancel:** Exit cleanly.

**If user chose [1] Edit specific fields:**

Ask which fields to edit. For each field the user wants to change, prompt for the new value. Only fields the user explicitly answers become updates; empty answers preserve the existing value.

```
Which fields do you want to update? (comma-separated or "all")
Options: title, goal, depends_on, requirements, success_criteria
```

For each selected field, ask:

```
New value for {field} [current: {current_value}]:
```

Build an `updates` map of {field → new_value} for non-empty answers.

**If user chose [2] Regenerate all from clarified intent:**

Ask the user:

```
Describe the revised intent for Phase {target} (replace the current description):
```

Wait for user input. Use the clarified intent to rewrite all fields:
- Generate a clear, concise `title` from the intent
- Write a complete `goal` statement
- Produce updated `requirements` if the original had them
- Generate `success_criteria` (3-5 measurable criteria)
- Preserve `depends_on` unless the user explicitly mentioned changing it
</step>

<step name="validate_depends_on">
If `depends_on` is being updated (or preserved as non-empty), validate that every referenced phase number exists in ROADMAP.md:

```bash
ALL_PHASES=$(gad_run query roadmap analyze)
```

Parse the `phases` array to get all valid phase numbers.

For each phase number referenced in `depends_on`:
- Normalize it (strip whitespace, "Phase" prefix if present)
- Check it is in the valid phase numbers set
- It must not reference itself (phase {target})

If any reference is invalid:

```
ERROR: depends_on references invalid phase(s): {bad_refs}

Valid phase numbers: {valid_list}

Fix the depends_on field and try again.
```

Exit (do not write).
</step>

<step name="show_diff_and_confirm">
Build the updated phase section by applying the changes to the original `section` text:

- For `title`: replace the heading text after `Phase {N}:`
- For `goal`: replace the `**Goal:**` line value
- For `depends_on`: replace or add the `**Depends on:**` line
- For `requirements`: replace or add the requirements block
- For `success_criteria`: replace the numbered list under `**Success Criteria**:`
- For full regeneration: rebuild the entire section from the new field values

Show a unified-style diff of old vs. new:

```
Proposed changes to Phase {target}:

--- current
+++ updated
@@ ...
- **Goal:** {old_goal}
+ **Goal:** {new_goal}
...

Apply these changes? (y/n):
```

Wait for confirmation. If the user says `n`, exit without writing.
</step>

<step name="write_updated_phase">
Before writing, capture the current milestone scope (window scope + phase set) so the write can be verified against it:

```bash
SCOPE_BEFORE=$(gad_run query roadmap milestone-scope)
```

Write the updated phase back in place in ROADMAP.md.

Read the full ROADMAP.md content, locate the phase section by its header (`## Phase {N}:` or `### Phase {N}:`), and replace exactly the old section text with the new section text. All content before and after the section (including other phases, milestone headers, and the summary checklist) must be left unchanged.

After writing, re-derive the milestone scope and compare it to the capture:

```bash
SCOPE_AFTER=$(gad_run query roadmap milestone-scope)
```

If `scope` or `phases` differs from SCOPE_BEFORE, the replacement text introduced a heading that terminates the current milestone window (a level 1-3 heading carrying a version token, a ✅/📋/🚧/🔄 marker, or the word "Milestone"). Restore ROADMAP.md by replacing the new section text with the original section text, then report and stop — do NOT update STATE.md and do NOT retry the write:

```
ERROR: edit rejected — milestone scope changed
Phase set before: {SCOPE_BEFORE phases} / after: {SCOPE_AFTER phases}
ROADMAP.md rolled back to the original section.
The updated phase text must not introduce a milestone-scoping heading; rewrite the offending line as plain text or a list item.
```

Exit.

If the milestone scope is unchanged, update STATE.md Roadmap Evolution:

```bash
gad_run query state.add-roadmap-evolution \
  --phase {target} \
  --action edited \
  --note "edited fields: {changed_field_list}"
```
</step>

<step name="completion">
Present completion summary:

```
Phase {target} updated in ROADMAP.md.

Fields changed: {changed_field_list}

---

## What's Next

- `/gad-progress` — view updated roadmap
- `/gad-plan-phase {target}` — re-plan this phase (if needed)
- `/gad-discuss-phase {target}` — discuss implementation approach

---
```
</step>

</process>

<anti_patterns>
- Don't renumber the phase — number and position must be preserved exactly
- Don't modify other phases when editing one
- Don't skip depends_on validation (invalid references block writes)
- Don't write without showing a diff and getting confirmation
- Don't edit in_progress/completed phases without --force
- Don't use raw Write on ROADMAP.md without reading it first; always replace section in place
- Don't modify the phase directory structure — only ROADMAP.md changes
- Don't introduce a milestone-scoping heading (level 1-3 with a version token, ✅/📋/🚧/🔄 marker, or "Milestone") in field values — it terminates the current milestone window; the post-write scope check rolls the edit back
- Don't commit the change — that's the user's decision
</anti_patterns>

<success_criteria>
Edit-phase is complete when:

- [ ] Phase {target} found and loaded from ROADMAP.md
- [ ] Status check performed; in_progress/completed blocked without --force
- [ ] Current values presented to user
- [ ] User chose edit mode (specific fields or full regeneration)
- [ ] depends_on references validated; invalid references blocked
- [ ] Diff shown and confirmed by user
- [ ] Updated phase written back in place; number, position, and status preserved
- [ ] Milestone scope verified unchanged after the write (rollback + error on mismatch)
- [ ] STATE.md Roadmap Evolution updated
- [ ] User informed of next steps
</success_criteria>
