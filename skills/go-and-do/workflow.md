<!-- ============================================================ -->
<!-- workflow.md — o miolo executável da skill go-and-do.        -->
<!-- Embutido no SKILL.md via @ (carregado na ativação).         -->
<!-- Instruções imperativas para o orquestrador. Não é doc.      -->
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

- Invoke GSD commands via the `Skill` tool (each `/gsd-*` is a skill) — inline in layer 0
  only where the stage block says so; most stages dispatch a layer-1 host subagent that
  invokes the command in its own window (Sub-rotina H). Either way, wait for one step to
  finish before starting the next — you control the chaining.
- Reuse, don't reinvent — with two declared exceptions, both in Etapa 5. (1) The UAT reuses the
  verify-work *scenario-derivation* logic (find_summaries → extract_tests → create_uat_file) inline,
  via a subagent, because verify-work has no "generate the UAT.md and stop" mode — invoking it would
  trigger its interactive loop, auto-fix cascade and auto-transition. (2) The UAT *drives the browser*
  via a subagent following `uat-playbook.md`, because no native GSD command does interactive
  acceptance testing. Both are deliberate; if a future maintainer sees a violation, the right fix is
  upstream (a `--generate-only` mode in verify-work; a native interactive-UAT command), not removing
  the reuse. The close itself is NOT an exception — it reuses the native `/close-phase` skill.
  A third declared deviation lives in Etapa 0-B: it invokes the native spec/discuss skills (pure
  reuse), but suppresses the discuss `auto_advance` side-effect and resets the chain flag it
  persists (executed inside the intent subagent — see `prompts/intent.md`) — this skill owns the
  chaining; the right upstream fix is a `--no-advance` flag in discuss-phase. Dívida registrada.
- Don't read artifact bodies into your own window — layer 0 decides by frontmatter, by the
  SDK's JSON status fields (`init.phase-op`, `phase-plan-index`) and by file existence, never
  by ingesting documents; reading them bloats context (the very thing the token gate
  protects). Whoever genuinely needs an artifact's content — verifying the intent (Etapa 0-B),
  reviewing the plan/code, deriving the UAT, **driving the browser**, narrating the summary —
  is the layer-1 subagent of that step (Sub-rotina H), which reads/writes on disk and returns
  only a compact status. (The old declared exception for `NN-SPEC.md`/`NN-CONTEXT.md` no
  longer exists: the intent review reads them inside its own subagent.) In particular, the
  UAT subagent (Etapa 5.4) drives the browser in its own window and returns only per-basket
  counts; the orchestrator never sees a DOM snapshot.
- Run the context gate before every main command (see "Sub-rotina A"). At the absolute
  token ceiling (`status=stop`) → checkpoint + pause + stop. This gate is not optional.
- Honor every stop point — never skip one to keep going. The hard stops are: missing
  entry prerequisites (0.3), incomplete execution blocked on your action (3.4 → Sub-rotina D),
  persistent verification gaps after one retry (3.5), open security threats (4.4), a UAT bug
  that survives one fix cycle (5.5 → Sub-rotina D), and the **anti-false-ship floor**: ship only
  when the UAT is objectively clean (no basket 2, no basket 3) — a basket-3 couldn't-verify scenario
  blocks the ship and hands back to `/gsd-verify-work` (Etapa 6.4-HB). When you stop, say why in the
  printed handoff line.
- Everything is resumable. Re-running `/go-and-do N` must never redo finished work.
  Check state first — Etapas 0/2/3 via `init.phase-op` (`has_plans`/`has_verification`); Etapas
  0-B, 1, 3.2, 4 and 5 by file existence (`NN-SPEC.md`/`NN-CONTEXT.md`/`NN-INTENT-REVIEW.md`;
  `NN-UI-SPEC.md`/`NN-AI-SPEC.md`; `NN-CONVERGENCE.md`; the `NN-*REVIEW`/`NN-SECURITY`/
  `NN-VALIDATION` artifacts; `NN-UAT.md`) — and skip what is already done.
- Keep a live task list (TaskList) that mirrors disk state. Build it in Etapa 0 and, on
  resume, make it faithful to what is already done and to the step in flight (Sub-rotina C).
  Only the orchestrator manages it.
- Log run telemetry at the moments defined in Sub-rotina G (`run`/`checkpoint`/`end`/`stop`,
  plus `skip` when a step is turned off by a config gate or an unavailable tool) — it is cheap,
  it never blocks (the script always exits 0), and it is the data behind every cost decision
  this skill has made with real numbers. Instrument, not gate.
- A step that does not run is never silent: one line to the user, a `skip` event, and an entry
  in the resumo's transparency block. Never mutate project config to make a step not run —
  config outlives the run.
- Paths: the skill lives at `$HOME/.claude/skills/go-and-do/`. The phase directory
  comes from `init.phase-op` (`phase_dir`); the padded phase number (`padded_phase`,
  e.g. `03`) is the `NN` prefix of every artifact.
</operating_rules>

---

<master_checklist>

## Roteiro-mestre (todas as ações, na ordem)

Legenda: 🎌 só com a flag · ⏭️ retomada (pula se já feito) · ⏸️ pode parar · 🔒 gate de contexto antes

**Etapa 0 — Preparação**
1. Lê argumentos (fase + `--ui`/`--ai`/`--no-ship`/`--vault`/`--obs`). Sem número → ⏸️ para e pede.
2. `gsd_run query init.phase-op N` (shim, Sub-rotina E) → retrato da fase.
3. ⏸️ Portões de entrada (projeto GSD? fase no ROADMAP?). Falhou → para. (CONTEXT.md faltando não é mais portão — a Etapa 0-B gera.)
4. Decide de onde começar (retomada por estado no disco), registra o evento `run` na telemetria (Sub-rotina G) e monta a lista de tarefas espelhando o disco (Sub-rotina C).
5. Banner e libera.

**Etapa 0-B — Intenção: spec + discuss + revisão adversarial** *(⏭️ fase já planejada → pula inteira · retomada fina por arquivo)*
6. ⏭️ `has_plans` (ou `has_verification`) → pula pra Etapa 1 (a intenção já virou plano).
7. 🔒 ⏭️ Despacha o **subagente de intenção** (Sub-rotina H + `prompts/intent.md`) — um único despacho cobre os itens 7–9; a retomada fina por arquivo é do subagente. Dentro dele: SPEC (sem `NN-SPEC.md`): `gsd-spec-phase N --auto` (auto-decide e loga `[auto]`; termina no SPEC, sem auto-advance).
8. ↳ *(no mesmo subagente)* CONTEXT (sem `NN-CONTEXT.md`): `gsd-discuss-phase N --auto`, **sem executar o `auto_advance`** dele (o encadeamento é desta skill) e zerando `workflow._auto_chain_active` na volta.
9. ↳ *(no mesmo subagente)* Revisão adversarial de intenção (sem `NN-INTENT-REVIEW.md` `done`): Codex + agy criticam ↔ Claude verifica (achados fundidos, dedup por `fontes`), loop ≤ 3 ciclos. Factual → corrige no lugar · requisito/critério/oráculo → `needs_decision` sobe → ⏸️ a pergunta chega a você e a resposta continua o MESMO subagente (0B.3) · tradeoff → adota + transparência. Escreve `NN-INTENT-REVIEW.md`. UM revisor indisponível/falhou → segue com o outro, sino declarado; os DOIS instalados-mas-falhos → `blocked` sobe → ⏸️ **para** (grava `intent_review: blocked`; a retomada re-tenta); NENHUM instalado (pré-check) → revisão **pulada** com sino gritante (`intent_review: skipped`) e a fase segue — ausência de ferramenta degrada declarado; só falha de runtime bloqueia.

**Etapa 1 — Contratos de design** *(🎌 só com a flag · retomada por existência de arquivo)*
10. ⏭️ Sem `--ui` e sem `--ai` → pula a Etapa 1 inteira. Com a flag e o `NN-*-SPEC.md` já existe → pula o sub-passo.
11. 🔒 🎌`--ui` Contrato de UI: `Skill gsd-ui-phase` → `N`. Herdadas: UI-SPEC BLOCKED; revision stall (máx 2).
12. 🔒 🎌`--ai` Contrato de IA: `Skill gsd-ai-integration-phase` → `N`. Herdadas: entrevista do framework-selector; validation fail. Ordem com ambos: UI → IA. Config off → degrada e segue.

**Etapa 2 — Planejamento**
13. ⏭️ `has_plans` → pula pra Etapa 3.
14. 🔒 Planejamento via **subagente** (Sub-rotina H + `prompts/plan.md`, hospedando `gsd-plan-phase N --tdd --research`).
15. ⏸️ Confirma que o plano nasceu (camada 0, pelo shim); senão para.

**Etapa 3 — Construção**
16. ⏭️ `has_verification` → pula a Etapa 3 inteira.
17. Pré-detecção: `phase-plan-index N` → tem plano não-autônomo? Avisa que pode exigir sua ação.
18. 🔒 ⏭️ Convergência via **subagente** (com `NN-CONVERGENCE.md` `done` → pula; Sub-rotina H + `prompts/convergence.md`, hospedando `gsd-plan-review-convergence --codex --agy --max-cycles 4`). Config off (checada na camada 0, antes do despacho) → degrada declarado (`skip`) e segue. Não convergiu (`escalou`) → ⏸️ para.
18b. **Pré-flight de paralelismo** (só quando `use_worktrees: true` no `.planning/config.json` e a fase tem onda com ≥2 planos): ANTES do despacho da execução, cheque se o worktree degradaria — `gsd_run worktree base-check` se existir; senão compare `git rev-parse HEAD` × `git rev-parse origin/HEAD`. (a) Degradaria por **base mismatch** (HEAD ≠ origin/HEAD): esse é o estado NORMAL de uma fase — a skill commita dezenas de vezes e só empurra no ship — então aplique você mesma o antídoto: `"worktree": {"baseRef": "head"}` no `.claude/settings.local.json` do projeto, re-cheque, e registre como auto-decisão no `NN-DECISOES.md` (conduta de pipeline, 1 linha, reversível). (b) Degradaria por **qualquer outra causa** (env ausente, fixture gitignored, causa nova): **investigue a solução** (o que falta, o que copiar/configurar, custo e reversibilidade) e ⏸️ suba **AskUserQuestion** com o diagnóstico + as opções (aplicar o fix investigado / aceitar serial nesta fase / outra rota) — decisão do dono, sempre; a degradação nunca vira fato consumado, nem mesmo declarado. O porquê: 3 fases de projetos diferentes serializaram pelo mesmo padrão (F16-ox por env, F19-ox e F2 rl-representation por base mismatch — nesta última o fix existia desde a F19-ox e nunca fora replicado ao projeto; 16 planos rodaram seriais com disclosure e sem antídoto).
19. 🔒 Execução: tudo autônomo → via **subagente** (Sub-rotina H + `prompts/execute.md`); há plano `autonomous: false` pendente → **inline** (`Skill gsd-execute-phase --auto --no-transition` — a interação humana é nativa na camada 0).
20. Checa completude: sobrou plano sem SUMMARY (ação humana travou ondas) → ⏸️ Sub-rotina D (pause-work). Senão lê o status: passed → segue · human_needed → anota (vira insumo da Etapa 5) e segue · gaps_found → 21.
21. *(gaps)* Fecha 1×: despacho da 2.3 (`prompts/plan.md`, args `N --gaps`) → re-execução pela regra de rota da 3.3 (`prompts/execute.md` ou inline) → re-verifica. ⏸️ Persistiu → Sub-rotina D (parada graciosa).

**Etapa 4 — Gates de qualidade** *(retomada por existência de arquivo)*
22. 🔒 ⏭️ Code review via **subagente** (sem `NN-REVIEW.md`; Sub-rotina H + `prompts/code-review.md`, hospedando `gsd-code-review N --fix --auto`). Critical restante → 🔔; segue sempre.
23. 🔒 🎌`--ui` ⏭️ UI review (sem `NN-UI-REVIEW.md`): sobe dev server → `gsd-ui-review N` → derruba. Pilar 1-2 / flag → 🔔.
24. 🔒 🎌`--ai` ⏭️ Eval review via **subagente** (sem `NN-EVAL-REVIEW.md`; Sub-rotina H + `prompts/eval-review.md`, hospedando `gsd-eval-review N`). Veredito < PRODUCTION READY → 🔔.
25. 🔒 ⏭️ Secure phase via **subagente** (sem `NN-SECURITY.md` com `threats_open: 0` limpo de `aceites_sem_dono`; Sub-rotina H + `prompts/secure.md`). Decisão de ameaça sobe (`needs_decision`) — inclusive aceite de risco NOVO. ⏸️ Ameaça aberta ao final → **bloqueia**.
26. 🔒 ⏭️ Validate phase via **subagente** (sem `NN-VALIDATION.md` com `nyquist_compliant: true`; Sub-rotina H + `prompts/validate.md`). ⏸️ Gaps → a escolha (Fix all / Skip) sobe como `needs_decision`.

**Etapa 5 — UAT interativo automatizado** *(retomada por ESTADO do `NN-UAT.md`, não mera existência)*
27. ⏭️ Retomada por estado (5.1): ausente → 28 · `pre_uat` ≠ `executed` → 29 · `executed` + `issue` sem marcador de fix → 30 · `executed` + `issue` com marcador → ⏸️ D · `executed`, sem `issue` em aberto → Etapa 6 (que roteia: balde 3 → hand-back · senão → ship).
28. 🔒 Gera o `NN-UAT.md` via subagente (find_summaries → extract_tests + cold-start → create_uat_file); frontmatter `pre_uat: generated`.
29. 🔒 Sobe o dev server (Sub-rotina B; fase sem server → pula DECLARANDO) → despacha o **subagente de UAT** (Sonnet 4.6 + `uat-playbook.md`) — **sempre, com ou sem GUI** (sem GUI ele usa `<non_gui_surfaces>`; UAT inline pela camada 0 é proibido): dirige browser/bash, classifica nos 4 baldes (1 pass · 2 issue · 3 não-pude-verificar · 4 assumed), aplica `<push_on_it>` no balde 1, escreve resultados, gera o teste do caminho feliz → derruba o server. Devolve só o resumo compacto (com `probes_executados`). Frontmatter → `pre_uat: executed`.
29b. *(balde 3 com prova objetiva plausível)* Conversão via **subagente de investigação** (5.4b): a caça à prova roda em janela descartável (nunca inline — proteção da janela do orquestrador); `provado` → o MESMO subagente de UAT reclassifica com a evidência; `não-provável` → fica balde 3, registra a tentativa.
30. *(balde 2)* 🔒 1 ciclo de conserto: despacho da 2.3 (args `N --gaps`) → re-execução pela regra da 3.3 (args `... --gaps-only`) → despacho da 4.1 (args `N --fix --auto --files=<arquivos do fix>`, sem a checagem de retomada) → reinicia o server → re-despacha o subagente de UAT **só** nos cenários `issue` → marca `pre_uat_fix_cycle: done`. Persistiu → ⏸️ Sub-rotina D.

**Etapa 6 — Encerramento + ship** *(roteamento por balde)*
31. **Roteia o desfecho:** sobrou balde 2 → ⏸️ D (pause-work) · sobrou balde 3 **ou** flag `--no-ship` → **hand-back** ao `/gsd-verify-work` (não shipa) · só baldes 1+4 → segue pro ship.
32. Consolida o "🔔 O que precisa de você agora" + os itens do **bloco de transparência** (balde 4 assumidos / balde 3 não-verificados / decisões de intenção adotadas por recomendação do revisor, 0-B / passos que não rodaram — config off ou ferramenta indisponível, com o motivo).
33. Resumo executivo (modo final, com o bloco de transparência no topo): **Sub-rotina F**. ⏭️ idempotente (`go_and_do_resumo: final`).
34. Commita os artefatos do UAT (`NN-UAT.md` + `tests/uat-fase-NN.spec.ts` + evidências) pra árvore ficar limpa pro preflight do ship (6.3b). 🔒 **Ship** (só na rota de ship): via **subagente** (Sub-rotina H + `prompts/close.md`, hospedando `close-phase N` — extract-learnings → promove a verificação → abre o PR). ⏸️ Bloqueio de ambiente (sem remote/`gh`) → sobe como `blocked`; respeita e reporta. Depois do retorno (shipado ou blocked): **emenda factual** da seção "Desfecho do ship" no resumo (6.4c) + commit.
35. Self-check (rede: sobrou plano sem SUMMARY → Sub-rotina D) + banner final (PR + bloco de transparência + add-tests como passo **pós-PR**) + evento `stop` na telemetria (Sub-rotina G) e devolve o controle.

</master_checklist>

---

<stop_points>

## Paradas herdadas — quando um comando GSD te chama (não é bug)

A `/go-and-do` tem stops próprios (gate de contexto no teto de tokens, a pausa da revisão de
intenção — achado confirmado que mexe em requisito/critério/oráculo sobe do subagente de intenção
como `needs_decision` e chega a você (0B.3), os revisores de intenção
instalados mas falhos — sem segunda opinião a fase não segue (Etapa 0-B, `intent_review:
blocked`; setup SEM nenhum revisor instalado não para: a revisão é pulada com sino,
`intent_review: skipped`), gaps
persistentes, ameaça aberta, portões de entrada, bug de UAT persistente, balde 3 que bloqueia o
ship) — esses estão no roteiro. Mas os comandos GSD que ela invoca
têm stops próprios deles, que aparecem como `AskUserQuestion` no meio do fluxo. Não são falhas: são
decisões que o comando não toma sozinho. Quando um destes disparar, roteie pela **triagem de
decisão (Sub-rotina I)**: o que for da alçada do usuário (informação externa, escopo, irreversível
fora do trilho, sem recomendada) chega a ele — nunca contorne a parada com flags —; o que a triagem
classificar como carimbo é auto-decidido, registrado no `NN-DECISOES.md` e segue. Se a skill parar,
registre o motivo numa linha de handoff (`🔔 ...`). **Quando o comando roda hospedado num
subagente** (Sub-rotina H), o mesmo stop chega a você por outro cano — o hospedeiro não tem
`AskUserQuestion`, então ele devolve `needs_decision` com a pergunta mastigada, a camada 0 a
apresenta ao usuário e a resposta continua o mesmo subagente. O stop é honrado igual; só muda o
transporte.

**No `gsd-ui-phase` / `gsd-ai-integration-phase`** (Etapa 1 — contratos de design):
- **UI-SPEC BLOCKED** — o `gsd-ui-researcher` não consegue montar o contrato (falta decisão crítica
  de design que o CONTEXT.md não cobre, ou registry de terceiros sem vetar). Para.
- **Revision stall (UI)** — o `gsd-ui-checker` reprovou 2× sem convergir → "force approve / edit /
  abandon". Parada saudável: melhor um contrato revisado do que design débito.
- **Entrevista do `gsd-framework-selector`** — quando o CONTEXT.md não cobre as decisões de IA (tipo
  de sistema, provider, linguagem, requisito), o selector faz uma entrevista de ≤6 perguntas.
  Decisão de arquitetura legítima: deixe chegar ao usuário (escolher o framework de IA não se
  automatiza às cegas — a 1ª opção pode ser a errada pro caso).
- **AI validation fail** — o AI-SPEC.md saiu incompleto e o comando pergunta re-run / continuar.

