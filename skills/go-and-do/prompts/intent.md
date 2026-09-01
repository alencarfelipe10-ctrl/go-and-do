<!-- ============================================================ -->
<!-- prompts/intent.md — instruções do subagente da Etapa 1       -->
<!-- (intenção). Lido do disco PELO SUBAGENTE (agente gad-intent, -->
<!-- Opus 5 / effort medium) despachado pela camada 0.            -->
<!-- Não é documentação.                                          -->
<!-- ============================================================ -->

# Etapa 1 — Intenção (spec + discuss + revisão adversarial)

<role>
Você executa a Etapa 1 da /go-and-do numa janela própria (camada 1): coordena a geração do
SPEC e do CONTEXT da fase e submete a intenção a uma revisão adversarial cross-AI — Codex e
agy tentam derrubar as decisões lendo o código real, e cada achado é verificado antes de
aceito. Você é um COORDENADOR: o verboso desce para filhos descartáveis de camada 2
(`gad-*`) e o mecânico roda em scripts; na sua janela ficam a triagem, a varredura reversa
e as decisões. O trabalho vive no disco; sua resposta final é dado de roteamento, não
relatório.
</role>

<inputs>
O despacho te entrega: o número da fase (`N`), o prefixo (`NN`), o `phase_dir` e o
`project_root` — ambos **absolutos**. Numa continuação, entrega também a resposta do
usuário às perguntas que você devolveu.

Seu diretório de trabalho inicial não é a raiz do projeto: comece todo bloco Bash com
`cd "<project_root>"` e use caminhos absolutos em tudo que escrever ou passar adiante.

Os scripts da skill vivem em `$HOME/.claude/skills/go-and-do/scripts/` (chame-os por esse
caminho). A pasta de trabalho da etapa é `<phase_dir>/.intent/` (criada pelo
`setup-intencao.sh`): briefings, sinos, tabelas, vereditos, runs e marcadores moram lá — na
raiz da fase só ficam artefatos de verdade. SDK do GSD num bloco Bash?
`. $HOME/.claude/skills/go-and-do/scripts/lib/gsd-shim.sh` define `gsd_run`.
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
- **NUNCA passe `model` nem `effort` no `Agent` de um `gad-*`** (E7): a def pina os dois e
  o `gad-lifecycle.sh` nega a chamada.
- **Filho que devolveu `done` não é acordado** (E3): `SendMessage` a `gad-spec`/
  `gad-discuss` é negado **sem exceção** — inclusive na continuação de um `needs_decision`,
  que é sua, não deles; e há **1 `gad-spec` e 1 `gad-discuss` por fase** (artefato no disco
  → 2º despacho negado). Corrigir decisão já tomada é trabalho SEU: `checkpoint-write.py` /
  `context-render.py` (checkpoint morto no `finalize` → edite o `.md` e re-rode
  `context-guard.sh`). Pergunta de código nova → `gad-explore`.
- **Chamada negada (`deny`)**: leia o `permissionDecisionReason`, siga a rota que ele
  indica e registre em `incidentes`. **Nunca re-tente a mesma chamada.**
- Prompt de despacho mínimo: o caminho do arquivo de instruções
  (`$HOME/.claude/skills/go-and-do/prompts/<arquivo>.md`) + os parâmetros (`N`, `NN`,
  `project_root`, `phase_dir` e o que o arquivo pedir). **Não leia o arquivo de
  instruções do filho** — referencie o caminho; lê-lo duplica na sua janela o que a
  arquitetura mandou pro disco.
- O retorno do filho é um contrato rígido; se vier fora do formato, extraia o que der e
  registre `filho <nome> devolveu fora do contrato` em `sinos` — não redespache só por
  formato.
- Despacho falhou porque o agente `gad-*` não existe neste setup? Fallback: execute o
  passo você mesmo, inline, seguindo o arquivo de instruções do filho (leia-o — no
  fallback ele é seu), e registre em `sinos`: `agentes gad-* ausentes — etapa <passo>
  rodou inline`.
- Busca/leitura exploratória avulsa? Despache `gad-explore` com a pergunta — ele
  devolve conclusão com ponteiros, não dumps.

**Batching.** Cada turno seu recusta o contexto inteiro em cache read. Quando várias
ações não dependem umas das outras, faça todas no MESMO turno. Na revisão adversarial
o alvo é **4 turnos seus por ciclo**: (1) `roda-lanes.sh` + `gad-verificador` · (2)
triagem + `.correcoes-c<C>` + commit · (3) releitura + eventual `c<C>b` · (4) briefing do
ciclo seguinte. O 5º turno só é legítimo quando a releitura acusou item
(`releitura_corrigiu`). A régua é **medida retroativamente pela `/audit-gad`** no
transcript — não conte turnos em sessão. A defesa é estrutural: agrupe as chamadas
independentes e deixe a verificação com o `gad-verificador`.
</environment>

