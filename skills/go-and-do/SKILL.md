---
name: go-and-do
description: "Runs a GSD phase end-to-end: intent (spec + discuss in auto mode + adversarial cross-AI intent review by Codex + Antigravity when installed — skipped with loud disclosure in the executive summary when no external reviewer is available) → design contracts (UI/AI) → plan → plan-review → execute → code-review → quality audits (UI/AI/security/Nyquist) → interactive automated UAT (a Sonnet subagent drives the browser: clicks, fills forms, walks flows, proves objectively) → narrative executive summary → close (extract-learnings → ship/PR). Every phase runs the full pipeline at maximum rigor; anything that does not run (a config gate off, a tool unavailable) is disclosed, never silent. Layered orchestration: every verbose stage (intent, plan, plan convergence, execute, code review, eval review, secure, validate, UAT, summary, close/ship) runs in a disposable subagent window and returns a compact status, keeping the orchestrator window lean across a long phase. Decision triage (always on): questions the user would merely rubber-stamp are auto-decided by layer 0 and logged to NN-DECISOES.md (disclosed in the executive summary, with an undo path); hard gates — external info only the user has, scope/intent changes, irreversible actions beyond the PR, or any question without a confident recommendation — still stop and wait, and during the night quiet window (23h–07h local) a hard gate becomes a graceful pause instead of a prompt hanging till morning. By default goes all the way to the PR; `--no-ship` stops before shipping (after the automated UAT). Resumable — run again to continue where it left off."
argument-hint: "<phase> [--ui] [--ai] [--no-ship] [--vault <profile>] [--obs \"<texto livre>\"]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
  - Agent
  - TaskCreate
  - TaskUpdate
  - TaskList
---

<objective>
Run a single GSD phase end-to-end, so the user does not have to babysit the machine.
Orchestrate the native GSD commands in order:

**spec-phase `--auto` → discuss-phase `--auto` → revisão adversarial de intenção (Codex + agy) →
ui-phase (`--ui`) / ai-integration-phase (`--ai`) → plan → plan-review-convergence →
execute → code-review → ui-review (`--ui`) → eval-review (`--ai`) → secure-phase →
validate-phase → UAT interativo automatizado → resumo executivo → close (extract-learnings → ship/PR).**

This skill **does not reimplement** GSD logic — it invokes the native commands (via the
`Skill` tool) and chains them, inserting cross-AI plan review between planning and execution
(like `gsd-autonomous`, but with design contracts up front, an interactive automated UAT, and an
automated close at the end). It has two declared reuses-of-logic instead of invocations, both in
Etapa 5 (deriving the UAT scenarios; driving the browser via the `uat-playbook.md`), plus one
declared side-effect suppression in Etapa 1 (the discuss `auto_advance` — this skill owns the
chaining) — deliberate, documented exceptions (see workflow.md `operating_rules`). The close reuses the native
`/close-phase` skill (extract-learnings → verification bridge → ship), inheriting its safety brake:
it refuses to ship unless the UAT is genuinely clean.

**Intenção primeiro (Etapa 1):** quando a fase ainda não tem SPEC/CONTEXT, a skill os gera
sozinha (`gsd-spec-phase --auto` → `gsd-discuss-phase --auto`, cada escolha logada `[auto]`) e
submete a intenção a uma **revisão adversarial cross-AI**: dois revisores externos (Codex +
Antigravity) leem o dossiê
(PROJECT/ROADMAP/REQUIREMENTS/SPEC/CONTEXT) e o código real e tentam derrubar as decisões; o
Claude verifica cada achado contra o código antes de aceitar (loop por convergência: continua
enquanto os achados novos confirmados caem e > 0; teto duro de 5 ciclos, com detecção de
estagnação). Achado factual → corrigido no lugar; tradeoff de risco/implementação → adotado e
destacado no bloco de transparência do resumo; achado que mexe em **requisito, critério de
aceite ou oráculo de verdade** → pausa e espera o usuário. Sai o `NN-INTENT-REVIEW.md`. Um
revisor indisponível/falho → segue com o outro, degradação declarada em `sinos`; os DOIS
instalados-mas-falhos → a fase **para** com handoff limpo (fail-closed: sem segunda opinião a
intenção não segue; `intent_review: blocked` fica gravado e a próxima invocação re-tenta a
revisão); **nenhum revisor externo instalado** → a revisão é **pulada** (`intent_review:
skipped`) e o pulo vira item obrigatório do bloco de transparência do resumo executivo — a
fase segue (modo degradado para setups sem Codex/agy; instalar um revisor e apagar o
`NN-INTENT-REVIEW.md` re-habilita a revisão). Fases já planejadas pulam a etapa inteira.
Isto substitui a exigência antiga de rodar spec/discuss manualmente antes da skill — a
entrevista-carimbo deu lugar a um cético de máquina, e o humano decide só o que é da alçada dele.

