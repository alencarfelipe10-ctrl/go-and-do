# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/) · Versionamento: [SemVer](https://semver.org/lang/pt-BR/).

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
