#!/usr/bin/env bash
# test-confere-ciclo.sh — bancada do R8 (respostas dirigidas na contagem de brutos).
#
# Régua: nenhum texto que um revisor escreveu sai da contagem por decisão de formato.
# `sim`/`incerto` = bruto; Q ausente/duplicada/malformada = bruto `incerto`; `não` só
# sai com evidência real E veredito `supported_no` do gad-verificador.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/confere-ciclo.sh"
FIX="$AQUI/fixtures/intent"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-r8-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

CODEX="$FIX/24.3-parecer-codex-c1.md"
AGY="$FIX/24.3-parecer-agy-c1.md"
MAN="$FIX/perguntas-c1.json"
VER="$FIX/vereditos-dirigidos.json"

total()   { sed -n 's/^achados_estruturais_total: *//p' "$1" | head -1; }
resumo()  { sed -n 's/^dirigidas: *//p' "$1" | head -1; }
campo()   { resumo "$1" | jq -r ".$2"; }
rotulo()  { grep -E "^\| $2 \|" "$1" | grep -oE '\| [a-z_-]+ \|$' | tr -d '| ' ; }

echo "== compatibilidade — --tabela sem as flags novas segue funcionando"
"$SCRIPT" --tabela "$CODEX" > "$TMP/t0.txt" 2>/dev/null
[ "$(total "$TMP/t0.txt")" = 1 ] && ok "1 achado estrutural (sem dirigidas)" || erro "total" "$(total "$TMP/t0.txt")"
grep -q '| estrutural |$' "$TMP/t0.txt" && ok "linhas antigas ganham elicitacao=estrutural" || erro "coluna elicitacao ausente"

echo "== R8.1 — lane única, sem vereditos (contagem conservadora pré-rota)"
"$SCRIPT" --tabela --perguntas "$MAN" "$CODEX" > "$TMP/t1.txt" 2>/dev/null
# Q1 sim=bruto · Q2 não com evidência=nao_provisorio (conta) · Q3 não N/A=incerto · Q4 ausente
[ "$(campo "$TMP/t1.txt" brutas)" = 4 ] && ok "4 brutas dirigidas (sim + nao_provisorio + incerto + ausente)" \
  || erro "brutas" "$(resumo "$TMP/t1.txt")"
[ "$(total "$TMP/t1.txt")" = 5 ] && ok "achados_estruturais_total soma estruturais + dirigidas (1+4)" \
  || erro "total" "$(total "$TMP/t1.txt")"
grep -q 'Q1: sim' "$TMP/t1.txt" && grep -qE '^\| codex \| L[0-9]+ \|.*Q1: sim.*\| dirigida \|$' "$TMP/t1.txt" \
  && ok "\`Q1: sim — evidência\` vira 1 bruto com elicitacao=dirigida" || erro "linha da Q1" "$(grep Q1 "$TMP/t1.txt")"
grep -qE 'Q2.*\| nao_provisorio \|$' "$TMP/t1.txt" && ok "\`Q2: NÃO — evidência\` entra como nao_provisorio" \
  || erro "Q2 não virou nao_provisorio" "$(grep -i q2 "$TMP/t1.txt")"
grep -qE 'Q3: não — N/A.*\| dirigida \|$' "$TMP/t1.txt" && ok "\`Q3: não — N/A\` vira bruto incerto (dirigida)" \
  || erro "Q3 com evidência fraca não virou bruto" "$(grep -i q3 "$TMP/t1.txt")"
grep -q 'Q4 NÃO RESPONDIDA' "$TMP/t1.txt" && ok "Q do manifesto sem resposta vira bruto (dirigida-ausente)" \
  || erro "Q4 ausente não contou"

echo "== R8.2 — vereditos: só supported_no tira a Q da contagem"
"$SCRIPT" --tabela --perguntas "$MAN" --vereditos "$VER" "$CODEX" > "$TMP/t2.txt" 2>/dev/null
[ "$(campo "$TMP/t2.txt" brutas)" = 3 ] && ok "supported_no derruba a Q2: 4 → 3 brutas" \
  || erro "brutas com vereditos" "$(resumo "$TMP/t2.txt")"
[ "$(campo "$TMP/t2.txt" excluidas)" = 1 ] && ok "1 exclusão registrada (auditável)" || erro "excluidas"
grep -qE 'Q2.*\| dirigida-excluida \|$' "$TMP/t2.txt" && ok "Q2 fica na tabela como dirigida-excluida (destino, não sumiço)" \
  || erro "Q2 sumiu da tabela"

