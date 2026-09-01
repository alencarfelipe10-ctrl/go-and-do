#!/usr/bin/env bash
# test-confere-reconciliacao.sh — bancada da reconciliação VEREDITO × APLICADO (A5a) e
# da trava de ordem releitura→correção na saída (A5b).
#
# Réguas:
#   · `confirmado` sem correção promovida é CONFIRMADO-NAO-APLICADO;
#   · `nao_sustentado` COM correção promovida é INVERSAO — o caso mais grave;
#   · id promovido sem linha de veredito é APLICADO-SEM-VEREDITO, salvo quando o id foge
#     do padrão estrito `c<N>-<NN>` (passada "b" e outras origens = fora-do-escopo, não conta);
#   · fase sem nenhum `.vereditos-c*.txt` é `n/a` e exit 0 — não se inventa falha;
#   · com --ordem, correção promovida DEPOIS da releitura do último ciclo é ORDEM-VIOLADA.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/confere-reconciliacao.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-a5-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

# fase <nome> → cria <TMP>/<nome>/.intent e ecoa o phase_dir
fase() { local d="$TMP/$1"; mkdir -p "$d/.intent"; echo "$d"; }

# vereditos <phase_dir> <C> <linha...>   (cada linha no formato "id|classe|veredito|cat")
vereditos() {
  local pd="$1" c="$2"; shift 2
  : > "$pd/.intent/.vereditos-c$c.txt"
  local l
  for l in "$@"; do
    printf '%s\n' "$l" | awk -F'|' '{printf "%s | %s | %s | %s\n",$1,$2,$3,$4}' \
      >> "$pd/.intent/.vereditos-c$c.txt"
  done
}

# aplicado <phase_dir> <C> <id,id,...>
aplicado() {
  local pd="$1" c="$2" ids="$3" json="" i
  for i in $(printf '%s' "$ids" | tr ',' ' '); do json="$json,\"$i\""; done
  json="${json#,}"
  printf '{"v":1,"ciclo":"%s","ids":[%s],"commit":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","caminhos":[]}\n' \
    "$c" "$json" > "$pd/.intent/.correcoes-c$c.aplicado"
}

echo "== as cinco classificações, uma a uma"

D=$(fase ok-confirmado); vereditos "$D" 1 "c1-01|novo|confirmado|A-produto"; aplicado "$D" 1 c1-01
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "reconciliacao: ok" && [ "$rc" = 0 ] \
  && ok "confirmado + aplicado → ok (exit 0)" || erro "confirmado aplicado não passou" "$saida"

D=$(fase ok-jacoberto); vereditos "$D" 1 "c1-01|novo|ja_coberto|D-documental"; aplicado "$D" 1 c1-01
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "reconciliacao: ok" && [ "$rc" = 0 ] \
  && ok "ja_coberto + aplicado → ok (a correção reforçou; é legítimo)" || erro "ja_coberto acusado" "$saida"

D=$(fase inversao); vereditos "$D" 4 "c4-01|novo|confirmado|A-produto" "c4-05|novo|nao_sustentado|D-documental"
aplicado "$D" 4 c4-01,c4-05
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "INVERSAO c4 c4-05" && [ "$rc" = 1 ] \
  && ok "nao_sustentado + aplicado → INVERSAO na saída + exit 1" || erro "inversão não acusada" "$saida"

D=$(fase cna); vereditos "$D" 1 "c1-04|novo|confirmado|C-instrumentacao"; aplicado "$D" 1 c1-01
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "CONFIRMADO-NAO-APLICADO c1 c1-04" && [ "$rc" = 1 ] \
  && ok "confirmado ausente do .aplicado → CONFIRMADO-NAO-APLICADO + exit 1" || erro "CNA não acusado" "$saida"

D=$(fase asv); vereditos "$D" 1 "c1-01|novo|confirmado|A-produto"; aplicado "$D" 1 c1-01,c1-07
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "APLICADO-SEM-VEREDITO c1 c1-07" && [ "$rc" = 1 ] \
  && ok "id promovido sem linha de veredito → APLICADO-SEM-VEREDITO + exit 1" || erro "ASV não acusado" "$saida"

