#!/usr/bin/env bash
# discuss-finalize.sh — D4 [v3] da onda 2 (fork seletivo do gad-discuss-phase); documento único desde o 06-11.
#
# Fecho determinístico do /gad-discuss-phase sobre o documento único promovido
# (`<phase_dir>/<NN>-CONTEXT.md`, «Especificação da fase NN — <nome>»), em UMA chamada, na ordem fixa:
#   0. confere-documento.py "$CONTEXT_PATH" — o conferidor do documento único (mesmo diretório).
#                      Exit ≠ 0 ⇒ aborta ANTES de qualquer efeito (sem índice, sem state, sem
#                      commit, sem limpeza): `rejected_path` = o CONTEXT, `reason: guard`, exit 2.
#                      Motivo: uma edição entre a promoção e o commit não pode ir ao git sem
#                      conferência (caso 24.4).
#   1. decisions-index.py .planning — o índice segue gerado: lê `<decisions>` e o título novo
#   2. gad_run query state.record-session
#   3. gad_run query commit … --files CONTEXT STATE [DECISIONS-INDEX]   (respeita commit_docs:
#      `skipped:true` quando a política nega — NUNCA um `git commit` improvisado, R-1)
#   4. limpeza de $CKPT e $T — só no fim, após sucesso.
# Não há mais render de documento para humanos nem argumentos de guarda guardados: o conferidor
# só precisa do documento.
#
# NUNCA despacha hook: o despacho é do modelo, antes deste script (D4 × D1 × D6).
#
# Falha de commit ⇒ $T e $CKPT SOBREVIVEM (dá para corrigir e re-rodar) e o exit
# é 2. `skipped` por política é sucesso (limpa e sai 0).
#
# Uso: discuss-finalize.sh [--tmp DIR] [--message MSG] [--no-clean] [--root DIR]
# Saída: JSON em stdout
#   {"commit": bool, "hash": str|null, "skipped": bool, "rejected_path": str|null,
#    "reason": str, "files": [...], "gad_tools": "...", "cleaned": bool,
#    "msgs": [...], "msgs_truncadas": N, "log": "<caminho>"}
#   `msgs` = as ÚLTIMAS 60 linhas do log (teto de 20 KB no stdout, P18); o log inteiro
#   fica em $T/finalize.log e, quando a limpeza apaga $T, em <phase_dir>/.discuss-finalize.log.
#
# `rejected_path` só é preenchido pelo conferidor do passo 0 (o CONTEXT reprovado, não
# movido: o checkpoint sobrevive, corrija pelo writer e re-rode o fecho).
#
# `gad_tools` volta no JSON porque a limpeza apaga o $T/env.sh — os passos
# seguintes (`auto_advance`) precisam de um `gad_run` e não têm mais o env.sh.
set -u

T_DIR=".planning/.discuss-tmp"; MSG=""; CLEAN=1; ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --tmp) T_DIR="${2:-}"; shift 2 ;;
    --message) MSG="${2:-}"; shift 2 ;;
    --no-clean) CLEAN=0; shift ;;
    --root) ROOT="${2:-.}"; shift 2 ;;
    *) echo "[finalize] flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

[ -f "$T_DIR/env.sh" ] || { echo "[finalize] $T_DIR/env.sh ausente — rode o initialize" >&2; exit 2; }
# shellcheck disable=SC1090
. "$T_DIR/env.sh"
T="${T:-$T_DIR}"
: "${CKPT:?CKPT ausente no env.sh}"; : "${CONTEXT_PATH:?CONTEXT_PATH ausente no env.sh}"
: "${NOSSO:?NOSSO ausente no env.sh}"; : "${phase_dir:?phase_dir ausente no env.sh}"
: "${padded_phase:?padded_phase ausente no env.sh}"
[ -n "$MSG" ] || MSG="docs(${padded_phase}): capture phase context + decisions index"

LOG="$T/finalize.log"; : > "$LOG"
log() { printf '%s\n' "$*" >>"$LOG"; }