**Rigor máximo sempre (decisão de 2026-07-05):** toda fase roda o pipeline completo — não há
classificação de porte nem supressão de etapas por tamanho. (Um classificador porte×risco, o
"dimmer", foi implementado, validado em fase real e **removido por decisão de custo-benefício
com dados**: nas fases reais medidas, a classificação sempre escalava para o rigor máximo, então
a máquina só somava custo e complexidade. A telemetria que embasou a decisão continua ligada.)
O que pode legitimamente não rodar é só o que a config do projeto desliga ou uma ferramenta
indisponível impede — e isso é sempre declarado: uma linha ao usuário, o evento `skip` na
telemetria e o bloco de transparência do resumo executivo.

**Arquitetura em camadas (P3):** a janela do orquestrador é o recurso mais escasso de uma
orquestração longa, então a skill separa **camada 0** (esta conversa: decide, encadeia, roteia,
pausa e fala com o usuário) de **camada 1** (subagentes com janela própria e descartável que
hospedam o trabalho verboso) e **camada 2** (os agentes internos que os comandos GSD spawnam —
intocados). Descem para a camada 1: a intenção inteira (Etapa 1 — `prompts/intent.md`), o
planejamento (2.3 — `prompts/plan.md`), a convergência do plano (3.2 —
`prompts/convergence.md`), a execução (3.3 — `prompts/execute.md`; **exceção**: com plano
`autonomous: false` pendente o execute roda inline, porque ação humana provável pede a
interação nativa da camada 0), o code review (4.1 — `prompts/code-review.md`), o eval review
(4.3 — `prompts/eval-review.md`), a secure phase (4.4 — `prompts/secure.md`), a validate phase
(4.5 — `prompts/validate.md`) e o close/ship (6.4 — `prompts/close.md`), além do UAT (5.3/5.4)
e do resumo executivo (Sub-rotina F), que já eram subagentes. Cada subagente lê as próprias
instruções do disco, trabalha, grava tudo em disco e devolve só um status compacto
(`done`/`needs_decision`/`blocked` — Sub-rotina H do workflow.md). Uma decisão que não é do
subagente sobe como `needs_decision` e passa pela **triagem de decisão** (Sub-rotina I, sempre
ligada): o que o usuário só carimbaria — condução do pipeline, decisão reversível com
recomendação clara — a camada 0 decide sozinha, registra no `NN-DECISOES.md` (com rota de
desfazer) e anuncia numa linha; o que é da alçada do dono — informação que só ele tem,
escopo/intenção, irreversível além do PR, ou qualquer pergunta sem recomendada — vira
`AskUserQuestion` e **continua o mesmo subagente** com a resposta — nada re-executa. Na janela
de silêncio (23h–07h locais) um gate duro vira parada graciosa com a pergunta no handoff, em
vez de prompt pendurado até de manhã. A varredura desce; a decisão sobe
(a ameaça de segurança, a estratégia de gaps de teste e a revisão do ship continuam sendo
suas). A descida não afrouxa nenhum fail-closed
(um `blocked` sobe com motivo e é a camada 0 quem para), o gate de contexto segue medindo a
camada 0 (é ela que não pode morrer) e o custo dos subagentes fica visível na telemetria
(`subagent_tokens`).

**Design contracts up front (Etapa 1.5):** under `--ui`/`--ai`, the skill first runs
`gsd-ui-phase`/`gsd-ai-integration-phase` to produce the `UI-SPEC.md`/`AI-SPEC.md` design
contracts *before* planning — because the planner consumes them, and the end-of-phase UI/eval
gates audit against them. Phases without the flag skip this.

**How far it goes (default):** all the way to the **PR**. Etapa 5 runs an *interactive automated
UAT* — a Sonnet subagent reads `uat-playbook.md` and drives the browser (clicks, fills forms,
walks flows) plus bash checks, **proving each scenario objectively** (HTTP status + console errors
+ persisted state, not fragile visual guessing). It classifies every scenario into **4 baskets**:
**1 passed** (green) · **2 failed** (one objective fix cycle, then a graceful stop if it survives) ·
**3 couldn't-verify** (login wall without a vault, 2FA, captcha, no browser → **blocks the ship**,
hands back to the human UAT) · **4 subjective** (aesthetic/content judgment → ships **with a
prominent disclosure** at the top of the executive summary). On a clean happy path it also leaves a
reusable Playwright regression test. When the UAT is objectively clean (only baskets 1+4), the skill
chains into `/close-phase` to extract learnings, bridge the verification gate, and open the PR.

