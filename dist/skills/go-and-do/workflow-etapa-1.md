<!-- workflow-etapa-1.md — Etapa 1 (Intenção — consultoria especializada) of the go-and-do workflow: the
     <stage id="1"> block, moved verbatim out of workflow.md (mapa-gad task 9). Layer 0 reads
     it on entering Etapa 1, in the same response as the stage's first command (workflow.md <pipeline_index>). -->

<stage id="1" name="Intenção — consultoria especializada">

> Replaces the human stamp with a machine skeptic: the phase's single intent document
> (`NN-CONTEXT.md`, written and approved by the owner in `/gad-discuss-phase NN`) goes
> through cross-AI specialist consultancy — two external consultants try to knock down the
> decisions reading the real code, and a verifier checks each finding before it is accepted.
> The stage starts straight at cycle 1: nobody authors the intent here and there is no cycle 0.
> The user is called only when a finding touches what is theirs to decide.

Flow of the stage: abre-rodada stops a phase without the document → the setup returns
`revisao` → consultancy cycles 1..4 (Codex + agy + the independent `releitura`, which in cycle 1
also checks the document for internal inconsistency — AC × AC, declared number × list, repeated
criterion — done by whoever did not write the text) → amendments touch only `NN-CONTEXT.md` →
text × machine-block coherence (`confere-reconciliacao.sh`) at the end of each cycle →
`NN-INTENT-REVIEW.md`.

**1.1 — Resume.** Format barrier first: with `etapa_1: despachar`, abre-rodada stops with exit 6
before any dispatch when the phase has no `NN-CONTEXT.md` in the new format, with the plain-language message
telling the owner to run `/gad-discuss-phase NN` — relay it and stop; `pular` and
`continuar_pergunta` are not checked. Then obey `etapa_1`: `pular` → Etapa 1.5 ·
`continuar_pergunta` → re-present the pending question stored in the artifact and dispatch with
the answer · `despachar` → 1.2. Fine-grained per-file resume belongs to the subagent
(`setup-intencao.sh`, which returns `entrada: revisao` for new work — an interrupted cycle
resumes in its cycle).

**1.2 — Dispatch.** `pre-despacho.sh 1` → dispatch the agent `gad-intent` (own def: Opus 5.5
medium — the coordinator routes; heavy judgment lives in the children and the external
consultants) with `prompts/intent.md`, carrying absolute `N`, `NN`, `phase_dir`,
`project_root` and, on a continuation, the verbatim answer. Inside: specialist consultancy on
`NN-CONTEXT.md` (Codex + agy — agy = Gemini 3.7 Flash — ↔ `gad-verificador`, which also
re-reads each cycle's committed amendment in `releitura` mode, `prompts/intent-releitura.md`;
loop by `decide-ciclo.sh`, hard ceiling 4; fail-closed at the "≥1 consultant" floor). The
coordinator's only layer-2 children are `gad-explorador` and `gad-verificador`. The lanes run in
the background (`roda-lanes.sh`; lane authority is `.gad/intent/c<C>/status-<lane>.json`,
`usable`/`independent`); the 4-turns-per-cycle budget (5 when the `releitura` corrected) is an
audit ruler measured by `/audit-gad` in the transcript, not counted in session.

Never pass `model` or `effort` in the `Agent` call of a `gad-*` (E7): the def pins both and
`gad-lifecycle.sh` denies the call with `deny` + an `incidente` event. The denial carries the
reason in `permissionDecisionReason` — read it and fix the route, do not retry.

**1.2a — Hand the subagent its transcript directory.** The dispatch of `gad-intent` also carries
`subagents_dir: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<slug do projeto>/<CLAUDE_CODE_SESSION_ID>/subagents` — it is
from there that the coordinator reads its own turns with `turnos-por-ciclo.py` at the close of the
stage. Without the parameter, the coordinator returns `turnos: nao_medido — transcript fora do
alcance`, which is a legitimate route (owner's decision of 11/09: layer 0 passes the path,
`nao_medido` as the fallback).

**1.3 — Routing the return.**
- `done` → route gate: `confere-rotas.sh <phase_dir>/.gad/intent` (exit 1 → back to the SAME
  subagent, step 7b of intent.md, fail-closed) → `confere-etapa.sh 1` (includes
  `confere-reconciliacao.sh --final`, informative; mechanical fence — intent document/review
  closed/chain zeroed/`.gad/intent/` cleanup — and the measured `end`; exit 1 → same subagent).
  Keep from the return: `transparencia` (input of 6.2), `sinos` (for the banner) and announce
  `pausas_de_negocio` in one line. Bells with a skipped review (`intent_review: skipped`) →
  `skip` event + a line to the user + mandatory item in `itens_nao_rodados`. Continue.
- `needs_decision` — finding that touches requirement/criterion/oracle, or a deadlock (hard
  gate by definition, criterion 2 of Sub-rotina I; silence window → graceful pause) →
  `AskUserQuestion` and continue the SAME subagent with the verbatim answers; route the new
  return by this list. The question follows the owner's rule (ADR 0001, question 2 — the owner
  has no technical background and follows the recommendation on every technical question):
  a pergunta ao dono vai em linguagem leiga, pela consequência que ele sente
  (o que é entregue, o que fica público, o que é irreversível, custo, prazo, risco de perder algo),
  com a recomendação primeiro e o efeito de cada opção,
  sem nome de arquivo, função ou ferramenta; o resto o modelo decide.
  Rewrite a technical `alegacao` into that form before asking — never forward it verbatim.
- `blocked` — BOTH consultants installed but failing with no complete cycle (fail-closed,
  decision of 02/07: without a second opinion the intent does not proceed; ONE failing
  continues degraded with a bell; NONE installed becomes `skipped` in the pre-check) →
  Sub-rotina D. `intent_review: blocked` is already on disk (the next invocation retries).
  Handoff: "🔔 revisão de intenção bloqueada — autentique um dos revisores e re-rode
  `/go-and-do N`."

**1.3a — The fiscal now leaves a receipt.** `confere-etapa.sh <etapa>` writes, on a pass,
`<phase_dir>/.gad/fences/<etapa>.ok` with the HEAD it checked, and deletes it on a fail (the pair of the
failed-gate lock, which lives in the ignored round state: `.planning/.gad/gates/<phase dir name>/<etapa>.json`). `gad-intent` only returns `done` after running the fiscal itself
and seeing a valid fence. A return that says `done` **without** a valid fence on disk is an
incident of the subagent, not of the fiscal: log it and send it back to the same subagent, as the
gate already prescribes. `--dry-run` neither writes nor deletes a fence.

**1.3b — What the `transparencia:` of the return may carry.** The field may bring a line
`turnos: <literal output of turnos-por-ciclo.py>` or `turnos: nao_medido — <motivo>`; no new field
is mandatory and no parser changes.

</stage>
