---
name: go-and-do
description: "Runs one GAD phase end-to-end without babysitting: intent (cross-AI consultancy on the owner-approved CONTEXT) → design contracts → plan → execute → code review → quality audits → automated UAT → executive summary → close/PR. Verbose stages run in disposable subagents; routine decisions are auto-triaged and logged; hard gates still wait for the user. Resumable: run again to continue. `--no-ship` stops after the UAT."
argument-hint: "<phase> [--ui] [--ai] [--no-ship] [--vault <profile>] [--obs \"<texto livre>\"]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
  - Agent
  - TaskCreate
  - TaskUpdate
  - TaskList
  - TaskStop
  - ListAgents
  - ToolSearch
---

<execution_context>
@~/.claude/skills/go-and-do/workflow.md
</execution_context>

<objective>
Run a single GAD phase end-to-end by invoking the native GAD commands in order and chaining
them. The full pipeline, the layered orchestration (layer 0 = this conversation; layer 1 =
disposable host subagents; layer 2 = the agents GAD spawns), every gate and stop point, the
decision triage, the telemetry and the resume logic are specified in workflow.md above (the
core) and in the per-stage files it names (`workflow-etapa-*.md`, read on entering each stage).
This file only carries what those do not: the argument contract and the intent prerequisite.

Every phase runs the full pipeline. There is no size classifier: one was built, measured on
real phases and removed because it always escalated to maximum rigor (decision of 2026-07-05;
see CHANGELOG). What may legitimately not run is only what the project config turns off or a
tool that is unavailable, and that is always disclosed: one line to the user, a `skip`
telemetry event, and an entry in the executive summary's transparency block.
</objective>

<context>
Phase number + flags: $ARGUMENTS

**Argument:** `<phase>` — required (e.g. `3`). No number → stop and ask.

**Flags:**
- `--ui` — the phase has frontend. Enables the UI design contract (Etapa 1.5) and the UI review
  gate (4.2), which spins up the dev server for a rendered audit.
- `--ai` — the phase is an AI feature. Enables the AI design contract (Etapa 1.5) and the eval
  review gate (4.3).
- `--no-ship` — run everything, including the automated UAT, then stop and hand back without
  closing or shipping. Default is to go through the UAT and open the PR.
- `--vault <profile>` — a pre-configured gsd-browser vault profile, passed down to the UAT
  subagent so it can log in. With it, login flows move from basket 3 (couldn't verify) to
  objectively verifiable; without it, login walls stay basket 3. 2FA and captcha stay basket 3
  either way. Not persisted across sessions: repeat the flag on a resume.
- `--obs "<texto livre>"` — a free-text note for this run. Captured once in Etapa 0.1 and
  prefixed onto every subagent dispatch of this invocation (Sub-rotina H); each stage judges
  for itself whether it is relevant. Not persisted across sessions: repeat the flag on a resume.

**Pré-requisito da rodada: o documento único da intenção.** Antes de `/go-and-do NN`, o dono roda `/gad-discuss-phase NN` (comando interativo, só perguntas de negócio, grava o `NN-CONTEXT.md` aprovado por ele). Sem esse documento, a Go & Do para e diz o que fazer.
The stop is `abre-rodada.sh` exit 6 (no approved `NN-CONTEXT.md` in the new format); the run
then starts straight at the cross-AI consultancy (Etapa 1), whose amendments land only in
`NN-CONTEXT.md`. A phase opened before the single document keeps its old artifacts and is
never migrated.

**Rules workflow.md states only by example:**
- Config gates are checked in layer 0 before dispatching a stage, never inside the subagent.
- A skipped intent review (`intent_review: skipped`, no external reviewer installed) is
  re-enabled by installing a reviewer and deleting `NN-INTENT-REVIEW.md`.
- Three distinct hand-backs, not one: a `human-action`/`blocking-human` gate in execution
  (Etapa 3.4 → graceful pause, resolve and run `/go-and-do N` again); a basket-3 UAT scenario
  (blocks the ship, hands to `/gad-verify-work`); and end-of-phase `human_needed` items (with
  `--no-ship` they become PENDING for the human; by default the UAT resolves what it can and only
  basket 3 blocks).
- `validate-phase` (4.5) already generated the Nyquist-gap tests before the ship; the manual
  broad suite (`/gad-add-tests`) is a post-PR step.
</context>

<process>
Execute end-to-end following workflow.md: its operating rules, stop points and sub-routines,
plus each stage's `workflow-etapa-*.md` (read on entering the stage, as its pipeline index
says), are the specification. Honor every gate and stop point as written there; route
every would-be question through the decision triage (Sub-rotina I); dispatch the stages marked
"via subagent" through Sub-rotina H and route their compact return. A step that does not run
is never silent.

Toda a saída ao usuário — banners, anúncios de status, linhas de sino — é em pt-BR.
</process>
