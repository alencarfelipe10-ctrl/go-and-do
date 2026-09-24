<!-- workflow-etapa-6.md — Etapa 6 (Encerramento + ship) of the go-and-do workflow: the
     <stage id="6"> block, moved verbatim out of workflow.md (mapa-gad task 9). Layer 0 reads
     it on entering Etapa 6, in the same response as the stage's first command (workflow.md <pipeline_index>). -->

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
dispatching the close**, same rigor as the fresh check (`workflow-etapa-3.md` §3.4); do not let the ship's own preflight
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