**No `gsd-plan-phase`** (mesmo com a research resolvida pela flag `--research`):
- **Decision-coverage gate** — o plano não cobre decisões do CONTEXT.md. *Desligável* por
  `workflow.context_coverage_gate: false`, se você quiser menos atrito.
- **Requirements-coverage gap** — REQ-IDs sem plano correspondente.
- **Source-audit gaps** / **Phase-split recommended** — a fase está mal-dimensionada (itens
  fora do escopo, ou grande demais). Parada saudável: melhor split do que plano inchado.
- **Revision-loop stall** — 3 iterações sem convergir → "force proceed / guidance / abandon".

**No `gsd-execute-phase`** (o `--auto` da 3.3 não silencia estes):
- **Falha de teste de regressão** — testes de fases anteriores quebraram. Deve parar.
- **Schema drift** — banco e tipos dessincronizados (Fix / override / abort).
- **Conflito pós-merge** entre planos paralelos.
- **Checkpoint `human-action`** — gates de auth / 2FA / verificação por e-mail, migrations
  que só você roda (`npx supabase db push`) e afins: nunca se automatizam, nem com `--auto`.
  A `/go-and-do` não contorna isso; quando o execute para num desses e você defere, a **3.4**
  detecta a execução incompleta e fecha com handoff limpo (**Sub-rotina D**) em vez de deixar
  você preso no prompt.

Regra de ouro: se o stop é uma decisão de design/escopo (contratos da Etapa 1 / plan) ou um portão
de realidade (regressão / schema / auth no execute), é legítimo — pausa, anota no banner, e o
usuário decide. A Sub-rotina I formaliza essa régua: ela separa o que é do dono do que é carimbo,
e é ela quem decide se a pergunta chega ao usuário, é auto-decidida com registro, ou (gate duro de
madrugada) vira parada graciosa.

</stop_points>

---

<subroutines>

<subroutine name="A — gate de contexto (antes de cada comando principal)">

## Sub-rotina A — gate de contexto (antes de CADA comando principal)

Antes de cada passo marcado 🔒 no roteiro-mestre — e isso vale para **todos** eles, do primeiro
ao último:

1. Rode Bash — o context-check e, no **mesmo bloco**, o checkpoint de telemetria (Sub-rotina G):
   ```bash
   out=$(bash $HOME/.claude/skills/go-and-do/scripts/context-check.sh); echo "$out"
   t=$(printf '%s' "$out" | sed -n 's/.*tokens=\([0-9]*\).*/\1/p')
   p=$(printf '%s' "$out" | sed -n 's/.*pct=\([0-9]*\).*/\1/p')
   l=$(printf '%s' "$out" | sed -n 's/.*limit=\([0-9]*\).*/\1/p')
   bash $HOME/.claude/skills/go-and-do/scripts/run-log.sh "<phase_dir>" "<NN>" checkpoint "<etapa que vem a seguir>" "$t" "$p" "" "$l"
   ```
   *(o context-check lê `$CLAUDE_CODE_SESSION_ID` direto do ambiente — não precisa exportar nada).*
2. Leia a linha do context-check: `tokens=NN limit=MM pct=PP status=XX [reason=...]`. Anuncie numa
   linha pro usuário o que mediu (ex.: "contexto em 180k/400k tokens (45%) — seguindo") — dá
   visibilidade da trajetória entre comandos. `tokens` = tokens absolutos em uso; `limit` = o
   teto; `pct` = % do teto consumido (só leitura humana).
   **Detector de auto-compact (mecânico, no script):** o `run-log.sh` compara cada checkpoint
   com o último valor de tokens da MESMA sessão no JSONL; queda > 100k (contexto não encolhe
   sozinho) → ele grava o evento `compact` automaticamente. A detecção saiu da sua disciplina
   de propósito (caso real 07/07: o compact foi percebido verbalmente e o evento NÃO foi
   gravado). O que continua sendo SEU trabalho quando o evento aparecer no output do bloco ou
   você notar a queda: anuncie numa linha ao usuário e **re-ancore na disciplina** — as
   Sub-rotinas A/C/G seguem valendo, o roteiro-mestre segue de onde o DISCO diz que está
   (caso real: após um compact, a telemetria silenciou até o fim da sessão porque o resumo
   comprimido não carregou esta disciplina). Nota: a medição ignora turnos que consultaram o
   advisor nativo (payload efêmero de ~118k inflava a leitura e gerava falso-positivo —
   corrigido no context-check.sh em 07/07).
3. **`status=stop`** (tokens ≥ teto): use a **Sub-rotina D** (parada graciosa) com o motivo
   `contexto em NNk tokens` na linha de handoff impressa. Ele retoma fresh com `/go-and-do N`.
4. **`status=ok`** → siga normalmente. **`status=unknown`** → siga, mas registre o
   `reason=` numa linha pro usuário (ex.: "⚠️ gate de contexto não mediu — `no-jq` —
   confiando na retomabilidade"). O freio falha aberto de propósito (a retomabilidade
   cobre); o ganho de tornar isso visível é você não se achar protegido quando não está.

Teto absoluto de **400k tokens** (não % da janela) = decisão deliberada. O gate mede a
QUANTIDADE de contexto carregado, não a fração de uma janela que varia 5x entre sessões (200k
vs 1M) — uma fração era ilegível por skill (o id do modelo no transcript vem sem o sufixo
`[1m]`) e gerava o bug de 1M lido como 200k. 400k fica ABAIXO do auto-compact do harness
(observado a ~460k em fase real): o gate só cumpre o papel — pausa graciosa, retomável, sob
controle da skill — se agir antes do compact, que é com perdas; a folga também absorve o
crescimento de uma etapa inteira entre duas checagens. Numa sessão de 200k o autocompact
nativo (~166k) age muito antes, então na prática o teto governa sessões de janela grande.
Ajustável via env `CONTEXT_TOKEN_LIMIT`. O número fica ≥1 turno atrás do real (turnos que
consultam o advisor são excluídos da medição) e mede só o orquestrador (subagentes não
contam) — ou seja, o gate SUB-mede e age mais tarde: fail-open assumido, coberto pela
retomabilidade (e é por isso que o teto tem folga sobre o compact, não margem zero).

> Por que parar e retomar (em vez de deixar correr e compactar): a doc de prompt da
> Anthropic recomenda, em workflows multi-janela, começar uma janela nova em vez de
> compactar — "Claude's latest models are extremely effective at discovering state from
> the local filesystem". O design da skill (estado em disco + commits atômicos + handoff do
> `gsd-pause-work`) é exatamente o que torna a retomada fresh superior à compactação, que perde
> fidelidade numa orquestração longa. Por isso o gate para — não é um workaround.

**Granularidade (limitação conhecida):** o gate só mede ENTRE comandos — não dá pra
interromper um `Skill gsd-*` no meio. Pós-Onda 2 isso pesa quase só na **rota inline da 3.3**
(plano `autonomous: false` → execute hospedado na camada 0): foi um execute inline que cresceu
+300k num único passo e causou o único auto-compact observado; despachado, esse custo nem toca
a camada 0. Se a rota inline for inevitável numa fase enorme, vale quebrá-la antes
(`/gsd-phase`) ou pausar manualmente (`/gsd-pause-work`); o detector de compact (passo 2)
cobre o pior caso.

</subroutine>

<subroutine name="B — subir / derrubar o dev server (UI review e UAT)">

## Sub-rotina B — subir / derrubar o dev server (UI review e UAT)

0. **Consulta a receita de launch persistida, se houver** (acelerador oportunista — não é
   dependência; a heurística dos passos 1–5 segue sendo o caminho padrão). Do diretório do
   projeto até a raiz git, procure uma skill de run no disco:
   `grep -Hm1 '^description:' <dir>/.claude/skills/*/SKILL.md` em cada nível. Case pela
   **descrição** (menciona subir/rodar/launch deste app), não pelo nome da pasta — `run-<nome>/`
   é o padrão, mas o nome varia.
   - **Achou** → leia o `SKILL.md` (e o driver que ele referencia) e extraia a **receita**:
     comando de launch, env vars, porta, pré-requisitos. Execute a receita você mesmo nos passos
     2–3 (mesmo esquema background + poll da porta) e pule o passo 1 — a receita já diz o
     comando. **Não invoque skill nenhuma**: nem `/run` (inline — despejaria DOM/logs na sua
     janela) nem `/run-skill-generator` (é `disableModelInvocation` — só o humano dispara). O
     ganho é a receita consultada, não a delegação.
   - **Não achou** → siga para o passo 1.
1. **Detecta o tipo de projeto e o comando** (leia o `package.json`; o gerenciador vem do lockfile:
   `pnpm-lock.yaml`→pnpm, `yarn.lock`→yarn, `bun.lockb`→bun, senão npm):
   - **Expo / React Native** — se `expo` está nas deps **ou** algum script roda `expo start`. O
     gsd-browser só dirige **navegador**, então o alvo é o **web do Expo** (não o app nativo
     iOS/Android, que precisaria de Maestro/Detox/Appium — fora do alcance desta skill). Comando:
     - se há um script que invoca `expo start --web` (ex.: `"web": "expo start --web"`) → rode-o pelo
       gerenciador (`npm run web` / `pnpm web` / `yarn web`);
     - senão → `npx expo start --web`.
     - Suba com `CI=1 BROWSER=none` no ambiente (não-interativo — sem o menu de teclas do Expo — e
       sem auto-abrir aba do navegador). Porta a esperar: **8081** (Metro web; fallback **19006** no
       Expo antigo baseado em webpack).
   - **Web comum** (Next/Vite/etc.) — script `dev` (fallback `start`). Porta a esperar:
     `3000` / `5173` / `8080`.
2. Sobe em background (`run_in_background` no Bash — um dev server nunca "termina"; em
   primeiro plano prenderia a skill).
3. Espera a porta (polling na porta da receita do passo 0 — se houve — ou na lista do tipo
   detectado no passo 1, timeout ~60-90s — o **primeiro
   boot do Expo web é lento**, pode bundlar por ~1-2 min na 1ª vez; se for Expo, use o teto de 90s).
   Guarde a **porta** que respondeu — é ela que vai no prompt do subagente de UAT (5.4).
4. De pé → use o servidor: o `gsd-ui-review` (4.2) acha sozinho; no UAT (5.4) o orquestrador passa a
   URL `http://localhost:<PORT>` ao **subagente** (que dirige o browser — o orquestrador não navega).
5. **Cold-start limpo SEM receita (o passo 0 não achou nada e a heurística subiu)?** Auto-persista
   a receita para a próxima rodada pular a adivinhação — escreva
   `<projeto>/.claude/skills/run-<nome-do-app>/SKILL.md` (você escreve o arquivo direto; é o mesmo
   precedente do `/verify` nativo, que persiste o próprio SKILL.md):
   ```markdown
   ---
   name: run-<nome-do-app>
   description: Sobe o <nome-do-app> localmente para desenvolvimento/verificação (dev server em localhost:<porta>)
   ---
   # Como subir o <nome-do-app>
   - Pré-requisitos: <.env? banco? install prévio? deps de web do Expo? — só o que você constatou>
   - Comando: `<o comando exato que funcionou>` (background, env: <CI=1 BROWSER=none etc.>)
   - Porta: <a porta que respondeu> (boot observado: ~<N>s)
   - Derrubar: matar a árvore de processos inteira do comando acima (não só o PID pai)
   ```
   O valor da receita está nas pegadinhas não-óbvias que você acabou de resolver — registre-as. Se
   já subiu por uma receita existente (passo 0) e algo dela divergiu (porta/comando mudou),
   atualize o arquivo em vez de criar outro. Falhou a escrita → siga sem ela; a receita é bônus.
6. Não subiu no timeout → siga em code-only e registre a ressalva. Causas comuns: monorepo, projeto
   não-Node, dev server que exige `.env`/banco/`install` prévio, ou — no Expo — **faltam as deps de
   web** (`react-dom`, `react-native-web`, `@expo/metro-runtime`); sem elas o `expo start --web`
   aborta. No UAT, sem server os cenários de UI viram **balde 3** (não-pude-verificar).
7. Cleanup obrigatório: ao terminar, mate o processo do servidor (e filhos),
   pra não deixar órfão consumindo recursos. *(O Metro do Expo abre processos filhos — garanta que
   o kill alcance a árvore inteira, não só o PID pai.)*

</subroutine>

<subroutine name="C — lista de tarefas ao vivo (TaskList)">

## Sub-rotina C — lista de tarefas ao vivo (TaskList)

A TaskList dá visibilidade ao vivo do pipeline no terminal. Ela é **efêmera** (vive só na
sessão; some num terminal novo ou após o reset de 5h) — por isso não é fonte da verdade: o
estado real continua no disco (`init.phase-op` + arquivos da fase).
A TaskList só **espelha** esse estado. Quem mexe nela é só o orquestrador.

**As tarefas (uma por comando principal)** — crie só as aplicáveis a esta rodada:

| # | Tarefa | Concluída (`completed`) quando, no disco: |
|---|--------|-------------------------------------------|
| 1 | Intenção — SPEC (`gsd-spec-phase`) *(pula se a fase já tem planos)* | existe `NN-SPEC.md` |
| 2 | Intenção — CONTEXT (`gsd-discuss-phase`) *(idem)* | existe `NN-CONTEXT.md` |
| 3 | Revisão adversarial de intenção *(idem)* | existe `NN-INTENT-REVIEW.md` com `intent_review: done` (`blocked` NÃO conclui — re-tenta) |
| 4 | Contrato de UI *(só com `--ui`)* | existe `NN-UI-SPEC.md` |
| 5 | Contrato de IA *(só com `--ai`)* | existe `NN-AI-SPEC.md` |
| 6 | Planejar (`gsd-plan-phase`) | `has_plans` verdadeiro |
| 7 | Revisão cruzada do plano (convergence) | existe `NN-CONVERGENCE.md` com `convergence: done` (ou `has_verification` verdadeiro — fase que rodou antes do marcador existir) |
| 8 | Executar a fase (`gsd-execute-phase`) | `has_verification` verdadeiro |
| 9 | Code review | existe `NN-REVIEW.md` |
| 10 | UI review *(só com `--ui`)* | existe `NN-UI-REVIEW.md` |
| 11 | Eval review *(só com `--ai`)* | existe `NN-EVAL-REVIEW.md` |
| 12 | Secure phase | existe `NN-SECURITY.md` com `threats_open: 0` e sem `aceites_sem_dono` |
| 13 | Validate phase | existe `NN-VALIDATION.md` com `nyquist_compliant: true` (ou com o marcador `go_and_do_validate: done`, no desfecho `partial`) |
| 14 | UAT interativo automatizado | `NN-UAT.md` com frontmatter `pre_uat: executed` e sem `result: issue` em aberto |
| 15 | Encerramento + ship | rota de ship: PR criado (close-phase) · rota de hand-back: banner + `NN-RESUMO-EXECUTIVO.md` (`go_and_do_resumo: final`) |

São os mesmos sinais que a retomada (0.4 + Etapas 1/4/5) já usa pra pular o que está pronto — a
lista não inventa estado, lê o disco.

**Montagem na Etapa 0 (toda invocação):**
0. **Disponibilidade primeiro**: os tools de task são um recurso que o runtime liga e desliga
   sem changelog (flag server-side — em 23/07, presentes numa sessão e ausentes noutra da
   MESMA versão 2.1.218). Se `TaskCreate`/`TaskList` não estiverem na janela (nem via
   `ToolSearch select:TaskCreate,TaskUpdate,TaskList`), **pule esta sub-rotina inteira**:
   registre a limitação uma vez ("TaskList indisponível neste runtime — seguindo pelo disco")
   e mencione no sumário executivo. Sem retry, sem ruído por etapa — o disco já é a fonte da
   verdade e a lista é só espelho. Se os tools voltarem numa re-invocação, a montagem abaixo
   religa sozinha.
1. Consulte `TaskList`. Se já existem as tarefas desta fase (re-invocação na mesma sessão),
   só reconcilie os status — não duplique.
2. Senão, `TaskCreate` para cada tarefa aplicável (pule a 4/UI e a 5/IA, e a 10/UI e a 11/IA, sem
   a flag; pule as 1–3/Intenção quando a fase já tem planos — mesma regra da Etapa 0-B).
3. Marque o status pelo sinal de disco da tabela: pronta → `completed`; o resto → `pending`.
   Numa retomada, isso faz a lista nascer **fiel ao que já foi feito**, em vez de começar
   vazia mentindo que nada aconteceu.

**Disciplina durante a execução** — vale para **todos** os comandos principais (todos os passos
🔒 do roteiro-mestre — os mesmos da Sub-rotina A), não só o primeiro:
- Ao **começar** um comando, `TaskUpdate` a tarefa correspondente para `in_progress`. É isso
  que mantém a lista **fiel à etapa que está sendo feita** agora.
- Ao **concluir** (artefato no disco), `TaskUpdate` para `completed` — e registre o evento `end`
  da telemetria (Sub-rotina G), que fecha a medição de duração daquela etapa.
- Etapa que roda via **despacho** (Sub-rotina H): o despacho é o comando principal — marque
  `in_progress` a(s) tarefa(s) que ele cobre ao despachar e atualize pela tabela no retorno.
  (O despacho da intenção cobre as tarefas 1–3 de uma vez; um retorno `needs_decision` deixa
  a tarefa em curso `in_progress` — o passo está no meio, aguardando a resposta.)
- **Varredura no fecho (anti-órfã):** no banner final (6.5) — ou na parada da Sub-rotina D —
  confira a `TaskList`: nenhuma tarefa da fase pode sobrar `in_progress`. Etapa que terminou →
  `completed`; etapa que não vai mais rodar → complete com nota do porquê. Caso real (F21,
  28/07): a tarefa do UAT abriu `in_progress` às 16:11 e nunca fechou — a lista terminou a
  fase mentindo que o UAT estava em curso.
- A tarefa 15 (Encerramento) vira `completed` no fim da Etapa 6, junto com o banner.

**Em parada** (stop point, gate de contexto no teto de tokens, bloqueio herdado): deixe a tarefa em curso
em `in_progress` — ela representa o passo travado/no meio; não marque `completed`. Na próxima
`/go-and-do N`, a montagem (Etapa 0) relê o disco: se aquele comando não gerou seu artefato,
a tarefa volta a `pending` e roda de novo — fiel ao que de fato ficou pronto.

</subroutine>

<subroutine name="D — parada graciosa (pause-work)">

## Sub-rotina D — parada graciosa (pause-work)

Use quando sobra **trabalho de implementação** que depende de você: uma ação humana
(`human-action` — rodar `npx supabase db push`, login, 2FA, colar uma chave), as ondas que
dependiam dela e não rodaram, os revisores de intenção bloqueados (Etapa 0-B — Codex E agy
instalados mas falhos, `intent_review: blocked`: você resolve o ambiente e retoma; nenhum
instalado = revisão pulada com sino, não parada), gaps
persistentes (3.5), uma **ameaça de segurança aberta** ao fim da 4.4, um **bug de UAT
(balde 2)** que sobreviveu a 1 ciclo de conserto (5.5), um ship reprovado pelo freio herdado
(6.4-SHIP, `uat_reprovado`), um **gate duro disparado na janela de silêncio** (Sub-rotina I —
a pergunta pendente vai no handoff em vez de pendurar de madrugada), ou o gate de contexto no
teto de tokens (Sub-rotina A). Em vez de
terminar no vazio ou ficar presa num prompt, feche com um handoff limpo.