echo "== R8.3 — parser tolerante e duas lanes"
"$SCRIPT" --tabela --perguntas "$MAN" "$CODEX" "$AGY" > "$TMP/t3.txt" 2>/dev/null
# agy: Q1 incerto, Q2 yes, Q3 sim, Q4 sim = 4 brutas · codex = 4 → 8
[ "$(campo "$TMP/t3.txt" brutas)" = 8 ] && ok "\`sim\` em duas lanes = 1 bruto POR lane (8 no total)" \
  || erro "brutas 2 lanes" "$(resumo "$TMP/t3.txt")"
grep -qE '^\| agy \|.*Q2: yes.*\| dirigida \|$' "$TMP/t3.txt" && ok "parser aceita \`yes\` (case-insensitive)" \
  || erro "yes não reconhecido"
grep -qE '^\| codex \|.*\*\*Q2:\*\*.*\|' "$TMP/t3.txt" && ok "parser tolera \`**Q2:**\` e \`NÃO\` maiúsculo" \
  || erro "negrito/maiúscula não tolerados"

echo "== R8.4 — lane usable:false não tem suas Q contadas"
"$SCRIPT" --tabela --perguntas "$MAN" --status-dir "$FIX" "$CODEX" "$AGY" > "$TMP/t4.txt" 2>/dev/null
[ "$(campo "$TMP/t4.txt" brutas)" = 4 ] && ok "agy (usable:false) some da contagem dirigida: 8 → 4" \
  || erro "brutas com status" "$(resumo "$TMP/t4.txt")"
grep -qE '^\| agy \|.*\| dirigida' "$TMP/t4.txt" && erro "Q da lane inutilizável entrou na tabela" \
  || ok "nenhuma Q da lane inutilizável na tabela"
resumo "$TMP/t4.txt" | grep -q 'usable:false' && ok "o motivo aparece nos avisos (não é silêncio)" || erro "sem aviso"

echo "== R8.5 — Q duplicada vira incerto; Q fora do manifesto ainda conta"
cat > "$TMP/24.3-parecer-dup-c1.md" <<'EOF'
## Respostas dirigidas

- Q1: não — evidência longa e concreta em `a.py:1`
- Q1: sim — na verdade quebra
- Q9: sim — pergunta que o briefing não fez
EOF
"$SCRIPT" --tabela --perguntas "$MAN" --status-dir "$FIX" "$TMP/24.3-parecer-dup-c1.md" > "$TMP/t5.txt" 2>/dev/null
resumo "$TMP/t5.txt" | grep -q 'duplicada' && ok "duplicata é registrada nos avisos" || erro "duplicata silenciosa"
grep -qE 'Q1.*\| dirigida \|$' "$TMP/t5.txt" && ok "Q duplicada vira bruto (incerto), nunca zero" || erro "Q1 duplicada não contou"
resumo "$TMP/t5.txt" | grep -q 'fora do manifesto' && ok "Q fora do manifesto é contada e sinalizada" || erro "Q9 ignorada"
[ "$(campo "$TMP/t5.txt" brutas)" = 5 ] && ok "Q1(dup)+Q2,Q3,Q4(ausentes)+Q9 = 5 brutas" \
  || erro "brutas dup" "$(resumo "$TMP/t5.txt")"

echo "== R8.6 — parecer sem a seção estruturada: nada é dado por respondido"
printf 'Sim, a varredura está incompleta (respondido em prosa).\n' > "$TMP/24.3-parecer-prosa-c1.md"
"$SCRIPT" --tabela --perguntas "$MAN" "$TMP/24.3-parecer-prosa-c1.md" > "$TMP/t6.txt" 2>/dev/null
[ "$(campo "$TMP/t6.txt" brutas)" = 4 ] && ok "resposta só em prosa = 4 Q ausentes = 4 brutos" \
  || erro "brutas prosa" "$(resumo "$TMP/t6.txt")"

echo "== C7 — a tag [A-E] vai para coluna própria, extraída ANTES do corte de 100 chars"
# Régua: o corte em 100 caracteres não pode decidir se um achado tem categoria. Se o
# revisor escreve a explicação primeiro e a tag depois, ela ainda tem de chegar à tabela.
LONGA="explicação bem comprida escrita antes da tag, com mais de cem caracteres de texto corrido para empurrar a tag para longe do começo da linha"
cat > "$TMP/24.3-parecer-tarde-c1.md" <<EOF
# Parecer

