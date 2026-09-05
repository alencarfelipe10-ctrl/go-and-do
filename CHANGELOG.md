# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/) · Versionamento: [SemVer](https://semver.org/lang/pt-BR/).

## [2.5.0] — 2026-09-05

Pacote dos **erros de julgamento da F24.4** (tarefas 40–43 da evolução; planos, relatórios e
fiações em `go-and-do-evolucao/planos-acao-f24.4-julgamento/`). Quatro planos de ação escritos
por subagentes Opus 5 em 04/09, auditados entre si (7 conflitos resolvidos, 14 perguntas
respondidas pelo dono) e executados em 05/09 por quatro subagentes Fable 5.1, um por plano, na
ordem P4 → (P1 ∥ P2) → P3, cada item provado em sandbox com os artefatos reais da F24.4. A parte
do GSD (fork seletivo: absorção de `gsd-planner`, `gsd-plan-checker`, `gsd-verifier`,
`gsd-code-reviewer`, `planner-guidance`, `templates/summary.md`; `roda-suite.sh`; `plan-gate`
com lastro e hub; vista recortada do índice de decisões; classe dos ACs no `spec.md`) mora no
`gen5-patches` (manifesto 48 → 55 entradas) e não é versionada aqui.

**O que mudou de entendimento:** o AC-12 da 24.4 nasceu na spec sem ninguém pedir e reprovou a
fase por uma cota; o CONTEXT chegou ao planner 2× e com decisões que só apontavam a spec; a
revisão adversarial achava por achar (8 de 21 achados serviram ao Goal) porque a contabilidade
do loop pagava por achado, não por vínculo; e a fase saiu serial porque o planner não sabia
dividir por dono. Nenhum dos consertos cria gate por número — classe, vínculo, lastro e forma.

### Ondas largas (plano 4 — A1–A4, B1–B5, C1–C3; tarefa 43)

Pacote das **ondas largas** (tarefa 43 da evolução; decisões A1–A4, B1–B5, C1–C3 de 04/09/2026,
plano e relatório em `go-and-do-evolucao/planos-acao-f24.4-julgamento/`). A parte do GSD (fork
seletivo: `roda-suite.sh`, `plan-gate.py` com sonda de lastro, absorção de `gsd-planner.md`,
`gsd-plan-checker.md`, `planner-guidance.md` e `templates/summary.md`) mora no `gen5-patches`.

**Adicionado**
- `confere-etapa.sh 3`: assert `prova_por_reexecucao` — "N de M … verdes/passed" num SUMMARY sem o
  comando rodado e a saída colada na mesma seção reprova quando o SUMMARY traz o marcador
  `<!-- gad_prova: v1 -->` do template do fork; sem o marcador vira aviso em `extrai.prova_avisos`
  (A4). Na 24.4 real: `24.4-05-SUMMARY.md:71` e `:223`, e só elas.
- `confere-etapa.sh 3`: onda planejada com 2+ planos que rodou em série vira um `incidente` por
  onda no run-log, com a janela entre os despachos (C2); `paralelismo_observado` ganha
  `duracao_onda_s` e `plano_mais_lento_s`; `extrai.suite` conta lançamentos, recusas por lock e
  tempo do `roda-suite.sh` (C3).
- `pre-despacho.sh 3`: bloqueio `plan_gate_ausente_ou_reprovado` — exige
  `.planning/.gad/last-plan-gate.json` com `passed: true` **e** `resumo.fase` da fase corrente
  (C1, no lugar de absorver `execute-phase.md`); sino `sem_onda_larga` + `incidente` quando
  nenhuma onda tem 2 planos (C2).
- `manifests/etapa-2.json`: `plan_gate` extrai também `fase` e `razao`.


**Alterado**

- `confere-etapa.sh 3`: `COMMITS-A-MENOS` e `SEM-COMMIT` passam a reprovar a etapa (A1) — na 24.4
  real os planos 02, 06 e 09 (1/3, 2/3, 2/3) entram na frase de reprovação; `confere-plano.sh`
  (cabeçalho).
- `prompts/execute.md`: waiters encadeados de ≤ 590 s com `timeout: 600000` na tool no lugar do
  "único until"; suíte completa uma vez, pelo host, depois da última onda, por `roda-suite.sh`;
  plano com menos commits de tarefa do que tarefas é falha do passo; degrade para serial
  (`Running these plans sequentially…`, base-check) entra em `incidentes:` (A1/A2/C2).
- `prompts/plan.md`: avisos do portão de forma (`ARQUIVO-HUB`, `LARGURA-MAXIMA-1`) são para
  relatar em `sinos:`, não para travar (B5).
- `hooks/gad-bash-guard.sh`: a mensagem de negativa aponta o `roda-suite.sh` e o waiter
  encadeado; lógica intocada.
- Testes: `test-confere-etapa.sh` (+14), `test-pre-despacho.sh` (+11), `test-gad-bash-guard.sh` (+3).

### Intenção — classe do critério de aceite (plano 1, decisões D1–D10 da F24.4)

- **`[exigido]`/`[desejável]` por critério** (`templates/spec.md`, fork): cada AC declara a classe
  com motivo e origem-régua (`AA-n` do Anexo A da pré-spec, `PS-nn`, `Goal`, não-regressão);
  seções novas `## Critérios exigidos` e `## Cobertura do Goal`; linha `**Goal coberto:**` na
  `## Consistência interna`; bloco `gsd:acs` irmão do `gsd:scope` (classe ASCII
  `exigido|desejavel`). Ligado pelo marcador `<!-- spec-classe: v1 -->` — SPEC antigo segue sem
  classe e sem os sinos (mesmo desenho do P12).
- **Step 6 do spec-phase** (fork): três perguntas por critério — classe (o Goal ainda está
  atingido se este falhar?), régua (item do Anexo A, `PS-nn`, não-regressão, Goal; divergir é
  permitido e escrito) e unicidade (qual verificação derruba só este?) — mais a pergunta de fecho
  da cobertura do Goal. Sem cota.
- **`confere-pre-spec.sh`**: sinos `AC-SEM-CLASSE`, `EXIGIDO-SEM-MOTIVO`, `EXIGIDO-SEM-REGUA`,
  `EXIGIDO-DIVERGE-SEM-MOTIVO`, `GOAL-SEM-COBERTURA` (falha com o marcador ou `--exige-classe`;
  aviso sem eles) e a bandeira `AC-ORIGEM-REPETIDA` (nunca reprova); origens `AA-n` e `Goal`;
  modo `--sem-pre-spec` (fase sem PRE-SPEC: SPEC do dono ou gerado sem insumo passa pelas mesmas
  conferências de forma; citar `PS-nn` reprova com «a fase não tem PRE-SPEC»); ids do
  REQUIREMENTS com segmento de versão (`CANC-v3x-01`) passam a casar o padrão. Fixtures novas
  sintéticas (fase 99).
- **`confere-etapa.sh 1`**: item `r2_spec_sem_pre_spec` quando a fase não tem PRE-SPEC (antes a
  etapa saía sem conferência de AC nenhuma); a família de falhas ganha os cinco códigos de classe
  e a de avisos ganha `AC-ORIGEM-REPETIDA`. O gate **não** passa `--exige-classe` (classe só por
  marcador; origem continua incondicional — assimetria deliberada, medir uma fase).
- **`setup-intencao.sh`**: SPEC e CONTEXT no disco vencem o PRE-SPEC — a rota do §0.5 só roda em
  `entrada: spec|discuss`; fora delas `pre_spec_bloco: nao_aplicavel` e o campo novo
  `pre_spec_precedencia` (`spec_e_context_em_disco` | `estado_do_intent_review`). Um PRE-SPEC sem
  bloco deixa de parar uma intenção pronta. O R2 do primeiro turno passa a rodar com
  `--exige-origem` e `--reqs` (paridade com o gate: fiação do P12 que não tinha chegado ao setup).
- **`abre-rodada.sh`**: campo `inventario: spec=<sim|nao> context=<sim|nao> pre_spec=<sim|nao>`
  (JSON e evento `run`).
- **Fork — `gsd-verifier.md` absorvido** (base 1.12.0, diff de 8 linhas): extrai
  `must_haves.desejaveis` (reportado, nunca pontuado), regra 1 do Step 9 reprova só por truth,
  seção `## Desejáveis pendentes` no VERIFICATION.md. `gsd-planner.md` (`derive_must_haves`:
  truths só de `[exigido]` quando há `gsd:acs`; desejáveis em `must_haves.desejaveis`),
  `gsd-plan-checker.md` (desejável sem tarefa é WARNING, exigido sem tarefa segue BLOCKER),
  `planner-prompt.md` (lift por classe, item de checklist «todo exigido tem truth», leitura por
  faixa com `sed -n` — o RTK truncou o `cat STATE.md` da 24.4 para 3 %).
- **`prompts/convergence.md`**: materialidade por classe — achado contra `[exigido]` sustenta
  ciclo; contra `[desejável]` sai por fix cirúrgico ou vira sobra; nunca replan por desejável.
- **Sondas** (`probes.md` + digests, fork): dispensa por prevalência medida zero em `--auto`
  (só com comando e número na razão e só onde há corpus); shapes conservadores e `shapes: []`
  como opt-out (na 24.4, R7+R8 passam de 11 células para 1); estágio 2 mantém a proibição que
  espelha Out-of-scope (única fiação até o verifier); `judgment` que repete prosa é bandeira,
  não tarefa.
- Testes: `test-setup-intencao.sh` 58→69, `test-abre-rodada.sh` 14→17,
  `test-confere-pre-spec.sh` 37→64, `test-confere-etapa.sh` 84→97 (skill);
  `test-spec-workflow.sh` 75→106, `test-agentes-classe.sh` novo (24) (fork).

