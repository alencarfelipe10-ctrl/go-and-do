#!/usr/bin/env bash
# test-gera-intent-review.sh — bancada do FJ-F27INS-06INT (tarefa 59 b6).
#
# Fixture: os arquivos REAIS do verificador da F27 INS (grupo-inspired, copiados só-leitura em
# 26/09 para tests/fixtures/gera-intent-review/F27/) — vereditos.txt, achados-verificados.json,
# releitura.json, correcoes.py/.aplicado/.base.json, deferred-items.md — mais o SPEC/CONTEXT de
# antes do ciclo (pre/, commit 019c3ab1/0f35a704) e de depois (pos/, HEAD), truncados na linha
# 240 (os spans vão até a 223). `27-INTENT-REVIEW.real.md` é a tabela escrita à mão na fase.
#
# Régua: (a) a tabela gerada passa no fiscal (`confere-cardinalidade.sh --json` sem aviso);
# (b) o gerador NÃO maquia divergência dos arquivos do verificador (c1-04/c1-05 da F27:
# «confirmado» no JSON × «confirmado_irrelevante» no vereditos.txt) — exit 1 + seção;
# (c) proposição que não se deriva sai PENDENTE sem nenhuma das cinco chaves.
#   bash tests/test-gera-intent-review.sh      · exit 0 = verde
set -u
RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
S="$RAIZ/skills/go-and-do/scripts/gera-intent-review.sh"
CARD="$RAIZ/skills/go-and-do/scripts/confere-cardinalidade.sh"
FIX="$RAIZ/tests/fixtures/gera-intent-review/F27"
OK=0; FALHAS=0
ok()    { OK=$((OK+1)); printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }
casa()  { if printf '%s' "$2" | grep -qE -- "$3"; then ok "$1"; else falha "$1" "não casou /$3/ em: $(printf '%s' "$2" | head -c 300)"; fi; }

BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT
SLUG=".planning/phases/INS-27-executavel-windows"

monta() { # <dir-projeto> <com-git: 1|0>
  local proj="$1" pd="$1/$SLUG"
  mkdir -p "$pd"
  cp -r "$FIX/fase/." "$pd/"
  if [ "$2" = 1 ]; then
    cp "$FIX/pre/27-CONTEXT.md" "$FIX/pre/27-SPEC.md" "$pd/"
    git -C "$proj" init -q
    git -C "$proj" add -A
    git -C "$proj" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm pre
  fi
  cp "$FIX/pos/27-CONTEXT.md" "$FIX/pos/27-SPEC.md" "$pd/"
  if [ "$2" = 1 ]; then
    git -C "$proj" add -A
    git -C "$proj" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm pos
    # o commit da correção na fixture é o «pos» (na F27 real: f2f67b42)
    sed -i "s/f2f67b42550d7f9f4c6e46963c3efb79144affd4/$(git -C "$proj" rev-parse HEAD)/g" \
      "$pd/.gad/intent/c1/correcoes.aplicado"
  fi
}

# Monta um 27-INTENT-REVIEW.md só com o que o gerador imprimiu (contagens + tabela + dívidas),
# com os marcadores «preencher» trocados — é o que o coordenador colaria.
cola() { # <saida.md> <destino>
  { echo "---"; echo "intent_review: done"
    sed -n '/^```yaml$/,/^```$/p' "$1" | grep -E '^achados_'
    echo "---"; echo
    sed -n '/^## Tabela de achados$/,$p' "$1" | sed '/^## Divergências/,$d' | sed 's/«preencher»/ok/g'
  } > "$2"
}