emite_json() {   # emite_json [FILES…] — o JSON de saída, a partir das variáveis de ambiente
  COMMITTED="${COMMITTED:-false}" SKIPPED="${SKIPPED:-false}" HASH="${HASH:-}" REASON="${REASON:-}" \
  CLEANED="${CLEANED:-false}" GAD_TOOLS="${GAD_TOOLS:-}" REJECTED="${REJECTED:-}" \
  python3 - "$LOG" "$@" <<'PY'
import json, os, sys
linhas = [l.rstrip("\n") for l in open(sys.argv[1], encoding="utf-8", errors="replace") if l.strip()]
msgs = linhas[-60:]
b = lambda k: os.environ.get(k) == "true"
print(json.dumps({
    "commit": b("COMMITTED"),
    "hash": os.environ.get("HASH") or None,
    "skipped": b("SKIPPED"),
    "rejected_path": os.environ.get("REJECTED") or None,
    "reason": os.environ.get("REASON") or None,
    "files": sys.argv[2:],
    "gad_tools": os.environ.get("GAD_TOOLS") or None,
    "cleaned": b("CLEANED"),
    "msgs": msgs,
    "msgs_truncadas": len(linhas) - len(msgs),
    "log": sys.argv[1],
}, ensure_ascii=False, indent=2))
PY
}

# 0. conferência do documento promovido — o conferidor do documento único, sem argumentos guardados
if ! python3 "$NOSSO/confere-documento.py" "$CONTEXT_PATH" >>"$LOG" 2>&1; then
  log "[finalize] o conferidor reprovou o documento ($CONTEXT_PATH) — nada commitado, \$T e \$CKPT preservados"
  REASON=guard REJECTED="$CONTEXT_PATH" emite_json
  exit 2
fi

# 1. índice de decisões
python3 "$NOSSO/decisions-index.py" .planning >>"$LOG" 2>&1 || log "[warn] decisions-index falhou"

# 2. estado
gad_run query state.record-session --stopped-at "Phase ${PHASE} context gathered" \
  --resume-file "$CONTEXT_PATH" >>"$LOG" 2>&1 || log "[warn] state.record-session falhou"

# 3. commit — o documento, o STATE e o índice
FILES=("$CONTEXT_PATH" .planning/STATE.md)
[ -f .planning/DECISIONS-INDEX.md ] && FILES+=(.planning/DECISIONS-INDEX.md)

# sem --raw: `query commit` devolve o JSON {committed, skipped?, hash, reason}
COMMIT_JSON=$(gad_run query commit "$MSG" --files "${FILES[@]}" 2>>"$LOG") || true
case "$COMMIT_JSON" in @file:*) COMMIT_JSON=$(cat "${COMMIT_JSON#@file:}") ;; esac
[ -n "$COMMIT_JSON" ] || COMMIT_JSON='{"committed":false,"reason":"sem_saida_do_commit"}'

_ler() { printf '%s' "$COMMIT_JSON" | python3 -c 'import json,sys
try: j=json.load(sys.stdin)
except Exception: j={}
v=j.get(sys.argv[1])
print("" if v is None else ("true" if v is True else ("false" if v is False else v)))' "$1"; }

COMMITTED=$(_ler committed); SKIPPED=$(_ler skipped); HASH=$(_ler hash); REASON=$(_ler reason)
[ "$SKIPPED" = true ] || SKIPPED=false

OK=false
if [ "$COMMITTED" = true ] || [ "$SKIPPED" = true ]; then OK=true; fi
[ "$SKIPPED" = true ] && log "[commit] skipped by commit_docs policy (${REASON:--})"

# 4. limpeza — SÓ no fim, após sucesso
CLEANED=false
if [ "$OK" = true ] && [ "$CLEAN" = 1 ]; then
  # o log sobrevive à limpeza, na pasta da fase
  mv -f "$LOG" "${phase_dir}/.discuss-finalize.log" 2>/dev/null && LOG="${phase_dir}/.discuss-finalize.log"
  rm -f "$CKPT"; rm -rf "$T"; CLEANED=true
elif [ "$OK" != true ]; then
  log "[finalize] commit falhou (${REASON:-sem reason}) — \$T e \$CKPT preservados"
fi

COMMITTED="$COMMITTED" SKIPPED="$SKIPPED" HASH="$HASH" REASON="$REASON" CLEANED="$CLEANED" \
emite_json "${FILES[@]}"

[ "$OK" = true ] || exit 2
exit 0
