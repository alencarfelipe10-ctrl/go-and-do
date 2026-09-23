<!-- ============================================================ -->
<!-- workflow.md — the executable core of the go-and-do skill.   -->
<!-- Embedded into SKILL.md via @ (loaded on activation).        -->
<!-- Imperative instructions for the orchestrator; not docs.     -->
<!-- Hybrid layout (T.3): only the resident part lives here —     -->
<!-- the stage script, per-stage contracts and always-on         -->
<!-- sub-routines. Per-stage detail lives in prompts/*.md (read  -->
<!-- by the subagent); conditional material lives in             -->
<!-- workflow-ui.md / workflow-ai.md / workflow-dev-server.md    -->
<!-- (read on demand).                                           -->
<!-- ============================================================ -->

# go-and-do — execution

<role>
You are the orchestrator. You run one GSD phase by invoking native GSD commands in order and
chaining them. You do not reimplement GSD logic.

Language: this file is in English. Everything the user reads is in pt-BR and its wording is
fixed — banners, `🔔` and `🤖` lines, handoff text, the commit messages quoted below, the
`DECISAO-DO-DONO` block and the decision labels. Emit those strings exactly as written here.
</role>

<operating_rules>
Read once, apply throughout:

- Invoke GSD commands via the `Skill` tool — inline in layer 0 only where the stage block says
  so; most stages dispatch a layer-1 host subagent that invokes the command in its own window
  (Sub-rotina H). Either way, wait for one step to finish before starting the next.
- Every main step runs between two mechanical fences: `pre-despacho.sh <id>` opens it
  (context gate + checkpoint + route `ok`/`pular`/`skip`/`stop`/`bloqueio`) and
  `confere-etapa.sh <id>` closes it (manifest asserts against the disk + canonical verdict
  extraction + the `end` telemetry event with measured tokens). You never re-read a gate report
  and never accept a subagent's `done` over a failing fence — exit 1 sends the work back with
  the list of what is missing, whatever the subagent claimed. Scripts compute; you judge and
  route.
- Three declared deviations from "reuse, don't reinvent": the UAT reuses verify-work's
  scenario derivation inline via subagent; the UAT drives the browser via subagent +
  `uat-playbook.md`; Etapa 1 suppresses the discuss `auto_advance` side effect and resets its
  chain flag. The close is not a deviation — it reuses the native `/close-phase` skill.
- Do not read artifact bodies into your own window — layer 0 decides by frontmatter, by the
  SDK's JSON fields and by file existence. Whoever needs an artifact's content is the layer-1
  subagent of that step; it reads and writes on disk and returns a compact status.
- Honor every stop point — never skip one to keep going. The hard stops: missing entry
  prerequisites (Etapa 0), incomplete execution blocked on the user (3.4 → Sub-rotina D),
  persistent gaps after one retry (3.5), no external reviewer at 2.5 (PC-6, fail-closed),
  open security threats (4.4), a UAT bug that survives one fix cycle (5.5 → D), and the
  anti-false-ship floor: ship only with the UAT objectively clean (no basket 2/3).
- Everything is resumable. Re-running `/go-and-do N` never redoes finished work —
  `abre-rodada.sh` and each `pre-despacho.sh` decide the resume mechanically from disk state.
- Keep the TaskList mirroring disk state (Sub-rotina C). Write telemetry only at your writer
  slots (Sub-rotina G); every other event has a script owner.
- A step that does not run is never silent: one line to the user, a `skip` event, and an entry
  in the resumo's transparency block. Never mutate project config to make a step not run.
- Paths: the skill lives at `$HOME/.claude/skills/go-and-do/`; `phase_dir`/`padded_phase`
  (the `NN` prefix) come from the abre-rodada snapshot. Dispatch paths are always absolute.
- Gates decide on RAW output, never on wrapper-filtered output. Under a hook that rewrites
  Bash and compacts output (e.g. RTK), every command whose result feeds a gate decision
  (`wc -l`, empty-output test, `grep` routed by exit code) runs as `rtk proxy <cmd>`. Applies
  to every layer and is passed down in briefings that carry gate commands. Exploratory reads
  stay filtered. The skill's scripts read the mirrors `.planning/.gad/last-*.json` when stdout
  is capped (PC-5).
- Session usage (5h / weekly) is not readable by a skill, so there is no gate for it: if the
  limit hits, re-run `/go-and-do N` after the reset and the run continues. Manual pause at any
  time: `/gsd-pause-work`.
</operating_rules>

---

<pipeline_index>

Legend used in the stages: 🎌 flag-only · ⏭️ resume (skips if done) · ⏸️ may stop · 🔒 context
gate (`pre-despacho.sh`) before it.

| Etapa | what | how |
|---|---|---|
| 0 | preparation | `abre-rodada.sh` + `confere-etapa.sh 0` + banner |
| 1 | intent: spec + discuss + specialist consultancy | 🔒 ⏭️ agent `gad-intent` + `prompts/intent.md` |
| 1.5 | design contracts | 🎌 `setup-contratos.sh` → agent `gad-contratos` + `prompts/contratos.md` |
| 2 | planning | 🔒 ⏭️ agent `gad-plan` + `prompts/plan.md`; 2.4b resolves `autonomous: false` |
| 2.5 | plan convergence | 🔒 ⏭️ agent `gad-plan` + `prompts/convergence.md` (PC-6 fail-closed) |
| 3 | build | 🔒 3.2 parallelism authority → `gad-execute` + `prompts/execute.md` → 3.4 crossroads → 3.5 gaps 1× |
| 4 | quality gates | 🔒 ⏭️ per gate: code-review · 🎌 ui-review · 🎌 eval-review · secure (only blocking gate) · validate |
| 5 | automated interactive UAT | resume by `NN-UAT.md` state; generate → run (Sonnet + `uat-playbook.md`) → 1 fix cycle |
| 6 | close + ship | `pre-despacho.sh 6` routes pausa/handback/ship; Sub-rotina F; ship via `prompts/close.md`; `confere-etapa.sh 6` |

</pipeline_index>

---

<stages>

<stage id="0" name="Preparação">

**0.1 — Arguments.** Phase number (first number) + flags `--ui`, `--ai`, `--no-ship`,
`--vault <profile>`, `--obs "<texto>"` (unquoted: everything up to the next flag). No number →
stop and ask. Keep `--no-ship` (terminal route of Etapa 6), `vault_profile` (goes down to the
UAT — the 0.2 JSON and the run pointer carry it as `args.vault_profile`) and `obs_text` (note
to every dispatch of the run — Sub-rotina H).

**0.2 — Atomic opening.** Run `$HOME/.claude/skills/go-and-do/scripts/abre-rodada.sh N [flags]`
and obey the JSON (mirror in `.planning/.gad/last-abre-rodada.json`): entry gates, phase
snapshot (`phase_dir`/`padded_phase`/`has_plans`/`has_verification`), context gate, resume
decisions (`etapa_1`/`etapa_2`), `vault_alerta`, TaskList
snapshot, `run` event + run pointer — all in one script. Exit ≠ 0 → stop with the script's reason (exit 2 =
gate/argument · 3 = context at the ceiling · 4 = phase not found · 5 = phase in the ROADMAP but
its directory unresolvable). Missing entry
prerequisites are the first hard stop (Etapa 0).

**0.3 — Obey the snapshot.**
- `confere-etapa.sh 0` (self-check of the opening: pointer + `run` event on disk).
- Mirror the TaskList (Sub-rotina C).
- `vault_alerta` → ask BEFORE spending the phase (phase that looks like an authenticated UI
  without `--vault`).
- `pos_ship_alerta` → ask BEFORE spending the phase, listing `pendentes` (a previous phase left
  a post-ship observation marked `bloqueia_proxima: sim` that nobody observed yet). The owner
  decides; record the answer in `NN-DECISOES.md`. The phase named in the item's
  `verificavel_em` never triggers it.
- `uat_superficie` (absolute path or null) → keep it for 5.4: it is the project's UAT contract.
- `--ui`/UI-SPEC → read `workflow-ui.md`; `--ai`/AI-SPEC → `workflow-ai.md` (the only read of
  the run). A phase with a server → `workflow-dev-server.md` at the first step that uses it
  (Sub-rotina B).

**0.4 — Banner.** Double ASCII frame in a `text` block:

```text
╔══════════════════════════════════════════════════╗
║  GO-AND-DO · Fase NN — <nome da fase>            ║
╠══════════════════════════════════════════════════╣
║  Contratos   UI ✅ · IA —                        ║
║  Rota        vai até abrir o PR                  ║
║  Vault       ligado (fluxos com login)           ║
║  Obs         <obs_text literal>                  ║
╚══════════════════════════════════════════════════╝
```

`Rota` = `--no-ship` → "para no seu UAT, sem shipar"; default → "vai até abrir o PR". `Vault`
and `Obs` only when present. Below the box, one loose line: the user may step away.

</stage>

<stage id="1" name="Intenção — spec + discuss + consultoria especializada">

> Replaces the human stamp with a machine skeptic: SPEC and CONTEXT come out in `--auto` (each
> choice logged) and the intent goes through cross-AI specialist consultancy — two external
> consultants try to knock down the decisions reading the real code, and a verifier checks
> each finding before it is accepted. The user is called only when a finding touches what is
> theirs to decide.

**1.1 — Resume.** Obey `etapa_1` from abre-rodada: `pular` → Etapa 1.5 · `continuar_pergunta`
→ re-present the pending question stored in the artifact and dispatch with the answer ·
`despachar` → 1.2. Fine-grained per-file resume belongs to the subagent (`setup-intencao.sh`).

**1.2 — Dispatch.** `pre-despacho.sh 1` → dispatch the agent `gad-intent` (own def: Opus 5
medium — the coordinator routes; heavy judgment lives in the children and the external
consultants) with `prompts/intent.md`, carrying absolute `N`, `NN`, `phase_dir`,
`project_root` and, on a continuation, the verbatim answer. If abre-rodada reported a non-null
`pre_spec` (`NN-PRE-SPEC.md` in the phase directory — decisions pre-locked by the user; the
normal way to produce it is `/gad-pre-spec NN`, which writes the `gad:decisoes` block), pass
its path in the dispatch and declare its use in the executive summary; `setup-intencao.sh`
classifies the block (`pre_spec_bloco: ok|ausente|invalido`) and
`pre_spec_mode: structured|legacy` goes explicitly to both children. With `NN-SPEC.md` and
`NN-CONTEXT.md` already on disk, the PRE-SPEC is briefing input only (abre-rodada brings
`inventario`, the setup returns `pre_spec_precedencia`). Inside: child `gad-spec` hosts
`gsd-spec-phase N --auto` (ends at the SPEC, no auto-advance) → child `gad-discuss` hosts
`gsd-discuss-phase N --auto` without running the `auto_advance`, zeroing
`workflow._auto_chain_active` on return (layer 1 runs the scout and a `gad-explore` first and
hands `explore: <phase_dir>/.intent/.explore-discuss.md`) → specialist consultancy (Codex +
agy — agy = Gemini 3.7 Flash — ↔ `gad-verificador`, which also re-reads each cycle's committed
amendment in `releitura` mode, `prompts/intent-releitura.md`; loop by `decide-ciclo.sh`, hard
ceiling 4; fail-closed at the "≥1 consultant" floor). The lanes run in
the background (`roda-lanes.sh`; lane authority is `.intent/.status-c<C>-<lane>.json`,
`usable`/`independent`); the 4-turns-per-cycle budget (5 when the `releitura` corrected) is an
audit ruler measured by `/audit-gad` in the transcript, not counted in session.

Never pass `model` or `effort` in the `Agent` call of a `gad-*` (E7): the def pins both and
`gad-lifecycle.sh` denies the call with `deny` + an `incidente` event. The same hook denies
resuming a `gad-spec`/`gad-discuss` that already returned `done`, and a second dispatch of one
when the artifact (`NN-SPEC.md`/`NN-CONTEXT.md`) is already on disk (E3). The denial carries
the reason in `permissionDecisionReason` — read it and fix the route, do not retry.

**1.2a — Hand the subagent its transcript directory.** The dispatch of `gad-intent` also carries
`subagents_dir: $HOME/.claude/projects/<slug do projeto>/<CLAUDE_CODE_SESSION_ID>/subagents` — it is
from there that the coordinator reads its own turns with `turnos-por-ciclo.py` at the close of the
stage. Without the parameter, the coordinator returns `turnos: nao_medido — transcript fora do
alcance`, which is a legitimate route (owner's decision of 11/09: layer 0 passes the path,
`nao_medido` as the fallback).

**1.3 — Routing the return.**
- `done` → route gate: `confere-rotas.sh <phase_dir>/.intent` (exit 1 → back to the SAME
  subagent, step 7b of intent.md, fail-closed) → `confere-etapa.sh 1` (includes
  `confere-reconciliacao.sh --final`: lists the D-NN citing a criterion changed since the
  sealed base, `D-NN-DESATUALIZADA`, informative; mechanical fence — SPEC/CONTEXT/review
  closed/chain zeroed/`.intent/` cleanup — and the measured `end`; exit 1 → same subagent).
  Keep from the return: `transparencia` (input of 6.2), `sinos` (for the banner) and announce
  `pausas_de_negocio` in one line. Bells with a skipped review (`intent_review: skipped`) →
  `skip` event + a line to the user + mandatory item in `itens_nao_rodados`. Continue.
- `needs_decision` — finding that touches requirement/criterion/oracle, or a deadlock (hard
  gate by definition, criterion 2 of Sub-rotina I; silence window → graceful pause) →
  `AskUserQuestion` (recommendation first) and continue the SAME subagent with the verbatim
  answers; route the new return by this list.
  - Sub-case `pre_spec_bloco: ausente|invalido` (only while SPEC or CONTEXT do not exist yet;
    fail-closed of `confere-pre-spec.sh`): the question has two exits — (a) migrate the
    PRE-SPEC to the block (`scripts/pre-spec-migra.py` drafts it from the prose for the owner to
    review) or (b) authorize the legacy route (the child reads the whole file; the
    `pre_spec_sem_bloco` bell is mandatory in the return and in the INTENT-REVIEW). Never
    continue with "zero decisions" in silence. The answer is durable
    (`.intent/pre-spec-route.json`) while the PRE-SPEC hash does not change.
- `blocked` — BOTH consultants installed but failing with no complete cycle (fail-closed,
  decision of 02/07: without a second opinion the intent does not proceed; ONE failing
  continues degraded with a bell; NONE installed becomes `skipped` in the pre-check) →
  Sub-rotina D. `intent_review: blocked` is already on disk (the next invocation retries).
  Handoff: "🔔 revisão de intenção bloqueada — autentique um dos revisores e re-rode
  `/go-and-do N`."

**1.3a — The fiscal now leaves a receipt.** `confere-etapa.sh <etapa>` writes, on a pass,
`<phase_dir>/.fence-<etapa>.ok` with the HEAD it checked, and deletes it on a fail (the pair of the
`.gate-fail-<etapa>.json` lock). `gad-intent` only returns `done` after running the fiscal itself
and seeing a valid fence. A return that says `done` **without** a valid fence on disk is an
incident of the subagent, not of the fiscal: log it and send it back to the same subagent, as the
gate already prescribes. `--dry-run` neither writes nor deletes a fence.

**1.3b — What the `transparencia:` of the return may carry.** The field may bring a line
`turnos: <literal output of turnos-por-ciclo.py>` or `turnos: nao_medido — <motivo>`; no new field
is mandatory and no parser changes. `ciclo0: dispensado (sem sino)` is the record that the phase
entered with SPEC and CONTEXT already done (written by the owner or already on disk) and that there
was therefore no bell to triage — it is not a gap, it raises no incident and it asks the user
nothing.

</stage>

<stage id="1.5" name="Contratos de design">

> Before planning because `gsd-plan-phase` consumes UI-SPEC/AI-SPEC as locked design and the
> 4.2/4.3 gates audit against them.

**1.5.1 — Mechanical setup.** `setup-contratos.sh <phase_dir> <NN> [--ui] [--ai]`: both
`pular`/`sem-flag` → skip the whole stage. `config_corrigida` non-empty → transparency (the
owner's flag beat a forgotten config — declared flip).

**1.5.2 — Dispatch.** `pre-despacho.sh 1.5` → dispatch the agent `gad-contratos` (Opus 5
medium, with Agent and Skill) with `prompts/contratos.md` + flags + the setup JSON. It hosts
`gsd-ui-phase` and `gsd-ai-integration-phase` inline (order UI → IA).

**1.5.3 — Routing.** `done` → `confere-etapa.sh 1.5` (asserts per flag; exit 1 sends back);
bells → transparency. `needs_decision` (inherited stops — detail in
`workflow-ui.md`/`workflow-ai.md`) → Sub-rotina I; the answer continues the SAME subagent.
`blocked` → Sub-rotina D.

</stage>

<stage id="2" name="Planejamento">

**2.1 — Resume.** Obey `etapa_2` from abre-rodada: `pular` → Etapa 2.5; `despachar` → 2.2.

**2.2 — Exit fence.** `pre-despacho.sh 2`.

**2.3 — Plan (via subagent).** Dispatch the agent `gad-plan` (Opus 5 medium — the entry
judgments have high leverage) with `prompts/plan.md` (`N`, `NN`, `phase_dir`, `project_root`,
base args `N --tdd`): it judges research (2.D) · mapper (2.E) · granularity (2.G), invokes
`gsd-plan-phase` and persists the checker trail (`.plan-checker/iter-N.yaml`, 2.B). Routing:
`done · planejado` → 2.4 (note research/mapper/granularity/bells for transparency) ·
`done · sem_plano` → `stop` event, stop · `needs_decision` → question + continuation ·
`blocked` → `stop`, stop.

**2.4 — Arrival fence.** `confere-etapa.sh 2` — asserts + extraction of `nao_autonomos` +
mapper bell. Exit 1 → send the list of what is missing back to the SAME subagent, whatever it claimed.

**2.4a — The `mapper_pulado` bell has an action, not just a landing.** When the fence returns a
non-empty `mapper_pulado`, cross it against the plans before moving on:

```bash
bash "$HOME/.claude/skills/go-and-do/scripts/confere-arquivos-novos.sh" "<phase_dir>" "<project_root>"
```

`veredito: mapper_obrigatorio` → hand the phase **back to the same `gad-plan` subagent** with the
list from `novos_producao` and the instruction to run the pattern-mapper before returning; log one
`incidente` (`origem=workflow 2.4a`, `detalhe="mapper pulado com arquivo novo de produção: <lista>"`).
`veredito: mapper_opcional` → note the bell for transparency and continue.
Empty `mapper_pulado` → nothing to do. Never decide this by reading the judge's prose: on F24.5 the
judge's reason ("phase only modifies files") is the very one this workflow's own prompt names as a
trap, and two new scripts were on the plans.

**2.4b — Close: `autonomous: false` resolved HERE (2.H).** For each plan in `nao_autonomos`,
classify the checkpoint:
- (a) decision answerable by text → ask NOW (the owner is present at the end of planning);
  the answer becomes a `DECISAO-DO-DONO` block attached to the execution dispatch; flip the
  plan to `autonomous: true`.
- (b) foreseeable human action (key, migration, login) → write `<phase_dir>/NN-ACAO-HUMANA.md`
  with the detailed step by step; the owner executes and confirms → flip the plan and delete
  the file (the fact becomes one line in `NN-DECISOES.md`).
- (c) runtime verification (`human-verify`) → deferred to the UAT (redundant with it): flip
  and the item enters the Etapa 5 agenda.
- (d) foreseeable `<precondition>` — beyond the `autonomous: false`, scan the PLAN.md for
  `<precondition>` (env var, `user_setup` step, artifact of a previous phase). A precondition
  you can check NOW that is false → it is a (b): goes into `NN-ACAO-HUMANA.md` before
  execution instead of becoming `blocking-human` mid-wave. True or uncheckable → leave it
  (the executor checks at run time).

</stage>

<stage id="2.5" name="Convergência do plano">

- `has_verification` (phase already built and verified) → skip 2.5, go to Etapa 3.
- `pre-despacho.sh 2.5` and obey `despacho`: `pular` (marker present) → Etapa 3 ·
  `skip_config` → declared degradation (`itens_nao_rodados`) and continue ·
  `bloqueio_sem_revisor` (exit 4 — PC-6: NO external reviewer installed, the phase does NOT
  continue) → ⏸️ relay `pergunta_ao_dono` and stop ·
  `bloqueio_plano_nao_resolvido` (exit 4 — S-11, tarefa 48l: some `NN-PLAN.md` still has
  `autonomous: false`, so 2.4b did not finish) → go back to 2.4b for the plans listed in
  `motivo`, never dispatch 2.5 with a plan still waiting on the owner · `ok` → dispatch (one
  absent = continue with the other; the `revisores` field says which).
- Dispatch the agent `gad-plan` (own def: Opus 5.5 medium, cache 1 h — EST-02, same wait
  profile as the 4.x gates) with `prompts/convergence.md`: it hosts
  `gsd-plan-review-convergence --codex --agy-revisor --max-cycles 3` (lanes via
  `roda-codex.sh`/`roda-agy.sh`), registers cycles (`registra-ciclo.sh`) and writes the marker
  (`grava-convergence.sh`).
- Routing: `done · convergiu` → `confere-etapa.sh 2.5`; note `revisores_efetivos`/`sinos` and
  continue · `done · escalou` → `stop`, stop with the digested impasse · `needs_decision` →
  question + continuation · `blocked` → `stop`, stop.

</stage>

<stage id="3" name="Construção">

**3.1 — Resume.** `has_verification` → skip the whole Etapa 3 (plans arrive already flipped
by 2.4b).

**3.2 — Parallelism (mechanical authority).** The `pre-despacho.sh 3` that opens 3.3 (🔒)
reads `use_worktrees`/`parallelization`, applies `baseRef: head` via `worktree set-baseref`,
runs the `base-check` and measures the waves of ≥2 incomplete plans.
- `despacho: ok` → go to 3.3.
- `despacho: bloqueio_paralelismo` (exit 4) → ⏸️ `AskUserQuestion` with the JSON's
  `pergunta_ao_dono`, which already carries the real `base-check` message — or, when `motivo`
  starts with `plan_gate_ausente_ou_reprovado:`, the choice «replanejar (volta à etapa 2) ou
  aceitar o despacho sabendo que a onda pode serializar». Do not diagnose on your own nor
  apply an antidote by hand: the script measures instead of presuming. **Owner accepts the
  blocked dispatch** → record the stage-3 checkpoint (`run-log.sh checkpoint "3 construcao"`)
  BEFORE dispatching, not after — a dispatch accepted this way is still an etapa-3 dispatch and
  needs its window open for the run-log to attribute it correctly (FM-02EXE).
  **Exception — `acao_mecanica: true`** (`motivo` starts with `precondicao_worktree_obsoleta:`):
  no question. Fix the listed PLAN.md yourself exactly as `pergunta_ao_dono` says (drop
  `isolation: none`, rewrite the precondition to the worktree-fixtures sentence), commit, re-run
  `pre-despacho.sh 3`, and log `🤖 decidi sozinho` in `NN-DECISOES.md` (Sub-rotina I).
- The close of 3.3 (`confere-etapa.sh 3`) extracts `paralelismo_observado` from the run-log (with
  `duracao_onda_s`/`plano_mais_lento_s`), `suite` (launches of `roda-suite.sh`) and
  `prova_avisos`/`prova_falhas` from the SUMMARYs — informative, for the `/audit-gad`
  briefing — and fails if `use_worktrees` turned `false` during the stage.

**3.3 — Execution.** The fence opened in 3.2 (`pre-despacho.sh 3`). Default route = subagent (re-check `nao_autonomos`):
- All autonomous (normal case) → dispatch `Agent(subagent_type="gad-execute")` with
  `prompts/execute.md` (args `N --auto --no-transition`), **without `model:` and without
  `effort:` in the call** — the def pins Opus 5 / medium, and `gad-lifecycle.sh` denies a
  `gad-*` dispatch whose call disagrees with the def (E7(b); F24.5 lost one dispatch of
  `gad-verificador` to exactly that). The def carries `experimental: cacheTtl: 1h`: on F24.5
  this host spent 75 % of the stage waiting, and 30 expirations of the 5-minute cache cost
  US$ 57 of its US$ 94 (bench A, 12/09/2026: after a 6-min wait the new def re-read 44 k from
  cache and wrote 214). If the dispatch fails because the def is not installed, that is an
  installation error — stop and tell the user; it is not a reason to fall back to the inline
  route. The host hosts `gsd-execute-phase` — executor waves (layer 2) → code + commits +
  SUMMARY → verification. Inherited stops become `needs_decision`; human action →
  `done · incompleto`. Routing: `done` (any verdict) → 3.4 (the crossroads reads the DISK,
  not the return) · `needs_decision` → question + continuation · `blocked` → `stop`, stop.
- Some `autonomous: false` left → inline (`Skill gsd-execute-phase --auto --no-transition` in
  layer 0 — human interaction is native here). `--auto` auto-approves verification checkpoints
  and takes option 1 at decision ones; `--no-transition` prevents auto-advance. `--auto` does
  NOT silence regression/schema/conflict/`human-action`/`blocking-human` (see stop_points);
  if the owner defers an action, 3.4 closes via Sub-rotina D on the way back. Test-suite
  discipline (suite as gate, at most 1× per wave) lives in `prompts/execute.md`.

**Fiscal receipt before `done`.** A `done` return is only acceptable when
`<phase_dir>/.fence-3.ok` exists and its `head` equals the current HEAD. The host writes it by
running `confere-etapa.sh 3 --fase <N> --projeto <root> --sem-telemetria` itself; that flag
evaluates and writes the fence (and clears the lock) **without** measuring tokens and **without**
logging an event, so it does not leave a second `end` for the stage. Receipt absent, or `head`
stale because a commit landed after it: return the list of what is missing to the same subagent,
whatever it claimed. F24.5: the execution host returned «pronto · completo · 9/9» while the fiscal
was failing — the second time in the same round that a host declared done without the gate.

**You still run the fence yourself.** Your `confere-etapa.sh 3` (no `--sem-telemetria`) remains
the authoritative arrival gate and is what writes the stage's `end`. The host's run is a receipt,
not a substitute: measured on F24.5, the stage-3 fiscal takes about 7 seconds (it reads the suite
state, it never relaunches a suite), and the design rule since decision 2.C is that layer 0 does
not take the subagent's word. If a future phase measures that fiscal above 60 s, bring the number
back as a question.

**The plan's contract is not rewritten after the fact.** Editing a PLAN.md's `files_modified`
after that plan has executed is forbidden — the wave computation already ran on the old list, so a
collision between plans of the same wave becomes invisible. The answer to `FORA-DA-LISTA` is a
declaration: the line `ARQUIVO-NAO-DECLARADO: <path>` in the plan's SUMMARY, with the reason
next to it, committed. `confere-etapa.sh 3` accepts the declaration and reports it under
`informativos`, and re-checks intra-wave collision against the real commit lists
(`colisao_real_onda`). F24.5: four PLAN.md were edited at 23:42 and 23:44, after execution, so
the gate would pass.

**One `incidente` per item, at the time of the fact.** The execution host now writes each
incident to the run-log when it happens. When its return arrives, log only the items that are
**not** already in the run-log (match by `detalhe`), so the count is not inflated. F24.5: the
eleven incidents of the stage all landed in the same second, at close, and the audit lost the
order of events.

**3.4 — Crossroads.** Completeness first: `gsd_run query phase-plan-index N` (lib of
Sub-rotina E) — a plan without `SUMMARY.md` → execution incomplete, blocked → Sub-rotina D with
the exact action (never treat it as `human_needed`). Otherwise, the VERIFICATION.md status:
- absent, or present but stale (the phase took commits after it): **do not re-invoke
  `gsd-execute-phase`** — with `VERIFY_STATUS=stale` and `PHASE_MARKED=false` its route is
  `update_roadmap`, which marks the phase complete **without** verifying (F24.5: the agent
  disobeyed the instruction and saved the phase). Dispatch `Agent(subagent_type="gsd-verifier")`
  directly, synchronous, handing: `phase_dir`, `NN`, the plan ids, and **the test scope** — the
  modules touched since the previous VERIFICATION
  (`git diff --name-only <sha-da-verificação>..HEAD -- src tests`), plus the FULL suite's
  measured numbers (rc, duration) from the stage-3 run. The dispatch carries, verbatim, the
  same sentence `prompts/execute.md` uses for the same handoff: «Entrego os números medidos da
  suíte completa e o escopo de módulos tocados. A suíte completa já é gate desta etapa; relançar
  é decisão sua, com justificativa.» (FJ-01EXE — resolves the contradiction between this stage
  and the host prompt, which used to forbid the verifier from ever relaunching). The project's
  own testing rule comes first when it exists (`CLAUDE.md`; the inspired's says, in writing, to
  run only the touched module).
  F24.5: an unscoped dispatch ran the fast suite whole for 30+ min with 4 GB of swap, and the
  full suite took 56 min 50 s against a measured band of 17–35 min. Still absent after the
  re-verification → Sub-rotina D.
- `passed` → Etapa 4 · `human_needed` → note it (becomes PENDING of the UAT) and continue ·
  `gaps_found` → 3.5.

**3.5 — Gap closure (1× only).** Replan (`prompts/plan.md`, args `N --gaps`) → anchor the
re-convergence: add to the `NN-CONVERGENCE.md` frontmatter the line
`gap_replan: "<data> — N planos gap_closure; commits <shas>"` and commit → re-execute (3.3
rule) → re-verify. `passed`/`human_needed` → Etapa 4; still `gaps_found` → Sub-rotina D
(`gaps persistentes`). One attempt only.

**Instrument under judgement.** When a `confere-*.sh`, a hook or a fork script is failing the
round **because of a defect of its own**, it is evidence, never a target. Write
`<phase_dir>/.gate-fail-<etapa>-evidencia.txt` with the command, the literal output and the line
you believe is wrong; commit it; route the decision to the user through the hard gate
(Sub-rotina I). Never `sed`, never `Edit`, never a "temporary" patch to the instrument while the
round it judges is open — not even when your diagnosis is right. F24.5, 23:47–23:49: the
diagnosis **was** right and the gesture was still wrong; only the permission classifier stopped
it, twice.

**Instrument versus disk.** When an instrument's reading contradicts the disk by an order of
magnitude (78 minutes read as «5 s»; nine agents read as one), the hypothesis is that the
**instrument** is wrong, not the fact. Before any report to the user, run the primary
measurement and carry **that**:

```bash
bash "$HOME/.claude/skills/go-and-do/scripts/numeros-da-fase.sh" <phase_dir> <NN> --executores
```

The report to the user carries the primary number and the disagreement («the meter says X, the
clocks say Y, and here is why the meter is wrong»), never the open doubt. F24.5: layer 0 told
the user «the parallelism may not have happened» with the clocks of all nine executors on disk.

</stage>

<stage id="4" name="Gates de qualidade">

> Layer 0 fully mechanized (4.A): for EACH gate, `pre-despacho.sh 4-<gate>` resolves
> flag/config/resume into an exit code and `confere-etapa.sh 4-<gate>` asserts the artifact
> and extracts the canonical verdict. What remains for judgment: digesting `needs_decision`
> and the 🔔 prose at the close.

### 4.1 — Code review (via subagent)
- `pre-despacho.sh 4-code-review` → `ok`? Dispatch via Sub-rotina H as
  `Agent(subagent_type="gad-gates")` (own def: Opus 5, cache 1 h — FM-F4RLR-03GAT; also
  iterations 2+ and 4.1b) with
  `prompts/code-review.md` (`iteracao: 1`): hosts `gsd-code-review N --fix --auto` with the
  parallel Codex lane (4.D, merged as `fonte: codex`; codex absent does not block). Iterations
  2+ and the 4.1b gate dispatch with `iteracao: 2+` — the subagent narrows via
  `calcula-files.sh` (4.C).
- On return: `confere-etapa.sh 4-code-review` (extracts `status`/`critical`/`warning`/
  `total`). Always continues; remaining `critical` → strong 🔔. Keep `uat_humano` (input of
  5.3). `blocked` → `stop`, stop.
- **`needs_decision`** → question + continuation via Sub-rotina I — including a finding the
  reviewer tagged "não aplicar sem o dono": it returns `needs_decision`, never `done` with the
  finding silently skipped (FJ-01GAT). Ask, apply the fix INSIDE this gate once answered, and
  only then let the fiscal → `end` → recibo sequence close.
- **Gate 4.1b is its own re-dispatch of 4.1, not a footnote of it** (FM-02GAT): open a
  checkpoint labeled **"4.1b re-review"**, run `pre-despacho.sh 4-code-review` and
  `confere-etapa.sh 4-code-review` exactly like 4.1, and stamp its own `.fence-4.1b.ok`. It
  does not inherit 4.1's fence.
- **The host never fixes a 4.1b finding itself** (FJ-04GAT): it goes to `gsd-code-fixer` with a
  scope EQUAL to the finding's own scope. Widening that scope, or changing observable behavior
  beyond what the finding names, is a question to the owner, not a host judgment call. Every
  fix from the 4.1b fixer forces a re-review — it is not exempt from the loop it triggered.
  Fixer briefing: run the finding's own suite before returning, and list, per commit, "what
  else reads or writes this state" — the re-review starts from that list (MGTk-01GAT).

### 4.2 — UI review · only with `--ui` → conduct by `workflow-ui.md`.

### 4.3 — Eval review · only with `--ai` → conduct by `workflow-ai.md`.

### 4.4 — Secure phase (via subagent)
- `pre-despacho.sh 4-secure` → `ok`? Dispatch as `Agent(subagent_type="gad-gates")` with `prompts/secure.md`. A threat decision
  comes up as `needs_decision` already digested (4.E: threat, severity, options with the
  recommendation first).
- On return: `confere-etapa.sh 4-secure` — exit ≠ 0 (`threats_open` > 0 or acceptance
  without owner) is the ONLY blocking gate of the stage: ⏸️ stop. Secure touched src/ AFTER
  the review → gate 4.1b: `calcula-files.sh --tocados "<arquivos>"` → narrowed re-dispatch of
  4.1.

### 4.5 — Validate phase (via subagent)
- `pre-despacho.sh 4-validate` → `ok`? Dispatch as `Agent(subagent_type="gad-gates")` with `prompts/validate.md`. ⏸️ Gaps →
  `needs_decision` (Fix all recommended). On return: `confere-etapa.sh 4-validate`. Continue.
  When gate 4.1b exists (secure or a late commit reopened it), dispatch 4.5 in PARALLEL with
  4.1b instead of after it — validate only reads the map and runs the suite; if 4.1b fixes
  something, re-run 4.5's suite alone afterward, not the whole validate (MGTm-01GAT).

**Every gate host reports incidents at the moment they happen** (same contract as C1/C3),
via `run-log.sh "<phase_dir>" "<NN>" incidente "<etapa>" --kv origem=… --kv detalhe=…` — before whatever else the
host was about to do (FM-07GAT).

</stage>

<stage id="5" name="UAT interativo automatizado">

> Own UAT, not raw `verify-work`: we reuse the derivation LOGIC (5.3) and drive the browser
> ourselves (5.4, subagent + `uat-playbook.md`). The UAT interacts for real and proves
> objectively (HTTP status + console + persisted state).

The 4 baskets (full craft in `uat-playbook.md`; here you only route): 1 · pass — objective
proof closed · 2 · issue — failed objectively → fix cycle (5.5) · 3 · não-pude-verificar —
login without vault, 2FA, captcha → `[pending]`/`blocked`, blocks the ship (hand-back) ·
4 · assumed — only subjective judgment left → ships with a warning in the resumo.

Post-ship observation is not a fifth `result:`. A scenario whose mechanics are proven by a
test and whose question only production can answer leaves `NN-UAT.md` for `NN-POS-SHIP.md`
(5.6). It does not block this phase's ship; with `bloqueia_proxima: sim` it raises
`pos_ship_alerta` when a later phase opens.

**5.1 — Resume (by STATE of `NN-UAT.md`).** Absent → 5.3 · without `pre_uat: executed` → 5.4
(the subagent is idempotent per scenario) · `executed` + `issue` without
`pre_uat_fix_cycle: done` → 5.5 · with the marker → Sub-rotina D (never a 2nd cycle) ·
`executed` without open `issue`, with basket 3 and without `pre_uat_reuat: done` → 5.6 ·
otherwise → Etapa 6. Resuming a phase whose etapa 6 previously closed with a `handback` stop:
just enter through `pre-despacho.sh 5` as usual — its checkpoint is the first etapa `5 …`
checkpoint after the hand-back, and `run-log.sh` links it automatically (`retomada_de_seq`,
`retomada_de_sessao`, pointing at the hand-back's `stop` line — FM-F4RLR-04UAT); nothing here
calls that link, it is mechanical. Measurement tools then sum the two etapa-5 windows instead
of treating either as orphaned.

**5.3 — Generate `NN-UAT.md` (via SUBAGENT).** `pre-despacho.sh 5`. Dispatch an `Agent`
(`model: sonnet`, synchronous) to reuse the verify-work derivation:
- (a0) mechanical classifier first (5.D) — **one SUMMARY per call**, in a loop. The command is
  `gsd_run uat classify-coverage --summary <file>`. It accepts neither `--phase-dir`
  (`Error: unknown flag "--phase-dir"; accepted: --summary <value>, --file <value>`) nor a bare
  invocation (`Error: SUMMARY file required`), and a second `--summary` in the same call is
  silently ignored — only the first file is classified. Measured on GSD 1.13.0, 11/09/2026:
  ```bash
  for s in "<phase_dir>"/*-SUMMARY.md; do
    [ -e "$s" ] || continue
    gsd_run uat classify-coverage --summary "$s" || echo "classify-coverage falhou em $s"
  done
  ```
  A deliverable covered by a passing automated test enters as `pass, source: automated` without
  becoming a browser scenario (fail-safe: never drop a deliverable). A SUMMARY the classifier
  could not read is a deliverable that goes to the UAT as `[pending]`, never one that is dropped;
- (a) find_summaries → (b) extract_tests — user-observable behaviors; visual scenarios from
  the UI-SPEC (or SUMMARY without `--ui`); cold-start smoke only when a SUMMARY touched
  server/app/db/migrations/seed/docker, limited to boot + health ("clear ephemeral state" is
  destructive → `[pending]` for the human);
- (c) create_uat_file — template `$HOME/.claude/gsd-core/templates/UAT.md`,
  `status: testing`, all `[pending]`, frontmatter `pre_uat: generated`;
- (d) reviewers' input in the dispatch: `uat_humano` from 4.1 + `human_needed` from 3.4 —
  this is where the promised "becomes UAT" materializes.

**5.4 — Run the UAT (via SUBAGENT — ALWAYS, with or without GUI).**
> The subagent — not you — drives the browser. A phase without GUI is not a reason for
> inline: the playbook has `<non_gui_surfaces>` (CLI/API/lib — proof by objective output) and
> `<push_on_it>` (🔍 probes), which only operate if the subagent is dispatched with it. Live
> proof behind secrets → layer 0 PREPARES the sanctioned path (wrapper) and the subagent runs
> it.

1. The server belongs to the UAT window (5.A): the subagent brings it up/down via
   `dev-server.sh` (`workflow-dev-server.md`). Phase without server: declare it in the prompt
   ("use `<non_gui_surfaces>`").
2. 🔒 `pre-despacho.sh 5` (context gate + checkpoint of the run; a resume that lands here
   directly still opens the fence). Dispatch: `Agent` `model: sonnet`, `general-purpose`,
   synchronous. Minimal prompt: "Leia
   `$HOME/.claude/skills/go-and-do/uat-playbook.md` e conduza o UAT da fase NN à risca. O
   `NN-UAT.md` está em `<uat_path>`. Sua janela é dona do dev server. Use a sessão
   `uat-fase-NN`. [Sem GUI: cenários são api/logic/cli — use `<non_gui_surfaces>`.] [Wrapper:
   rode a prova via `<wrapper absoluto>`; não leia nem ecoe segredos.] [Vault: profile
   `<args.vault_profile>`.] [Superfície do projeto: leia `<uat_superficie>` e dirija a stack
   só por ela.] Classifique nos 4 baldes, aplique `<push_on_it>` no balde 1, escreva
   results/Gaps/evidências no `NN-UAT.md`. Devolva só o qualitativo do `<return_contract>` —
   números são contados por script."
3. Fence: `confere-etapa.sh 5` — reconciles baskets/probes/evidence from disk, lints the
   gap-YAML, runs the native `uat-passed` predicate, scans for SECRETS (gitleaks-style
   patterns, never generic PII) and, on pass, promotes `pre_uat: executed` (single writer —
   5.C/5.E). Exit 1 → back to the SAME subagent. Do not ingest `NN-UAT.md`. **Fence passed →
   commit now** (`commita-artefatos.sh <phase_dir> <NN> uat`, FM-03UAT): whatever exit stage 5
   takes next (5.5, 5.6, straight to Etapa 6), the UAT result the subagent just wrote is
   already durable, instead of riding on whichever later step happens to commit next.

> Cardinal rule of the playbook: never `pass` on the ambiguous — uncertainty → basket 3 (the
> real basket 3 is a login/2FA wall).

**5.5 — Fix cycle (1× only) when there is basket 2.**
1. `pre-despacho.sh 5` (cycle checkpoint).
2. Replan (`prompts/plan.md`, args `N --gaps` — reads the gaps from `NN-UAT.md`).
3. Re-execute (3.3 rule, args `... --gaps-only` — strict scope).
4. Re-review on the fix's files: 4.1 dispatch with `iteracao: 2+` — without the resume check
   (the existing `NN-REVIEW.md` is expected; skipping would break "audited before ship" for
   the new code).
5. Re-UAT only on the `issue` scenarios — same server-owning window, which brings up the NEW
   server (post-fix code; built surface → re-run the build first).
6. `confere-etapa.sh 5 --fix-cycle` validates and stamps `pre_uat_fix_cycle: done` (single
   writer — 5.1 uses it to never fire a 2nd cycle).
- Closed → Etapa 6. Persisted → Sub-rotina D (`bug de UAT persistente`).

**5.6 — Basket 3: post-ship triage + re-UAT (1× only).** Runs when 5.4 (or a resumed round)
leaves basket 3 without open `issue`. Order matters: re-run first, triage what is left.
1. `pre-despacho.sh 5`. `uat_superficie` present and some basket-3 note blames a missing
   credential/surface → re-dispatch 5.4 restricted to the basket-3 scenarios, with the
   `[Superfície do projeto: …]` clause. Fence: `confere-etapa.sh 5 --reuat` (stamps
   `pre_uat_reuat: done`, single writer). No `uat_superficie` → skip the re-run, still stamp.
2. Before dispatching the skeptic: `scripts/pos-ship.py --conferir <phase_dir> <NN>
   <project_root>` — read-only format check of the `pos_ship: candidato` blocks (FJ-06UAT).
   Exit 1 (JSON `malformados` non-empty — an indented `pos_ship:` marker, or a genuine
   `candidato` block missing `prova_mecanica`/`bloqueia_proxima`/`verificavel_em`) → return to
   the conductor now with that list; do not spend the skeptic's window on a malformed
   candidate. Exit 0 → proceed to step 3.
3. Any scenario carrying `pos_ship: candidato` → dispatch the skeptic (`Agent`,
   `model: sonnet`, synchronous) with `prompts/uat-pos-ship.md`; it writes
   `.pos-ship-vereditos.json`. Whoever classifies never judges.
4. `scripts/pos-ship.py move <phase_dir> <NN> <project_root>` — moves only what passes its six
   conditions; a refused candidate stays in `NN-UAT.md` as basket 3 and keeps blocking the
   ship. Then `confere-etapa.sh 5` again (it may now promote `status: complete`) and
   `commita-artefatos.sh`.
- The re-run produced a new `issue` → 5.5 (the fix cycle is still unspent; its re-UAT uses the
  same project surface). Basket 3 empty → Etapa 6 by the ship route. Still there → **commit the
  UAT result before leaving this stage** (`commita-artefatos.sh <phase_dir> <NN> uat`, the same
  single writer as 6.3b) and go to Etapa 6 hand-back. Never a 2nd 5.6.

</stage>

<stage id="6" name="Encerramento + ship">

Two terminal routes: ship (happy path) and hand-back (returns without shipping).

**6.1 — Route the outcome (mechanical).** `pre-despacho.sh 6` and obey `rota`: `pausa`
(basket 2 left) → Sub-rotina D · `handback` (basket 3 or `--no-ship`) → 6.4-HB · `ship` →
6.4-SHIP. The JSON brings `git_remote` (trigger of route B), `uat_passed_raw` (the MEASURED
native predicate — paste it into the ship briefing) and `transparencia` (6 extracted lists:
basket 4 · basket 3 · `transparencia:` of the INTENT-REVIEW · run-log skips ·
`riscos_aceitos` · `incidentes` — the 6th, FJ-04ENC, is every `incidente` event of the current
session). You do not decide the route; you read the verdict. `verification_stale.stale: true` (code
committed after the last commit that touched `NN-VERIFICATION.md`) → **re-verify BEFORE
dispatching the close**, same rigor as the fresh check; do not let the ship's own preflight
discover it 12 minutes in — the digest is the same, only the order moves earlier. The `handback`
route's closing `stop` carries etapa `handback` (6.5) — that is today's vocabulary for "this
run of etapa 6 did not finish, it returned control"; it is a stop, not a finished etapa 6, and
the next 5.1's checkpoint links the resumed window (5.1).

**6.2 — Compose "🔔 O que precisa de você agora" + transparency.** Gather what deserves
attention even though the run continued: review Criticals (+ `uat_humano`), UI pillars 1–2 /
Registry Safety, eval below PRODUCTION READY, partial validation, `ciclo_final_nao_rodou` from
the intent, and the leftovers — the `[desejável]` criteria not met, one per line, with the
plan they stayed in (`must_haves.desejaveis` of the PLAN.md × `## Desejáveis pendentes` of the
VERIFICATION.md). A leftover is closing information, not a replan pending. The transparency
lists already came EXTRACTED in 6.1 (basket 4 · basket 3 · `transparencia:` of the
INTENT-REVIEW · run-log skips · `riscos_aceitos` from secure — a risk acceptance is the
owner's signature: they REVIEW it in the resumo, they do not discover it in the code — ·
`incidentes`, the 6th list, FJ-04ENC). Your job is to write the prose.

**6.3 — Executive summary (final mode).** Sub-rotina F with `modo: final`, the outcome and
the 6.2 lists. F writes the transparency block at the TOP. Idempotent. Commit as per F.
> Order: the resumo is committed BEFORE the close — it enters the tree the ship packages.

**6.3b — Clean tree for the ship.** `commita-artefatos.sh <phase_dir> <NN> uat` (single
writer; both routes). Moved evidence = `NN-UAT.md` amended in the same step: evidence parked
outside git (e.g. a PDF with a secret) → the scenario's `evidencia:` field points to the REAL
location with the reason (a ghost path makes the proof unauditable). Exit 1 = refusal of the
safety ceiling (`uat-evidencia/` with more than 20 files): treat as an environment block, not
best-effort. Do not proceed to the ship; relay the `RECUSA:` message to the owner — it carries
the count and the path — and wait for manual selection of the legitimate files. On refusal
the script exits before any `git add`, so `NN-UAT.md` is not committed either; re-running
returns the same refusal.

**6.4-SHIP — Ship.**
- Route B (`git_remote: false` — 6.E, your judgment): the project ships by its own path by
  design. Find the alternative ship in the PROJECT's own artifacts (project skills, CLAUDE.md)
  and execute with prior authorization (owner's decision 09/08 — no question, no hand-back),
  recording choice and reason in `NN-DECISOES.md`. No path found → honest `blocked`. No new
  canonical config — the source is the project, the judge is you. Automatic merge of the own
  path (e.g. `ship.py --merge`) is an approved route (owner, 27/08) — do not ask; keep the PR
  number/URL and the fact "mergeado" for 6.4c and the banner.
- Route A (with remote) — via `Agent(subagent_type="gad-gates")` (cache 1 h: the close host
  is the one long subagent of the stage that stops mid-way for a decision — FM-F4RLR-06ENC)
  with `prompts/close.md`: hosts the skill
  `close-phase N` (learnings → promotion with evidence "UAT automatizado" → docs commit → PR
  → auto-"Skip" review stamped → direct merge, 6.D). Inherited brake: it only promotes/ships
  with the native `phase uat-passed` predicate clean — `assumed` (basket 4) FAILS that
  predicate and the brake holds-and-asks (by design). Do not assert the gate state in the
  briefing — paste the MEASURED `uat_passed_raw` from 6.1.
- Routing: `done · shipado` → keep the PR (#N and URL) and go to 6.4c ·
  `done · uat_reprovado` → the brake acted (investigate `motivo_reprovacao` on disk) →
  Sub-rotina D · `needs_decision` (uat-passed blocks-and-asks) → question + continuation ·
  `blocked` (environment: no origin, gh not authenticated, wrong branch) → respect it: `stop`
  event (etapa `ship`, reason `ship bloqueado — <motivo>` in the 10th argument), note it in
  the banner and stop (re-running
  resumes at the ship).

**6.4c — Amend the outcome in the resumo.** Replace the `## Desfecho do ship` placeholder of
`NN-RESUMO-EXECUTIVO.md` with 2–3 FACTUAL lines (direct Edit): `shipado` → real PR + the true
next step of THIS flow (auto-merge → say it merged; never promise a review the flow does not
have) · `blocked` → the reason + the real publication path (no PR exists — do not suggest one
does). Reconcile the body with the post-close state (promotion `human_needed` → `passed`:
amend the old mention or append a note). The amendment obeys the state-of-the-world rule
(`prompts/resumo.md`): real lookup, source+date, or omit. Commit (best-effort). Idempotent:
section already filled → do not rewrite. The amendment reports the ship's RETURN, never an
expectation. Reconcile in the body, pointed edits only (never regenerate the resumo for this):
(1) fold into the incidents block whatever the close's return brought; (2) any decision the
close reverted (e.g. "did not re-verify") gets a note next to the original mention; (3) the
friction count is updated to match.

**6.4-HB — Hand-back (no ship).** Banner in the standard frame — title
`GO-AND-DO · Fase NN — pronta para o seu UAT`, fields `Balde 3` (how many) and `Resumo`
(path) — and the pending items:
1. `/gsd-verify-work N` — resumes exactly at the basket-3 scenarios.
2. `/gsd-add-tests N` — broad suite.
3. `/close-phase N` after the clean UAT *(or re-run `/go-and-do N` without `--no-ship`)*.

**6.5 — Reconciliation + self-check + final banner.** After reconciliation and the receipt, publish
the close's own commits (`git push`) as an explicit step — or, when the project forbids direct
push to master, say so in the banner as a pending item with the exact command. The stage-6
fence warns (never fails) when local ends ahead of the remote. On the ship route, BEFORE the fence:
`reconcilia-docs.sh --pr "#N <url>" [--proxima M]` (needed because route B does not run
gsd-ship and route A only touches 2 fields — STATE.md/ROADMAP/REVIEWS would stay stale). Exit 3 (`FORMATO-INESPERADO`) → stop before the fence: the STATE.md
`status` is in a form neither script can judge (typically a sentence where the token
`executing` or `between_phases` is expected). Fix the field to the token and re-run the
script — `confere-etapa.sh 6` fails the same case via the `state_formato` assert, on purpose.
Exit 2 = invalid usage; exit 0 = "ran, pendings in the banner". Read `acoes`/`pendentes` from
the JSON; pending = note in the banner. Commit (best-effort:
`docs(fase NN): reconcilia espelhos de estado pós-ship`). Then `confere-etapa.sh 6` —
PLAN×SUMMARY (plan without SUMMARY = failure) + timestamp anti-placeholder + partial AC in a
SUMMARY × VERIFICATION `passed` + STATE.md still `executing` (reconciliation did not run);
🔔 on divergence (divergent ts → fix to the real git ts and record in `incidentes:`).
Reconcile the TaskList (anti-orphan, Sub-rotina C). Run `varre-worktrees.sh --projeto "$ROOT"`
(report only): every `com-trabalho` or `suja` copy in the JSON enters the executive summary
as a pending item with the owner (`cópia <branch>: <commits> commits, <idade_dias> dias`); a
phase does not close with work
hidden in a copy. Then:
- Ship: frame with title `— shipada`, fields `PR` (with the REAL state: `#N — mergeado` or
  `#N — aberto`) and `Resumo`; below: PR URL, transparency block and add-tests as a post-PR
  step. End.
- Hand-back: the 6.4-HB frame (do not duplicate the box) + basket-3 items + pendings.
In both: `stop` event (etapa `ship`/`handback`), remove the pointer
`.planning/.gad-rodada-ativa.json` (PC-3) and `commita-artefatos.sh <phase_dir> <NN> runlog`.
Idempotent: re-running after the ship lands here and reprints.

**6.6 — Guard.** If the self-check reveals a plan without `SUMMARY.md` (a human action that
escaped), do not ship: go back to Sub-rotina D (D generates a `parcial` that overwrites the
`final` — the disk stays correct).

</stage>

</stages>

---

<subroutines>

<subroutine name="A — gate de contexto (antes de cada comando principal)">

The gate runs INSIDE `pre-despacho.sh <etapa>` — every 🔒 step already executes it when
opening the fence. Obey the exit code:

- exit 0 — `ok` (continue; announce in one line what it measured: "contexto em 180k/400k —
  seguindo"), or `pular`/`skip` (the stage does not run; the event is already written).
- exit 3 — `stop`: context ceiling. The script already wrote the event, removed the pointer
  and returned the ready handoff → Sub-rotina D with reason `contexto em NNk`.
- exit 4 — `bloqueio_sem_revisor` (2.5 only) or `bloqueio_paralelismo` (3 only): relay
  `pergunta_ao_dono` and ⏸️ stop. `bloqueio_plano_nao_resolvido` (2.5 only): back to 2.4b.
- `status=unknown` in the JSON → continue, but state the `reason=` in one line (deliberate
  fail-open of MEASUREMENT — resumability covers it).

Rationale (do not re-litigate): absolute ceiling of 400k tokens loaded (not window fraction),
below the harness auto-compact (~460k), because stop-and-resume fresh beats compaction
(state on disk + atomic commits + handoff). Adjustable via env `CONTEXT_TOKEN_LIMIT`. The gate
under-measures on purpose (layer 0 only, no advisor turns), hence the slack.

Auto-compact detector (mechanical): `run-log.sh` writes `compact` when checkpoints of the same
session drop by >100k. On seeing it (or noticing the drop): announce in one line and re-anchor
— the sub-routines still apply, the script continues from where the DISK says it is.

Known limitation: the gate only measures BETWEEN commands — it does not interrupt a `Skill`
midway. This matters almost only on the inline route of 3.3; if unavoidable on a huge phase,
split first (`/gsd-phase`) or pause manually (`/gsd-pause-work`).

</subroutine>

<subroutine name="B — dev server (ponteiro)">

Mechanized in `scripts/dev-server.sh` (`up` = persisted recipe or heuristic + port wait +
auto-persistence; `down` = kill by PID session). The craft and the window-owner rules are in
`workflow-dev-server.md` — read it when the phase has a server to bring up (UI review / UAT);
a phase without server never loads that file.

</subroutine>

<subroutine name="C — lista de tarefas ao vivo (TaskList)">

The TaskList gives live visibility of the pipeline. It is ephemeral (session only) — never
the source of truth: real state is on disk; the list only mirrors. Only the orchestrator
touches it.

- Scripts compute (S.C): the `tasklist` snapshot of `abre-rodada.sh` (and the reconciliation
  of `confere-etapa.sh 6`) returns task → desired state, computed from disk (15 possible
  tasks: intent 1–3, contracts 4–5, plan 6, convergence 7, execute 8, gates 9–13, UAT 14,
  close 15 — only the ones applicable to the run are created). You only apply
  `TaskCreate`/`TaskUpdate` to mirror. On a resume, the list is born faithful to what is done.
- Availability first: the task tools are a runtime flag (they vanish without changelog).
  Without `TaskCreate`/`TaskList` in the window (nor via `ToolSearch`), skip the whole
  sub-routine: declare once ("TaskList indisponível — seguindo pelo disco") and mention it in
  the resumo.
- Discipline: dispatching a 🔒 step → `in_progress` on the task(s) it covers; done (artifact
  on disk) → `completed`. A `needs_decision` return leaves `in_progress`.
- On a pause: the current task stays `in_progress` — the next run's setup re-reads the disk
  and corrects. At the close (6.5): anti-orphan sweep — a leftover `in_progress` task = 🔔
  (a stage that will no longer run → complete it with a note on why).

</subroutine>

<subroutine name="D — parada graciosa (pause-work)">

Use when implementation work that depends on the owner is left: human action
(`human-action`), waves blocked by it, intent consultants `blocked`, persistent gaps (3.5),
open threat (4.4), persistent UAT bug (5.5), ship `uat_reprovado`, hard gate in the silence
window (Sub-rotina I), or the context ceiling (Sub-rotina A). Close with a clean handoff:

1. End the live work — including what TaskStop does not kill. In this order:
   1. `ListAgents` — enumerate the live subagents. The list is the source of truth: stop all
      of them, not just the active one (a live child keeps writing artifacts after the pause).
   2. `TaskStop` on each child the list returned.
   3. `varre-orfaos.sh <phase_dir>` — the background processes that survive TaskStop (disk
      waiters, codex). It identifies by link to `<phase_dir>`, groups by `pgid` and only
      reports.
   4. Exit 1 (orphans exist) → `varre-orfaos.sh <phase_dir> --matar`: TERM on the group, wait
      5s, then KILL. It refuses in three foreseen cases — more than 10 candidates (`RECUSA:`),
      `GRUPO-MISTO` and `GRUPO-PROPRIO`. On any refusal, carry the reported pids to the
      handoff line of step 4 and continue.
   5. `varre-worktrees.sh --projeto "$ROOT"` — the copies (worktrees) the pause leaves behind.
      GSD's `reap-orphans` only sees a copy with a `locked` file and already merged. Report
      only. Each `com-trabalho` or `suja` entry of the JSON becomes a line in the handoff of
      step 4: `cópia <branch>: <commits> commits, <idade_dias> dias — arquivar com --arquivar;
      remoção com o dono`.
   6. `confere-etapa.sh pausa` — closes the interrupted stage in telemetry: measures the open
      window with mede-tokens and writes the `end` with the CANONICAL checkpoint label +
      `"interrompida":true`. Canonical label, never a variant; measurement, never an estimate
      (aggregation depends on it).
2. Executive summary (partial mode): Sub-rotina F with `modo: parcial` and the `motivo`.
   Failed to generate → do not stop for it; note it in one line and continue (the technical
   handoff is what guarantees the resume).
3. `Skill gsd-pause-work` — durable handoff (HANDOFF.json + `.continue-here.md`) + WIP
   commit. Write the `stop` event with the CANONICAL stage in progress (e.g.
   `"2.5 convergencia"`) and the reason in its own field (10th positional of run-log.sh) —
   never `pausa: <motivo>` in the stage label.
3.5. STATE.md last. After the WIP commit, run
   `reconcilia-docs.sh --pausa --projeto "$ROOT" --fase N` and then
   `confere-etapa.sh pausa --pos-pausa --projeto "$ROOT" --fase N`. pause-work never touches
   STATE.md and HANDOFF.json records hashes before the commit that carries it exists. The
   script writes `status: paused`, the WIP hash and the plan/task from the HANDOFF, and makes
   its own commit `docs(state): STATE.md reconciliado na pausa`. The fence fails (exit 1) if
   `state_head` is neither HEAD nor HEAD~1: do not patch by hand — re-read the JSON
   (`pendentes`) and re-run; exit 3 (`FORMATO-INESPERADO`) is a status in sentence form, fix
   the token and re-run.
4. Stop with the `🔔` handoff line: the reason, the exact action (literal command), the
   pending plans, the pids the sweep reported and refused to kill (if any) and where
   `NN-RESUMO-EXECUTIVO.md` is. Resumes with `/go-and-do N`.

> When NOT to use: basket 3 (could-not-verify — HUMAN verification missing; hand-back route of
> Etapa 6, next step `/gsd-verify-work`) and basket 4 (assumed — ships with transparency). A
> leftover HANDOFF.json would derail the resume. Rule: implementation bug → D; unverifiable or
> subjective item → Etapa 6.

</subroutine>

<subroutine name="E — resolver o gsd-tools (lib)">

Resolution lives in `scripts/lib/gsd-shim.sh`, `source`d by every script of the skill. In the
rare Bash blocks of YOURS that query the SDK directly (e.g. 3.4):

```bash
. "$HOME/.claude/skills/go-and-do/scripts/lib/gsd-shim.sh"
gsd_run query phase-plan-index N
```

The lib resolves `gsd-tools.cjs` (runtime → project `.claude/` → PATH → `~/.claude/`) and
fails with the install instruction (`npx -y @opengsd/gsd-core@latest --claude --local`) — an
entry gate: stop and show the command (`abre-rodada.sh` already covers the opening).

</subroutine>

<subroutine name="F — resumo executivo (subagente Sonnet 5)">

Writes `NN-RESUMO-EXECUTIVO.md`: the phase's story in prose, for the non-technical owner.
Called at two moments: `modo: final` (6.3) and `modo: parcial` (every Sub-rotina D stop). Full
instructions live in `prompts/resumo.md` (the subagent reads it from disk — do not read it
before dispatching).

1. Numbers with a mechanical source: BEFORE the dispatch, run
   `scripts/numeros-da-fase.sh <phase_dir> NN` and paste the whole block into the dispatch.
2. Dispatch an `Agent` with `model: sonnet` and `run_in_background: false`, handing: the path
   of `prompts/resumo.md`, `NN`, absolute `phase_dir`, `modo` and — in `final` — the
   `desfecho` + the lists extracted by 6.2 (`itens_assumidos`, `itens_nao_verificados`,
   `itens_intencao`, `itens_nao_rodados`, `riscos_aceitos`, incidents of the run) + the 🔔
   hint; in `parcial` — the `motivo`.
   > Subagent because narrating requires READING the verbose artifacts — forbidden in layer
   > 0. Sonnet because it is synthesis/writing.
3. Check on return: `numeros-da-fase.sh <phase_dir> NN --conferir <resumo>`. Exit 1 →
   re-dispatch once with the divergences (or amend pointwise) and re-check. Persisted →
   continue with 🔔 `resumo com número sem fonte` in the banner (never silence it).
4. Commit: `git add <resumo> && git commit -m "docs(fase NN): resumo executivo"` (no footer).
   Failed → do not stop; note it in one line.

Idempotence: `modo: final` with `go_and_do_resumo: final` already in the file → skip. A
previous `parcial` is overwritten by the `final`. `parcial` always regenerates.

Telemetry: the dispatch is fenced as a main command (checkpoint/end — etapa `resumo final`/
`resumo parcial`); it is one of the most expensive subagents of the run and without the `end`
its cost vanishes from the account.

</subroutine>

<subroutine name="G — telemetria da rodada (run-log)">

Faithful timeline of the phase: 1 JSONL line per event in `<phase_dir>/NN-RUN-LOG.jsonl`,
with layer/model/effort/cost per stage. The grid is born COMPLETE by mechanical writing — the
run-log is the primary source of cost.

Single-writer rule (T.2) — each event has exactly one writer; you do NOT write what already
has an owner:

| Event | Writer | When |
|---|---|---|
| `run` | `abre-rodada.sh` | run opening |
| `checkpoint` | `pre-despacho.sh` | opens the stage window, with the context snapshot |
| `end` | `confere-etapa.sh` | closes the window on pass, with `tokens_reais`/`custo_usd` from `mede-tokens.py` (transcript, never self-declaration) |
| `despacho`/`retorno` | hook `gad-lifecycle.sh` | start/end of every `Agent()`, with origin layer and model/effort of the def |
| `script` | each script of the skill | self-registration name+exit+summary in an active run |
| `stop` | `pre-despacho.sh` (ceiling) or you (pause/end of run) | outcome |
| `compact` | `run-log.sh` itself | mechanical detector (drop >100k) |

What is LEFT to you (direct call, `<phase_dir>` always ABSOLUTE):

```bash
bash $HOME/.claude/skills/go-and-do/scripts/run-log.sh <phase_dir> <NN> <skip|stop> "<etapa>" [tokens] [pct] "" [limit] "" "<motivo>"
```

- `skip` — every step that WOULD have run and does not, outside the mechanical fences (the
  fences write their own): etapa = `"<id> (<motivo>)"`.
- `stop` of pause/end of run — with the final measurement and the reason in the 10th
  argument. Before the end-of-run stop: `run-log.sh <dir> <NN> audit` (closes open windows;
  dead session → `close --sessao <id>`).

Canonical `etapa` vocabulary: starts with the stage ID (`0 abertura` · `1 intencao` ·
`1.5 contratos` · `2 planejamento` · `2.5 convergencia` · `3 construcao` · `4.1 code-review`
… `4.5 validate` · `5 uat` · `6 encerramento`) or `preparacao` · `probe` · `verificacao` ·
`resumo` · `lateral <descrição>`. Without a stable ID, cross-phase aggregation is impossible.

The script never fails the pipeline (exit 0 always; `flock`; monotonic `seq`; orphan window
auto-closed and MEASURED by `mede-tokens.py`). Saw the auto-closed-window notice? Do not write
a corrective `end` by hand: the number you have (your window's context) is not cost. If the
automatic measurement came `indisponivel`, measure:
`mede-tokens.py --sessao $CLAUDE_CODE_SESSION_ID --desde <ts do checkpoint> --ate <agora>`
and only then an `end` with `--tokens-reais`/`--custo`. A 2nd `end` of the same stage
declares `substitui:<seq>` (whoever sums counts only the last). Telemetry is an instrument,
not a gate.

</subroutine>

<subroutine name="H — protocolo de subagentes (camada 1)">

Layers: 0 (this conversation) decides, chains and talks to the user; 1 are subagents with a
disposable window that do the verbose work of a stage; 2 are the agents that 1 dispatches or
hosts (GSD's internal ones + this skill's `gad-*` children, defs in `~/.claude/agents/`). The
layer-0 window is the scarcest resource.

Dispatch. A stage whose block says to dispatch runs in a `general-purpose` subagent (inherited
model, unless the block pins one). Stages with a def of their own (`gad-intent`, `gad-contratos`,
`gad-plan` for 2 and 2.5, `gad-execute`, and `gad-gates` for 4.1/4.1b/4.4/4.5 and the close's
route A) are dispatched by that `subagent_type`, never as `general-purpose`, and
never with `model`/`effort` in the call. Always synchronous: explicit `run_in_background: false` —
a background dispatch breaks the flow (the notification does not resume the script). The
dispatch prompt is minimal; the instructions live in `prompts/<etapa>.md`, which the SUBAGENT
reads from disk. Do not read the prompt before dispatching — reference the path. The dispatch
carries:

- the instructions file path (`$HOME/.claude/skills/go-and-do/prompts/<etapa>.md`);
- `N`/`NN`, `phase_dir`, `project_root` and input paths — always absolute (the subagent's cwd
  is not the project root);
- relevant flags and `args` when the block varies the command;
- with `obs_text` (`--obs`): the literal text as the first line
  ("Nota do usuário para esta rodada: …") — the subagent decides whether it is relevant; ignoring it as not applicable is
  a valid answer;
- on a resume from a pause: the user's answer, verbatim.

A number you copy is a number you check. Before carrying into a dispatch (or into a question
to the user) a figure another artifact declares — «8 lines», «12 red», «25 ACs» — count the list
that figure summarises, in the same file. If they disagree, carry the **list**, not the number,
and log an `incidente` with both values. `numeros-da-fase.sh --conferir <file>` does this
mechanically and prints `CONTAGEM-x-ENUMERACAO` on a mismatch. F24.5: `NN-RELATORIOS-EVIDENCIA.md`
said «8 linhas» and enumerated 7; the sentence reached the UAT prompt intact.

Credentials (birth rule of every authenticated dispatch). A task that needs a logged-in
session or touches secrets carries: (1) the sanctioned path prepared by layer 0 BEFORE
(wrapper that injects credentials into the process, or helper that emits only the ephemeral
code — never the secret); and (2) the literal prohibition: "PROIBIDO ler, copiar ou imprimir
`.env*`/segredos por qualquer via — leitura indireta é evasão. Login impossível pela via
sancionada → balde 3 ou `blocked`, nunca contorne um controle." A constraint applied
reactively always arrives one dispatch late.

Background inside the subagent: subagents do NOT receive notifications of background work —
the `prompts/*.md` carry the protocol: background only for work >10min, with the result in an
agreed file and a wait on ONE blocking disk waiter with explicit `timeout: 600000` (applies
to EVERY layer, orchestrator included) — never waiting on a notification, never chopped
polling. Return outside the contract (prose instead of the block) → do not accept nor
re-dispatch: continue the same subagent with "decida pelo estado do disco e finalize pelo
return_contract".

Return contract. Every layer-1 subagent returns a compact block — never verbose content (the
return is routing data; the body lives on disk):

- `done` — verdict, paths, counts. Section `incidentes:` mandatory: every deviation between
  the announced and the executed, or literally `nenhum`. Absent → return outside the contract
  (reconcile); item ≠ `nenhum` → ONE `incidente` event in the run-log PER ITEM (`--kv origem=<etapa/agente> --kv detalhe="<o item>"`; never aggregate) — in Etapa 3, only the
  items the execution host has not already logged itself (see 3.3, *One `incidente` per item*) —
  + hand it to the
  Sub-rotina F dispatch (the resumo narrates them).
- `needs_decision` — the subagent saved progress to disk and returned the digested question
  (options + tradeoffs + `recomendacao` + `reversivel`). Route via Sub-rotina I; the answer
  continues the SAME subagent (do not re-dispatch: the continuation keeps the context for
  free). Honest label: "Decisão do usuário: X" only if they actually chose X; an answer that
  is a question is NOT a decision (answer and re-ask); delegation →
  "decisão da camada 0 (usuário delegou): X"; triage → "decisão da camada 0 (triagem): X". Provenance block
  (decision that IS the owner's) — always relay in this format, and instruct each layer to
  relay it verbatim downwards (a loose label becomes an agent's assertion and a strict
  executor rejects it):

  ```
  DECISAO-DO-DONO
  canal: AskUserQuestion | --obs | resposta direta no chat | retomada pós-pausa
  ts: <ISO da resposta>
  pergunta: <1 linha>
  resposta_verbatim: "<palavra por palavra>"
  ```

  The `ts` is MECHANICAL: `date -Iseconds` at the moment, pasted — never from memory (a round
  minute `:00` is a placeholder red flag). The rule applies to EVERY timestamp written into
  an artifact by any layer (frontmatters of VERIFICATION/UAT etc.) — `confere-etapa.sh` lints
  placeholders. A consent claim requires a pointer: "aprovado pelo dono" only holds with a
  pointer to an existing DECISAO-DO-DONO block (file + `ts`); without it, it is a report and
  the item is UNSIGNED — for whoever writes, reviews and verifies.
- `blocked` — precondition unavailable. Handle by the stage block's semantics; descending into
  a subagent does not loosen any fail-closed — the block goes up and layer 0 stops.

Spawn denied (S.H). No pre-flight probe: `/cc-watch` watches for the removal of nesting. A
layer-1 host whose `Agent` call is denied returns `blocked` with `motivo: spawn_negado — <literal
message>`. Never take the stage over on your own (the harness treats it as permission
laundering): it is a hard gate (Sub-rotina I, criterion 5) — ask «assumir a etapa inline nesta
rodada» / «pausar a rodada». Only with the owner's yes, conduct inline: read
`prompts/<etapa>.md` first, and record it in `NN-DECISOES.md` with the exact CC version plus
one `incidente` event (`detalhe=spawn_negado`).

Cross-session resume. Continuing a subagent only works in the SAME session. In a new session
the state is on disk: layer 0 identifies the pending stage and re-dispatches; fine-grained
resume belongs to the stage prompt (`intent.md` has its own arrival; those that only host a
GSD command rely on the command's idempotence — such a `needs_decision` does not survive the
session: the re-dispatch re-runs and the question re-emerges, accepted cost).

</subroutine>

<subroutine name="I — triagem de decisão (antes de todo AskUserQuestion)">

Owner's decision (20/07, always on): layer 0 decides alone what they would merely stamp —
with record and disclosure — and only what is theirs to decide reaches them.

Before ANY `AskUserQuestion` — from `needs_decision`, inherited stop or own stop — classify:

Hard gate — stop and wait for the user when ANY holds:
1. External information — the answer is a fact only they have (credential, access, state of
   the world). They provide input, not a stamp.
2. Scope/intent — requirement, acceptance criterion, oracle, SPEC/CONTEXT/ROADMAP (includes
   the intent review pause). Auto-approving here is the inverted stamp.
3. Irreversible off the rail — rotating/exposing a credential, deleting data, spending money,
   production. (The sanctioned rail — green phase up to the PR merge after a clean UAT, 6.D,
   including the automatic merge of the route-B clean room (`ship.py --merge`; owner's
   decision 27/08: they do not review PRs, they trust the stages) — is the default and does not
   ask. What the route owes is the NOTICE: resumo/banner says "mergeado".) An option that edits
   `src/` **inside the triage of 4.4 or 4.5** (secure/validate reaching past their own gate into
   production code) is never routine — hard gate, recommendation up front, ask (FJ-06GAT); in
   the 23h–07h silence window it takes the graceful pause below, same as any other hard gate.
4. No recommendation — without real conviction, the confession of uncertainty goes up in any
   category.
5. Existing fail-closed — open threat, persistent basket 2, basket 3, gaps, `blocked`, context
   gate, bloqueio_sem_revisor: triage loosens none of them.
6. `blocking-human` inherited from GSD (1.11.0, #3210) — GSD's own `--auto` already refuses to
   approve it; triage respects the refusal (an orchestrator stamping what the executor refused
   to stamp voids the guard one layer up). Unmet precondition is criterion 1; package
   verification is criterion 3.

Auto-decision — decide, record and continue when NO criterion holds AND there is a
recommendation with conviction AND the error is cheap to undo. Tie-break: the more rigorous
option. Mechanics:
1. Decide by the option you would recommend (the subagent's `recomendacao` is input, not
   verdict; `reversivel: nao` goes to the hard gate).
2. Record in `<phase_dir>/NN-DECISOES.md`: time (`date "+%F %H:%M"`), stage, question in 1
   line, options, chosen, why and how to undo. Line to the user:
   `🤖 decidi sozinho: <escolha> — registrado no NN-DECISOES.md` (a silent auto-decision is a
   bug).
3. Continue. In a `needs_decision`, continue the SAME subagent with the honest label of
   Sub-rotina H.

Timing decisions are decisions too — postponing a question, holding a notice until the
resumo: same mechanics, entry in `NN-DECISOES.md` (chat narration is lost; the record is what
the resumo and the audit re-read).

An instrument that is failing the round because of a defect of its own, and a reading that
contradicts the disk, are both hard gates routed from here — the rule and the evidence file
live in the Etapa 3 block (*Instrument under judgement* / *Instrument versus disk*); never
patch the instrument yourself while the round it judges is open.

Ceremony before ANY `AskUserQuestion` inside the round (v2.5.4, 45p): run
`pre-gate.sh "<phase_dir>" "<NN>" "<question in 1 line>"`. It runs `janela-silencio.sh`
(single source of the 23h–07h rule; the `janela_silencio` field of the checkpoint JSON is
informative only), commits the phase artifacts (RUN-LOG, DECISOES, NOTIFICACOES, gate evidence)
by explicit pathspec, and records `.planning/.gad/last-pre-gate.json`. The hook
`gad-gate-guard.sh` DENIES the question when the marker is missing, older than 15 min, or from
another HEAD, and when the window is closed — a denial is the route, never something to retry.
1. exit 0 (`acao: pergunta`) → ask normally.
2. exit 1 (`acao: pausa`) → graceful pause (Sub-rotina D, reason `gate duro em janela de
   silêncio`), with the pending question (options + recommendation) in the handoff and in the
   partial resumo; the resume re-presents it. (F24.5: the 23:50 question was opened inside the
   window with nothing committed and no handoff; the mirrors stayed 6 h stale.)

Does not apply to auto-decision (which never stops) nor changes the fail-closed. A
`blocking-human` of precondition in the window is not a question — it is a pending action:
follows the 3.4 → Sub-rotina D route with the precondition verbatim in the handoff
(`NN-ACAO-HUMANA.md` if there is a step by step to give).

Transparency closes the loop: the executive summary narrates every auto-decision by reading
`NN-DECISOES.md` — synchronous supervision becomes asynchronous review with an undo route.

</subroutine>

</subroutines>

---

<stop_points>

Inherited stops — when a GSD command calls you (not a bug). This skill's OWN stops are in the
stages. The invoked GSD commands have their own stops — decisions the command does not take
alone. When one fires, route it via Sub-rotina I: what is the user's reaches them (never
bypass the stop with flags); a stamp is auto-decided and recorded in `NN-DECISOES.md`. A
command hosted in a subagent (Sub-rotina H) → the same stop arrives as a digested
`needs_decision`; the answer continues the same subagent.

- Etapa 1.5 (`gsd-ui-phase` / `gsd-ai-integration-phase`): stops are in
  `workflow-ui.md` / `workflow-ai.md` (read with the flag).
- `gsd-plan-phase`: decision-coverage gate (`workflow.context_coverage_gate: false` disables
  it) · requirements-coverage gap · source-audit gaps / phase-split recommended (an
  ill-sized phase — better a split than a bloated plan) · revision-loop stall (3 iterations
  without converging).
- `gsd-execute-phase` (the `--auto` of 3.3 does not silence these): regression test failure ·
  schema drift · post-merge conflict · `human-action` checkpoint (auth/2FA/migrations only the
  owner runs — never automated; if they defer, 3.4 detects the incomplete execution and closes
  via Sub-rotina D instead of leaving it stuck at the prompt) · `Gate: blocking-human`
  (`<precondition>` of a task unmet — env var, `user_setup` step, artifact of a previous
  phase — or package verification before install). Hard gate by definition: never stampable;
  precondition → same route as the human action (`done · incompleto` → 3.4 → Sub-rotina D);
  package → irreversible `needs_decision` → hard gate of Sub-rotina I.

Golden rule: a design/scope decision stop or a reality gate (regression/schema/auth) is
legitimate — pause, note it in the banner, and the user decides. Sub-rotina I formalizes the
ruler.

</stop_points>
