#!/usr/bin/env bash
# test-registra-ciclo.sh — o apêndice do NN-REVIEWS tem de contar os MESMOS brutos que a
# tabela do coordenador (v2.2.0): o `confere-ciclo.sh --tabela` do registra-ciclo passa
# `--perguntas`/`--status-dir`/`--vereditos` quando os arquivos da intenção existem, e
# NÃO os passa no ciclo da convergência (numeração colide entre as duas famílias).
#
# FM-F27INS-01CONV: sem dirigida a somar (FLAGS_TAB vazio — convergência, ou intenção
# sem manifesto), o apêndice não confia mais em `achados_estruturais_total` — conta SÓ
# cabeçalhos «### Achado N» (N>=1) direto dos pareceres (PROPRIA abaixo). A fixture do
# agy tem uma linha "- Q4: sim — a correção **c0-01** trocou..." que o fallback por
# severidade/ref do confere-ciclo.sh (sem heading numerado) casa como achado — o mesmo
# falso positivo medido em 2 ciclos reais da F27-INS (3 brutos onde eram 1 e 0). Por
# desenho, SEM (a tabela antiga) e PROPRIA (a contagem nova) discordam nesta fixture.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/registra-ciclo.sh"
CONFERE="$AQUI/../skills/go-and-do/scripts/confere-ciclo.sh"
FIX="$AQUI/fixtures/intent"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-regciclo-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

# o número que VALE é o primeiro rótulo que aparecer: «brutos por cabeçalho ...: N»
# (FM-F27INS-01CONV, quando a contagem própria diverge da tabela antiga) tem prioridade
# sobre «brutos na tabela do ciclo: N» (formato de sempre, os dois números coincidem).
brutos_do_apendice() {
  local v
  v=$(sed -n 's/^- brutos por cabeçalho `### Achado N`: \([0-9]*\).*/\1/p' "$1" | tail -1)
  [ -n "$v" ] && { printf '%s' "$v"; return; }
  sed -n 's/^- brutos na tabela do ciclo: \([0-9]*\).*/\1/p' "$1" | tail -1
}
total_tabela()       { sed -n 's/^achados_estruturais_total: *//p' "$1" | head -1; }

monta() { # <phase_dir> <familia: intencao|convergencia>
  local PD="$1" fam="$2" pref
  mkdir -p "$PD/pareceres" "$PD/.intent/runs/c1/run-x"
  [ "$fam" = intencao ] && pref="24.3-parecer" || pref="24.3-planrev-parecer"
  cp "$FIX/24.3-parecer-codex-c1.md" "$PD/pareceres/$pref-codex-c1.md"
  cp "$FIX/24.3-parecer-agy-c1.md"   "$PD/pareceres/$pref-agy-c1.md"
  cp "$FIX/perguntas-c1.json"        "$PD/.intent/.perguntas-c1.json"
  cp "$FIX/.status-c1-codex.json"    "$PD/.intent/.status-c1-codex.json"
  cp "$FIX/.status-c1-agy.json"      "$PD/.intent/.status-c1-agy.json"
  cp "$FIX/vereditos-dirigidos.json" "$PD/.intent/runs/c1/run-x/vereditos-dirigidos.json"
  printf 'run-x\n' > "$PD/.intent/.run-atual-c1"
}

# referência: a tabela COM as flags (o que o coordenador vê) e SEM elas (o antigo)
"$CONFERE" --tabela --perguntas "$FIX/perguntas-c1.json" --status-dir "$FIX" \
  --vereditos "$FIX/vereditos-dirigidos.json" \
  "$FIX/24.3-parecer-codex-c1.md" "$FIX/24.3-parecer-agy-c1.md" > "$TMP/ref-com.txt" 2>/dev/null
"$CONFERE" --tabela "$FIX/24.3-parecer-codex-c1.md" "$FIX/24.3-parecer-agy-c1.md" \
  > "$TMP/ref-sem.txt" 2>/dev/null
COM=$(total_tabela "$TMP/ref-com.txt"); SEM=$(total_tabela "$TMP/ref-sem.txt")
[ -n "$COM" ] && [ -n "$SEM" ] && [ "$COM" != "$SEM" ] \
  && ok "a fixture discrimina as rotas (com flags=$COM · sem flags=$SEM)" \
  || erro "fixture não discrimina: com=$COM sem=$SEM (o teste não provaria nada)"

