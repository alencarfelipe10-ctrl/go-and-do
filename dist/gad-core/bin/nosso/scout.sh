#!/usr/bin/env bash
# scout.sh — o funil de exploração do código em script (fork gen5-patches, P11, 01/09/2026).
#
# Uso: bash scout.sh <fase> [--spec <SPEC.md>] [--out <arquivo>] [--goal-file <arquivo>] [--root <dir>]
#
# Faz, em ordem e sem julgamento: (1) entrada — objetivo da fase (goal.txt do spec-init/discuss-init
# ou `gad-tools roadmap get-phase`), arquivos citados na SPEC, termos-chave; (2) frescor — compara o
# commit gravado no graph.db com o HEAD e roda `code-review-graph update --skip-flows` se divergiu;
# (3) consulta ao grafo (scout.py, sqlite3 embutido, sem MCP); (4) reserva em grep sem grafo;
# (5) saída ≤ 8 KB em stdout e em --out. O funil que ele aplica está descrito em
# references/scout-codebase.md — o modelo não precisa ler aquela referência.
set -u
PHASE="${1:-}"; [ -n "$PHASE" ] || { echo "uso: scout.sh <fase> [--spec f] [--out f] [--goal-file f] [--root d]" >&2; exit 2; }
shift
SPEC=""; OUT=""; GOAL=""; ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --spec) SPEC="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --goal-file) GOAL="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    *) echo "scout.sh: argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done
cd "$ROOT" || exit 2
AQUI="$(dirname "$(readlink -f "$0")")"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# (1) objetivo: arquivo dado > goal.txt dos init > roadmap get-phase
if [ -z "$GOAL" ]; then
  for c in .planning/.spec-tmp/goal.txt .planning/.discuss-tmp/goal.txt; do
    [ -s "$c" ] && { GOAL="$c"; break; }
  done
fi
if [ -z "$GOAL" ]; then
  GAD_TOOLS="${GAD_TOOLS:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/gad-tools.cjs}"
  if [ -n "$GAD_TOOLS" ] && [ -f "$GAD_TOOLS" ]; then
    node "$GAD_TOOLS" roadmap get-phase "$PHASE" 2>/dev/null \
      | python3 -c 'import json,sys
try: j=json.load(sys.stdin)
except Exception: j={}
print((j.get("goal") or "")+"\n"+" ".join(j.get("success_criteria") or []))' > "$TMP/goal.txt" 2>/dev/null
  fi
  GOAL="$TMP/goal.txt"; [ -f "$GOAL" ] || : > "$GOAL"
fi
[ -s "$GOAL" ] || echo "scout.sh: objetivo da fase $PHASE vazio — só a SPEC (se houver) alimenta os termos" >&2

# (2) frescor do grafo
DB=".code-review-graph/graph.db"; AVISO=""
if [ -f "$DB" ]; then
  GRAVADO="$(python3 -c 'import sqlite3,sys
try: print(sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True).execute("select value from metadata where key=\"git_head_sha\"").fetchone()[0])
except Exception: print("")' "$DB" 2>/dev/null)"
  HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
  if [ -n "$HEAD" ] && [ "$GRAVADO" != "$HEAD" ]; then
    CRG="${SCOUT_CRG:-code-review-graph}"   # SCOUT_CRG: só para o teste simular CLI ausente/falsa
    if command -v "$CRG" >/dev/null 2>&1; then
      if timeout 120 "$CRG" update --skip-flows >/dev/null 2>&1; then
        AVISO="update do grafo executado (gravado ${GRAVADO:0:8}, HEAD ${HEAD:0:8})"
      else
        AVISO="grafo desatualizado (${GRAVADO:0:8} ≠ HEAD ${HEAD:0:8}); update falhou/expirou — usando o grafo velho"
      fi
    else
      AVISO="grafo desatualizado (${GRAVADO:0:8} ≠ HEAD ${HEAD:0:8}); CLI code-review-graph ausente — usando o grafo velho"
    fi
    echo "scout.sh: $AVISO" >&2
  fi
fi

# (3)-(5) consulta e saída
ARGS=(--root . --goal-file "$GOAL" --graph "$DB")
[ -n "$SPEC" ] && ARGS+=(--spec "$SPEC")
[ -n "$AVISO" ] && ARGS+=(--origem "$AVISO")
python3 "$AQUI/scout.py" "${ARGS[@]}" > "$TMP/scout.md" || { echo "scout.sh: scout.py falhou" >&2; exit 1; }
[ -n "$OUT" ] && cp "$TMP/scout.md" "$OUT"
cat "$TMP/scout.md"
