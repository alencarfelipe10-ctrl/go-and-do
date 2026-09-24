<!-- workflow-etapa-2.md — Etapa 2 (Planejamento) of the go-and-do workflow: the
     <stage id="2"> block, moved verbatim out of workflow.md (mapa-gad task 9). Layer 0 reads
     it on entering Etapa 2, in the same response as the stage's first command (workflow.md <pipeline_index>). -->

<stage id="2" name="Planejamento">

**2.1 — Resume.** Obey `etapa_2` from abre-rodada: `pular` → Etapa 2.5; `despachar` → 2.2.

**2.2 — Exit fence.** `pre-despacho.sh 2`.

**2.3 — Plan (via subagent).** Dispatch the agent `gad-plan` (Opus 5.5 medium — the entry
judgments have high leverage) with `prompts/plan.md` (`N`, `NN`, `phase_dir`, `project_root`,
base args `N --tdd`): it judges research (2.D) · mapper (2.E) · granularity (2.G), invokes
`gsd-plan-phase` and persists the checker trail (`.gad/plan-checker/iter-N.yaml`, 2.B). Routing:
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
Empty `mapper_pulado` → nothing to do. Never decide this by reading the judge's prose.

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
