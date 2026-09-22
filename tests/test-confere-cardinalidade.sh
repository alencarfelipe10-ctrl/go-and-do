#!/usr/bin/env bash
# test-confere-cardinalidade.sh — bancada do FM-F4RLR-09INT.
#
# Régua: cabeçalho × tabela de achados × arquivos de veredito × dívidas da seção contra o
# deferred-items.md. O script SÓ ACUSA (exit 1 com a lista); nunca reescreve.
#   bash tests/test-confere-cardinalidade.sh      · exit 0 = verde
set -u
RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
S="$RAIZ/skills/go-and-do/scripts/confere-cardinalidade.sh"
OK=0; FALHAS=0
ok()    { OK=$((OK+1)); printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }
casa()  { if printf '%s' "$2" | grep -qE "$3"; then ok "$1"; else falha "$1" "não casou /$3/ em: $(printf '%s' "$2" | head -c 300)"; fi; }

BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT
PD="$BASE/.planning/phases/97-bancada"; mkdir -p "$PD/.intent"

monta() { # <confirmados> <descartados> <dispensados>
  cat > "$PD/97-INTENT-REVIEW.md" <<EOF
---
intent_review: done
achados_confirmados: $1
achados_descartados: $2
achados_dispensados: $3
---

## Tabela de achados — 100% dos brutos

| id | alegação | fontes | veredito | destino |
|----|----------|--------|----------|---------|
| c1-01 | a | codex | confirmado (A-produto, alta) | correção |
| c1-02 | b | codex | confirmado (B-viabilidade) | correção |
| c1-03 | c | agy | nao_sustentado (D-documental) | registrado |
| c1-04 | d | agy | confirmado_irrelevante | dívida |

## Dívidas registradas

| id | alegação | evidência | dono | destino |
|----|----------|-----------|------|---------|
| c1-04 | d | ev | Amplify | plan-phase |
| I-01 | outra | ev | Amplify | dono |

## Reconciliação mecânica

| id | correção | commit | veredito |
|----|----------|--------|----------|
| c1-01 | c1-11 | abc1234 | aplicado |
EOF
}

echo "── cabeçalho × tabela ──"
monta 2 1 1
printf 'c1-01 | novo | confirmado | A-produto\nc1-02 | novo | confirmado | B\nc1-03 | novo | nao_sustentado | D\nc1-04 | novo | confirmado_irrelevante | C\n' \
  > "$PD/.intent/.vereditos-c1.txt"
printf -- '- c1-04 — dívida\n- I-01 — dívida da skill\n' > "$PD/deferred-items.md"
OUT="$(bash "$S" "$PD" 97 2>&1)"; RC=$?
eq "tudo batendo → exit 0" "$RC" "0"
casa "…e diz que bate"     "$OUT" 'cardinalidade: OK'

monta 12 1 1
OUT="$(bash "$S" "$PD" 97 2>&1)"; RC=$?
eq "cabeçalho 12 × tabela 2 → exit 1"  "$RC" "1"
casa "…nomeia os dois números"         "$OUT" 'CARDINALIDADE confirmados: cabeçalho diz 12, a tabela do mesmo arquivo tem 2'
casa "…e também o disco"               "$OUT" 'os arquivos de veredito têm 2'

echo "── a tabela da reconciliação NÃO entra na contagem ──"
# sem o recorte pela «## Tabela de achados» a linha `aplicado` viraria «veredito não
# reconhecido» e a contagem inflaria — foi o que aconteceu ao medir a F4 RLR real.
monta 2 1 1
OUT="$(bash "$S" "$PD" 97 2>&1)"
eq "nenhum VEREDITO-NAO-RECONHECIDO" "$(printf '%s' "$OUT" | grep -c 'VEREDITO-NAO-RECONHECIDO')" "0"

echo "── dívida da seção ausente do deferred-items.md ──"
printf -- '- c1-04 — dívida\n' > "$PD/deferred-items.md"
OUT="$(bash "$S" "$PD" 97 2>&1)"; RC=$?
eq "dívida sem registro → exit 1" "$RC" "1"
casa "…nomeia o id que falta"     "$OUT" 'DIVIDA-SEM-REGISTRO: I-01'

echo "── faixa c2-04..c2-07 conta como 4 ──"
monta 2 1 1
sed -i 's/^| c1-02 | b | codex | confirmado (B-viabilidade) | correção |$/| c2-04..c2-07 | b | codex | confirmado (D-documental) | correção |/' "$PD/97-INTENT-REVIEW.md"
OUT="$(bash "$S" "$PD" 97 --json 2>&1)"
eq "a faixa vale 4 (1 + 4 = 5 confirmados)" "$(printf '%s' "$OUT" | jq -r '.medido.tabela.confirmados')" "5"

echo "── sem INTENT-REVIEW não inventa número ──"
rm -f "$PD/97-INTENT-REVIEW.md"
OUT="$(bash "$S" "$PD" 97 2>&1)"; RC=$?
eq "sem artefato → exit 0" "$RC" "0"
casa "…e diz que não há o que conferir" "$OUT" 'nada a conferir'

echo
echo "── resumo: $OK ok / $FALHAS falhas ──"
[ "$FALHAS" -eq 0 ]