**`--no-ship`** keeps the older behavior: run everything **including the automated UAT**, then
**stop** and hand control back without shipping (for when you want to eyeball it yourself first).
**`--vault <profile>`** unlocks authenticated flows: with a pre-configured vault profile, login
flows move from basket 3 (blind) to objectively verifiable. Without it, login walls stay basket 3.
The manual broad test suite (`/gsd-add-tests`) stays out of scope and becomes a **post-PR** step
(the happy-path Playwright test above partially covers it; `validate-phase` already
generated the Nyquist-gap tests before the ship).

**Resumable:** running `/go-and-do N` again never restarts from zero — it detects what is
already on disk and continues. This protects against the context window filling up or the 5h
limit cutting in mid-run.

**Resumo executivo (ao fim e em toda parada):** ao concluir o ciclo, a skill despacha um subagente
(Sonnet 4.6) que lê os artefatos da fase e escreve um `NN-RESUMO-EXECUTIVO.md` — a história da fase
em **prosa narrativa**, para o dono do projeto **não-técnico**: o que foi entregue, as decisões, os
problemas que apareceram e os warnings/criticals que os revisores pegaram, tudo traduzido com
analogias. **Quando a fase shipa com itens subjetivos (basket 4) assumidos,** o resumo abre com um
**bloco de transparência destacado** — "⚠️ Shipei assumindo estes pontos — confira antes de dar
merge" — listando cada item que a IA não julgou sozinha. Como o ship só **abre o PR** (não dá
merge), esse bloco é o sinal humano final: o que foi conferido de verdade × o que foi assumido. O
mesmo resumo (em modo `parcial`, deixando claro que a fase está pausada) é escrito antes de **toda
parada graciosa** (Sub-rotina D), pra você sempre ter um panorama do que rolou até travar. Gerado
por subagente porque narrar exige ler os artefatos verbosos — o que o gate de contexto proíbe no
orquestrador. Ver Sub-rotina F no workflow.md.

**Safety brakes:** (1) a recurring context gate at an absolute token ceiling (400k — below the
harness auto-compact observed at ~460k, so the skill's graceful pause acts first; env
`CONTEXT_TOKEN_LIMIT`) — before each main command it reads the session's absolute token usage and,
if at/over the ceiling, checkpoints + pauses (it fails open and announces what it measured, so a
silent no-op stays visible); (2) the skill's own hard stop points — the intent-review pause (Etapa 1: a confirmed finding
that touches a requirement, acceptance criterion, or truth oracle surfaces from the intent
subagent as `needs_decision` and waits for the user), the
intent-review fail-closed floor (Etapa 1: both external reviewers — Codex and agy —
installed but failing blocks the phase, recorded as `intent_review: blocked` so the next run knows
and retries; a single missing reviewer degrades declared via `sinos`; a setup with NO external
reviewer installed skips the review loudly instead of blocking — `intent_review: skipped`,
surfaced as a mandatory transparency item in the executive summary), persistent
verification gaps (Etapa 3.5), open security threats (4.4), entry-gate failures (0.3), a UAT bug
that survives one fix cycle (5.5 → pause), and the **anti-false-ship floor**: the skill ships
**only** when the UAT is objectively clean (no basket 2, no basket 3). A basket-3 scenario
(couldn't-verify) **blocks the ship** and hands back to the human UAT — never ship a behavior
nobody confirmed; (3) inherited stops — the native GSD commands raise their own `AskUserQuestion`
prompts (ui-phase BLOCKED / revision stall; ai-integration framework-selector interview /
validation; plan-phase coverage/split gates; execute-phase regression/schema/auth gates) that even
`--auto` does not silence. These are legitimate design/scope/reality decisions: the skill lets them
through to the user. The close itself inherits `/close-phase`'s brake (refuses to ship an unclean
UAT). See "Paradas herdadas" in workflow.md.

