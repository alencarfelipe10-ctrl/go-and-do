---
name: go-and-do
description: "Runs one GSD phase end-to-end without babysitting: intent (spec + discuss + cross-AI consultancy) → design contracts → plan → execute → code review → quality audits → automated UAT → executive summary → close/PR. Verbose stages run in disposable subagents; routine decisions are auto-triaged and logged; hard gates still wait for the user. Resumable: run again to continue. `--no-ship` stops after the UAT."
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
@$HOME/.claude/skills/go-and-do/workflow.md
</execution_context>

<objective>
Run a single GSD phase end-to-end by invoking the native GSD commands in order and chaining
them. The full pipeline, the layered orchestration (layer 0 = this conversation; layer 1 =
disposable host subagents; layer 2 = the agents GSD spawns), every gate and stop point, the
decision triage, the telemetry and the resume logic are specified in workflow.md above. This
file only carries what workflow.md does not: the argument contract and the PRE-SPEC contract.

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

**PRE-SPEC (convention, not a flag).** If the phase directory contains `NN-PRE-SPEC.md` (exact
name, zero-padded NN), `abre-rodada.sh` detects it (`pre_spec` field) and Etapa 1 uses it as
input: spec and discuss adopt its decisions as user-locked, marked `[pre-spec:PS-nn, R-n]`,
never re-asked or overridden (an irreconcilable conflict rings a bell); the consultancy briefing
discloses their origin; the executive summary declares the file was used. The normal way to
produce one is `/gad-pre-spec NN`.

**PRE-SPEC decisions block (mandatory contract).** Decisions must be machine-readable; prose is
not a source. The file carries exactly one block

```
<!-- gad:decisoes:begin v1 -->   …canonical JSON array…   <!-- gad:decisoes:end -->
```

one object per decision, keys `id` (`PS-nn`), `kind`, `area`, `req_anchor` (`R-n` / `SC-n` /
a REQUIREMENTS id such as `DESC-01` / `none`), `decisao`, `opcoes_descartadas[]`, `evidencia`,
`reversibilidade` (`reversible|costly|one-way`), `reversibilidade_justificativa` (required for
`costly` and `one-way`), `ressalva` (optional), `span`.

Two kinds, two destinations: `decisao_dono` locks (reviewers attack its consequences, never the
decision); `fato_medido` does not lock — it enters the SPEC as `[medido:PS-nn]`, is listed to
the reviewers as a fact to verify, and requires a reproducible `evidencia` (`file:line`, or
command + output).

Fail-closed: block missing or invalid → Etapa 1 returns `needs_decision` with two exits: migrate
the file (`scripts/pre-spec-migra.py` drafts the block from the prose for the owner to review;
legacy tool for PRE-SPECs written before 2.2.0) or authorize the legacy route (the child reads
the whole file; mandatory `pre_spec_sem_bloco` bell). Never "zero decisions in silence". The
answer is durable (`.intent/pre-spec-route.json`); a changed file hash invalidates it and
re-asks. `scripts/confere-pre-spec.sh` is the gate (it runs inside `setup-intencao.sh` and
`confere-etapa.sh 1`); its header carries the exact failure codes.

**Rules workflow.md states only by example:**
- Config gates are checked in layer 0 before dispatching a stage, never inside the subagent.
- A skipped intent review (`intent_review: skipped`, no external reviewer installed) is
  re-enabled by installing a reviewer and deleting `NN-INTENT-REVIEW.md`.
- Three distinct hand-backs, not one: a `human-action`/`blocking-human` gate in execution
  (Etapa 3.4 → graceful pause, resolve and run `/go-and-do N` again); a basket-3 UAT scenario
  (blocks the ship, hands to `/gsd-verify-work`); and end-of-phase `human_needed` items (with
  `--no-ship` they become PENDING for the human; by default the UAT resolves what it can and only
  basket 3 blocks).
- `validate-phase` (4.5) already generated the Nyquist-gap tests before the ship; the manual
  broad suite (`/gsd-add-tests`) is a post-PR step.
</context>

<process>
Execute end-to-end following workflow.md: its operating rules, stages, stop points and
sub-routines are the specification. Honor every gate and stop point as written there; route
every would-be question through the decision triage (Sub-rotina I); dispatch the stages marked
"via subagent" through Sub-rotina H and route their compact return. A step that does not run
is never silent.

Toda a saída ao usuário — banners, anúncios de status, linhas de sino — é em pt-BR.
</process>
