<purpose>
Execute small, ad-hoc tasks with GAD guarantees (atomic commits, STATE.md tracking). Quick mode spawns gad-planner (quick mode) + gad-executor(s), tracks tasks in `.planning/quick/`, and updates STATE.md's "Quick Tasks Completed" table.

With `--full` flag: enables the complete quality pipeline — discussion + research + plan-checking + verification. One flag for everything.

With `--validate` flag: enables plan-checking (max 2 iterations) and post-execution verification only. Use when you want quality guarantees without discussion or research.

With `--discuss` flag: lightweight discussion phase before planning. Surfaces assumptions, clarifies gray areas, captures decisions in CONTEXT.md so the planner treats them as locked.

With `--research` flag: spawns a focused research agent before planning. Investigates implementation approaches, library options, and pitfalls. Use when you're unsure how to approach a task.

Granular flags are composable: `--discuss --research --validate` gives the same result as `--full`.
</purpose>

<required_reading>
Read all files referenced by the invoking prompt's execution_context before starting.
</required_reading>

<available_agent_types>
Valid GAD subagent types (use exact names — do not fall back to 'general-purpose'):
- gad-phase-researcher — Researches technical approaches for a phase
- gad-planner — Creates detailed plans from phase scope
- gad-plan-checker — Reviews plan quality before execution
- gad-executor — Executes plan tasks, commits, creates SUMMARY.md
- gad-verifier — Verifies phase completion, checks quality gates
- gad-code-reviewer — Reviews source files for bugs, security issues, and code quality
</available_agent_types>

<process>
**Step 1: Parse arguments and get task description**

Parse `$ARGUMENTS` for:
- `--full` flag → store `$FULL_MODE=true`, `$DISCUSS_MODE=true`, `$RESEARCH_MODE=true`, `$VALIDATE_MODE=true`
- `--validate` flag → store `$VALIDATE_MODE=true`
- `--discuss` flag → store `$DISCUSS_MODE=true`
- `--research` flag → store `$RESEARCH_MODE=true`
- Remaining text → use as `$DESCRIPTION` if non-empty

