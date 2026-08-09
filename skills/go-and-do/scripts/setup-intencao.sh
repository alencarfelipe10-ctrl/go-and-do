#!/usr/bin/env bash
# setup-intencao.sh — primeiro ato do coordenador de intenção (decisão 1.2).
#
# Irmão gêmeo, em granularidade fina, do if/else que o abre-rodada.sh mecanizou na
# camada 0: (a) higiene idempotente da flag de chain do discuss; (b) decisão de entrada
# pelo DISCO. O coordenador roda isto no primeiro turno e obedece o campo `entrada` —
# morre a classe "coordenador releu errado o estado e re-rodou o que estava pronto".
#
# Uso: setup-intencao.sh <phase_dir> <NN> [--com-resposta]
#
# Higiene: se NN-CONTEXT.md existe e a revisão não está done/skipped, roda
# `config-set workflow._auto_chain_active false` (zerar de novo é inócuo por design —
# um crash entre o discuss e o zeramento original deixaria a flag armada, e com ela o
# plan-phase encadearia direto pro execute, atropelando a revisão).
#
# `entrada` (ordem de precedência, tudo por existência/frontmatter — PC-2: um CONTEXT
# escrito à mão conta como pronto; o teste é existência, não autoria):
#   incorporar_resposta  — despacho veio com --com-resposta (continuação de pausa)
#   ja_pronto            — intent_review: done|skipped (idempotência: releia números e devolva)
#   reapresentar_pergunta— intent_review: needs_decision SEM resposta no despacho
#   revisao              — intent_review: blocked (re-tenta) OU spec+context prontos
#   spec                 — sem NN-SPEC.md
#   discuss              — sem NN-CONTEXT.md
#
# Também detecta NN-PRE-SPEC.md (campo `pre_spec`: insumo pré-travado pelo usuário —
# não muda a `entrada`, roteia o insumo aos filhos spec/discuss) e garante a pasta de
# trabalho .intent/ (decisão 1.5). Saída: JSON 1 linha +
# espelho PC-5. Exit 0 sempre que decidir; 2 = uso inválido.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; NN="${2:-}"; COM_RESPOSTA=0
[ -n "$PD" ] && [ -n "$NN" ] || { echo "uso: setup-intencao.sh <phase_dir> <NN> [--com-resposta]" >&2; exit 2; }
[ "${3:-}" = "--com-resposta" ] && COM_RESPOSTA=1
[ -d "$PD" ] || { echo "ERRO: phase_dir inexistente: $PD" >&2; exit 2; }

mkdir -p "$PD/.intent"

IR="$PD/$NN-INTENT-REVIEW.md"
ESTADO=""
[ -f "$IR" ] && ESTADO=$(grep -m1 '^intent_review:' "$IR" | sed 's/^intent_review: *//' | tr -d ' \r' || true)

# ── higiene idempotente da flag de chain ─────────────────────────────────────
CHAIN=nao_aplicavel
if [ -f "$PD/$NN-CONTEXT.md" ] && [ "$ESTADO" != "done" ] && [ "$ESTADO" != "skipped" ]; then
  ROOT="$(gad_project_root "$PD")"
  if (cd "$ROOT" && gsd_run query config-set workflow._auto_chain_active false >/dev/null 2>&1); then
    CHAIN=zerada
  else
    CHAIN=falhou   # declarado; a cancela do confere-etapa 1 barra na saída se armada
  fi
fi

# ── entrada fina pelo disco ──────────────────────────────────────────────────
if [ "$COM_RESPOSTA" = 1 ]; then          ENTRADA=incorporar_resposta
elif [ "$ESTADO" = done ] || [ "$ESTADO" = skipped ]; then ENTRADA=ja_pronto
elif [ "$ESTADO" = needs_decision ]; then ENTRADA=reapresentar_pergunta
elif [ "$ESTADO" = blocked ]; then        ENTRADA=revisao
elif [ ! -f "$PD/$NN-SPEC.md" ]; then     ENTRADA=spec
elif [ ! -f "$PD/$NN-CONTEXT.md" ]; then  ENTRADA=discuss
else                                      ENTRADA=revisao
fi

# PRE-SPEC: insumo pré-travado pelo usuário (existência exata, sem glob). Não muda a
# `entrada` — o SPEC continua sendo gerado; o coordenador repassa o caminho no despacho
# dos filhos spec/discuss, que o leem como insumo com decisões travadas.
PRE_SPEC=""
[ -f "$PD/$NN-PRE-SPEC.md" ] && PRE_SPEC="$PD/$NN-PRE-SPEC.md"

gad_json_out setup-intencao "$(jq -cn --arg ch "$CHAIN" --arg e "$ENTRADA" --arg est "${ESTADO:-ausente}" \
  --arg ps "$PRE_SPEC" \
  '{chain_flag_zerada:$ch, entrada:$e, intent_review:$est,
    pre_spec:(if $ps != "" then $ps else null end)}')"