### Intenção · discuss (plano 2, decisões C1–C8 da F24.4)
- `prompts/intent-discuss.md`: o discuss deixa de ler o projeto por conta própria — aceita `explore: <caminho>`
  (pré-varredura pelo `gad-explore`, feita pela camada 1) e registra cada leitura própria em
  `.sinos-discuss.txt` (`leitura_propria:`); retorno ganha `leituras_proprias` e `criterios_nao_fecham`;
  WARN de repetição literal do SPEC tratado e contado em `dedup_aplicada`; decisão que prescreve mecanismo
  vira invariante + modo de falha, receita em `nota`; seção «Critério que não fecha» — medição vira sino
  `criterio_nao_fecha:` (alerta + ponteiro), nunca decisão no CONTEXT.
- `agents/gad-explore.md`: pergunta vinda do discuss é respondida por requisito (uma conclusão por R-n).
- `scripts/confere-reconciliacao.sh`: classe `D-NN-DESATUALIZADA` (informativa, uma linha por decisão, id
  no 3º token) por ciclo — enumera todos os commits `correções do ciclo C —`, porque a passada «b»
  sobrescreve o `.aplicado` — e `--final` contra as bases seladas; `informativos:` no rodapé; exit intocado.
- `scripts/correcoes-commit.sh`: `.planning/DECISIONS-INDEX.md` entra como alvo no `--inicio` e é regravado
  no fecho quando o CONTEXT mudou (índice do inspired estava stale: 265.467 × 267.368 B); gerador ausente → silêncio.
- `scripts/confere-plano.sh`: `informativos` + `decisoes {plan, summary, faltantes, informational}` — código
  `DECISAO-SEM-SUMMARY` (nasce informativo; não muda `veredito` nem exit); D-NN `informational` saem da conta.
- `prompts/code-review.md`: confere que `phase_dir` chegou ao revisor e reporta `decisoes_lidas: sim|nao`.
- `manifests/etapa-1.json`: assert informativo `criterios_nao_fecham` (grep no INTENT-REVIEW; métrica M11).
- Testes: `test-contrato-intent-discuss.sh` (novo), casos novos em `test-confere-reconciliacao.sh`,
  `test-correcoes-commit.sh`, `test-confere-plano.sh`, `test-briefing-build.sh`.

### Fork gen5-patches (plano 2)
- `workflows/discuss-phase.md`: licença de leitura do `scout_codebase` troca «Grep/Read para confirmar» por
  «leia a conclusão do arquivo de exploração»; ponteiro «Group areas by object»; campo `nota` (núcleo a
  20.464 B, folga 16 B do teto de 20.480).
- `discuss-phase/modes/auto.md`: forma da decisão (`answer` = invariante + modo de falha, `evidence` prova,
  `nota` sugere); agrupamento de áreas por objeto (sem alvo numérico); medição que mostra requisito
  insatisfazível não é decisão (7.045 B de 7.168).
- `bin/nosso/decisions-index.py`: `--vista --out --recent N --linha-max 160` — visão recortada com
  compactação incondicional e ponteiro ` → <arquivo>#D-NN`; o canônico segue completo e intocado.
- `bin/nosso/discuss-init.sh`: o prior.txt leva a vista (`features.decisions_index_recent`, advisory, default 1;
  fail-open para o arquivo inteiro). No inspired: 265.467 B → 82.043 B (N=1) / 47.537 B (N=0).
- `bin/nosso/context-render.py`: decisão `pre-spec` com `source_id` (ou `pointer: true`) sai em forma de
  ponteiro, uma linha, tag `informational` (gate de cobertura 23 → 14 na 24.4, verde); campo `nota` →
  `### Implementation Notes` (última seção, invisível ao parser); `superada: c<N>` → `superada-c<N>, informational`.
- `bin/nosso/context-guard.sh`: checagem 8 — corrida ≥ `GUARD_SHINGLE` (15) palavras do SPEC dentro de um bullet
  → `WARN: D-NN repete <k> palavras do SPEC literalmente — use ponteiro (§C1)`; nunca FAIL. 24.4: 6 WARN
  (D-01, D-04, D-05, D-06, D-07, D-09), 0 sobre o re-render.
- `bin/nosso/checkpoint-write.py`: `--nota-file`; `nota`/`nota_file` e `superada` no `--batch`.
- `bin/nosso/scout.py` + `discuss-phase/templates/context.md`: Integration Points = só conexões; risco e
  restrição vão à Regression Surface do SPEC (achado P2).
- `agents/gsd-code-reviewer.md` absorvido (manifesto 53 → 54; diff de 6 linhas contra o instalado): passo 1b
  lê `<decisions>` do CONTEXT pelo `phase_dir` do `<config>`; item 4 «Locked decisions»; achado cita `per D-NN`.
- `templates/summary.md`: `decisions-honored: []` ao lado de `key-decisions:` (lido pelo gate sem mudança).
- Testes novos: `test-decisions-index-vista.sh`, `test-code-reviewer-fork.sh`; casos novos em
  `test-discuss-init.sh`, `test-context-render.sh`, `test-context-guard.sh`, `test-checkpoint-write.sh`.

### Consultoria especializada de intenção (plano 3 da F24.4 — R1–R5, R7–R10; tarefa 42)
- A etapa «revisão adversarial de intenção» passa a chamar-se **consultoria especializada de
  intenção**; quem escreve o parecer é o consultor. Só a prosa muda: nomes de arquivo
  (`pareceres/NN-parecer-*.md`, `.intent/*`), a tag `<adversarial_review>` do `intent.md`, os
  campos de frontmatter (`revisores_efetivos`) e os regexes dos gates ficam como estavam.
- **R1** — o briefing traz o `## Goal` do SPEC verbatim («Goal desta fase») e pede, por achado,
  uma linha de campo `vinculo_goal:` com o efeito medido do Goal em risco; achado verdadeiro sem
  vínculo entra como dívida registrada, não como moeda de ciclo. A licença de zero cobre o
  parecer inteiro. O `confere-ciclo.sh` ignora a linha de campo na contagem de achados.
- **R2** — `confirmado_irrelevante`: quarto valor do veredito (mesmo campo, nunca um quinto —
  o `decide-ciclo.sh` lê quatro). Não conta ciclo, não gera `CONFIRMADO-NAO-APLICADO`; aplicado
  mesmo assim sai como `DISPENSADO-APLICADO` (informativo). O INTENT-REVIEW ganha a seção
  `## Dívidas registradas` e o frontmatter `achados_dispensados: N`; achado A/B dispensado vai
  também ao `deferred-items.md` (leitores: `uat.cjs`, check 7 do forensic-audit). O
  `gsd-code-reviewer.md` do fork lê a seção; o `prompts/plan.md` recebe a linha por fiação.
- **R3** — `decide-ciclo.sh` conta `dispensados` e não deixa o motivo de `para-zerou` dizer
  «nenhum achado» quando houve dispensa; a regra de desempate da `categorias-achados.md` vale nos
  dois eixos (categoria para cima; vínculo para baixo fora de A-produto). Nenhum limiar novo.
  Medido nos dados da 24.4: o loop não pararia antes (2/1/2/3 achados com vínculo ainda compram
  os quatro ciclos); o ganho é contagem honesta e registro de dispensa.
- **R4** — «`não — irrelevante para o Goal: <efeito>, ver <AC-nn|arquivo:linha>`» ganha o rótulo
  `nao_irrelevante_fundamentado` e o contador `irrelevante_fundamentada`; a palavra solta segue
  fraca; só o `supported_no` do verificador tira a pergunta da conta.
- **R5** — o briefing do ciclo 1 traz «Obrigação do ciclo 1»: SPEC × régua do PRE-SPEC (ou ×
  REQUIREMENTS sem PRE-SPEC), CONTEXT como alvo, conjunto nomeado enumerado — e três perguntas
  dirigidas do montante (Q4–Q6, qids atribuídos pelo script).
- **R7** — `--mudancas` validado por forma: só `## O que corrigi` e `## Achados resolvidos`
  entram; heading fora do contrato é omitido com aviso `MUDANCAS-SECAO-FORA-DO-CONTRATO`.
- **R8** — a revalidação do ciclo 0 vira uma pergunta só (Q7 no c1); os sinos corrigidos
  continuam listados; a frase «evidência = o diff do commit» saiu.
- **R9** — a releitura grava em disco o objeto inteiro (`v: 2`) com `contradiz`,
  `prescreve_mecanismo`, `omissoes_novas`, `cardinalidade` (número declarado × lista),
  `unicidade` (c0), `consistencia` e `ok`; o `briefing-build.sh` exige as chaves e reprova
  `ok: false`; o `confere-reconciliacao.sh --ordem` acusa `RELEITURA-ABERTA` no último ciclo.
  Formato legado (sem `v`) passa com aviso nomeado. A releitura do ciclo 0 lê também o texto
  original (Anexo A, `gsd:acs`, `<decisions>` do CONTEXT) — regras consolidadas dos planos 1 e 2.
- `prompts/intent.md` consolidado com as fiações dos planos 1, 2 e 4 (inventário da fase,
  modo sem pré-spec, códigos de classe, pré-varredura pelo `gad-explore`, contrato dos ciclos
  sobre SPEC do dono, `criterio_nao_fecha:`/`leitura_propria:`); `intent-spec.md` idem;
  `intent-verifica.md` com o waiter em `timeout 590` (plano 4).
- `tests/test-decide-ciclo.sh` criado — o script estava sem teste.

