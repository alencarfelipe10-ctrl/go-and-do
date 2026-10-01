#!/usr/bin/env bash
# discuss-render-guard.sh — D4 da onda 2 (fork seletivo do gad-discuss-phase).
#
# Um ponto de invocação só, no passo `write_context`: persiste os campos de texto
# livre que o modelo escreveu em $T, renderiza o CONTEXT, roda a guarda e o gate
# de cobertura. Nada aqui é julgamento — o julgamento é do modelo, sobre o JSON
# devolvido.
#
# Pode rodar 2× na mesma fase (a regra do pass cap: uma correção e uma re-rodada).
# Não move nem apaga arquivo: o `.rejected.md` da 2ª falha é do workflow.
#
# Uso: discuss-render-guard.sh [--tmp DIR] [--root DIR]
#   --tmp   diretório do checkpoint temporário (default .planning/.discuss-tmp),
#           de onde vem o env.sh com CKPT/CONTEXT_PATH/NOSSO/SPEC_PATH/REQ_IDS.
#   --root  raiz passada ao renderer e à guarda (default ".").
#
# Saída: JSON em stdout `{"guard_exit": N, "render_exit": N, "context_path": "...",
#         "msgs": [...], "msgs_truncadas": N, "log": "<caminho>"}`.
#   `msgs` são as ÚLTIMAS 60 linhas do log (a guarda e o gate escrevem por último, e é
#   por elas que o finish.md decide); `msgs_truncadas` conta as que ficaram de fora e
#   `log` ($T/render-guard.log) guarda tudo. Motivo: teto de 20 KB no stdout (P18).
# Exit = guard_exit (0 ok/WARN · 2 FAIL estrutural), e 2 também quando o render
# falha (falha fechada: sem CONTEXT não há prova).
set -u

T_DIR=".planning/.discuss-tmp"; ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --tmp) T_DIR="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    *) echo "[render-guard] flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

[ -f "$T_DIR/env.sh" ] || { echo "[render-guard] $T_DIR/env.sh ausente — rode o initialize" >&2; exit 2; }
# shellcheck disable=SC1090
. "$T_DIR/env.sh"
T="${T:-$T_DIR}"

: "${CKPT:?CKPT ausente no env.sh}"; : "${CONTEXT_PATH:?CONTEXT_PATH ausente no env.sh}"
: "${NOSSO:?NOSSO ausente no env.sh}"

LOG="$T/render-guard.log"; : > "$LOG"

# 1. campos de texto livre → checkpoint (só os não-vazios)
for f in specifics:specifics deferred:deferred_ideas discretion:discretion \
         folded:folded_todos reviewed:reviewed_todos; do
  [ -s "$T/${f%%:*}.txt" ] && python3 "$NOSSO/checkpoint-write.py" set "$CKPT" \
    --field "${f#*:}" --file "$T/${f%%:*}.txt" >>"$LOG" 2>&1
done
[ -s "$T/refs-more.txt" ] && python3 "$NOSSO/checkpoint-write.py" set "$CKPT" \
  --field canonical_refs --file "$T/refs-more.txt" --append >>"$LOG" 2>&1

# 2. render
python3 "$NOSSO/context-render.py" "$CKPT" --out "$CONTEXT_PATH" --root "$ROOT" >>"$LOG" 2>&1
RENDER=$?

# 3. guarda + 4. gate de cobertura (informativo)
GUARD=2
if [ "$RENDER" -eq 0 ]; then
  G_ARGS=(); [ -n "${SPEC_PATH:-}" ] && G_ARGS+=(--spec "$SPEC_PATH")
  [ -n "${REQ_IDS:-}" ] && G_ARGS+=(--reqs "$REQ_IDS")
  bash "$NOSSO/context-guard.sh" "$CONTEXT_PATH" "${G_ARGS[@]}" --root "$ROOT" >>"$LOG" 2>&1
  GUARD=$?
  { gad_run query check.decision-coverage-plan "${phase_dir:-}" "$CONTEXT_PATH" 2>&1 | head -12; } >>"$LOG"
else
  echo "[render-guard] context-render.py falhou (exit $RENDER) — falha fechada" >>"$LOG"
fi

GUARD="$GUARD" RENDER="$RENDER" CONTEXT_PATH="$CONTEXT_PATH" \
python3 - "$LOG" <<'PY'
import json, os, sys
linhas = [l.rstrip("\n") for l in open(sys.argv[1], encoding="utf-8", errors="replace") if l.strip()]
msgs = linhas[-60:]
print(json.dumps({
    "guard_exit": int(os.environ["GUARD"]),
    "render_exit": int(os.environ["RENDER"]),
    "context_path": os.environ["CONTEXT_PATH"],
    "msgs": msgs,
    "msgs_truncadas": len(linhas) - len(msgs),
    "log": sys.argv[1],
}, ensure_ascii=False, indent=2))
PY

exit "$GUARD"
