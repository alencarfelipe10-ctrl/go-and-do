Apply response_language to all user-facing prose — narration between tool calls, status updates, progress notes, and findings included; preserve code, paths, and identifiers.

<purpose>
One-liner refresher for returning users. Output ONLY the `<reference>` content below. No additions.
</purpose>

<reference>
**GAD — top commands**

```text
/gad-new-project           Initialize a project (greenfield)
/gad-onboard               Onboard an existing codebase (brownfield)
/gad-map-codebase          Refresh/map codebase intelligence
/gad-plan-phase <N>        Create a phase plan
/gad-execute-phase <N>     Execute a phase
/gad-progress              Where am I, what's next
/gad-quick                 Small ad-hoc task with GAD guarantees
/gad-fast "<task>"         Trivial inline task — no subagents
/gad-debug "<symptom>"     Persistent debug session (survives /clear)
/gad-capture               Save an idea / todo / note
/gad-ship <N>              Open a PR from a completed phase
```

More: `/gad-help` (default tour) · `/gad-help --full` (everything) · `/gad-help <topic>` (one section)
</reference>
