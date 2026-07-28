# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/) · Versionamento: [SemVer](https://semver.org/lang/pt-BR/).

## [1.3.2] — 2026-07-28

Correções da auditoria da rodada 1 da F21 do grupo-inspired (28/07, 1ª fase real da
v1.3.1): blindagem estrutural do revisor Antigravity contra morte por soft-deny em
headless, e dois fechos de telemetria/disciplina de evidência.

### Adicionado

- **`--agent revisor-gsd` na invocação do agy** (`prompts/intent.md`): a revisão de
  intenção passa a rodar o Antigravity com um agente custom **sem ferramenta de shell**.
  Causa-raiz provada em 3 fases (F16-ox, F20, F21): em modo headless, UM comando fora da
  allow-list gera soft-deny e o CLI derruba a conversa inteira em ~60ms (rc=0, stdout
  vazio) — e o modelo tem o hábito de "imprimir" o parecer final via `echo`/`cat`.
  Sem shell não há pedido de permissão, logo a morte é impossível por construção; a
  leitura segue pelas tools nativas (`view_file`, `grep_search`) com auto-grant no
  workspace. **Capability-probed e fail-safe**: sem o agente instalado em
  `~/.gemini/config/agents/revisor-gsd/agent.md` (ou sem `--agent` no help do agy), a
  flag é omitida e a rota legada segue valendo, com sino de transparência. Validado por
  6 probes + smoke test adversarial (isca de `echo` no briefing) em 28/07. O mesmo fix
  para a convergência vive em patch local do `gsd-core/workflows/review.md` (fora deste
  repo — overlay gen5-patches do usuário), já que o arquivo upstream serve 3 runtimes.
- **`tokens_camada2` no contrato de retorno da intenção** (`prompts/intent.md`): a linha
  existia em 8 prompts mas faltava no `intent.md` — a etapa 0-B saía como
  `camada2: "sem_report"` no run-log mesmo sendo a mais cara da rodada (F21). Valor
  esperado da intenção é `0`: os revisores externos (codex/agy) rodam por CLI, fora do
  harness, e não entram na soma.
- **Alegação sobre config carrega trilha** (`prompts/execute.md`): reportar estado de
  config do projeto exige dizer de onde veio a leitura; disco ≠ commitado → reportar os
  dois com fonte (`git diff`/sha), nunca o estado efêmero como fato. Caso real (F21): o
  retorno da execução alegou `use_worktrees: false` "não-commitado" e a auditoria só
  encontrou `true` no git.

## [1.3.1] — 2026-07-27

Correções da auditoria da F20 do grupo-inspired (27/07, 1ª fase real da v1.3.0): telemetria
com grade determinística, fecho de fase com asserção, e dois guards novos no executor.

### Adicionado

- **Fixtures gitignored nos worktrees** (`prompts/execute.md`): o passo 0 do despacho de
  executor, que já replicava os `.env*`, agora também copia (`cp -an`) as pastas declaradas
  em `.planning/worktree-fixtures.txt` do projeto — dados locais que o git não carrega ao
  worktree (ex.: `.xlsx` LGPD). Sem isso, projetos com fixture gitignored ficavam presos à
  execução serial (caso real: 7 fases 100% seriais no grupo-inspired; a F20 pagou 5h57 — 39%
  da parede — em 8 planos sequenciais). A cópia é local (disco → disco), vive e morre com o
  worktree, e continua gitignored lá dentro.
- **Guarda anti-reversão no briefing de executor** (`prompts/execute.md`): bloco verbatim em
  todo despacho proibindo `git checkout <hash> -- .`, `reset --hard`, `clean -fd`, `stash` e
  `add -A`; precisa de um deles → para e devolve como decisão. Torna permanente o
  endurecimento improvisado da F20 (um executor reverteu arquivos rastreados da árvore
  compartilhada e se recuperou sozinho em 25s — zero perda, mas nada impedia a perda).
