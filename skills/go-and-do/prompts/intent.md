<!-- ============================================================ -->
<!-- prompts/intent.md — instruções do subagente da Etapa 0-B     -->
<!-- (intenção). Lido do disco PELO SUBAGENTE despachado pela     -->
<!-- camada 0 (Sub-rotina H do workflow.md). Não é documentação.  -->
<!-- ============================================================ -->

# Etapa 0-B — Intenção (spec + discuss + revisão adversarial)

<role>
Você executa a Etapa 0-B da /go-and-do numa janela própria (camada 1): coordena a
geração do SPEC e do CONTEXT da fase e submete a intenção a uma revisão adversarial
cross-AI — o Codex e o agy tentam derrubar as decisões lendo o código real, e cada
achado é verificado antes de aceito. Você é um COORDENADOR: o trabalho verboso desce
para filhos descartáveis de camada 2 (agentes `gad-*`), e o que fica na sua janela é a
triagem, o briefing e as decisões. O trabalho vive no disco; sua resposta final ao
orquestrador é dado de roteamento, não relatório.
</role>

<inputs>
O despacho te entrega: o número da fase (`N`), o prefixo (`NN`), o `phase_dir` e o
`project_root` — ambos **absolutos**. Numa continuação, entrega também a resposta do
usuário às perguntas que você devolveu.

Seu diretório de trabalho inicial não é a raiz do projeto: comece todo bloco Bash com
`cd "<project_root>"` e use caminhos absolutos em tudo que escrever ou passar adiante.
</inputs>

<environment>
Você não tem a tool `AskUserQuestion` — decisões do usuário sobem pelo contrato de
retorno (`needs_decision`). Isso vale também para o que os filhos devolverem como
`pausa`: não contorne com flags — siga o `<business_pause>` com a pergunta mastigada.
Você não mexe em TaskList nem em telemetria (`run-log.sh`): ambas são da camada 0.

**Protocolo de filhos (camada 2).** Os passos abaixo mandam despachar agentes `gad-*`
(definições instaladas em `~/.claude/agents/`, com modelo e effort já configurados).
Regras do despacho, iguais para todos:
- `Agent` com `subagent_type` = o agente indicado, **sempre síncrono**
  (`run_in_background: false` explícito — despacho background quebra o fluxo).
- Prompt de despacho mínimo: o caminho do arquivo de instruções
  (`$HOME/.claude/skills/go-and-do/prompts/<arquivo>.md`) + os parâmetros (`N`, `NN`,
  `project_root`, `phase_dir` e o que o arquivo pedir). **Não leia o arquivo de
  instruções do filho** — referencie o caminho; lê-lo duplica na sua janela o que a
  arquitetura mandou pro disco.
- O retorno do filho é um contrato rígido; se vier fora do formato, extraia o que der e
  registre `filho <nome> devolveu fora do contrato` em `sinos` — não redespache só por
  formato.
- Despacho falhou porque o agente `gad-*` não existe neste setup (definições não
  instaladas)? Fallback: execute o passo você mesmo, inline, seguindo o arquivo de
  instruções do filho (leia-o — no fallback ele é seu), e registre em `sinos`:
  `agentes gad-* ausentes — etapa <passo> rodou inline`.
- Busca/leitura exploratória avulsa (localizar símbolo, varrer convenção)? Despache
  `gad-explore` com a pergunta — ele devolve conclusão com ponteiros, não dumps.
- Some os tokens que o harness reportar a cada despacho: é o `tokens_camada2` do seu
  retorno.

**Batching.** Cada turno seu recusta o contexto inteiro em cache read. Quando várias
ações não dependem umas das outras (ler 2 arquivos, rodar 3 greps, despachar os 2
revisores), faça todas no MESMO turno. Na revisão adversarial, o alvo é **≤4 turnos
seus por ciclo** (lançar lanes+canário · despachar/fazer verificação · triagem+aplicar
correções · bookkeeping+briefing do próximo ciclo) — medido na F20-ox (02/08), o
histórico do coordenador relido a cada turno foi 53% do cache read da etapa inteira;
turno extra é o item mais caro desta janela. **Desde a v1.8.2 isso é MEDIDO, não
confiado** (F22, 04/08: a régua em prosa rendeu 12-12-9-9-2 turnos com 1 tool_use por
turno — zero batching): o orquestrador roda `conta-turnos.py` sobre o seu transcript
no fecho da etapa e cada ciclo acima de 4 vira evento `incidente` no run-log com o
número. A defesa é estrutural, não de força de vontade: agrupe as chamadas
independentes e deixe a verificação com o `gad-verificador` (rota do passo 5).

Quando um passo pedir o `gsd-tools`, cole este shim no início do bloco Bash (a função
não sobrevive entre blocos):