## [2.4.0] — 2026-09-02

Pacote dos **consertos do GSD (fork e padrão) e do paralelismo da F24.4** (tarefa 39 da
evolução; planos, relatórios e teste integral em `go-and-do-evolucao/planos-fork-f24.4/`).
Vinte e um planos executados por subagentes Fable 5.1, um plano por subagente, cada um
provado em sandbox com os artefatos reais da F24.4; um verificador independente (Opus)
rodou 25 itens de teste integral e achou 6 defeitos residuais, todos consertados no P21.
A parte do GSD (fork seletivo: `worktree-base-ref.cjs`, sentinel de isolamento, catálogo de
modelos, `spec-init`/`discuss-init`, scout, `plan-gate`) mora no `gen5-patches` e não é
versionada aqui — este release traz só o lado da skill.

**Fato que mudou o entendimento:** o Claude Code 2.1.257 honra `worktree.baseRef: head`
(provado por experimento); o GSD acreditava que não e rebaixava a onda para serial. E 20 dos
33 comandos de fundo da F24.4 vieram do hospedeiro de camada 1, não do executor — por isso o
hook do Bash cobre qualquer subagente da rodada.

### Adicionado
- `gad-bash-guard.sh` analisa o corpo entre aspas de `bash -c`/`sh -c`/`bash -lc`/`eval` com as mesmas regras (um nível) e nega também `screen -dm`, `tmux new -d`, `systemd-run`, `at now`, `coproc`, `start-stop-daemon` (P21, defeitos D1/D2 do teste integral).
- `pre-despacho.sh 3` ganha o bloco de paralelismo (manifest `pre.paralelismo`): `use_worktrees`/`parallelization` false, `--interactive` nos args ou `base-check` rebaixando onda de ≥2 planos → `bloqueio_paralelismo` (exit 4) com a `message` real; `baseRef: head` aplicado por `worktree set-baseref` e registrado no `NN-DECISOES.md` na primeira vez. O 18b do `workflow.md` deixa de ser prosa.
- `confere-etapa.sh 3` extrai `paralelismo_observado` (por onda planejada com ≥2 planos: despachados, `simultaneos_max`, janela entre despachos) e `serializacao_observada` do run-log; reprova `use_worktrees_alterado` (true no pré-despacho → false no fecho) e grava o `incidente`. Na F24.4 real: ondas 1 e 6 com `simultaneos_max: 1`.
- `gad-lifecycle.sh` grava `isolation` do `tool_input` no evento `despacho`; `tests/test-pre-despacho.sh` novo, casos de etapa 3 no `test-confere-etapa.sh`.
- `hooks/gad-bash-guard.sh` novo (P05): hook `PreToolUse` do Bash, registrado em `~/.claude/settings.json`, que nega a um subagente, dentro de uma rodada ativa, `run_in_background: true`, `nohup`/`setsid`/`disown` como palavra de comando e `&` de fundo (tokenizador ignora aspas, heredoc, comentário, `&&`, `>&`, `<&`, `&>`, `|&`); a única forma permitida é o waiter de disco `( trabalho ; touch marcador ) &`. Resposta viva `permissionDecision: deny` com o que fazer; cada negativa vira `incidente` no run-log (`origem=gad-bash-guard.sh`). Fora de rodada ou na sessão principal: allow em ~10 ms. Na F24.4 real, 32 dos 33 comandos de fundo do transcript (executor e host de camada 1) seriam negados; `tests/test-gad-bash-guard.sh` novo.
- `confere-pre-spec.sh` ganha a cancela de origem dos critérios de aceite (P12): toda linha de definição `- [ ] AC-nn — …` precisa terminar em `[origem: <ids>]` (`PS-nn` do bloco `gad:decisoes`, `R-n`/`SC-n`/REQ-ID, ou `AC-nn` da própria SPEC). `AC-SEM-ORIGEM` é FALHA quando a SPEC traz `<!-- spec-origem: v1 -->` (molde novo do fork) ou com `--exige-origem`; sem os dois é AVISO (specs antigas passam como antes). `AC-ORIGEM-INEXISTENTE` (FALHA) para id fora do bloco, fora da SPEC, auto-citação ou fora do padrão; com `--reqs REQUIREMENTS.md` os REQ-IDs são conferidos, sem ela entram com um único aviso `ORIGEM-NAO-CONFERIDA`. A origem é campo, não corpo: AC cujo corpo é só a origem cai em `AC-POR-PONTEIRO`, e o `corpo_do_ac` passa a tirar o checkbox `[ ]`/`[x]`/`[m]` antes de julgar. Na 24.4-SPEC real (50 ACs sem origem): sem flag, exit 0 e 50 avisos; com a flag, 50 falhas; com marcador e o AC-12 apontando `PS-99`, exatamente 1 `AC-ORIGEM-INEXISTENTE` — é o AC-12 que nasceu sem que ninguém o pedisse. Casos novos em `tests/test-confere-pre-spec.sh`; a go-and-do passa `--exige-origem` a partir da v2.4.0 (fiação em `prompts/intent.md`, `prompts/intent-spec.md` e `confere-etapa.sh 1`).
- `confere-plano.sh <phase_dir> <plan_id>` novo (P06): pelo git, confere que todo arquivo tocado pelos commits do plano (tag `tipo(<fase>-<plano>[-slug]):`, artefatos `.planning/**`/SUMMARY/STATE/ROADMAP/REQUIREMENTS fora) cabe em `files_modified` ∪ `files_deleted` do PLAN.md (`FORA-DA-LISTA`, `LISTA-VAZIA`) e que há um commit de tarefa por `<task>` — contam só os anteriores ao commit de metadados `docs(<plano>): complete … plan` (`COMMITS-A-MENOS`, `SEM-COMMIT`). JSON de uma linha + espelho `.planning/.gad/last-confere-plano-<plan>.json`. `confere-etapa.sh 3` roda em cada plano com SUMMARY e agrega `planos_conferidos {ok, falha, codigos}`: `FORA-DA-LISTA`/`LISTA-VAZIA` reprovam (`escopo_planos`); `COMMITS-A-MENOS` só extrai; um `incidente` por plano reprovado (`origem=confere-plano.sh`). Na F24.4 real: 02, 06 e 09 com 1–2 commits para 3 tarefas; 08 com 2 arquivos fora da lista, e 03/04/05 com o `veredito_regressao_244.py` do plano 02 (selos w2–w4) — a auditoria de 31/08 só vira o 08. `tests/test-confere-plano.sh` novo, casos no `test-confere-etapa.sh`.
- Cancela `parecer_informe` (P15): `confere-ciclo.sh --tabela` deixa de tratar como "0 achados" um parecer com corpo substantivo (≥ 12 linhas não vazias fora do frontmatter, do canário e do filtro `RUIDO`, ou ≥ 500 caracteres de corpo) e zero achados no gabarito — emite `parecer_informe: <lane> devolver` na 1ª vez e `parecer_informe: <lane> reprovada` quando o marcador `pareceres/.reformat-<lane>-c<C>` já existe (2ª vez): `usable:false, rc_reason:parecer_informe` no `.status-c<C>-<lane>.json` (com `--status-dir`), marcador `.reprovada` e um `incidente` no run-log (`origem=confere-ciclo.sh`, uma vez). `roda-lanes.sh … --reformata <lane>` relança só aquela lane, no mesmo ciclo, com o briefing original mais o bloco `## Reformatação obrigatória` (grava o marcador; 2º `--reformata` no ciclo → exit 4). `decide-ciclo.sh` não dá `para-zerou` com lane reprovada (`lanes_reprovadas` no JSON; cai em `continua`/`para-teto`). `### Achado 0 — nenhum achado novo` é o gabarito de zero achados: não conta como achado, não dispara a cancela (`sem_achado_novo: <lane>`) e passa a constar do briefing (`briefing-build.sh`). Nos 18 pareceres reais da F24.4: os 4 que a auditoria de 31/08 viu como "0 com texto" (planrev c4 agy/codex, c5, c6) saem `parecer_informe`, mais o planrev agy c2 ("Nenhum achado material" em prosa); os 13 restantes contam como antes (46 brutos no total). Família da convergência usa o marcador `.reformat-planrev-<lane>-c<C>`; a devolução dela ainda é manual (fiação em `prompts/intent.md`/`convergence.md`).
- `tests/test-roda-lanes.sh` estável (P15): barreiras de tempo (`SLEEP=2`/`SLEEP=3`/`SLEEP=30` no dublê, `sleep 1` como sincronização entre runs sobrepostos, tetos de 20–25 s) viraram barreiras de arquivo — o dublê `lane-stub.sh` ganha `STARTED=<arquivo>`, `WAIT_FOR=<arquivo>` e `CORPO=<arquivo>`; o teste espera marcador ou morte do supervisor (`espera_morrer`) com teto de 30 s; o caso de timeout usa `GAD_LANE_TIMEOUT=1` com marcador que nunca é criado. Bancada nova da cancela (cenários prosa 2×, prosa + gabarito, `Achado 0`) e casos novos em `test-confere-ciclo.sh` (fixture real `24.4-planrev-parecer-codex-c4.md`) e `test-briefing-build.sh`.
- `varre-worktrees.sh --projeto <raiz> [--arquivar] [--remover] [--max N]` novo (P16): irmão do `varre-orfaos.sh` para cópias (worktrees) em vez de processos. O `reap-orphans` do GSD só olha worktrees com arquivo `locked` e só remove as já incorporadas — a cópia da 24.2 do inspired (2 commits, 461 linhas, sem `locked`) ficou 11 dias invisível. Por padrão só relata: uma linha JSON `{projeto, base, acao, worktrees:[{path, branch, head, classe, commits, sujeira, nao_rastreados, idade_dias, existe, arquivado_em, removida, motivo}], removidas}` + espelho `.planning/.gad/last-varre-worktrees.json`, com classes `limpa` / `com-trabalho` (≥ 1 commit à frente da branch atual da raiz) / `suja` (rastreado modificado sem commit; `??` conta à parte) / `fantasma` (registrada, diretório ausente). `--arquivar` grava `git format-patch <merge-base>..<branch>` e `nao-commitado.diff` em `.planning/.gad/worktrees-arquivo/<branch>/` (gitignored; só arquivos rastreados entram) com README de reaplicação (`git am -3` a partir do commit-base). `--remover` exige `--arquivar` na mesma chamada ou pasta já existente cujos patches apliquem num clone temporário; `limpa` sai sem arquivo, raiz e branch da base nunca são tocadas, `--max` (padrão 3) limita as remoções por chamada, e `--projeto` apontando para uma worktree é exit 2. No inspired real: relata 1 `com-trabalho` e arquiva os 2 patches byte a byte iguais ao `format-patch` direto; a remoção fica com o dono. `tests/test-varre-worktrees.sh` novo (bancada sintética com as 4 classes).
- `reconcilia-docs.sh --pausa` (P17): o `pause-work.md` do GSD nunca toca o STATE.md e o `HANDOFF.json` anota hashes antes de existir o commit que o carrega — na F24.4 real o STATE.md ficou 16 commits atrás do HEAD depois da pausa (`state_head 06f3709f`, `status: executing`) e nenhum gate viu. O modo novo roda depois do commit WIP do pause-work e escreve o STATE.md por último: lê o HEAD real do projeto e o plano/tarefa do `HANDOFF.json` (só se for da mesma fase), grava `status: paused` (valor canônico do `STATUS_LIFECYCLE_ENUM`), `Stopped At`, `Last Activity` e `Last Activity Description` via `gsd-tools state update` (o verbo re-deriva `state_head` e `last_updated` sozinho; os três campos só aceitam o rótulo do corpo, e quando a linha não existe no corpo cai no sed do frontmatter, como o pós-ship), troca `— EXECUTING` por `— PAUSED` e o `Plan:` no `## Current Position`, e faz um único commit próprio `docs(state): STATE.md reconciliado na pausa` com `--files .planning/STATE.md` — o `state_head` gravado é o do WIP, o "onde paramos" verdadeiro. O JSON traz `discrepancia_commits` (quantos commits o `state_head` antigo estava atrás do HEAD; `null` com pendência se o sha não existe no repo), `commit_registrado`, `commit_proprio` e `ja_reconciliado` (2ª chamada não commita de novo). `--dry-run` relata sem escrever; frase no `status` continua exit 3; `between_phases`/`completed` ou fase divergente viram pendência sem toque. ROADMAP/REVIEW/REVIEWS ficam de fora neste modo. `confere-etapa.sh pausa --pos-pausa` é a cancela correspondente: `status: paused` e `state_head` ∈ {HEAD, HEAD~1}, senão `fail` com os motivos (quantos commits atrás). No sandbox com os espelhos reais do inspired e 5 commits à frente: `discrepancia_commits: 5`, um commit próprio, `state get "Current Position"` legível. Casos f–k em `tests/test-reconcilia-docs.sh`; a fiação na Sub-rotina D do `workflow.md` fica com o coordenador.
- Fiações (P19): `execute.md` ganha a `description` canônica do despacho (`Execute plan {NN} of phase {phase_number}`), a rota "matar e relançar; inline nunca" para executor travado e a menção ao `gad-bash-guard.sh`; `workflow.md` 18b vira reação ao `bloqueio_paralelismo` do `pre-despacho.sh 3`, a Sub-rotina D ganha `varre-worktrees.sh` (item 5, só relato) e o passo 3.5 `reconcilia-docs.sh --pausa` + `confere-etapa.sh pausa --pos-pausa` (a "reconciliação-lite" manual saiu), e o fecho 6.5 relata cópias com trabalho; `confere-etapa.sh 1` passa `--exige-origem`/`--reqs` e reprova `AC-SEM-ORIGEM`/`AC-ORIGEM-INEXISTENTE` (`ORIGEM-NAO-CONFERIDA` vai a `r2_avisos`); `intent.md`/`intent-spec.md` com o comando e os códigos novos e a devolução de `parecer_informe`; `convergence.md` com o relance manual da família planrev; `etapa-2.json` extrai `plan_gate` (tipo `json` novo no `confere-etapa.sh`, incidente se o espelho falta); `plan.md` devolve `planos: <n> (<w> ondas — largura máx <k>)`; README documenta o `gad-bash-guard`.

