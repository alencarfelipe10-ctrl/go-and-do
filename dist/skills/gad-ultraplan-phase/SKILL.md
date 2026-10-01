---
name: gad-ultraplan-phase
description: "[BETA] Offload plan phase to Claude Code's ultraplan cloud; review in browser and import back."
argument-hint: "[phase-number]"
allowed-tools:
  - Read
  - Bash
  - Glob
  - Grep
---


<objective>
Offload GAD's plan phase to Claude Code's ultraplan cloud infrastructure.

Ultraplan drafts the plan in a remote cloud session while your terminal stays free.
Review and comment on the plan in your browser, then import it back via /gad-import --from.

⚠ BETA: ultraplan is in research preview. Use /gad-plan-phase for stable local planning.
Requirements: Claude Code v2.1.91+, claude.ai account, GitHub repository.
</objective>

<execution_context>
To load this command's workflow spec: check for `.claude/gad-core/workflows/ultraplan-phase.md` relative to the current working directory first (project-local); if it is not there, fall back to `~/.claude/gad-core/workflows/ultraplan-phase.md` (the global install). If neither file exists, stop — a workflow spec is required and none was found.
@~/.claude/gad-core/references/ui-brand.md
</execution_context>

<context>
$ARGUMENTS
</context>

<process>
Execute the ultraplan-phase workflow end-to-end.
</process>