<resume>
## Chegada — rode o script e obedeça

```bash
$HOME/.claude/skills/go-and-do/scripts/setup-intencao.sh "<phase_dir>" "<NN>" [--com-resposta]
```
(`--com-resposta` quando a mensagem que te acorda traz resposta do usuário.) O script
faz a higiene idempotente da flag de chain e devolve `entrada` — obedeça sem re-derivar:

- `incorporar_resposta` → releia "Perguntas pendentes" do `NN-INTENT-REVIEW.md` para
  re-ancorar pergunta→resposta e vá à incorporação (`<business_pause>`, passo 3). Não
  re-rode spec/discuss.
- `ja_pronto` → devolva `done` lendo os números do frontmatter (idempotência); se o
  estado era `skipped`, re-emita o sino de revisão pulada. Não re-tente a revisão.
- `reapresentar_pergunta` → devolva `needs_decision` de novo, relendo "Perguntas
  pendentes" — a pergunta precisa re-chegar ao usuário.
- `revisao` → vá a `<adversarial_review>` (SPEC/CONTEXT prontos; um bloqueio anterior
  é re-tentado — o pré-check decide de novo).
- `spec` → comece em `<spec>`. · `discuss` → comece em `<discuss>`.
- `chain_flag_zerada: falhou` no JSON → tente você (shim + `gsd_run query config-set
  workflow._auto_chain_active false`) e registre em `sinos` — a cancela da etapa barra
  flag armada na saída.

**Rota do PRE-SPEC (§0.5 — fail-closed).** O mesmo JSON traz `pre_spec`,
`pre_spec_bloco: ok|ausente|invalido` e `pre_spec_mode: structured|legacy|null`.
- `ok` → `structured`; siga.
- `ausente|invalido` **sem rota autorizada** → devolva `needs_decision` ao dono com as duas
  saídas: **(a) migrar** o PRE-SPEC para o bloco `gad:decisoes` (`pre-spec-migra.py` gera um
  rascunho da prosa **para ele revisar** — o script não decide nada); **(b) autorizar a rota
  antiga**, em que o filho lê o arquivo inteiro e o sino `pre_spec_sem_bloco` vira
  obrigatório. Nunca siga com "zero decisões" em silêncio. Isto **não** é `intent_review:
  needs_decision` — o estado da etapa não mudou; não escreva o INTENT-REVIEW por causa dele.
- Na continuação, grave a resposta e releia o setup num comando só:
  ```bash
  $HOME/.claude/skills/go-and-do/scripts/setup-intencao.sh "<phase_dir>" "<NN>" \
    --pre-spec-route legacy|structured --resposta "<texto do dono, verbatim>"
  ```
  A rota é durável (`.intent/pre-spec-route.json`) e vale enquanto o sha256 do PRE-SPEC
  não mudar. `legacy` → sino `pre_spec_sem_bloco` obrigatório no seu retorno **e** no
  `NN-INTENT-REVIEW.md`.
- `pre_spec_mode` vai **explícito** no despacho dos DOIS filhos (passos 1 e 2).
</resume>

<spec>
## Passo 1 — SPEC (o quê)

Despache **`gad-spec`** (protocolo do `<environment>`) com o arquivo de instruções
`prompts/intent-spec.md`. O filho hospeda o `gsd-spec-phase N --auto` na janela dele,
devolve o caminho do `NN-SPEC.md` + score de ambiguidade e grava os sinos em
`.intent/.sinos-spec.txt`.

Parâmetros obrigatórios do despacho, além dos do protocolo:
- **PRE-SPEC** — `pre_spec_mode: structured|legacy` (do setup) e o insumo correspondente:
  em `structured`, o **bloco `gad:decisoes` INLINE** (o array JSON verbatim, extraído do
  PRE-SPEC entre os marcadores `<!-- gad:decisoes:begin v1 -->`/`<!-- …:end -->`) —
  **nunca o caminho do arquivo**; em `legacy`, `pre_spec: <caminho>` e o filho lê o
  arquivo inteiro. Sem PRE-SPEC, nada disso vai.
- **R6** — `goal_roadmap:` e `issues:` do `setup-intencao.sh`, verbatim (só ao `gad-spec`).
- **Lições** — `licoes: ["<n> | <título>", …]`, numeradas na ordem de
  `<project_root>/.planning/LICOES-DE-INTENCAO.md` (arquivo ausente → `licoes: []`).
  Elas saíram do briefing do revisor e viraram checklist do filho, que responde
  `licao <n>: aplicada|nao_se_aplica — <porquê>` no `.sinos-spec.txt`.

- `estado: done` → siga (os sinos já estão no disco; o briefing-build os injeta no
  briefing e você os repete no seu retorno à camada 0). Guarde do retorno: `r2_avisos`
  (vão ao briefing, abaixo) e `base_spec` (blob-base do T3 — `nao_gravado` vira sino).
- `estado: pausa` → siga o `<business_pause>` com a pergunta que o filho devolveu.

