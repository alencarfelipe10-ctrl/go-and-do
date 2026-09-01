#!/usr/bin/env bash
# test-confere-rotas.sh — bancada do E5a (violação INVERSA da rota de verificação).
#
# Régua: o marcador `.verificador-cN.done` NÃO distingue as rotas (a rota inline também
# o grava). Quem declara a rota é o `.rota-verificacao-cN.json`. Despachar o filho com
# <=2 brutos num ciclo >=3 é o caro sem gatilho — exit 1, decisão do dono (28/08).
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/confere-rotas.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-e5a-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

# monta_ciclo <dir> <N> <brutos> <verificador:sim|nao> [mode] [brutos_pre_rota] [categoria]
# Emite a tabela no formato de 5 colunas do confere-ciclo.sh (C7): a categoria mora em
# coluna própria. `categoria` vazia = achado sem tag [A-E].
monta_ciclo() {
  local d="$1" n="$2" b="$3" v="$4" modo="${5:-}" pre="${6:-}" cat="${7-A-produto}"
  mkdir -p "$d"
  { echo "| lane | linha | achado (trecho) | categoria | elicitacao |"
    echo "|---|---|---|---|---|"
    local i=1
    while [ "$i" -le "$b" ]; do echo "| codex | L$i | achado $i | $cat | estrutural |"; i=$((i+1)); done
    echo
    echo "achados_estruturais_total: $b"; } > "$d/.tabela-c$n.txt"
  : > "$d/.done-c$n-codex"
  [ "$v" = sim ] && : > "$d/.verificador-c$n.done"
  [ -n "$modo" ] && printf '{"run_id":"r-%s","mode":"%s","brutos_pre_rota":%s}\n' \
    "$n" "$modo" "$pre" > "$d/.rota-verificacao-c$n.json"
  return 0
}

# monta_ciclo_legado — tabela no formato ANTIGO de 4 colunas (sem `categoria`), com a tag
# embutida no trecho. Existe para provar que o fallback por texto não virou guarda cega.
monta_ciclo_legado() {
  local d="$1" n="$2" b="$3" trecho="$4"
  mkdir -p "$d"
  { echo "| lane | linha | achado (trecho) | elicitacao |"
    echo "|---|---|---|---|"
    local i=1
    while [ "$i" -le "$b" ]; do echo "| codex | L$i | $trecho $i | estrutural |"; i=$((i+1)); done
    echo
    echo "achados_estruturais_total: $b"; } > "$d/.tabela-c$n.txt"
  : > "$d/.done-c$n-codex"
  : > "$d/.verificador-c$n.done"
  printf '{"run_id":"r","mode":"child","brutos_pre_rota":%s}\n' "$b" > "$d/.rota-verificacao-c$n.json"
  return 0
}

echo "== E5a — as três fixtures do plano"
D="$TMP/a"; monta_ciclo "$D" 3 2 sim child 2
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "VIOLACAO-INVERSA c3" && ok "c3 mode=child com 2 brutos pré-rota → VIOLACAO-INVERSA" \
  || erro "não acusou a violação inversa" "$saida"
[ "$rc" = 1 ] && ok "exit 1 (mesma dureza da violação direta)" || erro "esperado exit 1, veio $rc"

D="$TMP/b"; monta_ciclo "$D" 3 2 sim inline 2
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "rota ok c3" && [ "$rc" = 0 ] \
  && ok "c3 mode=inline com 2 brutos → ok (exit 0)" || erro "inline com 2 brutos falhou" "$saida"

D="$TMP/c"; monta_ciclo "$D" 1 2 sim child 2
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "rota ok c1" && [ "$rc" = 0 ] \
  && ok "c1 mode=child com 2 brutos → ok (a regra só vale de c3 em diante)" || erro "c1 acusado" "$saida"

echo "== E5a — child COM gatilho e rota ilegível"
D="$TMP/d"; monta_ciclo "$D" 3 5 sim child 5
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "rota ok c3" && [ "$rc" = 0 ] \
  && ok "c3 child com 5 brutos pré-rota → ok" || erro "child com gatilho acusado" "$saida"

D="$TMP/e"; monta_ciclo "$D" 3 5 sim
echo '{"run_id":"r"}' > "$D/.rota-verificacao-c3.json"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "SEM-ROTA c3" && [ "$rc" = 1 ] \
  && ok "rota sem mode/brutos_pre_rota → SEM-ROTA + exit 1 (fail-closed)" || erro "rota ilegível passou" "$saida"

echo "== E5a — arquivo de rota AUSENTE: aviso declarado, nunca silêncio"
D="$TMP/f"; monta_ciclo "$D" 3 5 sim
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "aviso: c3 sem .rota-verificacao-c3.json" \
  && ok "ausência do arquivo vira aviso explícito" || erro "ausência silenciosa" "$saida"
[ "$rc" = 0 ] && ok "por ora não derruba (o intent.md ainda não grava o arquivo)" \
  || erro "ausência já está derrubando" "$saida"

echo "== regressão — as checagens antigas continuam valendo"
D="$TMP/g"; mkdir -p "$D"; : > "$D/.done-c1-codex"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "SEM-TABELA c1" && [ "$rc" = 1 ] \
  && ok "SEM-TABELA continua exit 1" || erro "SEM-TABELA quebrou" "$saida"

