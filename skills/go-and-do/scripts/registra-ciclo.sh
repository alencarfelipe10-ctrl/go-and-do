#!/usr/bin/env bash
# registra-ciclo.sh — apêndice por-ciclo no NN-REVIEWS.md (decisão 2.5-D).
#
# O registro do ciclo é gravado no fim DO CICLO, não só no fecho — uma convergência que
# não fecha (caso 21/07: ~100min sem CONVERGENCE.md) não pode deixar os ciclos que
# rodaram sem rastro de modelo em artefato. Junta as evidências mecânicas dos espelhos
# dos roda-* + a tabela anti-omissão do confere-ciclo.sh.
#
# Uso: registra-ciclo.sh <phase_dir> <NN> <ciclo>
# Lê:  pareceres/.roda-codex-c<k>.json · pareceres/.roda-agy-c<k>.json (os que existirem)
# Grava: apêndice em <phase_dir>/NN-REVIEWS.md · pareceres/.tabela-c<k>.txt
# Exit 0 sempre que registrar; 2 = uso inválido.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; NN="${2:-}"; K="${3:-}"
[ -n "$PD" ] && [ -n "$NN" ] && [ -n "$K" ] || { echo "uso: registra-ciclo.sh <phase_dir> <NN> <ciclo>" >&2; exit 2; }
PAR="$PD/pareceres"
REV="$PD/$NN-REVIEWS.md"

# tabela anti-omissão do ciclo (piso mecânico; a contagem de brutos vem DAQUI)
PARECERES=()
for f in "$PAR/$NN-parecer-codex-c$K.md" "$PAR/$NN-parecer-agy-c$K.md"; do
  [ -s "$f" ] && PARECERES+=("$f")
done
TABELA="$PAR/.tabela-c$K.txt"
if [ ${#PARECERES[@]} -gt 0 ]; then
  bash "$GAD_SCRIPTS_DIR/confere-ciclo.sh" --tabela "${PARECERES[@]}" > "$TABELA" 2>/dev/null || true
fi
BRUTOS=0
if [ -f "$TABELA" ]; then
  BRUTOS=$( { grep -cE '^\| [a-z]+ \| L?[0-9]+ \|' "$TABELA" || true; } | head -1 ); : "${BRUTOS:=0}"
fi

{
  echo
  echo "## Ciclo $K — registro mecânico (gad, $(date -Is))"
  echo
  for lane in codex agy; do
    J="$PAR/.roda-$lane-c$K.json"
    [ -f "$J" ] || continue
    if [ "$lane" = codex ]; then
      echo "- **codex**: modelo_efetivo=\`$(jq -r '.modelo_efetivo' "$J")\` · fresco=$(jq -r '.fresco' "$J") · vazio=$(jq -r '.vazio' "$J")"
      b=$(jq -r '.banner // ""' "$J"); [ -n "$b" ] && echo "  - codex_model_evidencia: \`$b\`"
    else
      echo "- **agy**: prova_leitura=$(jq -r '.prova_leitura' "$J") · degradado=$(jq -r '.degradado' "$J") · vazio=$(jq -r '.vazio' "$J")"
      e=$(jq -r '.evidencia // ""' "$J"); [ -n "$e" ] && echo "  - agy_model_evidencia: \`$e\`"
      jq -r '.sinos[]? | "  - 🔔 " + .' "$J"
    fi
  done
  echo "- brutos na tabela do ciclo: $BRUTOS (\`pareceres/.tabela-c$K.txt\`)"
} >> "$REV"

gad_autoregistro "registra-ciclo.sh" 0 "c$K registrado ($BRUTOS brutos)" || true
gad_json_out registra-ciclo "$(jq -cn --arg r "$REV" --arg t "$TABELA" --argjson b "$BRUTOS" \
  '{reviews:$r, tabela:$t, brutos:$b}')"