After parsing, normalize: if `$DISCUSS_MODE` and `$RESEARCH_MODE` and `$VALIDATE_MODE` are all true, set `$FULL_MODE=true`. This ensures `--discuss --research --validate` is treated identically to `--full`.

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; _gad_id_ok() { case "$("$1" runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') return 0;; *) return 1;; esac; }; _gad_homes() { _gad_at "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; elif _gad_homes; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; _gad_id_ok gad_run && GAD_IDENTITY_STATUS=ok; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
RESPONSE_LANGUAGE=$(gad_run query config-get response_language --raw --default "" 2>/dev/null || echo "")
```

**If `response_language` is set:** All user-facing output of this workflow — narration between tool calls, status updates, progress notes, findings, questions, prompts, and explanations — MUST be presented in `{response_language}`. Technical terms, code, file paths, and subagent prompts stay in English — only user-facing output is translated.

If `$DESCRIPTION` is empty after parsing, prompt user interactively:

**Text mode (`workflow.text_mode: true` in config or `--text` flag):** Set `TEXT_MODE=true` if `--text` is present in `$ARGUMENTS` OR `text_mode` from init JSON is `true`. When TEXT_MODE is active, replace every `AskUserQuestion` call with a plain-text numbered list and ask the user to type their choice number. This is required for non-Claude runtimes (OpenAI Codex, Antigravity, etc.) where `AskUserQuestion` is not available.

```
AskUserQuestion(
  header: "Quick Task",
  question: "What do you want to do?",
  followUp: null
)
```

Store response as `$DESCRIPTION`.

If still empty, re-prompt: "Please provide a task description."

Display banner based on active flags:

If `$FULL_MODE` (all phases enabled — `--full` or all granular flags):
```
### GAD ► QUICK TASK (FULL)

◆ Discussion + research + plan checking + verification enabled
```

If `$DISCUSS_MODE` and `$VALIDATE_MODE` (no research):
```
### GAD ► QUICK TASK (DISCUSS + VALIDATE)

◆ Discussion + plan checking + verification enabled
```

If `$DISCUSS_MODE` and `$RESEARCH_MODE` (no validate):
```
### GAD ► QUICK TASK (DISCUSS + RESEARCH)

◆ Discussion + research enabled
```

If `$RESEARCH_MODE` and `$VALIDATE_MODE` (no discuss):
```
### GAD ► QUICK TASK (RESEARCH + VALIDATE)

◆ Research + plan checking + verification enabled
```

If `$DISCUSS_MODE` only:
```
### GAD ► QUICK TASK (DISCUSS)

◆ Discussion phase enabled — surfacing gray areas before planning
```

If `$RESEARCH_MODE` only:
```
### GAD ► QUICK TASK (RESEARCH)

◆ Research phase enabled — investigating approaches before planning
```

If `$VALIDATE_MODE` only:
```
### GAD ► QUICK TASK (VALIDATE)

◆ Plan checking + verification enabled
```

---

**Step 2: Initialize**

```bash
DISCUSS_PARAM=""; if [[ "$ARGUMENTS" =~ (^|[[:space:]])--discuss([[:space:]]|$) ]]; then DISCUSS_PARAM="--discuss"; fi
RESEARCH_PARAM=""; if [[ "$ARGUMENTS" =~ (^|[[:space:]])--research([[:space:]]|$) ]]; then RESEARCH_PARAM="--research"; fi
VALIDATE_PARAM=""; if [[ "$ARGUMENTS" =~ (^|[[:space:]])--validate([[:space:]]|$) ]]; then VALIDATE_PARAM="--validate"; fi
FULL_PARAM=""; if [[ "$ARGUMENTS" =~ (^|[[:space:]])--full([[:space:]]|$) ]]; then FULL_PARAM="--full"; fi
INIT=$(gad_run query init.quick "$DESCRIPTION" $DISCUSS_PARAM $RESEARCH_PARAM $VALIDATE_PARAM $FULL_PARAM)
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
AGENT_SKILLS_PLANNER=$(gad_run query agent-skills gad-planner)
AGENT_SKILLS_EXECUTOR=$(gad_run query agent-skills gad-executor)
AGENT_SKILLS_CHECKER=$(gad_run query agent-skills gad-plan-checker)
AGENT_SKILLS_VERIFIER=$(gad_run query agent-skills gad-verifier)
AGENT_SKILLS_RESEARCHER=$(gad_run query agent-skills gad-phase-researcher)
```

Parse JSON for: `planner_model`, `executor_model`, `checker_model`, `verifier_model`, `reviewer_model`, `researcher_model`, `commit_docs`, `branch_name`, `quick_id`, `slug`, `date`, `timestamp`, `quick_dir`, `task_dir`, `roadmap_exists`, `planning_exists`, `response_language`.

`init.quick` does not emit dedicated `state_path`/`project_path` fields, so derive them from the already-absolute `quick_dir` (#2376 — files handed to a spawned subagent must resolve regardless of that subagent's own cwd):
```bash
STATE_PATH="$(dirname "${quick_dir}")/STATE.md"
PROJECT_PATH="$(dirname "${quick_dir}")/PROJECT.md"
```

```bash
USE_WORKTREES=$(gad_run query config-get workflow.use_worktrees --raw 2>/dev/null || echo "true")
RUNTIME=$(gad_run query config-get runtime --default claude --raw 2>/dev/null || echo "claude")
```

**Resolve isolation now (#2584/#2652).** Read @gad-core/references/dispatch-isolation-gate.md
and run its `Resolve ISOLATION`, `Single-agent dispatch sites`, and `Resolve the harness flag`
blocks in order; they set `ISOLATION`/`HARNESS_FLAG` via `query dispatch-isolation`.
`ISOLATION` — not `RUNTIME` — gates every worktree decision below. Substitute `{harnessFlag}`
in Step 6's `Agent()` with `$HARNESS_FLAG`+comma when `ISOLATION = "harness-worktree"`, else
empty. `{harnessFlag}`
is a template placeholder, not a shell variable.

If `USE_WORKTREES` is not `"false"`, run a startup orphan sweep before spawning any executors. This reaps locked worktrees whose lock-owner process is dead, whose branch is merged into the default branch, and whose lock file mtime is older than 5 minutes. Running it at startup prevents accumulation of orphaned worktrees from prior sessions that exited without cleanup (#3707).

```bash
if [ "$USE_WORKTREES" != "false" ]; then
  gad_run query worktree.reap-orphans 2>/dev/null || true
fi
```

If the project uses git submodules, worktree isolation is unsafe **only when the quick task touches a submodule path**. The previous behavior unconditionally disabled worktree isolation whenever `.gitmodules` existed, which penalised every quick task in a submodule project even when the task was nowhere near a submodule. Parse submodule paths from `.gitmodules` so the executor can act on actual submodule paths rather than the mere file's existence:

```bash
# Parse submodule paths from .gitmodules once (empty if no .gitmodules).
# SUBMODULE_PATHS is a newline-separated list of repo-relative paths used as
# a fail-loud commit-time guard inside the quick-task executor — if the
# executor stages any path that falls inside SUBMODULE_PATHS, it must abort
# the commit and surface the conflict rather than silently corrupting the
# submodule state.
if [ -f .gitmodules ]; then
  SUBMODULE_PATHS=$(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')
else
  SUBMODULE_PATHS=""
fi
```

Quick mode does not have a pre-declared `files_modified` list (the task is freeform), so use a fail-loud guard at commit time: when the executor stages files for the quick-task commit, if any staged path falls inside a `SUBMODULE_PATHS` entry, abort with a clear error explaining that worktree-isolated commits cannot safely span submodule boundaries — the user can re-run with `workflow.use_worktrees=false` to fall back to sequential execution on the main tree. If `SUBMODULE_PATHS` is empty (no `.gitmodules` in the repo), worktree isolation proceeds normally.

**If `roadmap_exists` is false:** Error — Quick mode requires an active project with ROADMAP.md. Run `/gad-new-project` first.

Quick tasks can run mid-phase - validation only checks ROADMAP.md exists, not phase status.

---

**Step 2.5: Handle quick-task branching**

**If `branch_name` is empty/null:** Skip and continue on the current branch.

**If `branch_name` is set:** Check out the quick-task branch before any planning commits.

The new branch must fork off the project's default branch (`origin/HEAD`), not
off whatever HEAD happens to be checked out — otherwise consecutive quick tasks
compound on top of each other and stay unpushed (#2916). If `$branch_name`
already exists locally, reuse it as-is so resumed work is not rebased.

```bash
DEFAULT_BRANCH=$(gad_run query git.base-branch 2>/dev/null \
  || git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' \
  || echo main)

if git show-ref --verify --quiet "refs/heads/$branch_name"; then
  git switch "$branch_name" \
    || { echo "ERROR: Could not switch to existing quick-task branch '$branch_name'." >&2; exit 1; }
else
  # Fetch the default branch so origin/$DEFAULT_BRANCH is current. If the fetch
  # fails (offline, no remote, auth failure) AND we have no local copy of
  # origin/$DEFAULT_BRANCH to fall back on, abort — creating the branch off
  # arbitrary HEAD is exactly the bug #2916 fixed.
  if ! git fetch --quiet origin "$DEFAULT_BRANCH"; then
    if ! git show-ref --verify --quiet "refs/remotes/origin/$DEFAULT_BRANCH"; then
      echo "ERROR: Could not fetch origin/$DEFAULT_BRANCH and no local copy exists. Refusing to create '$branch_name' off the current HEAD (#2916). Resolve the remote/network issue and retry." >&2
      exit 1
    fi
    echo "WARNING: git fetch origin $DEFAULT_BRANCH failed; using the local copy of origin/$DEFAULT_BRANCH as base." >&2
  fi

  if [ -n "$(git status --porcelain)" ]; then
    echo "WARNING: Uncommitted changes present. Carrying them onto the new quick-task branch — they will be branched off origin/$DEFAULT_BRANCH (not the previous-task HEAD)."
  else
    # Best-effort: fast-forward the local default branch so subsequent local
    # work sees the latest tip. Failure here is non-fatal because we always
    # create the new branch directly from origin/$DEFAULT_BRANCH below.
    git switch --quiet "$DEFAULT_BRANCH" 2>/dev/null \
      && git merge --ff-only --quiet "origin/$DEFAULT_BRANCH" 2>/dev/null \
      || true
  fi

  # Pin the new branch to origin/$DEFAULT_BRANCH so the start point is
  # deterministic regardless of which branch we are currently on (#2916).
  # On success HEAD is exactly at origin/$DEFAULT_BRANCH, so a post-creation
  # merge-base / "ahead-of" guard would be unreachable — the explicit base
  # argument here is the single source of correctness for #2916.
  # --no-track: with the default branch.autoSetupMerge=true, checkout -b from a
  # remote-tracking ref wires branch.<name>.merge to refs/heads/$DEFAULT_BRANCH
  # (origin/master), so a GUI sync pushes quick-task commits straight onto
  # origin/$DEFAULT_BRANCH, bypassing PR review (#2498).
  git checkout -b "$branch_name" "origin/$DEFAULT_BRANCH" --no-track \
    || { echo "ERROR: Could not create '$branch_name' from origin/$DEFAULT_BRANCH (#2916)." >&2; exit 1; }
fi
```

All quick-task commits for this run stay on that branch. User handles merge/rebase afterward.

---

**Step 3: Create task directory**

```bash
mkdir -p "${task_dir}"
```

---

**Step 4: Create quick task directory**

Create the directory for this quick task:

```bash
QUICK_DIR="${task_dir}"
mkdir -p "$QUICK_DIR"
```

Report to user:
```
Creating quick task ${quick_id}: ${DESCRIPTION}
Directory: ${QUICK_DIR}
```

Store `$QUICK_DIR` for use in orchestration.

---

**Step 4 ordering (#3894):** Check whether `workflow.research_before_questions` is enabled in `.planning/config.json` (or the config from init context) — the same check `/gad-discuss-phase` and `/gad-new-project` already make. When **enabled**, execute the research-phase section BELOW BEFORE the discussion-phase section: a gray-area answer given without research is written to `<quick_id>-CONTEXT.md` as a locked decision downstream agents are told not to revisit, so the evidence must come first. When **false or unset**, keep the written order (discussion, then research) — behavior unchanged.

If `section_manifest` is `null` or `"discussion-phase"` is in its `included` list: read and execute `gad-core/workflows/quick/steps/discussion-phase.md`. Otherwise skip — do not read the file.

---

If `section_manifest` is `null` or `"research-phase"` is in its `included` list: read and execute `gad-core/workflows/quick/steps/research-phase.md`. Otherwise skip — do not read the file.

---

**Step 5: Spawn planner (quick mode)**

**Capability gate:**
```bash
PLAN_PRE_HOOKS_JSON=$(gad_run loop render-hooks plan:pre --raw)
```

**Contribution dispatch (#3778):** read `PLAN_PRE_HOOKS_JSON.activeHooks` directly in context. In registry order, inject only active entries with `kind == "contribution"` and `into == "planner"` into each Quick planner prompt below, using `fragment.inline` verbatim plus resolved `configValues`. Do not paste `rendered`. Empty, inactive, incompatible, or non-planner entries inject nothing and do not error. Reuse this snapshot for revisions; do not render again.

**If `$VALIDATE_MODE`:** Use `quick-full` mode with stricter constraints.

**If NOT `$VALIDATE_MODE`:** Use standard `quick` mode.

Display: `◆ Spawning planner... (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze)`

```
Agent(
  prompt="
<planning_context>

**Mode:** ${VALIDATE_MODE ? 'quick-full' : 'quick'}
**Directory:** ${QUICK_DIR}
**Description:** ${DESCRIPTION}

<required_reading>
- ${STATE_PATH} (Project State)
- ./CLAUDE.md or ./.claude/CLAUDE.md (if exists — follow project-specific guidelines)
${DISCUSS_MODE ? '- ' + QUICK_DIR + '/' + quick_id + '-CONTEXT.md (User decisions — locked, do not revisit)' : ''}
${RESEARCH_MODE ? '- ' + QUICK_DIR + '/' + quick_id + '-RESEARCH.md (Research findings — use to inform implementation choices)' : ''}
</required_reading>

${AGENT_SKILLS_PLANNER}

**Project skills:** Check .claude/skills/ or .agents/skills/ directory (if either exists) — read SKILL.md files, plans should account for project skill rules

{For each active entry in `PLAN_PRE_HOOKS_JSON` where `kind == "contribution"` and `into == "planner"` (in array order): inject the entry's `fragment.inline` verbatim here, plus its resolved `configValues` when the entry carries them. If no active planner contributions exist, omit this block entirely.}

</planning_context>

<constraints>
- Create a SINGLE plan with 1-3 focused tasks
- Quick tasks should be atomic and self-contained
- PATH FORM (#4767): every path in the plan BODY — `files`, `verify`, `<automated>`, task actions — is repo-root-relative, and every `<automated>` command assumes cwd at the checkout root. Only the `<required_reading>` inputs above are absolute (#2376). An absolute path copied from this context into `<automated>` pins the command to THIS checkout; a worktree-isolated executor then runs it against the main tree and it passes on unchanged code.
- MUTABLE-SCOPE AUTHORITY (#3786): when concrete edit or verification scope depends on mutable external state (a merge index, PR/base diffs, the working tree), authorize scope ONLY from a live observation made at planning time — for conflict resolution that is the fresh merge index via `git diff --name-only --diff-filter=U` — or keep `files`/`verify` CONDITIONAL on that observation. Historical STATE.md entries, recovery notes, and cached PR/base diff paths may guide investigation only; they are never edit or verification authority, and a plan must not enumerate them as authorized files "pending replacement".
${RESEARCH_MODE ? '- Research findings are available — use them to inform library/pattern choices' : '- No research phase'}
${VALIDATE_MODE ? '- Target ~40% context usage (structured for verification)' : '- Target ~30% context usage (simple, focused)'}
${VALIDATE_MODE ? '- MUST generate `must_haves` in plan frontmatter (truths, artifacts, key_links)' : ''}
${VALIDATE_MODE ? '- Each task MUST have `files`, `action`, `verify`, `done` fields' : ''}
</constraints>

<output>
Write plan to: ${QUICK_DIR}/${quick_id}-PLAN.md
Return: ## PLANNING COMPLETE with plan path
</output>
",
  subagent_type="gad-planner",
  model="{planner_model}",
  description="Quick plan: ${DESCRIPTION}"
)
```

> **ORCHESTRATOR RULE — CODEX RUNTIME**: After calling Agent() above, stop working on this task immediately. Do not read more files, edit code, or run tests related to this task while the subagent is active. Wait for the subagent to return its result. This prevents duplicate work, conflicting edits, and wasted context. Only resume when the subagent result is available.

After planner returns:
1. Verify plan exists at `${QUICK_DIR}/${quick_id}-PLAN.md`
2. Extract plan count (typically 1 for quick tasks)
3. Report: "Plan created: ${QUICK_DIR}/${quick_id}-PLAN.md"

If plan not found, error: "Planner failed to create ${quick_id}-PLAN.md"

---

If `section_manifest` is `null` or `"plan-checker-loop"` is in its `included` list: read and execute `gad-core/workflows/quick/steps/plan-checker-loop.md`. Otherwise skip — do not read the file.

---

If `section_manifest` is `null` or `"worktree-pre-dispatch-commit"` is in its `included` list: read and execute `gad-core/workflows/quick/steps/worktree-pre-dispatch-commit.md`. Otherwise skip — do not read the file.

---

**Step 6: Spawn executor**

Auto-degrade to sequential if HEAD has diverged from the worktree fork base (#1941, mirrors
execute-phase's #683/#1369 guard). Claude Code's `isolation="worktree"` forks new worktrees from
`origin/HEAD`, not the live local HEAD. If a prior quick task in this session (or the Step 5.6
pre-dispatch plan commit above) advanced local HEAD without an intervening `git push`,
`origin/HEAD` stays pinned to a stale ancestor and the executor's `worktree_branch_check` guard
halts with a base-mismatch fatal — potentially many commits behind, not just one. Run this check
immediately before capturing `EXPECTED_BASE` so it reflects the most current local state.

```bash
if [ "$ISOLATION" = "harness-worktree" ] && [ "${USE_WORKTREES:-true}" != "false" ]; then
  _QUICK_SHOULD_DEGRADE=$(gad_run query worktree.base-check --mode "$ISOLATION" --pick shouldDegrade 2>/dev/null || true)
  if [ "$_QUICK_SHOULD_DEGRADE" = "true" ]; then
    _QUICK_DEGRADE_MSG=$(gad_run query worktree.base-check --mode "$ISOLATION" --pick message 2>/dev/null || true)
    [ -n "$_QUICK_DEGRADE_MSG" ] && printf '%s\n' "$_QUICK_DEGRADE_MSG" >&2
    echo "⚠ [#1941] Worktree fork base diverged from orchestrator HEAD — auto-degrading to sequential mode for this quick task to avoid a base-mismatch halt." >&2
    USE_WORKTREES=false
    ISOLATION=none
  fi
fi

# Re-resolve (and, as a side effect, re-persist) now that the base-check
# auto-degrade above may have changed $ISOLATION since the Step 2 gate's
# `dispatch-isolation` call (#3045). That first call recorded the NATURALLY
# resolved mode into the run-scoped sentinel the isolation guard hooks read
# (hooks/gad-agent-isolation-guard.js, hooks/gad-cursor-subagent-start.js via
# hooks/lib/isolation-sentinel.js). The degrade above is decided HERE, in
# shell — the resolver cannot see it — so without this the sentinel still
# asserts `harness-worktree` while the dispatch below correctly omits the
# harness flag, and the guard denies the dispatch with exit 2. `--force-isolation`
# pushes the FINAL, shell-computed value through that SAME single write path
# (`none` also clears the stored harnessFlag, since none applies to sequential
# dispatch). Best-effort: a write failure here must never fail the task — the
# guards' own sentinel-absent fallback is safe, just less precise.
gad_run query dispatch-isolation --raw --force-isolation "$ISOLATION" >/dev/null 2>&1 || true
```

Capture current HEAD before spawning (used for worktree branch check):
```bash
EXPECTED_BASE=$(git rev-parse HEAD)
if [ "$ISOLATION" = "harness-worktree" ]; then   # keyed on ISOLATION like every other dispatch-coupled branch (#2652)
  # BSD/macOS mktemp only randomizes XXXXXX when it is the final path component, so make a
  # suffixless temp then append the extension — portable across BSD + GNU (#1520).
  QUICK_WORKTREE_MANIFEST=$(mktemp "${TMPDIR:-/tmp}/gad-quick-worktree-XXXXXX") && mv "$QUICK_WORKTREE_MANIFEST" "${QUICK_WORKTREE_MANIFEST}.json" && QUICK_WORKTREE_MANIFEST="${QUICK_WORKTREE_MANIFEST}.json" || exit 1
  printf '{"worktrees":[]}\n' > "$QUICK_WORKTREE_MANIFEST"
  export QUICK_WORKTREE_MANIFEST
fi
```

Spawn gad-executor with plan reference:

```
Agent(
  prompt="
Execute quick task ${quick_id}.

${ISOLATION === "harness-worktree" ? `
<worktree_branch_check>
ORCHESTRATOR build-time embed (NOT a sub-agent runtime step): before this dispatch, read \`gad-core/references/worktree-branch-check.md\`, substitute \`{EXPECTED_BASE}\` with the base SHA captured above (${EXPECTED_BASE}), substitute \`{EXPECTED_BASE_ALTERNATE}\` with \`${QUICK_PLAN_PARENT}\` when it differs from \`${EXPECTED_BASE}\` (otherwise empty), and replace this note with that fragment's \`<worktree_branch_check>\` block so the dispatched prompt carries the runnable guard verbatim — do not pass this instruction through in its place.
</worktree_branch_check>

FIRST ACTION after the worktree branch check: ensure the quick PLAN.md exists at a worktree-rooted relative path before any Read/Edit/Write path can be primed. If \`${QUICK_DIR}/${quick_id}-PLAN.md\` is absent, materialize it from the shared git object store:

\`\`\`bash
QUICK_PLAN_COMMIT="${QUICK_PLAN_COMMIT}"
QUICK_PLAN_PATH="${QUICK_DIR}/${quick_id}-PLAN.md"
if [ ! -f "$QUICK_PLAN_PATH" ]; then
  mkdir -p "$(dirname "$QUICK_PLAN_PATH")"
  git show "${QUICK_PLAN_COMMIT}:${QUICK_PLAN_PATH}" > "$QUICK_PLAN_PATH" || {
    echo "FATAL: unable to materialize quick plan from ${QUICK_PLAN_COMMIT}:${QUICK_PLAN_PATH}; refusing to continue." >&2
    exit 42
  }
fi
\`\`\`
` : ''}

<required_reading>
- ${QUICK_DIR}/${quick_id}-PLAN.md (Plan)
- ${STATE_PATH} (Project state)
- ./CLAUDE.md or ./.claude/CLAUDE.md (Project instructions, if exists)
- .claude/skills/ or .agents/skills/ (Project skills, if either exists — list skills, read SKILL.md for each, follow relevant rules during implementation)
</required_reading>

${AGENT_SKILLS_EXECUTOR}

<submodule_commit_guard>
SUBMODULE_PATHS for this project: ${SUBMODULE_PATHS}

If SUBMODULE_PATHS is non-empty, you MUST run this fail-loud guard immediately
before EVERY git commit you create during this quick task (after \`git add\`,
before \`git commit\`). Quick mode does not have a pre-declared files_modified
list, so the guard runs at commit time:

\`\`\`bash
SUBMODULE_PATHS=\"${SUBMODULE_PATHS}\"
if [ -n \"\$SUBMODULE_PATHS\" ]; then
  STAGED=\$(git diff --cached --name-only)
  for sm_raw in \$SUBMODULE_PATHS; do
    sm=\"\${sm_raw#./}\"
    sm=\"\${sm%/}\"
    [ -z \"\$sm\" ] && continue
    for f_raw in \$STAGED; do
      f=\"\${f_raw#./}\"
      f=\"\${f%/}\"
      case \"\$f\" in
        \"\$sm\"|\"\$sm\"/*)
          echo \"ABORT: staged path \$f_raw falls inside submodule \$sm — worktree-isolated commits cannot safely span submodule boundaries. Re-run with workflow.use_worktrees=false.\" >&2
          exit 1 ;;
      esac
    done
  done
fi
\`\`\`

If the guard aborts, do NOT attempt the commit, do NOT remove the staged files,
and do NOT continue subsequent tasks. Surface the abort message in your
SUMMARY.md and stop — the user must rerun with worktrees disabled.
</submodule_commit_guard>

<constraints>
- Execute all tasks in the plan
- Commit each task atomically (code changes only)
- Run the <submodule_commit_guard> bash block before every \`git commit\` if SUBMODULE_PATHS is non-empty
- Create summary at: ${QUICK_DIR}/${quick_id}-SUMMARY.md with `status: complete` in SUMMARY frontmatter (required so the audit-open milestone-close scanner recognises the task as done, not [unknown])
- Do NOT commit docs artifacts (SUMMARY.md, STATE.md, PLAN.md) — the orchestrator handles the docs commit in Step 8
- Do NOT update ROADMAP.md (quick tasks are separate from planned phases)
</constraints>
",
  subagent_type="gad-executor",
  model="{executor_model}",
  {harnessFlag}
  description="Execute: ${DESCRIPTION}"
)
```

> **ORCHESTRATOR RULE — CODEX RUNTIME**: After calling Agent() above, stop working on this task immediately. Do not read more files, edit code, or run tests related to this task while the subagent is active. Wait for the subagent to return its result. This prevents duplicate work, conflicting edits, and wasted context. Only resume when the subagent result is available.

If the executor ran isolated (`ISOLATION = "harness-worktree"` at dispatch), append its returned `{agent_id, worktree_path, branch, expected_base, allowed_bases}` metadata to `QUICK_WORKTREE_MANIFEST` before cleanup. Set `expected_base` to `${EXPECTED_BASE}` and `allowed_bases` to `["${EXPECTED_BASE}", "${QUICK_PLAN_PARENT}"]` with duplicates removed. If any required field is unavailable, stop and ask for recovery; do not discover global worktrees.

After executor returns:
1. **Worktree cleanup:** If the executor ran isolated (`ISOLATION = "harness-worktree"` at dispatch), merge the worktree branch back and clean up:
   ```bash
   QUICK_WORKTREE_MANIFEST=${QUICK_WORKTREE_MANIFEST:-$WAVE_WORKTREE_MANIFEST}
   [ -n "${QUICK_WORKTREE_MANIFEST:-}" ] && [ -f "$QUICK_WORKTREE_MANIFEST" ] || {
     echo "BLOCKED: missing QUICK_WORKTREE_MANIFEST; refusing broad worktree cleanup (#3384)." >&2
     exit 1
   }

   # Prefer the bounded cleanup helper. It verifies branch identity, expected
   # base, deletion diffs, merge result, and worktree removal before branch
   # deletion. If it blocks, resolve the reported manifest entry and rerun.
   # Fail closed: SDK refusal (safety guard #3174/#3384) must surface — do not swallow exit 1.
   gad_run query worktree.cleanup-wave --manifest "$QUICK_WORKTREE_MANIFEST" || exit 1
   ```
   If `ISOLATION` was not `"harness-worktree"` at dispatch (including a #1941 base-check degrade — that is *this* file's degrade; #2649 is the `diagnose-issues.md` / `execute-plan.md` one), skip this step.

   > **ISOLATED-RUN RECOVERY — FAIL SAFE (#1292):** When an isolated (worktree) run is *rejected* — the user declines to merge it, the orchestrator surfaces recovery guidance for a blocked/halted plan, or the run over-reached the requested scope — the worktree-isolation contract MUST hold through recovery. Do **NOT** propose continuing on `main`/the primary checkout as the default or recommended recovery path. Default to a **safe halt** and offer: (a) re-attempt in a **fresh, narrowly-scoped worktree**, or (b) inspect or discard the rejected worktree without merging. Any path that edits the primary checkout requires an **explicit, clearly-labeled confirmation** from the user first — editing `main` directly is never the proposed or default option for a run the user configured to be isolated.

2. Verify summary exists at `${QUICK_DIR}/${quick_id}-SUMMARY.md`
3. Extract commit hash from executor output
4. Report completion status

**Known Claude Code bug (classifyHandoffIfNeeded):** If executor reports "failed" with error `classifyHandoffIfNeeded is not defined`, this is a Claude Code runtime bug — not a real failure. Check if summary file exists and git log shows commits. If so, treat as successful.

If summary not found, error: "Executor failed to create ${quick_id}-SUMMARY.md"

Note: For quick tasks producing multiple plans (rare), spawn executors in parallel waves per execute-phase patterns.

---

**Step 6.25: Code review (auto)**

Skip this step entirely if `$FULL_MODE` is false.

**Capability gate:**
```bash
EXECUTE_POST_HOOKS_JSON=$(gad_run loop render-hooks execute:post --raw)
```

**Generic step dispatch (#3606):** dispatch every `kind == "step"` hook from `EXECUTE_POST_HOOKS_JSON` per @gad-core/references/loop-hook-dispatch.md (skip silently when none); each step is advisory and best-effort. The code-review specialization below is one such hook, not a replacement for the generic dispatch.

Resolve active step hooks from `EXECUTE_POST_HOOKS_JSON` where `kind == "step"` and `ref.skill == "code-review"`.

If no active code-review step hook exists, skip with message "Code review skipped (code-review capability inactive)" — after dispatching any other active step hooks above — and proceed.

**Scope files from executor's commits:**
```bash
# Find the diff base: last commit before quick task started
# Use git log to find commits referencing the quick task id, then take the parent of the oldest
QUICK_COMMITS=$(git log --oneline --format="%H" --grep="${quick_id}" 2>/dev/null)
if [ -n "$QUICK_COMMITS" ]; then
  DIFF_BASE=$(echo "$QUICK_COMMITS" | tail -1)^
  # Verify parent exists (guard against first commit in repo)
  git rev-parse "${DIFF_BASE}" >/dev/null 2>&1 || DIFF_BASE=$(echo "$QUICK_COMMITS" | tail -1)
else
  # No commits found for this quick task — skip review
  DIFF_BASE=""
fi

if [ -n "$DIFF_BASE" ]; then
  # #4466: bound the tip at the quick task's own last commit, not HEAD --
  # QUICK_COMMITS is already the complete, newest-first list of this task's
  # commits, so its first line is the correct tip. An unbounded `..HEAD`
  # picks up any later commit landed on the same tree in the window between
  # this task's commits and this review step (worktree merge-back, a shared
  # tree, another session) and folds it into this task's own review scope.
  QUICK_TIP=$(echo "$QUICK_COMMITS" | head -1)
  CHANGED_FILES=$(git diff --name-only "${DIFF_BASE}..${QUICK_TIP}" -- . ':!.planning' 2>/dev/null | tr '\n' ' ')
else
  CHANGED_FILES=""
fi
```

If `CHANGED_FILES` is empty, skip with "No source files changed — skipping code review."

**Invoke review:**
```
Agent(
  prompt="Review these files for bugs, security issues, and code quality.
  Files: ${CHANGED_FILES}
  Output: ${QUICK_DIR}/${quick_id}-REVIEW.md
  Depth: quick",
  subagent_type="gad-code-reviewer",
  model="{reviewer_model}"
)
```

> **ORCHESTRATOR RULE — CODEX RUNTIME**: After calling Agent() above, stop working on this task immediately. Do not read more files, edit code, or run tests related to this task while the subagent is active. Wait for the subagent to return its result. This prevents duplicate work, conflicting edits, and wasted context. Only resume when the subagent result is available.

If review produces findings, display advisory message. **Error handling:** Failures are non-blocking — catch and proceed.

---

If `section_manifest` is `null` or `"quick-verification"` is in its `included` list: read and execute `gad-core/workflows/quick/steps/quick-verification.md`. Otherwise skip — do not read the file.

---

**Step 7: Update STATE.md**

Update STATE.md with quick task completion record.

**7a. Check if "Quick Tasks Completed" section exists:**

Read STATE.md and check for `### Quick Tasks Completed` section.

**7b. If section doesn't exist, create it:**

Insert after `### Blockers/Concerns` section:

**If `$VALIDATE_MODE`:**
```markdown
### Quick Tasks Completed

| # | Description | Date | Commit | Status | Directory |
|---|-------------|------|--------|--------|-----------|
```

**If NOT `$VALIDATE_MODE`:**
```markdown
### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
```

**Note:** If the table already exists in a legacy (pre-registry) column format, first run `gad_run quick-tasks-migrate` — the maintainer-decided repair path (#3730) that rewrites the table onto the canonical schema, losslessly bucketing unmapped columns into Description. It is a silent no-op when the table is already canonical or the section is absent, so running it before the first append of every quick task migrates exactly once and never prompts otherwise. After migration, use the canonical column format below.

**7c. Append new row to table:**

Append the row through the schema-backed `gad_run quick-tasks-append` command (`appendQuickTaskRow`,
#2133/#3356, ADR-2143 §3/§7) rather than authoring the row as raw markdown — this shares the exact
escaping the reader (`parseMarkdownTable`) requires, so a `${DESCRIPTION}` containing a literal `|`
(a Jinja filter, an Ansible task name) can never permanently rag the table (#4906 Phase 3, #4736).
Do NOT use the Edit tool to write this row directly; that raw-interpolation path is the defect this
step now avoids.

**If `$VALIDATE_MODE` (or table has Status column):**
```bash
gad_run quick-tasks-append --quick-id "${quick_id}" --slug "${slug}" --task "${DESCRIPTION}" --status "${VERIFICATION_STATUS}"
```

**If NOT `$VALIDATE_MODE` (and table has no Status column):**
```bash
gad_run quick-tasks-append --quick-id "${quick_id}" --slug "${slug}" --task "${DESCRIPTION}"
```

Both forms emit the row this step previously authored by hand: `--quick-id`/`--slug` derive the same
`[${quick_id}-${slug}](./quick/${quick_id}-${slug}/)` permalink (#3356), and `date`/commit are
computed by the command itself — from the current day and the current `HEAD` (already the executor's
own commit from Step 6 at this point in the workflow) — never passed explicitly. For a schema-safe
append outside this workflow, with neither a quick id nor a task directory (e.g. `fast.md`),
`gad_run quick-tasks-append --task <text>` alone remains the fallback shape (#2133) — the `#` cell is
a positional ordinal and `Directory` reads `—`.

**7d. Update "Last activity" line:**

Use `date` from init:
```
Last activity: ${date} - Completed quick task ${quick_id}: ${DESCRIPTION}
```

Use the Edit tool for 7a/7b/7d (section creation and the Last activity line). 7c above writes through `gad_run quick-tasks-append`, not the Edit tool.

---

**Step 8: Final commit and completion**

Stage and commit quick task artifacts. This step MUST always run — even if the executor already committed some files (e.g. when running without worktree isolation). The `gad_run query commit` command handles already-committed files gracefully.

Build file list:
- `${QUICK_DIR}/${quick_id}-PLAN.md`
- `${QUICK_DIR}/${quick_id}-SUMMARY.md`
- `.planning/STATE.md`
- If `$DISCUSS_MODE` and context file exists: `${QUICK_DIR}/${quick_id}-CONTEXT.md`
- If `$RESEARCH_MODE` and research file exists: `${QUICK_DIR}/${quick_id}-RESEARCH.md`
- If `$VALIDATE_MODE` and verification file exists: `${QUICK_DIR}/${quick_id}-VERIFICATION.md`
- If `${QUICK_DIR}/${quick_id}-deferred-items.md` exists: `${QUICK_DIR}/${quick_id}-deferred-items.md`

```bash
# Explicitly stage all artifacts before commit — PLAN.md may be untracked
# if the executor ran without worktree isolation and committed docs early
# Filter .planning/ files from staging if commit_docs is disabled (#1783)
COMMIT_DOCS=$(gad_run query config-get commit_docs --raw 2>/dev/null || echo "true")
if [ "$COMMIT_DOCS" = "false" ]; then
  file_list_filtered=$(echo "${file_list}" | tr ' ' '\n' | grep -v '^\.planning/' | tr '\n' ' ')
  git add ${file_list_filtered} 2>/dev/null
else
  git add ${file_list} 2>/dev/null
fi
gad_run query commit "docs(quick-${quick_id}): ${DESCRIPTION}" --files ${file_list}
```

Get final commit hash:
```bash
commit_hash=$(git rev-parse --short HEAD)
```

Display completion output:

**If `$VALIDATE_MODE`:**
```
---

GAD > QUICK TASK COMPLETE (VALIDATED)

Quick Task ${quick_id}: ${DESCRIPTION}

${RESEARCH_MODE ? 'Research: ' + QUICK_DIR + '/' + quick_id + '-RESEARCH.md' : ''}
Summary: ${QUICK_DIR}/${quick_id}-SUMMARY.md
Verification: ${QUICK_DIR}/${quick_id}-VERIFICATION.md (${VERIFICATION_STATUS})
Commit: ${commit_hash}

---

Ready for next task: /gad-quick ${GAD_WS}
```

**If NOT `$VALIDATE_MODE`:**
```
---

GAD > QUICK TASK COMPLETE

Quick Task ${quick_id}: ${DESCRIPTION}

${RESEARCH_MODE ? 'Research: ' + QUICK_DIR + '/' + quick_id + '-RESEARCH.md' : ''}
Summary: ${QUICK_DIR}/${quick_id}-SUMMARY.md
Commit: ${commit_hash}

---

Ready for next task: /gad-quick ${GAD_WS}
```

</process>

<success_criteria>
- [ ] ROADMAP.md validation passes
- [ ] User provides task description
- [ ] `--full`, `--validate`, `--discuss`, and `--research` flags parsed from arguments when present
- [ ] `--full` sets all booleans (`$FULL_MODE`, `$DISCUSS_MODE`, `$RESEARCH_MODE`, `$VALIDATE_MODE`)
- [ ] Slug generated (lowercase, hyphens, max 40 chars)
- [ ] Quick ID generated (YYMMDD-xxx format, 2s Base36 precision)
- [ ] Directory created at `.planning/quick/YYMMDD-xxx-slug/`
- [ ] (--discuss) Gray areas identified and presented, decisions captured in `${quick_id}-CONTEXT.md`
- [ ] (--research) Research agent spawned, `${quick_id}-RESEARCH.md` created
- [ ] `${quick_id}-PLAN.md` created by planner (honors CONTEXT.md decisions when --discuss, uses RESEARCH.md findings when --research)
- [ ] (--validate) Plan checker validates plan, revision loop capped at 2
- [ ] `${quick_id}-SUMMARY.md` created by executor
- [ ] (--validate) `${quick_id}-VERIFICATION.md` created by verifier
- [ ] STATE.md updated with quick task row (Status column when --validate)
- [ ] Artifacts committed
</success_criteria>
