#!/usr/bin/env bash
# discuss-finalize.sh — D4 [v3] da onda 2 (fork seletivo do gad-discuss-phase).
#
# Fecho determinístico do discuss, em UMA chamada, na ordem fixa:
#   0. context-guard.sh — com --spec/--reqs do env.sh (P09). Exit 2 da guarda ⇒
#                      aborta ANTES de qualquer efeito (sem índice, sem state, sem
#                      commit, sem limpeza): `rejected_path` = o CONTEXT, `reason: guard`.
#                      Motivo: o render-guard roda antes do for-humans e dos hooks; uma
#                      edição entre ele e o commit ficava sem conferência (caso 24.4).
#   1. fh-render.py  — SÓ se o FH .md existe (o .html precisa existir antes de
#                      montar o FILES do commit)
#   2. decisions-index.py .planning
#   3. gad_run query state.record-session
#   4. gad_run query commit … --files …   (respeita commit_docs: `skipped:true`
#      quando a política nega — NUNCA um `git commit` improvisado, R-1)
#   5. grava <phase_dir>/.discuss-guard-args (uma linha: --spec "…" --reqs "…") —
#      os argumentos da guarda sobrevivem ao env.sh, para a guarda pós-commit
#      (blocks/finish.md, reconcile_existing) nunca rodar nua.
#   6. limpeza de $CKPT e $T — só no fim, após sucesso.
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
# `rejected_path` só é preenchido pela guarda do passo 0 (o CONTEXT reprovado, não
# movido: o checkpoint sobrevive, corrija pelo writer e re-rode o render-guard).
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

# 0. guarda com a spec — mesmos argumentos do discuss-render-guard.sh
G_ARGS=(); [ -n "${SPEC_PATH:-}" ] && G_ARGS+=(--spec "$SPEC_PATH")
[ -n "${REQ_IDS:-}" ] && G_ARGS+=(--reqs "$REQ_IDS")
GUARD_LINE=$(printf -- '--spec "%s" --reqs "%s"' "${SPEC_PATH:-}" "${REQ_IDS:-}")
if ! bash "$NOSSO/context-guard.sh" "$CONTEXT_PATH" "${G_ARGS[@]}" --root "$ROOT" >>"$LOG" 2>&1; then
  log "[finalize] guarda reprovou o CONTEXT (${GUARD_LINE}) — nada commitado, \$T e \$CKPT preservados"
  REASON=guard REJECTED="$CONTEXT_PATH" emite_json
  exit 2
fi

# 1. for-humans — só se o .md existe
FH_MD="${phase_dir}/for-humans/${padded_phase}-CONTEXT-FH.md"
if [ -f "$FH_MD" ]; then
  python3 "$NOSSO/fh-render.py" "$FH_MD" >>"$LOG" 2>&1 || log "[warn] fh-render falhou (segue: o .html é opcional no FILES)"
else
  log "[finalize] sem FH — fh-render pulado"
fi

# 2. índice de decisões
python3 "$NOSSO/decisions-index.py" .planning >>"$LOG" 2>&1 || log "[warn] decisions-index falhou"

# 3. estado
gad_run query state.record-session --stopped-at "Phase ${PHASE} context gathered" \
  --resume-file "$CONTEXT_PATH" >>"$LOG" 2>&1 || log "[warn] state.record-session falhou"

# 4. commit — mesmos FILES de hoje (discuss-phase.md:298-299)
FILES=("$CONTEXT_PATH" .planning/STATE.md)
[ -f .planning/DECISIONS-INDEX.md ] && FILES+=(.planning/DECISIONS-INDEX.md)
for f in "${phase_dir}/for-humans/${padded_phase}-CONTEXT-FH.md" \
         "${phase_dir}/for-humans/${padded_phase}-CONTEXT-FH.html" \
         "${phase_dir}/${padded_phase}-DISCUSSION-LOG.md"; do
  [ -f "$f" ] && FILES+=("$f")
done

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

# 5. argumentos da guarda persistidos — antes da limpeza, só após sucesso
if [ "$OK" = true ]; then
  printf '%s\n' "$GUARD_LINE" > "${phase_dir}/.discuss-guard-args" \
    || log "[warn] não gravou ${phase_dir}/.discuss-guard-args"
fi

# 6. limpeza — SÓ no fim, após sucesso
CLEANED=false
if [ "$OK" = true ] && [ "$CLEAN" = 1 ]; then
  # o log sobrevive à limpeza ao lado do .discuss-guard-args
  mv -f "$LOG" "${phase_dir}/.discuss-finalize.log" 2>/dev/null && LOG="${phase_dir}/.discuss-finalize.log"
  rm -f "$CKPT"; rm -rf "$T"; CLEANED=true
elif [ "$OK" != true ]; then
  log "[finalize] commit falhou (${REASON:-sem reason}) — \$T e \$CKPT preservados"
fi

COMMITTED="$COMMITTED" SKIPPED="$SKIPPED" HASH="$HASH" REASON="$REASON" CLEANED="$CLEANED" \
emite_json "${FILES[@]}"

[ "$OK" = true ] || exit 2
exit 0
