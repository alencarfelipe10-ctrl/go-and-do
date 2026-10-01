---
name: gad-context
description: "codebase intel | map graphify docs learnings mempalace"
argument-hint: ""
allowed-tools:
  - Read
  - Skill
requires: [map-codebase, graphify, docs-update, extract-learnings, mempalace-recall, mempalace-capture]
---

Route to the appropriate codebase-intelligence skill based on the user's intent.
`gad-scan` and `gad-intel` were folded into `gad-map-codebase` flags by #2790.

| User wants | Invoke |
|---|---|
| Map the full codebase structure | gad-map-codebase |
| Quick lightweight codebase scan | gad-map-codebase --fast |
| Query mapped intelligence files | gad-map-codebase --query |
| Generate a knowledge graph | gad-graphify |
| Update project documentation | gad-docs-update |
| Extract learnings from a completed phase | gad-extract-learnings |
| Recall prior decisions and patterns before planning | gad-mempalace-recall |
| File a phase artifact into MemPalace | gad-mempalace-capture |

Invoke the matched skill directly using the Skill tool.
