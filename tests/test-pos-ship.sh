#!/usr/bin/env bash
# test-pos-ship.sh — bancada do pos-ship.py (balde «observação pós-ship», v2.7.0).
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"; REPO="$(dirname -- "$AQUI")"
S="$REPO/skills/go-and-do/scripts/pos-ship.py"
falhas=0; ok=0
ok()  { ok=$((ok+1)); echo "PASS: $1"; }
bad() { falhas=$((falhas+1)); echo "FAIL: $1${2:+ — $2}"; }
eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1" "esperado [$3] obtido [$2]"; }
PAI=$(mktemp -d); trap 'rm -rf "$PAI"' EXIT

R="$PAI/proj"; PD="$R/.planning/phases/04-x"; mkdir -p "$PD" "$R/tests"
: > "$R/tests/test_leitura.py"
cenario() { # <n> <result> <pos_ship|-> <prova|-> <bloqueia|-> <verificavel|->
  printf '### %s. cenário %s\ntype: api\nexpected: |\n  algo\nresult: %s\n' "$1" "$1" "$2"
  [ "$3" != - ] && printf 'pos_ship: %s\n' "$3"
  [ "$4" != - ] && printf 'prova_mecanica: %s\n' "$4"
  [ "$5" != - ] && printf 'bloqueia_proxima: %s\n' "$5"
  [ "$6" != - ] && printf 'verificavel_em: %s\n' "$6"
  printf 'note: |\n  nota do cenário %s\n\n' "$1"
}
{ printf -- '---\nstatus: testing\npre_uat: executed\nupdated: 2020-01-01T00:00:00-03:00\n---\n\n## Tests\n\n'
  cenario 1 pass - - - -
  cenario 2 blocked candidato tests/test_leitura.py sim 'Fase 04.1 — API real'
  cenario 3 blocked candidato tests/test_leitura.py nao 'Fase 04.1 — volume do piloto'
  cenario 4 blocked candidato tests/nao_existe.py sim 'Fase 04.1'
  cenario 5 blocked candidato tests/test_leitura.py sim 'Fase 04.1'
  cenario 6 pass candidato tests/test_leitura.py sim 'Fase 04.1'
  cenario 7 blocked - - - -
  cenario 8 blocked candidato tests/test_leitura.py talvez 'Fase 04.1'
  printf '## Summary\n\ntotal: 8\n\n## Gaps\n'
} > "$PD/04-UAT.md"
printf '[{"cenario":2,"veredito":"confirmado","motivo":"90 passed, 2 skipped (pytest tests/test_leitura.py)"},{"cenario":3,"veredito":"confirmado","motivo":"volume do piloto observável só em produção"},{"cenario":4,"veredito":"confirmado"},{"cenario":5,"veredito":"recusado"},{"cenario":6,"veredito":"confirmado"},{"cenario":8,"veredito":"confirmado"}]' > "$PD/.pos-ship-vereditos.json"

echo "── move: só sai do balde 3 quem cumpre as 6 condições"
OUT=$(python3 "$S" move "$PD" 04 "$R"); RC=$?
eq "exit 0" "$RC" 0
eq "movidos 2,3" "$(jq -c .movidos <<<"$OUT")" "[2,3]"
eq "recusados 4,5,6,8" "$(jq -c '[.recusados[].cenario]' <<<"$OUT")" "[4,5,6,8]"
eq "4: prova inexistente" "$(jq -r '.recusados[0].motivo' <<<"$OUT")" "prova_mecanica não existe: tests/nao_existe.py"
eq "5: sem veredito confirmado" "$(jq -r '.recusados[1].motivo' <<<"$OUT")" "sem veredito confirmado do verificador"
eq "6: pass nunca move" "$(jq -r '.recusados[2].motivo' <<<"$OUT")" "result não é blocked/[pending]"
eq "8: bloqueia_proxima inválido" "$(jq -r '.recusados[3].motivo' <<<"$OUT")" "bloqueia_proxima ausente ou fora de sim|nao"
eq "UAT.md perdeu 2 cenários" "$(grep -c '^### ' "$PD/04-UAT.md")" 6
eq "UAT.md ainda tem 4 blocked (4,5,7,8)" "$(grep -c '^result: blocked' "$PD/04-UAT.md")" 4
eq "UAT.md preservou o rodapé" "$(grep -c '^## Gaps' "$PD/04-UAT.md")" 1
eq "UAT.md preservou o frontmatter" "$(sed -n 3p "$PD/04-UAT.md")" "pre_uat: executed"
eq "POS-SHIP.md tem 2 itens" "$(grep -c '^### 04-' "$PD/04-POS-SHIP.md")" 2
eq "POS-SHIP.md não carrega result:" "$(grep -c '^result:' "$PD/04-POS-SHIP.md")" 0
eq "POS-SHIP.md fora da régua ### N. do predicado" "$(grep -cE '^### [0-9]+\. ' "$PD/04-POS-SHIP.md")" 0