- **Run-log endurecido** (`scripts/run-log.sh` — a grade virou determinística):
  `seq` monotônico por arquivo (ordenação canônica; 7 pares end/checkpoint colidiam no mesmo
  segundo na F20) · **auto-fechamento de janela** (checkpoint novo com a anterior aberta grava
  `end` sintético `auto_fechado` — a 3.4 da F20 rodou e ficou sem janela) · vocabulário
  canônico de `etapa` com aviso · `stop` com medição final de contexto + campo `motivo` ·
  **`tokens_camada2` como campo real** (9º arg; ausência declarada = `"camada2":"sem_report"`)
  · `parent_etapa` automático no end órfão de camada 2 · modo `audit` (lista janelas abertas
  antes do stop) · `--selftest` com 14 casos. A Sub-rotina G do `workflow.md` documenta o
  rebaixamento oficial: `subagent_tokens` é usage cumulativo reportado pelo harness —
  **conferência, nunca métrica** (superconta ~3-4x; a métrica é o ledger da /audit-gad).
- **Contrato `tokens_camada2` nos 8 prompts de host** (antes só execute e convergence):
  plan, code-review, secure, validate, close e eval-review agora reportam a soma dos próprios
  despachos — 5 etapas eram estruturalmente subcontadas sem marcador de ausência.
- **close-phase: Etapa 4.1 virou script com asserção**
  (`skills/close-phase/scripts/reconciliar-marcadores.sh`): usa o comando NATIVO
  `gsd_run phase complete N` (escreve ROADMAP + REQUIREMENTS + STATE atomicamente, incl. o
  frontmatter `status` — validado em sandbox: idempotente, sem carimbo duplicado) + `state.sync`,
  corrige o predicado do HANDOFF ("a fase apontada está FECHADA?" — por checkbox `[x]` ou
  VERIFICATION `passed` — em vez de "é a fase N?"), deriva as contagens dos `.continue-here.md`
  da contagem real de SUMMARYs, trata arquivos da era pré-frontmatter, e **assere tudo no fim**
  (`reconciliacao: ok` | `parcial` com residuais listados). Modos `--check` (dry-run) e
  `--sweep` (varre phases/ e milestones/). Motivo: a 4.1 era prosa sem asserção e falhou de 3
  jeitos distintos em fechos reais — F19: não rodou; F20: `status: executing` intocado (o
  comando usado escrevia o corpo e o motor do GSD preserva o frontmatter) e HANDOFF da F19
  sobrevivendo por instrução da própria regra.
- **Contrato do close ganha `marcadores_reconciliados: ok | parcial`** (`prompts/close.md`):
  a camada 0 e a auditoria passam a enxergar falha de reconciliação — antes o retorno só pedia
  `pr`/`learnings`/`verificacao_promovida` e o defeito era invisível.

### Corrigido

- **Resumo executivo não afirma o mundo por artefato local** (Sub-rotina F, regra dura nova):
  estado de OUTRA fase ou do repo publicado (PR pendente/mergeado, deploy) só entra com
  consulta real (`gh pr view`) ou fonte local COM data, como atribuição — nunca como fato nu;
  sem âncora, omite. Caso real (F20): o resumo afirmou "a Fase 19 segue pendente" lendo um
  `ship_state.json` desatualizado, com o PR #31 mergeado havia 2,5 dias.
- **Emenda 6.4c reconcilia o corpo do resumo pós-promoção**: se o close promoveu a verificação
  (`human_needed` → `passed`), a menção antiga no corpo é emendada ou carimbada — a § 4 da F20
  dizia `human_needed` para sempre, gerada 16 minutos antes da promoção e nunca atualizada.
- **Rodadas de code review em ordem cronológica** (`prompts/code-review.md`): a 1ª rodada
  fica no `NN-REVIEW.md` e as seguintes ganham sufixo crescente — na F20 o `iter2` continha a
  rodada 1 e o arquivo base a rodada 2 (quem lia pelo nome lia ao contrário).

