---
name: gad-quality
description: "quality gates | code review debug audit security eval ui"
argument-hint: ""
allowed-tools:
  - Read
  - Skill
requires: [code-review, audit-uat, secure-phase, eval-review, ui-review, validate-phase, debug, forensics, audit-fix, review, ui-phase]
---

Route to the appropriate quality / review skill based on the user's intent.
`gad-code-review-fix` was absorbed by `gad-code-review --fix` in #2790.

| User wants | Invoke |
|---|---|
| Review code for quality and correctness | gad-code-review |
| Auto-fix code review findings | gad-code-review --fix |
| Audit UAT / acceptance testing | gad-audit-uat |
| Security review of a phase | gad-secure-phase |
| Evaluate AI response quality | gad-eval-review |
| Review UI for design and accessibility | gad-ui-review |
| Validate phase outputs | gad-validate-phase |
| Debug a failing feature or error | gad-debug |
| Forensic investigation of a broken system | gad-forensics |
| Autonomous audit-to-fix pipeline | gad-audit-fix |
| Cross-AI peer review of plans | gad-review |
| Generate a UI design contract | gad-ui-phase |

Invoke the matched skill directly using the Skill tool.