echo "── FM-F27INS-03UAT: a movimentação anexa à seção de lacunas e atualiza a data"
eq "Gaps ganhou 1 linha gerada (não duplicou a seção)" "$(grep -c '^## Gaps' "$PD/04-UAT.md")" 1
GAPS_LINHA=$(grep '^# pos-ship ' "$PD/04-UAT.md")
eq "linha gerada existe"           "$([ -n "$GAPS_LINHA" ] && echo sim || echo nao)" sim
casa() { echo "$1" | grep -qF "$2" && ok "…$2" || bad "…$2 ausente" "$1"; }
casa "$GAPS_LINHA" "movidos 2,3"
casa "$GAPS_LINHA" "recusados e bloqueando o ship: 4,5,8"
eq "updated: mudou (não ficou 2020-01-01)" "$(grep -c '^updated: 2020-01-01' "$PD/04-UAT.md")" 0
eq "texto antigo do condutor não foi apagado" "$(grep -c '^## Gaps' "$PD/04-UAT.md")" 1

echo "── FJ-F27INS-03UAT: o item movido leva a prova do cético, não o número do condutor"
CETICO_2=$(awk '/^### 04-2\./{f=1} f&&/^cetico:/{print;exit}' "$PD/04-POS-SHIP.md")
casa "$CETICO_2" "90 passed, 2 skipped"
CETICO_3=$(awk '/^### 04-3\./{f=1} f&&/^cetico:/{print;exit}' "$PD/04-POS-SHIP.md")
casa "$CETICO_3" "volume do piloto observável só em produção"

echo "── move é idempotente (2ª passada não duplica)"
OUT=$(python3 "$S" move "$PD" 04 "$R")
eq "nada a mover" "$(jq -c .movidos <<<"$OUT")" "[]"
eq "POS-SHIP.md segue com 2" "$(grep -c '^### 04-' "$PD/04-POS-SHIP.md")" 2
eq "Gaps segue com 1 linha só (2ª passada não duplica)" "$(grep -c '^# pos-ship ' "$PD/04-UAT.md")" 1

echo "── sem arquivo de vereditos: ninguém sai"
PD2="$R/.planning/phases/05-y"; mkdir -p "$PD2"
{ printf -- '---\nstatus: testing\n---\n\n'; cenario 1 blocked candidato tests/test_leitura.py sim 'Fase 6'; } > "$PD2/05-UAT.md"
OUT=$(python3 "$S" move "$PD2" 05 "$R")
eq "movidos vazio" "$(jq -c .movidos <<<"$OUT")" "[]"
eq "POS-SHIP.md não nasce" "$([ -f "$PD2/05-POS-SHIP.md" ] && echo sim || echo nao)" nao

echo "── lista"
OUT=$(python3 "$S" lista "$PD" 04)
eq "total 2" "$(jq -r .total <<<"$OUT")" 2
eq "bloqueiam_proxima 1" "$(jq -r .bloqueiam_proxima <<<"$OUT")" 1

