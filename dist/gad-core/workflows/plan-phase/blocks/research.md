# plan-phase — research dispatch (step 5, second half)

Lazy block of `workflows/plan-phase.md`. Read it at step 5.1 only when RESEARCH.md is missing or `--research` is set — a run that reuses RESEARCH.md never pays for this text. First half: the interactive research question. Second half, when the answer (or `--auto`) is to research: the banner, the `gad-phase-researcher` spawn, its return handling and the research-only early exit; then go back to the core at step 5.5.

### Step 5.1 — the research question (interactive runs only)


If `TEXT_MODE` is true, present as a plain-text numbered list:
```
Research before planning Phase {X}: {phase_name}?

1. Research first (Recommended) — Investigate domain, patterns, and dependencies before planning. Best for new features, unfamiliar integrations, or architectural changes.
2. Skip research — Plan directly from context and requirements. Best for bug fixes, simple refactors, or well-understood tasks.

Enter number:
```

Otherwise use AskUserQuestion:
```
AskUserQuestion([
  {
    question: "Research before planning Phase {X}: {phase_name}?",
    header: "Research",
    multiSelect: false,
    options: [
      { label: "Research first (Recommended)", description: "Investigate domain, patterns, and dependencies before planning. Best for new features, unfamiliar integrations, or architectural changes." },
      { label: "Skip research", description: "Plan directly from context and requirements. Best for bug fixes, simple refactors, or well-understood tasks." }
    ]
  }
])
```

If user selects "Skip research": skip to step 6.

### Step 5 — research dispatch

Display banner:
```
### GAD ► RESEARCHING PHASE {X}

◆ Spawning researcher... (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze)
```

### Spawn gad-phase-researcher

```bash
if gad_run query teams-status --active >/dev/null 2>&1; then
  echo "⚠️  CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS detected. GAD's multi-agent orchestration is not validated under claude-code agent-teams and may stall (a subagent's completion can fail to route to the orchestrator). Recommend disabling agent-teams for GAD workflows. See https://github.com/open-gsd/gsd-core/issues/1355" >&2
fi
```

```bash
PHASE_DESC=$(gad_run query roadmap.get-phase "${PHASE}" --pick section)
if [ -z "${PLAN_PRE_HOOKS_JSON:-}" ]; then
  PLAN_PRE_HOOKS_JSON=$(gad_run loop render-hooks plan:pre --raw)
fi
```

Find the active `research` step hook in `PLAN_PRE_HOOKS_JSON`. Use the hook's `fragment.inline` as the prompt template and substitute the phase fields below before spawning its declared `ref.agent`.

```markdown
{research_hook.fragment.inline}
```

```
Agent(
  prompt=filled_research_hook_fragment,
  subagent_type=research_hook.ref.agent,
  model="{researcher_model}",
  description="Research Phase {phase}"
)
```

> **ORCHESTRATOR RULE — ALL RUNTIMES**: After calling Agent() above, stop working on this task immediately. Do not read more files, edit code, or run tests related to this task while the subagent is active. Wait for the subagent to return its result. This prevents duplicate work, conflicting edits, and wasted context. Only resume when the subagent result is available. Never call `ScheduleWakeup` or any host wake/sleep-scheduling tool to literalize this wait (#4079) — the Agent() call returns on its own; a partial-args wake call surfaces a red validation error.

### Handle Researcher Return

- **`## RESEARCH COMPLETE`:** Display confirmation, continue to step 6
- **`## RESEARCH BLOCKED`:** Display blocker, offer: 1) Provide context, 2) Skip research, 3) Abort

If `section_manifest` is `null` or `"research-only-early-exit"` is in its `included` list: read and execute `gad-core/workflows/plan-phase/steps/research-only-early-exit.md`. Otherwise skip — do not read the file.