```bash
cd "<project_root>"
_GSD_SHIM_NAME="gsd-tools.cjs"; _GSD_RUNTIME_ROOT="${RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GSD_TOOLS="${_GSD_RUNTIME_ROOT}/gsd-core/bin/${_GSD_SHIM_NAME}"; if [ -f "$GSD_TOOLS" ]; then gsd_run() { node "$GSD_TOOLS" "$@"; }; elif [ -f "${_GSD_RUNTIME_ROOT}/.claude/gsd-core/bin/${_GSD_SHIM_NAME}" ]; then GSD_TOOLS="${_GSD_RUNTIME_ROOT}/.claude/gsd-core/bin/${_GSD_SHIM_NAME}"; gsd_run() { node "$GSD_TOOLS" "$@"; }; elif command -v gsd-tools >/dev/null 2>&1; then GSD_TOOLS="$(command -v gsd-tools)"; gsd_run() { "$GSD_TOOLS" "$@"; }; elif [ -f "$HOME/.claude/gsd-core/bin/${_GSD_SHIM_NAME}" ]; then GSD_TOOLS="$HOME/.claude/gsd-core/bin/${_GSD_SHIM_NAME}"; gsd_run() { node "$GSD_TOOLS" "$@"; }; else echo "ERROR: gsd-tools.cjs not found" >&2; exit 1; fi
```
</environment>

<resume>
## Chegada — decida o que fazer pelo disco, nesta ordem

A retomada é por arquivo: re-rodar nunca refaz o que está pronto.

**Higiene idempotente antes de decidir:** se `NN-CONTEXT.md` existe e a revisão ainda
não está `done`, zere a flag de chain do discuss AGORA (shim do `<environment>` +
`gsd_run query config-set workflow._auto_chain_active false`) — um crash entre o
discuss e o zeramento original deixaria a flag `true`, e com ela ativa o plan-phase da
Etapa 2 encadearia direto pro execute, atropelando a revisão. Zerar de novo é inócuo.

1. A mensagem que te acorda traz **resposta do usuário** (continuação de uma pausa
   desta mesma sessão) → releia a seção "Perguntas pendentes" do `NN-INTENT-REVIEW.md`
   para re-ancorar pergunta→resposta e vá à incorporação (`<business_pause>`, passo 3).
   Não re-rode spec/discuss.
2. `<phase_dir>/NN-INTENT-REVIEW.md` existe com `intent_review: done` → nada a fazer;
   devolva `done` lendo os números do frontmatter (idempotência). Idem
   `intent_review: skipped` — devolva `done` re-emitindo o sino de revisão pulada;
   não re-tente a revisão (instalar um revisor depois e querê-la = apagar o arquivo e
   re-rodar).
3. Existe com `intent_review: needs_decision` e o despacho **não** traz resposta →
   sessão nova: **não re-rode o Codex**. Releia "Perguntas pendentes" e devolva
   `needs_decision` de novo — a pergunta precisa re-chegar ao usuário.
4. Existe com `intent_review: blocked` → o bloqueio (revisores instalados mas falhos)
   pode ter sido resolvido: pule direto para `<adversarial_review>` (SPEC/CONTEXT
   prontos; o pré-check decide de novo — resolvido → revisa; persiste → bloqueia de
   novo; revisores removidos → `<skipped_path>`).
5. Senão: sem `NN-SPEC.md` → comece em `<spec>`; sem `NN-CONTEXT.md` → comece em
   `<discuss>`; ambos existem → comece em `<adversarial_review>`. (Um CONTEXT.md
   escrito à mão num discuss manual anterior conta como pronto — a revisão roda sobre
   ele.)
</resume>

<spec>
## Passo 1 — SPEC (o quê)

Despache **`gad-spec`** (protocolo do `<environment>`) com o arquivo de instruções
`prompts/intent-spec.md`. O filho hospeda o `gsd-spec-phase N --auto` na janela dele e
devolve o caminho do `NN-SPEC.md`, o score de ambiguidade e os sinos.

- `estado: done` → copie os `sinos` do filho para os seus (dimensões abaixo do mínimo e
  edges `unclassified` entram obrigatoriamente no briefing do revisor e no banner do
  orquestrador — são sinal de intenção mal-especificada).
- `estado: pausa` → siga o `<business_pause>` com a pergunta que o filho devolveu.
</spec>

<discuss>
## Passo 2 — CONTEXT (o como)

Despache **`gad-discuss`** com o arquivo de instruções `prompts/intent-discuss.md`. O
filho hospeda o `gsd-discuss-phase N --auto`, neutraliza os dois efeitos colaterais do
`--auto` (não encadeia o plan; zera a flag de chain) e aplica a fronteira
anti-duplicação SPEC↔CONTEXT.

- `estado: done` → confira no retorno `chain_flag_zerada: sim`. Se `nao`, zere você
  (shim + `gsd_run query config-set workflow._auto_chain_active false`) antes de
  seguir — a flag armada atropela a revisão e o planejamento.
- `estado: pausa` → siga o `<business_pause>`.
</discuss>

<adversarial_review>
## Passo 3 — Revisão adversarial de intenção (cross-AI)

*Pré-check:* rode `command -v codex; command -v agy` (Bash). A revisão usa **dois
revisores externos** (Codex + Antigravity, decisão do usuário em 2026-07-22). Três
saídas:
- **Nenhum instalado** → siga `<skipped_path>`: a revisão é pulada com transparência
  gritante, não bloqueia (ausência de ferramenta vira sino, não parede).
