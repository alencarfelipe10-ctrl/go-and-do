<!-- workflow-etapa-3.md — Etapa 3 (Construção) of the go-and-do workflow: the
     <stage id="3"> block, moved verbatim out of workflow.md (mapa-gad task 9). Layer 0 reads
     it on entering Etapa 3, in the same response as the stage's first command (workflow.md <pipeline_index>). -->

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
  `effort:` in the call** — the def pins Opus 5.5 / medium, and `gad-lifecycle.sh` denies a
  `gad-*` dispatch whose call disagrees with the def (E7(b)). If the dispatch fails because the def is not installed, that is an
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
`<phase_dir>/.gad/fences/3.ok` exists and its `head` equals the current HEAD. The host writes it by
running `confere-etapa.sh 3 --fase <N> --projeto <root> --sem-telemetria` itself; that flag
evaluates and writes the fence (and clears the lock) **without** measuring tokens and **without**
logging an event, so it does not leave a second `end` for the stage. Receipt absent, or `head`
stale because a commit landed after it: return the list of what is missing to the same subagent,
whatever it claimed.

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
(`colisao_real_onda`).

**One `incidente` per item, at the time of the fact.** The execution host now writes each
incident to the run-log when it happens. When its return arrives, log only the items that are
**not** already in the run-log (match by `detalhe`), so the count is not inflated — and log them
**before** your `confere-etapa.sh 3`, which is what writes the stage's `end`. An `incidente`
stamped after that `end` fails the stage (`incidente_tardio`, FM-F27INS-06INT); on F27 INS the 5
relayed items landed 23 s after the `end` (FM-F27INS-07EXE).

**3.4 — Crossroads.** Completeness first: `gsd_run query phase-plan-index N` (lib of
Sub-rotina E) — a plan without `SUMMARY.md` → execution incomplete, blocked → Sub-rotina D with
the exact action (never treat it as `human_needed`). Otherwise, the VERIFICATION.md status:
- absent, or present but stale (the phase took commits after it): **do not re-invoke
  `gsd-execute-phase`** — with `VERIFY_STATUS=stale` and `PHASE_MARKED=false` its route is
  `update_roadmap`, which marks the phase complete **without** verifying. Dispatch `Agent(subagent_type="gsd-verifier")`
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
  Still absent after the re-verification → Sub-rotina D.
- `passed` → Etapa 4 · `human_needed` → note it (becomes PENDING of the UAT) and continue ·
  `gaps_found` → 3.5.

**3.5 — Gap closure (1× only).** Replan (`prompts/plan.md`, args `N --gaps`) → anchor the
re-convergence: add to the `NN-CONVERGENCE.md` frontmatter the line
`gap_replan: "<data> — N planos gap_closure; commits <shas>"` and commit → re-execute (3.3
rule) → re-verify. `passed`/`human_needed` → Etapa 4; still `gaps_found` → Sub-rotina D
(`gaps persistentes`). One attempt only.

**Instrument under judgement.** When a `confere-*.sh`, a hook or a fork script is failing the
round **because of a defect of its own**, it is evidence, never a target. Write
`<phase_dir>/.gad/gates/<etapa>-evidencia.txt` with the command, the literal output and the line
you believe is wrong; commit it; route the decision to the user through the hard gate
(Sub-rotina I). Never `sed`, never `Edit`, never a "temporary" patch to the instrument while the
round it judges is open — not even when your diagnosis is right.

**Instrument versus disk.** When an instrument's reading contradicts the disk by an order of
magnitude (78 minutes read as «5 s»; nine agents read as one), the hypothesis is that the
**instrument** is wrong, not the fact. Before any report to the user, run the primary
measurement and carry **that**:

```bash
bash "$HOME/.claude/skills/go-and-do/scripts/numeros-da-fase.sh" <phase_dir> <NN> --executores
```

The report to the user carries the primary number and the disagreement («the meter says X, the
clocks say Y, and here is why the meter is wrong»), never the open doubt.

</stage>
