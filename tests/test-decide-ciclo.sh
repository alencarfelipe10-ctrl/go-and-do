#!/usr/bin/env bash
# test-decide-ciclo.sh — bancada da parada por rendimento do loop da consultoria (R3, plano 3).
#
# Régua: o loop continua por proteção do Goal, não por achado. `confirmado_irrelevante` é
# contado em `dispensados` e não entra em `novos` nem em `novos_ab`; um ciclo cujo rendimento
# inteiro é verdadeiro-e-irrelevante para de comprar o seguinte; nenhum limiar numérico novo
# (o script estava sem teste até 05/09/2026).
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/decide-ciclo.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-dc-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

# fase <nome> → phase_dir com nome de fase (o shim grava run-log da fase no diretório)
fase() { local d="$TMP/$1/.planning/phases/24.3-$1"; mkdir -p "$d/.intent" "$d/pareceres"; echo "$d"; }
vereditos() { # <phase_dir> <C> <linha "id|classe|veredito|cat"...>
  local pd="$1" c="$2"; shift 2; : > "$pd/.intent/.vereditos-c$c.txt"
  local l; for l in "$@"; do printf '%s\n' "$l" | awk -F'|' '{printf "%s | %s | %s | %s\n",$1,$2,$3,$4}' >> "$pd/.intent/.vereditos-c$c.txt"; done
}
roda() { (cd "$TMP" && bash "$SCRIPT" "$@" 2>/dev/null); }
j() { printf '%s' "$1" | jq -r "$2"; }

echo "== os quatro desfechos, sem dispensados (comportamento de sempre)"
D=$(fase continua); vereditos "$D" 1 "c1-01|novo|confirmado|A-produto" "c1-02|novo|confirmado|D-documental"
s=$(roda "$D" 1); [ "$(j "$s" .decisao)" = continua ] && [ "$(j "$s" .novos_ab)" = 1 ] && [ "$(j "$s" .dispensados)" = 0 ] \
  && ok "1 A/B confirmado → continua (novos_ab=1, dispensados=0)" || erro "continua" "$s"
D=$(fase zerou); vereditos "$D" 2 "c2-01|novo|nao_sustentado|A-produto" "c2-02|reformulado|confirmado|A-produto"
s=$(roda "$D" 2); [ "$(j "$s" .decisao)" = para-zerou ] && [ "$(j "$s" .motivo)" = "ciclo 2: nenhum achado novo confirmado — convergiu" ] \
  && ok "nenhum novo confirmado (reformulado é eco) → para-zerou, motivo de sempre" || erro "para-zerou" "$s"
D=$(fase teto); vereditos "$D" 4 "c4-01|novo|confirmado|B-viabilidade"
s=$(roda "$D" 4); [ "$(j "$s" .decisao)" = para-teto ] && ok "ciclo 4 → para-teto" || erro "para-teto" "$s"
D=$(fase custo); vereditos "$D" 2 "c2-01|novo|confirmado|C-instrumentacao" "c2-02|reaberto|confirmado|D-documental"
s=$(roda "$D" 2); [ "$(j "$s" .decisao)" = para-custo-marginal ] && [ "$(j "$s" '.lote_cde|join(",")')" = "c2-01,c2-02" ] \
  && ok "só C/D/E → para-custo-marginal com o lote" || erro "custo marginal" "$s"
D=$(fase c1-nunca-corta); vereditos "$D" 1 "c1-01|novo|confirmado|D-documental"
s=$(roda "$D" 1); [ "$(j "$s" .decisao)" = continua ] && ok "ciclo 1 com só D → continua (ciclo 1 nunca é cortado)" || erro "c1" "$s"
D=$(fase sem-dados); s=$(roda "$D" 1); rc=$?
[ "$rc" = 3 ] && ok "sem .vereditos → exit 3 (sem_dados)" || erro "esperado 3, veio $rc" "$s"

echo "== R3 — dispensado não entra em novos nem em novos_ab; ciclo só de dispensados para"
D=$(fase so-disp); vereditos "$D" 2 "c2-01|novo|confirmado_irrelevante|B-viabilidade" "c2-02|novo|confirmado_irrelevante|A-produto" "c2-03|novo|confirmado_irrelevante|D-documental"
s=$(roda "$D" 2)
[ "$(j "$s" .novos_confirmados)" = 0 ] && [ "$(j "$s" .novos_ab)" = 0 ] && ok "3 dispensados: novos=0, novos_ab=0" || erro "contagem" "$s"
[ "$(j "$s" .dispensados)" = 3 ] && ok "dispensados=3 no JSON" || erro "dispensados" "$s"
[ "$(j "$s" .decisao)" = para-zerou ] && ok "decisão para-zerou (o ciclo que só rendeu irrelevantes não compra o seguinte)" || erro "decisão" "$s"
[ "$(j "$s" .motivo)" = "ciclo 2: nenhum achado novo com vínculo ao Goal — convergiu (3 dispensado(s) registrado(s))" ] \
  && ok "o motivo não diz «nenhum achado» quando houve dispensados" || erro "motivo" "$s"
D=$(fase misto); vereditos "$D" 3 "c3-01|novo|confirmado|A-produto" "c3-02|novo|confirmado_irrelevante|B-viabilidade" "c3-03|novo|confirmado|C-instrumentacao"
s=$(roda "$D" 3)
[ "$(j "$s" .decisao)" = continua ] && [ "$(j "$s" .novos_ab)" = 1 ] && [ "$(j "$s" .novos_confirmados)" = 2 ] && [ "$(j "$s" .dispensados)" = 1 ] \
  && ok "misto: 1 A/B com vínculo continua; o dispensado não conta (novos=2, ab=1, disp=1)" || erro "misto" "$s"
D=$(fase disp-c1); vereditos "$D" 1 "c1-01|novo|confirmado_irrelevante|A-produto"
s=$(roda "$D" 1); [ "$(j "$s" .decisao)" = para-zerou ] && ok "ciclo 1 só de dispensados → para-zerou (zero por dispensa não é silêncio)" || erro "c1 disp" "$s"
D=$(fase disp-cd); vereditos "$D" 2 "c2-01|novo|confirmado|D-documental" "c2-02|novo|confirmado_irrelevante|A-produto"
s=$(roda "$D" 2); [ "$(j "$s" .decisao)" = para-custo-marginal ] && [ "$(j "$s" '.lote_cde|join(",")')" = "c2-01" ] \
  && ok "dispensado A não vira A/B nem entra no lote C/D/E" || erro "lote" "$s"

echo "== retrocompatibilidade — arquivo antigo (só os três vereditos) sai idêntico, mais dispensados: 0"
D=$(fase legado); vereditos "$D" 3 "c3-01|novo|confirmado|A-produto" "c3-02|novo|ja_coberto|B-viabilidade" "c3-03|novo|nao_sustentado|D-documental"
s=$(roda "$D" 3)
[ "$(j "$s" 'keys|join(",")')" = "ciclo,decisao,dispensados,lanes_reprovadas,lote_cde,motivo,novos_ab,novos_confirmados" ] \
  && ok "chaves do JSON: as de sempre + dispensados" || erro "chaves" "$s"
[ "$(j "$s" .dispensados)" = 0 ] && [ "$(j "$s" .decisao)" = continua ] && ok "dispensados=0, decisão de sempre" || erro "legado" "$s"

echo
[ "$falhas" -eq 0 ] && echo "test-decide-ciclo: TUDO OK" || echo "test-decide-ciclo: $falhas falha(s)"
[ "$falhas" -eq 0 ]
