<!-- prompts/intent-discuss.md — filho de camada 2 (agente gad-discuss) que hospeda o
     gsd-discuss-phase para o subagente de intenção. Lido do disco PELO FILHO. -->

# Filho da intenção — CONTEXT (o como)

O despacho te entrega `N`, `NN`, `project_root` e `phase_dir` (absolutos) e, quando há
PRE-SPEC, `pre_spec_mode: structured|legacy` + o insumo correspondente. Traz ainda
`licoes` (checklist). Comece todo bloco Bash com `cd "<project_root>"` e use caminhos
absolutos em tudo.

## Trabalho

0. **Nada de leitura antes da `Skill` (D5a).** É **proibido** ler o SPEC, o código do
   projeto ou o PRE-SPEC antes de invocar o `gsd-discuss-phase`: na F24.3 esse hábito
   levou a janela do filho de 35 k a 81 k tokens antes do primeiro trabalho útil. O
   workflow carrega o SPEC sozinho, e as verificações de código acontecem **dentro** das
   decisões (com `--evidence path:line`), não numa varredura prévia.
1. Se `<phase_dir>/NN-CONTEXT.md` já existe → não re-rode nada; pule ao passo 4
   (a neutralização da flag é idempotente e barata) e devolva `done` com
   `base_context: nao_gravado — CONTEXT pré-existente`. **Não sele** (passo 5): base
   gravada tarde promoveria a "original" um artefato que um ciclo de revisão já corrigiu.
1b. **PRE-SPEC (insumo pré-travado).** Decisões registradas ali são **travadas pelo
   usuário**: gray area que o PRE-SPEC já responde não é re-decidida — adote a resposta
   dele e persista-a com `--origin pre-spec` (em vez de `--origin auto`) na chamada do
   `checkpoint-write.py add-decision`, com `--anchor <req_anchor>` (`R-n`/`SC-n`/`none`)
   e — assim que o `--source-id` existir no script (onda 2) — o `PS-nn` de origem; o
   renderizador emite `[pre-spec:PS-nn, R-n]` no bullet do CONTEXT (a marca em prosa não
   existe mais — o campo `origin` do checkpoint é a fonte). Duas rotas, pelo
   `pre_spec_mode`:
   - **`structured`** (rota normal): o coordenador te passa **só o bloco `gad:decisoes`**
     (array JSON) — **não abra o `NN-PRE-SPEC.md`**. Só `kind: decisao_dono` trava;
     `kind: fato_medido` não vira decisão (ele vive no SPEC como `[medido:PS-nn]`).
     Quando o `discuss-init.sh --pre-spec` entrar (onda 2), essas entradas chegarão
     prontas como batch e você não montará nenhuma delas à mão.
   - **`legacy`** (rota antiga, autorizada pelo dono): `Read` o `NN-PRE-SPEC.md` INTEIRO
     — **única exceção ao passo 0, e mesmo assim só DEPOIS da `Skill`**, dentro do loop
     de áreas, quando uma gray area precisar da resposta travada. Trate a prosa como as
     decisões travadas. Sino literal `pre_spec_sem_bloco` obrigatório no
     `.sinos-discuss.txt` e no retorno.
   - Conflito irreconciliável entre PRE-SPEC e SPEC → sino em `.sinos-discuss.txt`,
     nunca resolução silenciosa.
   ⚠️ **`--chosen-option` é 0-indexado** (`context-render.py`/`checkpoint-write.py` do
   fork): a 1ª opção listada é `0`, a 2ª é `1`. Na F24.3 o agente passou `1` querendo a
   1ª e marcou a opção errada nas 12 decisões (autocorrigido, 6 turnos perdidos). Conte a
   partir de zero — **ou não conte:** prefira `--chosen-label "<texto da opção>"`, que
   casa exato e, senão, por prefixo único case-insensitive, e falha alto na ambiguidade
   em vez de marcar a errada em silêncio. Ela exige `--option-file` e é **mutuamente
   exclusiva** com `--chosen-option` (passar as duas = erro, nada gravado).
2. Invoque `Skill` → `gsd-discuss-phase` com args `N --auto`. Ele carrega o SPEC.md,
   seleciona todas as gray areas ancoradas em R-n, escolhe a opção recomendada em cada
   decisão (persistida com `--origin auto` → bullet `- **D-NN [auto, R-n]:**` no CONTEXT),
   renderiza o CONTEXT por script, passa pela guarda estrutural e commita em 1 commit
   (CONTEXT + DECISIONS-INDEX + for-humans + STATE). Em `--auto` o workflow **não** lê
   `modes/chain.md` (fork 3b) — o passo 4 abaixo continua como defesa em profundidade.
3. **Fronteira de conteúdo (anti-duplicação):** decisão, requisito e critério moram no
   SPEC — o CONTEXT **referencia por ponteiro** (`NN-SPEC.md §seção`), nunca copia o
   parágrafo. O CONTEXT carrega só o que é dele: o *como* (abordagens escolhidas,
   tradeoffs, restrições de implementação). Conteúdo duplicado entre os dois é pago de
   novo em cada etapa que os relê — se o passe único produziu duplicação, edite o
   CONTEXT antes do retorno substituindo a cópia pelo ponteiro (e re-commite com
   `--amend` se o commit foi do próprio workflow, ou num commit novo se não).
