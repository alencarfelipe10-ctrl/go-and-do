<!-- workflow-etapa-2.5.md — Etapa 2.5 (Convergência do plano) of the go-and-do workflow: the
     <stage id="2.5"> block, moved verbatim out of workflow.md (mapa-gad task 9). Layer 0 reads
     it on entering Etapa 2.5, in the same response as the stage's first command (workflow.md <pipeline_index>). -->

<stage id="2.5" name="Convergência do plano">

- `has_verification` (phase already built and verified) → skip 2.5, go to Etapa 3.
- `pre-despacho.sh 2.5` and obey `despacho`: `pular` (marker present) → Etapa 3 ·
  `skip_config` → declared degradation (`itens_nao_rodados`) and continue ·
  `bloqueio_sem_revisor` (exit 4 — PC-6: NO external reviewer installed, the phase does NOT
  continue) → ⏸️ relay `pergunta_ao_dono` and stop ·
  `bloqueio_plano_nao_resolvido` (exit 4 — S-11, tarefa 48l: some `NN-PLAN.md` still has
  `autonomous: false`, so 2.4b did not finish) → go back to 2.4b (`workflow-etapa-2.md` §2.4b) for the plans listed in
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