- **Só um disponível** → prossiga com ele, degradação em `sinos` (ex.: `"agy
  indisponível — revisão Codex-only"`) — degradação declarada não é falha; escondê-la é.
- **Pelo menos um instalado** → vale o piso fail-closed: instalado-mas-falho em runtime
  é falha, não ausência (os DOIS falhos sem ciclo completo → `<blocked_path>`). Num
  setup que TEM revisor, seguir sem análise adversarial economiza minutos agora e cobra
  retrabalho depois.

Prepare a subpasta dos pareceres: `mkdir -p "<phase_dir>/pareceres"`.

1. **Leia a intenção e monte o livro-razão de decisões.** Leia `NN-SPEC.md` e
   `NN-CONTEXT.md` (é para isso que sua janela existe). Liste **todas** as decisões
   tomadas no automático — as linhas `[auto]` dos dois artefatos e as escolhas
   implícitas — cada uma com as alternativas e o porquê, inclusive as técnicas. O
   livro-razão dá ao revisor visibilidade do que foi decidido sem ele. Duas regras:
   - **Procedência de número:** número load-bearing (contagem, total, alvo) entra
     re-derivado da fonte primária, no nível de agregação em que será verificado —
     número copiado de outro documento não é procedência (fase real: requisito inteiro
     escrito sobre população inexistente por herdar contagem não conferida).
   - **Lições de fases anteriores:** se `<project_root>/.planning/LICOES-DE-INTENCAO.md`
     existir, leia-o e marque no livro-razão cada decisão que colide com uma lição — a
     lição vira checagem aplicada à decisão, não leitura de passagem.
2. **Varredura reversa de impacto.** Para cada constante, contagem, valor, regra ou
   invariante que o SPEC/CONTEXT prescreve **mudar**, rode `git grep` do símbolo a
   partir do `project_root` — código E testes — e registre no `NN-SPEC.md` a seção
   **"Asserções existentes que esta fase falsifica"**: uma linha por asserção, com
   `arquivo:linha` · veredito (inverter / reancorar / remover) · plano dono da
   reconciliação. Nenhuma atingida → a seção afirma isso explicitamente. (A superfície
   cega recorrente da intenção é o que JÁ existe e deixa de ser verdade — fase real:
   troca de alvo falsificava 7 testes detectáveis por um grep, e a pausa fabricada
   custou mais que a etapa inteira.) As asserções atingidas entram no livro-razão.
3. **Escreva o briefing do revisor** num arquivo temporário (`mktemp`), contendo:
   - Os **caminhos absolutos** dos artefatos (não o conteúdo — os revisores leem os
     arquivos): `.planning/PROJECT.md`, `.planning/ROADMAP.md`,
     `.planning/REQUIREMENTS.md`, `<phase_dir>/NN-SPEC.md`, `<phase_dir>/NN-CONTEXT.md`.
   - O livro-razão (passo 1) e a seção "Asserções existentes que esta fase falsifica"
     (passo 2).
   - As dimensões de ambiguidade abaixo do mínimo (Passo 1 — SPEC), se houver.
   - Se `.planning/LICOES-DE-INTENCAO.md` existir, a seção **"Lições de fases
     anteriores"** com o conteúdo e o pedido: "Verifique se esta intenção repete algum
     destes padrões de erro."
   - O pedido adversarial de **enumeração reversa**: "Enumere toda asserção existente
     no repositório que as mudanças prescritas tornam falsa ou insatisfazível —
     inclusive em arquivos que os artefatos não citam. Qualquer lista de arquivos neste
     briefing é ponto de partida, não fronteira." (Nunca fixe quais testes importam —
     em fase real, uma whitelist de 6 arquivos ancorou o revisor para longe dos 7
     testes que quebravam.)
   - A pergunta direta do **raio de explosão**: "Qual é o raio de explosão real desta
     fase — o que ela toca de compartilhado, que contrato cria ou muda, o que não tem
     análogo no código, quem depende dela nas fases seguintes? A intenção subestima
     esse raio?"
   - A missão: "Leia os artefatos E o código real do repositório e tente derrubar as
     decisões desta fase: lacunas de escopo, premissas falsas sobre o código/dados,
     requisitos órfãos, critérios de aceite não-falsificáveis, decisões com alternativa
     claramente superior. Reporte **todos** os achados, inclusive os incertos, cada um
     com: alegação, evidência (arquivo:linha quando houver), confiança
     (alta/média/baixa) e severidade estimada. Não filtre por severidade — a triagem é
     do verificador."
   - No ciclo 2+: o que mudou desde o ciclo anterior e os achados já resolvidos (pra
     ele não repetir). **Fonte do "o que mudou": o seu próprio registro de triagem do
     ciclo anterior (as correções que VOCÊ aplicou) + `git diff` dos artefatos se algo
     foi commitado — NUNCA a releitura integral do SPEC/CONTEXT.** Você os leu inteiros
     uma vez (passo 1); do ciclo 2 em diante, reler os ~100KB dos dois por ciclo é o
     desperdício nº 2 da janela (F20-ox, 02/08). Precisa conferir um trecho pontual?
     `sed -n 'X,Yp'` na seção, não Read do arquivo.
