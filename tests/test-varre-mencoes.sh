#!/usr/bin/env bash
# test-varre-mencoes.sh — bancada do varre-mencoes.sh (FM-F4RLR-03PLAN).
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
S="$AQUI/../skills/go-and-do/scripts/varre-mencoes.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-varre-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else erro "$1" "esperado [$3], obtido [$2]"; fi; }

echo "== menções espalhadas por .md e .json"
PD="$TMP/fase-a"; mkdir -p "$PD"
printf '# VALIDATION\n\nref ao 7-08 aqui\noutra linha 7-08 de novo\n' > "$PD/VALIDATION.md"
printf '{"nota":"cita 7-08 tambem"}\n' > "$PD/estado.json"
printf 'sem mencao nenhuma\n' > "$PD/limpo.md"
OUT=$(bash "$S" "$PD" 7-08); RC=$?
eq "exit 0" "$RC" 0
eq "2 arquivos com menção" "$(jq -r .total_arquivos <<<"$OUT")" 2
eq "VALIDATION.md com 2 ocorrências" "$(jq -r '.arquivos[] | select(.arquivo=="VALIDATION.md") | .ocorrencias|length' <<<"$OUT")" 2
eq "estado.json com 1 ocorrência" "$(jq -r '.arquivos[] | select(.arquivo=="estado.json") | .ocorrencias|length' <<<"$OUT")" 1
eq "limpo.md não entra na lista" "$(jq -r '.arquivos[] | select(.arquivo=="limpo.md")' <<<"$OUT")" ""

echo "== id que não aparece em lugar nenhum → 0 arquivos, exit 0"
PD2="$TMP/fase-b"; mkdir -p "$PD2"
printf 'nada aqui\n' > "$PD2/x.md"
OUT=$(bash "$S" "$PD2" 9-99); RC=$?
eq "exit 0" "$RC" 0
eq "0 arquivos" "$(jq -r .total_arquivos <<<"$OUT")" 0

echo "== id com ponto (número de fase 24.5) é casado LITERAL, não regex"
PD3="$TMP/fase-c"; mkdir -p "$PD3"
printf 'menciona 24.5-03 no texto\nmas 24X5-03 nao deveria casar\n' > "$PD3/doc.md"
OUT=$(bash "$S" "$PD3" 24.5-03); RC=$?
eq "só a linha literal casa (ponto não é wildcard)" "$(jq -r '.arquivos[0].ocorrencias|length' <<<"$OUT")" 1

echo "== .git/ nunca é varrido"
PD4="$TMP/fase-d"; mkdir -p "$PD4/.git"
printf 'cita 7-01\n' > "$PD4/.git/COMMIT_EDITMSG"
printf 'sem mencao\n' > "$PD4/doc.md"
OUT=$(bash "$S" "$PD4" 7-01)
eq "0 arquivos (.git ignorado)" "$(jq -r .total_arquivos <<<"$OUT")" 0

echo "== uso inválido → exit 2"
bash "$S" >/dev/null 2>&1; eq "sem argumentos" "$?" 2
bash "$S" "$TMP/nao-existe" 7-01 >/dev/null 2>&1; eq "pasta inexistente" "$?" 2

echo "--------------------------------------------------"
echo "$falhas falha(s)"
[ "$falhas" -eq 0 ]
