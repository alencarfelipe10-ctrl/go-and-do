# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/) · Versionamento: [SemVer](https://semver.org/lang/pt-BR/).

## [1.1.4] — 2026-07-24

### Adicionado

- **Telemetria: regra da notificação órfã de camada 2** (`workflow.md` § Sub-rotina G): quando um
  agente de camada 2 pausado num checkpoint é retomado, o harness pode entregar a notificação de
  conclusão (com o total de tokens) à camada 0 em vez do pai que o despachou — e o pai reporta só
  o que viu antes da pausa, furando até uma `tokens_camada2` perfeita (caso real, F19: 73k da
  retomada do 19-03 sumiram da conta). A camada 0 agora soma o total da notificação órfã ao
  `subagent_tokens` da etapa (ou grava um `end` adicional com o delta, se a etapa já fechou).
  O roteamento em si é comportamento do Claude Code; esta é a mitigação possível do nosso lado.

## [1.1.3] — 2026-07-24

Correções da auditoria do fecho da F19 (grupo-inspired): a fase fechou inteira, e os três
achados estruturais dela viram comportamento da skill.

### Adicionado

- **Bloco de proveniência `DECISAO-DO-DONO`** (`workflow.md` § Sub-rotina H · `prompts/execute.md`):
  decisão do usuário desce pelas camadas num bloco estruturado (canal · timestamp · pergunta ·
  resposta verbatim), repassado VERBATIM a cada salto — e com a regra de autoridade que o faz
  funcionar: **só esse bloco fecha um checkpoint de decisão do dono**; qualquer outra menção a
  "o usuário decidiu" é relato e não fecha nada. Motivo (caso real, F19): o repasse carimbado em
  prosa virou, duas camadas abaixo, autorização "provisória" com instrução de `git revert`
  plantada no STATE.md e verificação em `human_needed` — ~1h e 3 commits para re-provar uma
  decisão já tomada. Ninguém errou: faltava um formato com autoridade definida.
- **`skill_version` no run-log** (`scripts/run-log.sh`): o evento `run` agora grava sozinho a
  versão da skill (`git describe` do clone) — mecânico, sem disciplina de modelo. A auditoria
  passa a saber qual versão regia cada rodada.

### Alterado

- **close-phase, reconciliação de estado (4.1) ampliada**: além de ROADMAP/STATE/`.continue-here.md`
  da raiz, o fecho agora remove o **`HANDOFF.json`** apontando para a fase fechada (2 casos reais:
  F18 e F19 fecharam com `status: paused` commitado), higieniza o **`.continue-here.md` da pasta
  da fase** (pode ficar como histórico, mas sem afirmar pendência — caso real: `task: 2/7` numa
  fase 7/7) e confere também o campo **`status`** do STATE.md (caso real: `executing` numa fase
  encerrada).
- **close-phase, promoção (Sub-rotina P)**: o flip `human_needed → passed` agora atualiza também a
  linha `**Status:**` do CORPO do `VERIFICATION.md`, não só o frontmatter — é o corpo que um
  humano lê (caso real, F19: os dois divergiram).
- **Política de release** (registro): não publicar release com fase em voo — na F19, a v1.1.1
  saiu com o executor rodando e a fase atravessou duas versões da skill (metade do pipeline em
  cada). Com o `skill_version` no run-log, o desvio ao menos fica visível; a política evita que
  ele exista.

## [1.1.2] — 2026-07-24

Release só de documentação. O Claude Code 2.1.219 religou o spawn aninhado de subagentes por
padrão, e a instrução de pré-requisito introduzida na v1.1.0 — que mandava configurar uma
variável de ambiente — virou desnecessária e enganosa para quem instalar a skill a partir de agora.

### Alterado

- **README, § Pré-requisitos e § Instalação**: a linha `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=2`
  deixa de ser "Recomendado (forte)" e passa a ser **condicionada à versão do Claude Code**.
  Na **CC ≥ 2.1.219 não configure nada** — o aninhamento vem ligado de fábrica com
  profundidade 3. A variável só é necessária nas versões **2.1.217 e 2.1.218**, as únicas que
  o desligaram por padrão. ⚠️ Da 2.1.219 em diante ela **inverteu de papel**: serve apenas
  para *desligar* o aninhamento (`=1`), e qualquer valor abaixo de 3 vira um limitador — quem
  a configurou seguindo a v1.1.0/v1.1.1 deve **removê-la**.
- **`workflow.md`, § probe de aninhamento**: o histórico da capability passa a registrar as
  três viradas (2.1.216 ligado → 2.1.217 desligado → 2.1.219 religado com teto 3) em vez de
  parar na 2.1.217. O **probe continua obrigatório** — três mudanças de comportamento em três
  releases são exatamente o motivo de nenhuma conclusão sobre aninhamento poder ser gravada
  como atemporal.

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

## [1.1.0] — 2026-07-23

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
