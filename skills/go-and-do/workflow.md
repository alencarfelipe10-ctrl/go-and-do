<!-- ============================================================ -->
<!-- workflow.md — the executable core of the go-and-do skill.   -->
<!-- Embedded into SKILL.md via @ (loaded on activation).        -->
<!-- Imperative instructions for the orchestrator; not docs.     -->
<!-- Split layout (mapa-gad task 9): only the resident part lives -->
<!-- here — role, operating rules, pipeline index, Etapa 0,      -->
<!-- always-on sub-routines and stop points. Each later stage    -->
<!-- lives in workflow-etapa-ID.md, read by layer 0 on entering  -->
<!-- it (see the pipeline index). Per-stage detail for the       -->
<!-- subagents lives in prompts/*.md; conditional material lives -->
<!-- in workflow-ui.md / workflow-ai.md / workflow-dev-server.md -->
<!-- (read on demand). Size ceiling: tests/test-tamanho-workflow -->
<!-- (above ~25k tokens the @ attachment is dropped in silence). -->
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
- Phase evidence (v2.10.1): a phase opened by abre-rodada with no older evidence keeps ALL run
  evidence under `<phase_dir>/.gad/` (marker `.gad/FORMATO`, committed at opening;
  `formato_fase` in the abre-rodada and pre-despacho JSON). The stage files cite those new
  names (`.gad/fences/3.ok`, `.gad/intent/c<C>/…`). A phase without the marker keeps the old
  dotfiles: resolve each name with `scripts/caminho-fase.sh <phase_dir> <rel>`. Never mix.
- Gates decide on RAW output, never on wrapper-filtered output. Under a hook that rewrites
  Bash and compacts output (e.g. RTK), every command whose result feeds a gate decision
  (`wc -l`, empty-output test, `grep` routed by exit code) runs as `rtk proxy <cmd>`. Applies
  to every layer and is passed down in briefings that carry gate commands. Exploratory reads
  stay filtered. When a script's stdout comes capped, read its mirror: the path is the JSON's
  first key, `espelho` (copies live in the git cache `.git/gad-cache/`, never in `git status`;
  the 4 state mirrors stay in `.planning/.gad/`) (PC-5).
- Session usage (5h / weekly) is not readable by a skill, so there is no gate for it: if the
  limit hits, re-run `/go-and-do N` after the reset and the run continues. Manual pause at any
  time: `/gsd-pause-work`.
</operating_rules>

---

<pipeline_index>

Legend used in the stages: 🎌 flag-only · ⏭️ resume (skips if done) · ⏸️ may stop · 🔒 context
gate (`pre-despacho.sh`) before it.

| Etapa | what | how | file (in `$HOME/.claude/skills/go-and-do/`) | first layer-0 command on entry |
|---|---|---|---|---|
| 0 | preparation | `abre-rodada.sh` + `confere-etapa.sh 0` + banner | this file | `abre-rodada.sh … && confere-etapa.sh 0` + `ToolSearch`, in one response (0.2) |
| 1 | intent: spec + discuss + specialist consultancy | 🔒 ⏭️ agent `gad-intent` + `prompts/intent.md` | `workflow-etapa-1.md` | `pre-despacho.sh 1` (1.1 comes from the snapshot: `etapa_1: pular` → skip the stage and its file) |
| 1.5 | design contracts | 🎌 `setup-contratos.sh` → agent `gad-contratos` + `prompts/contratos.md` | `workflow-etapa-1.5.md` | `setup-contratos.sh <phase_dir> <NN> [--ui] [--ai]` (with neither flag: run it alone and read the file only if it does not skip) |
| 2 | planning | 🔒 ⏭️ agent `gad-plan` + `prompts/plan.md`; 2.4b resolves `autonomous: false` | `workflow-etapa-2.md` | `pre-despacho.sh 2` (2.1 comes from the snapshot: `etapa_2: pular` → Etapa 2.5) |
| 2.5 | plan convergence | 🔒 ⏭️ agent `gad-plan` + `prompts/convergence.md` (PC-6 fail-closed) | `workflow-etapa-2.5.md` | `pre-despacho.sh 2.5` (`has_verification` → skip the stage and its file) |
| 3 | build | 🔒 3.2 parallelism authority → `gad-execute` + `prompts/execute.md` → 3.4 crossroads → 3.5 gaps 1× | `workflow-etapa-3.md` | `pre-despacho.sh 3` (`has_verification` → skip the stage and its file) |
| 4 | quality gates | 🔒 ⏭️ per gate: code-review · 🎌 ui-review · 🎌 eval-review · secure (only blocking gate) · validate | `workflow-etapa-4.md` | `pre-despacho.sh 4-code-review` |
| 5 | automated interactive UAT | resume by `NN-UAT.md` state; generate → run (Sonnet + `uat-playbook.md`) → 1 fix cycle | `workflow-etapa-5.md` | the 5.1 state read of `<phase_dir>/NN-UAT.md` (exists? frontmatter `pre_uat*`, `result:` lines) — not a `pre-despacho.sh 5` of its own: 5.3/5.4 open it |
| 6 | close + ship | `pre-despacho.sh 6` routes pausa/handback/ship; Sub-rotina F; ship via `prompts/close.md`; `confere-etapa.sh 6` | `workflow-etapa-6.md` | `pre-despacho.sh 6` |

**Reading the stage files.** Only Etapa 0 lives in this file; every other stage's rules live
in its own file (column «file»), and you do not know them until you `Read` it. On entering
Etapa X, `Read` `$HOME/.claude/skills/go-and-do/workflow-etapa-X.md` **in the same response** as
the stage's first command (last column), in parallel — never a request of its own. In Etapa 1
that is the `pre-despacho.sh 1` of 1.2. A resumed run that enters at Etapa N reads only
`workflow-etapa-N.md`. When a step points to a rule in another stage file (e.g.
`workflow-etapa-3.md` §3.3), `Read` that file at that step, in the same response as the
step's first command — never act on a rule you have not read in this session. A file already
read in this session (and not compacted away since) is not read again.

</pipeline_index>

---

<stages>

<stage id="0" name="Preparação">

**0.1 — Arguments.** Phase number (first number) + flags `--ui`, `--ai`, `--no-ship`,
`--vault <profile>`, `--obs "<texto>"` (unquoted: everything up to the next flag). No number →
stop and ask. Keep `--no-ship` (terminal route of Etapa 6), `vault_profile` (goes down to the
UAT — the 0.2 JSON and the run pointer carry it as `args.vault_profile`) and `obs_text` (note
to every dispatch of the run — Sub-rotina H).

**0.2 — Atomic opening + self-check, one response.** Your first response of the run carries two
calls in parallel:
- one Bash: `S=$HOME/.claude/skills/go-and-do/scripts; $S/abre-rodada.sh N [flags] && $S/confere-etapa.sh 0`
  — opening and its self-check in one command (never two requests);
- `ToolSearch` with `select:TaskCreate,TaskUpdate,TaskList` (the task tools of Sub-rotina C).

Obey the abre-rodada JSON (first line; mirror at its `espelho` key): entry
gates, phase snapshot (`phase_dir`/`padded_phase`/`has_plans`/`has_verification`), context gate,
resume decisions (`etapa_1`/`etapa_2`), `vault_alerta`, TaskList snapshot, `run` event + run
pointer — all in one script. abre-rodada exit ≠ 0 (then the confere does not run) → stop with
the script's reason (exit 2 = gate/argument · 3 = context at the ceiling · 4 = phase not found ·
5 = phase in the ROADMAP but its directory unresolvable). Missing entry prerequisites are the
first hard stop (Etapa 0).

**0.3 — Obey the snapshot.**
- The `confere-etapa.sh 0` verdict already came in the 0.2 output (second JSON line; mirror at
  its `espelho` key): only read it — never re-run it. Exit 1 → the opening
  did not land on disk (pointer or `run` event missing): stop with its list.
- Mirror the TaskList (Sub-rotina C): every `TaskCreate` in ONE response.
- `vault_alerta` → ask BEFORE spending the phase (phase that looks like an authenticated UI
  without `--vault`).
- `pos_ship_alerta` → ask BEFORE spending the phase, listing `pendentes` (a previous phase left
  a post-ship observation marked `bloqueia_proxima: sim` that nobody observed yet). The owner
  decides; record the answer in `NN-DECISOES.md`. The phase named in the item's
  `verificavel_em` never triggers it.
- `uat_superficie` (absolute path or null) → keep it for 5.4: it is the project's UAT contract.
- `--ui`/UI-SPEC → read `workflow-ui.md`; `--ai`/AI-SPEC → `workflow-ai.md`, in the same response
  as the `TaskCreate` calls (the only reads of Etapa 0; each later stage reads its own file —
  pipeline index). A phase with a server → `workflow-dev-server.md` at the first step that uses it
  (Sub-rotina B).

**0.4 — Banner.** Print it now, before anything of the next stage — the user reads it to know the
run started and with which flags. It may open the response that enters the next stage or be a
response of its own; it is never omitted. Double ASCII frame in a `text` block:

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

<!-- Etapas 1–6 live in workflow-etapa-{1,1.5,2,2.5,3,4,5,6}.md — pipeline index. -->

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
  `pergunta_ao_dono` and ⏸️ stop. `bloqueio_plano_nao_resolvido` (2.5 only): back to 2.4b
  (`workflow-etapa-2.md` §2.4b).
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
- Lean creation, all tasks in ONE response: `subject` = the snapshot's `titulo`;
  `description` = only `Etapa <N>` (the field is mandatory; nothing else in it); no
  `activeForm`. The tools come from the `ToolSearch` of 0.2 — never a request of its own.
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
| `end` | `confere-etapa.sh` | closes the window on pass, with `tokens_reais`/`custo_usd` from `mede-tokens.py` (transcript, never self-declaration). Etapa 0 only: its window closes empty in 0.2, so the session's first `pre-despacho.sh` re-measures `run` → its checkpoint and writes a 2nd `end "0 abertura"` (`substitui`) |
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
mechanically and prints `CONTAGEM-x-ENUMERACAO` on a mismatch.

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
  items the execution host has not already logged itself (see `workflow-etapa-3.md` §3.3, *One `incidente` per item*) —
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
live in `workflow-etapa-3.md` (*Instrument under judgement* / *Instrument versus disk*): read it
when either case arises, in any stage; never patch the instrument yourself while the round it
judges is open.

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
   partial resumo; the resume re-presents it.

Does not apply to auto-decision (which never stops) nor changes the fail-closed. A
`blocking-human` of precondition in the window is not a question — it is a pending action:
follows the 3.4 → Sub-rotina D route (`workflow-etapa-3.md` §3.4) with the precondition verbatim in the handoff
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