echo "== id fora do padrão c<N>-<NN> não conta (passada \"b\" é documentada)"
D=$(fase fora); vereditos "$D" 1 "c1-01|novo|confirmado|A-produto"; aplicado "$D" 1 c1-01,c1b-01,c1b-02
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "fora-do-escopo=2" && [ "$rc" = 0 ] \
  && ok "c1b-01/c1b-02 → fora-do-escopo, exit 0" || erro "passada b contada como violação" "$saida"
# o padrão exige o espaço: a linha de resumo também traz a palavra ("APLICADO-SEM-VEREDITO=0")
printf '%s' "$saida" | grep -q "APLICADO-SEM-VEREDITO c" \
  && erro "id da passada b virou APLICADO-SEM-VEREDITO" "$saida" || ok "nenhuma linha de violação para c1b-*"

echo "== ciclo sem correção promovida"
D=$(fase sem-aplicado-limpo); vereditos "$D" 2 "c2-01|novo|nao_sustentado|D-documental"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
[ "$rc" = 0 ] && printf '%s' "$saida" | grep -q "reconciliacao: ok" \
  && ok "vereditos sem confirmado e sem .aplicado → legítimo (exit 0)" || erro "acusou ciclo legitimamente vazio" "$saida"

D=$(fase sem-aplicado-sujo); vereditos "$D" 2 "c2-01|novo|confirmado|A-produto" "c2-02|novo|confirmado|A-produto"
: > "$D/.intent/.correcoes-c2.vazio"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "ciclo marcado vazio" \
  && ok "marcador .vazio é nomeado na saída (não manda o leitor caçar o .aplicado)" || erro "marcador .vazio ignorado" "$saida"
[ "$(printf '%s' "$saida" | grep -c 'CONFIRMADO-NAO-APLICADO c')" = 2 ] && [ "$rc" = 1 ] \
  && ok "os dois confirmados viram CONFIRMADO-NAO-APLICADO + exit 1" || erro "confirmados sem correção passaram" "$saida"

echo "== terceiro campo ilegível: fail-closed dos DOIS lados"
D=$(fase ilegivel-aplicado); vereditos "$D" 1 "c1-01|novo|talvez|A-produto"; aplicado "$D" 1 c1-01
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "VEREDITO-ILEGIVEL c1 c1-01" && [ "$rc" = 1 ] \
  && ok "veredito ilegível + aplicado → VEREDITO-ILEGIVEL + exit 1" || erro "ilegível aplicado passou" "$saida"

D=$(fase ilegivel-nao-aplicado); vereditos "$D" 1 "c1-01|novo||A-produto"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "VEREDITO-ILEGIVEL c1 c1-01" && [ "$rc" = 1 ] \
  && ok "veredito vazio e NÃO aplicado também acusa (não é absorvido no contador ok)" \
  || erro "linha ilegível inflou o ok em silêncio" "$saida"

echo "== fase sem ciclos e usos inválidos"
D=$(fase vazia)
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "reconciliacao: n/a" && [ "$rc" = 0 ] \
  && ok "nenhum .vereditos-c*.txt → n/a + exit 0 (não se inventa falha)" || erro "inventou falha em fase sem ciclos" "$saida"

