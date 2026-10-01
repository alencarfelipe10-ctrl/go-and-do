---
name: gad-settings
description: "Configure GAD workflow toggles and model profile"
allowed-tools:
  - Read
  - Write
  - Bash
  - Grep
  - AskUserQuestion
---


<objective>
Interactive configuration of GAD workflow agents and model profile via multi-question prompt.

Routes to the settings workflow which handles:
- Config existence ensuring
- Current settings reading and parsing
- Interactive multi-question prompt covering model profile and workflow toggles (research, plan_check, verifier, drift guard, TDD, code review, worktrees, compact content, and more — see `gad-core/workflows/settings.md` for the current set)
- Config merging and writing
- Confirmation display with quick command references
</objective>

<execution_context>
To load this command's workflow spec: check for `.claude/gad-core/workflows/settings.md` relative to the current working directory first (project-local); if it is not there, fall back to `~/.claude/gad-core/workflows/settings.md` (the global install). If neither file exists, stop — a workflow spec is required and none was found.
</execution_context>

<process>
Execute end-to-end.
</process>
