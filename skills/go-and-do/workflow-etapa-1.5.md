<!-- workflow-etapa-1.5.md — Etapa 1.5 (Contratos de design) of the go-and-do workflow: the
     <stage id="1.5"> block, moved verbatim out of workflow.md (mapa-gad task 9). Layer 0 reads
     it on entering Etapa 1.5, in the same response as the stage's first command (workflow.md <pipeline_index>). -->

<stage id="1.5" name="Contratos de design">

> Before planning because `gsd-plan-phase` consumes UI-SPEC/AI-SPEC as locked design and the
> 4.2/4.3 gates audit against them.

**1.5.1 — Mechanical setup.** `setup-contratos.sh <phase_dir> <NN> [--ui] [--ai]`: both
`pular`/`sem-flag` → skip the whole stage. `config_corrigida` non-empty → transparency (the
owner's flag beat a forgotten config — declared flip).

**1.5.2 — Dispatch.** `pre-despacho.sh 1.5` → dispatch the agent `gad-contratos` (Opus 5.5
medium, with Agent and Skill) with `prompts/contratos.md` + flags + the setup JSON. It hosts
`gsd-ui-phase` and `gsd-ai-integration-phase` inline (order UI → IA).

**1.5.3 — Routing.** `done` → `confere-etapa.sh 1.5` (asserts per flag; exit 1 sends back);
bells → transparency. `needs_decision` (inherited stops — detail in
`workflow-ui.md`/`workflow-ai.md`) → Sub-rotina I; the answer continues the SAME subagent.
`blocked` → Sub-rotina D.

</stage>