### Achado 1 — $LONGA [C-processo] — fim
EOF
"$SCRIPT" --tabela "$TMP/24.3-parecer-tarde-c1.md" > "$TMP/t8.txt" 2>/dev/null
head -1 "$TMP/t8.txt" | grep -q '| categoria |' && ok "cabeçalho traz a coluna categoria" \
  || erro "cabeçalho sem a coluna categoria" "$(head -1 "$TMP/t8.txt")"
linha_t8=$(grep -E '^\| tarde \| L[0-9]+ \|' "$TMP/t8.txt")
printf '%s' "$linha_t8" | grep -qE '\| C-processo \| estrutural \|$' \
  && ok "tag depois do caractere 100 aparece na coluna categoria (sem colchetes)" \
  || erro "categoria não chegou à tabela" "$linha_t8"
printf '%s' "$linha_t8" | grep -q 'C-processo\] ' \
  && erro "o trecho não devia conter a tag (ela ficou além do corte)" "$linha_t8" \
  || ok "o trecho segue truncado — a categoria não depende mais dele"
[ "$(total "$TMP/t8.txt")" = 1 ] && ok "achados_estruturais_total intacto (registra-ciclo.sh o lê)" \
  || erro "total" "$(total "$TMP/t8.txt")"

echo "== C7 — o corte de 100 não parte caractere acentuado no meio"
# `cut -c` do coreutils corta BYTES: na F24.4 isso deixou um `\xc3` solto na tabela do
# planrev c2. O corte agora é `${var:0:100}` do bash, que conta caracteres.
{ echo "# Parecer"; echo
  printf '### Achado 1 — '; for i in $(seq 1 40); do printf 'autorização '; done; echo; } \
  > "$TMP/24.3-parecer-acento-c1.md"
"$SCRIPT" --tabela "$TMP/24.3-parecer-acento-c1.md" > "$TMP/t11.txt" 2>/dev/null
iconv -f utf-8 -t utf-8 "$TMP/t11.txt" >/dev/null 2>&1 \
  && ok "tabela sai UTF-8 válida (nenhum byte solto no corte)" \
  || erro "corte partiu caractere multibyte" "$(cat -v "$TMP/t11.txt" | grep 'L[0-9]' | head -1)"

echo "== C7 — achado sem tag nenhuma deixa a coluna categoria vazia (ausência de verdade)"
cat > "$TMP/24.3-parecer-nutag-c1.md" <<'EOF'
# Parecer

### Achado 1 — sem taxonomia alguma
EOF
"$SCRIPT" --tabela "$TMP/24.3-parecer-nutag-c1.md" > "$TMP/t9.txt" 2>/dev/null
grep -qE '^\| nutag \| L[0-9]+ \|[^|]*\|  \| estrutural \|$' "$TMP/t9.txt" \
  && ok "coluna categoria vazia quando a linha completa não tem tag" \
  || erro "coluna categoria não saiu vazia" "$(grep -E '^\| nutag' "$TMP/t9.txt")"

echo "== C7 — linha dirigida sai com a coluna categoria vazia (categoria nasce no verificador)"
"$SCRIPT" --tabela --perguntas "$MAN" "$CODEX" > "$TMP/t10.txt" 2>/dev/null
grep -qE '^\| codex \| L[0-9]+ \|.*\|  \| dirigida \|$' "$TMP/t10.txt" \
  && ok "linha dirigida tem categoria vazia" || erro "dirigida com categoria preenchida" "$(grep 'Q1: sim' "$TMP/t10.txt")"
grep -qE '^\| codex \| — \| Q4 NÃO RESPONDIDA \(manifesto\) \|  \| dirigida-ausente \|$' "$TMP/t10.txt" \
  && ok "linha dirigida-ausente também tem 5 colunas" \
  || erro "dirigida-ausente fora do formato de 5 colunas" "$(grep 'Q4' "$TMP/t10.txt")"

echo "== manifesto ilegível não zera a contagem (fail-closed)"
"$SCRIPT" --tabela --perguntas "$TMP/nao-existe.json" "$CODEX" > "$TMP/t7.txt" 2>/dev/null
[ "$(campo "$TMP/t7.txt" brutas)" -ge 1 ] && ok "manifesto ausente vira bruto, não zero" || erro "guarda cega"

echo
[ "$falhas" -eq 0 ] && echo "test-confere-ciclo: TUDO OK" || echo "test-confere-ciclo: $falhas falha(s)"
[ "$falhas" -eq 0 ]
