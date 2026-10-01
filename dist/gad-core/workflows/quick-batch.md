@~/.claude/gad-core/references/response-language-directive.md
<purpose>
Batch several `/gad-quick`-shaped tasks together (#3676, epic #3344, ADR-1239
"Quick-batch binding"). ONE coordinator (this workflow) owns every shared
write — `BATCH.json`, STATE.md, worktree create/merge/cleanup — and never
delegates them to a leaf. Leaves (planner/researcher/checker/executor/
verifier) return structured results only; they never invoke `/gad-quick`,
never touch `BATCH.json`, and never write STATE.md/ROADMAP.md themselves
(single-writer invariant).

Dispatch decisions (effective concurrency, deterministic merge order, spawn
backpressure, failure/verification routing) are computed by the pure
`quick-batch-dispatch.cts` module (via the `quick-batch` CLI verbs) — this
workflow never re-derives that logic inline.
</purpose>

<required_reading>
Read all files referenced by the invoking prompt's execution_context before starting.
</required_reading>

<available_agent_types>
Valid GAD subagent types (use exact names — do not fall back to 'general-purpose'):
- gad-phase-researcher — Researches technical approaches for an item
- gad-planner — Creates a plan for one item (`quick-batch` mode)
- gad-plan-checker — Reviews one item's plan before execution
- gad-executor — Executes one item's plan, commits, creates SUMMARY.md
- gad-verifier — Verifies one item's goal achievement
</available_agent_types>

<process>
**Step 1: Parse arguments, resolve mode**

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
RESPONSE_LANGUAGE=$(gad_run query config-get response_language --raw --default "" 2>/dev/null || echo "")
```

**If `response_language` is set:** all user-facing questions/prompts/explanations MUST be presented in `{response_language}`. Technical terms, code, file paths, and subagent prompts stay in English.

Validate `$ARGUMENTS` through the CLI's own grammar — never re-derive it inline (single source of truth: `parseQuickBatchArgs`, `src/quick-batch-dispatch.cts`). `$ARGUMENTS` is raw, attacker-influenced task text — pass it as ONE quoted argument via `--text` so the shell never word-splits or glob-expands it; `quick-batch parse-args` does the whitespace split itself, in Node, after the shell is done:

```bash
QB_PARSE_JSON=$(gad_run quick-batch parse-args --raw --text "$ARGUMENTS")
QB_PARSE_RC=$?
if [ $QB_PARSE_RC -ne 0 ]; then
  echo "$QB_PARSE_JSON" >&2
  exit 1
