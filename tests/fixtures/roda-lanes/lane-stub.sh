#!/usr/bin/env bash
# lane-stub.sh — dublê de `roda-<lane>.sh` para a bancada do roda-lanes.sh (E4).
# Nunca chama Codex/agy de verdade. O comportamento vem de $STUB_CFG/<lane>.env
# (sourced), com as chaves: SLEEP, RC, PARECER, ESPELHO, NONCE(sim|nao), NUL(sim|nao),
# SUICIDA(sim|nao), NOLOG(sim|nao), FRESCO, DEGRADADO, STARTED, WAIT_FOR, CORPO.
# Ausência de arquivo .env = parecer válido trivial.
# Barreiras de arquivo (P15): STARTED=<arquivo> é criado assim que o dublê começa;
# WAIT_FOR=<arquivo> segura o dublê até o arquivo existir (o teste cria quando quiser
# liberar — ou nunca, no caso de timeout). Substituem o SLEEP como sincronização: dormir
# N segundos é corrida sob carga. CORPO=<arquivo> é copiado como corpo do parecer (bancada
# da cancela parecer_informe do confere-ciclo.sh).
set -u
LANE="$(basename -- "$0")"; LANE="${LANE#roda-}"; LANE="${LANE%.sh}"
PD="${1:-}"; NN="${2:-}"; K="${3:-}"; BRIEF="${4:-}"; shift 4 || true
OUT=""; ESP=""; LOG=""; ERR=""; PROVA=""
while [ $# -gt 0 ]; do case "$1" in
  --out) OUT="${2:-}"; shift 2 ;; --espelho) ESP="${2:-}"; shift 2 ;;
  --log) LOG="${2:-}"; shift 2 ;; --err) ERR="${2:-}"; shift 2 ;;
  --prova) PROVA="${2:-}"; shift 2 ;; *) shift ;;
esac; done
SLEEP=0; RC=0; PARECER="Parecer de bancada da lane $LANE."; ESPELHO="auto"
NONCE=nao; NUL=nao; SUICIDA=nao; NOLOG=nao; STARTED=""; WAIT_FOR=""; CORPO=""
[ -n "${STUB_CFG:-}" ] && [ -f "$STUB_CFG/$LANE.env" ] && . "$STUB_CFG/$LANE.env"
[ -n "$STARTED" ] && : > "$STARTED"
if [ -n "$WAIT_FOR" ]; then while [ ! -e "$WAIT_FOR" ]; do sleep 0.05; done; fi
[ "$SLEEP" != 0 ] && sleep "$SLEEP"
[ "$SUICIDA" = sim ] && kill -9 $$
[ -n "$LOG" ] && [ "$NOLOG" = nao ] && echo "log de bancada da lane $LANE" > "$LOG"
[ -n "$ERR" ] && : > "$ERR"
PROVA_OK=ausente
if [ -n "$CORPO" ] && [ -f "$CORPO" ]; then
  cat "$CORPO" > "$OUT"
elif [ -n "$PARECER" ]; then
  { echo "$PARECER"; echo "src/exemplo.ts:42 — citação de fonte."; } > "$OUT"
fi
if [ -s "$OUT" ]; then
  if [ "$NONCE" = sim ] && [ -n "$PROVA" ] && [ -f "$PROVA" ]; then
    TOKEN="$(grep -oE 'PROVA-[0-9a-f]+' "$PROVA" | head -1)"
    printf 'prova_leitura: %s\n' "$TOKEN" >> "$OUT"; PROVA_OK=ok
  fi
  [ "$NUL" = sim ] && printf 'lixo\000binario\n' >> "$OUT"
fi
case "$ESPELHO" in
  NONE) : ;;
  MALFORMED) [ -n "$ESP" ] && printf '{ isto nao e json\n' > "$ESP" ;;
  auto) [ -n "$ESP" ] && jq -cn --arg p "$OUT" --arg pl "$PROVA_OK" \
          --argjson v "$([ -s "$OUT" ] && echo false || echo true)" \
          --argjson f "${FRESCO:-true}" --argjson d "${DEGRADADO:-false}" \
          '{parecer:$p, vazio:$v, fresco:$f, degradado:$d, prova_leitura:$pl, sinos:[]}' > "$ESP" ;;
  *) [ -n "$ESP" ] && printf '%s\n' "$ESPELHO" > "$ESP" ;;
esac
exit "$RC"
