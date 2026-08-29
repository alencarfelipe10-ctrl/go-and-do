#!/usr/bin/env bash
# test-pre-spec-migra.sh — suíte do pre-spec-migra.py (§0.5, rascunho do bloco).
# O rascunho da 24.3 é fixture versionada (insumo da onda 0.5), não a fixture final.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
M="$AQUI/../skills/go-and-do/scripts/pre-spec-migra.py"
F="$AQUI/fixtures/pre-spec"
RASCUNHO="$F/24.3-PRE-SPEC.rascunho.md"
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

# --- 1. Rascunho da 24.3 (gravado na onda 0) --------------------------------
if [ ! -f "$RASCUNHO" ]; then
  erro "rascunho da 24.3 presente" "não achei $RASCUNHO"
else
  saida=$(python3 - "$RASCUNHO" <<'PY'
import json, re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'<!-- gad:decisoes:begin v1 -->(.*?)<!-- gad:decisoes:end -->', s, re.S)
if not m:
    print("SEM-BLOCO"); raise SystemExit
try:
    d = json.loads(m.group(1))
except Exception as e:
    print(f"JSON-INVALIDO {e}"); raise SystemExit
kinds = {}
for c in d:
    kinds[c["kind"]] = kinds.get(c["kind"], 0) + 1
print("OK", len(d), kinds.get("decisao_dono", 0), kinds.get("fato_medido", 0))
PY
)
  set -- $saida
  if [ "${1:-}" != "OK" ]; then
    erro "rascunho da 24.3: bloco com JSON válido" "$saida"
  else
    ok "rascunho da 24.3: bloco presente e JSON válido ($2 candidatos)"
    if [ "${3:-0}" -ge 1 ]; then ok "rascunho da 24.3: ≥ 1 candidato decisao_dono ($3)"
    else erro "rascunho da 24.3: ≥ 1 decisao_dono" "obtido: ${3:-0}"; fi
    if [ "${4:-0}" -ge 1 ]; then ok "rascunho da 24.3: ≥ 1 candidato fato_medido ($4)"
    else erro "rascunho da 24.3: ≥ 1 fato_medido" "obtido: ${4:-0}"; fi
  fi
  if grep -q '9/9' "$RASCUNHO"; then
    ok "rascunho da 24.3: 'zero sobreposição 9/9' entrou como candidato"
  else
    erro "rascunho da 24.3: 9/9" "a medição 9/9 não aparece no rascunho"
  fi
  if grep -qEi '[a-z.]+@[a-z-]+\.[a-z]' "$RASCUNHO"; then
    erro "rascunho da 24.3: sem e-mail" "há e-mail no rascunho versionado"
  else
    ok "rascunho da 24.3: nenhum e-mail versionado"
  fi
fi

# --- 2. O migrador sobre uma fixture sintética ------------------------------
saida=$(python3 "$M" "$F/legado-PRE-SPEC.md" 2>/dev/null)
resumo=$(python3 "$M" "$F/legado-PRE-SPEC.md" 2>&1 >/dev/null)
if echo "$saida" | grep -q '<!-- gad:decisoes:begin v1 -->' && echo "$saida" | grep -q '<!-- gad:decisoes:end -->'; then
  ok "fixture legada: sai um bloco delimitado"
else
  erro "fixture legada: bloco delimitado" "$saida"
fi
conta=$(echo "$saida" | python3 -c '
import json,re,sys
s=sys.stdin.read()
d=json.loads(re.search(r"begin v1 -->(.*?)<!-- gad:decisoes:end", s, re.S).group(1))
dd=sum(1 for c in d if c["kind"]=="decisao_dono"); fm=sum(1 for c in d if c["kind"]=="fato_medido")
rev=sum(1 for c in d if "REVISAR" in json.dumps(c, ensure_ascii=False))
ids=[c["id"] for c in d]
print(dd, fm, rev, len(d), int(ids==sorted(ids)))')
set -- $conta
[ "${1:-0}" -ge 1 ] && ok "fixture legada: ≥ 1 decisao_dono ($1)" || erro "fixture legada: decisao_dono" "$conta"
[ "${2:-0}" -ge 1 ] && ok "fixture legada: ≥ 1 fato_medido ($2)" || erro "fixture legada: fato_medido" "$conta"
[ "${3:-0}" = "${4:-x}" ] && ok "fixture legada: todo candidato tem campo REVISAR (nunca decide sozinho)" \
                          || erro "fixture legada: REVISAR" "$3 de $4 candidatos"
[ "${5:-0}" = "1" ] && ok "fixture legada: ids PS-nn sequenciais" || erro "fixture legada: ids" "$conta"
echo "$resumo" | grep -q 'candidato' && ok "resumo por kind no stderr" || erro "resumo no stderr" "$resumo"

# --- 3. O rascunho NÃO passa no confere-pre-spec.sh (REVISAR não é enum) ----
C="$AQUI/../skills/go-and-do/scripts/confere-pre-spec.sh"
bash "$C" --so-bloco "$RASCUNHO" >/dev/null 2>&1
rc=$?
if [ "$rc" = "2" ]; then
  ok "rascunho reprova no confere-pre-spec.sh --so-bloco (exit 2) — precisa da revisão do dono"
else
  erro "rascunho deve reprovar" "exit=$rc (esperado 2)"
fi

echo "test-pre-spec-migra.sh: $falhas falha(s)"
[ "$falhas" -eq 0 ]