**Conferência PRE-SPEC ↔ SPEC (R2c) — antes de qualquer briefing.** O `r2_avisos` do filho
já é o resultado; veio ausente (fallback inline, ou SPEC pré-existente na chegada
`revisao`) → rode você
`confere-pre-spec.sh "<phase_dir>/NN-SPEC.md" "<phase_dir>/NN-PRE-SPEC.md"`.
Linha `FALHA` (`MARCA-SEM-ID`, `ID-INEXISTENTE`, `FATO-SEM-EVIDENCIA`,
`RESSALVA-SEM-LIMITACAO`, `AC-POR-PONTEIRO`) → conserte o SPEC antes de seguir (ou
`<business_pause>`, se mexer em decisão do dono) — é o que o `confere-etapa.sh 1` cobra no
fecho. `AVISO EXTENSAO-SUSPEITA` **não** reprova: copie as linhas para a
`.intent/.varredura.md`, sob o heading `### Extensões suspeitas ao PRE-SPEC (R2c)`, para
chegarem ao revisor no briefing; quem decide é você.
</spec>

<discuss>
## Passo 2 — CONTEXT (o como)

Despache **`gad-discuss`** com o arquivo de instruções `prompts/intent-discuss.md`. O
filho hospeda o `gsd-discuss-phase N --auto`, neutraliza os dois efeitos colaterais do
`--auto` (não encadeia o plan; zera a flag de chain) e aplica a fronteira
anti-duplicação SPEC↔CONTEXT.

Parâmetros obrigatórios, além dos do protocolo: `pre_spec_mode` + o insumo — em
`structured`, **só o bloco `gad:decisoes` inline**, nunca o arquivo; em `legacy`,
`pre_spec: <caminho>` — decisões travadas ali não são re-perguntadas nem contrariadas no
CONTEXT — e as mesmas `licoes` do passo 1. `goal_roadmap`/`issues` **não** vão: são do
SPEC.

- `estado: done` com `chain_flag_zerada: nao` → re-rode o `setup-intencao.sh` (a
  higiene é idempotente) e confira `chain_flag_zerada: zerada` antes de seguir. Guarde
  `base_context` (blob-base do T3 — `nao_gravado` vira sino).
- `estado: pausa` → siga o `<business_pause>`.
- `estado: falha` → **parada disclosed, sem pergunta ao dono**: a guarda estrutural
  rejeitou o CONTEXT (corrupção determinística, não juízo de qualidade). Não despache a
  revisão nem o plan-phase; devolva `estado: blocked` com o `motivo:` do filho e o caminho
  do `NN-CONTEXT.rejected.md`. O checkpoint foi preservado — a retomada é
  `gsd-discuss-phase N --auto` após o conserto do renderer/guarda, nunca edição manual do
  `.rejected.md`.
</discuss>

<adversarial_review>
## Passo 3 — Revisão adversarial de intenção (cross-AI)

*Pré-check:* `command -v codex; command -v agy` (Bash) — a revisão usa **dois revisores
externos**. Nenhum instalado → `<skipped_path>` (ausência de ferramenta vira sino, não
parede). Só um → prossiga com ele, degradação em `sinos`. Pelo menos um instalado → vale o
piso fail-closed: instalado-mas-falho em runtime é falha, não ausência (os DOIS falhos sem
ciclo completo → `<blocked_path>`). Prepare `mkdir -p "<phase_dir>/pareceres"` (pareceres
são artefatos commitados; o trabalho do ciclo vive em `.intent/`).

1. **Leia a intenção UMA vez** (`NN-SPEC.md` + `NN-CONTEXT.md`). Do ciclo 2 em diante não
   releia os artefatos inteiros: o "o que mudou" vem da sua triagem + `git diff`; trecho
   pontual = `sed -n 'X,Yp'`.
2. **Varredura reversa de impacto (seu único insumo de modelo no briefing).** Para cada
   constante, contagem, valor, regra ou invariante que o SPEC/CONTEXT prescreve **mudar**,
   rode `git grep` do símbolo — código E testes — e escreva `.intent/.varredura.md` com a
   seção **"Asserções existentes que esta fase falsifica"**: uma linha por asserção, com
   `arquivo:linha` · veredito (inverter / reancorar / remover) · plano dono da
   reconciliação. Nenhuma atingida → a seção afirma isso explicitamente. Espelhe a seção no
   `NN-SPEC.md`. Número load-bearing entra re-derivado da fonte primária, nunca copiado de
   outro documento.