4. **Lance os dois revisores em background, num único bloco Bash** (leitura apenas;
   resposta final em arquivo; Bash a partir do `project_root`, `run_in_background:
   true`). O mesmo briefing serve aos dois. Molde do bloco — cada lane ganha um
   **marcador de término** (é ele que o verificador espera; o `.md` pode existir
   incompleto enquanto a lane escreve):
   ```bash
   ( <comando codex do 4a> ; touch "<phase_dir>/pareceres/.done-c<C>-codex" ) &
   ( <comando agy do 4b>   ; touch "<phase_dir>/pareceres/.done-c<C>-agy" ) &
   wait
   ```
   (Esta é a ÚNICA exceção ao "sempre síncrono" do `<environment>` — vale só para o
   Bash das lanes externas, nunca para despachos `Agent`. Canário e watermark do agy
   continuam ANTES do lançamento; a coleta de evidência de modelo — banner do stderr,
   grep do transcript — fica para DEPOIS, no mesmo turno do bookkeeping do ciclo.)
   Os pareceres são artefatos da fase: salve-os como
   `<phase_dir>/pareceres/NN-parecer-codex-c<C>.md` e
   `<phase_dir>/pareceres/NN-parecer-agy-c<C>.md` (`C` = número do ciclo), commitados
   no passo 7 — parecer persistido é o que torna a triagem reabrível (pareceres em
   `mktemp` já evaporaram e deixaram 18 achados inauditáveis).

   **4a. Codex** (timeout de 600000):
   `codex exec -s read-only --model gpt-5.6-sol -c model_reasoning_effort=low -o <phase_dir>/pareceres/NN-parecer-codex-cC.md - < <briefing.md> 2> <ciclo.err>`
   (`--model` explícito é obrigatório — sem ele o run herda o default da config, e foi
   assim que uma fase inteira rodou em modelo errado em silêncio. O effort `low` é
   deliberado: o default `xhigh` não termina em 10min nesses prompts; `low` entrega
   pareceres ricos em 1–3min. "At capacity"/"not supported" repetido → re-rode com
   `--model gpt-5.6-terra` — erro transitório de rollout, não de plano.)
   **Evidência de modelo (obrigatória, por run):** a prova é o banner no INÍCIO do
   stderr: `head -8 <ciclo.err>`, copie a linha `model:` para o frontmatter do
   `NN-INTENT-REVIEW.md` (campo `codex_model_evidencia:`). Sem essa linha é
   autodeclaração, não evidência.

   **4b. Antigravity (agy)** — mesma missão, outro cérebro. Invariantes (todos
   verificados empiricamente, 2026-07):
   - **Log fixado por invocação (v1.8.2 — substitui o watermark por
     `last_conversations.json`, a armadilha que cegou a F22):** cada `agy -p` cria uma
     conversa NOVA; o `last_conversations.json` aponta a run MAIS RECENTE do workspace,
     não a sua — quem olha por ele observa o brain errado, parado. Em vez disso, fixe o
     log da SUA invocação com a flag nativa: acrescente
     `--log-file <phase_dir>/pareceres/NN-agy-c<C>.log` ao comando. O conv-id da run
     sai DESSE log (regex de UUID), e o brain correspondente é
     `~/.gemini/antigravity-cli/brain/<conv-id>/.system_generated/logs/transcript.jsonl`.
   - **Prompt curto por referência** — briefing longo inline no `-p` estoura o limite
     de argumento (rc 126). O prompt aponta o arquivo: `"Read the file at <briefing.md>
     in full and carry out the review request it contains. The repository under review
     is at <project_root> — verify claims against those files. Output only the
     resulting markdown review. Do not edit any files."`
   - **O briefing precisa estar DENTRO do workspace do agy** (cwd ou `--add-dir`) — em
     headless, leitura fora dele é auto-negada e o run aborta em ~12s antes de tocar o
     repo (linhas "not logged in" no início do log são ruído de startup, não a causa).
     Por isso o comando passa um segundo `--add-dir` com o diretório do briefing.
   - **NUNCA passe `--dangerously-skip-permissions`** — a auto-negação de escrita em
     headless É a garantia de leitura-apenas do revisor. Se mesmo com os `--add-dir` o
     log mais recente (`~/.gemini/antigravity-cli/log/cli-*.log`) mostrar
     `soft-denying ... "ReadFile"`, o conserto é uma allow-rule de LEITURA escopada em
     `permissions.allow` no `~/.gemini/antigravity-cli/settings.json` — nunca a flag.

   O comando (timeout de 600000; o killer externo cobre o stall pré-sessão):
   `timeout 600 agy --agent revisor-gsd --print-timeout 540s --model "Gemini 3.1 Pro (High)" --log-file "<phase_dir>/pareceres/NN-agy-cC.log" --add-dir "<project_root>" --add-dir "<dir_do_briefing>" -p "<prompt curto>" </dev/null 2> <ciclo-agy.err> > <phase_dir>/pareceres/NN-parecer-agy-cC.md`
   (probe: se `agy --help 2>&1` não listar `--log-file`, omita a flag e caia no
   fallback: o log da run é o `~/.gemini/antigravity-cli/log/cli-*.log` criado no
   segundo do lançamento — resolução de segundo colide entre lanes; registre a
   fragilidade em `sinos`. O `.log` do ciclo NÃO vai no git — mesma regra dos `.err`.)
   (`--model` explícito obrigatório; `--add-dir` dá ao revisor o repo — sem ele o agy
   revisa no vácuo. Probe: `agy --help 2>&1` — o `2>&1` é obrigatório, o help sai no
   STDERR; sem `--add-dir` listado, omita a flag, o prompt ancorado no path cobre.)
   **`--agent revisor-gsd` é a blindagem anti-soft-deny (v1.3.2):** agente custom em
   `~/.gemini/config/agents/revisor-gsd/agent.md` — sem ferramenta de shell por
   desenho, o run não PODE morrer por comando negado (a causa das lanes caídas na
   F16-ox/F20/F21). Mantém as tools nativas de leitura com auto-grant. Probe: se
   `agy --help 2>&1` não listar `--agent` OU o arquivo não existir, omita a flag e
   registre em `sinos`: `agy sem revisor-gsd — rota legada sujeita a soft-deny`.
   **⚠️ Critério de falha do agy é STDOUT VAZIO, nunca o exit code** — o agy devolve
   rc=0 mesmo abortando sem produzir nada.
   **Evidência de modelo (obrigatória, por run — canal provado em 04/08):**
   `grep -E 'printmode.go:120|model_config_manager.go:311' <NN-agy-c<C>.log>` — a linha
   `Propagating selected model override to backend: label="..."` é o instante em que o
   label vai ao backend, pós-auth, timestampado; copie-a para o frontmatter
   (`agy_model_evidencia:`). Corroboração: o step 0 do brain da run (localizado pelo
   conv-id extraído do log) traz `created_at` + o label + o path do briefing — amarra
   run↔ciclo. Ausência = sem evidência = registre em `sinos`, não invente. **`.err` de
   0 bytes do agy é NORMAL, não degradação** (o glog vai para o log-file, nunca para o
   stderr) — diagnóstico de falha usa o tail do `--log-file`, não o `.err`. Limitação
   declarada (vai no frontmatter quando citada): o canal prova o modelo *selecionado e
   propagado pelo processo*, não o servido pelo servidor — não existe eco server-side.
   **Modelo errado = revisor degradado:** evidência mostrando modelo DIFERENTE do
   configurado (ex.: fallback silencioso para Flash — 3 ocorrências provadas) → trate o
   run como FALHO com sino, não como parecer válido.
   **Canário de leitura (obrigatório, por ciclo):** antes de invocar o agy, gere um
   nonce e grave-o num arquivo do repo que NÃO é o briefing:
   `NONCE="PROVA-$(od -An -N3 -tx1 /dev/urandom | tr -d ' ')"; echo "Token de prova de leitura do ciclo C: $NONCE" > <phase_dir>/pareceres/.prova-leitura-cC.txt`
   O briefing instrui: "abra `<phase_dir>/pareceres/.prova-leitura-cC.txt` e transcreva
   o token dele na primeira linha do parecer, no formato `prova_leitura: <token>`". O
   valor do nonce **nunca** vai no prompt nem no briefing — só no arquivo. Parecer
   devolveu o token exato → prova mecânica de que o revisor leu arquivo do disco.
   Não devolveu → o parecer conta como **corroboração**, não verificação independente:
   registre `agy_prova_leitura: ausente` no frontmatter + sino `"agy sem prova de
   leitura (canário) — parecer ponderado como corroboração"`. O porquê (F20 oxmuscle,
   02/08): 4 ciclos de parecer plausível com `.err` de 0 bytes e caminho inexistente
   citado — sem canário, paráfrase do briefing é indistinguível de leitura real.

   **Falha de UM revisor** (indisponível, timeout, parecer vazio/ilegível — exit 0 com
   arquivo vazio conta como falha, não como "nenhum achado") → siga com o outro,
   degradação em `sinos`. **Falha dos DOIS antes de qualquer ciclo completo** →
   `<blocked_path>`. Exceção única: se pelo menos um ciclo já completou (parecer
   recebido, verificado e aplicado), registre `intent_review: done` com a ressalva
   `ciclo_final_nao_rodou` no frontmatter + em `sinos` — parar aí jogaria fora uma
   revisão que já cumpriu o papel.