echo "── gate: bloqueia a fase seguinte, isenta a nomeada e a própria"
OUT=$(python3 "$S" gate "$R" 5); eq "fase 5 → exit 1" "$?" 1
eq "1 pendente" "$(jq -r '.pendentes|length' <<<"$OUT")" 1
python3 "$S" gate "$R" 4.1 >/dev/null; eq "fase 4.1 (nomeada) → exit 0" "$?" 0
python3 "$S" gate "$R" 04.1 >/dev/null; eq "fase 04.1 == 4.1 → exit 0" "$?" 0
python3 "$S" gate "$R" 04 >/dev/null; eq "a própria fase → exit 0" "$?" 0
sed -i '0,/^observado_em:$/s//observado_em: 2026-09-25 — API real devolve id em 100% dos itens/' "$PD/04-POS-SHIP.md"
python3 "$S" gate "$R" 5 >/dev/null; eq "observado → fase 5 libera" "$?" 0

echo "── FM-F4RLR-07UAT: campo pos_ship indentado é malformação, não recusado silencioso"
PD3="$R/.planning/phases/06-z"; mkdir -p "$PD3"
{ printf -- '---\nstatus: testing\n---\n\n## Tests\n\n'
  printf '### 1. cenário 1\ntype: api\nresult: blocked\n  pos_ship: candidato\nprova_mecanica: tests/test_leitura.py\nbloqueia_proxima: sim\nverificavel_em: Fase 7\n\n'
  printf '## Summary\n'
} > "$PD3/06-UAT.md"
OUT=$(python3 "$S" move "$PD3" 06 "$R"); RC=$?
eq "indentado → exit 1" "$RC" 1
eq "indentado → malformados 1" "$(jq -r '.malformados|length' <<<"$OUT")" 1
eq "indentado → motivo" "$(jq -r '.malformados[0].motivo' <<<"$OUT")" "campo pos_ship indentado (coluna 0 exigida)"
eq "06-UAT.md intocado" "$(grep -c '^### ' "$PD3/06-UAT.md")" 1
eq "06-POS-SHIP.md não nasce" "$([ -f "$PD3/06-POS-SHIP.md" ] && echo sim || echo nao)" nao

echo "── FM-F4RLR-07UAT: sonda (prova_mecanica) de todo ausente é malformação"
PD4="$R/.planning/phases/07-w"; mkdir -p "$PD4"
{ printf -- '---\nstatus: testing\n---\n\n## Tests\n\n'
  printf '### 1. cenário 1\ntype: api\nresult: blocked\npos_ship: candidato\nbloqueia_proxima: sim\nverificavel_em: Fase 8\n\n'
  printf '## Summary\n'
} > "$PD4/07-UAT.md"
OUT=$(python3 "$S" move "$PD4" 07 "$R"); RC=$?
eq "sonda ausente → exit 1" "$RC" 1
eq "sonda ausente → motivo" "$(jq -r '.malformados[0].motivo' <<<"$OUT")" "sonda (prova_mecanica) ausente"

echo "── FJ-F4RLR-06UAT: conferir nunca escreve, mesmo veredito de malformação do move"
OUT=$(python3 "$S" conferir "$PD3" 06 "$R"); RC=$?
eq "conferir indentado → exit 1" "$RC" 1
eq "conferir não cria POS-SHIP" "$([ -f "$PD3/06-POS-SHIP.md" ] && echo sim || echo nao)" nao
OUT=$(python3 "$S" conferir "$PD" 04 "$R"); RC=$?
eq "conferir em fase já sem malformado → exit 0" "$RC" 0
eq "conferir malformados vazio" "$(jq -c .malformados <<<"$OUT")" "[]"
OUT=$(python3 "$S" --conferir "$PD" 04 "$R"); RC=$?
eq "alias --conferir (contrato literal do regras-comuns) funciona igual" "$RC" 0
BEFORE=$(md5sum "$PD/04-UAT.md")
python3 "$S" conferir "$PD" 04 "$R" >/dev/null
AFTER=$(md5sum "$PD/04-UAT.md")
eq "conferir não mexe no UAT.md" "$BEFORE" "$AFTER"

echo "── uso inválido"
python3 "$S" >/dev/null 2>&1; eq "exit 2" "$?" 2

echo "--------------------------------------------------"; echo "$ok ok / $falhas falhas"; [ "$falhas" -eq 0 ]
