---
name: gad-manage
description: "config workspace | workstreams thread update ship inbox"
argument-hint: ""
allowed-tools:
  - Read
  - Skill
requires: [config, workspace, workstreams, thread, pause-work, resume-work, update, ship, inbox, pr-branch, undo, cleanup, health, manager, settings, stats, surface, help]
---

Route to the appropriate management skill based on the user's intent.
`gad-config` (settings + advanced + integrations + profile) and `gad-workspace`
(new + list + remove) are post-#2790 consolidated entries.

| User wants | Invoke |
|---|---|
| Configure GAD settings (basic / advanced / integrations / profile) | gad-config |
| Manage workspaces (create / list / remove) | gad-workspace |
| Manage parallel workstreams | gad-workstreams |
| Continue work in a fresh context thread | gad-thread |
| Pause current work | gad-pause-work |
| Resume paused work | gad-resume-work |
| Ship completed work | gad-ship |
| Process inbox items | gad-inbox |
| Create a clean PR branch | gad-pr-branch |
| Undo the last GAD action | gad-undo |
| Archive accumulated phase directories | gad-cleanup |
| Diagnose planning directory health | gad-health |
| Open the interactive command center | gad-manager |
| Configure workflow toggles and model profile | gad-settings |
| Show project statistics | gad-stats |
| Toggle which skills are surfaced | gad-surface |
| Show the GAD command guide | gad-help |

Invoke the matched skill directly using the Skill tool.