## [1.3.0] — 2026-07-25

Correções da auditoria do fecho da F16-ox (25/07): destrava o paralelismo com worktrees e
endurece a honestidade do resumo executivo e da telemetria.

### Adicionado

- **Replicação de envs nos worktrees** (`prompts/execute.md`): worktree nasce sem os `.env*`
  (git-ignored por design) e isso já custou verificações adiadas (rodada 2 da F16-ox) e uma
  execução inteira serializada por override (rodada 3 — 2h25 de parede seriais). Decisão do
  dono (25/07, opção "copiar tudo" — o paralelismo vem primeiro): todo despacho de executor em
  worktree ganha um **passo 0 obrigatório** que replica os `.env*` do checkout principal
  (`cp -n`, preservando o que existir), e fica **proibido desligar/degradar worktrees por
  falta de env**. A cópia é o canal sancionado; a proibição de imprimir/dumpar `.env*` no
  transcript segue intacta (replicar ≠ inspecionar).

### Corrigido

- **Radiografia dos gates no resumo executivo** (Sub-rotina F, regra dura nova): o resumo DEVE
  citar o veredito agregado de cada gate que rodou (code review com IDs dos achados abertos ·
  UI score · eval veredito+score · segurança · validação · UAT por balde). Caso real: o resumo
  da F16-ox explicou os 4 blockers do eval mas omitiu o "36/100 NOT IMPLEMENTED" e não nomeou
  o Critical restante (CR-E01) — o número mais duro da fase ficou fora do documento do dono.
- **Checkpoint sem medição não passa mais em silêncio** (Sub-rotina G + `run-log.sh`): um
  `checkpoint` com `tokens`/`pct` vazios agora dispara aviso no stdout do script, e a regra
  manda re-rodar o context-check uma vez antes de seguir (persistindo, segue e anuncia a
  medição perdida). Caso real: o checkpoint da 5.4 (execução do UAT) da F16-ox nasceu sem
  tokens e a etapa ficou sem custo de contexto na auditoria.

## [1.2.0] — 2026-07-24

Fecha o P7 do roadmap: fim da pergunta pendurada no terminal sem ninguém saber (o inventário de
julho somou ~73h de espera em gates que ninguém viu chegar).

### Adicionado

- **Aviso no Telegram** (`tools/notify-telegram.sh` + hook `Notification` do Claude Code, matcher
  `permission_prompt`): quando uma pergunta interativa ou um pedido de permissão fica esperando o
  usuário, chega no Telegram em segundos uma mensagem com projeto, pergunta e opções (permissões
  mostram a ferramenta e o comando travado). Vale para **qualquer sessão** do CC, não só para a
  go-and-do; numa fase da go-and-do, a mensagem ganha fase e etapa correntes (lidas do
  `NN-RUN-LOG.jsonl` mais recente do projeto). Entre 23h e 07h a entrega é **muda**
  (`disable_notification`) — casa com a janela de silêncio da skill sem acordar ninguém.
  Instalação e credenciais (`~/.config/telegram-notify/config`, fora do repo): ver README
  § "Aviso no Telegram". Contrato do script: **nunca atrapalha a sessão** — qualquer falha
  (sem config, sem `jq`, sem rede) termina em exit 0, calada.
  - Fatos de mecânica que sustentam o desenho (probe de 24/07): pergunta interativa dispara
    `Notification` tipo `permission_prompt` ~2–8s depois de aparecer, **uma vez só**; `idle_prompt`
    não participa; não existe hook `PreToolUse` para `AskUserQuestion`. Como a notificação corre
    contra a gravação da pergunta no transcript (corrida real, perdida uma vez no UAT), o script
    relê o transcript a cada 2s por até 16s antes de montar a mensagem.

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