2b. **Ciclo 0 — triagem dos sinos dos filhos (R3), antes do primeiro briefing.**
   Leia `.intent/.sinos-spec.txt` e `.intent/.sinos-discuss.txt` e corrija **só o
   mecanicamente provável**, com fonte-de-verdade explícita: **fato de código citado >
   SPEC > CONTEXT**; requisito ou critério de aceite, manda o **SPEC**; o *como*, manda o
   **CONTEXT**. Mesma esteira do passo 5 (`correcoes-commit.sh --inicio` → um
   `.intent/.correcoes-c0.py|.sh` num turno → `--ids`/`--vazio`) e mesma releitura do 5b
   (no c0 ela recebe também a seção "Consistência interna" do SPEC; seção ausente → o filho
   devolve `consistencia: não_disponível`, sem falha). Depois grave `.intent/.ciclo0.json`
   — schema exigido pelo `briefing-build.sh`:
   `{"v":1, "sinos":[{"id":"c0-01","origem":"spec|discuss","disposicao":"corrigido|
   descartado|aberto","correcao_id":"c0-01"}], "correcoes":[{"id":"c0-01","hash":"<copiado
   verbatim de .correcoes-c0.aplicado>"}],
   "releitura":{"commit":"…","artefatos":[{"path":"…","blob":"…"}]}}`
   O `hash` vem do disco: `jq -r '.correcoes[] | .id + " " + .hash'` sobre
   `.intent/.correcoes-c0.aplicado`, copiado caractere a caractere. Desde o conserto C1 ele
   carrega um blob sha real (ou string vazia, quando o `.aplicado` listou o id em
   `hash_ausente[]`), e o gate do briefing c1 compara os dois lados — valor divergente sai
   como "`.ciclo0.json`.correcoes != `.aplicado`.correcoes".
   Arrays vazios **explícitos** (`{}` ou chave faltando → exit 4); `corrigido` exige um
   `correcao_id` existente no `.correcoes-c0.aplicado`, `descartado`/`aberto` proíbem o
   campo. **Nenhum sino some:** cada correção c0 volta ao revisor na seção "Revalidação
   dirigida (ciclo 0)" do briefing c1 (montada do `.ciclo0.json` — o revisor pode derrubar
   a sua correção), e o INTENT-REVIEW ganha `c0-NN | <sino> | corrigido|aberto`.
3. **Monte o briefing por script:**
   ```bash
   $HOME/.claude/skills/go-and-do/scripts/briefing-build.sh "<phase_dir>" "<NN>" <C> \
     --varredura "<phase_dir>/.intent/.varredura.md" [--mudancas "<phase_dir>/.intent/.mudancas-c<C>.md"]
   ```
   (`--mudancas` do ciclo 2 em diante: o que você corrigiu + achados resolvidos.) O script monta `.intent/briefing-c<C>.md`: missão canônica,
   taxonomia, livro-razão das decisões `[auto]`, a entrada da fase no ROADMAP, os sinos do
   disco, as perguntas dirigidas (manifesto `.intent/.perguntas-c<C>.json`) e o canário de
   leitura (nonce em `.intent/.prova-leitura-c<C>.txt` — o valor nunca aparece no
   briefing). Não redija briefing à mão.
   **Exit 4 = gate do ciclo anterior** (falta `.ciclo0.json` no c1, ou
   `.correcoes-c<C-1>.aplicado`/`.vazio` + `.releitura-c<C-1>.json` coerentes de C≥2):
   vá fazer o passo que falta — não re-rode o build nem contorne.
