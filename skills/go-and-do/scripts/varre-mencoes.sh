#!/usr/bin/env bash
# varre-mencoes.sh — FM-F4RLR-03PLAN: depois de mover ou remover um plano no replan,
# varre por grep todas as menções a ele que sobraram nos arquivos VIVOS da fase.
#
# Origem: F4 RLR (21/09/2026) — a varredura de um plano removido foi feita à mão e só
# cobriu o VALIDATION.md; 10 menções sobraram em outros arquivos (grep, medido). Este
# script existe para o planner corrigir ou o hospedeiro registrar, sem depender de
# lembrar de olhar em todo lugar.
#
# Uso: varre-mencoes.sh <pasta-da-fase> <id-do-plano>
#   <id-do-plano> = o identificador do plano tal como citado nos documentos (ex.: "7-08",
#   "24.5-03-nome-do-plano"). Casamento é por STRING LITERAL (-F), não regex — o id pode
#   ter caracteres especiais de regex (ponto no número da fase).
#
# Varre *.md, *.json, *.jsonl vivos na pasta da fase (recursivo). NUNCA varre .git/ nem
# arquivos binários. O próprio PLAN.md do plano (se ainda existir) e o SUMMARY dele são
# esperados citarem o id — por isso ENTRAM na lista (quem decide se é "sobra" ou
# referência legítima é o planner/hospedeiro, não este script; verificação vira script,
# julgamento fica no modelo).
#
# Saída: JSON de 1 linha {"id":…, "pasta":…, "total_arquivos":N, "arquivos":[{arquivo,
# ocorrencias:[{linha,texto}]}]}. Exit 0 sempre — é ferramenta de relato.

set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gsd-shim.sh" 2>/dev/null \
  && trap 'gad_autoregistro "varre-mencoes.sh" "$?"' EXIT || true

PASTA="${1:-}"; ID="${2:-}"
[ -n "$PASTA" ] && [ -n "$ID" ] || {
  echo "uso: varre-mencoes.sh <pasta-da-fase> <id-do-plano>" >&2; exit 2
}
[ -d "$PASTA" ] || { echo "ERRO: pasta não encontrada: $PASTA" >&2; exit 2; }
command -v jq >/dev/null || { echo "ERRO: jq ausente" >&2; exit 2; }

mapfile -t ARQS < <(find "$PASTA" -type f \( -name '*.md' -o -name '*.json' -o -name '*.jsonl' \) \
  -not -path '*/.git/*' 2>/dev/null | sort -u)

ITENS="[]"
TOTAL=0
for f in "${ARQS[@]}"; do
  [ -f "$f" ] || continue
  OCORR=$(grep -nF -- "$ID" "$f" 2>/dev/null | jq -Rn '
    [inputs | capture("^(?<n>[0-9]+):(?<t>.*)$") | {linha:(.n|tonumber), texto:.t}]')
  N=$(jq 'length' <<<"$OCORR")
  [ "$N" -gt 0 ] || continue
  TOTAL=$((TOTAL+1))
  REL="${f#"$PASTA"/}"
  ITENS=$(jq -c --arg a "$REL" --argjson o "$OCORR" '. + [{arquivo:$a, ocorrencias:$o}]' <<<"$ITENS")
done

JSON=$(jq -cn --arg id "$ID" --arg pasta "$PASTA" --argjson tot "$TOTAL" --argjson it "$ITENS" \
  '{id:$id, pasta:$pasta, total_arquivos:$tot, arquivos:$it}')
gad_json_out varre-mencoes "$JSON" || echo "$JSON"
exit 0
