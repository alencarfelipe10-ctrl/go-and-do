#!/usr/bin/env bash
# test-review-maior.sh — bancada do lib/review-maior.py (FM-F27INS-02GAT, t59/L6, 26/09).
#
# Cobre o bug real (run-log seq 381, F27-INS): o leitor escolhia o `NN-REVIEW-FIX*` mais
# recente por TIPO antes de olhar a iteração, e por isso lia o relatório do conserto da
# rodada 4 em vez da re-revisão real da rodada 5 (que deu `clean`). A regra correta: o N de
# iteração mais alto manda; só no empate de N o REVIEW-FIX desempata (ele é escrito depois
# do REVIEW da MESMA rodada).
#   bash tests/test-review-maior.sh      · exit 0 = verde
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
S="$AQUI/../skills/go-and-do/scripts/lib/review-maior.py"
OK=0; FALHAS=0
ok()    { OK=$((OK+1)); printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }
campo() { # <chave, com "." para aninhado> <json>
  python3 -c "
import json, sys
d = json.loads(sys.argv[2])
for k in sys.argv[1].split('.'):
    d = d.get(k, '') if isinstance(d, dict) else ''
print(d)
" "$1" "$2" 2>/dev/null
}

BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT

echo "── caso real F27-INS (seq 381): FIX.iter4 × REVIEW.iter5 (clean) — REVIEW.iter5 vence ──"
PD="$BASE/f27"; mkdir -p "$PD"
cat > "$PD/27-REVIEW.md" <<'EOF'
---
status: issues_found
critical: 2
---
EOF
cat > "$PD/27-REVIEW-FIX.iter4.md" <<'EOF'
---
iteration: 4
status: all_fixed
fixed: 1
skipped: 2
---
## Deixados ABERTOS e declarados
- **WR-10** — fora deste conserto.
- **WR-11** — fora deste conserto.
EOF
cat > "$PD/27-REVIEW.iter5.md" <<'EOF'
---
status: clean
critical: 0
warning: 0
---
Tudo fechado.
EOF
J="$(python3 "$S" "$PD" 27)"
eq "escolhe a re-revisão de N maior, não o conserto de N menor" "$(campo arquivo "$J")" "27-REVIEW.iter5.md"
eq "status vem do frontmatter da re-revisão"                    "$(campo status "$J")" "clean"
eq "WR-10/WR-11 não aparecem como abertos (não é busca de texto no FIX)" \
   "$(campo abertos "$J")" "[]"
eq "o conserto superado não desaparece — vai para ultima_correcao" \
   "$(campo 'ultima_correcao.arquivo' "$J")" "27-REVIEW-FIX.iter4.md"
eq "…com o skipped que o all_fixed_com_skipped precisa"          "$(campo 'ultima_correcao.skipped' "$J")" "2"

echo "── empate de N: REVIEW.iterN e REVIEW-FIX.iterN da MESMA rodada — o FIX desempata ──"
PD="$BASE/empate"; mkdir -p "$PD"
printf -- '---\nstatus: issues_found\ncritical: 1\n---\n' > "$PD/30-REVIEW.iter2.md"
printf -- '---\niteration: 2\nstatus: all_fixed\nskipped: 0\n---\n' > "$PD/30-REVIEW-FIX.iter2.md"
J="$(python3 "$S" "$PD" 30)"
eq "N igual → REVIEW-FIX vence (escrito depois do achado da mesma rodada)" \
   "$(campo arquivo "$J")" "30-REVIEW-FIX.iter2.md"

echo "── conserto sem re-review ainda (loop fechou na correção, N do FIX é o maior) ──"
PD="$BASE/semrevisao"; mkdir -p "$PD"
printf -- '---\nstatus: issues_found\ncritical: 1\n---\n' > "$PD/40-REVIEW.md"
printf -- '---\niteration: 3\nstatus: all_fixed\nskipped: 1\n---\n' > "$PD/40-REVIEW-FIX.iter3.md"
J="$(python3 "$S" "$PD" 40)"
eq "sem re-revisão mais nova → o REVIEW-FIX é o próprio arquivo" "$(campo arquivo "$J")" "40-REVIEW-FIX.iter3.md"
eq "…e não sobra ultima_correcao (ele já É o escolhido)"         "$(campo 'ultima_correcao.arquivo' "$J")" ""

echo "── só REVIEW.md (rodada 1, sem conserto ainda) ──"
PD="$BASE/so-review"; mkdir -p "$PD"
printf -- '---\nstatus: issues_found\ncritical: 3\n---\n' > "$PD/50-REVIEW.md"
J="$(python3 "$S" "$PD" 50)"
eq "escolhe o único arquivo"      "$(campo arquivo "$J")" "50-REVIEW.md"
eq "iteracao 1 (rodada 1)"        "$(campo iteracao "$J")" "1"
eq "sem ultima_correcao (não há FIX)" "$(campo 'ultima_correcao.arquivo' "$J")" ""

echo "── formato não reconhecido: sem 'status:' no cabeçalho ──"
PD="$BASE/semformato"; mkdir -p "$PD"
printf 'sem cabecalho nenhum\n' > "$PD/60-REVIEW.md"
J="$(python3 "$S" "$PD" 60)"
eq "formato_nao_reconhecido: true" "$(campo formato_nao_reconhecido "$J")" "True"

echo "── nada no disco: sem erro, sem inventar zero ──"
PD="$BASE/vazio"; mkdir -p "$PD"
J="$(python3 "$S" "$PD" 70)"
eq "arquivo: None"  "$(campo arquivo "$J")" "None"
eq "abertos: []"    "$(campo abertos "$J")" "[]"

echo
echo "── resumo: $OK ok / $FALHAS falhas ──"
[ "$FALHAS" -eq 0 ]
