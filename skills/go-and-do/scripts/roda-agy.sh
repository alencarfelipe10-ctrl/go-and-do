#!/usr/bin/env bash
# roda-agy.sh — lane Antigravity da revisão adversarial (decisão 2.5-D do gad-major).
#
# Absorve os invariantes provados empiricamente (2026-07/08): log fixado por invocação
# (o last_conversations.json aponta a run mais recente do WORKSPACE, não a sua — a
# armadilha que cegou a F22) · prompt curto por referência · canário de leitura (nonce
# nasce AQUI e nunca passa pelo prompt) · evidência de modelo pelo log · stdout vazio =
# falha (rc=0 mesmo abortando) · JAMAIS --dangerously-skip-permissions (o auto-deny de
# escrita do headless É a garantia de leitura-apenas).
#
# Uso: roda-agy.sh <phase_dir> <NN> <ciclo> <briefing> [--out PATH] [--root DIR]
#   parecer default: <phase_dir>/pareceres/NN-parecer-agy-c<k>.md
#   log:             <phase_dir>/pareceres/NN-agy-c<k>.log (não vai no git)
#
# Canário: gera nonce em pareceres/.prova-leitura-c<k>.txt e garante no briefing a
# instrução de transcrição (append idempotente — o VALOR nunca entra no briefing).
# Provado na F22 (8/9 ciclos com nonce transcrito); a falha que detecta — parecer-
# paráfrase sem leitura de disco — é indetectável por qualquer outro meio.
#
# JSON: {parecer, evidencia, prova_leitura, degradado, log, vazio} + espelho
# pareceres/.roda-agy-c<k>.json. Exit: 0 = parecer válido · 5 = agy NÃO INSTALADO
# (revisor_ausente) · 6 = rodou e FALHOU (stdout vazio, modelo errado = degradado,
# ou parecer não-fresco) · 2 = uso.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; NN="${2:-}"; K="${3:-}"; BRIEF="${4:-}"; OUT=""; ROOT=""
[ -n "$PD" ] && [ -n "$NN" ] && [ -n "$K" ] && [ -f "${BRIEF:-/nao-existe}" ] \
  || { echo "uso: roda-agy.sh <phase_dir> <NN> <ciclo> <briefing> [--out PATH] [--root DIR]" >&2; exit 2; }
shift 4
while [ $# -gt 0 ]; do case "$1" in
  --out)  OUT="${2:-}"; shift 2 ;;
  --root) ROOT="${2:-}"; shift 2 ;;
  *) shift ;;
esac; done
[ -n "$ROOT" ] || ROOT="$(gad_project_root "$PD")"

mkdir -p "$PD/pareceres"
: "${OUT:=$PD/pareceres/$NN-parecer-agy-c$K.md}"
LOG="$PD/pareceres/$NN-agy-c$K.log"
ERR="$PD/pareceres/.agy-c$K.err"   # 0 bytes é NORMAL do agy (glog vai pro log-file)
ESPELHO="$PD/pareceres/.roda-agy-c$K.json"
MODELO_ESPERADO="Gemini 3.1 Pro"

if ! command -v agy >/dev/null 2>&1; then
  jq -cn '{revisor_ausente:"agy"}' | tee "$ESPELHO"
  exit 5
fi

# ── canário: nonce só no arquivo; instrução (com o PATH, sem o valor) no briefing ──
PROVA="$PD/pareceres/.prova-leitura-c$K.txt"
NONCE="PROVA-$(od -An -N3 -tx1 /dev/urandom | tr -d ' ')"
echo "Token de prova de leitura do ciclo $K: $NONCE" > "$PROVA"
if ! grep -q "prova_leitura" "$BRIEF"; then
  { echo; echo "## Prova de leitura (obrigatória)"; echo
    echo "Abra \`$PROVA\` e transcreva o token dele na primeira linha do parecer, no formato \`prova_leitura: <token>\`."
  } >> "$BRIEF"
fi

# ── probes de capacidade (help sai no STDERR) ────────────────────────────────
HELP=$(agy --help 2>&1 || true)
FLAGS=(); SINOS=()
grep -q -- "--log-file" <<<"$HELP" && FLAGS+=(--log-file "$LOG") \
  || SINOS+=("agy sem --log-file — fallback frágil pro cli-*.log por timestamp")
if grep -q -- "--agent" <<<"$HELP" && [ -f "$HOME/.gemini/config/agents/revisor-gsd/agent.md" ]; then
  FLAGS+=(--agent revisor-gsd)
else
  SINOS+=("agy sem revisor-gsd — rota legada sujeita a soft-deny")
fi
grep -q -- "--add-dir" <<<"$HELP" && FLAGS+=(--add-dir "$ROOT")

PROMPT="Read the file at $BRIEF in full and carry out the review request it contains. The repository under review is at $ROOT — verify claims against those files. Output only the resulting markdown review. Do not edit any files."

T0=$(date +%s)
timeout 600 agy "${FLAGS[@]}" --print-timeout 540s --model "$MODELO_ESPERADO (High)" \
  -p "$PROMPT" </dev/null 2> "$ERR" > "$OUT" || true

# ── vereditos mecânicos ──────────────────────────────────────────────────────
VAZIO=true; [ -s "$OUT" ] && VAZIO=false
FRESCO=false
if [ -s "$OUT" ]; then
  MT=$(stat -c %Y "$OUT" 2>/dev/null || echo 0); [ "$MT" -ge "$T0" ] && FRESCO=true
fi
EVID=""
[ -f "$LOG" ] && EVID=$(grep -E 'printmode.go:120|model_config_manager.go:311' "$LOG" 2>/dev/null \
  | grep -i "Propagating selected model" | head -1 | head -c 300 || true)
DEGRADADO=false
if [ -n "$EVID" ] && ! grep -qi "$MODELO_ESPERADO" <<<"$EVID"; then
  DEGRADADO=true   # fallback silencioso de modelo (3 ocorrências provadas) = revisor falho
fi
[ -z "$EVID" ] && SINOS+=("agy sem evidência de modelo no log — não invente")
PROVA_OK=ausente
[ -s "$OUT" ] && grep -q "prova_leitura: *$NONCE" "$OUT" && PROVA_OK=ok
[ "$PROVA_OK" = ausente ] && [ "$VAZIO" = false ] \
  && SINOS+=("agy sem prova de leitura (canário) — parecer ponderado como corroboração")

SJ=$(printf '%s\n' ${SINOS[@]+"${SINOS[@]}"} | jq -R . | jq -cs 'map(select(length>0))')
jq -cn --arg p "$OUT" --arg ev "$EVID" --arg pl "$PROVA_OK" --arg lg "$LOG" \
  --argjson d "$DEGRADADO" --argjson v "$VAZIO" --argjson f "$FRESCO" --argjson s "$SJ" \
  '{parecer:$p, evidencia:$ev, prova_leitura:$pl, degradado:$d, vazio:$v, fresco:$f, log:$lg, sinos:$s}' | tee "$ESPELHO"
gad_autoregistro "roda-agy.sh" 0 "c$K vazio=$VAZIO degradado=$DEGRADADO prova=$PROVA_OK" || true
if [ "$VAZIO" = true ] || [ "$DEGRADADO" = true ] || [ "$FRESCO" = false ]; then exit 6; fi
