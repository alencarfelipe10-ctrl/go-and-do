---
name: end-mile
description: "Finaliza um milestone GSD: audit-milestone → milestone-summary → complete-milestone. Audita a definição de pronto, gera o sumário executivo e arquiva o milestone (com tag git). O gate do audit decide tudo: só um veredito `passed` segue; `gaps_found`/`tech_debt` param com caminho de saída. Não roda new-milestone (você faz manual). Resumível — re-rode para continuar de onde parou."
argument-hint: "[version] [--fresh]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
  - Agent
---

<objective>
Close out a GSD milestone — the three native commands that take a milestone from
"last phase shipped" to "archived and tagged", in the only order their data
dependencies allow:

**audit-milestone → milestone-summary → complete-milestone.**

This skill does not reimplement GSD logic — it invokes the native commands (via the
`Skill` tool) and chains them, gating the chain on the audit verdict. It picks up after
every phase of the milestone is shipped and takes the milestone to an archived,
git-tagged state.

**The one piece of glue it adds.** After `/gsd-audit-milestone` writes
`.planning/v{version}-MILESTONE-AUDIT.md`, this skill reads its `status:` verdict and
decides whether the chain may continue. Only `passed` proceeds. `gaps_found` (critical
blockers) and `tech_debt` (no blockers, but accumulated deferred items) **both stop** —
by the user's explicit choice this skill is stricter than native `complete-milestone`,
which would accept `tech_debt`. Every stop names the way forward, so the rigid gate is
never a dead end (resolve and re-run, or run `/gsd-complete-milestone` directly to accept).

**Where it stops:** at the archived, tagged milestone. Starting the next version cycle
(`/gsd-new-milestone`) is yours, on purpose. It also yields to `complete-milestone`'s own
interactive gates (readiness confirmation, PR merge prompts, tag push) — it does not
duplicate them.

**Resumable:** re-running `/end-mile` never redoes finished work — it reuses an existing
audit with a terminal verdict (unless `--fresh`), skips an already-generated summary, and
detects an already-archived milestone.
</objective>

<execution_context>
@$HOME/.claude/skills/end-mile/workflow.md
</execution_context>

<context>
Arguments: $ARGUMENTS

**`[version]`** — optional. The milestone version (e.g. `1.0`). Omit it and the skill
derives the version from the milestone audit file. A leading `v` is tolerated (`v1.0` = `1.0`).

**`--fresh`** — optional flag. Force `/gsd-audit-milestone` to re-run even when an audit
file already exists, instead of reusing the prior verdict.

Milestone-scoped (one whole version cycle). To close a single phase, use `/close-phase N`.
</context>

<process>
Execute end-to-end following workflow.md.
Preserve every stop point: not a GSD project (Etapa 0); an audit verdict that is not
`passed` — `gaps_found` or `tech_debt` both stop with an escape hatch (Etapa 1 gate);
an unresolvable version (Etapa 1); and any environment or readiness gate that
`complete-milestone` itself raises (Etapa 3). **Never invoke `complete-milestone` on a
non-`passed` audit.**
</process>
