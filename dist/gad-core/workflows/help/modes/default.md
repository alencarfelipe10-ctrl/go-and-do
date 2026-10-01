Apply response_language to all user-facing prose — narration between tool calls, status updates, progress notes, and findings included; preserve code, paths, and identifiers.

<purpose>
One-page newcomer-oriented tour of GAD Core. Output ONLY the `<reference>` content below. No additions.
</purpose>

<reference>
# GAD Core — Git. Ship. Done.

Plan-driven development for solo agentic work with Claude Code. GAD Core turns a vague idea into a hierarchical plan, then executes it phase by phase with state tracking and atomic commits.

## Start here (3 commands)

```text
/gad-new-project        # Greenfield: questioning → research → requirements → roadmap
/gad-onboard            # Existing codebase: map → ingest docs → initialize planning
/gad-plan-phase 1       # Create a detailed plan for phase 1
/gad-execute-phase 1    # Execute all plans in the phase
```

Existing codebase? Run `/gad-onboard` to map the repo, ingest existing docs, and initialize planning safely.

## Common commands

| Command | Purpose |
|---|---|
| `/gad-progress` | Where am I, what's next — also routes freeform intent with `--do "..."` |
| `/gad-quick` | Small ad-hoc task with GAD guarantees (planning dir + atomic commit) |
| `/gad-fast "<task>"` | Trivial inline change — no subagents, ≤3 file edits |
| `/gad-discuss-phase <N>` | Capture vision and decisions before planning |
| `/gad-debug "<symptom>"` | Persistent debug session, survives `/clear` |
| `/gad-capture` | Save an idea, todo, note, seed, or backlog item |
| `/gad-verify-work <N>` | Conversational UAT for a completed phase |
| `/gad-ship <N>` | Open a PR from a completed phase |
| `/gad-help --full` | Complete reference (every command, every flag) |

## Want more?

```text
/gad-help --brief         # 10-line refresher of top commands
/gad-help --full          # complete reference
/gad-help <topic>         # one section only — see topics below
/gad-help --brief <topic> # compact scoped lookup — signature + one-line summary
```

Topics: `workflow` · `planning` · `execute` · `quick` · `debug` · `capture` · `ship` · `config` · `milestones` · `spike` · `sketch` · `review` · `audit` · `progress`

## Update GAD

```bash
go-and-do install
```
</reference>
