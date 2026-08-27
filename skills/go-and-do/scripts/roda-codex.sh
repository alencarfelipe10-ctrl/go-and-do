#!/usr/bin/env bash
# roda-codex.sh — lane Codex da revisão adversarial (decisão 2.5-D do gad-major).
#
# Absorve a disciplina operacional que vivia em prosa (fallback silencioso de modelo,
# effort xhigh estourando 10min, path fixo servindo parecer velho, bypass negado pelo
# classificador): monta e executa o `codex exec` com as garantias em exit code.
#
# Uso: roda-codex.sh <phase_dir> <NN> <ciclo> <briefing> [--out PATH]
#   parecer default: <phase_dir>/pareceres/NN-parecer-codex-c<k>.md
#
# Garantias mecânicas:
#   --model gpt-5.6-sol explícito (sem ele o run herda o default da config em silêncio)
#   -c model_reasoning_effort=low (xhigh não termina em 10min; low entrega em 1–3min)
#   -s read-only e SEM flag de bypass (o auto-deny é a garantia de leitura-apenas)
#   output com sufixo de ciclo (path fixo reusado já serviu parecer do ciclo 1 como c2)
#   frescor: mtime pós-disparo E md5 ≠ parecer do ciclo anterior
#   banner de evidência: head -8 do stderr (linha model: verbatim — a prova durável)
#   "at capacity"/"not supported" no stderr → 1 retry com gpt-5.6-terra
#
# JSON: {parecer, banner, modelo_efetivo, fresco, retry, vazio} + espelho em
# <phase_dir>/pareceres/.roda-codex-c<k>.json (insumo do registra-ciclo.sh).
# Exit: 0 = parecer válido · 5 = codex NÃO INSTALADO (revisor_ausente — quem chamou
# segue com o outro, disclosed; ambos ausentes já bloquearam no pre-despacho, PC-6) ·
# 6 = rodou e FALHOU (parecer vazio/estagnado — revisor falho neste ciclo) · 2 = uso.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; NN="${2:-}"; K="${3:-}"; BRIEF="${4:-}"; OUT=""
[ -n "$PD" ] && [ -n "$NN" ] && [ -n "$K" ] && [ -f "${BRIEF:-/nao-existe}" ] \
  || { echo "uso: roda-codex.sh <phase_dir> <NN> <ciclo> <briefing> [--out PATH]" >&2; exit 2; }
shift 4
while [ $# -gt 0 ]; do case "$1" in --out) OUT="${2:-}"; shift 2 ;; *) shift ;; esac; done

mkdir -p "$PD/pareceres"
: "${OUT:=$PD/pareceres/$NN-parecer-codex-c$K.md}"
ESPELHO="$PD/pareceres/.roda-codex-c$K.json"
ERR="$PD/pareceres/.codex-c$K.err"   # não vai no git (evidência durável = banner copiado)

if ! command -v codex >/dev/null 2>&1; then
  jq -cn '{revisor_ausente:"codex"}' | tee "$ESPELHO"
  exit 5
fi

roda() { # <modelo> → exit do codex
  local m="$1"
  timeout 600 codex exec -s read-only --model "$m" -c model_reasoning_effort=low \
    -o "$OUT" - < "$BRIEF" 2> "$ERR" || true
}

T0=$(date +%s)
MODELO=gpt-5.6-sol; RETRY=false
roda "$MODELO"
if grep -qiE "at capacity|not supported" "$ERR" 2>/dev/null; then
  # v2.1.9 (F24.3 c1): o retry sobrescrevia um parecer VÁLIDO do 1º modelo (o stderr
  # acusou "at capacity" e o parecer saiu mesmo assim). Parecer presente → sem retry;
  # parecer vazio → retry, com o stderr do 1º modelo preservado em `-sol.err`.
  if [ -s "$OUT" ]; then
    echo "aviso: stderr acusou capacidade/suporte mas o parecer do $MODELO saiu — sem retry (parecer preservado)" >&2
  else
    cp -f "$ERR" "${ERR%.err}-sol.err" 2>/dev/null || true
    RETRY=true; MODELO=gpt-5.6-terra
    roda "$MODELO"
  fi
fi

BANNER=$(head -8 "$ERR" 2>/dev/null | grep -E 'model:|provider:|workdir:' | tr '\n' ' ' | head -c 300)
VAZIO=true; [ -s "$OUT" ] && VAZIO=false
FRESCO=false
if [ -s "$OUT" ]; then
  MT=$(stat -c %Y "$OUT" 2>/dev/null || echo 0)
  [ "$MT" -ge "$T0" ] && FRESCO=true
  # K não-numérico ("review" no modo code-review) não tem ciclo anterior — o $((K-1))
  # abortava o script sob set -u ("review: variável não associada", F24.3 4.1)
  case "$K" in
    (*[!0-9]*|'') ;;
    (*) ANT="$PD/pareceres/$NN-parecer-codex-c$((K-1)).md"
        if [ -f "$ANT" ] && [ "$(md5sum < "$OUT")" = "$(md5sum < "$ANT")" ]; then
          FRESCO=false   # idêntico ao ciclo anterior = parecer reciclado, não novo
        fi ;;
  esac
fi

# aterramento (#3194 upstream): sem citação arquivo:linha = revisou o texto colado,
# não o repositório → não é falha (exit 0), é rebaixamento no consenso (sino).
CITA=false; gad_tem_citacao_fonte "$OUT" && CITA=true
SINOS=()
[ "$VAZIO" = false ] && [ "$CITA" = false ] \
  && SINOS+=("codex sem citação arquivo:linha ($GAD_CARIMBO_SEM_CITACAO) — parecer rebaixado a corroboração")
SJ=$(printf '%s\n' ${SINOS[@]+"${SINOS[@]}"} | jq -R . | jq -cs 'map(select(length>0))')
jq -cn --arg p "$OUT" --arg b "$BANNER" --arg m "$MODELO" \
  --argjson f "$FRESCO" --argjson r "$RETRY" --argjson v "$VAZIO" --argjson c "$CITA" --argjson s "$SJ" \
  '{parecer:$p, banner:$b, modelo_efetivo:$m, fresco:$f, retry:$r, vazio:$v, citacoes_fonte:$c, sinos:$s}' | tee "$ESPELHO"
gad_autoregistro "roda-codex.sh" 0 "c$K modelo=$MODELO fresco=$FRESCO vazio=$VAZIO citacoes=$CITA" || true
if [ "$VAZIO" = true ] || [ "$FRESCO" = false ]; then exit 6; fi
