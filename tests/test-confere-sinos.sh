#!/usr/bin/env bash
# test-confere-sinos.sh — bancada do gate de sinos abertos ao fecho da etapa de
# intenção (item C3 do plano de consertos F24.4).
#
# Régua: `.ciclo0.json` tem uma lista `sinos[]`; cada sino tem `disposicao` em
# {corrigido, descartado, aberto}. Nenhum gate hoje impede a etapa de intenção de
# fechar com sinos `aberto` sobrando — este script é esse gate. Zero abertos (ou
# nenhum `.ciclo0.json`, fase sem sinos) passa; qualquer `aberto` reprova nomeando
# o sino; JSON ilegível é uso inválido, não "zero sinos".
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/confere-sinos.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-sinos-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

# monta_ciclo0 <phase_dir> <json_de_sinos>
monta_ciclo0() {
  local pd="$1" sinos_json="$2"
  mkdir -p "$pd/.intent"
  printf '{"v":1,"sinos":%s,"correcoes":[],"releitura":{}}\n' "$sinos_json" \
    > "$pd/.intent/.ciclo0.json"
}

echo "== (a) zero sinos abertos → exit 0"
D="$TMP/a"
monta_ciclo0 "$D" '[
  {"id":"c0-01","origem":"spec","disposicao":"corrigido","correcao_id":"c0-01"},
  {"id":"c0-02","origem":"discuss","disposicao":"descartado"}
]'
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^sinos_abertos: 0$" && [ "$rc" = 0 ] \
  && ok "todos corrigido/descartado → sinos_abertos: 0, exit 0" \
  || erro "esperado sinos_abertos: 0 / exit 0" "$saida (rc=$rc)"

echo "== (b) dois sinos abertos → exit 1 com as duas linhas"
D="$TMP/b"
monta_ciclo0 "$D" '[
  {"id":"c0-01","origem":"spec","disposicao":"corrigido","correcao_id":"c0-01"},
  {"id":"c0-07","origem":"discuss","disposicao":"aberto"},
  {"id":"c0-14","origem":"discuss","disposicao":"aberto"}
]'
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^sinos_abertos: 2$" && [ "$rc" = 1 ] \
  && ok "sinos_abertos: 2, exit 1" || erro "contagem/exit errados" "$saida (rc=$rc)"
printf '%s' "$saida" | grep -q "c0-07" && printf '%s' "$saida" | grep -q "c0-14" \
  && ok "as duas linhas (c0-07, c0-14) aparecem nomeadas" \
  || erro "sino aberto não nomeado na saída" "$saida"
printf '%s' "$saida" | grep -q "SINOS-ABERTOS: 2 sino(s)" \
  && ok "mensagem final SINOS-ABERTOS presente" || erro "mensagem final ausente" "$saida"

echo "== (c) .ciclo0.json ausente → exit 0 com n/a (fase sem sinos é legítima)"
D="$TMP/c"; mkdir -p "$D"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "sinos_abertos: n/a (sem .ciclo0.json)" && [ "$rc" = 0 ] \
  && ok "sem .intent/ nenhuma → n/a, exit 0" || erro "ausência devia ser n/a/exit 0" "$saida (rc=$rc)"

D="$TMP/c2"; mkdir -p "$D/.intent"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "sinos_abertos: n/a (sem .ciclo0.json)" && [ "$rc" = 0 ] \
  && ok ".intent/ existe mas sem .ciclo0.json → n/a, exit 0" \
  || erro "ausência do .ciclo0.json (com .intent/ presente) devia ser n/a/exit 0" "$saida (rc=$rc)"

echo "== (d) JSON inválido → exit 2"
D="$TMP/d"; mkdir -p "$D/.intent"
printf '{ isso nao e json' > "$D/.intent/.ciclo0.json"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "JSON malformado → exit 2" || erro "esperado exit 2, veio $rc" "$saida"

echo '== schema sem chave sinos[] -> exit 2 (uso invalido, nao zero sinos)'
D="$TMP/e"; mkdir -p "$D/.intent"
printf '{"v":1,"correcoes":[],"releitura":{}}\n' > "$D/.intent/.ciclo0.json"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
[ "$rc" = 2 ] && ok 'sem chave sinos -> exit 2' || erro "esperado exit 2, veio $rc" "$saida"

echo "== uso inválido: sem argumento / phase_dir inexistente"
saida=$("$SCRIPT" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "sem argumento → exit 2" || erro "esperado exit 2, veio $rc" "$saida"

saida=$("$SCRIPT" "$TMP/nao-existe" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "phase_dir inexistente → exit 2" || erro "esperado exit 2, veio $rc" "$saida"

echo "== regressão contra o caso real da F24.4 (fixture congelada aqui, cópia local)"
# Réplica local (não lemos o diretório real do grupo-inspired num teste automatizado
# recorrente — a validação contra o artefato de verdade foi feita manualmente e está
# registrada no relatório). Aqui fixamos o formato observado: 14 sinos, 13 correções,
# só c0-14 aberto sem correcao_id.
D="$TMP/f24_4"
monta_ciclo0 "$D" '[
  {"id":"c0-01","origem":"discuss","disposicao":"corrigido","correcao_id":"c0-01"},
  {"id":"c0-02","origem":"discuss","disposicao":"corrigido","correcao_id":"c0-02"},
  {"id":"c0-03","origem":"spec","disposicao":"corrigido","correcao_id":"c0-03"},
  {"id":"c0-04","origem":"discuss","disposicao":"corrigido","correcao_id":"c0-04"},
  {"id":"c0-05","origem":"spec","disposicao":"corrigido","correcao_id":"c0-05"},
  {"id":"c0-06","origem":"discuss","disposicao":"corrigido","correcao_id":"c0-06"},
  {"id":"c0-07","origem":"discuss","disposicao":"corrigido","correcao_id":"c0-07"},
  {"id":"c0-08","origem":"spec","disposicao":"corrigido","correcao_id":"c0-08"},
  {"id":"c0-09","origem":"spec","disposicao":"corrigido","correcao_id":"c0-09"},
  {"id":"c0-10","origem":"spec","disposicao":"corrigido","correcao_id":"c0-10"},
  {"id":"c0-11","origem":"spec","disposicao":"corrigido","correcao_id":"c0b-01"},
  {"id":"c0-12","origem":"spec","disposicao":"corrigido","correcao_id":"c0b-02"},
  {"id":"c0-13","origem":"spec","disposicao":"corrigido","correcao_id":"c0b-03"},
  {"id":"c0-14","origem":"discuss","disposicao":"aberto"}
]'
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^sinos_abertos: 1$" && [ "$rc" = 1 ] \
  && ok "réplica da F24.4: sinos_abertos: 1, exit 1" \
  || erro "réplica da F24.4 não bateu com o esperado (1 aberto, exit 1)" "$saida (rc=$rc)"
printf '%s' "$saida" | grep -q "aberto: c0-14" \
  && ok "c0-14 nomeado, exatamente como a auditoria apurou" \
  || erro "c0-14 não apareceu nomeado" "$saida"

echo
[ "$falhas" -eq 0 ] && echo "test-confere-sinos: TUDO OK" || echo "test-confere-sinos: $falhas falha(s)"
[ "$falhas" -eq 0 ]
