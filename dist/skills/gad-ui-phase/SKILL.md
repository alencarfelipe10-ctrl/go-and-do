---
name: gad-ui-phase
description: "Generate UI design contract (UI-SPEC.md) for frontend phases"
argument-hint: "[phase]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - Agent
  - WebFetch
  - AskUserQuestion
  - mcp__context7__*
---

<objective>
Create a UI design contract (UI-SPEC.md) for a frontend phase.
Orchestrates gad-ui-researcher and gad-ui-checker.
Flow: Validate → Research UI → Verify UI-SPEC → Done
</objective>

<execution_context>
To load this command's workflow spec: check for `.claude/gad-core/workflows/ui-phase.md` relative to the current working directory first (project-local); if it is not there, fall back to `~/.claude/gad-core/workflows/ui-phase.md` (the global install). If neither file exists, stop — a workflow spec is required and none was found.
@~/.claude/gad-core/references/ui-brand.md
</execution_context>

<context>
Phase number: $ARGUMENTS — optional, auto-detects next unplanned phase if omitted.
</context>

<process>
Execute end-to-end.
Preserve all workflow gates.
</process>
