#!/usr/bin/env bash
# test-registra-ciclo.sh — o apêndice do NN-REVIEWS tem de contar os MESMOS brutos que a
# tabela do coordenador (v2.2.0): o `confere-ciclo.sh --tabela` do registra-ciclo passa
# `--perguntas`/`--status-dir`/`--vereditos` quando os arquivos da intenção existem, e
# NÃO os passa no ciclo da convergência (numeração colide entre as duas famílias).
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

brutos_do_apendice() { sed -n 's/^- brutos na tabela do ciclo: \([0-9]*\).*/\1/p' "$1" | tail -1; }
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

echo "== intenção: o apêndice conta os brutos da tabela do coordenador"
PD="$TMP/24-fase"; monta "$PD" intencao
"$SCRIPT" "$PD" 24.3 1 intencao >/dev/null 2>&1
GOT=$(brutos_do_apendice "$PD/24.3-REVIEWS.md")
[ "$GOT" = "$COM" ] && ok "brutos do apêndice = $COM (dirigidas incluídas)" \
  || erro "apêndice contou $GOT, tabela do coordenador conta $COM" "$(cat "$PD/24.3-REVIEWS.md")"

echo "== convergência: as entradas da intenção NÃO são aplicadas (numeração colide)"
PDC="$TMP/24-conv"; monta "$PDC" convergencia
"$SCRIPT" "$PDC" 24.3 1 convergencia >/dev/null 2>&1
GOTC=$(brutos_do_apendice "$PDC/24.3-REVIEWS.md")
[ "$GOTC" = "$SEM" ] && ok "brutos do apêndice = $SEM (sem manifesto da intenção)" \
  || erro "convergência usou as flags da intenção: $GOTC (esperado $SEM)"

echo "== sem os arquivos novos: comportamento antigo, sem quebrar"
PDV="$TMP/24-velha"; mkdir -p "$PDV/pareceres"
cp "$FIX/24.3-parecer-codex-c1.md" "$PDV/pareceres/24.3-parecer-codex-c1.md"
cp "$FIX/24.3-parecer-agy-c1.md"   "$PDV/pareceres/24.3-parecer-agy-c1.md"
"$SCRIPT" "$PDV" 24.3 1 intencao >/dev/null 2>&1
rc=$?
GOTV=$(brutos_do_apendice "$PDV/24.3-REVIEWS.md")
[ "$rc" = 0 ] && [ "$GOTV" = "$SEM" ] && ok "fase sem .intent/ registra $SEM brutos, exit 0" \
  || erro "fase antiga quebrou (rc=$rc, brutos=$GOTV)"

echo
[ "$falhas" -eq 0 ] && echo "test-registra-ciclo: TUDO OK" || echo "test-registra-ciclo: $falhas falha(s)"
[ "$falhas" -eq 0 ]
