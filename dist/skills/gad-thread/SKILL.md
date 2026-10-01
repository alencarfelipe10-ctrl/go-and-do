---
name: gad-thread
description: "Manage persistent context threads for cross-session work"
argument-hint: "[list [--open | --resolved] | close <slug> | status <slug> | name | description]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Grep
---


<objective>
Create, list, close, or resume persistent context threads. Threads are lightweight
cross-session knowledge stores for work that spans multiple sessions but
doesn't belong to any specific phase.
</objective>

<execution_context>
To load this command's workflow spec: check for `.claude/gad-core/workflows/thread.md` relative to the current working directory first (project-local); if it is not there, fall back to `~/.claude/gad-core/workflows/thread.md` (the global install). If neither file exists, stop — a workflow spec is required and none was found.
</execution_context>

<process>
Execute end-to-end.
</process>