# PROPRIA: a MESMA régua do registra-ciclo.sh (FM-F27INS-01CONV) — só "### Achado N"
# com N>=1, direto dos pareceres. Nesta fixture: codex tem "### Achado 1" (=1), agy não
# tem heading de achado nenhum (=0) → PROPRIA=1, contra o SEM=2 da tabela antiga (que
# conta de mais o "c0-01" do Q4 do agy).
propria() { # <parecer...> → soma de cabeçalhos «### Achado N» (N>=1)
  local f n total=0
  for f in "$@"; do
    n=$({ grep -oE '^#{2,4}[[:space:]]+Achado[[:space:]]+[0-9]+' "$f" 2>/dev/null || true; } \
        | { grep -oE '[0-9]+$' || true; } | awk '$1>=1' | wc -l | tr -d ' ')
    total=$((total + n))
  done
  printf '%s' "$total"
}
PROPRIA=$(propria "$FIX/24.3-parecer-codex-c1.md" "$FIX/24.3-parecer-agy-c1.md")
[ "$PROPRIA" != "$SEM" ] && ok "PROPRIA ($PROPRIA) difere de SEM ($SEM) nesta fixture — o falso positivo que estamos corrigindo" \
  || erro "fixture não discrimina PROPRIA de SEM (o teste não provaria a correção)"

echo "== intenção: o apêndice conta os brutos da tabela do coordenador"
PD="$TMP/24-fase"; monta "$PD" intencao
"$SCRIPT" "$PD" 24.3 1 intencao >/dev/null 2>&1
GOT=$(brutos_do_apendice "$PD/24.3-REVIEWS.md")
[ "$GOT" = "$COM" ] && ok "brutos do apêndice = $COM (dirigidas incluídas)" \
  || erro "apêndice contou $GOT, tabela do coordenador conta $COM" "$(cat "$PD/24.3-REVIEWS.md")"

echo "== convergência: sem dirigida a somar → conta própria (FM-F27INS-01CONV), não a tabela antiga"
PDC="$TMP/24-conv"; monta "$PDC" convergencia
"$SCRIPT" "$PDC" 24.3 1 convergencia >/dev/null 2>&1
GOTC=$(brutos_do_apendice "$PDC/24.3-REVIEWS.md")
[ "$GOTC" = "$PROPRIA" ] && ok "brutos do apêndice = $PROPRIA (não o $SEM da tabela antiga)" \
  || erro "apêndice contou $GOTC (esperado $PROPRIA)" "$(cat "$PDC/24.3-REVIEWS.md")"
grep -qF "total da tabela do confere-ciclo.sh (\`pareceres/.tabela-c1.txt\`): $SEM" "$PDC/24.3-REVIEWS.md" \
  && ok "o apêndice também mostra o $SEM da tabela antiga, rotulado — nunca dois números escondidos" \
  || erro "faltou o segundo número (rotulado) no apêndice — dois números, um escondido" "$(cat "$PDC/24.3-REVIEWS.md")"
grep -qF "sem cabeçalho \`### Achado N\` reconhecível" "$PDC/24.3-REVIEWS.md" \
  && ok "o aviso de 'sem cabeçalho' também fica DURÁVEL no apêndice (não só em stderr)" \
  || erro "o aviso de 'sem cabeçalho' devia estar gravado no apêndice" "$(cat "$PDC/24.3-REVIEWS.md")"

echo "== sem os arquivos novos: sem dirigida a somar → mesma conta própria, exit 0"
PDV="$TMP/24-velha"; mkdir -p "$PDV/pareceres"
cp "$FIX/24.3-parecer-codex-c1.md" "$PDV/pareceres/24.3-parecer-codex-c1.md"
cp "$FIX/24.3-parecer-agy-c1.md"   "$PDV/pareceres/24.3-parecer-agy-c1.md"
"$SCRIPT" "$PDV" 24.3 1 intencao >/dev/null 2>&1
rc=$?
GOTV=$(brutos_do_apendice "$PDV/24.3-REVIEWS.md")
[ "$rc" = 0 ] && [ "$GOTV" = "$PROPRIA" ] && ok "fase sem .intent/ registra $PROPRIA brutos, exit 0" \
  || erro "fase antiga quebrou (rc=$rc, brutos=$GOTV)"

echo "== 45(j) — o espelho da lane é lido pela FAMÍLIA (.roda-planrev-… na convergência)"
PDE="$TMP/24-espelho"; monta "$PDE" convergencia
esp() { printf '{"modelo_efetivo":"%s","fresco":true,"vazio":false,"banner":"%s","prova_leitura":true,"degradado":false}\n' "$1" "$2"; }
esp modelo-INTENCAO banner-INTENCAO > "$PDE/pareceres/.roda-codex-c1.json"
esp modelo-CONVERGENCIA banner-CONVERGENCIA > "$PDE/pareceres/.roda-planrev-codex-c1.json"
"$SCRIPT" "$PDE" 24.3 1 convergencia >/dev/null 2>&1
if grep -q 'modelo-CONVERGENCIA' "$PDE/24.3-REVIEWS.md"; then
  ok "modo convergencia lê .roda-planrev-codex-c1.json"