fi
if [[ "$QB_PARSE_JSON" == @file:* ]]; then QB_PARSE_JSON=$(cat "${QB_PARSE_JSON#@file:}"); fi
```

Parse `$QB_PARSE_JSON` for `jobs` (`"auto"` or an integer), `validate` (bool), `research` (bool), `resume` (batch id or null). Store as `$JOBS`, `$VALIDATE_MODE`, `$RESEARCH_MODE`, `$RESUME_BATCH_ID`.

Extract the raw task-list text / `--file <path>` from `$ARGUMENTS` (everything that is not `--jobs <v>`, `--validate`, `--research`, `--resume <id>`, or `--file <path>`'s own flag pair).

```bash
VALIDATE_PARAM=""; if [ "$VALIDATE_MODE" = true ]; then VALIDATE_PARAM="--validate"; fi
RESEARCH_PARAM=""; if [ "$RESEARCH_MODE" = true ]; then RESEARCH_PARAM="--research"; fi
INIT=$(gad_run query init.quick-batch $VALIDATE_PARAM $RESEARCH_PARAM)
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
AGENT_SKILLS_PLANNER=$(gad_run query agent-skills gad-planner)
AGENT_SKILLS_EXECUTOR=$(gad_run query agent-skills gad-executor)
AGENT_SKILLS_CHECKER=$(gad_run query agent-skills gad-plan-checker)
AGENT_SKILLS_VERIFIER=$(gad_run query agent-skills gad-verifier)
AGENT_SKILLS_RESEARCHER=$(gad_run query agent-skills gad-phase-researcher)
```

Parse `$INIT` for: `planner_model`, `executor_model`, `checker_model`, `verifier_model`, `researcher_model`, `commit_docs`, `quick_dir`, `quick_batches_dir`, `roadmap_exists`, `planning_exists`.

<!-- #2517 model-omit-on-inherit -->

> **Model omission (#2517).** Every `Agent()` dispatch below (planner, researcher, plan-checker, executor, verifier) MUST omit the `model` parameter entirely when the value it would carry (`planner_model`, `checker_model`, `executor_model`, `verifier_model`, `researcher_model`) is `"inherit"` or empty. An empty value 404s on runtimes without native tier aliases — the default on non-Claude runtimes, where the installer writes `resolve_model_ids:"omit"`. Omitting it inherits the orchestrator's model. See @gad-core/references/model-profile-resolution.md.

```bash
STATE_PATH="${quick_dir%/quick}/STATE.md"
PROJECT_PATH="${quick_dir%/quick}/PROJECT.md"
USE_WORKTREES=$(gad_run query config-get workflow.use_worktrees --raw 2>/dev/null || echo "true")
RUNTIME=$(gad_run query config-get runtime --default claude --raw 2>/dev/null || echo "claude")
```

**If `roadmap_exists` is false:** Error — quick-batch requires an active project with ROADMAP.md. Run `/gad-new-project` first.

If the project uses git submodules, parse `SUBMODULE_PATHS` from `.gitmodules` exactly as `/gad-quick` does (a fail-loud commit-time guard, applied per item at commit time — see `gad-core/workflows/quick.md` Step 2 for the identical block, reused verbatim below):

```bash
if [ -f .gitmodules ]; then
  SUBMODULE_PATHS=$(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')
else
  SUBMODULE_PATHS=""
fi
```

**Resolve capacity now (#3676 design row 3-4).** `--jobs auto`/omitted uses this
value alone; `--jobs N` is capped by it (`min(taskCount, N, capacity)` — the
`quick-batch effective-concurrency` verb, called per-wave below, does the
arithmetic; this is only the raw resolve):
```bash
CAPACITY=$(gad_run query dispatch-capacity --raw 2>/dev/null || echo 1)
```

**Resolve isolation now (row 6, 20-22).** Read
@gad-core/references/dispatch-isolation-gate.md and run its `Resolve
ISOLATION`, `Single-agent dispatch sites`, and `Resolve the harness flag`
blocks in order; they set `ISOLATION`/`HARNESS_FLAG` via `query
dispatch-isolation`. `ISOLATION` gates every worktree decision below —
substitute `{harnessFlag}` in Step 6's `Agent()` with `$HARNESS_FLAG`+comma
when `ISOLATION = "harness-worktree"`, else empty.

If `USE_WORKTREES` is not `"false"`, sweep orphaned worktrees before dispatching anything (mirrors `/gad-quick`'s own startup sweep):
```bash
if [ "$USE_WORKTREES" != "false" ]; then
  gad_run query worktree.reap-orphans 2>/dev/null || true
fi
```

Display banner:
```
### GAD ► QUICK BATCH
◆ jobs=${JOBS} validate=${VALIDATE_MODE} research=${RESEARCH_MODE}${RESUME_BATCH_ID:+ resume=${RESUME_BATCH_ID}}
```

---

**Step 2: Resume or create**

If `$RESUME_BATCH_ID` is set: read and execute `gad-core/workflows/quick-batch/steps/resume-mode.md`.
It loads the batch via `quick-batch
resume`, refuses closed on an unknown batch id or a diverged base revision,
and sets `$BATCH_ID`/`$BATCH_MANIFEST_JSON` for the steps below. Task-list
parsing and `quick-batch create` are skipped entirely.

Otherwise: read and execute `gad-core/workflows/quick-batch/steps/batch-init.md`.
It parses the task list (inline or `--file`) and creates the
batch via `quick-batch create`, setting the same `$BATCH_ID`/
`$BATCH_MANIFEST_JSON` pair.

Either path converges on the same post-condition — continue to Step 3.

---

If `section_manifest` is `null` or `"research-phase"` is in its `included` list: read and execute `gad-core/workflows/quick-batch/steps/research-phase.md`. Otherwise skip — do not read the file.

---

**Step 4: Per-DAG-layer planning**

Read and execute `gad-core/workflows/quick-batch/steps/planner-wave.md`. It
dispatches a planner per eligible item (one `Agent()` per message, full task
catalog in every prompt), persists parsed `depends_on`/`files_modified` via
`quick-batch update` after each layer, and — when `$VALIDATE_MODE` — runs the
per-item plan-checker loop (`gad-core/workflows/quick-batch/steps/plan-checker-loop.md`)
before advancing to the next layer.

---

**Step 6: Worktree create + executor dispatch**

Read and execute `gad-core/workflows/quick-batch/steps/worktree-dispatch.md`.
Worktree create/executor dispatch is serialized per item (one `git worktree
add` in flight at a time); already-created worktrees run concurrently up to
the effective MUTATING-wave concurrency.

---

**Step 7: Deterministic merge**

Read and execute `gad-core/workflows/quick-batch/steps/merge-wave.md`. Merges
apply strictly in the wave's original dispatch order (`quick-batch
merge-eligible`), never completion order.

---

If `section_manifest` is `null` or `"verification-wave"` is in its `included` list: read and execute `gad-core/workflows/quick-batch/steps/verification-wave.md`. Otherwise skip — do not read the file.

---

**Step 9: Completion**

Read and execute `gad-core/workflows/quick-batch/steps/completion.md`. Calls
`completeQuickItem` (via `quick-batch complete`) only for a genuinely
complete item, updates STATE.md, and prints the final batch report.

</process>

<success_criteria>
- [ ] `--discuss`/`--full` rejected with a usage error before any dispatch
- [ ] A malformed `--jobs` value rejected before any dispatch
- [ ] `--resume <batch-id>` skips task-list parsing, dispatches only eligible items
- [ ] Task list parsed (inline or `--file`, ≥2 items) and batch created otherwise
- [ ] Planner dispatched per eligible item per DAG layer, full task catalog in prompt, `depends_on`/`files_modified` requested ALWAYS
- [ ] (--research) Researcher dispatched per item before planning
- [ ] (--validate) Plan-checker loop runs per item after planning (≤2 iterations)
- [ ] Worktree create/merge/cleanup serialized; concurrent leaves inside already-created worktrees
- [ ] `isolation == none` forces a mutating wave's concurrency to 1; a research-only wave is unaffected
- [ ] Merges apply in deterministic wave order, never completion order
- [ ] (--validate) Verifier dispatched per item post-merge; `human_needed` never completes the item, `gaps_found` fails it without rollback or retry
- [ ] A merge_failed/scope_violation item is marked failed with the worktree PRESERVED
- [ ] `completeQuickItem` called only for genuinely complete items; STATE.md updated; artifacts committed
</success_criteria>
