<!-- workflow-etapa-1.md — Etapa 1 (Intenção — spec + discuss + consultoria especializada) of the go-and-do workflow: the
     <stage id="1"> block, moved verbatim out of workflow.md (mapa-gad task 9). Layer 0 reads
     it on entering Etapa 1, in the same response as the stage's first command (workflow.md <pipeline_index>). -->

<stage id="1" name="Intenção — spec + discuss + consultoria especializada">

> Replaces the human stamp with a machine skeptic: SPEC and CONTEXT come out in `--auto` (each
> choice logged) and the intent goes through cross-AI specialist consultancy — two external
> consultants try to knock down the decisions reading the real code, and a verifier checks
> each finding before it is accepted. The user is called only when a finding touches what is
> theirs to decide.

**1.1 — Resume.** Obey `etapa_1` from abre-rodada: `pular` → Etapa 1.5 · `continuar_pergunta`
→ re-present the pending question stored in the artifact and dispatch with the answer ·
`despachar` → 1.2. Fine-grained per-file resume belongs to the subagent (`setup-intencao.sh`).

**1.2 — Dispatch.** `pre-despacho.sh 1` → dispatch the agent `gad-intent` (own def: Opus 5.5
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
