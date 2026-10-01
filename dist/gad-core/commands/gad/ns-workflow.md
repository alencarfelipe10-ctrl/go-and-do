---
name: gad-workflow
description: "workflow | discuss plan execute verify phase progress"
argument-hint: ""
allowed-tools:
  - Read
  - Skill
requires: [discuss-phase, spec-phase, plan-phase, execute-phase, verify-work, phase, progress, next, ultraplan-phase, plan-review-convergence, add-tests, ai-integration-phase, autonomous, fast, mvp-phase, quick, quick-batch]
---

Route to the appropriate phase-pipeline skill based on the user's intent.
Sub-skill names below are post-#2790 consolidated targets — `gad-phase`
absorbs the former add/insert/remove/edit-phase commands and `gad-progress`
absorbs the former next/do workflow-advance commands. The reclaimed
`gad-next` target is the state-aware smart-entry launcher, not the retired
workflow-advance command.

| User wants | Invoke |
|---|---|
| Gather context before planning | gad-discuss-phase |
| Clarify what a phase delivers | gad-spec-phase |
| Create a PLAN.md | gad-plan-phase |
| Execute plans in a phase | gad-execute-phase |
| Verify built features through UAT | gad-verify-work |
| Add / insert / remove / edit a phase | gad-phase |
| Advance to the next logical step | gad-progress |
| Open the state-aware smart-entry launcher | gad-next |
| Offload planning to the ultraplan cloud | gad-ultraplan-phase |
| Cross-AI plan review convergence loop | gad-plan-review-convergence |
| Generate tests for a completed phase | gad-add-tests |
| Design an AI-integration phase | gad-ai-integration-phase |
| Run all remaining phases autonomously | gad-autonomous |
| Execute a trivial task inline | gad-fast |
| Plan a phase as a vertical MVP slice | gad-mvp-phase |
| Execute a quick task with GAD guarantees | gad-quick |
| Batch several quick-shaped tasks together | gad-quick-batch |

Invoke the matched skill directly using the Skill tool.
