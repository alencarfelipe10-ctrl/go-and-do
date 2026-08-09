#!/usr/bin/env bash
# calcula-files.sh — escopo mecânico do re-review estreitado (decisão 4.C).
#
# O code review domina a Etapa 4 (45min/$27 medianos) e as iterações 2+ religam o
# escopo INTEIRO da 1ª. O `--files` é flag NATIVA do /gsd-code-review com precedência
# máxima — este script calcula a lista:
#
#   modo padrão (iteração 2+): diff desde o último commit que tocou o NN-REVIEW.md
#     (= tudo que os fixes mudaram desde o review) — decisão 4.C-a.
#   --tocados "a b c" (gate 4.1b): parte de uma lista dada (arquivos que o secure
#     tocou pós-review) — decisão 4.C-b.
#
# Mitigação de 1 salto (4.C-d): soma os DEPENDENTES REVERSOS diretos — arquivos que
# importam/requerem os módulos tocados (git grep mecânico de import/require/from) —
# porque fix pode mudar contrato (assinatura, retorno, exceção). O raio além de 1
# salto fica com quem já é dono dele (suíte Nyquist + UAT).
#
# Uso: calcula-files.sh <phase_dir> <NN> [--tocados "a b c"] [--projeto DIR]
# JSON: {files: [...], base, n_diff, n_dependentes} + espelho PC-5.
# Exit 0 = lista calculada (pode ser vazia — nada mudou) · 2 = uso/erro.

set -euo pipefail
shopt -s nullglob
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; NN="${2:-}"; TOCADOS=""; PROJ=""
[ -n "$PD" ] && [ -n "$NN" ] || { echo "uso: calcula-files.sh <phase_dir> <NN> [--tocados \"a b c\"] [--projeto DIR]" >&2; exit 2; }
shift 2
while [ $# -gt 0 ]; do case "$1" in
  --tocados) TOCADOS="${2:-}"; shift 2 ;;
  --projeto) PROJ="${2:-}"; shift 2 ;;
  *) shift ;;
esac; done
ROOT="$(gad_project_root "${PROJ:-$PD}")"
cd "$ROOT"

BASE=""
if [ -n "$TOCADOS" ]; then
  DIFF="$TOCADOS"; BASE="lista-do-secure"
else
  BASE=$(git log -1 --format=%H -- "$PD/$NN-REVIEW.md" 2>/dev/null || true)
  [ -n "$BASE" ] || { echo "ERRO: NN-REVIEW.md sem commit — não há 'desde o último review' para calcular" >&2; exit 2; }
  DIFF=$(git diff --name-only "$BASE"..HEAD 2>/dev/null | grep -v '^\.planning/' | tr '\n' ' ' || true)
fi

# dependentes reversos de 1 salto: quem importa o stem dos arquivos do diff
declare -A VISTO
LISTA=()
for f in $DIFF; do [ -n "$f" ] && [ -z "${VISTO[$f]:-}" ] && { VISTO[$f]=1; LISTA+=("$f"); }; done
N_DIFF=${#LISTA[@]}
DEPS=0
for f in $DIFF; do
  stem=$(basename "$f"); stem="${stem%.*}"
  [ -n "$stem" ] && [ "$stem" != "$f" ] || continue
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    case "$dep" in .planning/*) continue ;; esac
    [ -z "${VISTO[$dep]:-}" ] && { VISTO[$dep]=1; LISTA+=("$dep"); DEPS=$((DEPS+1)); }
  done < <(git grep -lE "(import|require|from)[^\"']*[\"'/.]${stem}[\"'.]" -- ':!*.md' ':!.planning' 2>/dev/null || true)
done

FILES=$(printf '%s\n' ${LISTA[@]+"${LISTA[@]}"} | jq -R . | jq -cs 'map(select(length>0))')
gad_json_out calcula-files "$(jq -cn --argjson f "$FILES" --arg b "$BASE" \
  --argjson nd "$N_DIFF" --argjson dp "$DEPS" \
  '{files:$f, base:$b, n_diff:$nd, n_dependentes:$dp}')"