1. **Encerre o trabalho vivo — inclusive o que o TaskStop não mata.** Subagente ativo →
   `TaskStop` na árvore. Depois varra o que sobrou: `TaskStop` não alcança os **bash em
   background** que o subagente deixou armados (waiters de disco, processos codex) — caso real
   21/07: um waiter órfão sobreviveu 55min ao TaskStop e foi a última entrada da sessão.
   Cheque as tasks de background vivas e os processos (`ps` por `codex`/waiters conhecidos) e
   encerre o que pertencia à árvore parada; o que não der para matar, anote no handoff.
   Feche também na telemetria a etapa que a pausa interrompeu: se o último evento da sessão no
   `NN-RUN-LOG.jsonl` é um `checkpoint` sem `end`, registre `end` com etapa
   `"<etapa> (interrompida na pausa)"` e os `subagent_tokens` que o harness chegou a reportar
   (parcial vale; nada reportado → omita; nunca estime). Etapa sem `end` fica "aberta" no JSONL
   e some da conta de custo (caso real 21/07: o secure interrompido pela pausa de contexto).
2. **Resumo executivo (modo parcial).** Antes do pause-work, gere o panorama do que rolou até
   aqui: **Sub-rotina F** com `modo: parcial` e o `motivo` desta parada (ação humana / gaps
   persistentes / ameaça aberta / bug de UAT / ship reprovado / gate duro em janela de
   silêncio — com a pergunta pendente / `contexto em NN%`).
   Escreve+commita o `NN-RESUMO-EXECUTIVO.md`.
   É um subagente — barato mesmo com o contexto já alto (tem janela própria). Falhou ao gerar →
   **não pare por isso**: registre numa linha e siga pro pause-work (o handoff técnico é o que
   garante a retomada; o resumo é o conforto pro humano).
3. `Skill gsd-pause-work` — escreve o handoff durável (HANDOFF.json + `.continue-here.md`) e faz
   o commit WIP. Não exige input seu; lê o estado do disco. Registre também o evento `stop` na
   telemetria (Sub-rotina G), com `pausa: <motivo>` como etapa.
   **Reconciliação-lite do STATE.md:** depois do pause-work, confira que o `stopped_at` e o
   `Resume file` do `.planning/STATE.md` apontam para o ponto REAL da parada (a etapa desta
   pausa e o `.continue-here.md`) — o pause-work lê o disco, mas não corrige um `stopped_at`
   herdado de uma etapa anterior (caso real 21/07: fase pausou na 3.2 e o STATE ficou dizendo
   "UI-SPEC approved", 2 etapas atrás; quem retoma pelo STATE é enganado — mesma família do
   handoff stale da F18). Divergiu → emende as duas linhas e inclua no commit WIP.
4. **Pare** e imprima uma linha de handoff `🔔` ao usuário: o **motivo** (ação humana, gaps
   persistentes, bug de UAT ou `contexto em NN%`), a **ação exata** com o comando literal
   quando houver (ex.: "🔔 rode `npx supabase db push`, depois `/go-and-do N`"), os planos que
   ficaram pendentes, e que **escreveu um panorama do que rolou até aqui em `NN-RESUMO-EXECUTIVO.md`**.
   Ele resolve e retoma com `/go-and-do N` (o execute-phase pula os planos com `SUMMARY.md` e roda só
   os que faltam; a Sub-rotina C reconstrói a lista fiel ao que já ficou pronto).

> **Quando NÃO usar:** dois casos fecham na **Etapa 6 com banner** (sem handoff de pause-work; um
> HANDOFF.json sobrando desviaria a retomada):
> - **Balde 3 (não-pude-verificar)** — login sem vault, 2FA, browser indisponível. A fase está
>   completa e auditada; só falta **verificação humana**. Próximo passo: `/gsd-verify-work` (que
>   retoma exatamente nesses cenários), não `/gsd-resume-work`. Rota de **hand-back** (6.4-HB).
> - **Balde 4 (assumed)** — juízo subjetivo. Não bloqueia nada: shipa com o aviso de transparência.
>
> Distinção que importa: um **bug de implementação** do UAT que não fechou em 1 ciclo (balde 2, 5.5)
> é trabalho de implementação → usa D. Um item **não-verificável** (balde 3) ou **subjetivo**
> (balde 4) → fecha na Etapa 6.

</subroutine>

<subroutine name="E — resolver o gsd-tools (shim do SDK)">

## Sub-rotina E — resolver o `gsd-tools` (shim do SDK)

Os retratos da fase (`init.phase-op`, `phase-plan-index`) vêm do `gsd-tools.cjs` do GSD —
**não** do antigo `gsd-sdk` (binário global removido na migração pro OpenGSD). Resolva o
caminho com o shim canônico (o mesmo que os comandos GSD nativos usam): tenta
`<runtime>/gsd-core/bin/`, depois `<root>/.claude/gsd-core/bin/`, depois `gsd-tools` no PATH,
depois `~/.claude/gsd-core/bin/`. O shim define a função `gsd_run`:

```bash
_GSD_SHIM_NAME="gsd-tools.cjs"; _GSD_RUNTIME_ROOT="${RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GSD_TOOLS="${_GSD_RUNTIME_ROOT}/gsd-core/bin/${_GSD_SHIM_NAME}"; if [ -f "$GSD_TOOLS" ]; then gsd_run() { node "$GSD_TOOLS" "$@"; }; elif [ -f "${_GSD_RUNTIME_ROOT}/.claude/gsd-core/bin/${_GSD_SHIM_NAME}" ]; then GSD_TOOLS="${_GSD_RUNTIME_ROOT}/.claude/gsd-core/bin/${_GSD_SHIM_NAME}"; gsd_run() { node "$GSD_TOOLS" "$@"; }; elif command -v gsd-tools >/dev/null 2>&1; then GSD_TOOLS="$(command -v gsd-tools)"; gsd_run() { "$GSD_TOOLS" "$@"; }; elif [ -f "$HOME/.claude/gsd-core/bin/${_GSD_SHIM_NAME}" ]; then GSD_TOOLS="$HOME/.claude/gsd-core/bin/${_GSD_SHIM_NAME}"; gsd_run() { node "$GSD_TOOLS" "$@"; }; else echo "ERROR: gsd-tools.cjs not found at $GSD_TOOLS and gsd-tools is not on PATH. Run: npx -y @opengsd/gsd-core@latest --claude --local" >&2; exit 1; fi
gsd_run query init.phase-op N
```

**Cole o shim no início de TODO bloco Bash que consulta o SDK** — os passos 0.2, 2.4, 3.1b,
3.2 (o `config-get` do gate de config, antes do despacho) e 3.4. A função `gsd_run` vive só
no shell daquele bloco e **não sobrevive** entre chamadas Bash separadas (estado de shell não
persiste), então cada um desses passos re-cola o shim e logo em seguida roda
`gsd_run query <comando> N`. *(O `config-set` que zera a flag de chain do discuss vive agora
no subagente de intenção — o `prompts/intent.md` carrega a própria cópia do shim.)*

Se o shim cair no `else` (não achou o `gsd-tools.cjs` em lugar nenhum), é um portão de entrada
falhando — **pare** (como na Etapa 0.3) e mostre ao usuário o comando de install
`npx -y @opengsd/gsd-core@latest --claude --local`.

</subroutine>

<subroutine name="F — gerar o resumo executivo (subagente Sonnet 4.6)">

## Sub-rotina F — gerar o resumo executivo (via SUBAGENTE)

