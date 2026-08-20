# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/) · Versionamento: [SemVer](https://semver.org/lang/pt-BR/).

## [2.1.7] — 2026-08-20

### Alterado

- **Convergência do plano pede `--agy-revisor`, não `--agy`.** A lane declarada
  `agy-revisor` (capability do gen5-patches, agente `revisor-gsd` sem shell) passou a ser
  invocável pelo runner do GSD (#2927 corrigido na 1.10.0) e foi provada em 20/08 no
  runner 1.11.0 **sem patch**: `ok · stubbed:false · model pinned`, canário e citações;
  controle com a lane stock `antigravity` no mesmo runner → `stubbed:true` (soft-deny).
  Com isso o patch local do `review-lane-runner.cjs` foi aposentado; a flag antiga
  voltaria a depender dele. `convergence.md` + `workflow.md`; nota no `roda-agy.sh`.

### Corrigido

- **`registra-ciclo.sh`: 3 achados do próprio agy** (parecer da lane `agy-revisor` no
  teste de 20/08, todos confirmados): JSON `.roda-*` de 0 bytes abortava o script sob
  `set -e` (`-f` → `-s`); caminho do parecer passado ao `grep` sem `--`; frontmatter
  CRLF fazia o `awk` do `models:` sair sem ler nada (`sub(/\r$/,"")`).

## [2.1.6] — 2026-08-20

Adaptação ao GSD 1.11.0 (tarefa 29 e/f do go-and-do-evolucao). Nenhuma mudança de contrato
de roteamento; dois sinais novos nos JSONs e uma parada herdada nova reconhecida.

### Adicionado

- **Aterramento por citação (GSD #3194).** `gad_tem_citacao_fonte` no shim reproduz a
  `SOURCE_CITATION_RE` do `review-lane-runner` upstream; `roda-codex.sh`/`roda-agy.sh`
  devolvem `citacoes_fonte: true|false` (+ sino, nunca exit 6 — é rebaixamento, não
  falha); `registra-ciclo.sh` grava o veredito por lane no apêndice do `NN-REVIEWS.md`,
  reconhece o carimbo `[reviewed-without-source-citations]` do runner e devolve
  `sem_citacao_fonte: [lanes]`. `convergence.md` e `intent-verifica.md`/`intent.md`
  rebaixam a lane não-aterrada a corroboração (`pareceres_sem_citacao` no retorno do
  verificador; `sem_citacao_fonte:` no frontmatter do INTENT-REVIEW).
- **Modelo nativo do GSD (#2295).** `registra-ciclo.sh` lê `models:` do frontmatter do
  `NN-REVIEWS.md` quando existe e o põe ao lado da nossa evidência; `unknown` vira sino
  ("vale a evidência própria"). Avaliação registrada no cabeçalho do `roda-agy.sh`: a
  evidência via `--log-file` CONTINUA necessária — o resolvedor nativo só roda dentro do
  review-lane-runner, e nossas lanes rodam fora dele (reavaliar na 29a).
- **`Gate: blocking-human` (GSD #3210).** `execute.md` 2b: precondição não atendida →
  rota da ação humana (`done · incompleto`, precondição verbatim); verificação de pacote
  → `needs_decision` irreversível. `workflow.md`: parada herdada listada; critério 6 da
  Sub-rotina I (a triagem não carimba o que o executor se recusou a carimbar); janela de
  silêncio trata como ação pendente, não pergunta; 2.4b ganha a rota (d) — varrer
  `<precondition>` dos PLAN.md e antecipar as checáveis no `NN-ACAO-HUMANA.md`.

## [2.1.5] — 2026-08-11

Só dado, sem código (PC-7): tabela de preços.

### Corrigido

- **`precos.json`: Sonnet 5 a $2/$10 permanente.** A Anthropic anunciou em 11/08 que o
  preço introdutório do Sonnet 5 (input $2 · output $10 · cache write $2,50 · cache
  read $0,20 por 1M) vira permanente — o aumento para $3/$15 de 1º/09 foi cancelado.
  Entrada nova `claude-sonnet-5` com esses valores; a genérica `claude-sonnet` segue
  em $3/$15 (correta para Sonnet 4.5/4.6). O match por prefixo mais longo do
  mede-tokens.py roteia sozinho. Nota: até aqui a tabela superestimava o custo do
  Sonnet 5 em 50% (usava o preço padrão, não o introdutório).

## [2.1.4] — 2026-08-11

Pendências 2, 3 e 4 da auditoria do FECHO da F24 do grupo-inspired (11/08 — 1ª rodada
100% autônoma da v2.x), mais a remoção do conta-turnos.py. Nota de contrato: o `end`
do run-log agora honra o lock do gate (antes, telemetria nunca bloqueava nada).

### Adicionado

- **Gate com dente** (3ª ocorrência do padrão "guarda cega reporta verde", desta vez
  com prova no run-log: `confere-etapa.sh` exit 1 → `end` pass 18 segundos depois).
  No fail, o `confere-etapa.sh` grava `.gate-fail-<id>.json` na phase_dir; o
  `run-log.sh` RECUSA qualquer `end` dessa etapa enquanto o lock existir — grava um
  evento `incidente` (`origem: gate-dente`) e instrui no stdout a re-rodar o gate
  até pass (só o próprio confere-etapa, ao passar, remove o lock) ou abrir
  `needs_decision`. Exceções que fecham janela sem gate: pausa (`interrompida=true`),
  `stop`/`skip`, fecho administrativo. Um pass que sucede um fail fica rastreável:
  o `end` ganha `"pos_gate_fail":true`. 3 casos novos no `--selftest`; validado
  ponta a ponta contra cópia da fase F24 real (fail → end recusado + incidente →
  fix → pass limpa o lock e grava o end).

### Corrigido

- **Campo `modelo` do run-log: regressão de 72% na F24 fechada** (46/64
  despachos/retornos sem o campo). Quatro causas, quatro fixes no
  `gad-lifecycle.sh`: (1) o hook nunca lia o `model` EXPLÍCITO da chamada do Agent
  tool — e é assim que os `gsd-*` recebem modelo (as defs deles não têm `model:`);
  (2) `meta.json` com `"model":null` agora cai para o transcript do próprio
  subagente (último `message.model` — fonte mecânica); (3) retomada por SendMessage
  cujo `to` é o id hex do agente acha o meta pelo nome do arquivo; (4) despacho que
  herda o modelo do pai (sem `model`, sem def) ganha `"modelo_herdado":true` em vez
  de campo silenciosamente ausente — o retorno preenche o id real. Replay sintético
  das 4 classes da F24 + regressão da def com `model:`: 5/5.
- **`mede-tokens.py`: janela vazia deixou de ser "total 0"** (fail-open da falha
  "end da etapa 0 mediu 0" — 100% de desvio contra o ledger da auditoria). Janela
  sem nenhum request (camada 0 e subagentes) agora retorna
  `status:"sem_medicao"` com reason explícita, e o `end` sai com
  `medicao=janela vazia…` em vez de `tokens_reais:0` fingindo medida válida.

### Removido

- **`conta-turnos.py`** — 4ª fase seguida com 0 execuções mesmo depois do modo
  `--auto` da v2.1.2. Decisão (11/08): turnos do coordenador são dado 100%
  recuperável do transcript — viram régua da auditoria (/audit-gad), não medição
  em sessão. O teto de ≤4 turnos/ciclo continua declarado no intent.md como
  disciplina; a cobrança é retroativa.

## [2.1.3] — 2026-08-11

### Alterado

- **Espelhos PC-5 agrupados em pasta única.** Os JSONs de última execução dos scripts
  agora vivem em `.planning/.gad/last-<script>.json`, em vez de nove dotfiles
  `.gad-last-*.json` soltos na raiz do `.planning/` do projeto alvo. Sem mudança de
  conteúdo nem de contrato — só o caminho. Recomendado ignorar a pasta no projeto
  alvo: `.planning/.gad/` no `.gitignore`.

## [2.1.2] — 2026-08-10

Pendências 2–9 da auditoria da F24 do grupo-inspired (1ª fase real inteira sob a v2.x):
a arquitetura passou, a telemetria nova falhou por inteiro — este patch conserta a
telemetria e os três casos de "guarda cega reportando verde".

### Corrigido

- **Camada real nos eventos `despacho`/`retorno`** (`hooks/gad-lifecycle.sh`). O
  `transcript_path` que o hook recebe é SEMPRE o da sessão principal — a detecção por
  `*/subagents/*` nunca acendia (F24: 34/34 eventos com `camada: 0`, inclusive filhos
  de spawnDepth 2). Agora o `retorno` casa o `tool_use_id` com o `meta.json` do
  subagente (camada = `spawnDepth − 1`, `modelo` real do meta) e o `despacho` usa a
  contagem de hosts abertos com `Agent` nas tools. Retomadas por `SendMessage` entram
  no run-log (`despacho`/`retorno` com `"retomada":true`; matcher do hook vira
  `Agent|Task|SendMessage` — atualize o `settings.json`).
- **Caminho de interrupção agora mede**: novo `confere-etapa.sh pausa` (Sub-rotina D)
  fecha a janela com `tokens_reais`/`custo_usd` do mede-tokens, rótulo CANÔNICO do
  checkpoint e `"interrompida":true` — na F24 a pausa ficou sem medição e o rótulo
  fragmentou em 3 grafias. A etapa 0 ganhou janela própria (mede desde o evento `run`)
  e o crash do `confere-etapa.sh 0` (grep vazio sob `set -euo pipefail`, espelho
  stale) foi corrigido.
- **Piso anti-omissão destravado** (`confere-ciclo.sh`/`registra-ciclo.sh`/
  `confere-rotas.sh`): pareceres da convergência (`NN-planrev-parecer-*-cN.md`)
  entram no glob e na extração de lane; headings `### Achado N [tag]` sem `.`/`:`
  são detectados; ruído ("Confiança: alta", headings de seção) filtrado; contagem de
  brutos passa a ler a linha-total da tabela. Sem parecer legível = **SEM MEDIÇÃO**
  explícito (nunca "0 verde"); `confere-rotas.sh` vira fail-closed no "nenhum ciclo
  detectado".
- **`conta-turnos.py` finalmente roda** (3ª fase seguida sem execução): novo modo
  `--auto` localiza sozinho o transcript do `gad-intent` pelos meta.json da sessão, e
  o `confere-etapa.sh 1` o chama mecanicamente. Estouro do teto grava evento
  `incidente`; rodada pausada é guard (não escreve pós-`stop`). Medição real da F24:
  25/15/26/17 turnos/ciclo contra um autorrelato de 5–6.

### Adicionado

- **Evento `incidente` no contrato do `run-log.sh`** (+ selftest) — fonte mecânica da
  régua 27(a); na F24 os 10 incidentes desviaram para `DECISOES.md` por falta dele.

### Documentado

- **Caveat do flush lag no `mede-tokens.py`** (investigação da divergência de 5,3%
  da F24): medir no instante do fecho subconta ~4–5% porque o usage final dos
  subagentes ainda está sendo gravado; a re-medição a posteriori bate o ledger exato.

## [2.1.1] — 2026-08-09

### Corrigido

- **`precos.json`: preço do `claude-fable` corrigido** de $5/$25 (preço do Opus) para
  os $10/$50 oficiais por MTok (cache write $12.50, cache read $1.00). O erro fazia o
  `mede-tokens.py` subcontar em ~2× o custo de sessões rodando em Fable 5. Conferência
  de 09/08 contra a página oficial de modelos: Opus ($5/$25), Sonnet ($3/$15) e Haiku
  ($1/$5) batem e ficam como estavam — no Sonnet o preço introdutório ($2/$10 até
  31/08/2026) é deliberadamente ignorado, mantendo o sticker por viés conservador.

## [2.1.0] — 2026-08-09

### Adicionado

- **`NN-PRE-SPEC.md` como insumo formal da intenção.** Quando o diretório da fase já
  contém `NN-PRE-SPEC.md` (decisões travadas pelo usuário numa sessão interativa
  anterior à rodada — nome exato, NN com zero à esquerda), a abertura o detecta
  automaticamente (`abre-rodada.sh` e `setup-intencao.sh` → campo `pre_spec`;
  registrado no evento `run`) e a Etapa 1 o usa como insumo: os filhos spec e discuss
  leem o arquivo antes de invocar o workflow e adotam as decisões dele como
  **travadas** — marcadas `[pre-spec]`, nunca re-perguntadas nem contrariadas por
  escolha `[auto]`; conflito irreconciliável com ROADMAP/REQUIREMENTS/SPEC vira sino.
  O briefing adversarial declara a origem (decisão `[pre-spec]` tem dono — o revisor
  ataca a consequência técnica, não a "falta de justificativa") e o livro-razão
  mecânico enumera `[pre-spec]` junto de `[auto]`. O arquivo entra no commit da
  intenção. A flag `--obs` deixa de ser o veículo para esse hábito (segue existindo
  para notas livres).

## [2.0.0] — 2026-08-09

Reformulação major da `/go-and-do` (plano aprovado em 09/08, blocos A–K). Princípio
regente (P15): **número, gatilho e verificação moram em script com exit code; o
julgamento mora no modelo.** Todo o registro de decisões está em
`gad-major-update.md` do projeto de evolução; aqui, a consolidação.

### Quebra de contrato (o porquê do major)

- **Renumeração das etapas:** a intenção deixa de ser "0-B" e vira **Etapa 1**;
  Contratos de design viram **1.5**; a convergência do plano deixa de ser "3.2" e
  vira **2.5** (ela pertence ao planejamento). IDs novos em roteiro, prompts,
  scripts e run-log. Eventos antigos seguem legíveis (validação só na escrita).
- **Esquema novo do run-log:** regra do **escritor único** — `run` (abre-rodada) ·
  `checkpoint` (pre-despacho) · `end` (confere-etapa, com `tokens_reais`/`custo_usd`
  medidos do transcript) · `despacho`/`retorno` (hook) · `script` (auto-registro) ·
  `stop`/`compact`. **`tokens_camada2` MORREU** (autodeclaração de subagente não é
  medição); o custo real sai do `mede-tokens.py` + `precos.json` (dedup por
  requestId, preço por request×modelo). Divergência 0% contra o token-ledger da
  /audit-gad na F21-ox real (31 subagentes).
- **Hook novo `hooks/gad-lifecycle.sh`** (PreToolUse/PostToolUse em `Agent|Task`):
  grava despacho/retorno com camada de origem e modelo/effort da definição do
  agente. Global, no-op fora de rodada (~17ms); sem ele a skill degrada declarado.
- **Fail-closed sem revisor externo (PC-6):** sem NENHUM revisor (codex/agy)
  instalado, a convergência (2.5) NÃO continua — `pre-despacho.sh 2.5` sai com
  exit 4 e a pergunta vai ao dono. Um ausente = segue com o outro, disclosed.

### Adicionado

- **Par de cancelas 2.C em toda etapa:** `pre-despacho.sh <id>` (gate de contexto
  absorvido, teto 400k · flags/config/retomada · janela de silêncio · checkpoint) e
  `confere-etapa.sh <id>` (motor de asserts por manifest declarativo — 13
  `scripts/manifests/etapa-*.json` — + extração de veredito canônico + `end`
  medido). A camada 0 roteia por exit code; nunca relê relatório.
- **`abre-rodada.sh`** — abertura atômica em 10 estágios (portões, retrato, gate,
  retomada `etapa_1`/`etapa_2`, alerta de vault, cache versão-condicionado do probe
  de aninhamento, conferência do hook, retrato da TaskList, evento `run` + ponteiro
  `.planning/.gad-rodada-ativa.json`).
- **Etapa 1 (intenção) mecanizada:** agentes `gad-intent`/`gad-contratos`/`gad-plan`
  pinados (Opus 5 medium); `setup-intencao.sh` (chegada), `briefing-build.sh`
  (livro-razão 1:1 com `[auto]`, missão canônica, canário de leitura),
  `decide-ciclo.sh` (parada por custo marginal, teto 4), taxonomia A–E de achados
  (`prompts/categorias-achados.md`), artefatos de ciclo em `.intent/`.
- **Convergência (2.5):** lanes externas por `roda-codex.sh`/`roda-agy.sh`
  (frescor, evidência de modelo no stderr, canário em exit code — exit 5 =
  ausente, 6 = falho no ciclo), `registra-ciclo.sh`, `grava-convergence.sh`,
  briefing direcionado com trilha do plan-checker, `--max-cycles 3`.
- **Gates (4):** lane Codex paralela no code review (4.D, funil `gad-verificador`,
  merge com `fonte: codex`); iterações 2+ estreitadas por `calcula-files.sh` (diff
  + dependentes reversos de 1 salto, 4.C); UI review desce a subagente (4.B) com
  `dev-server.sh up|down` (receita persistida + heurística + morte por sessão);
  mastigação antecipada de aceites do secure (4.E).
- **UAT (5):** classificador mecânico `uat.classify-coverage` antes da derivação
  (5.D); `confere-etapa.sh 5` reconcilia baldes/probes/evidência do disco, linta
  gaps, roda o predicado nativo `uat-passed`, varre **SEGREDOS** (padrão-gitleaks;
  PII genérica vetada) e é o escritor único das promoções de frontmatter
  (`pre_uat`, `status`, `pre_uat_fix_cycle`).
- **Encerramento (6):** roteamento por baldes no `pre-despacho.sh 6` +
  `uat_passed_raw` medido no briefing do ship + transparência extraída de 5 fontes;
  `commita-artefatos.sh` (uat|runlog); **merge direto pós-PR (6.D)** com o freio
  `uat-passed` na frente (revisão pós-PR = "Skip" carimbado — dev solo, o review
  real rodou na Etapa 4); ship alternativo por julgamento da camada 0 quando não há
  remote (6.E — sem config nova, a fonte é o projeto).
- **Formato híbrido do workflow (T.3):** residente = roteiro + contratos +
  sub-rotinas (~15,3k tokens, antes ~33k); condicional em `workflow-ui.md`,
  `workflow-ai.md`, `workflow-dev-server.md` (lidos sob demanda); o prompt da
  Sub-rotina F virou `prompts/resumo.md` (o subagente lê do disco).

### Mudado

- 8 prompts da camada 1 reformados (intent/plan/convergence/code-review/close +
  novos contratos/ui-review/codex-code-review/resumo); `uat-playbook.md` 409→373
  linhas (lifecycle 5.A: a janela do UAT é dona do server; frontmatter só via
  script; blindagem RTK); `close-phase` ganha o merge direto (3.3) e dieta de
  narrativa (mecânica intocada, 6.F). Sub-rotina F em Sonnet 5.
- Fecho do planejamento (2.4b/2.H): todo `autonomous: false` é resolvido no fim da
  Etapa 2 (pergunta agora · `NN-ACAO-HUMANA.md` executado e apagado · deferido ao
  UAT) — a rota inline da Etapa 3 vira exceção rara.

### Removido

- `tokens_camada2` (8 prompts + run-log) · pré-detecção de ações humanas da Etapa 3
  (3.1b) · subagente de conversão de balde 3 (5.4b/5.B) · passo 29b · shim colável
  da Sub-rotina E (virou `scripts/lib/gsd-shim.sh`) · gravação manual de
  checkpoint/end pela camada 0 (escritor único).

### Desvios declarados (estimativa era alvo; a garantia venceu)

- `uat-playbook.md` ficou em 373 linhas (alvo ~270).
- Residente do workflow ficou em ~15,3k tokens (alvo ~10–12k).

### Validação

- Aceites por bloco contra dados reais (F20/F21/F22, INS-19/21/22, RLR-02, AOS-13);
  a validação de campo são as **2 primeiras fases reais** desta versão (tarefas
  27/28 do projeto de evolução, payoff testável = fase equivalente à F21-ox fechar
  sem os incidentes dela).

## [1.8.2] — 2026-08-04

Enforcement da dieta v2 (v1.8.0) + captura de evidência de modelo do agy. Pacote da
auditoria temática da intenção da F22 (`040826-inspired-f22-intencao.md`): a dieta
executou pela metade porque as réguas de custo eram prosa — esta release as torna
mecânicas. Decisão do dono (04/08): **endurecer** a rota inline, não re-calibrar.

### Adicionado

- **`scripts/confere-rotas.sh`** — enforcement fail-closed da rota de verificação:
  cruza `.tabela-cN.txt` (piso mecânico) × `.verificador-cN.done` (prova de que o
  `gad-verificador` rodou); ciclo com ≥3 brutos sem verificador = `VIOLACAO`, ciclo
  sem tabela = `SEM-TABELA`, exit 1. Roda 2×: no passo 7b do `intent.md` (o coordenador
  não devolve `done` com violação — despacha verificação retroativa) e no item 9b do
  `workflow.md` (a camada 0 confere de novo antes de aceitar o `done`). Desenho
  deliberado: o atalho fica mais caro que a rota certa. Validado contra a F22 real
  (acusa exatamente c3 e c4; c1/c2/c5 ok).
- **`scripts/conta-turnos.py`** — medição determinística dos turnos do coordenador por
  ciclo (fronteiras = mtime dos nonces `.prova-leitura-cN.txt`; turno = mensagem
  assistant com tool_use) + taxa de batching. Estouro do teto de 4 vira evento
  `incidente` no run-log, com o número. Validado contra a F22 real (reproduz os
  estouros e o batching 1.0/turno).
- **`intent-verifica.md` grava `.verificador-cN.done`** como último ato — a prova de
  máquina que o `confere-rotas.sh` exige.

### Mudado

- **Rota inline endurecida (`intent.md` passo 5):** a `.tabela-cN.txt` é obrigatória
  em TODO ciclo (a contagem de brutos vem dela, nunca da leitura do modelo — contagem
  autorreportada foi o furo dos c3–c5 da F22); com 3+ brutos o `gad-verificador` é
  obrigatório SEM exceção — "consciente por custo de contexto" deixou de ser rota
  válida (o verificador custa ~1,5M cache read ≈ US$0,75/ciclo, medido).
- **Evidência de modelo do agy — canal novo, provado em 04/08** (`intent.md` 4b e
  `convergence.md`): `--log-file` por ciclo fixa o log da invocação; a prova é a linha
  `model_config_manager.go:311] Propagating selected model override to backend`
  (timestampada, pós-auth), corroborada pelo step 0 do brain localizado pelo conv-id
  extraído DO LOG — nunca de `cache/last_conversations.json` (cada `agy -p` cria
  conversa nova; o cache aponta a run mais recente do workspace — a armadilha que
  cegou a F22). `.err` de 0 bytes do agy é NORMAL (glog não vai ao stderr), não
  degradação; o cheque `agy --continue` foi abolido (mesma armadilha). Limitação
  declarada: prova o modelo selecionado/propagado pelo processo, não o servido.
- **`spot-check-ponteiros.sh` multi-root** — caminho relativo tentado em cada raiz
  passada; `MISSING-FILE` só se ausente em todas (F22: falsos-positivos em massa com
  docs citando repo + transcrições; validado: 22-CONTEXT 39/44→44/44 limpo, restos do
  SPEC = ponteiros genuinamente quebrados).
- **Teto de ≤4 turnos/ciclo agora é medido** (`intent.md`): o `conta-turnos.py` roda
  no fecho da etapa (camada 0); estouro = incidente auditável. O freio estrutural é a
  rota do verificador — medição não bloqueia, torna visível.

## [1.8.1] — 2026-08-04

Seis correções derivadas da auditoria da F22 do grupo-inspired (relatório
`040826-inspired-f22.md`), todas de comportamento — sem feature nova. Aprovadas pelo
dono item a item em 04/08.

### Corrigido

- **`confere-ciclo.sh`: falsos-positivos removidos** — a linha do canário
  (`prova_leitura:`/`PROVA-...`) e rubricas de classificação ("Nível Geral de Risco",
  "Overall Risk") casavam nos padrões de achado e forçavam exit 1 mesmo sem omissão
  (F22: exit 1 nas 8 execuções; no ciclo 4 era só ruído). Também corrigida a extração
  da lane no `--tabela` (`22-parecer-plan-agy-c4.md` → `agy`, não `plan`). Validado
  contra os pareceres reais da F22 como fixture.
- **Guarda anti-aninhamento no passo 0 do executor** (`prompts/execute.md`): a cópia de
  fixtures usa `rsync -a --ignore-existing` (merge idempotente; `cp -an` vira fallback)
  + normalização de barra final + detecção pós-cópia de `dir/dir/` aninhado com parada
  e incidente (caso F22: re-execução do `cp -an` aninhou `other-files/other-files/` e
  destruiu ~23 arquivos dentro do worktree).
- **Ts mecânico virou regra geral** (`workflow.md`): todo campo de timestamp gravado em
  artefato por qualquer camada usa `date -Iseconds` no ato — frontmatters de
  VERIFICATION/UAT incluídos (caso F22: `verified: 14:00:00` 5h no futuro do próprio
  commit). O self-check do fecho (6.5) ganhou conferência mecânica frontmatter×git
  (`git log -1 --format=%cI`).
- **Consentimento exige ponteiro** (`workflow.md` + `prompts/code-review.md`): alegação
  de "aprovado/assinado pelo dono" só vale com ponteiro para bloco DECISAO-DO-DONO
  existente (arquivo + ts); sem ponteiro, o item é tratado como não-assinado (caso F22:
  citação de assinatura fabricada sobreviveu 3 rodadas de review).
- **Gates decidem sobre saída crua** (`workflow.md` operating_rules): comando cujo
  resultado alimenta decisão de gate roda com `rtk proxy` quando há wrapper de filtro
  ativo (caso F22: newline fantasma, `grep -h` reescrito e `wc -l` sobre saída filtrada
  derrubaram 3 gates na mesma rodada). Leitura exploratória continua filtrada.
- **`.err` bruto nunca vai pro git** (`prompts/convergence.md`): a evidência durável de
  modelo é o banner copiado verbatim no REVIEWS; commit de pareceres adiciona só
  `NN-parecer-*.md` (caso F22: ~1,6MB de stderr commitados como "evidência").

## [1.8.0] — 2026-08-03

Dieta v2 da etapa de intenção, derivada da auditoria temática da F20 do oxmuscle-v2
(relatório `030826-oxmuscle-f20-intencao.md`: v1.5.0 validada com custo $48→$35; alavancas
restantes = coordenador com 53% do cache read e ~27min de espera serial de lane).
Aprovada pelo dono item a item em 03/08. Estimativa: ~$35→~$24–28 e 1h49→~1h10–1h25 por
etapa de intenção de 4–5 ciclos; validação = próxima fase real (tarefa 28 da evolução).

### Adicionado

- **Pipeline lane→verificador** (`prompts/intent.md` passos 4–5): as lanes Codex/agy saem
  em background num único bloco Bash, cada uma com marcador de término
  `pareceres/.done-cN-<lane>`; nos ciclos 1–2 UM `gad-verificador` é despachado
  imediatamente, espera o marcador do Codex (chega primeiro), verifica esse parecer
  enquanto o agy termina e incorpora o do agy depois — a espera de lane fica sobreposta à
  verificação. Nunca um 2º verificador para o parecer atrasado (contexto novo = custo;
  objeção do dono). Lane sem marcador no deadline → `sem_parecer` + regra de degradação
  existente. Única exceção ao "sempre síncrono" — só para o Bash das lanes, nunca `Agent`.
- **Freio de cauda** (passo 6, decisão do dono 2026-08-03): encerra o loop quando 2 ciclos
  consecutivos devolvem ≤1 novo confirmado cada, nenhum CRÍTICO/ALTO, e todos são
  refinamento de tema já tratado. Um único CRÍTICO/ALTO ou frente nova desarma. Registro
  obrigatório em `motivo_encerramento` com a série e os ciclos restantes. (Medição F20-ox:
  os ciclos 4–5 custaram ~11min/US$3 para devolver 1 reformulação cada.)
- **Verificação inline nos ciclos magros** (passo 5): ciclos 3+ com ≤2 achados brutos
  (contados pelo piso mecânico) são verificados inline pelo coordenador, mesmo protocolo
  do `intent-verifica.md`, com `verificacao_inline_cN` em `transparencia:` — formaliza o
  que a F20-ox fez espontaneamente no ciclo 5.
- **`confere-ciclo.sh --tabela`**: emite o esqueleto dos achados estruturais dos pareceres
  (lane · linha · trecho) — piso de enumeração da fusão: cada linha precisa de destino na
  tabela final do ciclo. O `intent-verifica.md` parte dele (passo 1 novo).
- **`motivo_encerramento:`** no frontmatter do `NN-INTENT-REVIEW.md` (passo 7): contagem
  zerou · teto de 5 · freio de cauda — com a série.

### Corrigido

- **Extração de achados do `confere-ciclo.sh` estava cega para o formato real dos
  pareceres**: a heurística da v1.7.0 (severidade em maiúsculas, IDs `cN-XN`) detectava
  **0 achados** nos 10 pareceres reais da F20-ox (headings `### 1. …`, `### Achado N:`,
  `### C3-1 —`, severidade minúscula). Refatorada para heading-first com fallback
  case-insensitive; validada retroativamente nos 5 ciclos reais: 47/12/6/4/5 achados
  estruturais por ciclo, sempre ≥ os 26/10/2/1/1 fundidos (piso sem furo por baixo).
  Vale para os dois modos (anti-omissão e `--tabela`).

### Alterado

- **Dieta do coordenador de intenção** (`prompts/intent.md`): teto de ≤4 turnos por ciclo
  (batching — o histórico do coordenador foi 53% do cache read da etapa na F20-ox);
  do ciclo 2 em diante é proibido reler SPEC/CONTEXT integrais — o "o que mudou" do
  briefing vem do próprio registro de triagem + `git diff`, trecho pontual via `sed -n`.
- **`intent-verifica.md`**: modo pipeline (passo 0 — espera por marcadores com deadline,
  Codex primeiro) + piso mecânico `--tabela` antes da leitura (passo 1).

## [1.7.0] — 2026-08-03

Fixes da auditoria da F20 do oxmuscle-v2 (relatório `020826-oxmuscle-f20-pausa.md`),
aprovados pelo dono item a item em 03/08. O fio comum: incidente e leitura provados por
mecânica, nunca por confiança — e a decisão de degradar deixa de ser de quem degrada.

### Adicionado

- **Seção `incidentes:` obrigatória (regra 24a)** em todo retorno `done` dos 9 contratos
  de camada 1 (`prompts/*.md`): todo desvio entre o anunciado/configurado e o executado,
  ou literalmente `nenhum`. Camada 0 (workflow.md): seção ausente = retorno fora do
  contrato (reconciliação); item ≠ `nenhum` → evento `incidente` no run-log + seção
  "Incidentes da rodada" no resumo executivo. Gatilho: 2ª ocorrência de incidente preso
  em camada intermediária (F2-rlr 30/07; F20-ox 02/08 — camada 0 anunciou "sem degradação
  de paralelismo" e a camada 1 registrou execução serial 6min depois, sem o dono saber).
- **Canário de leitura do agy** (`prompts/intent.md` 4b + `prompts/convergence.md`): nonce
  gravado em `pareceres/.prova-leitura-cN.txt` (nunca no prompt/briefing); o parecer
  transcreve `prova_leitura: <token>` na 1ª linha. Token de volta = prova mecânica de
  leitura de disco; ausente = parecer ponderado como corroboração
  (`agy_prova_leitura: ausente` + sino). Motivo: F20-ox — 4 ciclos de parecer plausível
  com `.err` de 0 bytes e caminho inexistente citado.
- **`scripts/confere-ciclo.sh`** — piso mecânico anti-omissão em resumo de ciclo: extrai
  do parecer bruto os achados estruturais (severidade, IDs `cN-XN`, refs arquivo:linha) e
  confere rastro no CYCLE_SUMMARY; `NAO-COBERTO` (exit 1) → leitura obrigatória do bruto.
  Fiado na convergência (passo 2b), com a regra complementar: resumo que REDUZ contagem
  também obriga a leitura (o HIGH omitido do ciclo 2 da F20-ox estava em prosa pura —
  indetectável por grep; o script é piso, não teto).
- **Evidência de máquina do P7** (`tools/notify-telegram.sh`): todo disparo grava
  `{"evento":"notify",ts,tipo,silencioso,enviado_ok}` em `NN-NOTIFICACOES.jsonl` ao lado
  do run-log da fase ativa — 2 auditorias seguidas ficaram `sem_evidencia` com o hook
  funcionando.

### Modificado

- **Paralelismo por wave vira mandato** (`prompts/execute.md`): a camada 1 perde a
  autoridade de serializar — precedente histórico ("validado na fase X") não autoriza;
  necessidade de serial → `needs_decision` à camada 0; fixture gitignored → declarar em
  `.planning/worktree-fixtures.txt` e copiar, nunca serializar. Serialização de fato,
  por qualquer caminho, entra obrigatoriamente em `incidentes:`.
- **`ts` dos blocos DECISAO-DO-DONO é mecânico** (workflow.md): `date -Iseconds` colado
  no ato — digitá-lo de memória é proibido (2º caso real de placeholder: F20-ox com
  minuto redondo e ~6min de desvio contra o transcript).

## [1.6.0] — 2026-08-01

Fixes da auditoria da retomada da F2 do rl-representation (relatório
`300726-rl-representation-f2-retomada.md`), aprovados pelo dono item a item em 01/08.
O fio comum: onde a regra escrita reincidiu, a fonte virou script (fix mecânico >
disciplina de modelo).

### Adicionado

- **`scripts/numeros-da-fase.sh`** — fonte MECÂNICA dos números do resumo executivo
  (3ª reincidência de número "de memória": F21 ordinal · F2-rlr "6 ondas" com os
  frontmatters declarando 9, "20 planos desta rodada" com 2 SUMMARYs da rodada anterior,
  baseline "71 passing" fantasma — as regras escritas da v1.4.1/v1.4.2 estavam em vigor
  e não seguraram). Computa do disco planos (total/summary/gap-closure/originais), ondas
  distintas por frontmatter e SUMMARYs por dia; modo `--conferir <md>` valida todo
  "N planos/ondas" citado num documento e sai 1 na divergência. Testado contra o caso
  real: pega o "6 ondas" e aceita 18/20/9. A Sub-rotina F agora roda o script ANTES do
  despacho (bloco colado no prompt via `<bloco_numeros>`) e DEPOIS (`--conferir` no
  documento final; divergir → 1 re-despacho; persistir → 🔔 no banner, nunca silêncio).
- **`run-log.sh close --sessao <id> ["motivo"]`** — fecho ADMINISTRATIVO de janela órfã
  de sessão morta (2ª ocorrência do padrão: notificação órfã da F19-inspired · API 500
  de 29/07 na F2-rlr). Grava `end` sintético com `fechado_admin: true` + `fechado_por`
  na sessão morta; no-op se a janela já está fechada; recusa a sessão atual (essa fecha
  pelo caminho normal). O modo `audit` passa a apontar o comando quando a janela órfã
  não é da sessão atual — o orquestrador descobre a chave mecanicamente. Selftest: 4
  casos novos, 18/18.

### Corrigido

- **3.5 passo 1b — replan de gap-closure ancora a re-convergência nos artefatos
  canônicos**: o plan-checker do replan roda dentro do GSD, que não conhece o
  `NN-CONVERGENCE.md` (marcador da 3.2) — na F2-rlr a 2ª convergência (3 blockers +
  5 warnings fechados) só existia no git, com CONVERGENCE/REVIEWS de mtime da rodada
  original. Agora a camada 0 acrescenta `gap_replan:` ao frontmatter dos dois arquivos
  e commita.

### Não aplicado (decisão do dono, 01/08)

- Seção `incidentes:` obrigatória no retorno de hospedeiros (o caso da onda 3 invisível):
  fica em MONITORAMENTO — aplica na reincidência (tarefa 24(a) do acervo).

## [1.5.0] — 2026-07-30

Dieta de cache read da etapa de intenção — resposta à auditoria temática da intenção da
F2 do rl-representation (relatório `300726-rlr-f2-intencao.md`): o pacote v1.4.0+gen5
executou 100% e só reprovou no custo (~US$48 > teto ~US$35; motor = cache read 63M, 66%
do custo, causado pelos workflows do spec/discuss residentes na camada 1 por ~200
requests). O desenho: o subagente de intenção vira COORDENADOR e o trabalho verboso
desce para filhos descartáveis de camada 2. Decisões de modelo/effort aprovadas pelo
dono em 30/07.

### Adicionado

- **Agentes `gad-*`** (`agents/`, instalar em `~/.claude/agents/`): `gad-spec` (Opus 5,
  high — hospeda o `gsd-spec-phase`), `gad-discuss` (Opus 5, high — hospeda o
  `gsd-discuss-phase` + neutralização do `--auto` + fronteira anti-duplicação),
  `gad-explore` (Sonnet 5, medium — busca somente-leitura, devolve conclusões com
  ponteiros), `gad-verificador` (Sonnet 5, medium — config espelhada no
  `audit-gad-cetico`, vencedora do A/B de 25/07: funde, deduplica, classifica e
  verifica os achados dos pareceres). Todos com contrato rígido de retorno e regra de
  batching; fallback inline declarado quando as definições não estão instaladas.
- **Prompts-filhos** (`prompts/intent-spec.md`, `intent-discuss.md`,
  `intent-verifica.md`): instruções gen-5 lidas do disco pelo próprio filho (mesmo
  padrão da Sub-rotina H), com contratos de retorno parseáveis.
- **`scripts/spot-check-ponteiros.sh`**: verificação determinística de citações
  `arquivo:linha` (existência de arquivo e de linha). Régua: verificação vira script;
  julgamento fica no modelo. Usado pelo `gad-verificador` (ponteiros dos pareceres) e
  pela camada 1 antes do commit (ponteiros dos artefatos).

### Mudado

- **`prompts/intent.md` reescrito** (30,6KB → 27,4KB): passos 1–2 despacham
  `gad-spec`/`gad-discuss` (os workflows de ~33KB do GSD deixam de residir na camada 1
  — na F2 eles custaram ~5,5M de cache read sozinhos); passo 5 despacha o
  `gad-verificador` e a camada 1 faz só a triagem de destino sobre a tabela de
  vereditos (na F21, UMA verificação inline custou 8,16M).
- **Convergência por redução, não por teto fixo**: o loop continua enquanto os achados
  NOVOS confirmados caem e são > 0 (na F2, 21→12→8 teria ganhado um 4º ciclo);
  encerra em 0; estagnação/subida → `needs_decision`; teto duro de segurança em
  **5 ciclos**. Critério novo/reformulado/reaberto definido no `intent-verifica.md`
  (reformulado é eco, não sinal — não sustenta o loop).
- **Pareceres em subpasta**: `<phase_dir>/pareceres/NN-parecer-*-c<C>.md` (era a raiz
  da fase).
- **Anti-duplicação SPEC↔CONTEXT**: decisão/requisito/critério mora no SPEC; o CONTEXT
  referencia por ponteiro (~20–25% de duplicação medida na F2, paga de novo em cada
  etapa que relê os dois).
- **Batching como regra de protocolo** (camada 1 e filhos): ações independentes no
  mesmo turno — na F2 foram 211 requests para 122 tool calls.
- `workflow.md` (itens 7–9, Sub-rotina H, 0B.2) e `SKILL.md` atualizados para o novo
  desenho; README ganha o passo de instalação dos agentes.

### A validar na próxima fase real

Custo da intenção ≤ ~US$35 · filhos devolvem contrato rígido · convergência por
redução em ação · `tokens_camada2` ≠ 0 (agora há despachos de verdade) · fallback
inline nunca disparando num setup com os agentes instalados.

## [1.4.2] — 2026-07-30

Melhorias da auditoria da F2 do rl-representation (sessão `805a8180`, interrompida por
API 500; relatório `300726-rl-representation-f2-interrompida.md`). O fio condutor: a
3ª fase serializada pelo mesmo padrão de worktree, e um vazamento de PII que a varredura
só pegou depois do commit.

### Adicionado

- **Pré-flight de paralelismo** (`workflow.md`, passo novo 18b): com `use_worktrees: true`
  e onda ≥2 planos, a camada 0 checa ANTES do despacho da execução se o worktree
  degradaria. Base mismatch (HEAD ≠ origin/HEAD — o estado normal de uma fase, que
  commita muito e só empurra no ship) → aplica sozinha `worktree.baseRef: "head"` no
  settings do projeto, re-checa e registra como auto-decisão. Qualquer OUTRA causa →
  investiga a solução e sobe AskUserQuestion com diagnóstico + opções (decisão do dono;
  degradação nunca vira fato consumado). (Casos reais: F16-ox por env, F19-ox e F2
  rl-representation por base mismatch — na F2 o fix existia desde a F19-ox e nunca fora
  replicado; 16 planos rodaram seriais.)
- **Guarda de segredo PRÉ-commit** (`prompts/execute.md`): briefing de executor cujo
  plano toca API viva ganha regra dura — redigir campos sensíveis ANTES do primeiro
  commit e varrer segredos antes do `git add`, com caminhos explícitos (glob não
  expandido em zsh = falso-limpo silencioso). Varredura pós-commit não protege: o valor
  fica no histórico. (Caso real F2: probe commitou corpo cru de `GET /users` com
  token/e-mail de 34 funcionários; o fix veio 1 commit depois.)
- **Contagem de ondas com fonte estrutural** (`workflow.md`, Sub-rotina F): o número de
  ondas citado em resumo/checkpoint vem do `=== waves ===` computado pelo execute-phase,
  nunca da declaração do planner. (Caso real F2: planner declarou 7, o execute rodou 6.)

## [1.4.1] — 2026-07-28

Fixes da auditoria do fecho da F21 grupo-inspired (retomada `2e5e11b0`, relatório
`280726-inspired-f21-fecho.md`): a fase fechou bem — o freio de UAT inclusive segurou o
fecho contra uma afirmação falsa da própria camada 0 — mas a rodada expôs quatro pontos
de disciplina, todos com caso real citado no texto.

### Corrigido

- **Camada 0 não afirma estado de gate sem medir** (`workflow.md`, 6.4-SHIP): o texto
  antigo dizia que "na rota de ship o veredito é CLEAN" — falso quando o UAT fecha com
  `assumed` (balde 4), que o predicado nativo `phase uat-passed` REPROVA (allowlist =
  `pass`/`passed`). Regra nova: rodar o predicado antes do despacho e citar o resultado
  MEDIDO no briefing, ou despachar sem afirmação nenhuma sobre o gate. (Caso real F21: o
  despacho afirmou gate satisfeito; o subagente mediu, desmentiu e a pergunta subiu.)
- **Ordinal de progresso com fonte estrutural** (`workflow.md`, Sub-rotina F): "onde a
  rodada parou" deriva do `HANDOFF.json` (`plan`/`task`) ou da contagem de SUMMARYs —
  nunca de `remaining_tasks[].id` — com self-check de consistência interna antes de
  gravar. (Caso real F21: "pausa no 4º de 9" no resumo final quando o HANDOFF dizia
  plano 3; o erro sobreviveu a duas regerações.)
- **Evidência de UAT movida = `NN-UAT.md` emendado no mesmo passo** (`workflow.md`,
  6.3b): evidência estacionada fora do Git (ex.: PII) exige emenda do campo `evidencia:`
  com o paradeiro real e o motivo — path fantasma é defeito de fecho. (Caso real F21:
  fase fechada com 0 evidência versionada e 1 path inexistente.)
- **Higiene do fecho** — 3 itens miúdos da mesma família:
  - `workflow.md` (Sub-rotina C): varredura anti-órfã da TaskList no fecho — nenhuma
    tarefa da fase sobra `in_progress` (caso real F21: a tarefa do UAT nunca fechou);
  - `workflow.md` (Sub-rotina H, bloco `DECISAO-DO-DONO`): `ts` é timestamp real
    (transcript ou `date -Iseconds`), nunca placeholder (caso real F21: `05:2x` literal);
  - `close-phase/scripts/reconciliar-marcadores.sh`: ao editar um `.continue-here.md`
    (status/contagens), o campo `last_updated` acompanha a edição (caso real F21: 2
    edições e o campo parado em 03:46Z).

## [1.4.0] — 2026-07-28

Aplicação integral da auditoria temática da etapa de intenção (F20+F21 do grupo-inspired,
28/07): a revisão adversarial pagava o custo, mas 36/36 achados sustentados já tinham a
informação no repo, e a pausa que travou a F21 foi fabricada pela própria intenção (uma
decisão falsificava 7 testes pré-existentes, detectáveis por `git grep`). Esta versão
compra a montante, por instrução, o que a revisão entregava — e deixa o revisor para o
que só segundo cérebro pega.

### Adicionado

- **R1 — Varredura reversa de impacto** (`prompts/intent.md`, novo passo 2 da revisão):
  para cada constante/valor/regra/invariante que o SPEC/CONTEXT muda, `git grep` do
  símbolo (código E testes) e seção nova no SPEC — **"Asserções existentes que esta fase
  falsifica"** (arquivo:linha · veredito · plano de reconciliação). As asserções
  atingidas entram no livro-razão e no briefing. Fecha a causa-raiz da pausa da F21.
- **R2 — Enumeração reversa no lugar de whitelist** (`prompts/intent.md`, briefing): o
  briefing não fixa quais testes importam; pede ao revisor enumerar toda asserção que as
  mudanças tornam falsa — "qualquer lista de arquivos é ponto de partida, não fronteira".
  Na F21, uma whitelist de 6 arquivos ancorou o revisor para longe dos 7 testes que
  quebravam.
- **R3 — Pareceres persistidos** (`prompts/intent.md`): os pareceres saem de `mktemp`
  para `<phase_dir>/NN-parecer-{codex,agy}-cN.md`, commitados com os artefatos; e a
  tabela do INTENT-REVIEW enumera 100% dos achados brutos — "já coberto" vira destino
  registrado com ponteiro, não filtro silencioso (na F20, 18 achados evaporaram).
- **R5 — Procedência de número** (`prompts/intent.md`, livro-razão): número load-bearing
  só entra re-derivado da fonte (dados/testes), no nível de agregação em que será
  verificado; e evidência de pergunta ao dono medida sobre o oráculo inteiro, não n=1.
- **R6 — Spot-check de citações** (`prompts/intent.md`, passo do commit): toda citação
  `arquivo:linha` dos artefatos escritos/alterados é conferida antes do commit.
- **R7 — Compatibilidade composicional** (`prompts/intent.md`, convergência): ciclo que
  alterou 2+ decisões/critérios checa a satisfazibilidade entre as próprias alterações
  (na F20, duas alterações do mesmo ciclo saíram algebricamente incompatíveis).
- **R9 — Lições de intenção** (`prompts/close.md` + `prompts/intent.md`): arquivo por
  projeto `.planning/LICOES-DE-INTENCAO.md` (teto ~30 linhas; cada lição = checagem
  acionável + origem + condição de aposentadoria). O close destila ≤3 lições novas de
  LEARNINGS+INTENT-REVIEW (dedupe por recorrência); a intenção o lê no livro-razão
  (marcação ativa de decisões que colidem) e o injeta no briefing do revisor. Vedado
  nomear arquivos como escopo de busca (anti-whitelist) e colar LEARNINGS inteiros.

### Alterado

- **R4 — Régua do ciclo 2 sem exceção** (`prompts/intent.md`, convergência): os três
  freios do loop (sem achado novo · estagnação · teto de 3) são a lista completa —
  "oráculo exaurido" não encerra o loop; com correção aplicada e ciclo no teto, o ciclo
  seguinte roda (a F20 fechou no ciclo 1 com 8 correções aplicadas, contra a própria
  régua, e dois vazamentos sobreviveram).
- Passos do `<adversarial_review>` renumerados (1–8) para acomodar a varredura reversa
  como passo 2; referências cruzadas atualizadas.

### Fora desta versão (registrado)

- **R8** (latência de relay de ~17 min entre resposta do dono e entrega ao subagente) é
  investigação de harness/camada 0, não mudança de prompt — na fila do go-and-do-evolucao.
- Espelho das lições no STATE.md (onda 2 do R9) fica para quando o fecho rodar em fase
  real.

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