echo "── F27 real com histórico git: contagens, colunas e proposições ──"
P1="$BASE/p1"; monta "$P1" 1; PD1="$P1/$SLUG"
J="$(bash "$S" "$PD1" 27 --json 2>/dev/null)"; RC=$?
eq "divergência c1-04/c1-05 no disco → exit 1" "$RC" "1"
eq "contagem confirmados = 4 (c1-07 entra)"  "$(jq -r '.contagem.confirmados' <<<"$J")" "4"
eq "contagem descartados = 0"                "$(jq -r '.contagem.descartados' <<<"$J")" "0"
eq "contagem dispensados = 3"                "$(jq -r '.contagem.dispensados' <<<"$J")" "3"
eq "7 linhas, na ordem dos vereditos"        "$(jq -r '[.linhas[].id]|join(",")' <<<"$J")" "c1-01,c1-02,c1-03,c1-04,c1-05,c1-06,c1-07"
eq "c1-07 (só no vereditos.txt) vem da releitura" "$(jq -r '.linhas[]|select(.id=="c1-07")|.alegacao|startswith("(releitura c1)")' <<<"$J")" "true"
eq "divergências = c1-04 e c1-05, tipo VEREDITO-DIVERGENTE" \
  "$(jq -r '[.divergencias[]|"\(.id):\(.tipo)"]|join(",")' <<<"$J")" "c1-04:VEREDITO-DIVERGENTE,c1-05:VEREDITO-DIVERGENTE"