- Suíte: 23 arquivos, 23/23 verde.

## [2.3.0] — 2026-09-01

Pacote dos **consertos mecânicos da F24.4** (auditoria interina de 31/08,
`auditorias/310826-inspired-f24.4-interina.md`): falhas em que um script não rodou, um campo
não foi gravado ou uma régua publicada nunca virou trava — nada de julgamento do modelo.
Dezessete falhas listadas, doze consertadas, executadas por doze subagentes com escopo de
arquivos exclusivo.

**A exigência que definiu o pacote:** nenhum conserto valia por passar em fixture — cada um
teve de reencontrar o incidente nos artefatos reais da F24.4. Isso derrubou **três** dos
dezessete diagnósticos:

- A régua T3 não estava sem dado: os 21 achados confirmados tinham `proposicao`, 21/21. Quem
  não lia era o `etiqueta-achados.py`, que só aceitava fixture e nunca abria o
  `NN-INTENT-REVIEW.md` — e ainda avisava de uma ausência que não fora conferir.
- Os "39 achados sem categoria" não vinham do truncamento: 0 de 77 linhas perderam a tag no
  corte. Eram 31 respostas dirigidas (sem categoria por desenho) + 4 falsos-positivos + 4
  headings capturados por engano.
- O commit dos 190 arquivos não veio do `commita-artefatos.sh` — nenhum dos arquivos está em
  `uat-evidencia/`. O defeito consertado é real (6 fases antigas comitaram o diretório
  inteiro), mas a origem do incidente segue **em aberto**.

### Adicionado
- `confere-reconciliacao.sh` — cruza veredito × aplicado por ciclo (`INVERSAO`,
  `CONFIRMADO-NAO-APLICADO`, `APLICADO-SEM-VEREDITO`) e, com `--ordem`, acusa correção
  promovida depois da releitura. Na F24.4 reencontra os 5 casos apurados à mão, incluindo o
  achado `nao_sustentado` aplicado assim mesmo. Fiado como assert `r5_reconciliacao` do
  `confere-etapa.sh 1` e como passo do `intent.md` 7.
- `confere-sinos.sh` — nenhum sino do ciclo 0 fecha a etapa `aberto` (na F24.4, o `c0-14`
  fechou). Assert `c3_sinos_abertos`.
- `janela-silencio.sh` — fonte única da janela 23h–07h, com exit code que o gate duro
  obedece (Sub-rotina I). O sensor existia em dois lugares e ninguém o consumia: a pergunta
  ficou pendurada das 23:58 às 05:50.
- `varre-orfaos.sh` — órfãos por vínculo com o `phase_dir`, nunca por nome de processo
  (o critério por nome falhou 2× na F24.4). Só relata; `--matar` recusa acima de 10
  candidatos, em `GRUPO-MISTO` e em `GRUPO-PROPRIO`. Fiado na Sub-rotina D, agora uma
  sequência numerada que começa por `ListAgents` e para **todos** os filhos.
- `--intent-review` no `etiqueta-achados.py` da `/audit-gad`: 21/21 no caso real.
- `--regua`/`--limiar`/`--exit-code`/`--e4` no `turnos-por-ciclo.py`: turnos por ciclo
  (16·8·16·19 contra régua ≤4) e contrato E4 medido — atrasos reais de 27, 21, 376 e 280 s.

### Corrigido
- `hash` das correções deixa de sair vazio (58/58 na F24.4). O `intent.md` mandava passar
  `cC-01:<hash>` antes de o commit existir; quem preenche agora é o próprio
  `correcoes-commit.sh`, e ciclos com mais de um arquivo declaram `id:<caminho>` — sem isso,
  40% das entradas ficariam degradadas por desenho.
- `commita-artefatos.sh uat` não comita mais o diretório inteiro; acima de 20 arquivos
  recusa e devolve exit 1, que o `workflow.md` 6.3b trata como bloqueio de ambiente.
- `reconcilia-docs.sh` ganha exit 3 (`FORMATO-INESPERADO`) para `status` que não é token, com
  dono na etapa 6.5 — antes virava pendência muda, e a trava que deveria pegar o descuido
  compartilhava o mesmo ponto cego.
- Categoria dos achados em coluna própria (`confere-ciclo.sh`, `confere-rotas.sh`); o corte
  passou a contar caracteres, não bytes — vinha partindo palavras acentuadas.
- `token-ledger.py` classifica a divergência run-log × ledger (`direcao`, `causa_provavel`);
  os 3,1% da F24.4 saem como `flush_lag`, não como conta errada.
- `pre-despacho.sh` deixa de calcular a janela de silêncio por conta própria.
- `execute.md` nomeia os atalhos de background proibidos — os mesmos que criavam os órfãos.

### Notas
- Os textos de instrução tocados neste pacote foram revisados para as diretrizes Gen5 da
  Anthropic (fraseado normal no lugar de ênfase agressiva, forma positiva no lugar de
  negativas empilhadas, condição → consequência → motivo, sequência numerada onde a ordem
  importa). Literais de script, flags, exit codes e tokens que os gates procuram foram
  preservados verbatim.