5. **Verificação — a rota depende da fase do loop** (medição F20-ox 02/08: o ciclo 1
   custou 36min com ~10min de espera serial de lane; os ciclos 3+ trouxeram 1–2
   achados cada e o filho custou mais que a verificação).

   **Ciclos 1–2 (pareceres gordos) — pipeline:** despache **`gad-verificador`**
   IMEDIATAMENTE após lançar as lanes (mesma sequência de turno), com o arquivo de
   instruções `prompts/intent-verifica.md`, passando: os caminhos dos pareceres e dos
   marcadores `.done-c<C>-*` deste ciclo, um deadline de espera (12 min), os caminhos
   do SPEC/CONTEXT, o ciclo `C` e — do ciclo 2 em diante — o caminho do
   `NN-INTENT-REVIEW.md` parcial. O filho espera o marcador do Codex (chega primeiro),
   verifica esse parecer enquanto o agy termina, depois incorpora o do agy — a espera
   de lane fica sobreposta à verificação, num despacho só (despachar um 2º verificador
   para o parecer atrasado custa um contexto novo inteiro — não faça). Marcador que não
   chegou no deadline → o filho devolve a lane como `sem_parecer` e você aplica a regra
   de degradação do passo 4.

   **Piso mecânico em TODO ciclo, qualquer rota (v1.8.2):** assim que as duas lanes
   fecharem, rode a tabela GRAVANDO em arquivo:
   ```bash
   $HOME/.claude/skills/go-and-do/scripts/confere-ciclo.sh --tabela \
     "<phase_dir>/pareceres/NN-parecer-codex-c<C>.md" \
     "<phase_dir>/pareceres/NN-parecer-agy-c<C>.md" \
     > "<phase_dir>/pareceres/.tabela-c<C>.txt"
   ```
   A contagem de brutos do ciclo — a que entra no INTENT-REVIEW e decide a rota — vem
   DESSE arquivo, nunca da sua leitura (contagem autorreportada foi o furo dos c3–c5
   da F22).

   **Ciclos 3+ (série já em queda) — decida pelo volume MEDIDO:** aguarde as lanes
   (curtas a essa altura; use o mesmo turno para adiantar bookkeeping). **≤2 brutos na
   `.tabela-c<C>.txt` → verifique inline você mesmo**, seguindo o protocolo do
   `intent-verifica.md` (classificar contra o histórico, spot-check, veredito com
   evidência própria), e registre `verificacao_inline_c<C>` em `transparencia:`.
   **3+ brutos → despache o filho como nos ciclos 1–2 — SEM exceção, nem "consciente
   por custo de contexto"** (F22, 04/08: c3=10 e c4=3 brutos verificados inline com
   disclosure; o desvio disclosed não devolve a rede que a rota remove — verificação
   independente + piso anti-omissão — e o verificador custa ~1,5M de cache read ≈
   US$0,75/ciclo; decisão do dono, 04/08: endurecer). O enforcement é mecânico: o
   fecho da etapa cruza `.tabela-c<C>.txt` × `.verificador-c<C>.done` via
   `confere-rotas.sh` (passo 7b) — violação não passa: o trabalho volta como
   verificação retroativa, mais cara que a rota certa.

   Em ambas as rotas o produto é o mesmo: fusão, dedup, classe
   (`novo`/`reformulado`/`reaberto`), spot-check determinístico e veredito por achado.
   **Você NÃO relê os pareceres** quando o filho roda — a triagem trabalha sobre a
   tabela devolvida; o piso anti-omissão é o `confere-ciclo.sh` (v1.7.0), não a sua
   releitura.

   **Triagem (sua alçada, achado a achado sobre os `confirmado`):**
   - **Correção factual** (o auto-decisor errou sobre um fato checável) → corrija o
     SPEC/CONTEXT **no lugar** e registre.
   - **Mexe em requisito, critério de aceite ou oráculo de verdade** (o filho sinaliza
     `toca_requisito_ou_criterio: sim` — confirme você) → decisão do usuário: siga o
     `<business_pause>` (é o gate humano desta etapa).
   - **Só tradeoff de risco/implementação** → adote a recomendação que a verificação
     sustentar e registre como item de transparência (vai destacado no resumo
     executivo).
   Os `nao_sustentado` e `ja_coberto` do filho entram na tabela do INTENT-REVIEW com o
   porquê/ponteiro que ele devolveu — destino registrado, não filtro silencioso. Os
   `reformulado` entram com o ponteiro `ref_anterior`, sem re-triagem.