D="$TMP/h"; monta_ciclo "$D" 2 4 nao inline 4
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "VIOLACAO c2" && [ "$rc" = 1 ] \
  && ok "VIOLACAO direta (>=3 brutos sem verificador) continua exit 1" || erro "violação direta quebrou" "$saida"

saida=$("$SCRIPT" "$TMP/vazio-nao-existe" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "diretório inexistente → exit 2 (uso inválido)" || erro "esperado 2, veio $rc"

D="$TMP/i"; mkdir -p "$D"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "SEM-INSUMO" && [ "$rc" = 1 ] \
  && ok "diretório sem nenhum ciclo → SEM-INSUMO (fail-closed)" || erro "guarda cega" "$saida"

echo "== R8 x E5 — linha dirigida não acende o aviso de categoria"
D="$TMP/j"; monta_ciclo "$D" 1 1 sim inline 1
sed -i 's/^achados_estruturais_total: 1/| codex | L9 | - Q1: sim — x.py:10 |  | dirigida |\n\nachados_estruturais_total: 2/' "$D/.tabela-c1.txt"
saida=$("$SCRIPT" "$D" 2>&1)
printf '%s' "$saida" | grep -q "sem categoria" && erro "linha dirigida acendeu o aviso de categoria" "$saida" \
  || ok "linha dirigida não conta como achado sem categoria"

echo "== C7 — os OUTROS dois rótulos R8 também não acendem o aviso"
# Desvio declarado do plano: dirigida-excluida e nao_provisorio saem da contagem pelo
# mesmo motivo dos outros dois (a categoria deles nasce no verificador). Medido na
# F24.4: os 27 "sem categoria" do ciclo 1 eram 26 dirigida-excluida + 1 nao_provisorio.
D="$TMP/k"; monta_ciclo "$D" 1 1 sim inline 1
sed -i 's/^achados_estruturais_total: 1/| codex | L9 | - Q1: não — a.py:1 |  | dirigida-excluida |\n| agy | L4 | - Q2: não — b.py:2 |  | nao_provisorio |\n| agy | L5 | - Q3 NÃO RESPONDIDA |  | dirigida-ausente |\n\nachados_estruturais_total: 2/' "$D/.tabela-c1.txt"
saida=$("$SCRIPT" "$D" 2>&1)
printf '%s' "$saida" | grep -q "sem categoria" && erro "dirigida-excluida/nao_provisorio acenderam o aviso" "$saida" \
  || ok "dirigida-excluida, nao_provisorio e dirigida-ausente ficam fora da contagem"

echo "== C7 — achado sem categoria: AVISO na saída e exit 0 (fail-up rio abaixo)"
# Régua central da decisão 1.7, até hoje sem asserção direta: ausência de tag [A-E] é
# aviso, jamais falha — quem resolve é o verificador com fail-up.
D="$TMP/l"; monta_ciclo "$D" 1 3 sim inline 3 ""
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "c1 tem 3 achado(s) sem categoria" \
  && ok "3 achados com a coluna categoria vazia → aviso com a contagem certa" \
  || erro "aviso ausente ou com contagem errada" "$saida"
[ "$rc" = 0 ] && ok "exit 0 preservado (a política 1.7 NÃO virou falha)" \
  || erro "achado sem categoria derrubou a rota — regressão de política" "$saida"

echo "== C7 — a coluna vence o texto do trecho (o truncamento deixa de decidir)"
D="$TMP/m"; monta_ciclo "$D" 1 2 sim inline 2 "C-instrumentacao"
saida=$("$SCRIPT" "$D" 2>&1)
printf '%s' "$saida" | grep -q "sem categoria" \
  && erro "coluna categoria preenchida ainda acendeu o aviso" "$saida" \
  || ok "categoria na coluna própria satisfaz a detecção, mesmo sem tag no trecho"

# O inverso: trecho COM a tag mas coluna vazia = ausência de verdade, tem de acender.
D="$TMP/n"; monta_ciclo "$D" 1 2 sim inline 2 ""
sed -i 's/achado 1/achado [A-produto] 1/' "$D/.tabela-c1.txt"
saida=$("$SCRIPT" "$D" 2>&1)
printf '%s' "$saida" | grep -q "c1 tem 2 achado(s) sem categoria" \
  && ok "tag solta no trecho não engana mais a detecção (a coluna é a fonte)" \
  || erro "tag no trecho ainda mascara a coluna vazia" "$saida"

echo "== C7 — tabela no formato antigo (4 colunas) continua sendo avaliada"
D="$TMP/o"; monta_ciclo_legado "$D" 1 3 "achado sem tag nenhuma"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "c1 tem 3 achado(s) sem categoria" && [ "$rc" = 0 ] \
  && ok "fallback por texto acusa os 3 (sem ele o aviso sumiria em silêncio)" \
  || erro "tabela legada virou guarda cega" "$saida"

D="$TMP/p"; monta_ciclo_legado "$D" 1 3 "achado [B-viabilidade] com tag"
saida=$("$SCRIPT" "$D" 2>&1)
printf '%s' "$saida" | grep -q "sem categoria" \
  && erro "tabela legada com tag no trecho acendeu o aviso" "$saida" \
  || ok "tabela legada com tag no trecho segue passando"

echo
[ "$falhas" -eq 0 ] && echo "test-confere-rotas: TUDO OK" || echo "test-confere-rotas: $falhas falha(s)"
[ "$falhas" -eq 0 ]
