---
name: gad-config
description: "Configure GAD settings — workflow toggles, advanced knobs, integrations, and model profile"
argument-hint: "[--advanced | --integrations | --profile <name>]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Grep
  - AskUserQuestion
---


<objective>
Configure GAD settings interactively with a single consolidated command.

Mode routing:
- **default** (no flag): Common-case toggles (model, research, plan_check, verifier, branching) → settings workflow
- **--advanced**: Power-user knobs (planning tuning, timeouts, branch templates, cross-AI execution) → settings-advanced workflow
- **--integrations**: Third-party API keys, code-review CLI routing, agent-skill injection → settings-integrations workflow
- **--profile <name>**: Switch model profile (quality|balanced|budget|inherit) → set-profile (inline)
</objective>

<routing>

| Flag | Action | Workflow |
|------|--------|----------|
| (none) | Interactive 5-question common-case config prompt | settings |
| --advanced | Power-user knobs: planning, execution, discussion, cross-AI, git, runtime | settings-advanced |
| --integrations | API keys (Brave/Firecrawl/Exa), review CLI routing, agent skills | settings-integrations |
| --profile &lt;name&gt; | Switch model profile without interactive prompt | gad-tools query config-set-model-profile |

</routing>

<execution_context>
To load this command's workflow spec: check for `.claude/gad-core/workflows/settings.md` relative to the current working directory first (project-local); if it is not there, fall back to `~/.claude/gad-core/workflows/settings.md` (the global install). If neither file exists, stop — a workflow spec is required and none was found.
To load this command's workflow spec: check for `.claude/gad-core/workflows/settings-advanced.md` relative to the current working directory first (project-local); if it is not there, fall back to `~/.claude/gad-core/workflows/settings-advanced.md` (the global install). If neither file exists, stop — a workflow spec is required and none was found.
To load this command's workflow spec: check for `.claude/gad-core/workflows/settings-integrations.md` relative to the current working directory first (project-local); if it is not there, fall back to `~/.claude/gad-core/workflows/settings-integrations.md` (the global install). If neither file exists, stop — a workflow spec is required and none was found.
</execution_context>

<context>
Arguments: $ARGUMENTS

Parse the first token of $ARGUMENTS:
- If it is `--advanced`: strip the flag, execute settings-advanced workflow
- If it is `--integrations`: strip the flag, execute settings-integrations workflow
- If it starts with `--profile`: extract the profile name (remainder after `--profile`), then:
  1. Verify the engine exists at `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/gad-tools.cjs` (never look it up on PATH); if absent, emit the install hint `Install GAD by running the go-and-do installer (go-and-do install)` and stop.
  2. Run: `node "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/gad-tools.cjs" query config-set-model-profile <profile-name> --raw` and display the output verbatim.
- Otherwise: execute settings workflow (no argument needed)
</context>

<process>
1. Parse the leading flag (if any) from $ARGUMENTS.
2. Load and execute the appropriate workflow end-to-end, or run the inline SDK command for --profile.
3. Preserve all workflow gates from the target workflow.
</process>
