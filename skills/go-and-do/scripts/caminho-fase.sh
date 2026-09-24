#!/usr/bin/env bash
# caminho-fase.sh — CLI do helper de layout da fase (v2.10.1, tarefa 57), para prompts e
# para o modelo. Toda a regra mora em lib/gad-caminhos.sh; aqui só a porta de linha de comando.
#
# Uso:
#   caminho-fase.sh <phase_dir> <rel>        → caminho real de <rel> (nome NOVO, relativo a
#                                              .gad/) conforme o formato da fase
#                                              ex.: … intent/c1/vereditos.txt
#                                                   novo   → <pd>/.gad/intent/c1/vereditos.txt
#                                                   antigo → <pd>/.intent/.vereditos-c1.txt
#   caminho-fase.sh <phase_dir> --formato    → novo | antigo
#   caminho-fase.sh --tabela                 → a tabela nome novo → nome antigo (exemplos)
# Exit: 0 ok · 2 uso.
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gad-caminhos.sh"
if [ "${1:-}" = --tabela ]; then
  for r in intent/c1/vereditos.txt intent/c1/status-codex.json intent/c1/done-codex \
           intent/c1/briefing.md intent/c1/runs/RUN intent/c0/ciclo.json intent/c0b/releitura.json \
           intent/sinos-spec.txt intent/pre-spec-route.json convergencia/c1/done-agy \
           lanes/roda-codex-c1.json lanes/codex-review.done fences/3.ok gates/5.json \
           gates/5-evidencia.txt plan-checker/iter-1.yaml pos-ship/vereditos.json uat/humano-4.1.md; do
    printf '.gad/%-32s ← %s\n' "$r" "$(gad_fase_legado_rel "$r")"
  done
  exit 0
fi
PD="${1:-}"; REL="${2:-}"
[ -n "$PD" ] && [ -n "$REL" ] || { echo "uso: caminho-fase.sh <phase_dir> <rel> | <phase_dir> --formato | --tabela" >&2; exit 2; }
if [ "$REL" = --formato ]; then gad_fase_formato "$PD"; echo; exit 0; fi
gad_fase_caminho "$PD" "$REL"; echo
