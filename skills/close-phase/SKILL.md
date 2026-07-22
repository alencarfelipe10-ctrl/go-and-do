---
name: close-phase
description: "Closes a GSD phase after UAT: extract-learnings → ship. Extracts LEARNINGS.md, bridges the verification gate (promotes human_needed → passed when the UAT is clean), commits the docs so the tree is clean, then creates the PR via gsd-ship. Resumable — re-run to continue where it left off."
argument-hint: "<phase>"
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
Close a single GSD phase — the last two steps of the phase lifecycle, after the
manual UAT (`/gsd-verify-work`) is done. Orchestrate the native GSD commands in order:

**extract-learnings → (verification bridge + docs commit) → ship → close.**

This skill does not reimplement GSD logic — it invokes the native commands (via the
`Skill` tool) and chains them. It picks up where `/go-and-do` + the manual UAT leave off
and takes the phase to a created PR.

**The one piece of glue it adds.** After a clean UAT, `VERIFICATION.md` is almost always
left at `human_needed` — no native GSD command promotes it to `passed` — yet
`/gsd-ship`'s preflight blocks on anything other than `passed`. When the UAT is genuinely
clean — judged by the native `phase uat-passed` predicate (GSD 1.5.0+; markdown-aware,
fail-closed, only `pass`/`passed` count, scans all `*-UAT.md`) — this skill promotes the
verification status to `passed`, transparently and with the evidence recorded in the file.
A real failure stops it (→ `/gsd-verify-work`); **skipped (unverified) tests block and ask**,
so the user resolves them or explicitly accepts shipping unverified behavior. It also commits
the `LEARNINGS.md` it produced (and the promoted `VERIFICATION.md`) so ship sees a clean
working tree.

**Where it stops:** at the created PR. Approving and merging are yours. It also yields to
ship's own environment gates (no remote, no `gh`, wrong branch) and to its review prompt.

**Resumable:** re-running `/close-phase N` never redoes finished work — it detects the
`LEARNINGS.md`, an already-`passed` verification, and an existing PR, and skips them.
</objective>

<execution_context>
@$HOME/.claude/skills/close-phase/workflow.md
</execution_context>

<context>
Phase number: $ARGUMENTS

**Argument:** `<phase>` — required. The phase number to close (e.g. `3`). No number → stop and ask.

Phase-scoped (like `/go-and-do`). To ship a whole milestone, use `/gsd-ship vX.Y` directly.
</context>

<process>
Execute end-to-end following workflow.md.
Preserve every stop point: not a GSD project / phase not found (Etapa 0); an incomplete or
unclean UAT while verification is `human_needed` (Etapa 0 gate → stop and send the user to
`/gsd-verify-work N`); `gaps_found` verification (stop); and any environment block ship
itself raises (no remote / no `gh` / wrong branch). **Never promote the verification status
without the UAT evidence.**
</process>
