---
name: gad-ns-project
description: "project lifecycle | milestones audits summary"
allowed-tools:
  - Read
  - Skill
---


Route to the appropriate project / milestone skill based on the user's intent.
`gad-plan-milestone-gaps` was deleted by #2790 — gap planning now happens
inline as part of `gad-audit-milestone`'s output.

| User wants | Invoke |
|---|---|
| Start a new project | gad-new-project |
| Onboard an existing codebase | gad-onboard |
| Create a new milestone | gad-new-milestone |
| Complete the current milestone | gad-complete-milestone |
| Audit a milestone for issues | gad-audit-milestone |
| Summarize milestone status | gad-milestone-summary |
| Import an external plan | gad-import |
| Bootstrap planning from existing docs | gad-ingest-docs |
| Generate a developer profile | gad-profile-user |
| Review and promote backlog items | gad-review-backlog |

Invoke the matched skill directly using the Skill tool.
