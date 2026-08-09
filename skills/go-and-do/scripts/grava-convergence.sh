#!/usr/bin/env bash
# grava-convergence.sh — marcador durável da convergência (decisão 2.5-D).
#
# Escreve o NN-CONVERGENCE.md (frontmatter convergence: done + ciclos + revisores +
# sinos) e commita best-effort. É este arquivo que o pre-despacho.sh 2.5 checa na
# retomada — sem ele, um crash entre a convergência e o fim do execute re-pagaria a
# revisão cruzada inteira (~68min num caso real).
#
# Uso: grava-convergence.sh <phase_dir> <NN> --ciclos N --revisores "codex,agy"
#                           [--sinos "a;b"] [--corpo ARQ]
#   --corpo: arquivo com as linhas "1 por correção aplicada" (insumo do modelo).
# Exit 0 = gravado (commit é best-effort; falha de commit vira aviso) · 2 = uso.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; NN="${2:-}"; CICLOS=""; REVS=""; SINOS=""; CORPO=""
[ -n "$PD" ] && [ -n "$NN" ] || { echo "uso: grava-convergence.sh <phase_dir> <NN> --ciclos N --revisores lista [--sinos ...] [--corpo ARQ]" >&2; exit 2; }
shift 2
while [ $# -gt 0 ]; do case "$1" in
  --ciclos) CICLOS="${2:-}"; shift 2 ;;
  --revisores) REVS="${2:-}"; shift 2 ;;
  --sinos) SINOS="${2:-}"; shift 2 ;;
  --corpo) CORPO="${2:-}"; shift 2 ;;
  *) shift ;;
esac; done
[ -n "$CICLOS" ] && [ -n "$REVS" ] || { echo "ERRO: --ciclos e --revisores são obrigatórios" >&2; exit 2; }

F="$PD/$NN-CONVERGENCE.md"
{
  echo "---"
  echo "convergence: done"
  echo "ciclos: $CICLOS"
  echo "revisores_efetivos: [$REVS]"
  [ -n "$SINOS" ] && echo "sinos: [$(printf '%s' "$SINOS" | sed 's/;/, /g')]"
  echo "gravado_por: grava-convergence.sh"
  echo "ts: $(date -Is)"
  echo "---"
  echo
  echo "# Convergência do plano — fase $NN ($CICLOS ciclo(s))"
  echo
  if [ -n "$CORPO" ] && [ -f "$CORPO" ]; then cat "$CORPO"; else echo "*(correções por ciclo registradas no $NN-REVIEWS.md)*"; fi
} > "$F"

COMMIT=ok
ROOT="$(gad_project_root "$PD")"
( cd "$ROOT" && git add "$F" 2>/dev/null \
  && { git diff --cached --quiet 2>/dev/null || git commit -m "docs(fase $NN): convergência do plano ($CICLOS ciclos)" >/dev/null; } ) \
  || COMMIT=falhou

gad_autoregistro "grava-convergence.sh" 0 "convergence done ($CICLOS ciclos, commit $COMMIT)" || true
gad_json_out grava-convergence "$(jq -cn --arg f "$F" --arg c "$COMMIT" '{convergence:$f, commit:$c}')"