else
  erro "modo convergencia leu o espelho errado" "$(grep -n 'modelo_efetivo' "$PDE/24.3-REVIEWS.md" | head -3)"
fi
grep -q 'modelo-INTENCAO' "$PDE/24.3-REVIEWS.md" \
  && erro "modo convergencia leu o espelho da INTENÇÃO" || ok "o espelho da intenção não é lido na convergência"

PDI="$TMP/24-espelho-int"; monta "$PDI" intencao
esp modelo-INTENCAO banner-INTENCAO > "$PDI/pareceres/.roda-codex-c1.json"
"$SCRIPT" "$PDI" 24.3 1 intencao >/dev/null 2>&1
grep -q 'modelo-INTENCAO' "$PDI/24.3-REVIEWS.md" \
  && ok "modo intencao continua lendo .roda-codex-c1.json (sem prefixo)" \
  || erro "o modo intenção regrediu" "$(grep -n 'modelo_efetivo' "$PDI/24.3-REVIEWS.md" | head -3)"

PDA="$TMP/24-espelho-antigo"; monta "$PDA" convergencia
esp modelo-ANTIGO banner-ANTIGO > "$PDA/pareceres/.roda-codex-c1.json"
"$SCRIPT" "$PDA" 24.3 1 convergencia >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok "fase anterior à separação (só o espelho sem prefixo): exit 0, lane pulada" \
  || erro "fase antiga quebrou no modo convergencia (rc=$rc)"

echo "== FM-F4RLR-05CONV — «## Seção» citada no parecer precisa existir como título de verdade"
PDS="$TMP/24-secao"; mkdir -p "$PDS/pareceres"
printf -- '# Fase 24.3\n\n## Requisitos\n\ncorpo\n' > "$PDS/24.3-PLAN.md"
printf 'prova_leitura: PROVA-abc\nConferi conforme `## Requisitos` e bateu. Também citei `## Secao Fantasma`, que não existe.\nsrc/x.py:1 — citação.\n' \
  > "$PDS/pareceres/24.3-parecer-codex-c1.md"
jq -cn --arg p "$PDS/pareceres/24.3-parecer-codex-c1.md" \
  '{modelo_efetivo:"m", fresco:true, vazio:false, banner:"", prova_leitura:"ok", degradado:false, parecer:$p}' \
  > "$PDS/pareceres/.roda-codex-c1.json"
"$SCRIPT" "$PDS" 24.3 1 intencao >/dev/null 2>&1
grep -qF '`## Secao Fantasma`' "$PDS/24.3-REVIEWS.md" \
  && ok "seção inexistente vira aviso no apêndice" || erro "aviso de seção ausente não apareceu" "$(cat "$PDS/24.3-REVIEWS.md")"
grep -qF '`## Requisitos`' "$PDS/24.3-REVIEWS.md" \
  && erro "seção que EXISTE não devia gerar aviso" "$(cat "$PDS/24.3-REVIEWS.md")" \
  || ok "seção que existe de verdade não dispara aviso"

echo "== FM-F27INS-01CONV — «Achado 0» explícito conta zero SEM aviso; prosa sem cabeçalho reconhecível GANHA aviso"
PDZ="$TMP/24-zero"; mkdir -p "$PDZ/pareceres"
printf 'prova_leitura: PROVA-z1\n\n### Achado 0 — nenhum achado novo\n' \
  > "$PDZ/pareceres/24.3-planrev-parecer-codex-c1.md"
printf 'prova_leitura: PROVA-z2\n\nRevisei tudo, sem achar nada de errado além de comentários gerais.\n' \
  > "$PDZ/pareceres/24.3-planrev-parecer-agy-c1.md"
ERR=$("$SCRIPT" "$PDZ" 24.3 1 convergencia 2>&1 1>/dev/null)
GOTZ=$(brutos_do_apendice "$PDZ/24.3-REVIEWS.md")
[ "$GOTZ" = "0" ] && ok "brutos = 0 (Achado 0 explícito + prosa sem cabeçalho)" \
  || erro "brutos deveriam ser 0, veio $GOTZ"
printf '%s' "$ERR" | grep -q 'sem cabeçalho' \
  && ok "aviso de 'sem cabeçalho reconhecível' apareceu para o parecer em prosa (agy)" \
  || erro "faltou o aviso de cabeçalho não reconhecível" "$ERR"
printf '%s' "$ERR" | grep -q 'planrev-parecer-codex-c1.md sem cabeçalho' \
  && erro "o parecer com 'Achado 0' explícito NÃO deveria disparar o aviso" "$ERR" \
  || ok "o parecer com 'Achado 0' explícito não dispara o aviso"

echo
[ "$falhas" -eq 0 ] && echo "test-registra-ciclo: TUDO OK" || echo "test-registra-ciclo: $falhas falha(s)"
[ "$falhas" -eq 0 ]