- **Fora deste release:** a guarda de isolamento e o auto-degrade #683 são do GSD, não da
  skill — vão para o lote do fork. As mudanças da `/audit-gad` acompanham o pacote mas não
  são versionadas aqui (a skill não é repositório git).
- Suíte: 19 arquivos, 19/19 verde.

## [2.2.0] — 2026-08-30

Pacote dos **27 ajustes da etapa de intenção** (triagem do dono em 28/08 sobre a auditoria
fina da F24.3 — *Onde foram os 23 milhões*, `260827-inspired-f24.3-intencao-tokens.html`):
E1–E5, E7 · D1–D6 · S1–S4 · R1–R9 · T1, T3 · A1–A2. Plano em
`gsd-optimize/go-and-do-evolucao/intencao-ajustes/PLANO-execucao.md` (v11.1, fechada após 11
rodadas de revisão adversarial Codex + agy). **T2 foi descartado** por decisão do dono (SPEC e
CONTEXT vão sempre juntos aos revisores) e **E6 virou a `/gad-prefix`**, publicada à parte.
Execução em ondas (0 scripts puros · 0.5 contrato do PRE-SPEC · 1 ativação na skill · 2 fork do
GSD · 3 bancadas condicionais), por subagentes com escopo de arquivos exclusivo.

Régua da próxima fase real, medida pela `/audit-gad` e nunca em sessão: intenção 23,1 M →
~11 M tokens · US$ 31 → ~15 · 79 → ~50 min · **achados originais confirmados** (T3)
7 originais/13 confirmados/4 ciclos → 2–3 em 2 ciclos.

**Fase descartável (30/08)** — clone do grupo-inspired em scratchpad, fase sintética com
PRE-SPEC de 3 entradas (`R-1`, `none`, `SC-1`), Sonnet 5 sem MCPs, US$ 3,5: ondas 1+2 provadas
ponta a ponta (1 `spec-init.sh` e 0 `init` cru, PRE-SPEC autodetectado nos dois workflows,
`map-pre-spec` casando e fechando áreas, `[pre-spec:PS-nn, Rn]` no CONTEXT, hooks filtrados,
`finalize` commitando). Ela sozinha pegou **3 bugs de fiação que nenhuma suíte pegaria**:
normalização `R-n`→`Rn` ausente (o `map-pre-spec` nunca casaria), `discuss-phase.md` chamando
`discuss-init.sh` sem `--pre-spec` (o §0.5 era código morto) e `env.sh` sem `export` (o
`discuss-hooks-filter.sh` falhava fechado). Corrigidos com testes.

### Adicionado

**Coordenador da intenção — `prompts/intent.md`, hook e lanes (E1, E3, E4, E7)**

- **`scripts/roda-lanes.sh` (E4)** — despacha as lanes adversariais em **supervisores de
  background** e devolve em < 1 s, para o `gad-verificador` sair no mesmo turno (na F24.3 as
  lanes eram síncronas e o turno morria esperando). Cada invocação tem `run_id` e escreve tudo
  em `.intent/runs/c<C>/<run_id>/`; os caminhos canônicos (`.intent/pareceres/…`, `.status-c<C>-<lane>.json`)
  são promovidos por cópia + rename atômico, sob lock por ciclo, **só pelo supervisor que ainda
  é dono do ponteiro** `.intent/.run-atual-c<C>` — dois runs sobrepostos deixaram de reescrever
  os arquivos fixos que o `roda-agy.sh`/`roda-codex.sh` usavam. O status separa **dois eixos**:
  `usable` (parecer não vazio, fresco e legível) × `independent` (`nonce_ok && modelo_ok`), com
  `mirror_valid` à parte — parecer íntegro com espelho ausente **não some**, entra como
  corroboração não-independente. `usable:false` vira `sem_parecer` imediato, sem os 12 min de
  espera. 76 testes.
- **`scripts/correcoes-commit.sh` (E2b)** — tira do script gerado por LLM a parte git do commit
  por ciclo: índice temporário semeado do HEAD (`read-tree` → `apply --cached` → `update-index`
  → `write-tree` → `commit-tree`), **validação por blobs antes de mover a ref** e só então
  `update-ref` + `update-index`. Inclui `ROADMAP.md`/`REQUIREMENTS.md` quando o ciclo resolveu
  issue R6 ou reconciliou o Goal (a 24.3 precisou dos dois), preservando o trabalho que já
  estava sujo no worktree do usuário; alvo staged, sobreposição real ou artefato que continua
  sujo → **exit 3 sem promover nada**. Grava `.intent/.correcoes-c<C>.aplicado` (ids, commit e
  a lista exata de caminhos commitados), insumo do R1 e do T3.
- **Gate de override de modelo e de retomada de filho no `hooks/gad-lifecycle.sh` (E7, E3)** —
  a checagem roda **antes** de gravar qualquer evento (senão sobrava `despacho` órfão) e nega
  via `hookSpecificOutput.permissionDecision: deny`, gravando só `incidente`: `model`/`effort`
  no `Agent` de um `gad-*` que já pina no frontmatter; `SendMessage` cujo `to` **resolvido** pelo
  `agent-*.meta.json` é um `gad-spec`/`gad-discuss` (retomar filho que devolveu `done` custou
  203 k na F24.3); 2º `Agent(gad-discuss)` na mesma fase com `NN-CONTEXT.md` já existente (idem
  `gad-spec` × `NN-SPEC.md`). Restrito a `gad-*` — `gsd-mempalace-curator` pina modelo
  legitimamente. `tool_input.effort` não existe no `Agent` do CC: coberto só em teste sintético.
- **`experimental.cacheTtl: 1h` (E1)** no frontmatter do `gad-intent` — provado em bancada de
  28/08 (escritas no balde `ephemeral_1h`, cache reaproveitado após 10 min; o controle em 5m
  reescreveu 5,9 k). Filhos de camada 2 ficam em 5m.
- **`prompts/intent-releitura.md` (R1)** — modo `releitura` do `gad-verificador`: relê o `git diff`
  do commit do ciclo antes do briefing seguinte e devolve `{contradiz, prescreve_mecanismo,
  omissoes_novas}`. Não é filtro de erro factual — erro novo continua sendo trabalho dos
  revisores externos.

**Gates e scripts da etapa 1**

- **`scripts/confere-pre-spec.sh` (R2, R7, S4)** — gate mecânico do SPEC contra o bloco
  `gad:decisoes` do PRE-SPEC: falhas `MARCA-SEM-ID`, `ID-INEXISTENTE`, `ID-DUPLICADO`,
  `FATO-SEM-EVIDENCIA`, `RESSALVA-SEM-LIMITACAO`, `AC-POR-PONTEIRO`; aviso `EXTENSAO-SUSPEITA`
  (número, identificador ou literal na linha marcada `[pre-spec:PS-nn]` e ausente no span do PS —
  o revisor recebe a lista, o coordenador decide). Roda no `setup-intencao.sh` e no
  `confere-etapa.sh 1`.
- **Gates de cadeia no `scripts/briefing-build.sh` (E2c, R1, R3)** — o briefing do ciclo C ≥ 2
  **recusa (exit 4)** sem `.correcoes-c<C−1>.aplicado` (ou um `.vazio` explícito) e sem
  `.releitura-c<C−1>.json` válido; C = 1 recusa sem `.intent/.ciclo0.json` com schema versionado
  (arrays vazios explícitos; `{}` não basta). A validação é por conteúdo: `releitura.commit` ==
  commit do `.aplicado`, conjunto de caminhos **idêntico**, e cada `blob` == `git rev-parse
  <commit>:<path>` == worktree atual — editar o artefato depois da releitura reprova. Novo: seção
  **"Revalidação dirigida (ciclo 0)"** (R3) — toda correção feita a partir dos sinos entra no
  briefing como "sino → correção → evidência: confirme ou derrube"; **nenhum sino sai do briefing**.
- **Perguntas dirigidas (R8)** — o briefing emite `.intent/.perguntas-c<C>.json` (manifesto de
  Q-ids) e exige resposta estruturada `- Q<n>: sim|não|incerto — evidência`. `confere-ciclo.sh
  --tabela --perguntas --vereditos` conta `sim`/`incerto` como **brutos** (`elicitacao=dirigida`),
  trata `não` como `nao_provisorio` — só sai da conta com veredito `supported_no` do verificador,
  gravado em `runs/c<C>/<run_id>/vereditos-dirigidos.json` — e transforma Q ausente, duplicada ou
  malformada em bruto `incerto`. Nenhum texto de revisor sai da contagem por decisão de formato.
- **`VIOLACAO-INVERSA` no `scripts/confere-rotas.sh` (E5)** — o coordenador grava
  `.intent/.rota-verificacao-c<C>.json` `{run_id, mode: inline|child, brutos_pre_rota}` **antes**
  de verificar (o marcador `.done` não distinguia as rotas); ciclo ≥ 3 com `mode: child` e ≤ 2
  brutos pré-rota é violação. **Severidade decidida pelo dono (28/08): `exit 1` desde a 1ª fase**,
  a mesma dureza da violação original — o coordenador registra `incidente` e re-roda o gate.
