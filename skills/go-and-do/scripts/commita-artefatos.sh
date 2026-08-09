#!/usr/bin/env bash
# commita-artefatos.sh — commits mecânicos do fecho da fase (decisão 6.A: os blocos
# bash prontos do 6.3b e do 6.5 viram funções de script — escritor único: script
# commita, modelo não digita git).
#
# Uso: commita-artefatos.sh <phase_dir> <NN> <uat|runlog>
#   uat    — NN-UAT.md + uat-evidencia/ (árvore limpa pro preflight do ship; caminhos
#            explícitos — NUNCA git add de diretório .planning inteiro nem .err/.log)
#   runlog — NN-RUN-LOG.jsonl + NN-DECISOES.md (fecho da rodada, 6.5)
#
# Best-effort: sem git/nada staged → exit 0 com aviso (commit falhou não para fase).

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; NN="${2:-}"; MODO="${3:-}"
[ -n "$PD" ] && [ -n "$NN" ] || { echo "uso: commita-artefatos.sh <phase_dir> <NN> <uat|runlog>" >&2; exit 2; }
ROOT="$(gad_project_root "$PD")"
cd "$ROOT"

STATUS=ok
case "$MODO" in
  uat)
    git add "$PD/$NN-UAT.md" 2>/dev/null || true
    [ -d "$PD/uat-evidencia" ] && git add "$PD/uat-evidencia" 2>/dev/null || true
    MSG="docs(fase $NN): artefatos do UAT (resultado + evidências)" ;;
  runlog)
    git add "$PD/$NN-RUN-LOG.jsonl" 2>/dev/null || true
    [ -f "$PD/$NN-DECISOES.md" ] && git add "$PD/$NN-DECISOES.md" 2>/dev/null || true
    MSG="docs(fase $NN): run-log e decisões da rodada" ;;
  *) echo "modo desconhecido: $MODO (uat|runlog)" >&2; exit 2 ;;
esac
if git diff --cached --quiet 2>/dev/null; then
  STATUS=nada_a_commitar
else
  git commit -m "$MSG" >/dev/null 2>&1 || STATUS=falhou
fi
gad_autoregistro "commita-artefatos.sh" 0 "$MODO: $STATUS" || true
gad_json_out commita-artefatos "$(jq -cn --arg m "$MODO" --arg s "$STATUS" '{modo:$m, commit:$s}')"