Escreve o `NN-RESUMO-EXECUTIVO.md`: a **história da fase em prosa narrativa**, para o **dono do
projeto (não-técnico)**. Chamada em dois momentos: `modo: final` no encerramento (Etapa 6) e
`modo: parcial` em toda parada graciosa (Sub-rotina D, passo 1). Recebe:
- `modo` ∈ {final, parcial}.
- no `parcial`: o `motivo` da parada.
- no `final`: o `desfecho` ∈ {ship, handback}; a lista `itens_assumidos` (balde 4 — vai shipar
  assumido); no handback, a lista `itens_nao_verificados` (balde 3 — precisa do humano); em
  qualquer desfecho, a lista `itens_intencao` (decisões de intenção adotadas por recomendação do
  revisor cross-AI na Etapa 0-B, com o tradeoff de cada uma — vem do `transparencia:` do
  `NN-INTENT-REVIEW.md`; pode ser vazia), a lista `itens_nao_rodados` (passos que não rodaram
  por gate de config off ou ferramenta indisponível, com o motivo — da 6.2; pode ser vazia)
  e a lista `riscos_aceitos` (do retorno da 4.4, cada um com o ponteiro da decisão; pode ser
  vazia).
  **Ao montar `itens_nao_rodados`, leia também o frontmatter do `NN-CONVERGENCE.md` e do
  `NN-INTENT-REVIEW.md`** (campos `sinos:`/`intent_review:`) e some os sinos relevantes —
  `intent_review: skipped` (nenhum revisor externo instalado) entra OBRIGATORIAMENTE na
  lista, revisor indisponível (ex.: agy falho → revisão
  mono-modelo) e incidentes de recuperação (ex.: veredito de reviewer recusado e re-rodado)
  SÃO transparência devida ao dono (caso real: uma fase fechou o resumo sem mencionar que a
  revisão cruzada rodou o pipeline inteiro sem o 2º modelo — o dado existia, só não fluiu).
  Frontmatter é leitura permitida à camada 0 (operating rule "decide por frontmatter/JSON,
  nunca ingerindo documento"); o corpo continua proibido.

> Por que um subagente (e não o orquestrador): narrar decisões/problemas/warnings exige **ler** os
> artefatos verbosos da fase (SUMMARY/REVIEW/SECURITY/VERIFICATION/UAT…) — exatamente o que a
> operating_rule "não leia artefatos verbosos na sua janela" + o gate de contexto proíbem no
> orquestrador. O subagente tem janela própria; o orquestrador lê de volta só um status compacto.
> **Modelo: Sonnet 4.6** (`Agent` com `model: sonnet`) — é tarefa de síntese/escrita, não precisa
> de Opus; mais rápido e barato, e não consome a janela do orquestrador.

**Retomada / idempotência (só no `modo: final`):** se já existe `<phase_dir>/NN-RESUMO-EXECUTIVO.md`
com frontmatter `go_and_do_resumo: final`, **pule** — não redespacha o subagente (re-rodar uma fase
pronta não regera à toa). Um arquivo `parcial` (escrito numa parada anterior) **é** sobrescrito pelo
`final` quando a fase conclui. (Espelha o padrão `pre_uat: generated/executed` da Etapa 5.) No
`modo: parcial` sempre regera — cada parada reescreve o panorama completo do que foi feito até ali.

Telemetria: todo despacho desta sub-rotina fecha com `end` no run-log (Sub-rotina G) — etapa
`resumo parcial` ou `resumo final`, `subagent_tokens` reportados pelo harness, args 5/6 vazios.
É um dos subagentes mais caros da rodada (caso real 21/07: ~421k tokens do resumo da pausa
ficaram invisíveis no JSONL) — sem esta linha o custo dele some da telemetria.

**Despache um `Agent` com `model: sonnet` e `run_in_background: false`** (despacho síncrono —
mesma regra da Sub-rotina H) e este prompt (preencha `NN`, `<phase_dir>`, `<modo>`,
`<motivo>`, `<desfecho>`, `<itens_assumidos>`, `<itens_nao_verificados>`, `<itens_intencao>`,
`<itens_nao_rodados>`, `<riscos_aceitos>`, e — vindo da Etapa 6 — a dica de 🔔 que você já montou):

---
Você escreve o **resumo executivo** da fase NN de um projeto GSD, para o **dono do projeto — uma
pessoa NÃO-técnica**. Escreva em **português do Brasil**, em **prosa narrativa** (não bullets de
status), contando a *história* da fase.

**Objetivo:** que o dono entenda, sem jargão, **o que foi entregue**, **as decisões tomadas**, **os
problemas que apareceram e como foram resolvidos**, e **os erros críticos e os warnings que os
revisores pegaram** (code review, as IAs externas da revisão cruzada de plano, segurança, eval).
Traduza cada conceito técnico com **analogias do cotidiano**.

**Leia (apenas os que existirem) na `<phase_dir>`:** os `NN-*-SUMMARY.md` (o que cada plano
construiu), `NN-REVIEW.md`/`NN-REVIEW-FIX.md` (code review), `NN-UI-REVIEW.md`, `NN-EVAL-REVIEW.md`,
`NN-SECURITY.md`, `NN-VALIDATION.md`, `NN-VERIFICATION.md`, `NN-UAT.md` (cenários e o que ficou
PENDING), os `NN-UI-SPEC.md`/`NN-AI-SPEC.md`/`NN-SPEC.md`/`NN-CONTEXT.md` (a intenção da fase), o
`NN-INTENT-REVIEW.md` (a revisão adversarial da intenção — o que o revisor cético achou e o que
foi corrigido/adotado), o
`NN-DECISOES.md` **se existir** (as decisões que a orquestração tomou sozinha pela triagem — cada
uma com o porquê e como desfazer) e o
`NN-LEARNINGS.md` **se existir** (pode ainda não existir — ignore se faltar). **Não invente nada**
que não esteja nesses arquivos — em especial, **não invente contexto externo de negócio**.

**Atribuição de autoria de decisão — só com fonte citável.** Ao mencionar qualquer decisão
tomada durante a fase, a autoria segue a fonte: está no `NN-DECISOES.md` → foi a orquestração
("decidi por você"); está no Interview Log do SPEC como decisão do dono, num `AskUserQuestion`
respondido ou num `--obs` → foi o dono ("você decidiu"). **Sem fonte que crave a autoria, use
voz neutra** ("ficou decidido", "a fase definiu") — nunca "tomada por mim". Caso real
(F19 grupo-inspired, 24/07): o resumo atribuiu ao sistema uma decisão de oráculo que o dono
respondera ao vivo — erro na direção que rouba o crédito do dono e infla a autonomia relatada.

**Números de progresso com fonte estrutural.** Ao narrar onde uma rodada pausou ou retomou
("parou no plano X de Y", "N de M planos prontos"), derive o número do `HANDOFF.json`
(campos `plan`/`task`) ou da contagem de `NN-*-SUMMARY.md` no disco — **nunca** de
`remaining_tasks[].id` (o id da primeira tarefa restante não é o ordinal do plano). Antes de
gravar, self-check de consistência: todo número/ordinal citado mais de uma vez no documento
tem que bater entre as menções — e bater com a fonte. Caso real (F21, 28/07): o resumo disse
"pausa no 4º de 9 planos" quando o HANDOFF dizia plano 3 (`remaining_tasks[0].id: 4` era a
Task 2 do 21-03); o número errado sobreviveu a duas regerações e virou memória permanente
da fase.
**Contagem de ondas, mesma regra:** o número de ondas citado no resumo (ou em qualquer
checkpoint) vem do `=== waves ===` que o execute-phase COMPUTOU (ou da contagem real de
despachos), nunca da declaração do planner. Caso real (F2 rl-representation, 29/07): o
planner declarou 7 ondas, o execute computou e rodou 6 — mesma família de número que
sobrevive errado.

**BLOCO DE TRANSPARÊNCIA (no `modo: final`, SEMPRE no topo do documento, antes de tudo):**
Este é o sinal humano mais importante — escreva-o **primeiro**, destacado:
- **Desfecho `ship`** + há `<itens_assumidos>` → abra com:
  > **⚠️ Shipei assumindo estes pontos — confira antes de dar merge:**
  > [liste cada item balde 4: o que é, e por que depende do seu olho]
  >
  > O sistema passou em tudo que dá pra verificar objetivamente (a parte funcional). Estes pontos são
  > de **gosto/conteúdo** — só você decide se ficaram bons. O que aconteceu com o PR está na seção
  > "Desfecho do ship", no fim deste documento.
- **Desfecho `ship`** + sem `<itens_assumidos>` → uma linha tranquila: "Tudo que dava pra verificar
  objetivamente passou; a fase segue agora para o fecho (ship). O resultado real está na seção
  'Desfecho do ship', no fim deste documento."
  **Nunca afirme que o PR foi aberto, está aberto ou foi mergeado** — quando você escreve, o ship
  ainda não rodou; qualquer afirmação sobre ele seria previsão narrada como fato (caso real: um
  resumo afirmou "abri o PR" e o ship bloqueou 11 minutos depois sem PR nenhum).
- **Desfecho `handback`** → abra com:
  > **⚠️ Não shipei — estes pontos eu não consegui verificar e precisam de você:**
  > [liste cada item balde 3: o quê e por quê — ex.: "o cadastro fica atrás de um login que eu não
  > tenho credencial pra testar"]
  >
  > A fase está construída e auditada, mas não abri PR porque há comportamento que **ninguém
  > confirmou**. Rode `/gsd-verify-work NN` pra fechar isso.
- **Em qualquer desfecho**, se há `<itens_intencao>`: acrescente ao bloco uma subseção curta —
  "**Decisões de intenção que adotei por recomendação do revisor cético**" — listando cada uma
  com o tradeoff explicado em linguagem simples (o dono precisa saber o que foi decidido por
  recomendação de máquina, não por ele).
- **Em qualquer desfecho**, se há `<itens_nao_rodados>`: acrescente uma subseção curta —
  "**O que esta fase não rodou — ou rodou com ressalva**" — explicando em linguagem simples
  quais verificações ficaram de fora e por quê (um gate de configuração desligado neste
  projeto, ou uma ferramenta indisponível — ex.: um revisor externo fora do ar), separadas
  dos **incidentes com recuperação** (algo que falhou e foi refeito por outro caminho — ex.:
  um parecer de revisor recusado e re-emitido): pulo é ausência, incidente é ressalva — não
  misture os dois na mesma frase. O dono nunca descobre depois que algo foi pulado.
- **Em qualquer desfecho**, se há `<riscos_aceitos>`: acrescente uma subseção curta —
  "**Riscos que você aceitou**" — cada um em linguagem simples, com onde a decisão foi tomada
  (na revisão de intenção / na pergunta desta rodada). É assinatura do dono: ele revê aqui,
  não descobre no código.
- **Em qualquer desfecho**, se existe `NN-DECISOES.md`: acrescente uma subseção curta —
  "**Decisões que tomei por você (sem parar a fase)**" — cada uma em linguagem simples: o que
  foi decidido, por quê, e **como desfazer** se o dono discordar. É a contrapartida da
  autonomia: a supervisão que era um clique no meio do fluxo virou esta revisão no fim — nunca
  omita uma decisão registrada.

**Estrutura (esqueleto-guia — OMITA as seções que não se aplicam a esta fase):**
1. **O que a fase faz** — uma a duas frases, sem jargão.
2. **Os números reais** — só se a fase produziu números mensuráveis (contagens, cobertura, nº de
   testes). Senão, pule a seção inteira.
3. **Os problemas que apareceram — e como foram resolvidos** — um a um, narrados com calma e
   analogia; inclua os criticals/warnings do code review e o que as IAs externas pegaram no plano.
4. **O que garante que está certo** — testes, segurança, verificação, e o que o UAT automatizado
   conferiu (clicou/preencheu/percorreu) vs. o que ficou assumido.
5. **O que precisa de você agora** — na rota de ship: os itens assumidos + remeta à seção
   "Desfecho do ship" para o próximo passo concreto (não presuma qual será); na rota de handback:
   as pendências (verify-work → add-tests → close-phase) e os itens balde 3.
6. **A lição** — só se houver um aprendizado que valha a pena registrar.

**Honestidade (regra dura):** não infle ("está tudo perfeito") nem esconda pendências; marque com
clareza o que foi **assumido** (balde 4), o que ficou **não-verificado** (balde 3) ou não foi
testado. Um problema descrito honestamente vale mais que um verde falso — e aqui isso pesa mais,
porque na rota de ship o dono pode agir sobre o PR confiando em você.

**Estado do mundo além desta fase (regra dura):** qualquer afirmação sobre o estado de OUTRA
fase ou do repositório publicado (PR aberto/pendente/mergeado, deploy feito, fase "esperando
publicação") só entra no documento com uma destas âncoras: (a) consulta real ao mundo no momento
da escrita (`gh pr view`/`gh pr list` no repo de publicação), citando o resultado; ou (b) a fonte
local **com data**, escrita como atribuição ("segundo `ship_state.json`, atualizado em <data>"),
nunca como fato nu. **Artefato local não é evidência do mundo** — ele registra o que este repo
viu, não o que aconteceu lá fora (caso real, F20: o resumo afirmou "a Fase 19 segue pendente"
lendo um `ship_state.json` desatualizado, com o PR #31 mergeado havia 2,5 dias). Sem âncora
possível, **omita a afirmação** — o documento é sobre ESTA fase.

**Radiografia dos gates (regra dura):** o resumo DEVE citar, textualmente, o **veredito
agregado de cada gate que rodou** — code review (status + contagem por severidade + o ID de
cada achado que ficou ABERTO, ex.: "CR-E01"), UI review (score), eval review (veredito +
score, ex.: "NOT IMPLEMENTED, 36/100"), segurança (ameaças abertas/aceitas), validação
(veredito) e UAT (contagem por balde). Os vereditos estão nos frontmatters dos artefatos que
você já lê. Cobrir a "substância" de um gate sem citar o veredito NÃO cumpre a regra — caso
real (F16-ox, 25/07): o resumo explicou os 4 blockers do eval mas omitiu o "36/100 NOT
IMPLEMENTED", e não nomeou o único Critical restante do code review; o número mais duro da
fase só existia fora do documento do dono. Número ruim é exatamente o que este documento
existe para mostrar.

**Modo = `<modo>`:**
- `final` + `desfecho: ship` → a fase está na **rota** de ship (o ship roda DEPOIS de você): termine
  o documento com a seção literal:

  ```
  ## Desfecho do ship
  _(a ser preenchido pelo orquestrador após o fecho — se esta linha ainda estiver aqui, o ship
  não concluiu e nenhum PR deve ser presumido)_
  ```

  NÃO diga "pronta para UAT" (o UAT automatizado já rodou) e não afirme nada sobre PR.
- `final` + `desfecho: handback` → a fase está construída mas **não shipou**: feche com "**pronta
  para o seu UAT**" e aponte os itens balde 3.
- `parcial` → a fase está **PAUSADA** (motivo: `<motivo>`). Deixe isso explícito logo no topo:
  conte o que **já** foi feito até aqui, o que ainda **falta**, e que ele retoma com `/go-and-do NN`.
  **Não** diga "pronta para UAT" nem "PR aberto".

**Saída:** escreva em `<phase_dir>/NN-RESUMO-EXECUTIVO.md` com frontmatter contendo `fase`,
`go_and_do_resumo: <modo>` e `gerado_em` (rode `date +%F`; se não conseguir a data, omita o campo).
Responda ao orquestrador APENAS com: o caminho do arquivo + UMA linha ("resumo final escrito" /
"resumo parcial escrito — motivo X"). Não devolva o conteúdo do documento.
---

Quando o subagente retornar, o orquestrador faz o **commit**:
`git add <phase_dir>/NN-RESUMO-EXECUTIVO.md && git commit -m "docs(fase NN): resumo executivo"`
(sem footer de co-autoria — não polui o histórico do projeto). Se o commit falhar (nada a
commitar, `.planning/` fora do versionamento, ou repo sem git), **não pare** — registre numa linha
e siga (o arquivo no disco é o que importa).

</subroutine>

<subroutine name="G — telemetria da rodada (run-log)">

## Sub-rotina G — telemetria da rodada (`NN-RUN-LOG.jsonl`)

Mede o custo real de cada etapa (tokens, tempo, paradas). É ela que dá dado real às decisões
de custo do fluxo — foi esta telemetria que mediu o custo por etapa em fases reais e embasou
decisões de design da própria skill. O registro é um JSONL por fase:
`<phase_dir>/NN-RUN-LOG.jsonl` (uma linha por evento; sessões/retomadas distintas se distinguem
pelo campo `sessao`).

```bash
bash $HOME/.claude/skills/go-and-do/scripts/run-log.sh <phase_dir> <NN> <evento> "<etapa>" [tokens] [pct] [subagent_tokens] [limit] [tokens_camada2] [motivo]
```

`<phase_dir>` sempre ABSOLUTO (o script resolve relativo contra a raiz do git como
defesa, mas não confie no cwd — um subagente na pasta errada já criou uma árvore
`.planning/` duplicada). `limit` (8º arg) = o `limit=` que o context-check emitiu no
mesmo bloco — grava o denominador do `pct` e torna a linha autodescritiva.
`tokens_camada2` (9º arg) = a soma que o host reportou na linha `tokens_camada2:` do
contrato de retorno; host que devia reportar e não reportou → passe o literal
`sem_report` (vira a chave `"camada2":"sem_report"` — a ausência fica distinguível de
contagem completa). `motivo` (10º arg) = texto livre do `stop`/`skip` — vai em campo
próprio, não dentro da etapa.

**Vocabulário canônico da `etapa` (regra dura):** a string SEMPRE começa com o ID do
passo (`0-B intencao`, `2.3 planejamento`, `3.2 convergencia`, `3.3 execucao`,
`3.4 verificacao`, `4.1 code review`, `4.1b re-review`, `4.4 secure`, `4.5 validate`,
`5.3 gera-UAT`, `5.4 UAT`, `6.3 resumo`, `6.4 ship`) ou com um dos rótulos
`preparacao` · `probe` · `resumo` · `lateral <descrição>` (despacho fora do fluxo, ex.:
uma pesquisa pedida pelo dono). O script avisa quando o 1º token foge do vocabulário —
sem ID estável, a agregação entre fases é inviável (caso real F20: 4 grafias distintas).

O script também escreve sozinho (mecânico, sem disciplina): **`seq`** (contador
monotônico — a ordenação canônica do arquivo; timestamps colidem no mesmo segundo) e o
**auto-fechamento de janela** — um `checkpoint` novo com o anterior da mesma sessão ainda
sem `end`/`skip`/`stop` grava antes um `end` sintético `"auto_fechado":true` e avisa no
stdout (caso real F20: a 3.4 rodou e ficou sem janela; o custo caiu na etapa vizinha).
Viu o aviso → a telemetria da etapa anterior se perdeu; anote o `subagent_tokens` dela
num `end` corretivo se você o tiver.

Os 4 eventos e onde cada um é registrado:
- **`run`** — na Etapa 0.4, assim que o retrato entregou o `phase_dir` (marca o início ou a
  retomada da rodada; etapa = `preparacao`). O script grava sozinho o campo `skill_version`
  (`git describe` do clone da skill) nessa linha — é o que diz à auditoria qual versão regia
  a rodada (caso real, F19: uma release saiu com a fase em voo e metade do pipeline rodou em
  cada versão; a política associada — não publicar release com fase em voo — está no
  CHANGELOG da v1.1.3).
- **`checkpoint`** — no mesmo bloco Bash do context-check (Sub-rotina A, passo 1), com a etapa
  que vem a seguir e os `tokens`/`pct` medidos. É o "início" daquela etapa. `tokens`/`pct`
  saíram **vazios** (o context-check falhou — o `run-log.sh` avisa no stdout)? Re-rode o bloco
  inteiro UMA vez antes de seguir; persistindo, siga com o checkpoint vazio e anuncie numa
  linha a medição perdida (caso real, F16-ox 25/07: o checkpoint da 5.4 nasceu sem tokens em
  silêncio e a etapa ficou sem custo de contexto na auditoria).
- **`end`** — logo depois que o comando principal da etapa terminar (junto do `TaskUpdate` para
  `completed`, Sub-rotina C). A duração da etapa = `end.ts − checkpoint.ts`. Se a etapa rodou
  num subagente (Sub-rotina H), passe os tokens que o harness reportou pra ele como 7º
  argumento (`subagent_tokens`) — é o que mantém a telemetria de custo honesta quando o
  trabalho desce da camada 0; se o harness não reportar o número, omita o argumento (nunca
  estime). Subagente continuado (needs_decision → resposta → novo retorno): some os números
  que o harness reportou em cada volta; se só a última volta reporta (acumulado), use-a. Um
  despacho cujo desfecho roteia pra uma parada (`escalou`) ainda fecha com `end` — a etapa
  rodou e terminou; a parada em si é outro evento.
  **Camada 2 conta:** se o host despachado spawna agentes próprios (ex.: a convergência
  hospedando revisores/replans), o usage que o harness reporta à camada 0 cobre SÓ o host —
  os filhos ficam de fora e a etapa sai subcontada (caso real F16-ox 23/07: 2 replans Opus
  invisíveis no RUN-LOG). Regra: o prompt de **todo** host de etapa (os 8 de `prompts/`)
  exige, no retorno, a linha `tokens_camada2: <soma reportada pelo harness aos seus
  despachos>` — a camada 0 grava o valor como **9º argumento** do `end` (campo próprio
  `tokens_camada2`, separado do `subagent_tokens` do host). Host que não reportar a linha →
  registre só o host (nunca estime) e passe o literal `sem_report` no 9º argumento — a
  chave `"camada2":"sem_report"` marca a subcontagem de forma verificável.
  **Papel dos números (não re-aprenda da pior forma):** `subagent_tokens`/`tokens_camada2`
  são usage CUMULATIVO reportado pelo harness (input+cache+output de todos os turnos) —
  servem de **conferência e ordem de grandeza**, nunca de métrica de custo; a métrica é o
  ledger da /audit-gad, medido dos transcripts (o run-log superconta ~3-4x — caso real F20).
  **Notificação órfã de camada 2:** quando um agente de camada 2 pausado num checkpoint é
  retomado, o harness pode entregar a notificação de conclusão dele — com o total de tokens —
  à camada 0, e não ao pai que o despachou; o pai então reporta só o que viu antes da pausa,
  e nem uma `tokens_camada2` perfeita cobre o delta (caso real, F19: o executor do plano
  fechou em 261k, o pai só viu 188k, e os 73k da retomada sumiram da conta). Regra: chegou
  notificação de subagente que você NÃO despachou diretamente, com total de tokens → some-o
  ao `subagent_tokens` do `end` da etapa a que ele pertence; se o `end` daquela etapa já foi
  gravado, grave um `end` adicional só com o delta e etapa = `"<etapa> (camada 2 retomada)"`.
  Nunca descarte o número — a camada 0 é a única que o recebeu.
  **Vale também para as rotas inline e híbridas** (execute inline da 3.3, verificação 3.4,
  resumo parcial/final da Sub-F, gera-UAT 5.3, UAT 5.4): TODA etapa aberta
  por um `checkpoint` fecha com `end` (ou `skip`/`stop`) — etapa inline sem `end` fica "aberta"
  no JSONL e some da conta de custo (caso real: numa fase auditada, só as etapas despachadas
  tinham par run/end limpo). No `end` de uma etapa inline que spawnou agentes camada-2, some os
  usage que o harness reportou e passe como `subagent_tokens` (mesma regra de nunca estimar).
  Forma da chamada com `subagent_tokens` sem tokens/pct próprios — os args 5/6 vão VAZIOS
  (senão os tokens do subagente caem no campo `tokens` e poluem o detector de compact):
  ```bash
  bash $HOME/.claude/skills/go-and-do/scripts/run-log.sh <phase_dir> <NN> end "<etapa>" "" "" <subagent_tokens>
  ```
- **`stop`** — no desfecho da rodada: na Sub-rotina D (passo 2), no banner final da 6.5 e em
  qualquer parada por `blocked` ou impasse de um despacho (2.3, 3.2, 3.3, 4.1, 4.3, 4.4,
  4.5 ou 6.4). Etapa = `pausa` | `ship` | `handback`; o texto do motivo vai no **10º
  argumento** (campo `motivo`), não dentro da etapa. E o `stop` leva **medição final**:
  rode o mesmo context-check do checkpoint no mesmo bloco — sem isso o custo final de
  contexto da rodada fica desconhecido (caso real F20: último ponto medido 20min e um
  despacho de 354k antes do fim). Bloco canônico:
  ```bash
  out=$(bash $HOME/.claude/skills/go-and-do/scripts/context-check.sh); echo "$out"
  t=$(printf '%s' "$out" | sed -n 's/.*tokens=\([0-9]*\).*/\1/p')
  p=$(printf '%s' "$out" | sed -n 's/.*pct=\([0-9]*\).*/\1/p')
  l=$(printf '%s' "$out" | sed -n 's/.*limit=\([0-9]*\).*/\1/p')
  bash $HOME/.claude/skills/go-and-do/scripts/run-log.sh <phase_dir> <NN> stop "pausa" "$t" "$p" "" "$l" "" "<motivo em 1 linha>"
  ```
  Parada sem `stop` deixa a rodada "aberta" no JSONL. (Forma antiga — motivo dentro da
  etapa — continua aceita pelo script, mas não a use em registro novo.)
  **Antes do `stop` de fim de rodada (6.5 ou pausa), rode a auditoria da grade:**
  ```bash
  bash $HOME/.claude/skills/go-and-do/scripts/run-log.sh <phase_dir> <NN> audit
  ```
  Ela lista janelas abertas (checkpoint sem end/skip) — feche cada uma (`end` ou `skip`
  honesto) antes de fechar a rodada; e confira que todo passo pulado tem seu `skip`.

O script nunca falha o pipeline (sai 0 sempre; valida os campos numéricos; append puro). Se o
log não escrever, siga — telemetria é instrumento, não gate.

**Dois eventos adicionais:**
- **`skip`** — sempre que um passo que TERIA rodado não roda (gate de config off, ferramenta
  indisponível), com etapa = `"<id do passo> (<motivo>)"` (ex.:
  `"3.2 (config plan_review_convergence off)"`). Isso fecha o buraco do checkpoint-sem-`end`:
  um passo pulado depois do checkpoint termina em `skip`, não fica "aberto" no JSONL.
- **`compact`** — gravado AUTOMATICAMENTE pelo próprio `run-log.sh` quando um `checkpoint`
  registra queda > 100k vs o último valor da mesma sessão (detector mecânico — a detecção
  saiu da disciplina do modelo depois que um compact real foi percebido e não logado). Você
  não o grava na mão; seu papel é reagir quando ele aparecer (Sub-rotina A, passo 2:
  anunciar + re-ancorar). Sem este evento, um compact no meio de uma etapa fica invisível
  no JSONL e a queda de tokens do checkpoint seguinte parece erro de medição.

</subroutine>

<subroutine name="H — protocolo de subagentes (camada 1)">

## Sub-rotina H — protocolo de subagentes (camada 1)

A skill é organizada em camadas: a **camada 0** (esta conversa, o orquestrador) decide, encadeia,
trata erros e fala com o usuário; a **camada 1** são subagentes com janela própria e descartável
que executam o trabalho verboso de uma etapa; a **camada 2** são os agentes internos que os
comandos GSD spawnam por conta própria (planner, executor, reviewer — esta skill não os toca).
O porquê da divisão: a janela do orquestrador é o recurso mais escasso de uma orquestração
longa — cada etapa hospedada inline deixa o modelo das etapas finais mais "cansado" que o das
iniciais, e foi o eco de orquestração dos comandos GSD hospedados na camada 0 que levou fases
reais a ~90% da janela. Os subagentes que a skill já tinha (UAT 5.3/5.4, resumo executivo da
Sub-rotina F) seguem os próprios blocos; esta sub-rotina generaliza o padrão deles para as
etapas que descem.

**Despacho.** Uma etapa cujo bloco manda despachar roda num subagente `general-purpose`
(modelo herdado da sessão, salvo onde o bloco da etapa disser outro), **sempre síncrono:
`run_in_background: false` explícito na chamada do `Agent`** — o harness despacha em
background por padrão, e um despacho background quebra o fluxo (a notificação de término não
retoma o roteiro e a ida-e-volta de pergunta não se completa; caso real: um despacho
background da 0-B exigiu que o usuário matasse a sessão e recomeçasse). O prompt de despacho é
mínimo — as instruções detalhadas moram num arquivo que o SUBAGENTE lê do disco (mesmo padrão
do `uat-playbook.md`). **Não leia o `prompts/<etapa>.md` antes de despachar** — referencie o
caminho e pronto; ler duplica na camada 0 exatamente o conteúdo que a arquitetura mandou pro
disco (caso real: a camada 0 leu intent/plan/convergence.md antes dos 3 primeiros despachos de
uma rodada — custo puro, e parou de fazer nos seguintes). O despacho leva:

- o caminho do arquivo de instruções: `$HOME/.claude/skills/go-and-do/prompts/<etapa>.md`;
- a fase (`N`/`NN`), o `phase_dir`, o `project_root` e os caminhos dos artefatos de entrada —
  **sempre absolutos** (o cwd do subagente não é a raiz do projeto; verificado em teste);
- as flags relevantes da rodada (ex.: `--ui`, `--ai`, `vault_profile`) e, quando o bloco da
  etapa variar o comando, os `args` (ex.: `N --gaps` no fechamento de gaps);
- havendo `obs_text` (flag `--obs`): o texto literal como **primeira linha** da mensagem de
  despacho — "Nota do usuário para esta rodada: `<obs_text>`" — antes do caminho do arquivo de
  instruções. Não é um campo que os `prompts/*.md` precisam declarar em `<inputs>`: é texto
  solto no início do prompt, igual a uma instrução de continuação de pausa. O subagente decide
  se é relevante pro que ele hospeda (ex.: "veja o continue-here.md" pode importar pro plano OU
  pra execução, dependendo de qual etapa está rodando) — ignorar a nota por não ser aplicável
  àquela etapa é uma resposta válida, não um erro;
- em retomada de pausa: a resposta do usuário, verbatim.

Gates de config e condições de rota são checados na camada 0 ANTES do despacho (config off →
evento `skip`, sem gastar um subagente à toa).

**Credenciais (regra de nascença de todo despacho autenticado).** Se a tarefa do despacho —
em QUALQUER camada que ele spawne — exige sessão logada ou toca segredos (UI review de página
com login, UAT, probe de fluxo autenticado), o prompt de despacho leva duas coisas: (1) o
**caminho sancionado de acesso**, preparado pela camada 0 ANTES de despachar — um wrapper que
injeta as credenciais no processo, ou um helper que emite SÓ o código efêmero (ex.:
`uat-totp-now.ts`), nunca o segredo; e (2) a proibição literal: "PROIBIDO ler, copiar ou
imprimir `.env*`/segredos por qualquer via — Read, cat, script node/tsx, pipe; o guard de
permissão é string-match no comando e leitura indireta é evasão, não engenhosidade. Login
impossível pela via sancionada → devolva o item como não-verificável (balde 3) ou `blocked`
com o motivo — nunca contorne um controle." O porquê: 2 incidentes em 2 rodadas reais (um
subagente tentou editar config global para cumprir prompt; outro materializou senha+TOTP no
stdout via script) — a constraint aplicada por fase, reativamente, chega sempre um despacho
tarde.

Os subagentes não recebem notificações de trabalho em background (fato observado em fase
real: um hospedeiro ficou ~1h "aguardando" um revisor aninhado que nunca poderia notificá-lo)
— os `prompts/*.md` carregam o protocolo de background (decisão de 18/07, no lugar da
proibição total que era violada na prática): background é permitido para trabalho >10min
(o teto real do parâmetro `timeout` da tool Bash, capado pelo harness em 600000ms), desde
que o resultado seja um arquivo combinado e a espera seja UM waiter de disco bloqueante
com teto — nunca espera de notificação, nunca polling picado. O próprio waiter leva
`timeout: 600000` explícito na chamada Bash — vale para TODA camada, orquestrador incluso
(caso real, 19/07: um waiter do orquestrador rodou no default de 120s e morreu com exit
143 no meio da espera; a regra existia para os executores e o orquestrador não a aplicou
a si mesmo). Se ainda assim um retorno
vier **fora do contrato** (prosa em vez de um dos 3 blocos), não o aceite nem redespache:
**continue o mesmo subagente** com uma instrução de reconciliação ("decida pelo estado do
disco e finalize pelo return_contract") — foi o que recuperou o caso real.

**Contrato de retorno.** Todo subagente da camada 1 devolve um bloco compacto com um de três
estados — e nunca conteúdo verboso (o retorno é dado de roteamento; corpo de artefato vive no
disco, que é a fonte de verdade):

- **`done`** — com veredito, caminhos dos artefatos escritos e contagens. A camada 0 segue o
  roteamento do bloco da etapa.
- **`needs_decision`** — o subagente esbarrou numa decisão que não é dele. Antes de
  devolver, ele **gravou todo o progresso em disco** (regra de ouro dos arquivos de prompt) e
  devolveu a pergunta mastigada (opções + tradeoffs + `recomendacao` + `reversivel`). A camada 0
  roteia pela **triagem de decisão (Sub-rotina I)** — carimbo vira auto-decisão registrada no
  `NN-DECISOES.md`; alçada do dono vira `AskUserQuestion` (ou parada graciosa, na janela de
  silêncio) — e **continua o MESMO subagente** com a resposta (mensagem de follow-up —
  o contexto dele fica preservado integralmente). Não redespache do zero enquanto a
  continuação estiver disponível: redespachar re-paga o setup e re-executa trabalho que a
  continuação aproveita de graça.
  **Rótulo honesto na continuação:** só escreva "Decisão do usuário: X" se o usuário de fato
  escolheu X. Se ele respondeu com uma pergunta ou dúvida, isso NÃO é decisão — responda a
  dúvida e **re-pergunte** antes de continuar o subagente. Se ele delegou ("faça o que achar
  melhor"), rotule como é: "decisão da camada 0 (usuário delegou): X"; auto-decisão da triagem
  é "decisão da camada 0 (triagem): X". O porquê: o rótulo vira
  registro permanente no artefato — uma escolha da camada 0 assinada como se fosse do dono é
  exatamente o carimbo invertido que a revisão adversarial existe para impedir (caso real:
  usuário respondeu com pergunta e a camada 0 repassou a própria recomendação como "decisão
  do usuário").
  **Bloco de proveniência (quando a decisão É do usuário):** o rótulo sozinho não sobrevive à
  descida — para quem está duas camadas abaixo, "Decisão do usuário: X" escrito por você é
  asserção de agente, e um executor rigoroso vai (corretamente) recusá-la como resolução de
  checkpoint bloqueante (caso real, F19: o repasse carimbado virou autorização "provisória"
  com instrução de `git revert` plantada no STATE.md e verificação em `human_needed` — ~1h e
  3 commits para re-provar uma decisão já tomada). Repasse decisão do usuário SEMPRE neste
  formato, e instrua cada camada a repassá-lo verbatim ao descer:

  ```
  DECISAO-DO-DONO
  canal: AskUserQuestion | --obs | resposta direta no chat | retomada pós-pausa
  ts: <ISO da resposta>
  pergunta: <1 linha — o que foi perguntado>
  resposta_verbatim: "<a resposta dele, palavra por palavra>"
  ```

  O `ts` é o timestamp REAL da resposta — copie do transcript ou rode `date -Iseconds` no
  ato do registro. NUNCA aproximação ou placeholder (caso real F21, 28/07: um registro foi
  gravado com `ts: 2026-07-28T05:2x-03:00` literal no `NN-DECISOES.md` — campo de
  proveniência com valor inventado corrói a confiança do bloco inteiro).

  A contraparte — a regra de autoridade que faz o bloco funcionar — vive nos prompts das
  etapas que tocam checkpoint bloqueante (`prompts/execute.md`): só este bloco fecha um
  checkpoint de decisão do dono; qualquer outra menção é relato e não fecha nada.
- **`blocked`** — pré-condição indisponível (ex.: revisor cross-AI fora do ar). A camada 0
  trata conforme a semântica do bloco da etapa (re-tentar / Sub-rotina D). A descida para
  subagente **não afrouxa nenhum fail-closed** — o bloqueio sobe com motivo e é a camada 0
  quem para.

**Probe de aninhamento (uma vez por fase, antes do 1º despacho que hospeda comando GSD).**
O aninhamento (camada 1 spawnar camada 2) é uma capability que o runtime liga e desliga entre
releases — por isso o probe existe, e por isso nenhuma conclusão sobre ele pode ser gravada
como atemporal. Histórico: funcionava na CC 2.1.216; a 2.1.217 o desligou por padrão (antídoto
da época: `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, validado por probe A/B em 23/07); a **2.1.219
religou por padrão e subiu o teto para profundidade 3**, e nessa versão a mesma env var inverteu
de papel — hoje ela só **desliga** (`=1`), e qualquer valor abaixo de 3 vira um limitador. Ou
seja: na CC ≥ 2.1.219 o aninhamento não exige configuração nenhuma. Antes do primeiro
despacho de etapa que hospeda um comando GSD spawnador (plan/convergence/execute/gates/close),
rode um probe mínimo: um subagente `general-purpose` cuja única tarefa é responder se tem o
tool `Agent` na lista (base ou deferida via `ToolSearch select:Agent,Task`). Custa ~2k tokens
e decide a rota da fase inteira; sem ele, a descoberta custa um despacho cheio queimado (caso
real, F16 oxmuscle: ~9min/127k para receber `blocked`). Probe `sim` → camadas normais. Probe
`não` → rota inline para as etapas spawnadoras, com as duas regras abaixo.

**Rota inline (fallback do aninhamento) — duas regras inegociáveis.**
1. **Inline ⇒ leia o `prompts/<etapa>.md` antes de conduzir.** A regra "não leia o prompt
   antes de despachar" vale para o DESPACHO (evita duplicar na camada 0 o que vai pro disco);
   no inline ela INVERTE — a camada 0 está assumindo o papel do subagente, e as disciplinas
   da etapa (critérios, protocolos, correções recentes) moram no arquivo de prompt. Caso
   real, F16 oxmuscle: a convergência rodou inline guiada só pelo resumo do workflow.md e o
   critério de materialidade (correção de 22/07 em `prompts/convergence.md`) nunca entrou na
   janela.
2. **Registro versão-condicionado, nunca atemporal.** A decisão inline entra no
   `NN-DECISOES.md` e no `.continue-here.md` como "na CC <versão-exata>, subagentes não
   recebem `Agent`/`Task`" — jamais como "este harness não permite aninhamento". Um registro
   atemporal vira anti-pattern stale que perpetua o inline depois que o runtime muda (caso
   real: a D1 da F16 cristalizou como permanente uma regressão de 48h). Na retomada ou no
   bump de versão do CC, re-rode o probe antes de reutilizar a decisão.

**Telemetria envolvente.** O despacho é cercado como qualquer comando principal: `checkpoint`
(Sub-rotina A) antes; `end` na volta, com os tokens que o harness reportou pro subagente no 7º
argumento (`subagent_tokens`, Sub-rotina G). O gate de contexto segue medindo só a camada 0 —
é ela que não pode morrer; o custo da camada 1 fica visível no run-log.

**Retomada cross-sessão (fallback do protocolo).** Continuar um subagente só funciona dentro
da MESMA sessão. Numa retomada em sessão nova (`/go-and-do N` fresh), o subagente antigo não
existe mais — o caminho é o de sempre: o estado está em disco (artefatos + frontmatters), a
camada 0 identifica a etapa pendente e redespacha o subagente dela, que retoma cirúrgico pelo
que encontrar no disco. Quem cobre a retomada fina varia por prompt: o `intent.md` tem seção
própria de chegada (inclusive re-devolver uma pergunta pendente gravada no artefato); nos
despachos que só hospedam um comando GSD (`convergence.md` / `code-review.md` /
`eval-review.md` / `plan.md` / `execute.md` / `secure.md` / `validate.md` / `close.md`),
a retomada é a checagem-por-estado da camada 0 antes do despacho + a idempotência do próprio
comando — e um `needs_decision` desses **não sobrevive à sessão como artefato**: o
redespacho re-roda o comando e a mesma pergunta re-emerge (custo de re-execução aceito; pausas
de negócio esperadas moram na intenção, que persiste as suas em disco).

</subroutine>

<subroutine name="I — triagem de decisão (antes de todo AskUserQuestion)">

## Sub-rotina I — triagem de decisão (antes de TODO `AskUserQuestion`)

Base empírica (inventário de 20/07/2026 — 461 perguntas históricas nos transcripts): quando
havia opção recomendada, o usuário a escolheu em ~84–90% dos casos, e o custo real eram as
perguntas penduradas fora do horário dele (16 perguntas somaram 47h de fluxo parado). Decisão
do usuário (20/07, sempre-ligado, sem flag): a camada 0 decide sozinha o que ele carimbaria —
com registro e disclosure — e só o que é genuinamente da alçada dele continua parando o fluxo.

Antes de disparar qualquer `AskUserQuestion` — venha de um `needs_decision` da camada 1, de um
stop herdado de comando rodando inline ou de um stop próprio do roteiro — classifique a decisão:

**Gate duro — para e espera o usuário** quando QUALQUER um destes vale:
1. **Informação externa** — a resposta é fato que só o usuário tem: credencial, acesso, estado
   do cliente ou do mundo ("a regra estabilizou?", "o staging existe?"). Ele não escolhe entre
   opções; ele fornece o insumo. (Inventário: 23% de carimbo nessa classe — o humano informa,
   não carimba.)
2. **Escopo/intenção** — aprovar ou alterar requisito, critério de aceite, oráculo de verdade,
   SPEC/CONTEXT/ROADMAP (inclui a pausa da revisão de intenção da Etapa 0-B). É onde escopo
   novo nasce nas respostas dele; auto-aprovar aqui é o carimbo invertido que a revisão
   adversarial existe para impedir.
3. **Irreversível fora do trilho** — rotacionar/expor credencial, apagar dado, gastar dinheiro,
   mexer em produção, merge. (O trilho sancionado — fase verde até o **PR** — já é o default e
   não pergunta; é o merge para além do PR que fica com o dono.)
4. **Sem recomendada** — nem você nem o subagente têm uma recomendação com convicção. Confissão
   de incerteza sobe ao usuário em qualquer categoria (no inventário, a taxa de carimbo despenca
   exatamente quando não há recomendada).
5. **Fail-closed existentes** — ameaça aberta (4.4), balde 2 persistente (5.5), balde 3
   (6.4-HB), gaps (3.5), `blocked`, gate de contexto: a triagem não afrouxa nenhum deles.

**Auto-decisão — decide, registra e segue** quando NENHUM critério acima vale E existe opção
recomendada com convicção E o erro é barato de desfazer (um edit, um re-run, um revert). Cobre o
miolo medido: condução do pipeline (re-rodar um gate, ordem de passos, housekeeping), decisão de
produto pontual e reversível, tratamento de erro com fix claro. Desempate: entre duas opções
viáveis, a **mais rigorosa** — o histórico mostra que quando o usuário diverge é para endurecer
(mais rodadas, pesquisar antes, pausar), quase nunca para afrouxar.

Mecânica da auto-decisão:
1. Decida pela opção que você recomendaria. Num `needs_decision`, a `recomendacao` do subagente
   é insumo, não veredito — a camada 0 é quem assina (e um `reversivel: nao` do subagente joga
   direto pro gate duro, critério 3).
2. Registre em `<phase_dir>/NN-DECISOES.md` (crie no primeiro uso da rodada): hora
   (`date "+%F %H:%M"`), etapa, a pergunta em 1 linha, as opções consideradas, a escolhida, o
   porquê em 1–2 linhas e **como desfazer**. Imprima uma linha ao usuário
   (`🤖 decidi sozinho: <escolha> — registrado no NN-DECISOES.md`) — auto-decisão silenciosa é
   bug da mesma família do passo pulado sem disclosure.
3. Siga o fluxo. Num `needs_decision`, continue o MESMO subagente com o rótulo honesto da
   Sub-rotina H: **"decisão da camada 0 (triagem): X"** — nunca "decisão do usuário".

**Decisões de timing também são decisões.** Escolher QUANDO envolver o dono — "não vou
interrompê-lo agora, os gates ficam para a retomada", adiar uma pergunta para o fim da wave,
segurar um aviso até o resumo — passa pela mesma mecânica: entrada no `NN-DECISOES.md` com
critério, porquê e desfazer (ex.: "perguntar agora mesmo assim"). Caso real (F16-ox, 23/07): a
escolha de não interromper o dono no gate do 16-12 foi narrada no chat mas não registrada — a
narração se perde; o registro é o que o resumo e a auditoria releem.

**Janela de silêncio (23h–07h locais):** um gate duro fora dela pergunta normalmente via
`AskUserQuestion`. Dentro dela (confira `date +%H` no momento do gate), não pendure a pergunta
de madrugada: feche com **parada graciosa** (Sub-rotina D) com motivo
`gate duro em janela de silêncio`, registrando a pergunta pendente (opções + recomendação) no
handoff e no resumo parcial — o usuário acorda, lê o panorama e retoma com `/go-and-do N`, que
re-apresenta a pergunta na retomada. A janela não se aplica à auto-decisão (que nunca para) e
não muda os fail-closed (que já fecham por Sub-rotina D de qualquer jeito).

A transparência fecha o ciclo: o resumo executivo (Sub-rotina F) narra toda auto-decisão da
rodada lendo o `NN-DECISOES.md` — a supervisão que era síncrona (fluxo parado esperando clique)
vira assíncrona (revisão no fim, com rota de desfazer anotada).

</subroutine>

</subroutines>

---

<stages>

<stage id="0" name="Preparação">

## Etapa 0 — Preparação

**0.1 — Argumentos.** Pegue o número da fase (primeiro número) e detecte as flags: `--ui`, `--ai`,
`--no-ship`, `--vault <profile>` (o token seguinte a `--vault` é o nome do profile) e
`--obs "<texto livre>"` (o valor é tudo entre aspas logo após `--obs`; sem aspas, tudo até a
próxima flag reconhecida ou o fim dos argumentos).
Sem número → **pare** e peça o número da fase. Guarde `--no-ship` (decide a rota terminal da
Etapa 6), o `vault_profile` (passado ao subagente de UAT na 5.4) e o `obs_text` (repassado como
nota a **todo** subagente despachado nesta rodada — Sub-rotina H).

**0.2 — Retrato da fase.** Rode Bash com o **shim da Sub-rotina E** no mesmo bloco, depois
`gsd_run query init.phase-op N`. Guarde o JSON (`planning_exists`, `phase_found`,
`has_context`, `has_plans`, `has_verification`, `phase_dir`, `padded_phase`). Se o shim não
achar o `gsd-tools.cjs` (sai com `ERROR`), trate como portão de entrada (0.3) e **pare**.

**0.3 — Portões de entrada (stop points).** Em ordem:
1. `planning_exists` falso → **pare**: "não é um projeto GSD aqui".
2. `phase_found` falso → **pare**: "fase N não está no ROADMAP (número errado?)".

> `has_context` falso **não é mais portão de entrada**: a Etapa 0-B gera o SPEC e o CONTEXT
> quando faltam (e submete a intenção à revisão adversarial). A skill não "inventa contexto" —
> ela o deriva do ROADMAP/REQUIREMENTS com defaults logados e um cético de máquina conferindo.

**0.4 — Retomada + telemetria + lista de tarefas.** Use o retrato pra saber o que pular:
`has_plans` → pula a Etapa 0-B (Intenção) e a Etapa 2 (Planejamento); `has_verification` → pula
a Etapa 3 (Construção). As Etapas 0-B (dentro dela), 1 (Contratos), 4 (Gates) e 5 (UAT) decidem
por estado de arquivo. Re-rodar nunca recomeça do zero. Com o `phase_dir` em mãos, registre
o evento `run` na telemetria (**Sub-rotina G**). Em seguida, monte a lista de
tarefas com a **Sub-rotina C** (mesmos sinais de disco) — assim
a retomada já nasce fiel ao que foi feito e à etapa que está em curso.

> Uma fase iniciada antes desta versão pode ter um `NN-PORTE.md` no diretório (artefato do
> classificador de porte, removido da skill em 2026-07-05 por decisão de custo-benefício —
> toda fase roda o pipeline completo). Ignore-o: ele não participa mais de nenhuma decisão.

**0.5 — Banner.** Imprima o banner de abertura na moldura padrão — caixa ASCII dupla num
bloco de código `text`:

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

Conteúdo dos campos: `Contratos` = flags UI/IA ligadas (que ligam tanto os contratos da
Etapa 1 quanto as auditorias da Etapa 4); `Rota` = rota terminal (`--no-ship` → "para no seu
UAT, sem shipar"; padrão → "vai até abrir o PR"); `Vault` e `Obs` são linhas condicionais —
só entram se `--vault`/`obs_text` existirem (obs longo quebra em mais linhas `║`; mostre o
texto literal — é a nota que vai acompanhar toda etapa despachada nesta rodada). Alinhamento:
emoji ocupam ~2 colunas ao fechar a borda direita; ajuste a largura da moldura ao conteúdo.
Abaixo da caixa, uma linha solta: o usuário pode sair de perto.

</stage>

<stage id="0B" name="Intenção — spec + discuss + revisão adversarial">

## Etapa 0-B — Intenção (spec + discuss + revisão adversarial)

> Por que existe: spec e discuss eram manuais — e a entrevista interativa era um carimbo na
> prática (o usuário segue a recomendação em ~100% das vezes; a cerimônia não agrega julgamento).
> Esta etapa troca o carimbo humano por um **cético de máquina**: o Claude gera SPEC e CONTEXT
> sozinho (`--auto`, com cada escolha logada) e submete a intenção a uma revisão adversarial
> cross-AI — dois revisores externos (Codex + agy) tentam derrubar as decisões lendo o código de verdade, e o Claude verifica
> cada achado antes de aceitar. O usuário só é chamado quando um achado mexe no que é da alçada
> dele: requisito, critério de aceite ou oráculo de verdade.
>
> **Formato de capability (decisão de projeto):** esta etapa é autocontida de propósito —
> entrada: fase N no ROADMAP; saída: `NN-SPEC.md` + `NN-CONTEXT.md` revisados +
> `NN-INTENT-REVIEW.md` — para um dia ser extraída como contribution no hook `discuss:post`
> do GSD sem cirurgia. Não crie dependências daqui para outras etapas além dessas fronteiras.
> A fronteira agora é física: a etapa inteira roda num **subagente de camada 1**
> (`prompts/intent.md`); a camada 0 só decide se despacha e roteia o retorno.

**0B.1 — Retomada (camada 0 — decide por frontmatter e existência, nunca por corpo).**
- `has_plans` (ou `has_verification`) verdadeiro → **pule a Etapa 0-B inteira**: a intenção já
  virou plano, e revisá-la agora não muda o que foi planejado (mudança de intenção pós-plano é
  replanejamento — fora do escopo desta etapa).
- Existe `<phase_dir>/NN-INTENT-REVIEW.md` com `intent_review: done` — ou `skipped`
  (revisão pulada por ausência total de revisores externos: estado final, não pendência;
  o sino do pulo já está no frontmatter e a 6.2 o recolhe) — (cheque só o frontmatter,
  ex.: `head -15 ... | grep intent_review`) → a intenção está pronta: pule a Etapa
  0-B inteira.
- Qualquer outro estado (artefatos de intenção faltando; `intent_review: blocked` — o bloqueio
  pode ter sido resolvido; `intent_review: needs_decision` — há pergunta pendente) →
  **despache** (0B.2). A retomada fina — o que re-rodar e o que pular, arquivo a arquivo — é
  do subagente, que decide pelo disco (`prompts/intent.md`, seção de chegada).

**0B.2 — Despacho do subagente de intenção.** Gate de contexto (Sub-rotina A). Despache pela
**Sub-rotina H** com `prompts/intent.md`: um único subagente executa, na própria janela, o
SPEC (`gsd-spec-phase N --auto`) → o CONTEXT (`gsd-discuss-phase N --auto`, sem executar o
`auto_advance` e zerando `workflow._auto_chain_active` — a neutralização dos 2 efeitos
colaterais do `--auto`) → a revisão adversarial cross-AI (Codex + agy criticam, o subagente
verifica cada achado contra o código antes de aceitar, loop ≤ 3 ciclos, fail-closed no piso
de "pelo menos um revisor"). O
despacho leva `N`, `NN`, `phase_dir` e `project_root` — caminhos absolutos — e, numa
continuação de pausa, a resposta do usuário verbatim.
> Por que um subagente: o bloco de intenção media ~140–165k tokens de eco de orquestração na
> janela da camada 0 (medido em fases reais) — o orquestrador chegava ao plano com metade da
> janela gasta. O trabalho é o mesmo; a janela que o hospeda agora é descartável.

**0B.3 — Roteamento do retorno.** Pelo `estado` do bloco compacto que o subagente devolve:
- **`done`** → registre o evento `end` com `subagent_tokens` (Sub-rotina G), atualize as
  tarefas 1–3 (Sub-rotina C), e guarde do retorno: `transparencia` (insumo da 6.2 — a fonte
  durável é o frontmatter do `NN-INTENT-REVIEW.md`), os itens `sinos` pro banner (dimensões
  de ambiguidade abaixo do mínimo; `ciclo_final_nao_rodou`) e anuncie `pausas_de_negocio`
  numa linha ao usuário (o resumo executivo as narra lendo o próprio `NN-INTENT-REVIEW.md` —
  a Sub-rotina F já recebe o artefato na lista de leitura). Se os `sinos` trazem **revisão
  pulada** (`intent_review: skipped` — nenhum revisor externo instalado), registre também o
  evento `skip` da revisão (Sub-rotina G, motivo `ferramenta indisponível`), declare numa
  linha ao usuário e carregue o item para os `itens_nao_rodados` da 6.2 — é transparência
  de topo de resumo, não rodapé. Siga pra Etapa 1.
- **`needs_decision`** — achado confirmado que mexe em **requisito, critério de aceite ou
  oráculo de verdade**, ou impasse de estagnação (⏸️ stop point próprio desta skill: a alçada
  é do usuário, não da máquina — **gate duro por definição na triagem da Sub-rotina I**, critério
  de escopo/intenção; na janela de silêncio vira parada graciosa em vez de pergunta pendurada) →
  apresente as perguntas via `AskUserQuestion` (a recomendação
  do subagente vem primeiro nas opções) e **continue o MESMO subagente** com as respostas
  verbatim (Sub-rotina H — não redespache: a continuação preserva o contexto dele e não
  re-executa nada; observe o **rótulo honesto** da Sub-H: resposta que é pergunta não é
  decisão — responda e re-pergunte antes de continuar). Depois, roteie o novo retorno por
  esta mesma lista.
- **`blocked`** — os DOIS revisores (Codex e agy) instalados mas falhos sem nenhum ciclo
  completo (ausência total de revisores não chega aqui — vira `skipped` no pré-check do
  subagente e desce no `done` com sino) → **pare** via
  **Sub-rotina D** (fail-closed, decisão do usuário em 2026-07-02: sem segunda opinião a
  intenção não segue; um só revisor falho NÃO bloqueia — desce degradado com sino). O
  `intent_review: blocked` já está gravado no disco (o subagente grava
  antes de subir — é o que faz a próxima invocação re-tentar a revisão). A linha de handoff
  diz a ação exata: "🔔 revisão de intenção bloqueada — autentique um dos revisores
  (`codex login` / `agy`) e re-rode `/go-and-do N`; a skill retoma exatamente na revisão."

</stage>

<stage id="1" name="Contratos de design">

## Etapa 1 — Contratos de design

> Por quê antes do planejamento: o `gsd-plan-phase` consome `UI-SPEC.md`/`AI-SPEC.md` como
> contexto de design travado, e os gates de UI/eval da Etapa 4 auditam contra eles. Rodar os
> contratos aqui dá ao planner esse insumo e fecha o loop com as auditorias do fim.

**1.1 — Retomada (por existência de arquivo).** Sem `--ui` e sem `--ai` → **pule a Etapa 1
inteira**. Com `--ui` e já existe `<phase_dir>/NN-UI-SPEC.md` → pule o sub-passo de UI (não chame
o comando — isso evita o `AskUserQuestion` "Existing UI-SPEC: Update/View/Skip" do ui-phase). Idem
`--ai`/`NN-AI-SPEC.md`. (O `init.phase-op` não rastreia esses artefatos; a retomada é só por arquivo.)

**1.2 — Contrato de UI · só com `--ui`.**
- Gate de contexto (Sub-rotina A).
- `Skill gsd-ui-phase` com args `N`. Orquestra `gsd-ui-researcher` → `gsd-ui-checker` (com loop de
  revisão), gravando o `NN-UI-SPEC.md`.
  > Não passamos `--auto`: o ui-phase não parseia essa flag (é inerte). O que evita o prompt
  > "existing spec" é a retomada-por-arquivo da 1.1 — quando o arquivo não existe, o comando roda
  > limpo (o prompt só dispara se já existe).
- Config `workflow.ui_phase: false` → o comando sai sozinho; degrada com elegância e segue
  (registre o evento `skip` com motivo `config` — fecha o checkpoint desta etapa no JSONL).
- Herdadas (deixe chegar ao usuário): **UI-SPEC BLOCKED**; **revision stall** (máx 2). Ver "Paradas herdadas".

**1.3 — Contrato de IA · só com `--ai`.**
- Gate de contexto (Sub-rotina A).
- `Skill gsd-ai-integration-phase` com args `N`. Encadeia internamente
  `gsd-framework-selector` → `gsd-ai-researcher` → `gsd-domain-researcher` → `gsd-eval-planner`,
  gravando o `NN-AI-SPEC.md`.
  > A **entrevista do framework-selector** dispara quando o `CONTEXT.md` não cobre as decisões de
  > IA (tipo de sistema, provider, linguagem, requisito). É uma decisão de arquitetura legítima —
  > deixe chegar ao usuário (não se automatiza a escolha do framework às cegas). Se o `discuss-phase`
  > cobriu essas decisões, o selector pula a entrevista e segue sozinho.
- Config `workflow.ai_integration_phase: false` → o comando sai sozinho; degrada e segue
  (registre o evento `skip` com motivo `config`).
- Herdada: **AI validation fail** (SPEC incompleto → re-run / continuar). Ver "Paradas herdadas".

**1.4 — Ordem com ambas as flags.** Rode UI (1.2) **antes** de IA (1.3) — ordem fixa e
determinística (são arquivos disjuntos; a ordem só importa pra reprodutibilidade).

</stage>

<stage id="2" name="Planejamento">

## Etapa 2 — Planejamento

**2.1 — Retomada.** `has_plans` verdadeiro → pule pra Etapa 3.

**2.2 — Gate de contexto** (Sub-rotina A).

**2.3 — Planejar (via subagente).** Despache pela **Sub-rotina H** com `prompts/plan.md`
(leva `N`, `NN`, `phase_dir`, `project_root` absolutos e os args `N --tdd --research`): o
subagente hospeda o `gsd-plan-phase` — internamente ele pesquisa → planeja → verifica em
loop, tudo em agentes próprios (camada 2). O porquê das flags (e das paradas herdadas de
coverage/split/stall, que sobem como `needs_decision`) mora no próprio `plan.md`.
> Por que um subagente: o planejamento media +64–73k de eco de orquestração na janela da
> camada 0 (medido em fases reais) — leitura de contexto que desce quase inteira.
- Roteamento do retorno:
  - `done · planejado` → `end` com `subagent_tokens` (Sub-rotina G); anote
    `planos_nao_autonomos` (confere com a pré-detecção da 3.1b) e os `sinos`; siga pra 2.4.
  - `done · sem_plano` → registre o `end` e o evento `stop` (etapa `pausa: planejamento sem
    plano`), **pare** e avise (o planejamento não produziu plano).
  - `needs_decision` → pergunta ao usuário + **continuação do MESMO subagente** com a
    resposta (Sub-rotina H); roteie o novo retorno por esta lista.
  - `blocked` → registre o evento `stop` (Sub-rotina G, etapa `pausa: planejamento
    indisponível`), **pare** e reporte (re-rodar `/go-and-do N` retoma aqui).

**2.4 — Confirma (camada 0 — verificação independente).** Re-rode (shim da Sub-rotina E +
`gsd_run query init.phase-op N`): `has_plans` virou `true`? Se não → registre o evento `stop`
(etapa `pausa: planejamento sem plano`), **pare** e avise (o planejamento não produziu plano
— não confie só no retorno do subagente).

</stage>

<stage id="3" name="Construção">

## Etapa 3 — Construção

**3.1 — Retomada.** `has_verification` verdadeiro → pule a Etapa 3 inteira.

**3.1b — Pré-detecção de ações humanas.** Antes de construir, rode Bash (shim da Sub-rotina E +
`gsd_run query phase-plan-index N`). Leia `has_checkpoints` e, por plano, `autonomous`/`wave`.
Se houver planos `autonomous: false`, avise numa linha **antes de começar** (ex.: "a fase tem
2 planos não-autônomos — 03-03, 03-05; sob `--auto` verificações e decisões são automáticas,
mas se algum exigir uma AÇÃO sua — migration, login, 2FA — o execute vai parar nele"). Tudo
autônomo → siga sem alarde. Isto é **só um aviso**: não reordena nem pula nada — o motor de
waves do GSD já ordena por dependência, e essa é a única ordenação possível. O resultado real
(o que rodou e o que travou) é apurado na 3.4 e reportado no banner final.

**3.2 — Convergência do plano (via subagente).**
- **Retomada (por arquivo):** existe `<phase_dir>/NN-CONVERGENCE.md` com
  `convergence: done` (cheque só o frontmatter)? → a revisão cruzada já convergiu numa
  rodada anterior: pule a 3.2 inteira (a retomada da Etapa 3 só enxerga
  `has_verification`, que vira `true` bem depois — sem este marcador, um crash entre a
  convergência e o fim do execute re-pagaria a revisão inteira).
- **Gate de config (camada 0 — barato, sem gastar um subagente à toa):** rode Bash
  (shim da Sub-rotina E no mesmo bloco)
  `gsd_run query config-get workflow.plan_review_convergence`. Veio `false` ou vazio →
  registre o `skip` com motivo `config` (fecha a medição da etapa no JSONL), siga com o
  plano da Etapa 2 (degradação declarada) e **não despache**.
- **Pré-check de revisores (camada 0 — mesmo bloco Bash):** `command -v codex; command -v agy`.
  **Nenhum dos dois instalado** → registre o `skip` com motivo `ferramenta indisponível:
  nenhum revisor externo (codex/agy)`, declare numa linha ao usuário, carregue o item para
  os `itens_nao_rodados` da 6.2 e **não despache** — mesma degradação declarada do gate de
  config (despachar a revisão cruzada sem nenhum revisor externo só queimaria um subagente
  para voltar `blocked`). Um instalado → despache normal (o comando degrada mono-revisor
  sozinho e reporta em `revisores_efetivos`).
- Gate de contexto (Sub-rotina A). Despache pela **Sub-rotina H** com
  `prompts/convergence.md` (leva `N`, `NN`, `phase_dir`, `project_root` absolutos): o
  subagente hospeda o `gsd-plan-review-convergence --codex --agy --max-cycles 4` — o
  plano já existe, então ele vai direto pra revisão cruzada; ao convergir, ele grava e
  commita o marcador `NN-CONVERGENCE.md`.
  > Por que `--max-cycles 4`: o default do comando é 3, e estourar o teto com pendências
  > dispara uma pergunta interativa ("proceed anyway / manual review") que, à noite,
  > deixava o workflow pendurado num AskUserQuestion (caso real: fase 15 do oxmuscle-v2,
  > 2h30 da madrugada). O 4º ciclo é a margem que o usuário sempre autorizava — agora
  > pré-concedida. Se nem o 4º convergir, o subagente devolve `escalou` (nunca
  > `needs_decision` para a pergunta de teto — regra no `convergence.md`) e a parada é
  > graciosa: impasse mastigado, sem pergunta pendurada.
  > Por que um subagente: a convergência é risco de cauda — em fases reais ela matou uma
  > sessão por estouro de contexto e levou ~68min/3 ciclos em outra; o eco dos ciclos agora
  > fica numa janela descartável.
  > Por que `--codex --agy`: dois revisores independentes desde 2026-07-22 (o GSD 1.8.0
  > destravou a whitelist para `--agy` — o gap upstream que segurava a convergência
  > Codex-only fechou). Flags explícitas de propósito, não a invocação sem flags que lê
  > `review.default_reviewers` — a skill não depende de config que instaladores editam.
  > Um revisor falho no ciclo → segue com o outro, degradação em `sinos`, nunca
  > silenciosa (disciplina completa no `prompts/convergence.md`).
- Roteamento do retorno:
  - `done · convergiu` → `end` com `subagent_tokens` (Sub-rotina G); anote
    `revisores_efetivos`/`sinos` (degradação de revisor — ex.: agy com stdout vazio —
    vira item de transparência, nunca silêncio) e siga.
  - `done · config_off` (não deveria acontecer — o gate acima checa antes) → trate como o
    gate: registre o `skip` com motivo `config`, declare e siga.
  - `done · escalou` → registre o `end` (a etapa rodou; o desfecho é impasse) e o evento
    `stop` (etapa `pausa: convergência escalou`), **pare** e entregue o impasse (o retorno já
    o traz mastigado).
  - `needs_decision` → pergunta ao usuário + **continuação do MESMO subagente** com a
    resposta (Sub-rotina H); roteie o novo retorno por esta lista.
  - `blocked` → registre o evento `stop` (Sub-rotina G, etapa `pausa: convergência
    indisponível`), **pare** e reporte o motivo: a revisão cruzada não aconteceu; você
    decide re-tentar (`/go-and-do N` retoma aqui) ou desligar o gate na config do projeto.

**3.3 — Execução.** Gate de contexto (Sub-rotina A). A rota depende da pré-detecção da 3.1b
(re-conferida com o `planos_nao_autonomos` do retorno da 2.3):

- **Todos os planos pendentes são autônomos → via subagente.** Despache pela **Sub-rotina H**
  com `prompts/execute.md` (leva `N`, `NN`, `phase_dir`, `project_root` absolutos e os args
  `N --auto --no-transition`): o subagente hospeda o `gsd-execute-phase` — ondas de
  `gsd-executor` (camada 2) → código + commits + `SUMMARY.md` → verificação →
  `VERIFICATION.md`. O porquê das flags e o tratamento das paradas herdadas
  (regressão/schema/conflito → `needs_decision`; ação humana → `done · incompleto`) moram no
  próprio `execute.md`.
  > Por que um subagente: o execute é o maior custo isolado da fase (+82–115k de eco de
  > coordenação na camada 0, medido em fases reais) — e foi um salto de +300k dele, num único
  > passo inline, que causou o único auto-compact observado. Descer elimina o salto na origem.
  - Roteamento do retorno: `done` (qualquer veredito) → `end` com `subagent_tokens`
    (Sub-rotina G) e siga pra 3.4 — a encruzilhada apura pelo disco, não pelo retorno (um
    `veredito: incompleto` vai desaguar na Sub-rotina D dela). `needs_decision` → pergunta ao
    usuário + **continuação do MESMO subagente** (Sub-rotina H); roteie o novo retorno.
    `blocked` → registre o evento `stop` (etapa `pausa: execução indisponível`), **pare** e
    reporte.

- **Há plano `autonomous: false` pendente → inline (como sempre foi).** `Skill
  gsd-execute-phase` com args `--auto --no-transition`, na camada 0 — um plano não-autônomo
  tem chance real de precisar de VOCÊ no meio (ação humana, decisão de gasto), e a interação
  é nativa aqui; despachá-lo só adicionaria ida-e-volta de pergunta a cada parada.
  > Havendo `obs_text`: não há prompt de despacho pra prefixar (é a própria camada 0 que roda o
  > comando) — a nota já está visível no banner da 0.5; leve-a em conta ao acompanhar a execução.
  > **Por que `--auto --no-transition`:** `--auto` liga o `AUTO_MODE` do executor —
  > checkpoints de verificação são auto-aprovados e checkpoints de decisão pegam a
  > 1ª opção. `--no-transition` impede o auto-avanço pra próxima fase.
  > *(Sem `--tdd`: o execute-phase não parseia essa flag — o TDD liga só por
  > `workflow.tdd_mode: true` na config, honrado a partir do plan-phase.)*
  > ✋ **`--auto` não silencia tudo:** falha de regressão, schema drift, conflito pós-merge e
  > gates de auth (`human-action`) continuam parando — e devem (ver "Paradas herdadas").
  > 🤝 **Se um plano exige a SUA ação** e você defere (ou sai), a **3.4** detecta a execução
  > incompleta e fecha com a **Sub-rotina D** (pause-work) — a skill não interrompe um
  > `Skill` no meio; o tratamento honesto acontece **na volta**, pela checagem da 3.4.

> ⚖️ **Trade-off do `--auto` (consciente, nas duas rotas):** decisões de arquitetura são
> tomadas no automático (1ª opção) sem te consultar. Aceitável porque a skill manda toda
> "lógica" pro UAT e trata `human_needed` — mas essa autonomia tem esse custo.

> 🧪 **Economia de testes (nas duas rotas; princípio agnóstico de stack):** a suíte completa
> de testes é gate, não feedback — roda no máximo 1× por wave, como check independente ao
> final dela; o feedback do ciclo de TDD são os testes do escopo tocado. Timeout de run de
> suíte se dimensiona pela duração já medida (folga ≥2×), nunca pelo default às cegas. Os
> parâmetros por projeto (comando da suíte, flags de paralelização, o que fica serial) vivem
> no CLAUDE.md do projeto — esta skill carrega o princípio, não o pytest. Racional: na F16,
> 58% da execução foi suíte de teste, com ~1h45 de re-verificação duplicada e ~35min de runs
> mortos por timeout (auditoria 170726-inspired-f16).

**3.4 — Encruzilhada.** Primeiro, **cheque a completude da execução**: re-rode
(shim da Sub-rotina E + `gsd_run query phase-plan-index N`) e veja se sobrou algum plano sem `SUMMARY.md`. Se sobrou — o
execute parou num plano que exige a **sua ação** (`human-action`: migration, auth) e as ondas
dependentes não rodaram — então classifique como **execução incompleta — bloqueada** e vá
direto pra **Sub-rotina D** (parada graciosa), citando a ação exata e os planos pendentes.
**Não** trate isso como `human_needed` nem siga pra Etapa 4.

Se todos os planos têm `SUMMARY.md`, leia o status do `VERIFICATION.md`:
- **ausente** (tudo executado, mas a verificação nunca rodou — ex.: sessão morreu entre as
  ondas e o verify) → re-execute pela regra de rota da 3.3: a idempotência do execute-phase
  pula os planos prontos e vai direto à verificação. Persistiu ausente → **Sub-rotina D**.
- `passed` → segue pra Etapa 4.
- `human_needed` → não é erro; anota e segue. *(Verificação de fim de fase: esses itens viram
  insumo PENDING do UAT (Etapa 5), retomados depois pelo `/gsd-verify-work`; não disparam
  pause-work.)*
- `gaps_found` → fechamento de gaps, 1 tentativa (3.5).

**3.5 — Fechamento de gaps (1× só):**
1. Replaneja só correções: despacho da 2.3 (`prompts/plan.md`) com args `N --gaps`.
2. Re-executa: mesma regra de rota da 3.3 — planos de gap autônomos → despacho
   (`prompts/execute.md`, args `N --auto --no-transition`); senão inline.
3. Re-verifica.
- `passed`/`human_needed` → segue pra Etapa 4.
- ainda `gaps_found` → **Sub-rotina D** (parada graciosa), motivo `gaps persistentes`.
> Só 1 tentativa: pra não entrar em loop caro; o resto merece decisão humana.

</stage>

<stage id="4" name="Gates de qualidade">

## Etapa 4 — Gates de qualidade

> Retomada por existência de arquivo aqui (o `init.phase-op` não rastreia estes
> artefatos). Antes de cada gate desta etapa — todos eles, não só o primeiro — cheque
> se o arquivo já existe na `<phase_dir>`; se sim, pule. Isso também evita o
> `AskUserQuestion` ("Re-audit/View") que alguns comandos disparam quando o arquivo já
> existe, e que travaria o pipeline.

### 4.1 — Code review (via subagente)
- Gate de contexto.
- Retomada: existe `<phase_dir>/NN-REVIEW.md`? → pule.
- Despache pela **Sub-rotina H** com `prompts/code-review.md` (leva `N`, `NN`, `phase_dir`,
  `project_root` absolutos): o subagente hospeda o `gsd-code-review N --fix --auto` — sem
  `--all` (Info é cosmético, não vale o risco do fixer mexer às cegas); o escopo de arquivos
  sai dos `SUMMARY.md`. O fixer corrige Critical+Warning em worktree isolado, loop
  corrige→re-revisa até 3×; correções de lógica ele marca `requires human verification`.
- Roteamento do retorno: `done` → `end` com `subagent_tokens` (Sub-rotina G); guarde
  `uat_humano` (é passado ao despacho da derivação do UAT, 5.3) e os `sinos`. Decisão:
  sempre segue (não para); Critical restante → 🔔 forte no banner final.
  `needs_decision` → pergunta ao usuário + continuação do MESMO subagente (Sub-rotina H);
  roteie o novo retorno. `blocked` → registre o evento `stop` (Sub-rotina G, etapa
  `pausa: code review indisponível`), **pare** e reporte (o review não aconteceu —
  re-rodar `/go-and-do N` retoma aqui).

### 4.2 — UI review · só com `--ui`
- Sem `--ui` → pule o gate inteiro.
- Gate de contexto.
- Retomada: existe `<phase_dir>/NN-UI-REVIEW.md`? → pule (nem chame o comando).
- Sobe o dev server (Sub-rotina B) pra auditoria ver a tela renderizada.
- Tela auditada atrás de login? Prepare o acesso sancionado ANTES (wrapper/helper — regra de
  credenciais da Sub-rotina H) e passe-o à auditoria junto com a proibição literal de
  ler/dumpar `.env*`. Sem via sancionada → a página logada fica em code-only com ressalva
  registrada, nunca com login improvisado (caso real 21/07: o auditor escreveu um script para
  evadir o guard de `.env` e imprimiu senha+TOTP — contido, mas era exatamente isto que
  faltava aqui).
- `Skill gsd-ui-review` com args `N`. O auditor detecta o servidor e tira screenshots.
- Derruba o dev server (cleanup — Sub-rotina B). Não subiu no timeout → segue em
  code-only e registra a ressalva.
- O gate dá nota 1-4 em 6 pilares (/24) + Top 3 + Registry Safety (se shadcn de
  terceiros). Não corrige nada — diagnóstico.
- Decisão: sempre segue. 🔔 forte se algum pilar tirar 1 ou 2 OU houver flag de
  Registry Safety.

### 4.3 — Eval review · só com `--ai` (via subagente)
- Sem `--ai` → pule.
- Gate de contexto.
- Retomada: existe `<phase_dir>/NN-EVAL-REVIEW.md`? → pule.
- Despache pela **Sub-rotina H** com `prompts/eval-review.md` (leva `N`, `NN`, `phase_dir`,
  `project_root` absolutos): o subagente hospeda o `gsd-eval-review N`.
  - State A: existe `AI-SPEC.md` → auditoria completa contra o plano de eval. *(Com `--ai`, a
    Etapa 1 já gerou o `AI-SPEC.md` — então o caminho normal aqui é o State A.)*
  - State B: sem `AI-SPEC.md` → audita contra boas práticas (sinal mais fraco);
    registra no banner que foi State B.
  - O auditor marca dimensões COVERED/PARTIAL/MISSING + 5 itens de infra + score /100 +
    veredito. Não corrige nada.
- Roteamento do retorno: `done` → `end` com `subagent_tokens` (Sub-rotina G); guarde os
  `sinos`. Decisão: sempre segue. 🔔 forte se veredito não for PRODUCTION READY
  (score < 80) ou houver critical gaps > 0. `needs_decision` → pergunta ao usuário +
  continuação do MESMO subagente (Sub-rotina H); roteie o novo retorno. `blocked` →
  registre o evento `stop` (Sub-rotina G, etapa `pausa: eval review indisponível`),
  **pare** e reporte (a auditoria não aconteceu — re-rodar `/go-and-do N` retoma aqui).

### 4.4 — Secure phase (via subagente)
- Gate de contexto.
- Retomada: existe `<phase_dir>/NN-SECURITY.md` **com `threats_open: 0` E sem o marcador
  `aceites_sem_dono`**? → pule. (Existe com ameaças abertas, com `aceites_sem_dono` no
  frontmatter, ou não existe → roda. O marcador é gravado pelo subagente quando encontra
  riscos "aceitos" sem decisão do usuário rastreável — o arquivo já está no estado "bom",
  e sem essa checagem a retomada pularia o gate com um aceite órfão dentro.)
- Despache pela **Sub-rotina H** com `prompts/secure.md` (leva `N`, `NN`, `phase_dir`,
  `project_root` absolutos): o subagente hospeda o `gsd-secure-phase N` — verifica as
  mitigações do threat model dos `PLAN.md` no código (sem threat model, STRIDE
  retroativo). A varredura desce; a decisão sobre ameaça aberta sobe.
- Roteamento do retorno:
  - `done · secured` (`threats_open: 0`) → `end` com `subagent_tokens` (Sub-rotina G);
    guarde `riscos_aceitos`/`sinos` — a lista `riscos_aceitos` entra no bloco de
    transparência da 6.2 e chega ao resumo (Sub-F) — e siga.
  - `done · ameacas_abertas` → registre o `end` (a auditoria rodou; o desfecho é
    bloqueio), **pare** via **Sub-rotina D** (motivo `ameaça de segurança aberta`) —
    este é o stop point onde a autonomia legitimamente cede (segurança não se
    auto-aceita). 🔔 forte.
  - `needs_decision` (a decisão Verify/Accept de cada ameaça, mastigada) → pergunta ao
    usuário + **continuação do MESMO subagente** (Sub-rotina H); roteie o novo retorno.
  - `blocked` → registre o evento `stop` (etapa `pausa: secure indisponível`), **pare**
    e reporte (re-rodar `/go-and-do N` retoma aqui).

### 4.5 — Validate phase (via subagente)
- Gate de contexto.
- Retomada: existe `<phase_dir>/NN-VALIDATION.md` com `nyquist_compliant: true` **ou** com o
  marcador custom `go_and_do_validate: done`? → pule. (O marcador é gravado pelo subagente ao
  concluir com veredito `partial` — desfecho terminal que não bloqueia; sem ele, toda retomada
  posterior re-pagaria o auditor e re-perguntaria a estratégia que você já decidiu.)
- Despache pela **Sub-rotina H** com `prompts/validate.md` (leva `N`, `NN`, `phase_dir`,
  `project_root` absolutos): o subagente hospeda o `gsd-validate-phase N` — mapeia
  requisito↔teste (COVERED/PARTIAL/MISSING) e pode gerar os testes faltantes. Não
  bloqueia a fase.
- Roteamento do retorno:
  - `done` (`nyquist_compliant` ou `partial`) → `end` com `subagent_tokens`
    (Sub-rotina G); `partial` → 🔔 no banner (validação *partial* já era item da 6.2).
    Siga.
  - `needs_decision` (a escolha Fix all / Skip manual-only, mastigada — "Fix all" gera
    os testes agora, commitados, e o add-tests manual depois os enxerga) → pergunta ao
    usuário + **continuação do MESMO subagente** (Sub-rotina H); roteie o novo retorno.
  - `blocked` → registre o evento `stop` (etapa `pausa: validate indisponível`),
    **pare** e reporte (re-rodar `/go-and-do N` retoma aqui).

</stage>

<stage id="5" name="UAT interativo automatizado">

## Etapa 5 — UAT interativo automatizado

> Por que UAT própria, não `verify-work` cru: o verify-work é interativo (pergunta teste a teste),
> auto-diagnostica e auto-transiciona. Reusamos a LÓGICA de derivação dele (5.3) e dirigimos o
> browser por conta própria (5.4, via subagente + `uat-playbook.md`). Diferença-chave em relação à
> versão anterior: o UAT agora **interage de verdade** (clica, preenche, percorre fluxos) e **prova
> objetivamente** (status HTTP + console + estado persistido), em vez de só navegar+screenshot. Isso
> move muitos cenários do antigo "PENDING por ser visual" para o balde "verificável".

**Os 4 baldes** (a craft completa está no `uat-playbook.md`; aqui o orquestrador só roteia por eles):
- **1 · pass** — prova objetiva fechou.
- **2 · issue** — falhou objetivamente → ciclo de conserto (5.5).
- **3 · não-pude-verificar** — login sem vault, 2FA, captcha, browser indisponível → `[pending]`/`blocked`; **bloqueia o ship** (Etapa 6 faz hand-back).
- **4 · assumed** — só sobra juízo subjetivo → shipa **com aviso** no resumo.

**5.1 — Retomada (por ESTADO do `NN-UAT.md`, não por mera existência).**
> O `NN-UAT.md` nasce no 5.3 todo `[pending]` e é preenchido em 5.4/5.5. Os cenários de balde 3
> ficam `[pending]`/`blocked` de propósito (pro `/gsd-verify-work` retomar via `resume_from_file`).
> Resuma pelo frontmatter (campos custom que o verify-work ignora) + os `result:` das linhas:

- `<phase_dir>/NN-UAT.md` **ausente** → vá pro 5.3 (gerar).
- existe, frontmatter **sem `pre_uat: executed`** → vá pro 5.4 (re-despacha o subagente; ele é
  idempotente por cenário — só processa o que não tem `result` definitivo).
- existe, `pre_uat: executed` + **alguma linha `result: issue`** + **sem** `pre_uat_fix_cycle: done`
  → vá pro 5.5 (1º — e único — ciclo de conserto).
- existe, `pre_uat: executed` + `result: issue` + **com** `pre_uat_fix_cycle: done` → o ciclo único
  já rodou e o bug não fechou → **Sub-rotina D** (não rode um 2º ciclo).
- existe, `pre_uat: executed` + **sem** `result: issue` em aberto → vá pra Etapa 6 (que roteia: se
  sobrou balde 3 → hand-back; senão → ship).

**5.2 — Gate de contexto** (Sub-rotina A).

**5.3 — Geração do `NN-UAT.md` (via SUBAGENTE).**
> Derivar cenários exige ler os `SUMMARY.md` — a operating_rule "não leia artefatos verbosos" + o
> gate de contexto proíbem ingerir isso no orquestrador. Um subagente lê, deriva e **escreve**.

Despache um `Agent` (`model: sonnet`, `run_in_background: false` — despacho síncrono, mesma
regra da Sub-rotina H) para reusar a lógica de derivação do `verify-work`:
- (a) **find_summaries** — lista os `SUMMARY.md` da fase.
- (b) **extract_tests** — comportamentos **user-observáveis** (pular refactors / mudanças de tipo);
  cenários visuais derivados do `NN-UI-SPEC.md` (ou do `SUMMARY.md` quando não há `--ui`).
  - **Cold-start smoke test:** injetar **apenas** quando algum `SUMMARY` tocou
    `server`/`app`/`index`/`main`/`db`/`migrations`/`seed`/`docker`. Limitar a **boot +
    health/homepage**. O "clear ephemeral state" (apagar DBs/caches) é **destrutivo** → marque
    `[pending]` pro humano, nunca automatize.
- (c) **create_uat_file** — a partir do template `$HOME/.claude/gsd-core/templates/UAT.md`,
  `status: testing`, todos os cenários `[pending]`. Frontmatter custom `pre_uat: generated`.
- (d) **insumos dos revisores** — inclua no despacho (e o subagente converte em cenários):
  os itens `uat_humano` do retorno da 4.1 (correções de lógica que o fixer marcou
  `requires human verification`) e os itens `human_needed` da 3.4. É aqui que o "vira UAT"
  prometido pelos revisores se materializa — sem isso, esses itens se perderiam entre a
  Etapa 4 e a 5.

O subagente retorna: `uat_path`, `total`, e por cenário o tipo `{logic|api|cli|boot|ui|judgment}`.

**5.4 — Execução do UAT (via SUBAGENTE — SEMPRE, com ou sem GUI).**
> Mudança de arquitetura: o subagente — **não** o orquestrador — dirige o browser. Dirigir é
> trabalho verboso (DOM/snapshots/network) que inundaria a janela do orquestrador e fura o gate de
> contexto. O subagente tem janela própria + o `browser_batch { summary_only }` é uma 2ª camada de
> proteção **dentro** dele. O orquestrador só coordena o server e lê o veredito compacto. (O comentário
> antigo "subagentes não dirigem o browser" estava desatualizado: um `Agent` general-purpose alcança
> os tools MCP `browser_*` por conta própria, independente da allowlist do orquestrador.)

> **Fase sem GUI NÃO é motivo para executar o UAT inline.** O playbook tem `<non_gui_surfaces>`
> (CLI/API/lib/agente — prova por status de saída/HTTP/comportamento) e `<push_on_it>` (probes
> adversariais 🔍) — ambos existem exatamente para fases de backend/banco/CLI, e só operam se o
> subagente for despachado com o playbook. Caso real (AOS-10, 07/07): o orquestrador julgou "não
> há o que dirigir" e fez o UAT inline — o resultado até saiu decente, mas sem nenhum probe 🔍 e
> sem `probes_executados`, e a janela da camada 0 pagou o custo. O despacho muda pouco: pula a
> Sub-rotina B (declarando "fase sem server — Sub-B não se aplica"), o prompt omite URL/porta e
> aponta as superfícies (ex.: "os cenários são api/logic — use `<non_gui_surfaces>`"). Se a prova
> ao vivo exige credenciais atrás da parede de segredos, o orquestrador PREPARA o acesso (wrapper
> tipo `scripts/run-<coisa>.sh` que injeta o env no processo, nunca no contexto; permissão pedida
> ao usuário se precisar) e o SUBAGENTE roda o wrapper — a condução, os baldes, os probes e a
> escrita do `NN-UAT.md` continuam sendo dele.

1. **Sobe o dev server** (Sub-rotina B) — o orquestrador é dono do ciclo de vida do server.
   Fase sem server: pule DECLARANDO (linha ao usuário + a nota no prompt do subagente).
   > **Cold-start primeiro:** se há cenário de cold-start (boot do zero), o orquestrador roda esse
   > **antes** de subir o server persistente (eles brigam pela porta) e grava o resultado dele;
   > depois sobe o server persistente pros demais cenários.
2. **Despacha o subagente de UAT.** `Agent` com `model: sonnet`, `subagent_type: general-purpose`
   e `run_in_background: false` (despacho síncrono — mesma regra da Sub-rotina H; o UAT é o
   despacho mais longo da fase, e em background a volta dele não retomaria o roteiro)
   (precisa de Bash + tools `browser_*` via MCP + Read/Write). Prompt mínimo:
   > "Leia `$HOME/.claude/skills/go-and-do/uat-playbook.md` e conduza o UAT da fase NN seguindo-o à
   > risca. O `NN-UAT.md` está em `<uat_path>`. [Com server:] O dev server está rodando em
   > `http://localhost:<PORT>` — **não** gerencie esse processo. Use a sessão `uat-fase-NN`.
   > [Sem GUI/server:] Esta fase não tem UI — os cenários são `api`/`logic`/`cli`; use a tabela
   > `<non_gui_surfaces>` do playbook e prove por saída objetiva. [Com wrapper de segredos:]
   > rode a prova ao vivo via `<caminho absoluto do wrapper>` — ele injeta as credenciais no
   > processo; não leia nem ecoe segredos. [Se `--vault <profile>`:] há um
   > profile de vault `<profile>` pra fluxos com login. Classifique cada cenário nos 4 baldes do
   > playbook, aplique o `<push_on_it>` nos cenários de balde 1, escreva os `result:` e os Gaps
   > YAML no `NN-UAT.md`, e — se o caminho feliz passar limpo — gere o teste Playwright (fases com
   > GUI). Devolva só o resumo compacto do `<return_contract>` (inclui `probes_executados`)."
3. **Derruba o dev server** (cleanup — Sub-rotina B).
4. **Lê o resumo compacto** do subagente (contagens por balde + os itens balde 3/balde 4 + caminho
   do teste gerado). **Não** ingira o `NN-UAT.md` inteiro.
5. Confirme que o subagente virou o frontmatter `pre_uat: generated` → `pre_uat: executed`. Se ele
   não conseguiu processar tudo (resumo incompleto), trate como retomável (5.1 re-despacha).

> O subagente **nunca** carimba `pass` no ambíguo (regra cardeal do playbook): incerteza → balde 3.
> Um `pass` falso é a surpresa que este UAT existe pra evitar.

**5.4b — Conversão de balde 3 por prova objetiva (via SUBAGENTE de investigação).** Um cenário
balde 3 às vezes é provável sem o humano — a limitação era do AMBIENTE do driver, não do
comportamento (caso real, F17: o dataset sintético do UAT não continha o caso R$ 1,2M/802426,
mas os goldens contra o dataset canônico provavam exatamente aquilo). Quando você enxergar uma
prova objetiva plausível (teste existente, golden, oráculo independente):
1. **Não investigue inline.** A caça à prova (ler testes, rodar suítes, analisar outputs) é
   leitura verbosa — exatamente o que a janela do orquestrador não pode pagar no fim da fase
   (caso real: a investigação inline da F17 empurrou o contexto a 99% do teto). Despache um
   `Agent` descartável (genérico, `run_in_background: false`) com este contrato: "Cenário
   balde-3: <descrição + por que o driver não pôde verificar>. Hipótese de prova: <onde você
   acha que ela mora>. Encontre e EXECUTE a prova objetiva (teste/golden/oráculo); vale
   reforçá-la com guardas (ex.: asserção do valor exato, espião anti-regressão). Devolva SÓ:
   veredito (provado/não-provável) + o comando executado + resultado + caminhos-ponteiro,
   ≤10 linhas. Não devolva output de teste nem conteúdo de arquivo. Se a prova depender de
   gosto/conteúdo ou de credencial ausente, devolva não-provável — isso é balde 3 legítimo."
2. Veredito `provado` → **continue o MESMO subagente de UAT** (Sub-rotina H) com a evidência
   compacta para ele reclassificar o cenário (ele reescreve o `NN-UAT.md`; a regra cardeal se
   mantém — quem carimba é o UAT, com prova em mãos, nunca você por conveniência).
3. Veredito `não-provável` → o cenário FICA balde 3 (rota de hand-back). Registre a tentativa
   numa linha (transparência: "tentei provar X por Y; não dava sem humano").

**5.5 — Ciclo de conserto (1× só) quando há balde 2 (`issue`).**
> 1 ciclo só: mesma disciplina do fechamento de gaps da Construção (3.5) — evita loop caro de contexto.
1. Gate de contexto.
2. Replaneja o conserto: despacho da 2.3 (`prompts/plan.md`) com args `N --gaps` (lê os
   gaps do `NN-UAT.md`).
3. Re-executa: mesma regra de rota da 3.3 — planos de gap autônomos → despacho
   (`prompts/execute.md`, args `N --auto --no-transition --gaps-only`); senão inline.
   > `--gaps-only` roda só os planos `gap_closure: true` — escopo estrito do conserto.
4. **Re-roda o code review** nos arquivos do fix: despacho da 4.1
   (`prompts/code-review.md`) com args `N --fix --auto --files=<arquivos alterados>` —
   **sem a checagem de retomada da 4.1** (o `NN-REVIEW.md` existente aqui é esperado, a
   4.1 já rodou; pular por causa dele furaria em silêncio a garantia "auditado antes do
   ship" pro código do fix).
   > O conserto mudou código **depois** dos gates da Etapa 4 — re-revisar restaura a garantia
   > "auditado antes do ship" pro código novo.
5. **Garante que a superfície re-testada reflete o código pós-fix.** Fase com server: reinicia
   (Sub-rotina B: derruba + sobe) — um server sem hot-reload serviria o código pré-fix, dando
   veredito falso. Fase sem server: nada a reiniciar, mas o mesmo risco existe em outra forma —
   se a superfície depende de artefato buildado (CLI compilado, pacote instalado), re-rode o
   passo de build/install antes do re-teste.
6. **Re-despacha o subagente de UAT (5.4 passo 2) só nos cenários `issue`.** Mesmo prompt, com a
   instrução extra de processar apenas os cenários que estavam `issue`.
7. **Grava `pre_uat_fix_cycle: done`** no frontmatter — a retomada (5.1) usa isso pra nunca disparar
   um 2º ciclo.
- Fechou (viraram pass/assumed) → Etapa 6.
- Persistiu → **Sub-rotina D** (parada graciosa), motivo `bug de UAT persistente`.

</stage>

<stage id="6" name="Encerramento + ship">

## Etapa 6 — Encerramento + ship

Só se chegou até aqui (se parou antes, a Sub-rotina D já fez o handoff). Esta etapa tem **duas
rotas terminais**: **ship** (caminho feliz) e **hand-back** (devolve sem shipar).

**6.1 — Roteia o desfecho** (lendo o resumo compacto do subagente da Etapa 5 + o estado da fase):
- **Sobrou balde 2** (bug não fechou após o ciclo único) → **Sub-rotina D** (pause-work). *(Já
  tratado na 5.5; esta é a rede.)*
- **Sobrou balde 3** (não-pude-verificar: login sem vault, 2FA, browser indisponível) **OU** a flag
  **`--no-ship`** → **rota de hand-back** (6.4-HB). A fase está completa e auditada, mas **não
  shipa**: ou porque há comportamento que ninguém confirmou (balde 3), ou porque você pediu pra
  conferir antes (`--no-ship`).
- **Só baldes 1+4** (objetivo limpo, sem balde 3) e **sem `--no-ship`** → **rota de ship** (6.4-SHIP).

**6.2 — Monta o "🔔 O que precisa de você agora" + o bloco de transparência.** Junte tudo que
merece atenção, mesmo o que seguiu sem parar: Criticals do code-review (+ itens `requires human
verification`); pilares de UI 1-2 / Registry Safety; eval abaixo de PRODUCTION READY; validação
*partial*; a ressalva `ciclo_final_nao_rodou` da revisão de intenção, se existir (a revisão
aconteceu, mas o ciclo final de confirmação do revisor não rodou). E monte os **itens do bloco de transparência** (insumo do resumo):
- **balde 4 (assumed)** — os itens subjetivos que vão ser **shipados assumidos** ("⚠️ Shipei
  assumindo estes pontos — confira antes de dar merge").
- **balde 3 (não-verificados)** — na rota de hand-back, o que **precisa da sua verificação**.
- **decisões de intenção (0-B)** — a lista `transparencia:` do frontmatter do
  `NN-INTENT-REVIEW.md` (tradeoffs adotados por recomendação do revisor cross-AI, sem passar
  por você). Vazia ou arquivo ausente → nada a incluir.
- **passos não rodados** — o que esta rodada não rodou e por quê (gate de config off,
  ferramenta indisponível — os eventos `skip` e as degradações declaradas da rodada).
  Nada pulado → nada a incluir.
- **riscos aceitos (4.4)** — a lista `riscos_aceitos` que o subagente do secure devolveu
  (cada um com o ponteiro de onde o usuário decidiu). Aceite de risco é assinatura do dono —
  ele precisa REVER a assinatura no resumo, não descobri-la no código. Vazia → nada a incluir.

**6.3 — Resumo executivo (modo final, com bloco de transparência).** **Sub-rotina F** com
`modo: final`, passando o **desfecho** (`ship` ou `handback`), a lista de itens **balde 4 (assumed)**,
a lista **`itens_intencao`** (as decisões de intenção da 6.2), a lista **`itens_nao_rodados`**
(os passos não rodados da 6.2), a lista **`riscos_aceitos`** (da 6.2) e — no handback — a lista
**balde 3**, além do cabeçalho de 🔔. A F escreve o bloco de transparência
**no topo** do `NN-RESUMO-EXECUTIVO.md`. Idempotente (`go_and_do_resumo: final`). Commit conforme a F.
> Ordem: o resumo é gerado e **commitado antes** do `close-phase` — assim ele entra na árvore limpa
> que o ship empacota, e vira parte do diff do PR.

**6.3b — Árvore limpa pro ship (commit dos artefatos do UAT).** O subagente da Etapa 5 pode ter
gerado um teste Playwright (`tests/uat-fase-NN.spec.ts`, fora do `.planning/` → **não** é coberto
por gitignore) e evidências (`<phase_dir>/uat-evidencia/`). O preflight do `gsd-ship` (chamado pela
close-phase) **exige árvore limpa** — esses arquivos não-commitados o travariam ou disparariam o
prompt "commit/stash" no meio do fluxo autônomo. Então, **antes** de chamar a close-phase, commite-os
(use os caminhos `teste_gerado` / `evidencias` que o subagente devolveu no resumo compacto):
```bash
git add "<phase_dir>/NN-UAT.md" "tests/uat-fase-NN.spec.ts" "<phase_dir>/uat-evidencia" 2>/dev/null
git diff --cached --quiet 2>/dev/null || \
  git commit -m "test(fase NN): UAT automatizado — cenários + e2e do caminho feliz" >/dev/null
```
> O `git add ... 2>/dev/null` ignora os que não existem (sem `--ui` não há `.spec.ts`/evidência; o
> `NN-UAT.md` pode estar em `.planning/` gitignorado). O `git diff --cached --quiet` pula o commit se
> nada foi staged. Falhou (sem git, nada a commitar) → **não pare**: registre numa linha e siga (o
> caso de árvore-suja-real a close-phase reporta como bloqueio de ambiente). Vale para **ambas** as
> rotas (na de hand-back também, pra não deixar o `.spec.ts` solto sujando a árvore).

**Evidência movida = `NN-UAT.md` emendado no mesmo passo.** Se você mover ou estacionar uma
evidência fora do Git (ex.: PDF com PII — a decisão de não versionar está certa), emende o
`NN-UAT.md` na hora: o campo `evidencia:` do cenário passa a apontar o paradeiro REAL, com o
motivo numa linha. Path inexistente no `NN-UAT.md` é defeito de fecho — a prova deixa de ser
auditável. Caso real (F21, 28/07): o PDF dos cenários 3/4 foi ao scratchpad por PII e o
`21-UAT.md` continuou apontando `uat-evidencia/….pdf` — a fase fechou com 0 evidência
versionada e 1 path fantasma.

**6.4-SHIP — Ship via `/close-phase` (via subagente).** Gate de contexto (Sub-rotina A).
Despache pela **Sub-rotina H** com `prompts/close.md` (leva `N`, `NN`, `phase_dir`,
`project_root` absolutos): o subagente hospeda a skill `close-phase N`, que faz
`extract-learnings → promove a verificação (com evidência "UAT automatizado", não "humana") →
commita os docs → abre o PR`. Ela tem o **freio herdado**: só promove/shipa se o veredito da
UAT for limpo pelo predicado nativo `phase uat-passed` (GSD 1.5.0+; markdown-aware,
fail-closed, conta só `pass`/`passed`, varre todos os `*-UAT.md`). ⚠️ **`assumed` (balde 4)
REPROVA nesse predicado** — a Etapa 5 fecha "objetivamente limpa" com baldes 1+4, mas a
allowlist nativa só aceita `pass`/`passed`: com ≥1 assumed o freio herdado segura e pergunta.
**Não afirme o estado do gate no briefing do despacho** — estado de gate se MEDE, não se
presume: rode o predicado antes do despacho (`phase uat-passed <N> --raw` via gsd-tools, o
mesmo idioma da close-phase) e cite no briefing o resultado MEDIDO; ou despache sem afirmação
nenhuma sobre o gate (o subagente mede sozinho — é o desenho do freio). Caso real (F21,
28/07): o despacho afirmou o gate satisfeito com 1 assumed no UAT; o predicado reprovava com
2 blockers e o subagente teve que desmentir a camada 0 por escrito antes de perguntar ao
dono. Reprovação real (pending/blocked/issue/failed/partial) → para.
- Roteamento do retorno:
  - `done · shipado` → `end` com `subagent_tokens` (Sub-rotina G); guarde o **PR (#N e
    URL)** pro banner e siga pra 6.5.
  - `done · uat_reprovado` → registre o `end` (a etapa rodou; o desfecho é bloqueio). O freio
    herdado agiu (não deveria acontecer na rota de ship — investigue o `motivo_reprovacao`
    pelo disco): **pare** via **Sub-rotina D** com o motivo.
  - `needs_decision` (revisão do ship Skip/Self-review/Request review; `uat-passed`
    bloqueia-e-pergunta) → pergunta ao usuário + **continuação do MESMO subagente**
    (Sub-rotina H); roteie o novo retorno.
  - `blocked` (bloqueio de ambiente: sem `origin`, `gh` ausente/não autenticado, branch
    errado) → **respeite**: registre o evento `stop` (etapa `pausa: ship bloqueado —
    <motivo>`), anote no banner o que faltou e **pare** (o PR fica pra quando você resolver o
    ambiente; re-rodar `/go-and-do N` retoma no ship).

**6.4c — Emenda do desfecho no resumo (fecho que afirma só o que aconteceu).** Depois que o
retorno do ship foi roteado (`done · shipado` ou `blocked` — no `uat_reprovado` a Sub-rotina D
assume), substitua o placeholder da seção `## Desfecho do ship` do `NN-RESUMO-EXECUTIVO.md` por
2–3 linhas **factuais**, escritas por você (Edit direto — é emenda pontual, não redespacho da
Sub-rotina F):
- `done · shipado` → o PR real (#N e URL) e o próximo passo verdadeiro DESTE fluxo (num fluxo
  com revisão humana: "revise e dê merge"; num fluxo com auto-merge, diga que já mergeou — não
  prometa uma revisão que o fluxo não tem).
- `blocked` → o motivo do bloqueio e o caminho real de publicação do projeto (ex.: "sem remote
  por design; publique com `/ship-clean-room NN`"). Nenhum PR existe — não deixe o texto sugerir
  que existe.
- Em ambos os desfechos, **reconcilie o corpo do resumo com o estado pós-close**: o resumo foi
  escrito ANTES do close — se a close-phase promoveu a verificação (`human_needed` → `passed`),
  procure a menção antiga (`grep -n human_needed <phase_dir>/NN-RESUMO-EXECUTIVO.md`) e emende-a
  no lugar, ou anexe à seção a nota "_status promovido a `passed` no fecho — ver § Desfecho do
  ship_". Sem isso o documento nasce internamente contraditório (caso real, F20: a § 4 dizia
  `human_needed` para sempre, com o estado real `passed` desde as 04:07 do mesmo fecho).
- A emenda obedece à **regra do estado do mundo** da Sub-rotina F: nada de afirmar situação de
  OUTRAS fases (pendente/publicada/mergeada) por artefato local — ou consulte o mundo
  (`gh pr view`), ou cite fonte + data, ou omita.
Commite: `git add <phase_dir>/NN-RESUMO-EXECUTIVO.md && git commit -m "docs(fase NN): desfecho
do ship no resumo"` (best-effort, mesma regra da Sub-rotina F). Idempotente: se a seção já está
preenchida (retomada), não reescreva. Regra de ouro: a emenda relata o retorno do subagente do
ship, nunca uma expectativa.

**6.4-HB — Hand-back (não shipa).** Imprima o banner na moldura padrão da 0.5 — título
`GO-AND-DO · Fase NN — pronta para o seu UAT`, campos `Balde 3` (quantos itens restam) e
`Resumo` (caminho do `NN-RESUMO-EXECUTIVO.md`) — e, abaixo da caixa, as pendências manuais,
nesta ordem:
1. `/gsd-verify-work N` — UAT conversacional. Retoma exatamente nos cenários **balde 3** (os demais
   já estão marcados). Resolva o acesso (login/vault) ou confirme o que faltou.
2. `/gsd-add-tests N` — suíte ampla (unit + E2E). O validate-phase (4.5) pode já ter gerado testes.
3. `/close-phase N` — depois do UAT limpo: `extract-learnings → ship` (cria o PR). *(Ou re-rode
   `/go-and-do N` sem `--no-ship` depois de resolver o balde 3 — ela retoma e shipa.)*

**6.5 — Self-check + banner final.** Antes de imprimir, confira: todos os gates reais honrados (ou
seus 🔔 no banner) e a execução completa — todos os planos com `SUMMARY.md`, checado por glob no
`<phase_dir>` (`NN-*-PLAN.md` × `NN-*-SUMMARY.md`; contagem casa → completo — sem precisar do
shim). Depois imprima:
- **Rota de ship:** moldura padrão da 0.5 com título `GO-AND-DO · Fase NN — shipada`, campos
  `PR` (#N) e `Resumo` (caminho do resumo executivo); abaixo da caixa: a **URL do PR**, o
  **bloco de transparência** (itens balde 4 assumidos + passos não rodados, se houver) e
  add-tests como passo **pós-PR** (adicione testes à mesma branch depois). Encerre.
- **Rota de hand-back:** a moldura da 6.4-HB (se a 6.4-HB acabou de imprimi-la, não duplique
  a caixa — reaproveite o mesmo banner) + os itens **balde 3** a resolver + as pendências da
  6.4-HB + onde está o resumo. Encerre.
Em ambas as rotas, junto do banner, registre o evento `stop` na telemetria (Sub-rotina G) com a
etapa `ship` ou `handback` — fecha a medição da rodada — e, no mesmo bloco Bash, **commite o
run-log** (best-effort):
```bash
git add "<phase_dir>/NN-RUN-LOG.jsonl" 2>/dev/null
git diff --cached --quiet 2>/dev/null || \
  git commit -m "chore(fase NN): telemetria — fim da rodada" >/dev/null
```
> Por quê: os eventos gravados depois do último commit de docs são um append não-commitado —
> num sync posterior do branch (checkout/reset pós-merge), um arquivo sujo trava o checkout e
> o append acaba descartado (aconteceu em fase real: o `stop` do ship se perdeu). Commit
> falhou (sem git, nada staged) → não pare; siga.
> Idempotente: re-rodar depois de shipado (PR já existe — a close-phase detecta e cai no banner) ou
> depois de hand-back cai direto aqui e reimprime.

**6.6 — Guarda (rede de segurança).** Se o self-check revelar que sobrou um plano sem `SUMMARY.md`
(ação humana que escapou da 3.4), **não** shipe nem diga "pronta": volte pra **Sub-rotina D**.
*(Neste caso raro, a D gera um resumo `parcial` que sobrescreve o `final` — o disco fica correto.)*

</stage>

</stages>

---

<note title="sem freio para o limite de 5h">

## Nota — sem freio para o limite de 5h

O uso da sessão de 5h não é legível por uma skill (não está no transcript; só no payload
da statusline, que a skill não recebe). Portanto não há gate de 5h — confia na
retomabilidade: se o limite estourar, rode `/go-and-do N` de novo após o reset e a skill
continua de onde parou (estado em disco; commits atômicos limitam trabalho parcial). Pausa
manual via `/gsd-pause-work` continua disponível a qualquer momento.

</note>
</output>