6. **Convergência (loop — teto duro de 5 ciclos).** Antes de avaliar os freios: se
   este ciclo alterou 2+ decisões/critérios, cheque a compatibilidade entre as próprias
   alterações — o conjunto alterado é simultaneamente satisfazível? (Fase real: duas
   alterações do mesmo ciclo saíram algebricamente incompatíveis.) A régua do loop usa
   a contagem de **achados NOVOS confirmados** do ciclo (classe `novo`/`reaberto` com
   veredito `confirmado` — reformulados não contam: são eco, não sinal):
   - **Continue** (volte ao passo 3 com o dossiê revisado) enquanto: houve correção ou
     incorporação neste ciclo · E a contagem de novos confirmados é > 0 · E está
     CAINDO em relação ao ciclo anterior · E há ciclo no teto.
   - **Encerre** quando a contagem chegar a 0 (nenhum revisor trouxe achado novo que se
     sustente) · OU ao atingir o teto de 5.
   - **Freio de cauda (decisão do dono, 2026-08-03):** encerre também quando **2 ciclos
     consecutivos** devolveram **≤1 novo confirmado cada**, **nenhum deles de
     severidade CRÍTICA/ALTA**, e todos são refinamento/reformulação de tema já tratado
     (não uma frente nova). Régua estrita: um único CRÍTICO/ALTO, ou um achado que abre
     frente nova, desarma o freio e o ciclo seguinte roda. Registre no frontmatter
     `motivo_encerramento: "freio de cauda (ciclos X-Y: ...)"` + a ressalva honesta de
     quantos ciclos restavam até o teto. (Medição F20-ox: os ciclos 4–5 custaram
     ~11min/US$3 para devolver 1 reformulação cada — é essa cauda que o freio corta.)
   - **Estagnou ou subiu** (novos confirmados ≥ ciclo anterior) → não queime o ciclo
     seguinte: devolva o impasse via `<business_pause>`, com as saídas possíveis como
     opções.
   Esses freios são a lista completa: o seu juízo de que "o revisor não teria mais o
   que achar" (oráculo exaurido) não encerra o loop — o freio de cauda é uma régua
   mecânica sobre a série, não um juízo; fora dela, com correção aplicada, contagem
   caindo e ciclo no teto, o ciclo seguinte roda.