saida=$("$SCRIPT" "$TMP/nao-existe" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "phase_dir inexistente → exit 2 (uso inválido)" || erro "esperado exit 2, veio $rc" "$saida"
saida=$("$SCRIPT" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "sem argumento → exit 2" || erro "esperado exit 2, veio $rc" "$saida"
saida=$("$SCRIPT" "$D" --nao-existe 2>&1); rc=$?
[ "$rc" = 2 ] && ok "flag desconhecida → exit 2" || erro "esperado exit 2, veio $rc" "$saida"

echo "== recorte por ciclo"
D=$(fase recorte)
vereditos "$D" 1 "c1-01|novo|confirmado|A-produto"; aplicado "$D" 1 c1-01
vereditos "$D" 2 "c2-01|novo|nao_sustentado|D-documental"; aplicado "$D" 2 c2-01
saida=$("$SCRIPT" "$D" 1 2>&1); rc=$?
[ "$rc" = 0 ] && ok "ciclo 1 isolado → exit 0 (a inversão do c2 fica fora do recorte)" || erro "recorte não respeitado" "$saida"
saida=$("$SCRIPT" "$D" 2 2>&1); rc=$?
printf '%s' "$saida" | grep -q "INVERSAO c2" && [ "$rc" = 1 ] \
  && ok "ciclo 2 isolado → INVERSAO + exit 1" || erro "recorte do c2 falhou" "$saida"

echo "== A5b — a trava de ordem na saída"
# Fixtures com reconciliação LIMPA de propósito: assim o único motivo possível de exit 1
# é a ordem, e não a reconciliação vazando por baixo.
D=$(fase ordem-ok); vereditos "$D" 3 "c3-01|novo|confirmado|A-produto"; aplicado "$D" 3 c3-01
echo '{"ciclo":3,"commit":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","ok":true}' > "$D/.intent/.releitura-c3.json"
touch -d '2026-08-30 08:51:00' "$D/.intent/.correcoes-c3.aplicado"
touch -d '2026-08-30 08:52:30' "$D/.intent/.releitura-c3.json"
saida=$("$SCRIPT" "$D" --ordem 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^ordem: ok" && [ "$rc" = 0 ] \
  && ok "releitura depois da correção → ordem: ok (exit 0)" || erro "ordem correta acusada" "$saida"

D=$(fase ordem-violada); vereditos "$D" 4 "c4-01|novo|confirmado|A-produto"; aplicado "$D" 4 c4-01
echo '{"ciclo":4,"commit":"aaaabbbbccccddddeeeeffff0000111122223333","ok":true}' > "$D/.intent/.releitura-c4.json"
touch -d '2026-08-30 09:07:46' "$D/.intent/.releitura-c4.json"
touch -d '2026-08-30 09:12:44' "$D/.intent/.correcoes-c4.aplicado"
saida=$("$SCRIPT" "$D" --ordem 2>&1); rc=$?
printf '%s' "$saida" | grep -q "ORDEM-VIOLADA" && [ "$rc" = 1 ] \
  && ok "correção depois da releitura → ORDEM-VIOLADA + exit 1" || erro "ordem violada passou" "$saida"
printf '%s' "$saida" | grep -q "reconciliacao: ok" \
  && ok "e a reconciliação segue ok — o exit 1 veio só da ordem" || erro "reconciliação vazou na fixture de ordem" "$saida"
printf '%s' "$saida" | grep -q "corroboração:" \
  && ok "acusa também a divergência de commit entre releitura e .aplicado" || erro "corroboração de hash não saiu" "$saida"

# Fail-open que existia e foi fechado: fase COM ciclo 0 e SEM nenhum .vereditos-c*.txt
# (revisão adversarial pulada). Antes, o `reconciliacao: n/a` saía 0 sem sequer olhar a
# ordem — verde no caso que o gate existe para pegar.
D=$(fase ordem-sem-vereditos); aplicado "$D" 0 c0-01
echo '{"ciclo":0,"commit":"aaaabbbbccccddddeeeeffff0000111122223333","ok":true}' > "$D/.intent/.releitura-c0.json"
touch -d '2026-08-30 08:04:00' "$D/.intent/.releitura-c0.json"
touch -d '2026-08-30 08:09:00' "$D/.intent/.correcoes-c0.aplicado"
saida=$("$SCRIPT" "$D" --ordem 2>&1); rc=$?
printf '%s' "$saida" | grep -q "reconciliacao: n/a" && printf '%s' "$saida" | grep -q "ORDEM-VIOLADA" && [ "$rc" = 1 ] \
  && ok "sem vereditos, --ordem ainda avalia o ciclo 0 → ORDEM-VIOLADA + exit 1" \
  || erro "fase sem vereditos escapou da trava de ordem (fail-open)" "$saida"

D=$(fase ordem-na); vereditos "$D" 1 "c1-01|novo|confirmado|A-produto"; aplicado "$D" 1 c1-01
saida=$("$SCRIPT" "$D" --ordem 2>&1); rc=$?
printf '%s' "$saida" | grep -q "ordem: n/a" && [ "$rc" = 0 ] \
  && ok "sem .releitura-c1.json → ordem: n/a + exit 0 (é gate de outro)" || erro "ausência de releitura virou falha aqui" "$saida"

echo
[ "$falhas" -eq 0 ] && echo "test-confere-reconciliacao: TUDO OK" || echo "test-confere-reconciliacao: $falhas falha(s)"
[ "$falhas" -eq 0 ]
