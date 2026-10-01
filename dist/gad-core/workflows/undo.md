<purpose>
Safe git revert workflow. Rolls back GAD phase or plan commits using the phase manifest with dependency checks and a confirmation gate. Uses git revert --no-commit (NEVER git reset) to preserve history.
</purpose>

<required_reading>
@~/.claude/gad-core/references/ui-brand.md
@~/.claude/gad-core/references/gate-prompts.md
</required_reading>

<process>
```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
RESPONSE_LANGUAGE=$(gad_run query config-get response_language --raw --default "" 2>/dev/null || echo "")
```

**If `response_language` is set:** All user-facing output of this workflow — narration between tool calls, status updates, progress notes, findings, questions, prompts, and explanations — MUST be presented in `{response_language}`. Technical terms, code, file paths, and subagent prompts stay in English — only user-facing output is translated.

<step name="banner" priority="first">
Display the stage banner:

```
### GAD ► UNDO
```
</step>

<step name="parse_arguments">
Parse $ARGUMENTS for the undo mode:

- `--last N` → MODE=last, COUNT=N (integer, default 10 if N missing)
- `--phase NN` → MODE=phase, TARGET_PHASE=NN (two-digit phase number)
- `--plan NN-MM` → MODE=plan, TARGET_PLAN=NN-MM (phase-plan ID)

If no valid argument is provided, display usage and exit:

```
Usage: /gad-undo --last N | --phase NN | --plan NN-MM

Modes:
  --last N      Show last N GAD commits for interactive selection
  --phase NN    Revert all commits for phase NN
  --plan NN-MM  Revert all commits for plan NN-MM

Examples:
  /gad-undo --last 5
  /gad-undo --phase 03
  /gad-undo --plan 03-02
```
</step>

<step name="gather_commits">
Based on MODE, gather candidate commits.

**MODE=last:**

Run:
```bash
git log --oneline --no-merges -${COUNT}
```

Filter for GAD conventional commits matching `type(scope): message` pattern (e.g., `feat(04-01):`, `docs(03):`, `fix(02-03):`).

Display a numbered list of matching commits:
```
Recent GAD commits:
  1. abc1234 feat(04-01): implement auth endpoint
  2. def5678 docs(03-02): complete plan summary
  3. ghi9012 fix(02-03): correct validation logic
```

**Text mode (`workflow.text_mode: true` in config or `--text` flag):** Set `TEXT_MODE=true` if `--text` is present in `$ARGUMENTS` OR `text_mode` from init JSON is `true`. When TEXT_MODE is active, replace every `AskUserQuestion` call with a plain-text numbered list and ask the user to type their choice number. This is required for non-Claude runtimes (OpenAI Codex, Gemini CLI, etc.) where `AskUserQuestion` is not available.
Use AskUserQuestion to ask:
- question: "Which commits to revert? Enter numbers (e.g., 1,3) or 'all'"
- header: "Select"

Parse the user's selection into COMMITS list.

---

**MODE=phase:**

Read `.planning/.phase-manifest.json` if it exists.

If the file exists and `manifest.phases?.[TARGET_PHASE]?.commits` is a non-empty array:
  - Use `manifest.phases[TARGET_PHASE].commits` entries as COMMITS (each entry is a commit hash)

If the file does not exist, or `manifest.phases?.[TARGET_PHASE]` is missing:
  - Display: "Manifest has no entry for phase ${TARGET_PHASE} (or file missing), falling back to git log search"
  - Fallback: run git log and filter for the target phase scope:
    ```bash
    git log --oneline --no-merges --all | grep -E "\(0*${TARGET_PHASE}(-[0-9]+)?\):" | head -50
    ```
  - Use matching commits as COMMITS

---

**MODE=plan:**

Run:
```bash
git log --oneline --no-merges --all | grep -E "\(${TARGET_PLAN}\)" | head -50
```

Use matching commits as COMMITS.

---

**Empty check:**

If COMMITS is empty after gathering:
```
No commits found for ${MODE} ${TARGET}. Nothing to revert.
```
Exit cleanly.
</step>

<step name="dependency_check">
**Applies when MODE=phase or MODE=plan.**

Skip this step entirely for MODE=last.

---

**MODE=phase:**

Read `.planning/ROADMAP.md` inline.

Search for phases that list a dependency on the target phase. Look for patterns like:
- "Depends on: Phase ${TARGET_PHASE}"
- "Depends on: ${TARGET_PHASE}"
- "depends_on: [${TARGET_PHASE}]"

For each dependent phase N found:
1. Check if `.planning/phases/${N}-*/` directory exists
2. If directory exists, check for any PLAN.md or SUMMARY.md files inside it

If any downstream phase has started work, collect warnings:
```
⚠  Downstream dependency detected:
   Phase ${N} depends on Phase ${TARGET_PHASE} and has started work.
```

---

**MODE=plan:**

