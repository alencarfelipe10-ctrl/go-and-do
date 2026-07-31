<!-- prompts/intent-discuss.md — filho de camada 2 (agente gad-discuss) que hospeda o
     gsd-discuss-phase para o subagente de intenção. Lido do disco PELO FILHO. -->

# Filho da intenção — CONTEXT (o como)

O despacho te entrega `N`, `NN`, `project_root` e `phase_dir` (absolutos). Comece todo
bloco Bash com `cd "<project_root>"` e use caminhos absolutos em tudo.

## Trabalho

1. Se `<phase_dir>/NN-CONTEXT.md` já existe → não re-rode nada; pule ao passo 4
   (a neutralização da flag é idempotente e barata) e devolva `done`.
2. Invoque `Skill` → `gsd-discuss-phase` com args `N --auto`. Ele carrega o SPEC.md,
   seleciona todas as gray areas, escolhe a opção recomendada em cada decisão (logando
   `[auto]` no CONTEXT.md) e escreve+commita o `NN-CONTEXT.md` em passe único.
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

## Retorno (obrigatório, sem prosa antes ou depois)

```
estado: done | pausa
context: <caminho absoluto do NN-CONTEXT.md, ou ausente se pausa antes de nascer>
chain_flag_zerada: sim | nao — <porquê>
dedup_aplicada: <n parágrafos substituídos por ponteiro; 0 se o passe já saiu limpo>
sinos: [<um item por linha; ausente se vazio>]
pergunta: <só no estado pausa — a decisão pendente com opções e sua recomendação primeiro>
```