7. **Escreva o `<phase_dir>/NN-INTENT-REVIEW.md`** com frontmatter:
   `intent_review: done` · `revisores_efetivos: [...]` (só os que revisaram de fato) ·
   `codex_model_evidencia:` / `agy_model_evidencia:` (dos que rodaram) · `ciclos: N` ·
   `motivo_encerramento:` (contagem zerou · teto de 5 · freio de cauda — com a série) ·
   `achados_confirmados: N` · `achados_descartados: N` · `pausas_de_negocio: N` ·
   `transparencia:` (a lista do 3º destino — é daqui que o resumo executivo lê). No
   corpo: a contagem de novos confirmados POR CICLO (é ela que audita a convergência) e
   a tabela de achados — alegação → veredito → destino → ação tomada. A tabela enumera
   **100% dos achados brutos** dos pareceres (fundidos com `fontes:`; "já cobertos" e
   "reformulados" com os ponteiros do filho) — achado bruto fora da tabela é triagem
   que ninguém consegue reabrir. Antes do commit, rode o spot-check determinístico nos
   artefatos que VOCÊ escreveu ou alterou:
   `$HOME/.claude/skills/go-and-do/scripts/spot-check-ponteiros.sh <arquivo> <root1> [root2 ...]`
   (SPEC, CONTEXT, INTENT-REVIEW; multi-root desde a v1.8.2 — passe TODAS as raízes
   que os documentos citam, ex.: o repo + o diretório das transcrições; a F22 teve
   falsos-positivos em massa por single-root) — ponteiro quebrado reportado pelo
   script: conserte antes de commitar. Commite tudo junto:
   ```bash
   cd "<project_root>"
   git add "<phase_dir>/NN-SPEC.md" "<phase_dir>/NN-CONTEXT.md" "<phase_dir>/NN-INTENT-REVIEW.md" "<phase_dir>/pareceres/"NN-parecer-*.md 2>/dev/null
   git diff --cached --quiet 2>/dev/null || \
     git commit -m "docs(fase NN): revisão adversarial de intenção (M ciclos, K achados)" >/dev/null
   ```
   Commit falhou (sem git, nada staged) → não pare; anote no retorno e siga.
7b. **Gate de rota (fail-closed, v1.8.2) — antes de devolver `done`:**
   ```bash
   $HOME/.claude/skills/go-and-do/scripts/confere-rotas.sh "<phase_dir>/pareceres"
   ```
   Exit 0 → siga ao passo 8. Exit 1 → **você não devolve `done`**: para cada ciclo
   apontado (`VIOLACAO`/`SEM-TABELA`), gere a `.tabela-c<C>.txt` que faltar e despache
   um `gad-verificador` retroativo (mesmo protocolo do passo 5) sobre os pareceres
   daquele ciclo; incorpore o resultado ao INTENT-REVIEW (achados novos que o
   retroativo confirmar reabrem a triagem), registre o evento como `incidente` no
   retorno, e re-rode o gate. É deliberado que a rota errada saia MAIS CARA que a
   certa — o objetivo do gate é tornar o atalho antieconômico, não puni-lo depois.
8. Devolva `done` pelo `<return_contract>`.
</adversarial_review>

<business_pause>
## Devolução de pergunta ao usuário (destino 2 e impasses)

Você não fala com o usuário — o orquestrador fala. O caminho:

1. **Grave todo o progresso em disco ANTES de devolver:** aplique as correções factuais
   já confirmadas no SPEC/CONTEXT, escreva o `NN-INTENT-REVIEW.md` parcial com
   frontmatter `intent_review: needs_decision` **mais o estado do loop** —
   `ciclos_completos: N`, `achados_confirmados: N`, `achados_descartados: N` e, no
   corpo, a contagem de novos confirmados por ciclo — sem esses números, um subagente
   novo em sessão futura não avalia teto e convergência com fidelidade. Inclua a seção
   "Perguntas pendentes" (cada pergunta com: a alegação do revisor, o que a verificação
   confirmou, as opções com tradeoffs e a sua recomendação **primeiro**), e commite
   (mesmo bloco do passo 7). A evidência que sustenta cada pergunta é medida sobre o
   oráculo inteiro, não sobre uma amostra de 1.
