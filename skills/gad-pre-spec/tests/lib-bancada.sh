#!/usr/bin/env bash
# lib-bancada.sh — helpers comuns dos test-*.sh da /gad-pre-spec.
# Não casa com o glob `test-*.sh` do roda.sh, então nunca roda sozinho.
#
# A bancada é um `.planning/` sintético no scratchpad — nenhum teste toca projeto real.
# Se CLAUDE_SCRATCHPAD_DIR não estiver no ambiente, cai num diretório temporário próprio.

AQUI="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$(CDPATH= cd -- "$AQUI/.." && pwd -P)"
FIX="$AQUI/fixtures"
CONFERE="$SKILL/../go-and-do/scripts/confere-pre-spec.sh"

falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ -n "${2:-}" ] && echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

# bancada <nome> → imprime a raiz de um projeto GSD sintético recém-criado
bancada() {
  local base="${CLAUDE_SCRATCHPAD_DIR:-${TMPDIR:-/tmp}}/gad-pre-spec-test"
  local raiz="$base/$1"
  rm -rf "$raiz"
  mkdir -p "$raiz/.planning/phases"
  cp "$FIX/ROADMAP.md" "$raiz/.planning/ROADMAP.md"
  cp "$FIX/REQUIREMENTS.md" "$raiz/.planning/REQUIREMENTS.md"
  printf '%s\n' "$raiz"
}

# molde <alvo> <NN> <nome> — materializa o templates/PRE-SPEC.md (mesma substituição do passo 4).
# Sem sed de propósito: nome de fase com `/` mataria o sed e `&` corromperia o título.
molde() {
  NN="$2" NOME="$3" DATA="2026-08-29" python3 -c 'import os,sys
t=open(sys.argv[1],encoding="utf-8").read()
for k in ("NN","NOME","DATA"): t=t.replace("{{%s}}"%k, os.environ[k])
open(sys.argv[2],"w",encoding="utf-8").write(t)' "$SKILL/templates/PRE-SPEC.md" "$1"
}

# jq_campo <json> <chave> — sem depender do jq (nem todo ambiente tem)
jq_campo() {
  printf '%s' "$1" | python3 -c '
import json,sys
d=json.loads(sys.stdin.read())
v=d.get(sys.argv[1])
print("" if v is None else (v if isinstance(v,str) else json.dumps(v)))
' "$2"
}

fim() {
  echo "$(basename "${BASH_SOURCE[1]}"): $falhas falha(s)"
  [ "$falhas" -eq 0 ]
}