eq "…e o veredito da célula é o do vereditos.txt (selado)" "$(jq -r '.linhas[]|select(.id=="c1-04")|.veredito' <<<"$J")" "confirmado_irrelevante"
eq "nenhuma proposição pendente" "$(jq -c '.pendentes' <<<"$J")" "[]"
for par in "c1-01:D-19:125" "c1-02:D-22:145" "c1-03:D-23:152" 'c1-07:"## Regression Surface":223'; do
  id=${par%%:*}; resto=${par#*:}; anc=${resto%:*}; lin=${resto##*:}
  p="$(jq -r --arg i "$id" '.linhas[]|select(.id==$i)|.proposicao' <<<"$J")"
  casa "$id: âncora $anc, linha $lin (bate com a tabela da fase)" "$p" "ancora: $anc, span_linhas: \\[$lin, $lin\\]"
done
casa "c1-01: texto verbatim do old" "$(jq -r '.linhas[]|select(.id=="c1-01")|.proposicao' <<<"$J")" \
  'texto: "senão o ship falha\. Ver 27-SPEC\.md R6'
eq "dívidas = os 3 confirmado_irrelevante" "$(jq -r '.dividas|join(",")' <<<"$J")" "c1-04,c1-05,c1-06"

OUT="$BASE/p1.md"; bash "$S" "$PD1" 27 > "$OUT" 2>"$BASE/p1.err"; RC=$?
eq "modo markdown → exit 1 também" "$RC" "1"
M="$(cat "$OUT")"
casa "cabeçalho com a coluna fontes (o fiscal lê o veredito na 4ª)" "$M" '^\| id \| alegação \| fontes \| veredito \| destino \| ação tomada \| proposição \|$'
casa "veredito seco na 4ª coluna" "$(grep '^| c1-01 |' "$OUT" | awk -F'|' '{gsub(/ /,"",$5); print $5}')" '^confirmado$'
casa "ponteiro com diretório (o ship.py:60 da F27 vinha sem)" "$(grep '^| c1-04 |' "$OUT")" 'clean-room/ship\.py:60'
casa "linha divergente anotada na «ação tomada»" "$(grep '^| c1-04 |' "$OUT")" '⚠ DIVERGÊNCIA: achados-verificados\.json diz `confirmado`'
casa "seção de divergências presente" "$M" '^## Divergências dos arquivos do verificador'
casa "…e o stderr nomeia o id" "$(cat "$BASE/p1.err")" 'VEREDITO-DIVERGENTE c1-04'
n5=0
while IFS= read -r l; do
  n=0; for k in artefato ancora span_linhas texto origem_texto; do
    printf '%s' "$l" | grep -qE "(^|[^A-Za-z0-9_])$k:" && n=$((n+1)); done
  [ "$n" = 5 ] && n5=$((n5+1))
done < <(grep -E '^\| c[0-9]+-[0-9]+ \|.*\| confirmado \|' "$OUT")
eq "os 4 confirmados trazem as 5 chaves da proposição (R7)" "$n5" "4"

echo "── a tabela colada passa no fiscal (confere-cardinalidade) ──"
cola "$OUT" "$PD1/27-INTENT-REVIEW.md"
C="$(bash "$CARD" "$PD1" 27 --json 2>/dev/null)"; RC=$?
eq "fiscal: exit 0" "$RC" "0"
eq "fiscal: bloqueantes []" "$(jq -c '.bloqueantes' <<<"$C")" "[]"
eq "fiscal: avisos []" "$(jq -c '.avisos' <<<"$C")" "[]"
eq "fiscal: tabela 4/0/3" "$(jq -r '.medido.tabela|"\(.confirmados)/\(.descartados)/\(.dispensados)/\(.outros)"' <<<"$C")" "4/0/3/0"
cp "$FIX/27-INTENT-REVIEW.real.md" "$PD1/27-INTENT-REVIEW.md"
C="$(bash "$CARD" "$PD1" 27 --json 2>/dev/null)"
casa "contraprova: a tabela escrita à mão na F27 é barrada" "$(jq -r '.bloqueantes|join("|")' <<<"$C")" 'cabeçalho diz 3, a tabela do mesmo arquivo tem 0'

echo "── sem histórico: proposição não derivável sai PENDENTE, sem chaves ──"
P2="$BASE/p2"; monta "$P2" 0; PD2="$P2/$SLUG"
J="$(bash "$S" "$PD2" 27 --json 2>/dev/null)"; RC=$?
eq "exit 1" "$RC" "1"
eq "pendentes = c1-01..c1-03 (o old já foi substituído no disco)" \
  "$(jq -r '[.pendentes[]|select(.tipo=="PROPOSICAO-PENDENTE")|.id]|join(",")' <<<"$J")" "c1-01,c1-02,c1-03"
p="$(jq -r '.linhas[]|select(.id=="c1-01")|.proposicao' <<<"$J")"
casa "célula começa com PENDENTE" "$p" '^PENDENTE — '
eq "…e não tem nenhuma das 5 chaves (não passaria falso no R7)" \
  "$(printf '%s' "$p" | grep -cE '(^|[^A-Za-z0-9_])(artefato|ancora|span_linhas|texto|origem_texto):')" "0"
casa "c1-07 ainda achado no disco (linha antiga preservada)" "$(jq -r '.linhas[]|select(.id=="c1-07")|.proposicao_linhas_de' <<<"$J")" '^disco$'

echo "── id só no achados-verificados.json não some ──"
A1="$PD1/.gad/intent/c1/runs/20260925T133612-2d0bd5/achados-verificados.json"
jq '. + [{"id":"c1-08","alegacao":"x","fontes":["agy"],"veredito":"confirmado","categoria":"C-risco","evidencia":"a/b.py:1"}]' "$A1" > "$BASE/a.json" && cp "$BASE/a.json" "$A1"
J="$(bash "$S" "$PD1" 27 --json 2>/dev/null)"
eq "c1-08 vira linha com veredito sem_veredito_no_disco" "$(jq -r '.linhas[]|select(.id=="c1-08")|.veredito' <<<"$J")" "sem_veredito_no_disco"
eq "…fora das 3 contagens" "$(jq -r '.contagem|"\(.confirmados)/\(.outros)"' <<<"$J")" "4/1"
casa "…e listado como divergência" "$(jq -r '[.divergencias[].tipo]|join(",")' <<<"$J")" 'SEM-VEREDITO-NO-DISCO'

echo "── arquivos concordes → exit 0 ──"
jq 'map(select(.id!="c1-08") | if .id=="c1-04" or .id=="c1-05" then .veredito="confirmado_irrelevante" else . end)' "$A1" > "$BASE/a.json" && cp "$BASE/a.json" "$A1"
bash "$S" "$PD1" 27 > "$BASE/p3.md" 2>&1; RC=$?
eq "sem divergência nem pendência → exit 0" "$RC" "0"
eq "…e sem a seção de divergências" "$(grep -c '^## Divergências' "$BASE/p3.md")" "0"

echo "── uso ──"
bash "$S" >/dev/null 2>&1; eq "sem argumentos → exit 2" "$?" "2"
mkdir -p "$BASE/vazia/.planning/phases/98-x"
bash "$S" "$BASE/vazia/.planning/phases/98-x" 98 >/dev/null 2>&1; eq "sem vereditos.txt → exit 2" "$?" "2"

echo
echo "── resumo: $OK ok / $FALHAS falhas ──"
[ "$FALHAS" -eq 0 ]