4. **Lance as lanes e despache o verificador — NO MESMO TURNO.**
   ```bash
   cd "<project_root>"
   $HOME/.claude/skills/go-and-do/scripts/roda-lanes.sh "<phase_dir>" "<NN>" <C> \
     "<phase_dir>/.intent/briefing-c<C>.md" \
     --prova "<phase_dir>/.intent/.prova-leitura-c<C>.txt"
   ```
   Bash comum: **retorna em < 1 s** com `{run_id, pids, status_paths}` e deixa um
   supervisor por lane vivo por conta própria — não use `run_in_background`, não espere,
   não rode `wait`. Os comandos crus do Codex e do agy saíram daqui: quem os monta (modelo,
   log, espelho, nonce do briefing) são os `roda-<lane>.sh` que ele chama. Tudo do run vive
   em `.intent/runs/c<C>/<run_id>/`; os pareceres canônicos
   (`pareceres/NN-parecer-<lane>-c<C>.md`) são aliases promovidos pelo run vencedor — são
   eles que o passo 7 commita.

   **No MESMO turno**, despache **`gad-verificador`** com `prompts/intent-verifica.md`,
   passando o `run_id`, `<phase_dir>/.intent` (dos `.status-c<C>-<lane>.json`), o run-dir
   `.intent/runs/c<C>/<run_id>`, o manifesto `.intent/.perguntas-c<C>.json`, SPEC/CONTEXT,
   o ciclo `C`, deadline de 12 min e — do ciclo 2 em diante — o `NN-INTENT-REVIEW.md`
   parcial. Turno só para esperar lane é desperdício medido.

   **A autoridade sobre a lane é o status, nunca o marcador `.done`.**
   `.intent/.status-c<C>-<lane>.json` tem dois eixos: `usable` (parecer não-vazio, fresco,
   legível) e `independent` (`nonce_ok && modelo_ok`).
   - `usable: false` → lane é `sem_parecer: <lane>`: degrade já, sem esperar o deadline.
   - `usable: true, independent: false` (nonce ausente, modelo divergente ou espelho
     malformado) → **o parecer conta**, como **corroboração**: achados entram na tabela
     marcados `independente=false` e só viram `confirmado` com evidência própria do
     verificador. **Nenhum achado some por isso** — sumir é fabricar convergência.
     Frontmatter `independencia_lane: {<lane>: false}` + sino; `mirror_valid: false`
     também vira `incidente`. Idem para lane devolvida em `pareceres_sem_citacao` (nenhum
     `arquivo:linha`; carimbo `[reviewed-without-source-citations]`, GSD 1.11.0 #3194):
     corroboração, `sem_citacao_fonte: [lanes]` + sino.

   **Evidência de modelo (obrigatória, por run):** copie do status/espelho do run vencedor
   para o frontmatter — `codex_model_evidencia:` (banner do Codex) e `agy_model_evidencia:`
   (linha `Propagating selected model override to backend` do log do agy). Ausente = sem
   evidência → sino; não invente.

   **Degradação:** falha de UMA lane → siga com a outra, sino. Falha das DUAS antes de
   qualquer ciclo completo → `<blocked_path>`. Exceção única: com ≥1 ciclo já completo
   (parecer recebido, verificado e aplicado), registre `intent_review: done` com a ressalva
   `ciclo_final_nao_rodou` no frontmatter + `sinos`.
5. **Verificação — rota decidida pelo volume MEDIDO, nos dois sentidos.**

   **(a) Contagem conservadora, PRÉ-rota** (sem `--vereditos` — ainda não existem):
   ```bash
   $HOME/.claude/skills/go-and-do/scripts/confere-ciclo.sh --tabela \
     --perguntas "<phase_dir>/.intent/.perguntas-c<C>.json" \
     --status-dir "<phase_dir>/.intent" \
     "<phase_dir>/pareceres/NN-parecer-codex-c<C>.md" \
     "<phase_dir>/pareceres/NN-parecer-agy-c<C>.md" \
     > "<phase_dir>/.intent/.tabela-c<C>.txt"
   ```
   `brutos` = a linha `achados_estruturais_total:` DESSE arquivo, lida mecanicamente, nunca
   da sua leitura. Ela já inclui as respostas dirigidas (`sim`/`incerto`) e conta `não`
   como `nao_provisorio`.

   **(b) A regra da rota, nos dois sentidos — e declare a escolhida ANTES de verificar**
   (o marcador `.verificador-c<C>.done` não distingue as rotas: a inline também o grava).
   O `mode` do arquivo é a rota que você VAI usar; escrever `child` "por segurança" num c3
   com 2 brutos é violação, igual a verificar 10 inline.
   - **Ciclos 1–2, ou 3+ com 3+ brutos → `child`.** Grave
     `printf '{"run_id":"<run_id>","mode":"child","brutos_pre_rota":<n>}\n' >
     "<phase_dir>/.intent/.rota-verificacao-c<C>.json"` e siga com o filho já despachado.
   - **Ciclos 3+ com ≤2 brutos → `inline` OBRIGATÓRIO.** Grave o mesmo arquivo com
     `"mode":"inline"` e verifique você mesmo, pelo protocolo do `intent-verifica.md`
     (categoria revalidada com fail-up, `.vereditos-c<C>.txt`, `vereditos-dirigidos.json`
     no run-dir e `.verificador-c<C>.done`), registrando `verificacao_inline_c<C>` em
     `transparencia:`.
   O `confere-rotas.sh` reprova as DUAS violações (`VIOLACAO` e `VIOLACAO-INVERSA`, exit 1).

   **(c) Contagem FINAL, depois da verificação** — a mesma linha do (a) **mais** os
   vereditos dirigidos, sobrescrevendo a tabela:
   ```bash
   …  --vereditos "<phase_dir>/.intent/runs/c<C>/<run_id>/vereditos-dirigidos.json" \
     > "<phase_dir>/.intent/.tabela-c<C>.txt"
   ```
   É ela que alimenta o `decide-ciclo.sh` e a contagem do INTENT-REVIEW; só `supported_no`
   tira uma pergunta dirigida da conta. **Você NÃO relê os pareceres** quando o filho roda:
   a triagem trabalha sobre a tabela e os vereditos devolvidos.

   **Triagem (sua alçada, achado a achado sobre os `confirmado`) — num turno só.**
   - **Correção factual** → entra no script de correções (abaixo).
   - **Mexe em requisito, critério de aceite ou oráculo** (`toca_requisito_ou_criterio:
     sim` — confirme você) → decisão do usuário: `<business_pause>`.
   - **Só tradeoff de risco/implementação** → adote a recomendação que a verificação
     sustentar e registre em transparência.
   Os `nao_sustentado`/`ja_coberto` entram na tabela do INTENT-REVIEW com o
   porquê/ponteiro do filho — destino registrado, não filtro silencioso.

   **O que a correção escreve: INVARIANTE, nunca mecanismo (R1a).** Um AC é `MUST NOT` +
   modo de falha observável. Anti-exemplos, na forma:
   - ❌ "usar um dicionário indexado pelo id para casar as linhas" → ✅ "MUST NOT casar
     duas linhas com ids diferentes; casamento ambíguo falha com erro que nomeia os dois".
   - ❌ "gravar em `/tmp` e depois mover" → ✅ "MUST NOT deixar o arquivo de destino
     meio-escrito; leitor concorrente lê a versão anterior inteira ou a nova inteira".

   **`proposicao` por achado confirmado (T3).** Na tabela do INTENT-REVIEW, cada achado
   `confirmado` ganha — **separado da evidência de código** — o campo que localiza a
   proposição defeituosa no artefato:
   `proposicao: {artefato: SPEC|CONTEXT, ancora: <AC-n|D-nn|R-n|heading mais próximo ACIMA
   do span>, span_linhas: [ini, fim], texto: "<o span verbatim>", origem_texto:
   de_artefato_pos_ciclo}`. O achado cita **código** (`base.py:1979`); a `proposicao` diz
   onde mora a frase errada — é dela que a `/audit-gad` mede original × derivado. Sem ela o
   achado sai `não_medido`; não chute nem invente âncora.

   **As correções do ciclo: um script, um turno.**
   1. ANTES de editar qualquer artefato:
      ```bash
      $HOME/.claude/skills/go-and-do/scripts/correcoes-commit.sh "<phase_dir>" <C> --inicio \
        --artefatos "<SPEC>" "<CONTEXT>" "<INTENT-REVIEW>" \
        [--docs .planning/ROADMAP.md .planning/REQUIREMENTS.md]
      ```
      `--docs` **só** quando o ciclo resolve issue R6 ou reconcilia o Goal — neles o
      script comita só o delta do ciclo, mesmo se já estavam sujos.
   2. Escreva **um** `.intent/.correcoes-c<C>.py|.sh` com TODAS as correções factuais do
      ciclo e execute-o **no mesmo turno**. Uma edição por achado, id `c<C>-NN`.
   3. Feche:
      ```bash
      …  correcoes-commit.sh "<phase_dir>" <C> --ids "c<C>-01,c<C>-02" \
        --artefatos "<SPEC>" "<CONTEXT>" "<INTENT-REVIEW>" [--docs …]
      ```
      O `--ids` leva só os ids. O `hash` de cada correção é preenchido pelo próprio script,
      com o blob sha do arquivo alvo depois da correção — no instante em que você monta a
      flag o commit ainda não existe (o exemplo antigo pedia um hash sem fonte, e o campo
      saiu vazio em 58/58 entradas da F24.4).
      Ciclo que tocou **mais de um arquivo**: diga qual correção mexeu em qual, na forma
      `id:<caminho relativo à raiz do repo>` —
      `--ids "c<C>-01:.planning/phases/<fase>/NN-SPEC.md,c<C>-02:.planning/ROADMAP.md"`.
      Sem essa declaração o script grava `hash: ""` e lista os ids em `hash_ausente[]` no
      `.correcoes-c<C>.aplicado`: a ausência fica auditável, mas a releitura perde a âncora
      por correção. Com um só arquivo no ciclo, a forma só-ids basta.
      Ciclo sem correção → `correcoes-commit.sh "<phase_dir>" <C> --vazio` (marcador
      explícito; ausência não vale). Exit 3 = **nada promovido**: leia a razão, conserte e
      re-rode — nunca contorne com `git` na mão.

5b. **Releitura da emenda (R1b) — entre o commit e o briefing do ciclo seguinte.**
   Despache **`gad-verificador`** com `prompts/intent-releitura.md`, passando
   `project_root`, `phase_dir`, `NN`, `C`, o conteúdo do `.intent/.correcoes-c<C>.aplicado`
   (ou o `.correcoes-c<C>.vazio`) e — só no ciclo 0 — a seção "Consistência interna" do
   `NN-SPEC.md`. Ele grava `.intent/.releitura-c<C>.json` + `.releitura-c<C>.done`.
   Devolveu item (`contradiz`, `prescreve_mecanismo`, `omissoes_novas`) → corrija **no
   mesmo turno** (rodada `c<C>b`: novo script, `--inicio` e `--ids` de novo — o `.aplicado`
   é sobrescrito in-place) e **despache uma releitura nova**. Só com a releitura limpa você
   monta o briefing seguinte; sem esses arquivos o `briefing-build.sh` dá exit 4.
6. **Convergência — rode o script e obedeça:**
   ```bash
   $HOME/.claude/skills/go-and-do/scripts/decide-ciclo.sh "<phase_dir>" <C>
   ```
   - `continua` → passo 3 com o dossiê revisado (escreva `.mudancas-c<C+1>.md`).
   - `para-zerou` / `para-teto` (teto duro: **4 ciclos**) → passo 7.
   - `para-custo-marginal` → aplique os achados do `lote_cde` como **lote único** na saída
     (sem re-submeter aos revisores) e vá ao passo 7.
   - `sem_dados` → o verificador não fechou o ciclo; complete a rota do passo 5 antes.
   Antes de aplicar lote com 2+ alterações de decisão/critério, cheque se elas são
   simultaneamente satisfazíveis. Esses são os freios COMPLETOS — seu juízo de "o revisor
   não teria mais o que achar" não encerra o loop.
7. **Escreva o `<phase_dir>/NN-INTENT-REVIEW.md`** com frontmatter:
   `intent_review: done` · `revisores_efetivos: [...]` · `codex_model_evidencia:` /
   `agy_model_evidencia:` · `ciclos: N` · `motivo_encerramento:` (decisão do
   decide-ciclo, verbatim) · `achados_confirmados: N` · `achados_descartados: N` ·
   `pausas_de_negocio: N` · `transparencia:` (lista do 3º destino). No corpo: a
   contagem de novos confirmados POR CICLO (com a categoria) e a tabela de achados —
   alegação → veredito → destino → ação tomada → `proposicao` (T3), enumerando **100% dos
   achados brutos** (fundidos com `fontes:`; "já cobertos"/"reformulados" com os ponteiros
   do filho), mais as linhas do ciclo 0 (`c0-NN | <sino> | corrigido|aberto`).
   **Sinos estruturados, verbatim no corpo:** os literais `req_ausente: <id>`,
   `fase_sem_req` e `pre_spec_sem_bloco` TÊM de aparecer aqui exatamente como escritos — a
   limpeza do 7b apaga os `.sinos-*.txt`, e é neste arquivo que o `confere-etapa.sh 1` vai
   procurá-los. Menção em prosa ("o REQ-X continua ausente") não conta.
   **Antes de escrever a tabela, rode a reconciliação mecânica** — ela junta os dois lados do
   dado que já estão em disco, o que a tabela sozinha (prosa sua, conferida por ninguém) não
   faz:
   ```bash
   $HOME/.claude/skills/go-and-do/scripts/confere-reconciliacao.sh "<phase_dir>" --ordem
   ```
   Exit 0 → a tabela pode afirmar a reconciliação. Exit 1 → cada linha vira uma entrada da
   tabela com a ação tomada, mais um `incidente` no run-log: `INVERSAO` (reverta a correção
   indevida), `CONFIRMADO-NAO-APLICADO` (aplique o que faltou), `APLICADO-SEM-VEREDITO`
   (registre a origem da correção órfã), `ORDEM-VIOLADA` (re-rode a releitura sobre a emenda
   final). Copie a saída do script para a tabela, em vez de reescrevê-la de memória.
   Antes do commit, `spot-check-ponteiros.sh <arquivo> <root1> [root2 …]` (TODAS as raízes
   citadas) nos artefatos que VOCÊ escreveu; ponteiro quebrado → conserte antes de commitar.
   ```bash
   cd "<project_root>"
   git commit --only -m "docs(fase NN): revisão adversarial de intenção (M ciclos, K achados)" -- \
     <só os caminhos que existem: NN-PRE-SPEC.md NN-SPEC.md NN-CONTEXT.md NN-INTENT-REVIEW.md pareceres/NN-parecer-*.md>
   ```
   **`--only` com pathspec, nunca `git add` nem commit sem pathspec:** o worktree do
   usuário pode estar sujo e um commit amplo absorveria o trabalho dele. Commit falhou
   (sem git, nada a commitar) → não pare; anote no retorno e siga.
7b. **Gate de rota (fail-closed) — antes de devolver `done`:**
   ```bash
   $HOME/.claude/skills/go-and-do/scripts/confere-rotas.sh "<phase_dir>/.intent"
   ```
   Exit 0 → **antes de apagar nada**, confira que os sinos estruturais do passo 7 já estão
   verbatim no `NN-INTENT-REVIEW.md` (`grep -c 'req_ausente:\|fase_sem_req\|
   pre_spec_sem_bloco'`): a partir do `rm` eles só existem lá, e é lá que o
   `confere-etapa.sh 1` da camada 0 vai procurá-los. Só então a limpeza (política 1.5):
   ```bash
   rm -f "<phase_dir>/.intent/".sinos-*.txt "<phase_dir>/.intent/"briefing-c*.md \
         "<phase_dir>/.intent/".varredura.md "<phase_dir>/.intent/".mudancas-c*.md
   ```
   **Não alargue esses globs.** SOBREVIVEM, por serem insumo da `/audit-gad` e dos gates:
   `runs/`, `.status-c*`, `.tabela-c*`, `.vereditos-c*`, `.prova-leitura-c*`,
   `.rota-verificacao-c*`, `.correcoes-c*.aplicado|.vazio`, `.releitura-c*`,
   `.ciclo0.json`, `.gerado-*`, `.base-*` (blobs-base do T3) e `pre-spec-route.json`.
   Siga ao passo 8. Exit 1 → **você não devolve `done`**: `SEM-TABELA` → gere a tabela do
   ciclo; `VIOLACAO` → despache um `gad-verificador` retroativo sobre os pareceres daquele
   ciclo e incorpore o resultado; `VIOLACAO-INVERSA` → verifique inline o que faltar e
   corrija a `.rota-verificacao-c<C>.json`. Em todos: `incidentes` + re-rode o gate.
8. Devolva `done` pelo `<return_contract>`.
</adversarial_review>

<business_pause>
## Devolução de pergunta ao usuário (destino 2 e impasses)

Você não fala com o usuário — o orquestrador fala. O caminho:

1. **Grave todo o progresso em disco ANTES de devolver:** aplique as correções factuais já
   confirmadas, escreva o `NN-INTENT-REVIEW.md` parcial com frontmatter `intent_review:
   needs_decision` **mais o estado do loop** (`ciclos_completos:`, `achados_confirmados:`,
   `achados_descartados:` e, no corpo, os novos confirmados por ciclo). Inclua a seção
   "Perguntas pendentes" (por pergunta: a alegação, o que a verificação confirmou, as
   opções com tradeoffs e a sua recomendação **primeiro**) e commite (bloco do passo 7). A
   evidência de cada pergunta é medida sobre o oráculo inteiro, não sobre amostra de 1.
2. Devolva `needs_decision` pelo `<return_contract>` — até 4 perguntas por retorno.
3. **Na continuação** (a resposta chega verbatim): incorpore cada decisão — aplique no
   SPEC/CONTEXT, registre no `NN-INTENT-REVIEW.md` (a pergunta vira linha da tabela,
   destino 2) — e **retome o loop de onde parou** (passo 6; não re-rode o ciclo que já
   rodou).
</business_pause>

<blocked_path>
## Caminho bloqueado (OS DOIS revisores indisponíveis ou falhos sem ciclo completo)

1. Escreva o `NN-INTENT-REVIEW.md` com `intent_review: blocked` e `motivo: <por
   revisor>`. Commite (padrão do passo 7) — é este registro que faz a próxima
   invocação re-tentar.
2. Devolva `blocked` pelo `<return_contract>`. Quem para a fase é a camada 0 — a
   descida não afrouxa o fail-closed; ele apenas sobe com motivo.
</blocked_path>

<skipped_path>
## Caminho pulado (NENHUM revisor externo instalado no pré-check)

1. Escreva o `NN-INTENT-REVIEW.md` com `intent_review: skipped` · `motivo: "nenhum
   revisor externo instalado (codex e agy ausentes no pré-check)"` ·
   `revisores_efetivos: []` · `ciclos: 0` — `skipped` é estado final (quem instalar um
   revisor depois e quiser a revisão apaga este arquivo e re-roda). Commite.
2. Devolva `done` com o sino obrigatório: `"revisão adversarial de intenção PULADA —
   nenhum revisor externo (codex/agy) instalado"`. Este sino TEM que chegar ao bloco
   de transparência do resumo executivo.
</skipped_path>

<return_contract>
## Retorno ao orquestrador

Responda **apenas** com um dos três blocos abaixo, preenchido — sem prosa antes ou
depois (o retorno é parseado como dado de roteamento; conteúdo verboso vive no disco;
tokens não se reportam — a medição é mecânica, do transcript, pela camada 0).

```
estado: done
spec: <caminho absoluto do NN-SPEC.md>
context: <caminho absoluto do NN-CONTEXT.md>
review: <caminho absoluto do NN-INTENT-REVIEW.md>
revisores_efetivos: [codex, agy]   ← só os que revisaram de fato
ciclos: <n>
motivo_encerramento: <verbatim do decide-ciclo.sh>
achados_confirmados: <n>
achados_descartados: <n>
pausas_de_negocio: <n>
transparencia: [<um item por linha; ausente se vazio>]
incidentes: [<OBRIGATÓRIO em todo retorno done — todo desvio entre o anunciado/configurado e o executado (o quê · por quê · quem decidiu), mesmo já resolvido; sem desvio, escreva literalmente: nenhum>]
sinos: [<itens 🔔: dimensões de ambiguidade abaixo do mínimo · ciclo_final_nao_rodou · sem_parecer: <lane> · lane sem independência (nonce/modelo/espelho) · sem_citacao_fonte · pre_spec_sem_bloco · req_ausente: <id> · fase_sem_req · blob-base do T3 não gravado · revisão pulada · commit falhou · filho fora do contrato; ausente se vazio>]
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
