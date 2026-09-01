#!/usr/bin/env bash
# test-janela-silencio.sh — bancada do B1 (parada graciosa noturna, PLANO-B-rotas.md).
#
# Régua: silêncio = true para as horas 23 e 00–06 (mesma regra de pre-despacho.sh:76-79).
# `acao` é "pausa" quando silêncio, "pergunta" caso contrário. exit 0 = pergunta,
# exit 1 = pausa — é o exit code que uma rota de gate duro consome (`|| <pausa>`).
# GAD_HORA_FALSA força a hora sem depender do relógio real — é o que torna isto testável.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/janela-silencio.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-janela-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

checa() {
  # checa <hora_falsa> <silencio_esperado> <acao_esperada> <exit_esperado>
  local h="$1" sil_esp="$2" acao_esp="$3" rc_esp="$4"
  local saida rc
  saida=$(GAD_HORA_FALSA="$h" "$SCRIPT" 2>&1); rc=$?
  if printf '%s' "$saida" | grep -q "\"silencio\": $sil_esp" \
    && printf '%s' "$saida" | grep -q "\"acao\": \"$acao_esp\"" \
    && [ "$rc" = "$rc_esp" ]; then
    ok "hora=$h → silencio=$sil_esp acao=$acao_esp exit=$rc_esp"
  else
    erro "hora=$h esperava silencio=$sil_esp acao=$acao_esp exit=$rc_esp (veio exit=$rc)" "$saida"
  fi
}

echo "== B1 — as duas bordas nomeadas no plano"
checa 22 false pergunta 0   # 22 → pergunta (última hora fora da janela, à noite)
checa 23 true  pausa    1   # 23 → pausa (primeira hora da janela)
checa 06 true  pausa    1   # 06 → pausa (última hora da janela)
checa 07 false pergunta 0   # 07 → pergunta (primeira hora fora da janela, de manhã)

echo "== B1 — miolo da janela e do dia, para não confiar só nas bordas"
checa 00 true  pausa    1
checa 03 true  pausa    1
checa 12 false pergunta 0

echo "== B1 — uso inválido"
saida=$("$SCRIPT" --flag-inexistente 2>&1); rc=$?
[ "$rc" = 2 ] && ok "flag desconhecida → exit 2" || erro "esperado exit 2, veio $rc" "$saida"

saida=$(GAD_HORA_FALSA=25 "$SCRIPT" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "GAD_HORA_FALSA fora de 0-23 → exit 2" || erro "esperado exit 2, veio $rc" "$saida"

saida=$(GAD_HORA_FALSA=abc "$SCRIPT" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "GAD_HORA_FALSA não numérico → exit 2" || erro "esperado exit 2, veio $rc" "$saida"

echo "== B1 — --phase-dir é aceito (uniformidade de invocação) sem afetar o cálculo"
saida=$(GAD_HORA_FALSA=23 "$SCRIPT" --phase-dir "$TMP" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "\"acao\": \"pausa\"" && [ "$rc" = 1 ] \
  && ok "--phase-dir não muda o resultado" || erro "--phase-dir quebrou o cálculo" "$saida"

echo
[ "$falhas" -eq 0 ] && echo "test-janela-silencio: TUDO OK" || echo "test-janela-silencio: $falhas falha(s)"
[ "$falhas" -eq 0 ]