- **`setup-intencao.sh`: §0.5 fail-closed, `req_ids_ausentes` e salvaguarda do T3** — PRE-SPEC
  presente sem bloco `gad:decisoes` (ou com bloco inválido) emite `pre_spec_bloco: ausente|invalido`
  e o coordenador devolve `needs_decision` ("migrar ou autorizar a rota antiga com sino"), nunca
  "zero decisões em silêncio"; a resposta fica durável em `.intent/pre-spec-route.json` com hash.
  R6: `issues: [{tipo: missing_requirement, id}, {tipo: phase_without_req_id}]` + `goal_roadmap`,
  com assert exato no `confere-etapa.sh 1` (menção em prosa não conta). T3: snapshot imutável do
  SPEC/CONTEXT via `git hash-object -w`, gravado **pelo filho que cria o artefato**; sem prova
  durável de que nenhuma revisão começou, o T3 sai `não_medido` em vez de promover artefato já
  corrigido a "original".
- **Suíte na raiz do repo** — `tests/roda.sh` + 13 suítes (`test-roda-lanes.sh`,
  `test-correcoes-commit.sh`, `test-gad-lifecycle.sh`, `test-briefing-build.sh`,
  `test-confere-ciclo.sh`, `test-confere-rotas.sh`, `test-confere-etapa.sh`,
  `test-setup-intencao.sh`, `test-confere-pre-spec.sh`, `test-pre-spec-migra.sh`,
  `test-spot-check.sh`, `test-registra-ciclo.sh`, `test-abre-rodada.sh`) com fixtures da 24.3.

**Fork do `gsd-discuss-phase` (D1, D3, D4, D5b, D6, R5) — `gen5-patches`**

- **Contrato §0.5 no `bin/nosso/checkpoint-write.py`** — `init --area "nome|R2,R3"` persiste
  `areas: [{name, anchors, anchors_remaining}]` (antes eram strings puras) e o campo `source_id`
  (`PS-\d\d`); novo subcomando **`map-pre-spec`**, dono único das entradas do PRE-SPEC: casa cada
  PS contra a estrutura de âncoras — 1 casamento → insere e só fecha a área quando todos os
  anchors estão cobertos; `req_anchor: none` ou 0 casamentos → área dedicada criada e fechada na
  hora; **≥ 2 → sino, nenhuma área fecha** (ramo confirmado pelo dono em 29/08). `context-render.py`
  emite `[pre-spec:PS-nn, R-n]` e `[medido:PS-nn]`.
- **`add-decision --batch <arquivo.json>` (D3)** — aplica N decisões atomicamente (validação
  completa antes de qualquer gravação, ids na ordem, `save` único, `complete-area` por área
  marcada). Sequência fixa no `modes/auto.md`: `init` → `map-pre-spec` → `--batch`.
- **`bin/nosso/discuss-hooks-filter.sh` (D1)** — filtro mecânico do envelope de
  `loop render-hooks discuss:post`: em `--auto` com `features.mempalace_capture_on_auto_discuss`
  ≠ `true`, remove **só** a entrada `mempalace-capture` e devolve o resto **inteiro**; o despacho
  continua no modelo, com todos os `kind` do contrato upstream. `ref.agent` sai em
  `nao_despachaveis` (o host `gad-discuss` não tem `Agent`) e vira sino `hook_nao_despachado` +
  incidente, nunca silêncio; `agentVerdict` é sempre não-bloqueante; `gate` malformado falha fechado.
- **`discuss-render-guard.sh` + `discuss-finalize.sh` (D4)** — dois scripts, um ponto de invocação
  cada: render → guarda → `check.decision-coverage-plan` em `write_context`; e FH-render →
  `decisions-index.py` → `state.record-session` → commit → limpeza no `finalize`. A releitura do
  CONTEXT pelo modelo sai — a guarda é a prova.
- **`blocks/finish.md` (D6)** — `write_context` em diante saiu do arquivo principal, lido em toda
  borda que entre no bloco (fim do loop de áreas, skip do `--auto`, `reconcile_existing`).
  `discuss-phase.md` 37,4 → 25,9 KB (o teto de 20 KB não fechou: o resto é o cabeçalho da
  entrevista, mantido de propósito).
- **`bin/nosso/pre-spec-batch.py` + `discuss-init.sh --pre-spec` (D5b)** — o init lê **só o bloco**
  do PRE-SPEC e gera `pre-spec-batch.json` com filtro estrito `kind == decisao_dono` (`fato_medido`
  nunca trava decisão; vai só para a lista do briefing/SPEC). O PRE-SPEC inteiro não entra mais na
  janela do filho.
- **`bin/nosso/artefatos-novos.py` + guarda (R5)** — a seção "Artefatos novos commitados" do SPEC
  vira gray area obrigatória por artefato no `discuss-init.sh`, e o `context-guard.sh` sai com
  `GUARD_EXIT=2` se a seção é não-vazia e falta um `D-NN` por artefato.

**Fork do `gsd-spec-phase` (S1, S2a, S3, R4, R5a, R7)**

- **`bin/nosso/spec-init.sh` (S1)** — uma chamada de `init phase-op` no lugar de ~12 leituras:
  devolve num resultado só a entrada do ROADMAP, a fatia do REQUIREMENTS, os cabeçalhos do STATE,
  os cabeçalhos do SPEC anterior como molde e (R6) Goal + `req_ids_ausentes`, gravando
  `.planning/.spec-tmp/env.sh`. O glob passou a excluir `AI-SPEC`/`PRE-SPEC` — o PRE-SPEC era
  tomado por SPEC existente.
- **`blocks/probes.md` (S3)** — passos 5.5/5.6 saem do arquivo principal, lidos ao chegar no 5.5.
  `spec-phase.md` 41 → 18,9 KB.
- **`references/edge-probe-digest.md` (S2a)** — substitui o `@edge-probe.md` de 17,7 KB. Ficou em
  5,9 KB (não os 3–4 KB do cartão, aceito pelo dono) porque preserva o que o motor **não** faz:
  "floor, not ceiling", a taxonomia de 8 em tabela compacta, o filtro de relevância com dismissal
  por razão, o aumento manual de categorias perdidas pelo classificador, `unclassified` e os
  estados de resolução. Sai só o didatismo.
- **`references/prohibition-probe-digest.md` (S2b)** — substitui o `prohibition-probe.md` de
  20,1 KB por um digest de 6,0 KB (−70 % por turno do spec-phase). Entrou **só depois do A/B**
  previsto no plano (`intencao-ajustes/bancadas/S2b-ab.md`): 3 SPEC-bases reais (24.2, 24.3 e
  RLR-02) × referência inteira × digest × 2 repetições, adjudicação cega com rubrica travada
  antes de abrir as saídas. Digest ≥ inteira em recall nas 6/6 células (a inteira recuperou
  12 %/25 %/0 % das proibições do gabarito; o digest 50 %/50 %/12 %), empate em falsos positivos
  (0), vazamento de canon (0), completude status×verificação e ACs promovidos, e saída zero
  num spec limpo inédito (0×0). A bateria de fixtures oficiais saiu do ledger: a referência
  inteira devolvia a frase da fixture *verbatim* (cópia, não competência). US$ 11,29.
  `blocks/probes.md` passo 5.6 aponta para o digest; `test-spec-workflow.sh` trocou o tripwire
  "fica inteiro" por 13 assertivas de invariantes do digest.
- **Três seções novas no `templates/spec.md`** (headings = contrato de máquina): "Consistência
  interna" (R4 — cada `MUST NOT` × os ACs que precisam do recurso proibido; na 24.3 o par
  AC-16 × AC-10/AC-42 era insatisfazível e dois gates deixaram passar), "Artefatos novos
  commitados" (R5a) e "Limitações declaradas" (R7 — toda `ressalva:` do bloco do PRE-SPEC precisa
  de linha citando `PS-nn`, ou `descartada: porquê`).
- **`workflows/plan-phase.md` entrou no fork** (36 entradas no `manifesto.json`, `triar.sh` 🟢)
  por uma linha: o planner lia `NN-PRE-SPEC.md` como se fosse o SPEC.

**`/audit-gad` v1.2.0 (A1, A2, T3)**

- **`scripts/turnos-por-ciclo.py`** — turnos por ciclo do `gad-intent` (ciclos delimitados pelos
  `tool_use` do `briefing-build.sh`), marcação de `releitura_corrigiu` como 5º turno legítimo e
  detecção de expirações de cache; `--gaps` distribui os intervalos entre requests por agente
  `gad-*` (insumo da decisão E1). Na 24.3: 11·6·8·6 turnos e 6 expirações = 916 k.
- **`scripts/etiqueta-achados.py` (T3)** — proveniência de achado em **dois eixos**,
  `origem_artefato = original|derivado` e `elicitacao = livre|dirigida`, medida pela `proposicao`
  gravada na triagem (artefato, span, fingerprint por âncora `AC-n/D-nn > R-n > heading`) contra o
  blob-base — nunca `git blame`. Sem `proposicao` ou sem blob → `não_medido`, e com `não_medido > 0`
  o relatório **não pode** concluir melhora ou piora comparativa (o cético reprova). A régua nova
  ("originais confirmados / confirmados / ciclos", "dos quais dirigidos", cobertura) entrou no
  `templates/relatorio.md`, com a fixture histórica 7/6 obrigatória na suíte.

**Skill `/gad-pre-spec`** (`skills/gad-pre-spec/`) — sessão interativa que produz o
`NN-PRE-SPEC.md` de uma fase, o insumo que a `/go-and-do` entrega ao `gsd-spec-phase` e ao
`gsd-discuss-phase`. Nasce de um levantamento dos 9 PRE-SPECs reais (grupo-inspired,
oxmuscle-v2, rl-representation): nunca houve molde — cada documento copiava o anterior, o que
produziu 3 linhagens divergentes, 4 convenções de nome e **zero** blocos `gad:decisoes` (ou
seja, toda fase caía na rota legado do `intent.md`). A skill fixa as três coisas:

- **molde único** em `templates/PRE-SPEC.md` — 11 seções (leigo · origem · código ·
  medições · decisões do dono · hipóteses falsificadas · regras do cliente · fora de escopo ·
  aberto deliberadamente · ressalvas · referências) + as marcas do bloco. Seção vazia fica
  com `— nada —`, nunca é removida.
- **nome canônico**: `<phase_dir>/<padded_phase>-PRE-SPEC.md`, com `padded_phase` vindo do
  `init.phase-op` — é o caminho exato que o `abre-rodada.sh` procura (fase 2 → `02-…`).
- **bloco gerado, não escrito à mão**: `scripts/gera-bloco.py` traduz as respostas da
  entrevista (JSON com nomes em português) para o contrato v1, numera `PS-01…PS-99`, insere
  entre as marcas e chama o `confere-pre-spec.sh --so-bloco`; reprovou, o arquivo é
  restaurado e o exit é ≠ 0.
- `scripts/abre-fase.sh` envolve `init.phase-op` (e `phase.insert` + espelhos de estado
  quando o dono autoriza a inserção) e devolve `{phase_found, dir, padded, alvo, existe}` —
  `dir` cai em `expected_phase_dir` quando o diretório ainda não existe, **nunca** no
  `$NN-nova`. `--inserir` exige `--apos <M>` porque quem calcula o número decimal é o GSD, e
  o script reporta `numero_atribuido`/`aviso_numero` quando ele diverge do pedido.
- `scripts/confere-pii.sh` (+ `scripts/nomes-permitidos.txt`) — gate de PII em duas camadas:
  lista dura dos nomes vistos nos insumos (vale em qualquer contexto) e heurística
  "Nome Sobrenome" fora de heading, código, caminho e URL. Fecha a dívida da fase 24, em que
  a PII foi corrigida a posteriori com `sed`.
- Regra permanente escrita no molde, na skill e no gerador: **número sem fonte executada na
  sessão é `[herdado]`** e não vira `fato_medido`. Precedente: uma fase montada sobre números
  de auditoria velha teve os números reprovados quando foram re-derivados.
- 4 suítes em `skills/gad-pre-spec/tests/` (`roda.sh` + `test-fase.sh`, `test-molde.sh`,
  `test-gera-bloco.sh`, `test-pii.sh`), com bancada `.planning/` sintética no scratchpad e
  `init.phase-op` real. **Não** são recolhidas pelo runner da raiz (`tests/roda.sh`), que só
  varre `tests/test-*.sh`.
- Comportamento documentado, contrário ao que o plano supunha: `confere-pre-spec.sh
  --so-bloco` **aprova** bloco vazio (`[]` → exit 0, `entradas=0`); não existe código
  `BLOCO-VAZIO`. O gate de conteúdo é a revisão com o dono (passo 6 da skill), e o
  `test-molde.sh` trava esse comportamento.

### Alterado

**Coordenador e prompts dos filhos**

- **`prompts/intent.md` reescrito nos passos 2b–5** (25,5 → 32,8 KB): triagem do **ciclo 0** dos
  sinos com regra explícita de fonte-de-verdade (fato de código citado > SPEC > CONTEXT; requisito
  manda o SPEC, *como* manda o CONTEXT); correções factuais de um ciclo **num único script**
  `.intent/.correcoes-c<C>` escrito e executado num turno só; correção escreve **invariante**
  (AC `MUST NOT` + modo de falha observável), **nunca mecanismo**, com os anti-exemplos da 24.3 no
  prompt; passo 4 vira "rode o `roda-lanes.sh` e, **no mesmo turno**, despache o `gad-verificador`"
  — a frase "sempre síncrono" e os comandos crus das lanes saíram; filho que devolveu `done` não é
  acordado (correção de decisão = coordenador via `checkpoint-write.py`; pergunta de código nova =
  `gad-explore`).
- **`prompts/intent-spec.md`** (R2, R4, R5a, R7, R8) — toda regra que compara, ordena, itera ou lê
  um campo cita o `arquivo:linha` do **tipo** e diz o **comportamento nulo**; decisão do PRE-SPEC
  entra marcada `[pre-spec:PS-nn]` e o que o spec acrescenta em cima vai em frase/AC separado
  `[auto]`; passe de consistência `MUST NOT` × AC antes do commit; as três seções novas do SPEC
  passam a ser preenchidas; lições viram checklist respondido no `.sinos-spec.txt` em vez de peso
  no briefing.
- **`prompts/intent-discuss.md`** — **proibido ler SPEC, código ou PRE-SPEC antes da Skill** (na
  24.3 o filho foi de 35 k a 81 k assim); o PRE-SPEC é **autodetectado pelo workflow forkado**, o
  filho não passa flag nem abre o arquivo.
- **`prompts/intent-verifica.md`** — o passo 0 espera o **status com o mesmo `run_id` e nonce**, não
  o `.done`; `usable:false` → `sem_parecer` na hora; achado de lane sem nonce continua na tabela
  marcado `independente=false` (corroboração, nunca descarte); seção nova dos vereditos dirigidos.
- **`briefing-build.sh`**: o ROADMAP entra com **só a entrada da fase** (antes vinham as vizinhas),
  as lições saem do briefing e o ciclo ≥ 2 ganha "o que mudou" logo após a Missão — briefing c1 da
  24.3 **−52 % em bytes**.
- **`SKILL.md` e `workflow.md`** — §0.5 do PRE-SPEC (bloco obrigatório, rota `legacy` com sino),
  etapa 1 reescrita com os gates novos, e a `/gad-pre-spec` apontada como a rota de criação do
  `NN-PRE-SPEC.md`.

**Lane do agy (T1) e citações (R9)**

- **Modelo esperado da lane `agy-revisor` passa a `Gemini 3.7 Flash`** (`roda-agy.sh`,
  `convergence.md`, `capabilities/agy-revisor/capability.json`) — A/B cego em 3 projetos
  (28/08): **Flash 3.7 High venceu 3×0** (9 brutos → 6 confirmados, 0 falsos, 1,7–2,2 min) contra
  o Gemini 3.1 Pro High (5 brutos → **0** confirmados, 4,9–6,3 min). Reverter é uma linha, e a
  régua de reversão está declarada: 2 fases com Flash abaixo do histórico do Pro.
  Relatório: `auditorias/260828-bench-cachettl-ab-agy.md`.
- **`spot-check-ponteiros.sh` normaliza links markdown antes do grep** — `[t](file:///abs/x.py#L12)`
  e `[x.py:12](/abs/x.py:12)` colapsam no mesmo alvo `/abs/x.py:12` (`#L<n>` → `:<n>`), com dedup
  depois e saída `referencias_vistas=N · alvos_unicos=M · OK M'/M`. Vai no mesmo commit do T1: o
  Flash cita nesse formato e sem isso os `MISSING-FILE` seriam falsos em massa (180 → 27 nos 12
  pareceres reais).

**Bancadas e decisões tomadas por dado (onda 3)**

- **E1 — TTL de cache por agente.** O `gad-plan` passa a `experimental.cacheTtl: 1h`. A medição
  (`turnos-por-ciclo.py --gaps`, com decomposição do `cache_creation` pós-gap em *prefixo reescrito*
  × *sufixo novo*) nas 3 últimas fases reais do grupo-inspired mostra o `gad-plan` reescrevendo
  281,8 k / 2 701,8 k / 689,1 k tokens de prefixo em 20 gaps de 5–10 min — todos expirações totais
  (`cache_read = 0`) com sufixo novo de 0,3–5 k: a assinatura do *waiter* esperando os filhos do
  `gsd-plan-phase`. Saldo da desigualdade (benefício × 1,15 − custo × 0,75): **−0,39 / +3,82 /
  +0,52 US$** → positivo em 2 de 3, entra. O `gad-intent` reconferido pela mesma régua confirma
  (+0,90 / −0,28 / +0,89). O **`gad-contratos` fica em 5m por falta de dado** (0 instâncias nas
  3 fases). Em *overage* o balde de 1h é ignorado; a auditoria reporta o balde **efetivo**.
  Bancada: `intencao-ajustes/bancadas/E1-gaps.md`.
- **S4 — a convenção de ponteiro NÃO entra.** `bancadas/mede-repeticao-spec.py` mediu 4 pares
  SPEC × PRE-SPEC reais: **0,5 % dos parágrafos** repetidos (limiar 0,8; Jaccard-3 concorda com
  0,1 %), contra os ≥ 30 % que o S4 exigia — o SPEC condensa o PRE-SPEC, não o copia. O
  `intent-spec.md` diz isso explicitamente para ninguém "otimizar" trocando corpo por
  `→ NN-PRE-SPEC.md §x`. O que sobrou do S4 é a guarda, **alargada**: `AC-POR-PONTEIRO` agora
  pega `ver §x`, `→ §x` e `conforme PRE-SPEC §x` além da forma original, e continua deixando
  passar o AC que apenas **termina** com a citação (corpo próprio). Bancada:
  `intencao-ajustes/bancadas/S4-medicao.md`.

**Outros**

- **`abre-rodada.sh`** usa `expected_phase_dir` e sai com **exit 5** quando a fase não existe — fim
  do diretório fantasma `$NN-nova`.
- **`registra-ciclo.sh`** e **`confere-etapa.sh`** absorvem os asserts novos da etapa 1 (R2/R6) e a
  família de pareceres por ciclo.

### Corrigido

