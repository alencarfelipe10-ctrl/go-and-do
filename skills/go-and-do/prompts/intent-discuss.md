<!-- prompts/intent-discuss.md — filho de camada 2 (agente gad-discuss) que hospeda o
     gsd-discuss-phase para o subagente de intenção. Lido do disco PELO FILHO. -->

# Filho da intenção — CONTEXT (o como)

O despacho te entrega `N`, `NN`, `project_root` e `phase_dir` (absolutos). Comece todo
bloco Bash com `cd "<project_root>"` e use caminhos absolutos em tudo.

## Trabalho

1. Se `<phase_dir>/NN-CONTEXT.md` já existe → não re-rode nada; pule ao passo 4
   (a neutralização da flag é idempotente e barata) e devolva `done`.
1b. **PRE-SPEC (insumo pré-travado).** Se o despacho trouxe `pre_spec: <caminho>`,
   `Read` o arquivo INTEIRO antes de invocar o workflow. Decisões registradas ali são
   **travadas pelo usuário**: gray area que o PRE-SPEC já responde não é re-decidida —
   adote a resposta dele e persista-a com `--origin pre-spec` (em vez de `--origin auto`)
   na chamada do `checkpoint-write.py add-decision`; o renderizador emite a marca
   `[pre-spec, R-n]` no bullet do CONTEXT (a marca em prosa não existe mais — o campo
   `origin` do checkpoint é a fonte, e a âncora `R-n` vem junto).
   Conflito irreconciliável entre PRE-SPEC e SPEC → sino em `.sinos-discuss.txt`,
   nunca resolução silenciosa.
   ⚠️ **`--chosen-option` é 0-indexado** (`context-render.py`/`checkpoint-write.py` do
   fork): a 1ª opção listada é `0`, a 2ª é `1`. Na F24.3 o agente passou `1` querendo a
   1ª e marcou a opção errada nas 12 decisões (autocorrigido, 6 turnos perdidos). Conte a
   partir de zero.
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
dedup_aplicada: <n parágrafos substituídos por ponteiro; 0 se o passe já saiu limpo>
sinos: [<um item por linha; ausente se vazio — grave também em <phase_dir>/.intent/.sinos-discuss.txt (1 por linha): o briefing do revisor lê do arquivo, não do retorno>]
pergunta: <só no estado pausa — a decisão pendente com opções e sua recomendação primeiro>
```
