<!-- ============================================================ -->
<!-- workflow.md — o miolo executável da skill go-and-do.        -->
<!-- Embutido no SKILL.md via @ (carregado na ativação).         -->
<!-- Instruções imperativas para o orquestrador. Não é doc.      -->
<!-- Formato híbrido (T.3): aqui mora só o residente — roteiro,  -->
<!-- contratos por etapa e sub-rotinas sempre-ativas. O detalhe  -->
<!-- de cada etapa mora nos prompts/*.md (lidos pelo subagente); -->
<!-- o condicional mora em workflow-ui.md / workflow-ai.md /     -->
<!-- workflow-dev-server.md (lidos sob demanda).                 -->
<!-- ============================================================ -->

# go-and-do — execução

<role>
You are the orchestrator. You run one GSD phase by invoking native GSD commands in order and
chaining them. You do not reimplement GSD logic.

Toda a sua saída ao usuário — banners, anúncios de status, linhas de "🔔" —
é em **pt-BR**. (As tags estruturais e o papel aqui estão em inglês por convenção; a
operação e tudo que o usuário lê, em pt-BR.)
</role>

<operating_rules>
Operating rules — read once, apply throughout:

- Invoke GSD commands via the `Skill` tool — inline in layer 0 only where the stage block says
  so; most stages dispatch a layer-1 host subagent that invokes the command in its own window
  (Sub-rotina H). Either way, wait for one step to finish before starting the next — you
  control the chaining.
- **Every main step runs between two mechanical fences (par 2.C):** `pre-despacho.sh <id>`
  opens it (context gate + checkpoint + route: `ok`/`pular`/`skip`/`stop`/`bloqueio`) and
  `confere-etapa.sh <id>` closes it (manifest asserts against the DISK + canonical verdict
  extraction + the `end` telemetry event with measured tokens). You never re-read a gate
  report and never accept a subagent's `done` over a failing fence — exit 1 sends the work
  back. Scripts compute; you judge and route.
- Reuse, don't reinvent — three declared deviations: (1) the UAT reuses the verify-work
  scenario-derivation logic inline via subagent (verify-work has no "generate and stop" mode);
  (2) the UAT drives the browser via subagent + `uat-playbook.md` (no native interactive-UAT
  command); (3) Etapa 1 suppresses the discuss `auto_advance` side-effect and resets its chain
  flag (this skill owns the chaining). All deliberate; the right fix for each is upstream.
  The close is NOT an exception — it reuses the native `/close-phase` skill.
- Don't read artifact bodies into your own window — layer 0 decides by frontmatter, by the
  SDK's JSON status fields and by file existence. Whoever genuinely needs an artifact's
  content — verifying intent, reviewing plan/code, deriving the UAT, driving the browser,
  narrating the summary — is the layer-1 subagent of that step, which reads/writes on disk and
  returns only a compact status.
- Honor every stop point — never skip one to keep going. The hard stops: missing entry
  prerequisites (Etapa 0), incomplete execution blocked on the user (3.4 → Sub-rotina D),
  persistent gaps after one retry (3.5), no external reviewer at 2.5 (PC-6, fail-closed),
  open security threats (4.4), a UAT bug that survives one fix cycle (5.5 → D), and the
  anti-false-ship floor: ship only with the UAT objectively clean (no basket 2/3).
- Everything is resumable. Re-running `/go-and-do N` must never redo finished work — the
  `abre-rodada.sh` and each `pre-despacho.sh` decide resume mechanically from disk state.
- Keep a live task list mirroring disk state (Sub-rotina C). Log telemetry only at your
  assigned writer slots (Sub-rotina G) — every other event already has a script owner.
- A step that does not run is never silent: one line to the user, a `skip` event, and an entry
  in the resumo's transparency block. Never mutate project config to make a step not run.
- Paths: the skill lives at `$HOME/.claude/skills/go-and-do/`; `phase_dir`/`padded_phase`
  (the `NN` prefix) come from the abre-rodada retrato. Dispatch paths are always absolute.
- **Gates decidem sobre saída CRUA, nunca filtrada por wrapper.** Ambiente com hook que
  reescreve Bash e compacta saída (ex.: RTK): todo comando cujo RESULTADO alimenta decisão de
  gate (`wc -l`, teste de saída vazia, `grep` que roteia por exit code) roda com
  `rtk proxy <cmd>`. Vale para TODAS as camadas e vai repassada nos briefings com
  comandos-gate (caso real F22: 3 golpes na mesma rodada). Leitura exploratória continua
  filtrada; só o comando-gate é cru. Os scripts da skill leem espelhos
  `.planning/.gad-last-*.json` quando o stdout for capado (PC-5).
</operating_rules>

---

<master_checklist>

## Roteiro-mestre (todas as ações, na ordem)

Legenda: 🎌 só com a flag · ⏭️ retomada (pula se já feito) · ⏸️ pode parar · 🔒 gate de contexto antes

**Etapa 0 — Preparação**
1. Lê argumentos (fase + `--ui`/`--ai`/`--no-ship`/`--vault`/`--obs`). Sem número → ⏸️ para e pede.
2. `abre-rodada.sh N [flags]` — portões, retrato, gate, retomada, vault_alerta, aninhamento, hook, retrato da TaskList, evento `run` + ponteiro, num script só. Exit ≠ 0 → ⏸️ para com o motivo.
3. `confere-etapa.sh 0` (self-check da abertura); espelha a TaskList do retrato (Sub-rotina C), obedece `vault_alerta` (pergunta antes de gastar a fase) e `aninhamento: probe_necessario` (probe mínimo + `--registra-aninhamento`).
4. 🎌 `--ui` (ou UI-SPEC existente) → leia `workflow-ui.md` agora (única leitura da rodada); `--ai` idem → `workflow-ai.md`; fase com server → `workflow-dev-server.md` quando chegar no 1º passo que o usa.
5. Banner e libera.

**Etapa 1 — Intenção: spec + discuss + revisão adversarial** *(⏭️ obedece `etapa_1` do abre-rodada)*
6. ⏭️ `etapa_1: pular` → Etapa 1.5 (a intenção já virou plano ou o review está `done`/`skipped`).
7. 🔒 ⏭️ `pre-despacho.sh 1` → despacha o agente **`gad-intent`** (Opus 5 medium) com `prompts/intent.md` — um único despacho cobre SPEC + CONTEXT + revisão adversarial; a retomada fina por arquivo é do subagente (`setup-intencao.sh`). Dentro dele: filho `gad-spec` hospeda `gsd-spec-phase N --auto` (termina no SPEC, sem auto-advance).
8. ↳ *(filho `gad-discuss`)* CONTEXT: `gsd-discuss-phase N --auto`, sem executar o `auto_advance`, zerando `workflow._auto_chain_active` na volta.
9. ↳ *(no subagente)* Revisão adversarial: Codex + agy criticam (pareceres em `<phase_dir>/pareceres/`) ↔ filho `gad-verificador` verifica cada achado; loop com parada por custo marginal (`decide-ciclo.sh`, teto duro 4); factual → corrige · requisito/critério/oráculo → `needs_decision` ⏸️ sobe · tradeoff → adota + transparência. UM revisor falho → segue com o outro, sino; os DOIS instalados-mas-falhos → `blocked` ⏸️; NENHUM instalado → `skipped` com sino gritante e segue.
9b. **Gate de rota (camada 0, ao receber o `done`):** `confere-rotas.sh <phase_dir>/pareceres` — exit 1 → devolve ao MESMO subagente (passo 7b do intent.md, fail-closed). Exit 0 → `conta-turnos.py <transcript> <pareceres>` (estouro = evento `incidente`; medição, não bloqueio) → `confere-etapa.sh 1` (cancela + `end` medido).

**Etapa 1.5 — Contratos de design** *(🎌 só com a flag · retomada por existência de arquivo)*
10. ⏭️ `setup-contratos.sh <phase_dir> <NN> [--ui] [--ai]` decide: ambos `pular`/`sem-flag` → pula a etapa inteira; flag × config off → flip declarado (flag vence).
11. 🔒 🎌 Despacha o agente `gad-contratos` (Opus 5 medium) com `prompts/contratos.md` — hospeda `gsd-ui-phase` e `gsd-ai-integration-phase` inline (ordem UI → IA). Perguntas herdadas sobem como `needs_decision`; a resposta continua o MESMO subagente.
12. Ao voltar: `confere-etapa.sh 1.5` (asserts por flag) — exit 1 devolve ao mesmo subagente.

**Etapa 2 — Planejamento**
13. ⏭️ Obedeça `etapa_2` do abre-rodada (`pular` → Etapa 2.5).
14. 🔒 `pre-despacho.sh 2` → despacha o agente `gad-plan` (Opus 5 medium) com `prompts/plan.md` — ele julga pesquisa/mapper/granularidade (2.D/2.E/2.G) e hospeda o `gsd-plan-phase`.
15. ⏸️ `confere-etapa.sh 2` (cancela mecânica; senão devolve ao subagente) + fecho 2.4b: classifica os `autonomous: false` — (a) pergunta agora · (b) `NN-ACAO-HUMANA.md` detalhado, executado e apagado · (c) defere ao UAT — e flipa os planos.

**Etapa 3 — Construção**
16. ⏭️ `has_verification` → pula a Etapa 3 inteira.
18. 🔒 ⏭️ `pre-despacho.sh 2.5` decide (pular · skip_config declarado · ⏸️ bloqueio_sem_revisor = fail-closed PC-6 · ok) → Convergência via **subagente** (Sub-rotina H + `prompts/convergence.md`, hospedando `gsd-plan-review-convergence --codex --agy --max-cycles 3`; lanes por `roda-codex.sh`/`roda-agy.sh`). Não convergiu (`escalou`) → ⏸️ para.
18b. **Pré-flight de paralelismo** (só com `use_worktrees: true` e onda com ≥2 planos): worktree degradaria por **base mismatch** → aplique o antídoto `"worktree": {"baseRef": "head"}` no `.claude/settings.local.json`, re-cheque, registre no `NN-DECISOES.md`. Degradaria por **qualquer outra causa** → investigue a solução e ⏸️ suba AskUserQuestion com diagnóstico + opções — degradação nunca vira fato consumado (3 fases já serializaram pelo mesmo padrão sem antídoto).
19. 🔒 Execução via **subagente** (Sub-rotina H + `prompts/execute.md`) — sobrou `autonomous: false` (exceção rara pós-2.4b) → **inline** (`Skill gsd-execute-phase --auto --no-transition`).
20. Checa completude: plano sem SUMMARY (ação humana travou ondas) → ⏸️ Sub-rotina D. Senão status: passed → segue · human_needed → anota (insumo da Etapa 5) e segue · gaps_found → 21.
21. *(gaps)* Fecha 1×: despacho da 2.3 (`prompts/plan.md`, args `N --gaps`) → re-execução pela regra de rota da 3.3 → re-verifica. ⏸️ Persistiu → Sub-rotina D.

**Etapa 4 — Gates de qualidade** *(retomada por existência de arquivo)*
22. 🔒 ⏭️ `pre-despacho.sh 4-code-review` → Code review via **subagente** (`prompts/code-review.md`, iteração 1 com lane Codex 4.D; 2+ estreitadas via `calcula-files.sh`). `confere-etapa.sh` extrai critical/warning/total → Critical restante 🔔; segue sempre.
23. 🔒 🎌 UI review — conduza pelo `workflow-ui.md` (já lido no item 4).
24. 🔒 🎌 Eval review — conduza pelo `workflow-ai.md` (já lido no item 4).
25. 🔒 ⏭️ `pre-despacho.sh 4-secure` → Secure via **subagente** (`prompts/secure.md`); aceites chegam MASTIGADOS (4.E). ⏸️ `confere-etapa.sh 4-secure` exit ≠ 0 → **bloqueia** (único gate bloqueante). Secure tocou src/ → 4.1b re-review estreitado.
26. 🔒 ⏭️ `pre-despacho.sh 4-validate` → Validate via **subagente** (`prompts/validate.md`). ⏸️ Gaps → `needs_decision` (Fix all recomendado).

**Etapa 5 — UAT interativo automatizado** *(retomada por ESTADO do `NN-UAT.md`)*
27. ⏭️ Retomada por estado (5.1): ausente → 28 · `pre_uat` ≠ `executed` → 29 · `executed` + `issue` sem marcador de fix → 30 · com marcador → ⏸️ D · sem `issue` em aberto → Etapa 6.
28. 🔒 Gera o `NN-UAT.md` via subagente (classify-coverage MECÂNICO primeiro → find_summaries → extract_tests + cold-start → create_uat_file); frontmatter `pre_uat: generated`.
29. 🔒 Despacha o **subagente de UAT** (Sonnet + `uat-playbook.md`) — **sempre, com ou sem GUI**. A janela dele gerencia o server; classifica nos 4 baldes, devolve só o QUALITATIVO. Ao voltar: `confere-etapa.sh 5` reconcilia do disco e — só ele — promove `pre_uat: executed`.
30. *(balde 2)* 🔒 1 ciclo de conserto: replan `--gaps` → re-execução `--gaps-only` → re-review estreitado → re-UAT só nos `issue` → `confere-etapa.sh 5 --fix-cycle`. Persistiu → ⏸️ Sub-rotina D.

**Etapa 6 — Encerramento + ship** *(roteamento por balde)*
31. **Roteamento mecânico:** `pre-despacho.sh 6` → `rota` (pausa → ⏸️ D · handback → banner · ship) + `git_remote` (false → rota B 6.E) + `uat_passed_raw` + transparência extraída (6.2).
32. Consolida o "🔔 O que precisa de você agora" + o bloco de transparência (as 5 listas já vêm extraídas — você só redige).
33. Resumo executivo (modo final): **Sub-rotina F**. ⏭️ idempotente (`go_and_do_resumo: final`).
34. `commita-artefatos.sh uat` (6.3b). 🔒 **Ship** (rota A): via **subagente** (`prompts/close.md`, hospedando `close-phase N` — learnings → promoção → PR → revisão auto-"Skip" carimbada → merge direto, 6.D). Rota B (sem remote): ship alternativo do projeto executado pela camada 0 (6.E). ⏸️ Bloqueio de ambiente → `blocked`; respeita e reporta. Depois: emenda factual do "Desfecho do ship" no resumo (6.4c) + commit.
35. `confere-etapa.sh 6` (self-check PLAN×SUMMARY + anti-placeholder de ts) + banner final + evento `stop` + ponteiro removido + `commita-artefatos.sh runlog`, e devolve o controle.

</master_checklist>

---

<stop_points>

## Paradas herdadas — quando um comando GSD te chama (não é bug)

Os stops PRÓPRIOS desta skill estão no roteiro (gate de contexto, pausa da revisão de intenção,
bloqueio sem revisor, gaps persistentes, ameaça aberta, bug de UAT persistente, balde 3 no
ship). Os comandos GSD invocados têm stops deles — decisões que o comando não toma sozinho.
Quando um disparar, roteie pela **triagem de decisão (Sub-rotina I)**: alçada do usuário chega
a ele (nunca contorne a parada com flags); carimbo é auto-decidido e registrado no
`NN-DECISOES.md`. Comando hospedado em subagente (Sub-rotina H) → o mesmo stop chega como
`needs_decision` mastigado; a resposta continua o mesmo subagente. O stop é honrado igual; só
muda o transporte.

- **Etapa 1.5** (`gsd-ui-phase` / `gsd-ai-integration-phase`): os stops estão em
  `workflow-ui.md` / `workflow-ai.md` (lidos com a flag).
- **`gsd-plan-phase`**: decision-coverage gate (desligável por
  `workflow.context_coverage_gate: false`) · requirements-coverage gap · source-audit gaps /
  phase-split recommended (fase mal-dimensionada — melhor split que plano inchado) ·
  revision-loop stall (3 iterações sem convergir).
- **`gsd-execute-phase`** (o `--auto` da 3.3 não silencia estes): falha de teste de
  regressão · schema drift · conflito pós-merge · checkpoint `human-action` (auth/2FA/
  migrations que só o dono roda — nunca se automatizam; se ele defere, a 3.4 detecta a
  execução incompleta e fecha pela Sub-rotina D em vez de deixar preso no prompt).

Regra de ouro: stop de decisão de design/escopo ou portão de realidade (regressão/schema/auth)
é legítimo — pausa, anota no banner, e o usuário decide. A Sub-rotina I formaliza a régua.

</stop_points>

---

<subroutines>

<subroutine name="A — gate de contexto (antes de cada comando principal)">

## Sub-rotina A — gate de contexto (antes de CADA comando principal)

O gate roda DENTRO do `pre-despacho.sh <etapa>` — todo passo 🔒 do roteiro já o executa ao
abrir a cerca. Você não digita mais bloco de medição; obedece o exit code:

- **exit 0** — `ok` (siga; anuncie numa linha o que mediu: "contexto em 180k/400k — seguindo"),
  ou `pular`/`skip` (a etapa não roda; o evento já foi gravado).
- **exit 3** — `stop`: teto de contexto. O script já gravou o evento, removeu o ponteiro e
  devolveu o handoff pronto → **Sub-rotina D** com o motivo `contexto em NNk`.
- **exit 4** — `bloqueio_sem_revisor` (só na 2.5): repasse a `pergunta_ao_dono` e ⏸️ pare.
- `status=unknown` no JSON → siga, mas declare o `reason=` numa linha (fail-open de MEDIÇÃO,
  deliberado — a retomabilidade cobre; o ganho é você não se achar protegido quando não está).

Racional (não re-litigue): teto **absoluto de 400k tokens** — mede a quantidade carregada, não
fração de janela (que varia 5× e era ilegível por skill); fica abaixo do auto-compact do
harness (~460k) porque **parar-e-retomar fresh > compactar** (estado em disco + commits
atômicos + handoff tornam a retomada superior à compactação com perdas). Ajustável via env
`CONTEXT_TOKEN_LIMIT`. O gate SUB-mede de propósito (exclui turnos de advisor; só camada 0) —
por isso o teto tem folga, não margem zero.

**Detector de auto-compact (mecânico):** o `run-log.sh` grava `compact` quando os checkpoints
da mesma sessão caem >100k. Ao vê-lo (ou notar a queda): anuncie numa linha e **re-ancore** —
as sub-rotinas seguem valendo, o roteiro segue de onde o DISCO diz que está.

**Granularidade (limitação conhecida):** o gate só mede ENTRE comandos — não interrompe um
`Skill` no meio. Isso pesa quase só na rota inline da 3.3; se ela for inevitável numa fase
enorme, quebre antes (`/gsd-phase`) ou pause manualmente (`/gsd-pause-work`).

</subroutine>

<subroutine name="B — dev server (ponteiro)">

## Sub-rotina B — subir / derrubar o dev server

Mecanizada no `scripts/dev-server.sh` (`up` = receita persistida ou heurística + espera de
porta + auto-persistência; `down` = morte por sessão do PID). **A craft e as regras de dono da
janela estão em `workflow-dev-server.md`** — leia quando a fase tiver server para subir (UI
review / UAT); fase sem server, este arquivo nem entra na janela.

</subroutine>

<subroutine name="C — lista de tarefas ao vivo (TaskList)">

## Sub-rotina C — lista de tarefas ao vivo (TaskList)

A TaskList dá visibilidade ao vivo do pipeline. É **efêmera** (vive só na sessão) — nunca
fonte da verdade: o estado real está no disco; a lista só **espelha**. Quem mexe nela é só o
orquestrador.

- **Quem calcula é script (S.C):** o retrato `tasklist` do `abre-rodada.sh` (e a reconciliação
  do `confere-etapa.sh 6`) devolve tarefa → estado desejado, computado do disco (15 tarefas
  possíveis: intenção 1–3, contratos 4–5, planejar 6, convergência 7, executar 8, gates 9–13,
  UAT 14, encerramento 15 — criadas só as aplicáveis à rodada). Você só aplica
  `TaskCreate`/`TaskUpdate` para espelhar. Numa retomada, a lista nasce fiel ao que já foi
  feito.
- **Disponibilidade primeiro:** os tools de task são flag de runtime (some sem changelog). Sem
  `TaskCreate`/`TaskList` na janela (nem via `ToolSearch`), pule a sub-rotina inteira:
  declare uma vez ("TaskList indisponível — seguindo pelo disco") e mencione no resumo.
- **Disciplina:** ao despachar um passo 🔒 → `in_progress` na(s) tarefa(s) que ele cobre; ao
  concluir (artefato no disco) → `completed`. Retorno `needs_decision` deixa `in_progress`
  (o passo está no meio).
- **Em parada:** a tarefa em curso fica `in_progress` — a montagem da próxima rodada relê o
  disco e corrige. **No fecho (6.5):** varredura anti-órfã — tarefa `in_progress` sobrando =
  🔔 (etapa que não vai mais rodar → complete com nota do porquê).

</subroutine>

<subroutine name="D — parada graciosa (pause-work)">

## Sub-rotina D — parada graciosa (pause-work)

Use quando sobra **trabalho de implementação** que depende do dono: ação humana
(`human-action`), ondas travadas por ela, revisores de intenção `blocked`, gaps persistentes
(3.5), ameaça aberta (4.4), bug de UAT persistente (5.5), ship `uat_reprovado`, gate duro na
janela de silêncio (Sub-rotina I), ou o teto de contexto (Sub-rotina A). Feche com handoff
limpo:

1. **Encerre o trabalho vivo — inclusive o que o TaskStop não mata.** `TaskStop` na árvore do
   subagente ativo; depois varra bash em background órfãos (waiters de disco, processos codex
   — um waiter já sobreviveu 55min ao TaskStop) e encerre o que era da árvore parada. Feche na
   telemetria a etapa interrompida: último evento é `checkpoint` sem `end` → grave `end` com
   etapa `"<etapa> (interrompida na pausa)"` (parcial vale; nunca estime).
2. **Resumo executivo (modo parcial):** Sub-rotina F com `modo: parcial` e o `motivo`. Falhou
   ao gerar → não pare por isso; registre numa linha e siga (o handoff técnico é o que garante
   a retomada).
3. `Skill gsd-pause-work` — handoff durável (HANDOFF.json + `.continue-here.md`) + commit WIP.
   Registre o evento `stop` (etapa `pausa: <motivo>`). **Reconciliação-lite do STATE.md:**
   confira que `stopped_at`/`Resume file` apontam o ponto REAL desta parada (o pause-work não
   corrige um stopped_at herdado — quem retoma pelo STATE seria enganado); divergiu → emende
   as duas linhas no commit WIP.
4. **Pare** com a linha de handoff `🔔`: o motivo, a ação exata (comando literal), os planos
   pendentes, e onde está o `NN-RESUMO-EXECUTIVO.md`. Retoma com `/go-and-do N`.

> **Quando NÃO usar:** balde 3 (não-pude-verificar — falta verificação HUMANA; rota de
> hand-back da Etapa 6, próximo passo `/gsd-verify-work`) e balde 4 (assumed — shipa com
> transparência). Um HANDOFF.json sobrando desviaria a retomada. A régua: bug de
> implementação → D; item não-verificável ou subjetivo → Etapa 6.

</subroutine>

<subroutine name="E — resolver o gsd-tools (lib)">

## Sub-rotina E — resolver o `gsd-tools` (lib/gsd-shim.sh)

O shim colável morreu: a resolução vive em `scripts/lib/gsd-shim.sh`, `source`d por todos os
scripts da skill. Nos raros blocos Bash SEUS que consultam o SDK direto (ex.: 3.4):

```bash
. "$HOME/.claude/skills/go-and-do/scripts/lib/gsd-shim.sh"
gsd_run query phase-plan-index N
```

A lib resolve o `gsd-tools.cjs` (runtime → `.claude/` do projeto → PATH → `~/.claude/`) e
falha com a instrução de install (`npx -y @opengsd/gsd-core@latest --claude --local`) — isso é
portão de entrada: **pare** e mostre o comando (o `abre-rodada.sh` já cobre a abertura).

</subroutine>

<subroutine name="F — resumo executivo (subagente Sonnet 5)">

## Sub-rotina F — gerar o resumo executivo (via SUBAGENTE)

Escreve o `NN-RESUMO-EXECUTIVO.md`: a história da fase em prosa, para o dono não-técnico.
Chamada em dois momentos: `modo: final` (Etapa 6.3) e `modo: parcial` (toda parada da
Sub-rotina D). As instruções completas moram em **`prompts/resumo.md`** (o subagente lê do
disco — não leia antes de despachar).

1. **Números com fonte mecânica:** ANTES do despacho, rode
   `scripts/numeros-da-fase.sh <phase_dir> NN` e cole o bloco inteiro no despacho.
2. **Despache** um `Agent` com `model: sonnet` e `run_in_background: false`, entregando: o
   caminho de `prompts/resumo.md`, `NN`, `phase_dir` absoluto, `modo` e — no `final` — o
   `desfecho` + as listas extraídas pela 6.2 (`itens_assumidos`, `itens_nao_verificados`,
   `itens_intencao`, `itens_nao_rodados`, `riscos_aceitos`, incidentes da rodada) + a dica de
   🔔; no `parcial` — o `motivo`.
   > Por que subagente: narrar exige LER os artefatos verbosos — proibido na camada 0.
   > Por que Sonnet: síntese/escrita, não precisa de Opus.
3. **Confira na volta:** `numeros-da-fase.sh <phase_dir> NN --conferir <resumo>`. Exit 1 →
   re-despache 1× com as divergências (ou emende pontual) e re-confira. Persistiu → siga com
   🔔 `resumo com número sem fonte` no banner (nunca silencie).
4. **Commit:** `git add <resumo> && git commit -m "docs(fase NN): resumo executivo"` (sem
   footer). Falhou → não pare; registre numa linha.

**Idempotência:** `modo: final` com `go_and_do_resumo: final` já no arquivo → pule. Um
`parcial` anterior é sobrescrito pelo `final`. No `parcial` sempre regera.

**Telemetria:** o despacho é cercado como comando principal (checkpoint/end — etapa
`resumo final`/`resumo parcial`); é um dos subagentes mais caros da rodada e sem o `end` o
custo dele some da conta.

</subroutine>

<subroutine name="G — telemetria da rodada (run-log)">

## Sub-rotina G — telemetria da rodada (`NN-RUN-LOG.jsonl`)

Retrato fiel da linha do tempo da fase: 1 linha JSONL por evento em
`<phase_dir>/NN-RUN-LOG.jsonl`, com camada/modelo/effort/custo por etapa. A grade nasce
COMPLETA por escrita mecânica — o run-log é a fonte primária de custo.

**Regra do escritor único (T.2)** — cada evento tem exatamente um escritor; você NÃO grava o
que já tem dono:

| Evento | Escritor | Quando |
|---|---|---|
| `run` | `abre-rodada.sh` | abertura da rodada |
| `checkpoint` | `pre-despacho.sh` | abre a janela da etapa, com a fotografia do contexto |
| `end` | `confere-etapa.sh` | fecha a janela no pass, com `tokens_reais`/`custo_usd` do `mede-tokens.py` (transcript, nunca autodeclaração — `tokens_camada2` MORREU) |
| `despacho`/`retorno` | hook `gad-lifecycle.sh` | início/fim de todo `Agent()`, com camada de origem e modelo/effort da def |
| `script` | cada script da skill | auto-registro nome+exit+resumo em rodada ativa |
| `stop` | `pre-despacho.sh` (teto) ou você (pausa/fim de rodada) | desfecho |
| `compact` | o próprio `run-log.sh` | detector mecânico (queda >100k) |

O que SOBRA para você (chamada direta, `<phase_dir>` sempre ABSOLUTO):

```bash
bash $HOME/.claude/skills/go-and-do/scripts/run-log.sh <phase_dir> <NN> <skip|stop> "<etapa>" [tokens] [pct] "" [limit] "" "<motivo>"
```

- **`skip`** — todo passo que TERIA rodado e não roda fora das cercas mecânicas (as cercas já
  gravam os delas): etapa = `"<id> (<motivo>)"`.
- **`stop`** de pausa/fim de rodada — com medição final e o motivo no 10º argumento. Antes do
  stop de fim de rodada: `run-log.sh <dir> <NN> audit` (fecha janelas abertas; sessão morta →
  `close --sessao <id>`).

**Vocabulário canônico da `etapa`:** começa com o ID novo (`0 abertura` · `1 intencao` ·
`1.5 contratos` · `2 planejamento` · `2.5 convergencia` · `3 construcao` · `4.1 code-review`
… `4.5 validate` · `5 uat` · `6 encerramento`) ou `preparacao` · `probe` · `resumo` ·
`lateral <descrição>`. Sem ID estável, a agregação entre fases é inviável.

O script nunca falha o pipeline (exit 0 sempre; `flock`; `seq` monotônico; auto-fechamento de
janela órfã com aviso — viu o aviso, anote o que souber num `end` corretivo). Telemetria é
instrumento, não gate.

</subroutine>

<subroutine name="H — protocolo de subagentes (camada 1)">

## Sub-rotina H — protocolo de subagentes (camada 1)

Camadas: a **0** (esta conversa) decide, encadeia e fala com o usuário; a **1** são subagentes
com janela descartável que executam o trabalho verboso de uma etapa; a **2** são os agentes
que a 1 despacha ou hospeda (os internos do GSD + os filhos `gad-*` desta skill, defs em
`~/.claude/agents/`). O porquê: a janela da camada 0 é o recurso mais escasso — foi o eco de
orquestração inline que levou fases reais a ~90% da janela.

**Despacho.** Etapa cujo bloco manda despachar roda num subagente `general-purpose` (modelo
herdado, salvo pin declarado no bloco), **sempre síncrono: `run_in_background: false`
explícito** — despacho background quebra o fluxo (a notificação não retoma o roteiro). O
prompt de despacho é mínimo; as instruções moram no `prompts/<etapa>.md` que o SUBAGENTE lê do
disco. **Não leia o prompt antes de despachar** — referencie o caminho (ler duplica na camada
0 o que a arquitetura mandou pro disco). O despacho leva:

- o caminho do arquivo de instruções (`$HOME/.claude/skills/go-and-do/prompts/<etapa>.md`);
- `N`/`NN`, `phase_dir`, `project_root` e caminhos de entrada — **sempre absolutos** (o cwd do
  subagente não é a raiz do projeto);
- flags relevantes e `args` quando o bloco variar o comando;
- havendo `obs_text` (`--obs`): o texto literal como primeira linha ("Nota do usuário para
  esta rodada: …") — o subagente decide se é relevante; ignorar por não se aplicar é resposta
  válida;
- em retomada de pausa: a resposta do usuário, verbatim.

**Credenciais (regra de nascença de todo despacho autenticado).** Tarefa que exige sessão
logada ou toca segredos leva: (1) a **via sancionada** preparada pela camada 0 ANTES (wrapper
que injeta credenciais no processo, ou helper que emite só o código efêmero — nunca o
segredo); e (2) a proibição literal: "PROIBIDO ler, copiar ou imprimir `.env*`/segredos por
qualquer via — leitura indireta é evasão. Login impossível pela via sancionada → balde 3 ou
`blocked`, nunca contorne um controle." Constraint aplicada reativamente chega sempre um
despacho tarde.

**Background dentro do subagente:** subagentes NÃO recebem notificações de trabalho em
background — os `prompts/*.md` carregam o protocolo: background só para trabalho >10min, com
resultado em arquivo combinado e espera por UM waiter de disco bloqueante com
`timeout: 600000` explícito (vale para TODA camada, orquestrador incluso) — nunca espera de
notificação, nunca polling picado. Retorno fora do contrato (prosa em vez de bloco) → não
aceite nem redespache: **continue o mesmo subagente** com "decida pelo estado do disco e
finalize pelo return_contract".

**Contrato de retorno.** Todo subagente da camada 1 devolve um bloco compacto — nunca
conteúdo verboso (o retorno é dado de roteamento; corpo vive no disco):

- **`done`** — veredito, caminhos, contagens. **Seção `incidentes:` obrigatória (regra 24a):**
  todo desvio entre o anunciado e o executado, ou literalmente `nenhum`. Ausente → retorno
  fora do contrato (reconciliação); item ≠ `nenhum` → evento `incidente` no run-log + repasse
  ao despacho da Sub-rotina F (o resumo os narra — incidente declarado numa camada e não
  repassado já enganou o dono 2×).
- **`needs_decision`** — o subagente gravou o progresso em disco e devolveu a pergunta
  mastigada (opções + tradeoffs + `recomendacao` + `reversivel`). Roteie pela **Sub-rotina I**;
  a resposta **continua o MESMO subagente** (não redespache: a continuação preserva o contexto
  de graça). **Rótulo honesto:** "Decisão do usuário: X" só se ele de fato escolheu X;
  resposta que é pergunta NÃO é decisão (responda e re-pergunte); delegação → "decisão da
  camada 0 (usuário delegou): X"; triagem → "decisão da camada 0 (triagem): X".
  **Bloco de proveniência (decisão que É do dono)** — repasse SEMPRE neste formato, e instrua
  cada camada a repassá-lo verbatim ao descer (rótulo solto vira asserção de agente e um
  executor rigoroso o recusa):

  ```
  DECISAO-DO-DONO
  canal: AskUserQuestion | --obs | resposta direta no chat | retomada pós-pausa
  ts: <ISO da resposta>
  pergunta: <1 linha>
  resposta_verbatim: "<palavra por palavra>"
  ```

  O `ts` é MECÂNICO: `date -Iseconds` no ato, colado — nunca de cabeça (minuto redondo `:00`
  é red flag de placeholder). **A regra vale para TODO timestamp gravado em artefato por
  qualquer camada** (frontmatters de VERIFICATION/UAT etc.) — o `confere-etapa.sh` linta
  placeholders. **Alegação de consentimento exige ponteiro:** "aprovado pelo dono" só vale
  com ponteiro para um bloco DECISAO-DO-DONO existente (arquivo + `ts`); sem ponteiro, é
  relato e o item é NÃO-assinado — por quem escreve, revisa e verifica.
- **`blocked`** — pré-condição indisponível. Trate pela semântica do bloco da etapa; a
  descida para subagente **não afrouxa nenhum fail-closed** — o bloqueio sobe e é a camada 0
  quem para.

**Probe de aninhamento (S.H, cache mecânico).** Aninhamento (camada 1 spawnar camada 2) é
capability que o runtime liga/desliga entre releases — nenhuma conclusão é atemporal. O
`abre-rodada.sh` mantém o cache versão-condicionado (`~/.claude/.gad-aninhamento.json`):
`aninhamento: ok|falha` → obedeça; `probe_necessario` (versão do CC mudou) → rode o probe
mínimo (um `general-purpose` que responde se tem o tool `Agent`, ~2k tokens) e grave com
`abre-rodada.sh --registra-aninhamento ok|falha`. Probe `falha` → **rota inline** para as
etapas spawnadoras, com duas regras inegociáveis: (1) inline ⇒ **leia o `prompts/<etapa>.md`
antes de conduzir** (a regra "não leia antes de despachar" INVERTE — você assume o papel do
subagente e as disciplinas moram lá); (2) registro **versão-condicionado** no
`NN-DECISOES.md`/`.continue-here.md` ("na CC <versão-exata>…"), nunca atemporal — na retomada
ou bump de versão, o cache re-exige o probe.

**Retomada cross-sessão.** Continuar um subagente só funciona na MESMA sessão. Em sessão
nova, o estado está em disco: a camada 0 identifica a etapa pendente e redespacha; a retomada
fina é do prompt da etapa (o `intent.md` tem chegada própria; os que só hospedam um comando
GSD contam com a idempotência do próprio comando — um `needs_decision` desses não sobrevive à
sessão: o redespacho re-roda e a pergunta re-emerge, custo aceito).

</subroutine>

<subroutine name="I — triagem de decisão (antes de todo AskUserQuestion)">

## Sub-rotina I — triagem de decisão (antes de TODO `AskUserQuestion`)

Base empírica (inventário 20/07, 461 perguntas): com opção recomendada, o usuário a escolheu
em ~84–90% dos casos; o custo real eram perguntas penduradas fora do horário dele (16
perguntas = 47h paradas). Decisão do dono (20/07, sempre-ligado): a camada 0 decide sozinha o
que ele carimbaria — com registro e disclosure — e só o que é da alçada dele para o fluxo.

Antes de QUALQUER `AskUserQuestion` — de `needs_decision`, stop herdado ou stop próprio —
classifique:

**Gate duro — para e espera o usuário** quando QUALQUER um vale:
1. **Informação externa** — a resposta é fato que só ele tem (credencial, acesso, estado do
   mundo). Ele fornece o insumo, não carimba.
2. **Escopo/intenção** — requisito, critério de aceite, oráculo, SPEC/CONTEXT/ROADMAP (inclui
   a pausa da revisão de intenção). Auto-aprovar aqui é o carimbo invertido.
3. **Irreversível fora do trilho** — rotacionar/expor credencial, apagar dado, gastar
   dinheiro, produção. (O trilho sancionado — fase verde até o merge do PR pós-UAT-limpo,
   6.D — é o default e não pergunta.)
4. **Sem recomendada** — sem convicção real, a confissão de incerteza sobe em qualquer
   categoria.
5. **Fail-closed existentes** — ameaça aberta, balde 2 persistente, balde 3, gaps, `blocked`,
   gate de contexto, bloqueio_sem_revisor: a triagem não afrouxa nenhum.

**Auto-decisão — decide, registra e segue** quando NENHUM critério vale E há recomendada com
convicção E o erro é barato de desfazer. Desempate: a opção **mais rigorosa** (quando o
usuário diverge, é para endurecer). Mecânica:
1. Decida pela opção que você recomendaria (a `recomendacao` do subagente é insumo, não
   veredito; `reversivel: nao` joga pro gate duro).
2. Registre no `<phase_dir>/NN-DECISOES.md`: hora (`date "+%F %H:%M"`), etapa, pergunta em 1
   linha, opções, escolhida, porquê e **como desfazer**. Linha ao usuário:
   `🤖 decidi sozinho: <escolha> — registrado no NN-DECISOES.md` (auto-decisão silenciosa é
   bug).
3. Siga. Num `needs_decision`, continue o MESMO subagente com o rótulo honesto da Sub-H.

**Decisões de timing também são decisões** — adiar pergunta, segurar aviso até o resumo:
mesma mecânica, entrada no `NN-DECISOES.md` (a narração no chat se perde; o registro é o que
o resumo e a auditoria releem).

**Janela de silêncio (23h–07h):** o `pre-despacho.sh` já reporta a janela; um gate duro
dentro dela não pendura pergunta de madrugada — feche com **parada graciosa** (Sub-rotina D,
motivo `gate duro em janela de silêncio`), com a pergunta pendente (opções + recomendação) no
handoff e no resumo parcial; a retomada re-apresenta. Não se aplica à auto-decisão (que nunca
para) nem muda os fail-closed.

A transparência fecha o ciclo: o resumo executivo narra toda auto-decisão lendo o
`NN-DECISOES.md` — a supervisão que era síncrona vira revisão assíncrona com rota de desfazer.

</subroutine>

</subroutines>

---

<stages>

<stage id="0" name="Preparação">

## Etapa 0 — Preparação

**0.1 — Argumentos.** Número da fase (primeiro número) + flags: `--ui`, `--ai`, `--no-ship`,
`--vault <profile>`, `--obs "<texto>"` (sem aspas: tudo até a próxima flag). Sem número →
**pare** e peça. Guarde `--no-ship` (rota terminal da Etapa 6), `vault_profile` (desce no UAT)
e `obs_text` (nota a todo despacho da rodada — Sub-rotina H).

**0.2 — Abertura atômica.** Rode
`$HOME/.claude/skills/go-and-do/scripts/abre-rodada.sh N [flags]` e obedeça o JSON (espelho em
`.planning/.gad-last-abre-rodada.json`): portões de entrada, retrato da fase
(`phase_dir`/`padded_phase`/`has_plans`/`has_verification`), gate de contexto, decisões de
retomada (`etapa_1`/`etapa_2`), `vault_alerta`, `aninhamento`, `hook_instalado`, retrato da
TaskList, evento `run` + ponteiro da rodada. Exit ≠ 0 → **pare** com o motivo do script (exit
2 = portão/argumento · 3 = contexto no teto · 4 = fase não encontrada).

**0.3 — Obedecer o retrato.**
- `confere-etapa.sh 0` (self-check da abertura: ponteiro + evento `run` no disco).
- Espelhe a TaskList (Sub-rotina C).
- `vault_alerta` → pergunte ANTES de gastar a fase (fase com cara de UI autenticada sem
  `--vault`).
- `aninhamento: probe_necessario` → probe mínimo + `--registra-aninhamento` (Sub-rotina H).
- `hook_instalado: false` → degradação declarada (uma linha; asserts de despacho viram
  informativos).
- `--ui`/UI-SPEC → leia `workflow-ui.md`; `--ai`/AI-SPEC → `workflow-ai.md` (única leitura da
  rodada).

**0.4 — Banner.** Moldura ASCII dupla num bloco `text`:

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

`Rota` = `--no-ship` → "para no seu UAT, sem shipar"; padrão → "vai até abrir o PR". `Vault` e
`Obs` só entram se existirem. Abaixo da caixa, uma linha solta: o usuário pode sair de perto.

</stage>

<stage id="1" name="Intenção — spec + discuss + revisão adversarial">

## Etapa 1 — Intenção (spec + discuss + revisão adversarial)

> Troca o carimbo humano por um **cético de máquina**: SPEC e CONTEXT saem em `--auto` (cada
> escolha logada) e a intenção passa por revisão adversarial cross-AI — dois revisores
> externos tentam derrubar as decisões lendo o código de verdade, e um verificador confere
> cada achado antes de aceitar. O usuário só é chamado quando um achado mexe no que é da
> alçada dele. Autocontida de propósito (candidata a capability `discuss:post` no futuro).

**1.1 — Retomada.** Obedeça `etapa_1` do abre-rodada: `pular` → Etapa 1.5 ·
`continuar_pergunta` → re-apresente a pergunta pendente gravada no artefato e despache com a
resposta · `despachar` → 1.2. A retomada fina por arquivo é do subagente
(`setup-intencao.sh`).

**1.2 — Despacho.** `pre-despacho.sh 1` → despache o agente **`gad-intent`** (def própria:
Opus 5 medium — coordenador roteia; o julgamento pesado mora nos filhos e nos revisores) com
`prompts/intent.md`, levando `N`, `NN`, `phase_dir`, `project_root` absolutos e, numa
continuação, a resposta verbatim. Dentro dele: filho `gad-spec` (SPEC `--auto`) → filho
`gad-discuss` (CONTEXT `--auto`, auto_advance neutralizado) → revisão adversarial (Codex +
agy ↔ `gad-verificador`; loop por `decide-ciclo.sh`, teto 4; fail-closed no piso "≥1
revisor").

**1.3 — Roteamento do retorno.**
- **`done`** → gate de rota 9b (`confere-rotas.sh`; exit 1 devolve ao MESMO subagente) +
  `conta-turnos.py` (estouro = evento `incidente`) + `confere-etapa.sh 1` (cancela mecânica —
  SPEC/CONTEXT/review fechado/chain zerada/limpeza `.intent/` — e o `end` medido; exit 1
  devolve ao MESMO subagente). Guarde do retorno: `transparencia`
  (insumo da 6.2), `sinos` (pro banner) e anuncie `pausas_de_negocio` numa linha. Sinos com
  **revisão pulada** (`intent_review: skipped`) → evento `skip` + linha ao usuário + item
  obrigatório nos `itens_nao_rodados` (transparência de topo, não rodapé). Siga.
- **`needs_decision`** — achado que mexe em requisito/critério/oráculo, ou impasse (gate duro
  por definição — critério 2 da Sub-rotina I; janela de silêncio → parada graciosa) →
  `AskUserQuestion` (recomendação primeiro) e **continue o MESMO subagente** com as respostas
  verbatim; roteie o novo retorno por esta lista.
- **`blocked`** — os DOIS revisores instalados mas falhos sem nenhum ciclo completo
  (fail-closed, decisão de 02/07: sem segunda opinião a intenção não segue; UM falho desce
  degradado com sino; NENHUM instalado vira `skipped` no pré-check) → **Sub-rotina D**. O
  `intent_review: blocked` já está no disco (a próxima invocação re-tenta). Handoff: "🔔
  revisão de intenção bloqueada — autentique um dos revisores e re-rode `/go-and-do N`."

</stage>

<stage id="1.5" name="Contratos de design">

## Etapa 1.5 — Contratos de design

> Antes do planejamento porque o `gsd-plan-phase` consome UI-SPEC/AI-SPEC como design travado
> e os gates 4.2/4.3 auditam contra eles.

**1.5.1 — Setup mecânico.** `setup-contratos.sh <phase_dir> <NN> [--ui] [--ai]`: ambos
`pular`/`sem-flag` → pule a etapa inteira. `config_corrigida` não-vazio → transparência (flag
do dono venceu config esquecida — flip declarado).

**1.5.2 — Despacho.** `pre-despacho.sh 1.5` → despache o agente **`gad-contratos`** (Opus 5
medium, com Agent e Skill) com `prompts/contratos.md` + flags + JSON do setup. Ele hospeda
`gsd-ui-phase` e `gsd-ai-integration-phase` INLINE (ordem UI → IA).

**1.5.3 — Roteamento.** `done` → `confere-etapa.sh 1.5` (asserts por flag; exit 1 devolve);
sinos → transparência. `needs_decision` (stops herdados — detalhe em
`workflow-ui.md`/`workflow-ai.md`) → triagem I; resposta continua o MESMO subagente.
`blocked` → Sub-rotina D.

</stage>

<stage id="2" name="Planejamento">

## Etapa 2 — Planejamento

**2.1 — Retomada.** Obedeça `etapa_2` do abre-rodada: `pular` → Etapa 2.5; `despachar` → 2.2.

**2.2 — Cancela de saída.** `pre-despacho.sh 2`.

**2.3 — Planejar (via subagente).** Despache o agente **`gad-plan`** (Opus 5 medium — os
julgamentos de entrada têm alta alavancagem) com `prompts/plan.md` (`N`, `NN`, `phase_dir`,
`project_root`, args-base `N --tdd`): ele julga pesquisa (2.D, viés pesquisar) · mapper
(2.E, só fase que cria arquivo novo) · granularidade (2.G), invoca o `gsd-plan-phase` e
persiste a trilha do checker (`.plan-checker/iter-N.yaml`, 2.B). Roteamento:
`done · planejado` → 2.4 (anote pesquisa/mapper/granularidade/sinos p/ transparência) ·
`done · sem_plano` → evento `stop`, **pare** · `needs_decision` → pergunta + continuação ·
`blocked` → `stop`, **pare**.

**2.4 — Cancela de chegada.** `confere-etapa.sh 2` — asserts + extração `nao_autonomos` +
sino do mapper. Exit 1 → devolva ao MESMO subagente a lista do que falta, não importa o que
ele alegou.

**2.4b — Fecho: `autonomous: false` resolvido AQUI (2.H).** Para cada plano em
`nao_autonomos`, classifique o checkpoint:
- **(a) decisão respondível por texto** → pergunte AGORA (o dono está presente no fim do
  planejamento); a resposta vira bloco `DECISAO-DO-DONO` anexado ao despacho da execução;
  flipe o plano para `autonomous: true`.
- **(b) ação humana antecipável** (chave, migration, login) → escreva
  `<phase_dir>/NN-ACAO-HUMANA.md` com o passo a passo DETALHADO; o dono executa e confirma →
  flipe o plano e **apague o arquivo** (o fato vira 1 linha no `NN-DECISOES.md`).
- **(c) verificação de runtime** (`human-verify`) → deferida ao UAT (redundante com ele):
  flipe e o item entra na pauta da Etapa 5.
Efeito: a rota inline da Etapa 3 vira exceção raríssima.

</stage>

<stage id="3" name="Construção">

## Etapa 3 — Construção

**3.1 — Retomada.** `has_verification` → pule a Etapa 3 inteira. (A pré-detecção de ações
humanas MORREU aqui — o fecho 2.4b já resolveu; os planos chegam flipados.)

**2.5 — Convergência do plano (via subagente).**
- `pre-despacho.sh 2.5` e obedeça `despacho`: `pular` (marcador presente) → 3.3 ·
  `skip_config` → degradação declarada (itens_nao_rodados) e siga · `bloqueio_sem_revisor`
  (exit 4 — PC-6: NENHUM revisor externo instalado, a fase NÃO continua) → ⏸️ repasse a
  `pergunta_ao_dono` e pare · `ok` → despache (um ausente = segue com o outro; o campo
  `revisores` diz quais).
- Despache pela Sub-rotina H com `prompts/convergence.md`: o subagente monta o briefing
  direcionado (trilha do plan-checker como "não re-litigue" + ênfase A-domínio/B-mundo),
  hospeda `gsd-plan-review-convergence --codex --agy --max-cycles 3` (lanes por
  `roda-codex.sh`/`roda-agy.sh` — frescor, evidência de modelo e canário em exit code),
  registra ciclos (`registra-ciclo.sh`) e grava o marcador (`grava-convergence.sh`).
- Roteamento: `done · convergiu` → `confere-etapa.sh 2.5`; anote `revisores_efetivos`/`sinos`
  e siga · `done · escalou` → `stop`, **pare** com o impasse mastigado · `needs_decision` →
  pergunta + continuação · `blocked` → `stop`, **pare**.

**3.3 — Execução.** `pre-despacho.sh 3`. Rota padrão = subagente (re-confira
`nao_autonomos`):
- **Todos autônomos (caso normal) → subagente** com `prompts/execute.md` (args
  `N --auto --no-transition`): hospeda o `gsd-execute-phase` — ondas de executor (camada 2) →
  código + commits + SUMMARY → verificação. Paradas herdadas viram `needs_decision`; ação
  humana → `done · incompleto`. Roteamento: `done` (qualquer veredito) → siga pra 3.4 (a
  encruzilhada apura pelo DISCO, não pelo retorno) · `needs_decision` → pergunta +
  continuação · `blocked` → `stop`, pare.
- **Sobrou `autonomous: false` → inline** (`Skill gsd-execute-phase --auto --no-transition`
  na camada 0 — a interação humana é nativa aqui). `--auto` auto-aprova checkpoints de
  verificação e pega a 1ª opção nos de decisão; `--no-transition` impede o auto-avanço. ✋
  `--auto` NÃO silencia regressão/schema/conflito/`human-action` (ver Paradas herdadas); se o
  dono defere uma ação, a 3.4 fecha pela Sub-rotina D na volta.

> ⚖️ Trade-off do `--auto` (consciente): decisões de arquitetura saem no automático (1ª
> opção). Aceitável porque a skill manda toda "lógica" pro UAT e trata `human_needed`.
> 🧪 Economia de testes (princípio agnóstico de stack): suíte completa é gate, não feedback —
> no máximo 1× por wave; o feedback do TDD são os testes do escopo tocado. Timeout de suíte
> dimensionado pela duração medida (folga ≥2×). Parâmetros por projeto no CLAUDE.md do
> projeto.

**3.4 — Encruzilhada.** Primeiro a completude: `gsd_run query phase-plan-index N` (lib da
Sub-E) — sobrou plano sem `SUMMARY.md` → **execução incompleta — bloqueada** → Sub-rotina D
com a ação exata (não trate como `human_needed`). Senão, o status do VERIFICATION.md:
- **ausente** (verificação nunca rodou) → re-execute pela regra da 3.3 (idempotência pula os
  prontos). Persistiu → D.
- `passed` → Etapa 4 · `human_needed` → anota (vira PENDING do UAT) e segue ·
  `gaps_found` → 3.5.

**3.5 — Fechamento de gaps (1× só).** Replaneja (`prompts/plan.md`, args `N --gaps`) →
**1b:** ancore a re-convergência: acrescente ao frontmatter do `NN-CONVERGENCE.md` a linha
`gap_replan: "<data> — N planos gap_closure; commits <shas>"` e commite (sem isso a 2ª
revisão só existe no git) → re-executa (regra da 3.3) → re-verifica. `passed`/`human_needed`
→ Etapa 4; ainda `gaps_found` → **Sub-rotina D** (`gaps persistentes`). Só 1 tentativa — o
resto merece decisão humana.

</stage>

<stage id="4" name="Gates de qualidade">

## Etapa 4 — Gates de qualidade

> Camada 0 100% mecanizada (4.A): para CADA gate, `pre-despacho.sh 4-<gate>` resolve
> flag/config/retomada num exit code e `confere-etapa.sh 4-<gate>` asserta o artefato E
> extrai o veredito canônico — você NUNCA relê relatório de gate; roteia pelo dado extraído.
> O que fica de julgamento: mastigação de `needs_decision` e a prosa do 🔔 no fecho.

### 4.1 — Code review (via subagente)
- `pre-despacho.sh 4-code-review` → `ok`? Despache pela Sub-rotina H com
  `prompts/code-review.md` (`iteracao: 1`): hospeda `gsd-code-review N --fix --auto` COM a
  lane Codex paralela (4.D: parecer bruto → funil `gad-verificador` → merge com
  `fonte: codex` — codex ausente não bloqueia, o reviewer interno é o piso). Iterações 2+ e o
  gate 4.1b despacham com `iteracao: 2+` — o subagente estreita via `calcula-files.sh` (diff
  desde o último review + dependentes reversos de 1 salto, 4.C).
- Ao voltar: `confere-etapa.sh 4-code-review` (extrai `status`/`critical`/`warning`/`total`).
  Sempre segue; `critical` restante → 🔔 forte. Guarde `uat_humano` (insumo da 5.3).
  `needs_decision` → pergunta + continuação. `blocked` → `stop`, pare.

### 4.2 — UI review · só com `--ui` → conduza pelo `workflow-ui.md`.

### 4.3 — Eval review · só com `--ai` → conduza pelo `workflow-ai.md`.

### 4.4 — Secure phase (via subagente)
- `pre-despacho.sh 4-secure` → `ok`? Despache com `prompts/secure.md`. Decisão de ameaça sobe
  (`needs_decision`) — **mastigação antecipada (4.E):** prepare a decisão mastigada (ameaça,
  severidade, opções com recomendação primeiro) ao recebê-la — o custo real do gate era a
  espera da pergunta crua.
- Ao voltar: `confere-etapa.sh 4-secure` — exit ≠ 0 (threats_open > 0 ou aceite sem dono) é o
  ÚNICO bloqueio da etapa: ⏸️ pare. Secure tocou src/ DEPOIS do review → gate 4.1b:
  `calcula-files.sh --tocados "<arquivos>"` → re-despacho da 4.1 estreitado.

### 4.5 — Validate phase (via subagente)
- `pre-despacho.sh 4-validate` → `ok`? Despache com `prompts/validate.md`. ⏸️ Gaps →
  `needs_decision` (Fix all recomendado). Ao voltar: `confere-etapa.sh 4-validate`. Segue.

</stage>

<stage id="5" name="UAT interativo automatizado">

## Etapa 5 — UAT interativo automatizado

> UAT próprio, não `verify-work` cru: reusamos a LÓGICA de derivação (5.3) e dirigimos o
> browser por conta própria (5.4, subagente + `uat-playbook.md`). O UAT **interage de
> verdade** e **prova objetivamente** (status HTTP + console + estado persistido).

**Os 4 baldes** (a craft completa está no `uat-playbook.md`; aqui você só roteia):
- **1 · pass** — prova objetiva fechou.
- **2 · issue** — falhou objetivamente → ciclo de conserto (5.5).
- **3 · não-pude-verificar** — login sem vault, 2FA, captcha → `[pending]`/`blocked`;
  **bloqueia o ship** (hand-back).
- **4 · assumed** — só sobra juízo subjetivo → shipa **com aviso** no resumo.

**5.1 — Retomada (por ESTADO do `NN-UAT.md`).** Ausente → 5.3 · sem `pre_uat: executed` →
5.4 (o subagente é idempotente por cenário) · `executed` + `issue` sem
`pre_uat_fix_cycle: done` → 5.5 · com o marcador → **Sub-rotina D** (nunca um 2º ciclo) ·
`executed` sem `issue` em aberto → Etapa 6.

**5.3 — Geração do `NN-UAT.md` (via SUBAGENTE).** `pre-despacho.sh 5`. Despache um `Agent`
(`model: sonnet`, síncrono) para reusar a derivação do verify-work:
- (a0) **classificador mecânico primeiro (5.D):** `gsd_run query uat.classify-coverage
  --summary` — deliverable coberto por teste automatizado passando entra `pass, source:
  automated` sem virar cenário de browser (fail-safe: never drop a deliverable);
- (a) find_summaries → (b) extract_tests — comportamentos user-observáveis; cenários visuais
  do UI-SPEC (ou SUMMARY sem `--ui`); **cold-start smoke** só quando um SUMMARY tocou
  server/app/db/migrations/seed/docker, limitado a boot + health ("clear ephemeral state" é
  destrutivo → `[pending]` pro humano);
- (c) create_uat_file — template `$HOME/.claude/gsd-core/templates/UAT.md`,
  `status: testing`, tudo `[pending]`, frontmatter `pre_uat: generated`;
- (d) **insumos dos revisores no despacho:** `uat_humano` da 4.1 + `human_needed` da 3.4 — é
  aqui que o "vira UAT" prometido se materializa.

**5.4 — Execução do UAT (via SUBAGENTE — SEMPRE, com ou sem GUI).**
> O subagente — não você — dirige o browser (trabalho verboso; janela própria). Fase sem GUI
> NÃO é motivo para inline: o playbook tem `<non_gui_surfaces>` (CLI/API/lib — prova por
> saída objetiva) e `<push_on_it>` (probes 🔍), que só operam se o subagente for despachado
> com ele. Prova ao vivo atrás de segredos → a camada 0 PREPARA a via sancionada (wrapper) e
> o subagente a roda.

1. **O server é da janela do UAT (5.A):** o subagente sobe/derruba via `dev-server.sh`
   (`workflow-dev-server.md`). Fase sem server: declare no prompt ("use
   `<non_gui_surfaces>`").
2. **Despacho:** `Agent` `model: sonnet`, `general-purpose`, síncrono. Prompt mínimo: "Leia
   `$HOME/.claude/skills/go-and-do/uat-playbook.md` e conduza o UAT da fase NN à risca. O
   `NN-UAT.md` está em `<uat_path>`. Sua janela é dona do dev server. Use a sessão
   `uat-fase-NN`. [Sem GUI: cenários são api/logic/cli — use `<non_gui_surfaces>`.] [Wrapper:
   rode a prova via `<wrapper absoluto>`; não leia nem ecoe segredos.] [Vault: profile
   `<profile>`.] Classifique nos 4 baldes, aplique `<push_on_it>` no balde 1, escreva
   results/Gaps/evidências no `NN-UAT.md`. Devolva só o qualitativo do `<return_contract>` —
   números são contados por script."
3. **Cancela:** `confere-etapa.sh 5` — reconcilia baldes/probes/evidência do disco, linta o
   gap-YAML, roda o predicado nativo `uat-passed`, varre SEGREDOS (padrão-gitleaks, NUNCA PII
   genérica) e, no pass, promove `pre_uat: executed` (escritor único — 5.C/5.E). Exit 1 →
   devolva ao MESMO subagente. **Não** ingira o `NN-UAT.md`.

> Regra cardeal do playbook: **nunca `pass` no ambíguo** — incerteza → balde 3. (O antigo
> subagente de conversão de balde 3 morreu, 5.B: o balde 3 real é parede de login/2FA.)

**5.5 — Ciclo de conserto (1× só) quando há balde 2.**
1. `pre-despacho.sh 5` (checkpoint do ciclo).
2. Replaneja (`prompts/plan.md`, args `N --gaps` — lê os gaps do `NN-UAT.md`).
3. Re-executa (regra da 3.3, args `... --gaps-only` — escopo estrito).
4. **Re-review** nos arquivos do fix: despacho da 4.1 com `iteracao: 2+` — sem a checagem de
   retomada (o `NN-REVIEW.md` existente é esperado; pular furaria a garantia "auditado antes
   do ship" pro código novo).
5. **Re-UAT só nos cenários `issue`** — mesma janela-dona-do-server, que sobe o server NOVO
   (código pós-fix; superfície buildada → re-rodar build antes).
6. `confere-etapa.sh 5 --fix-cycle` valida e carimba `pre_uat_fix_cycle: done` (escritor
   único — a 5.1 usa isso pra nunca disparar um 2º ciclo).
- Fechou → Etapa 6. Persistiu → **Sub-rotina D** (`bug de UAT persistente`).

</stage>

<stage id="6" name="Encerramento + ship">

## Etapa 6 — Encerramento + ship

Duas rotas terminais: **ship** (caminho feliz) e **hand-back** (devolve sem shipar).

**6.1 — Roteia o desfecho (mecânico).** `pre-despacho.sh 6` e obedeça `rota`: `pausa`
(sobrou balde 2) → Sub-rotina D · `handback` (balde 3 ou `--no-ship`) → 6.4-HB · `ship` →
6.4-SHIP. O JSON traz `git_remote` (gatilho da rota B), `uat_passed_raw` (o predicado nativo
MEDIDO — cola no briefing do ship) e `transparencia` (5 listas extraídas). Você não decide
rota; lê o veredito.

**6.2 — Monta o "🔔 O que precisa de você agora" + transparência.** Junte o que merece
atenção mesmo tendo seguido: Criticals do review (+ `uat_humano`), pilares de UI 1–2 /
Registry Safety, eval abaixo de PRODUCTION READY, validação partial, `ciclo_final_nao_rodou`
da intenção. As listas de transparência já vieram EXTRAÍDAS na 6.1 (balde 4 · balde 3 ·
`transparencia:` do INTENT-REVIEW · skips do run-log · `riscos_aceitos` do secure — aceite de
risco é assinatura do dono: ele REVÊ no resumo, não descobre no código). Seu trabalho é só
REDIGIR.

**6.3 — Resumo executivo (modo final).** **Sub-rotina F** com `modo: final`, o desfecho e as
listas da 6.2. A F escreve o bloco de transparência no TOPO. Idempotente. Commit conforme a
F.
> Ordem: o resumo é commitado ANTES do close — entra na árvore que o ship empacota.

**6.3b — Árvore limpa pro ship.** `commita-artefatos.sh <phase_dir> <NN> uat` (escritor
único; vale para ambas as rotas). **Evidência movida = `NN-UAT.md` emendado no mesmo passo:**
evidência estacionada fora do git (ex.: PDF com segredo) → o campo `evidencia:` do cenário
aponta o paradeiro REAL com o motivo — path fantasma é defeito de fecho (a prova deixa de ser
auditável).

**6.4-SHIP — Ship.**
- **Rota B (`git_remote: false` — 6.E, julgamento seu):** o projeto shipa por caminho próprio
  por design. Descubra o ship alternativo nos artefatos do PRÓPRIO projeto (skills do
  projeto, CLAUDE.md) e **execute com autorização prévia** (decisão do dono 09/08 — sem
  perguntar nem hand-back), registrando escolha e porquê no `NN-DECISOES.md`. Não achou
  caminho → `blocked` honesto. NENHUMA config canônica nova — a fonte é o projeto, o juiz é
  você.
- **Rota A (com remote) — via subagente** com `prompts/close.md`: hospeda a skill
  `close-phase N` (learnings → promoção com evidência "UAT automatizado" → commit docs → PR →
  revisão auto-"Skip" carimbada → merge direto, 6.D). Freio herdado: só promove/shipa com o
  predicado nativo `phase uat-passed` limpo — ⚠️ **`assumed` (balde 4) REPROVA nesse
  predicado** e o freio segura-e-pergunta (por design). **Não afirme o estado do gate no
  briefing** — cole o `uat_passed_raw` MEDIDO da 6.1 (estado de gate se mede, não se
  presume).
- Roteamento: `done · shipado` → guarde PR (#N e URL) e siga pra 6.4c · `done ·
  uat_reprovado` → o freio agiu (investigue `motivo_reprovacao` pelo disco) → **Sub-rotina
  D** · `needs_decision` (uat-passed bloqueia-e-pergunta) → pergunta + continuação ·
  `blocked` (ambiente: sem origin, gh não autenticado, branch errado) → **respeite**: evento
  `stop` (`pausa: ship bloqueado — <motivo>`), anote no banner e pare (re-rodar retoma no
  ship).

**6.4c — Emenda do desfecho no resumo.** Substitua o placeholder `## Desfecho do ship` do
`NN-RESUMO-EXECUTIVO.md` por 2–3 linhas FACTUAIS (Edit direto): `shipado` → PR real + o
próximo passo verdadeiro DESTE fluxo (auto-merge → diga que mergeou; nunca prometa revisão
que o fluxo não tem) · `blocked` → o motivo + o caminho real de publicação (nenhum PR existe
— não sugira que existe). **Reconcilie o corpo com o estado pós-close** (promoção
`human_needed` → `passed`: emende a menção antiga ou anexe nota — sem isso o documento nasce
contraditório). A emenda obedece à regra do estado do mundo (`prompts/resumo.md`): consulta
real, fonte+data, ou omita. Commite (best-effort). Idempotente: seção já preenchida → não
reescreva. A emenda relata o RETORNO do ship, nunca uma expectativa.

**6.4-HB — Hand-back (não shipa).** Banner na moldura padrão — título `GO-AND-DO · Fase NN —
pronta para o seu UAT`, campos `Balde 3` (quantos) e `Resumo` (caminho) — e as pendências:
1. `/gsd-verify-work N` — retoma exatamente nos cenários balde 3.
2. `/gsd-add-tests N` — suíte ampla.
3. `/close-phase N` depois do UAT limpo *(ou re-rode `/go-and-do N` sem `--no-ship`)*.

**6.5 — Self-check + banner final.** `confere-etapa.sh 6` — PLAN×SUMMARY (plano sem SUMMARY
= falha) + anti-placeholder de timestamps; 🔔 em divergência (ts divergente → corrija para o
ts real do git e registre em `incidentes:`). Reconcilie a TaskList (anti-órfã S.C). Depois:
- **Ship:** moldura com título `— shipada`, campos `PR` e `Resumo`; abaixo: URL do PR, bloco
  de transparência e add-tests como passo **pós-PR**. Encerre.
- **Hand-back:** a moldura da 6.4-HB (não duplique a caixa) + itens balde 3 + pendências.
Em ambas: evento `stop` (etapa `ship`/`handback`), **remova o ponteiro**
`.planning/.gad-rodada-ativa.json` (PC-3) e `commita-artefatos.sh <phase_dir> <NN> runlog`
(append não-commitado do run-log já se perdeu em sync de branch). Idempotente: re-rodar
depois de shipado cai direto aqui e reimprime.

**6.6 — Guarda.** Se o self-check revelar plano sem `SUMMARY.md` (ação humana que escapou),
**não** shipe: volte pra **Sub-rotina D** (a D gera um `parcial` que sobrescreve o `final` —
o disco fica correto).

</stage>

</stages>

---

<note title="sem freio para o limite de 5h">

## Nota — sem freio para o limite de 5h

O uso da sessão de 5h não é legível por uma skill (não está no transcript). Não há gate de
5h — confia na retomabilidade: estourou, re-rode `/go-and-do N` após o reset e a skill
continua de onde parou. Pausa manual via `/gsd-pause-work` a qualquer momento.

</note>
