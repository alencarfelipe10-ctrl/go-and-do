# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/) · Versionamento: [SemVer](https://semver.org/lang/pt-BR/).

## [1.1.1] — 2026-07-24

Release de correções vinda da auditoria dupla de 24/07 (duas fases reais na mesma noite,
ambas com pausa graciosa auditada): honestidade do resumo e da telemetria, e o revisor
Antigravity finalmente configurável de verdade em headless.

### Adicionado

- **Detecção de fallback silencioso de modelo do `agy`** (`prompts/intent.md` +
  `prompts/convergence.md`): evidência de modelo mostrando um modelo **diferente** do
  configurado (caso real: `Gemini 3.5 Flash` respondendo com o 3.1 Pro pinado, 3 vezes na
  mesma fase) agora conta como **revisor falho com sino**, nunca como parecer válido.
  Cheque extra documentado: `agy --continue --print "Qual modelo de LLM você é?"`.
- **Atribuição de autoria de decisão no resumo executivo** (`workflow.md`, Sub-rotina F):
  autoria só com fonte citável (`NN-DECISOES.md` = orquestração; Interview Log /
  `AskUserQuestion` / `--obs` = dono); sem fonte, voz neutra. Caso real: um resumo atribuiu
  ao sistema uma decisão de oráculo que o dono respondera ao vivo.
- **Decisões de timing no `NN-DECISOES.md`** (`workflow.md`, Sub-rotina I): escolher QUANDO
  envolver o dono ("não vou interrompê-lo agora") é decisão como qualquer outra — entra no
  registro com critério, porquê e desfazer, não só narração no chat.
- **Campo `tokens_camada2` nos contratos de retorno** (`prompts/convergence.md` +
  `prompts/execute.md`) e regra de agregação na telemetria (`workflow.md`): o usage que o
  harness reporta à camada 0 cobre só o host despachado — os agentes camada-2 dele ficavam
  invisíveis no RUN-LOG (caso real: dois replans Opus fora da conta). O host agora reporta a
  soma dos próprios despachos; sem report, a etapa é anotada como subcontada — nunca estimada.

### Corrigido

- **Probe de capacidade do `agy`** (`prompts/intent.md`): `agy --help 2>&1` no lugar de
  `2>/dev/null` — o agy ≥1.1.5 imprime o help no **stderr**, e o probe antigo falso-negativava
  a flag `--add-dir`, derrubando a tentativa inteira do revisor (provado em fase real,
  24/07). Quem usa o `agy` como revisor deve aplicar o mesmo `2>&1` em qualquer probe
  equivalente fora desta skill (ex.: workflows do GSD).

Release de resiliência ao runtime, motivada pelas mudanças do Claude Code 2.1.217/218
(o 2.1.217 desligou por padrão o spawn aninhado de subagentes — a primitiva de que a
orquestração em camadas depende) e por uma auditoria de fase real que achou a causa-raiz
de falhas do revisor Antigravity em modo headless.

### Adicionado

- **Probe de aninhamento** (Sub-rotina H): antes do primeiro despacho de etapa que hospeda
  um comando GSD spawnador, um subagente-sonda de ~2k tokens verifica se a camada 1 recebe o
  tool `Agent`. Positivo → orquestração em camadas normal; negativo → rota inline decidida
  de imediato, sem queimar um despacho inteiro para descobrir o bloqueio.
- **Regras da rota inline** (Sub-rotina H): (1) ao hospedar uma etapa inline, o orquestrador
  **lê o `prompts/<etapa>.md` antes de conduzir** — as disciplinas da etapa moram lá e não
  podem ser perdidas no fallback; (2) o registro da decisão inline é sempre
  **versão-condicionado** ("na CC X.Y.Z…"), nunca "o harness não permite" — evita que um
  registro stale perpetue o fallback depois que o runtime muda.
- **Passo 0 na Sub-rotina C (TaskList)**: os tools de task do Claude Code podem sumir da
  sessão sem changelog (flag server-side). Se indisponíveis, a sub-rotina é pulada com uma
  declaração única — sem retry, sem ruído; religa sozinha quando os tools voltam.
- **README**: pré-requisito novo — env `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=2` (com
  snippet de configuração), necessário no Claude Code ≥ 2.1.217 para a orquestração em
  camadas.

### Corrigido

- **Revisor Antigravity (`agy`) em headless** (`prompts/intent.md`): o arquivo de briefing
  agora entra no workspace do agy via segundo `--add-dir`. Causa-raiz encontrada em fase
  real: o briefing ficava num diretório temporário fora do workspace e o modo headless
  auto-negava a leitura (`soft-denying ReadFile`) — o run morria antes de tocar o repo, e o
  sintoma era confundido com falha de login. A orientação de diagnóstico agora cobre isso:
  "not logged in" no início do log é ruído transitório, e o conserto seguro para soft-deny
  residual é uma allow-rule de leitura escopada — nunca `--dangerously-skip-permissions`.

### Alterado

- **Evidência de modelo do Codex** (`prompts/convergence.md`): o banner do stderr (versão,
  `workdir:`, `model:`, `provider:`) agora é copiado **verbatim** para o artefato durável de
  revisão, por ciclo — o `.err` vive em diretório temporário e evapora; a prova precisa
  sobreviver à sessão.

## [1.0.0] — 2026-07-22

Primeira release pública. 🎉

### Skills incluídas

- **go-and-do** — fase GSD de ponta a ponta (intenção → plano → execução → auditorias → UAT automatizado → resumo → PR).
- **close-phase** — fechamento de fase (extract-learnings → verificação → PR).
- **end-mile** — finalização de milestone (audit → summary → complete).

### Adicionado nesta release

- **Modo degradado dos revisores adversariais**: quando nenhum revisor externo (Codex/`agy`) está instalado, a revisão adversarial de intenção e a convergência do plano são **puladas com aviso destacado no resumo executivo** (`intent_review: skipped`), em vez de bloquear a fase. Setups com revisor instalado que falha em runtime continuam fail-closed (`blocked`), como antes.