4. **Neutralize os dois efeitos colaterais do `--auto`** (quem encadeia os comandos é a
   /go-and-do; o auto-advance nativo atropelaria a revisão adversarial):
   - Quando o workflow chegar no passo `auto_advance` (que mandaria despachar
     `Skill gsd-plan-phase N --auto`), **não despache** — para você, o discuss termina
     no CONTEXT.md commitado.
   - Zere a flag de chain persistida na config. Bash, com este shim no mesmo bloco:

     ```bash
     cd "<project_root>"
     _GSD_SHIM_NAME="gsd-tools.cjs"; _GSD_RUNTIME_ROOT="${RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GSD_TOOLS="${_GSD_RUNTIME_ROOT}/gsd-core/bin/${_GSD_SHIM_NAME}"; if [ -f "$GSD_TOOLS" ]; then gsd_run() { node "$GSD_TOOLS" "$@"; }; elif [ -f "${_GSD_RUNTIME_ROOT}/.claude/gsd-core/bin/${_GSD_SHIM_NAME}" ]; then GSD_TOOLS="${_GSD_RUNTIME_ROOT}/.claude/gsd-core/bin/${_GSD_SHIM_NAME}"; gsd_run() { node "$GSD_TOOLS" "$@"; }; elif command -v gsd-tools >/dev/null 2>&1; then GSD_TOOLS="$(command -v gsd-tools)"; gsd_run() { "$GSD_TOOLS" "$@"; }; elif [ -f "$HOME/.claude/gsd-core/bin/${_GSD_SHIM_NAME}" ]; then GSD_TOOLS="$HOME/.claude/gsd-core/bin/${_GSD_SHIM_NAME}"; gsd_run() { node "$GSD_TOOLS" "$@"; }; else echo "ERROR: gsd-tools.cjs not found" >&2; exit 1; fi
     gsd_run query config-set workflow._auto_chain_active false
     ```
5. **Selagem do artefato (T3), última ação antes do retorno.** Depois de *todas* as
   edições (inclusive a dedup do passo 3 e o `--amend`) e do commit final — nada pode
   tocar o CONTEXT depois disto:

   ```bash
   cd "<project_root>"
   mkdir -p "<phase_dir>/.intent"
   git hash-object    "<phase_dir>/NN-CONTEXT.md" > "<phase_dir>/.intent/.gerado-CONTEXT.txt"
   git hash-object -w "<phase_dir>/NN-CONTEXT.md" > "<phase_dir>/.intent/.base-CONTEXT.txt"
   ```

   O rótulo do arquivo é `CONTEXT` (não o nome do artefato). Sem essa base a proveniência
   dos achados sai `não_medido` — o coordenador não a reconstrói depois. Na onda 2 o
   `discuss-finalize.sh` assume esta gravação; até lá é sua.

## Checklist de lições

O despacho traz `licoes: [ "<n> | <título da lição>", … ]` (ausente ou vazio → nada a
fazer). Aplique cada uma às decisões do CONTEXT e grave no `.sinos-discuss.txt` uma linha
por lição, com o prefixo exato `licao <n>: aplicada|nao_se_aplica — <porquê em 1 linha>`.
São **respostas, não sinos**: o coordenador as separa pelo prefixo `licao `. Lição sem
resposta = checklist incompleta.

## Pausa

Decisão que as regras do workflow mandam levar ao usuário → NÃO contorne com flags;
devolva `estado: pausa` com a pergunta mastigada. Antes de devolver, execute o passo 4
mesmo assim (a flag não pode ficar armada no disco).

## Falha (guarda estrutural)

Se o workflow terminar com `[guard] CONTEXT rejected: …` (a guarda `context-guard.sh`
falhou 2× por corrupção estrutural — tag ausente/desbalanceada, parser `could-not-parse`),
ele **não commita**, preserva o checkpoint e deixa `NN-CONTEXT.rejected.md`. Não tente
"consertar na mão" o arquivo rejeitado: devolva `estado: falha` com o `motivo:` técnico
literal da guarda e o caminho do `.rejected.md`. Execute o passo 4 mesmo assim. Sino não é
controle de fluxo — só este estado para o pai.

## Retorno (obrigatório, sem prosa antes ou depois)

```
estado: done | pausa | falha
context: <caminho absoluto do NN-CONTEXT.md, ou ausente se pausa/falha antes de nascer>
motivo: <só no estado falha — as linhas [guard] FAIL literais + caminho do NN-CONTEXT.rejected.md>
chain_flag_zerada: sim | nao — <porquê>
base_context: <blob do .base-CONTEXT.txt; nao_gravado + porquê se o CONTEXT não nasceu>
dedup_aplicada: <n parágrafos substituídos por ponteiro; 0 se o passe já saiu limpo>
sinos: [<um item por linha; ausente se vazio — grave também em <phase_dir>/.intent/.sinos-discuss.txt (1 por linha): o briefing do revisor lê do arquivo, não do retorno>]
pergunta: <só no estado pausa — a decisão pendente com opções e sua recomendação primeiro>
```
