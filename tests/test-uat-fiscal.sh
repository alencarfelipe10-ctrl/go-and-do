#!/usr/bin/env bash
# test-uat-fiscal.sh — bancada do leitor único do NN-UAT.md (auditoria F4 RLR).
#
# Régua: FM-01UAT (pass conduzido sem evidência) · FJ-01UAT (logic em pass sem linha
# `$ ` na evidência) · FJ-02UAT (pass conduzido sem 🔍) · FM-02UAT (o Summary é
# recalculado e escrito por ESTE script, o status é promovido, o Current Test some).
# `source: automated` fica fora dos três primeiros: não há condutor a cobrar.

set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
S="$AQUI/../skills/go-and-do/scripts/uat-fiscal.py"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-uatf-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }
eq()   { [ "$2" = "$3" ] && ok "$1" || erro "$1" "veio [$2], esperado [$3]"; }

PD="$TMP/fase"; mkdir -p "$PD/uat-evidencia"
U="$PD/99-UAT.md"
printf 'log do cenario 3\n' > "$PD/uat-evidencia/cenario-03.txt"
printf '$ pytest -q\n12 passed\n' > "$PD/uat-evidencia/cenario-04.txt"

cat > "$U" <<'MD'
---
status: testing
pre_uat: executed
---

## Current Test

number: 9
awaiting: user response

## Tests

### 1. Cenário conduzido sem evidência e sem sondagem
type: cli
result: pass
note: |
  rodei e funcionou.

### 2. Cenário sem evidência, mas com a exceção declarada
type: cli
result: pass
note: |
  ação sem saída: o comando não imprime nada.
  🔍 probe: rodei duas vezes seguidas.

### 3. Cenário logic com evidência sem nenhuma linha de comando
type: logic
result: pass
evidencia: uat-evidencia/cenario-03.txt
note: |
  🔍 probe: procurei o caso contrário e não achei.

### 4. Cenário logic com evidência que tem comando
type: logic
result: pass
evidencia: uat-evidencia/cenario-04.txt
note: |
  🔍 não se aplica: cenário de leitura, sem superfície adversarial.

### 5. Cenário automatizado (suíte) — fora dos três asserts
type: cli
result: pass
source: automated

## Summary

total: 33
passed: 20
pending: 13

## Gaps
MD

J=$(python3 "$S" "$U" "$PD")
lista() { printf '%s' "$J" | jq -r --arg k "$1" '.[$k]|join("|")' | sed 's/([^)]*)//g;s/ *|/|/g;s/ *$//'; }

echo "== leitura (modo seco)"
eq "conta os 5 cenários" "$(printf '%s' "$J" | jq -r .cenarios)" "5"
eq "placar: 5 pass" "$(printf '%s' "$J" | jq -r .placar.pass)" "5"
eq "FM-01UAT: só o cenário 1 (o 2 declarou «ação sem saída»; o 5 é automated)" \
   "$(lista pass_sem_evidencia)" "1"
eq "FJ-01UAT: só o logic cujo arquivo não tem linha '\$ '" \
   "$(lista logic_sem_comando)" "3"
eq "FJ-02UAT: só o cenário 1 (o 4 usou «🔍 não se aplica»; o 5 é automated)" \
   "$(lista pass_sem_sondagem)" "1"
printf '%s' "$J" | grep -q '"escrito": *\[\]' && ok "modo seco não escreve nada" \
  || erro "modo seco escreveu" "$J"
grep -q '^total: 33' "$U" && ok "modo seco preserva o Summary velho" || erro "Summary mexido no seco"

echo "== FM-02UAT: --escrever recalcula, promove e limpa"
python3 "$S" "$U" "$PD" --escrever >/dev/null
grep -q '^total: 5' "$U"  && ok "Summary recalculado do corpo (total 5, não 33)" || erro "total não recalculado" "$(sed -n '/## Summary/,/## Gaps/p' "$U")"
grep -q '^passed: 5' "$U" && ok "passed recalculado (5, não 20)" || erro "passed não recalculado"
grep -q '^pending: 0' "$U" && ok "pending recalculado (0, não 13)" || erro "pending não recalculado"
grep -q '^status: complete' "$U" && ok "status promovido a complete" || erro "status não promovido"
grep -q '## Current Test' "$U" && erro "bloco Current Test sobreviveu" || ok "bloco Current Test removido"

echo "== idempotência: segunda passada não escreve de novo"
antes=$(md5sum "$U" | cut -d' ' -f1)
J2=$(python3 "$S" "$U" "$PD" --escrever)
depois=$(md5sum "$U" | cut -d' ' -f1)
eq "arquivo inalterado na 2ª passada" "$antes" "$depois"
eq "…e o JSON declara que nada foi escrito" "$(printf '%s' "$J2" | jq -r '.escrito|length')" "0"

echo "== status NÃO é promovido com cenário em aberto"
sed -i 's/^status: complete/status: testing/' "$U"
sed -i '0,/^result: pass$/s//result: blocked/' "$U"
python3 "$S" "$U" "$PD" --escrever >/dev/null
grep -q '^status: testing' "$U" && ok "blocked no corpo trava a promoção" || erro "promoveu com blocked aberto"

echo
[ "$falhas" -eq 0 ] && echo "test-uat-fiscal: TUDO OK" || echo "test-uat-fiscal: $falhas falha(s)"
[ "$falhas" -eq 0 ]