- **Canário duplicado da lane do agy.** O nonce nascia em dois lugares e o `grep -q prova_leitura`
  do `roda-agy.sh` **sempre casava** — a prova de leitura saía `ausente` em 100 % dos ciclos, sem
  ninguém notar. Agora o nonce nasce só no `briefing-build.sh`, o `roda-agy.sh` recebe
  `--prova <arquivo>` e extrai o token com `grep -oE 'PROVA-[0-9a-f]+'`; o bloco local vira
  fallback para quando o briefing não cita `prova_leitura`.
- **`roda-agy.sh`/`roda-codex.sh` com caminhos fixos.** Parecer, espelho, `--log` e `--err` eram
  gravados direto em `pareceres/`: dois runs do mesmo ciclo misturavam a evidência de modelo. Os
  scripts ganharam `--out`, `--espelho`, `--log` e `--err`, e o supervisor só passa caminhos do
  run-dir.
- **`rc 6` por modelo divergente deixava o parecer inteiro de fora.** Passa a ser
  `usable:true, independent:false` — degradação de independência, não perda de conteúdo.
- **Três bugs de fiação pegos pela fase descartável de 30/08**: (i) `R-n`/`SC-n` não eram
  normalizados para `Rn`/`SCn` — o `map-pre-spec` nunca casaria uma âncora real (corrigido em
  `pre-spec-batch.py`, `checkpoint-write.py` e na regex do `context-guard.sh`); (ii) o
  `discuss-phase.md` chamava o `discuss-init.sh` **sem `--pre-spec`**, deixando todo o §0.5 como
  código morto (agora autodetecta o `NN-PRE-SPEC.md` da fase); (iii) o `env.sh` do `spec-init.sh`
  era gravado sem `export`, o que fazia o `discuss-hooks-filter.sh` falhar fechado (5 turnos de
  contorno na 1ª rodada).

## [2.1.9] — 2026-08-27

Pacote da auditoria de fecho da F24.3 (grupo-inspired, 2 sessões, 26/08 —
`gsd-optimize/go-and-do-evolucao/auditorias/260826-inspired-f24.3-fecho.md`, tarefa 34).
Treze correções aprovadas pelo dono em 27/08; a 34(e) (regra do conserto pós-gate) ficou de
fora por decisão dele — o caso foi pontual, fica em vigilância.

### Adicionado

- **`scripts/reconcilia-docs.sh`** — reconcilia os espelhos de estado depois do ship
  (tarefa 32e, 3ª reincidência F24→F24.3): STATE.md `executing → between_phases` (+
  `stopped_at`, progresso incremental do milestone), checkbox `[x]` da fase no ROADMAP.md,
  `NN-REVIEW.md` `status: clean` quando o último `REVIEW.iter<k>.md` está clean, frontmatter
  do `NN-REVIEWS.md` derivado do `NN-CONVERGENCE.md`. Idempotente, best-effort (`pendentes`
  no JSON). Roda na 6.5 antes da cancela, nas duas rotas — a rota B (clean-room) não roda o
  gsd-ship e a rota A só toca 2 campos do STATE.md. Validado contra a cópia pré-reconciliação
  da F24.3 (mesmo resultado da reconciliação manual: 8/10 fases, 59/59 planos, 80%).
- **`confere-etapa.sh 6`**: dois asserts novos — `ac_parcial_x_verification` (AC marcado
  PARCIAL/bloqueador em algum SUMMARY com VERIFICATION `passed`; falha 5 da F24.3, em que a
  promoção precedeu a medição do AC em 47 min) e `state_reconciliado` (STATE.md ainda
  `executing` para a fase = reconciliação não rodou). Dry-run contra a F24.3 real reproduz
  a falha 5.
- **`run-log.sh`**: (a) janela órfã fechada automaticamente é **medida** pelo
  `mede-tokens.py` (do checkpoint até agora) — a construção da S2 da F24.3 (7,05M
  tokens_reais) saiu sem custo e o "end corretivo" à mão gravou 251.511 (contexto da camada
  0) como custo; (b) `end` da etapa 5 com `veredito=pass` é **recusado** enquanto o
  `NN-UAT.md` tiver cenário `[pending]`/`blocked`; (c) 2º `end` da mesma etapa na mesma
  sessão declara `substitui:<seq>` (o UAT da F24.3 foi somado em dobro: 504k vs 260k);
  (d) o detector de `compact` só compara checkpoints (o 251.511 de um `end` gerou compact
  falso). Selftest +3 casos (31/31).
- **`registra-ciclo.sh <pd> <NN> <k> [intencao|convergencia]`** — 4º argumento escolhe a
  família de pareceres (na F24.3 o c1 da convergência contou 10 brutos onde eram 2, por
  colisão com o c1 da intenção); sem o argumento, compat + aviso quando as duas existem.
  `convergence.md` passa `convergencia`.
- **`confere-etapa.sh`**: o pass que destrava um fail grava evento `script` (`exit=0`, "pass
  pós-fail") — só a reprovação aparecia no run-log (F24.3 4.4).

### Alterado

- **Merge automático é rota normal** (decisão do dono 27/08: a skill automatiza de ponta a
  ponta; ele não revisa PR e confia nas etapas). `SKILL.md`, `workflow.md` (critério 3 da
  Sub-rotina I, 6.4-SHIP rota B, 6.5): o merge — inclusive `ship.py --merge` do clean-room —
  está no trilho sancionado e não pergunta; o que a rota DEVE é o aviso (banner com `PR #N —
  mergeado`, 6.4c). `resumo.md`: "confira antes de dar merge" → "o merge é automático nesta
  rota; o desfazer está no Desfecho do ship".
- **Waiter em disco** (8 prompts: `execute`, `secure`, `plan`, `validate`, `code-review`,
  `close`, `eval-review`, `convergence`): o marcador esperado é criado pelo **próprio comando
  de fundo** (`( … ; touch <arq> ) &`); nunca esperar por um arquivo que "o harness" deveria
  criar (F24.3 4.4: ~40 min esperando um `.done` que ninguém escrevia); teto = duração
  esperada + 5 min, estourou → decide pelo disco. *(Diferente do que o relatório de 27/08
  sugeriu — "o harness avisa" — porque um host de camada 1 NÃO recebe notificação de
  background; o waiter continua sendo o único mecanismo, o bug era o contrato do arquivo.)*
- **`hooks/gad-lifecycle.sh`**: semântica do campo `camada` = camada do agente DESPACHADO
  (= `spawnDepth`: filho da camada 0 → 1, neto → 2). Até a 2.1.8 era "camada de origem"
  (spawnDepth−1) e nunca chegava a 2 (tarefa 34d). Despacho `general-purpose` sem `model` e
  sem def grava o modelo do transcript principal + `modelo_herdado:true` em vez de campo
  ausente (34j — 8/42 despachos cegos na F24.3).
- **`workflow.md`** Sub-rotina G: proibido `end` corretivo à mão com número do harness;
  caminho certo = `mede-tokens.py` na janela. Contrato de retorno: **um evento `incidente`
  por item** (F24.3: 1 evento para 9 incidentes, 5 sem registro). `execute.md`: um item por
  incidente na lista.
- **`plan.md`**: critério do pattern-mapper lê os artefatos que LISTAM arquivos (SPEC/RESEARCH/
  PLAN), não uma impressão do CONTEXT (F24.3: mapper suprimido com o plano 02 criando
  arquivo novo); todo `skip` leva o motivo no 10º argumento do `run-log.sh` (o campo já
  existia; o gad-plan não usava).
- **`close.md`** passo 0: commit de código depois do `verified:` do VERIFICATION → suíte
  completa no HEAD antes da promoção `human_needed → passed` (`EXEC-NN-SUITE-HEAD-FINAL`
  no DECISOES); AC parcial em SUMMARY não promove.
- **`intent-discuss.md`**: `--chosen-option` é 0-indexado (12 decisões marcadas erradas na
  F24.3, autocorrigidas em 6 turnos). **`code-review.md`**: timestamps do frontmatter são
  `date -Is` real, nunca placeholder.

### Corrigido

- **`roda-codex.sh`**: o retry (gpt-5.6-terra) sobrescrevia um parecer VÁLIDO do gpt-5.6-sol
  quando o stderr acusava "at capacity" mas o parecer saía — agora só há retry com parecer
  vazio, e o stderr do 1º modelo fica em `-sol.err`. E `K` não-numérico (`review`, modo
  code-review) abortava o script sob `set -u` em `$((K-1))` — "review: variável não
  associada" (F24.3 4.1, parecer órfão sem `.json`).

## [2.1.8] — 2026-08-25

### Adicionado

- **`estado: falha` no contrato do `gad-discuss`** (`prompts/intent-discuss.md`): quando a
  guarda estrutural do discuss-phase forkado (`context-guard.sh`, gen5-patches tarefa 3b)
  rejeita o CONTEXT 2× por corrupção determinística, o filho devolve `falha` com o `motivo:`
  literal e o caminho do `NN-CONTEXT.rejected.md`. `prompts/intent.md` ganha o branch:
  parada disclosed sem pergunta ao dono, sem revisão adversarial nem plan-phase, `blocked`
  para a camada 0. Sino deixou de ser a única barreira — sino não é controle de fluxo.

### Alterado

- **Marcas `[auto]`/`[pre-spec]` viram campo `origin` do checkpoint.** O discuss forkado
  persiste cada decisão via `checkpoint-write.py add-decision --origin auto|pre-spec` e o
  renderizador emite `- **D-NN [origin, R-n]:**` no CONTEXT (com a âncora ao requisito). O
  prompt do filho instrui o campo, não a prosa. Nota: `--auto` puro não lê mais `chain.md`
  nem encadeia — o passo 4 (zerar a flag) continua como defesa em profundidade.

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