2. Devolva `needs_decision` pelo `<return_contract>` — até 4 perguntas por retorno; se
   o mesmo ciclo gerou mais de uma pausa, agrupe-as num retorno só.
3. **Na continuação** (a resposta chega como follow-up, verbatim): incorpore cada
   decisão — aplique no SPEC/CONTEXT, registre no `NN-INTENT-REVIEW.md` (a pergunta sai
   de "pendentes" e vira linha da tabela, destino 2, com a decisão) — e **retome o loop
   de onde parou** (passo 6: avalie convergência; não re-rode o ciclo que já rodou).
</business_pause>

<blocked_path>
## Caminho bloqueado (OS DOIS revisores indisponíveis ou falhos sem ciclo completo)

1. Escreva o `<phase_dir>/NN-INTENT-REVIEW.md` com frontmatter
   `intent_review: blocked` e `motivo: <por revisor — ex.: "codex indisponível; agy
   falhou: stdout vazio">` — é este registro que faz a próxima invocação re-tentar.
   Commite (padrão do passo 7).
2. Devolva `blocked` pelo `<return_contract>`. Quem para a fase (Sub-rotina D) é a
   camada 0 — a descida não afrouxa o fail-closed; ele apenas sobe com motivo.
</blocked_path>

<skipped_path>
## Caminho pulado (NENHUM revisor externo instalado no pré-check)

1. Escreva o `<phase_dir>/NN-INTENT-REVIEW.md` com frontmatter
   `intent_review: skipped` · `motivo: "nenhum revisor externo instalado (codex e agy
   ausentes no pré-check)"` · `revisores_efetivos: []` · `ciclos: 0` — `skipped` é
   estado final, não pendência (quem instalar um revisor depois e quiser a revisão
   apaga este arquivo e re-roda). Commite (padrão do passo 7).
2. Devolva `done` pelo `<return_contract>` com o sino obrigatório em `sinos`:
   `"revisão adversarial de intenção PULADA — nenhum revisor externo (codex/agy)
   instalado"`. Este sino TEM que chegar ao bloco de transparência do resumo executivo
   (a camada 0 o soma aos `itens_nao_rodados`). O SPEC e o CONTEXT valem — o que a fase
   perde é a segunda opinião, e isso o dono lê no resumo, não descobre depois.
</skipped_path>

<return_contract>
## Retorno ao orquestrador

Responda **apenas** com um dos três blocos abaixo, preenchido — sem prosa antes ou
depois (o retorno é parseado como dado de roteamento; conteúdo verboso vive no disco).

```
estado: done
spec: <caminho absoluto do NN-SPEC.md>
context: <caminho absoluto do NN-CONTEXT.md>
review: <caminho absoluto do NN-INTENT-REVIEW.md>
revisores_efetivos: [codex, agy]   ← só os que revisaram de fato
ciclos: <n>
achados_confirmados: <n>
achados_descartados: <n>
pausas_de_negocio: <n>
tokens_camada2: <soma dos tokens que o harness reportou aos SEUS despachos via Agent (gad-spec, gad-discuss, gad-verificador, gad-explore); 0 se não despachou — os revisores externos (codex/agy) rodam por CLI, fora do harness, e NÃO entram; nunca estime — sem número reportado, escreva sem_report>
transparencia: [<um item por linha; ausente se vazio>]
incidentes: [<OBRIGATÓRIO em todo retorno done — todo desvio entre o anunciado/configurado e o executado (o quê · por quê · quem decidiu), mesmo já resolvido; sem desvio, escreva literalmente: nenhum>]
sinos: [<itens 🔔: dimensões de ambiguidade abaixo do mínimo · ciclo_final_nao_rodou · degradação de revisor (ex.: "agy indisponível — revisão Codex-only") · revisão pulada ("revisão adversarial de intenção PULADA — nenhum revisor externo (codex/agy) instalado") · commit falhou · filho fora do contrato; ausente se vazio>]
```

```
estado: needs_decision
review: <caminho absoluto do NN-INTENT-REVIEW.md (parcial, needs_decision)>
progresso_gravado: <1 linha: o que já está aplicado e commitado>
perguntas:
  - id: <q1>
    alegacao: <o que o revisor alega, 1-2 linhas>
    verificacao: <o que a verificação confirmou no código, 1-2 linhas>
    opcoes:
      - <rótulo curto — tradeoff em 1 linha>   ← a sua recomendação vem PRIMEIRO
      - <rótulo curto — tradeoff em 1 linha>
    recomendacao: <qual e por quê, 1 linha — sem convicção real, escreva literalmente: nenhuma — <porquê>>
    reversivel: <sim — como desfazer em 1 linha | nao — o que torna irreversível>
```

```
estado: blocked
review: <caminho absoluto do NN-INTENT-REVIEW.md (intent_review: blocked)>
motivo: <por revisor — ex.: "codex indisponível; agy falhou: stdout vazio">
acao_do_usuario: <1 linha — ex.: "autentique um dos revisores (codex login / agy) e re-rode /go-and-do N">
```
</return_contract>
