<!-- workflow-etapa-5.md — Etapa 5 (UAT interativo automatizado) of the go-and-do workflow: the
     <stage id="5"> block, moved verbatim out of workflow.md (mapa-gad task 9). Layer 0 reads
     it on entering Etapa 5, in the same response as the stage's first command (workflow.md <pipeline_index>). -->

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
  this is where the promised "becomes UAT" materializes;
- (e) FJ-F27INS-01UAT — the dispatch prompt itself says, in these terms: every scenario
  leaves this generator as `[pending]` — you run no proof and you do not decide a basket
  (5.4/5.5/5.6 do that); any factual claim you record about the state of the repo (e.g.
  "nothing changed since commit X", "this gate already ran clean") must quote the command
  and its real output, never a recollection. A generator caught re-running the PII gate 3×
  and asserting `git log` came back empty when the same command listed 11 commits is the
  failure this line exists to stop (measured 25/09/2026: ~6 min of the conductor's window
  redoing the gate, plus a false claim that almost reached the pass record).

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
3. Re-execute (`workflow-etapa-3.md` §3.3 rule, args `... --gaps-only` — strict scope).
4. Re-review on the fix's files: 4.1 dispatch (`workflow-etapa-4.md` §4.1) with `iteracao: 2+` — without the resume check
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
   `.gad/pos-ship/vereditos.json`. Whoever classifies never judges.
4. `scripts/pos-ship.py move <phase_dir> <NN> <project_root>` — moves only what passes its six
   conditions; a refused candidate stays in `NN-UAT.md` as basket 3 and keeps blocking the
   ship. Then `commita-artefatos.sh <phase_dir> <NN> uat` — it commits `NN-POS-SHIP.md` and the
   `uat-evidencia/` files a scenario cites — and only then `confere-etapa.sh 5` again (it may
   now promote `status: complete`; an `NN-POS-SHIP.md` outside git fails it: `uat_fora_do_git`).
- The re-run produced a new `issue` → 5.5 (the fix cycle is still unspent; its re-UAT uses the
  same project surface). Basket 3 empty → Etapa 6 by the ship route. Still there → **commit the
  UAT result before leaving this stage** (`commita-artefatos.sh <phase_dir> <NN> uat`, the same
  single writer as 6.3b) and go to Etapa 6 hand-back. Never a 2nd 5.6.

</stage>