**Human action vs. couldn't-verify (the two graceful hand-backs):** when `execute-phase` blocks on
a `human-action` gate — a migration you must run (`npx supabase db push`), a login, a key to
paste — and that work is deferred, the skill detects the incomplete execution on return (Etapa 3.4
checks for plans missing `SUMMARY.md`) and closes with a clean handoff via `gsd-pause-work`
(Sub-rotina D), so you resolve the action and resume with `/go-and-do N`. The second hand-back is at
the UAT: a **basket-3** scenario (login wall without a vault, 2FA, captcha, no browser) means the
skill **could not verify** a behavior, so it does **not** ship — it hands back to `/gsd-verify-work`
for the human to verify those items. Both differ from end-of-phase `human_needed` (verification
items deferred): with `--no-ship` those become PENDING inputs the human resolves via
`/gsd-verify-work`; by default, the skill resolves what it can in the UAT and only the genuinely
unverifiable (basket 3) blocks the ship.
</objective>

<execution_context>
@$HOME/.claude/skills/go-and-do/workflow.md
</execution_context>

<context>
Phase number + flags: $ARGUMENTS

**Argument:** `<phase>` — required. The phase number to run (e.g. `3`). No number → stop and ask.

**Flags:**
- `--ui` — the phase has frontend; enables the UI design contract (Etapa 1.5) and the UI review gate (4.2), which spins up the dev server for a rendered audit.
- `--ai` — the phase is an AI feature; enables the AI design contract (Etapa 1.5) and the eval review gate (4.3).
- `--no-ship` — run everything including the automated UAT, then **stop** and hand back without closing/shipping (the older "prepare for your UAT" behavior). Default is to go through the UAT and ship.
- `--vault <profile>` — pass a pre-configured gsd-browser vault profile so the UAT subagent can log in and verify authenticated flows (moves login flows from basket 3 to verifiable). 2FA/captcha stay basket 3.
- `--obs "<texto livre>"` — a free-text note for this run (e.g. "check file X", "see continue-here.md"). Captured once in Etapa 0.1 and carried as a standing note to **every** stage dispatched in this invocation (Sub-rotina H prefixes it onto each subagent's dispatch message) — each stage judges for itself whether it's relevant. Not persisted across sessions: repeat the flag on a resume if you want it applied again.

Phases without a flag skip those gates (UI/AI contracts and audits). Everything else always
runs. A step that does not run (config gate off, tool unavailable) is announced and disclosed
in the summary.
</context>

<process>
Execute end-to-end following workflow.md.
Preserve every gate and every stop point: entry gates (Etapa 0.3), the intent-review pause
(Etapa 1 — a confirmed finding touching a requirement, acceptance criterion, or truth oracle
waits for the user; both external reviewers (Codex + agy) unavailable/failed blocks the phase,
`intent_review: blocked`, never proceed without the second opinion — one missing reviewer
degrades declared, never silently), persistent gaps
(Etapa 3.5 → pause), open security threats (4.4 → block), a UAT bug that survives one fix
cycle (Etapa 5.5 → pause), a basket-3 couldn't-verify scenario (Etapa 5 → block the ship, hand
back), and the recurring context gate (absolute token ceiling → checkpoint + pause). Honor the
anti-false-ship floor: ship only when the UAT is objectively clean (no basket 2, no basket 3). Route
every would-be `AskUserQuestion` — inherited stops included (ui-phase BLOCKED / revision stall;
ai-integration framework-selector interview / validation; plan-phase coverage/split;
execute-phase regression/schema/auth) — through the decision triage (Sub-rotina I): what the user
would merely rubber-stamp is auto-decided and logged to `NN-DECISOES.md`; what is genuinely his
(external info, scope/intent, irreversible beyond the PR, no confident recommendation) reaches him —
or, in the night quiet window, becomes a graceful pause with the pending question in the handoff.
Never skip a stop point to "keep going", and never auto-decide across a hard-gate criterion. When
execution ends incomplete because
a plan needs your action (Etapa 3.4), close gracefully via Sub-rotina D (`gsd-pause-work`) rather
than ending raw or sitting blocked.
Keep a live task list (TaskList) mirroring disk state —
built in Etapa 0 and faithful on resume to what is done and to the step in flight
(Sub-rotina C); only the orchestrator touches it.
A step that does not run (a config gate off, an unavailable tool) is never silent: announce it,
log the `skip` event, and disclose it in the summary's transparency block. Never mutate project
config to make a step not run.
Stages marked "via subagente" dispatch through Sub-rotina H (`prompts/*.md`, absolute paths,
config gates checked in layer 0 before dispatching) and route the compact return: a
`needs_decision` becomes an `AskUserQuestion` and the user's answer continues the same subagent;
a `blocked` surfaces with its reason and layer 0 is who stops — dispatching never relaxes a
fail-closed gate.
</process>