Extract the phase number from TARGET_PLAN (the NN part of NN-MM). Extract the plan number (the MM part).

Look for later plans in the same phase directory (`.planning/phases/${NN}-*/`). For each later plan (plans with number > MM):
1. Read the later plan's PLAN.md
2. Check if its `<files>` sections or `consumes` fields reference outputs from the target plan

If any later plan references the target plan's outputs, collect warnings:
```
⚠  Intra-phase dependency detected:
   Plan ${LATER_PLAN} in phase ${NN} references outputs from plan ${TARGET_PLAN}.
```

---

If any warnings exist (from either mode):
- Display all warnings
- Use AskUserQuestion with approve-revise-abort pattern:
  - question: "Downstream work depends on the target being reverted. Proceed anyway?"
  - header: "Confirm"
  - options: Proceed | Abort

If user selects "Abort": exit with "Revert cancelled. No changes made."
</step>

<step name="confirm_revert">
Display the confirmation gate using approve-revise-abort pattern from gate-prompts.md.

Show:
```
The following commits will be reverted (in reverse chronological order):

  {hash} — {message}
  {hash} — {message}
  ...

Total: {N} commit(s) to revert
```

Use AskUserQuestion:
- question: "Proceed with revert?"
- header: "Approve?"
- options: Approve | Abort

If "Abort": display "Revert cancelled. No changes made." and exit.
If "Approve": ask for a reason:

```
AskUserQuestion(
  header: "Reason",
  question: "Brief reason for the revert (used in commit message):",
  options: []
)
```

Store the response as REVERT_REASON. Continue to execute_revert.
</step>

<step name="execute_revert">
**HARD CONSTRAINT: Use git revert --no-commit. NEVER use git reset (except for conflict cleanup as documented below).**

**Dirty-tree guard (run first, before any revert):**

Run `git status --porcelain`. If the output is non-empty, display the dirty files and abort:
```
Working tree has uncommitted changes. Commit or stash them before running /gad-undo.
```
Exit immediately — do not proceed to any revert operations.

---

Sort COMMITS in reverse chronological order (newest first). If commits came from git log (already newest-first), they are already in correct order.

For each commit hash in COMMITS:
```bash
git revert --no-commit ${HASH}
```

If any revert fails (merge conflict or error):
1. Display the error message
2. Run cleanup — handle both first-call and mid-sequence cases:
   ```bash
   # Try git revert --abort first (works if this is the first failed revert)
   git revert --abort 2>/dev/null
   # If prior --no-commit reverts already staged cleanly before this failure,
   # revert --abort may be a no-op. Clean up staged and working tree changes:
   git reset HEAD 2>/dev/null
   git restore . 2>/dev/null
   ```
3. Display:
   ```
### ERROR

   Revert failed on commit ${HASH}.
   Likely cause: merge conflict with subsequent changes.

   **To fix:** Resolve the conflict manually or revert commits individually.
   All pending reverts have been aborted — working tree is clean.
   ```
4. Exit with error.

After all reverts are staged successfully, create a single commit:

For MODE=phase:
```bash
git commit -m "revert(${TARGET_PHASE}): undo phase ${TARGET_PHASE} — ${REVERT_REASON}"
```

For MODE=plan:
```bash
git commit -m "revert(${TARGET_PLAN}): undo plan ${TARGET_PLAN} — ${REVERT_REASON}"
```

For MODE=last:
```bash
git commit -m "revert: undo ${N} selected commits — ${REVERT_REASON}"
```
</step>

<step name="summary">
Display the completion banner:

```
### GAD ► UNDO COMPLETE ✓
```

Show summary:
```
  ✓ ${N} commit(s) reverted
  ✓ Single revert commit created: ${REVERT_HASH}
```

Show next steps:
```
---

## ▶ Next Up — [${PROJECT_CODE}] ${PROJECT_TITLE}

**Review state** — verify project is in expected state after revert

/clear then:

/gad-progress

---

**Also available:**
- `/gad-execute-phase ${PHASE}` — re-execute if needed
- `/gad-undo --last 1` — undo the revert itself if something went wrong

---
```
</step>

</process>

<success_criteria>
- [ ] Arguments parsed correctly for all three modes
- [ ] --phase mode reads .planning/.phase-manifest.json using manifest.phases[TARGET_PHASE].commits
- [ ] --phase mode falls back to git log if manifest entry missing
- [ ] Dependency check warns when downstream phases have started (MODE=phase)
- [ ] Dependency check warns when later plans reference target plan outputs (MODE=plan)
- [ ] Dirty-tree guard aborts if working tree has uncommitted changes
- [ ] Confirmation gate shown before any revert execution
- [ ] Reverts use git revert --no-commit in reverse chronological order
- [ ] Single commit created after all reverts staged
- [ ] Error handling cleans up both first-call and mid-sequence conflict cases
- [ ] git reset --hard is NEVER used anywhere in this workflow
</success_criteria>
