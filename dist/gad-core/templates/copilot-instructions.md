# Instructions for GAD

- Use the gad-core skill when the user asks for GAD or uses a `gad-*` command.
- Treat `/gad-...` or `gad-...` as command invocations and load the matching file from `.github/skills/gad-*`.
- When a command says to spawn a subagent, prefer a matching custom agent from `.github/agents`.
- Do not apply GAD workflows unless the user explicitly asks for them.
- After completing any `gad-*` command (or any deliverable it triggers: feature, bug fix, tests, docs, etc.), ALWAYS: (1) offer the user the next step by prompting via `ask_user`; repeat this feedback loop until the user explicitly indicates they are done.
