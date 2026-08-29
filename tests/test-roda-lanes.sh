#!/usr/bin/env bash
# test-roda-lanes.sh — bancada do item E4 (roda-lanes.sh + flags novas dos roda-*.sh).
#
# Roda em bancada ISOLADA: as lanes são dublês (tests/fixtures/roda-lanes/stub), Codex e
# agy nunca são chamados. Autônomo — pode ser rodado direto ou pelo tests/roda.sh.
#   bash tests/test-roda-lanes.sh
# Exit 0 = tudo verde; 1 = alguma falha (o resumo final diz quantas).
set -u

RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
LANES="$RAIZ/skills/go-and-do/scripts/roda-lanes.sh"
FIX="$RAIZ/tests/fixtures/roda-lanes"
export GAD_LANES_DIR="$FIX/stub"

OK=0; FALHAS=0
ok()    { OK=$((OK+1)); printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }

# ── bancada: phase_dir descartável ────────────────────────────────────────────
BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT
monta_fase() { # → ecoa o phase_dir novo
  local pd; pd="$(mktemp -d "$BASE/fase-XXXXXX")"
  mkdir -p "$pd/.intent" "$pd/pareceres"
  printf 'Briefing de bancada.\nprova_leitura: <token>\n' > "$pd/.intent/briefing-c1.md"
  printf 'Token de prova de leitura do ciclo 1: PROVA-abc123\n' > "$pd/.intent/.prova-leitura-c1.txt"
  printf '%s\n' "$pd"
}
cfg() { # <dir> <lane> <linhas...>  → escreve o .env do dublê
  local d="$1" lane="$2"; shift 2; mkdir -p "$d"; printf '%s\n' "$@" > "$d/$lane.env"
}
espera() { # <arquivo> [segundos]
  local f="$1" t="${2:-20}" i
  for ((i = 0; i < t * 10; i++)); do [ -f "$f" ] && return 0; sleep 0.1; done
  return 1
}
campo() { jq -r "$2" "$1" 2>/dev/null || echo "<sem-status>"; }

lanca() { # <phase_dir> <cfgdir> [lanes] → ecoa o JSON do lançador
  local pd="$1" cfgd="$2" lanes="${3:-codex}"
  STUB_CFG="$cfgd" bash "$LANES" "$pd" 01 1 "$pd/.intent/briefing-c1.md" \
    --prova "$pd/.intent/.prova-leitura-c1.txt" --lanes "$lanes"
}

echo "── E4: predicados do status ──"

# 1. retorno < 1 s + 2. lanes vivas depois do retorno
PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex "SLEEP=2"
T0=$(date +%s%N); J="$(lanca "$PD" "$CFG")"; T1=$(date +%s%N)
MS=$(( (T1 - T0) / 1000000 ))
if [ "$MS" -lt 1000 ]; then ok "lançador retorna em < 1 s (${MS} ms)"
else falha "lançador retorna em < 1 s" "levou ${MS} ms"; fi
PID="$(jq -r '.pids[0]' <<<"$J")"
if kill -0 "$PID" 2>/dev/null; then ok "supervisor vivo após o retorno da tool (pid $PID)"
else falha "supervisor vivo após o retorno da tool" "pid $PID já morto"; fi
if jq -e '.run_id and (.pids|length==1) and (.status_paths|length==1)' <<<"$J" >/dev/null
then ok "JSON de retorno traz run_id, pids e status_paths"
else falha "JSON de retorno" "$J"; fi
ST="$(jq -r '.status_paths[0]' <<<"$J")"; espera "$ST" 20

# tabela de predicados: cada caso = um cfg + as asserções do status
caso() { # <nome> <cfg-linhas separadas por |> <usable> <independent> [mirror_valid] [rc_reason]
  local nome="$1" linhas="$2" eu="$3" ei="$4" emv="${5:-}" err="${6:-}"
  local pd cfgd j st
  pd="$(monta_fase)"; cfgd="$pd/cfg"; mkdir -p "$cfgd"
  printf '%s\n' "$linhas" | tr '|' '\n' > "$cfgd/codex.env"
  j="$(lanca "$pd" "$cfgd")"; st="$(jq -r '.status_paths[0]' <<<"$j")"
  if ! espera "$st" 25; then falha "$nome" "status nunca apareceu em $st"; return; fi
  eq "$nome → usable=$eu" "$(campo "$st" .usable)" "$eu"
  eq "$nome → independent=$ei" "$(campo "$st" .independent)" "$ei"
  [ -n "$emv" ] && eq "$nome → mirror_valid=$emv" "$(campo "$st" .mirror_valid)" "$emv"
  [ -n "$err" ] && eq "$nome → rc_reason=$err" "$(campo "$st" .rc_reason)" "$err"
  return 0
}

caso "rc 5 (CLI ausente)"        'RC=5|PARECER=|ESPELHO={"revisor_ausente":"codex"}' false false "" revisor_ausente
caso "stdout vazio"              'RC=6|PARECER=' false false "" parecer_vazio
caso "parecer obsoleto"          'FRESCO=false|RC=6' false false "" parecer_obsoleto
caso "parecer ilegível (byte NUL)" 'NUL=sim' false false "" parecer_ilegivel
caso "rc 6 só por modelo divergente" 'RC=6|DEGRADADO=true|NONCE=sim' true false true modelo_divergente
caso "espelho ausente + parecer íntegro"   'ESPELHO=NONE|NONCE=sim' true false false espelho_invalido
caso "espelho malformado + parecer íntegro" 'ESPELHO=MALFORMED|NONCE=sim' true false false espelho_invalido
caso "parecer sem nonce, com conteúdo"     'NONCE=nao' true false true sem_prova_leitura
caso "token do briefing devolvido"         'NONCE=sim' true true true ok

# timeout do filho sem parecer válido
PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex "SLEEP=30" "PARECER="
J="$(GAD_LANE_TIMEOUT=1 lanca "$PD" "$CFG")"; ST="$(jq -r '.status_paths[0]' <<<"$J")"
if espera "$ST" 25; then
  eq "timeout do filho → usable=false" "$(campo "$ST" .usable)" false
  eq "timeout do filho → rc_reason=timeout" "$(campo "$ST" .rc_reason)" timeout
else falha "timeout do filho" "status nunca apareceu"; fi

# kill -9 do filho sem parecer válido
caso "kill -9 do filho sem parecer" 'SUICIDA=sim|PARECER=' false false "" parecer_vazio

echo "── E4: 4 combinações nonce_ok × modelo_ok ──"
for n in sim nao; do for d in false true; do
  PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex "NONCE=$n" "DEGRADADO=$d" "RC=0"
  J="$(lanca "$PD" "$CFG")"; ST="$(jq -r '.status_paths[0]' <<<"$J")"
  espera "$ST" 25 || { falha "combo nonce=$n degradado=$d" "sem status"; continue; }
  ENON=false; [ "$n" = sim ] && ENON=true
  EMOD=true;  [ "$d" = true ] && EMOD=false
  EIND=false; [ "$ENON" = true ] && [ "$EMOD" = true ] && EIND=true
  eq "combo nonce=$n degradado=$d → nonce_ok" "$(campo "$ST" .nonce_ok)" "$ENON"
  eq "combo nonce=$n degradado=$d → modelo_ok" "$(campo "$ST" .modelo_ok)" "$EMOD"
  eq "combo nonce=$n degradado=$d → independent" "$(campo "$ST" .independent)" "$EIND"
done; done

# lane sem log próprio (caso do codex real) → `log: null`, nunca caminho inexistente
PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex "NOLOG=sim" "NONCE=sim"
J="$(lanca "$PD" "$CFG")"; ST="$(jq -r '.status_paths[0]' <<<"$J")"; espera "$ST" 25
eq "lane sem log → status.log = null" "$(campo "$ST" '.log // "null"')" null

# --prova obrigatório
PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex "NONCE=sim"
RC=0; STUB_CFG="$CFG" bash "$LANES" "$PD" 01 1 "$PD/.intent/briefing-c1.md" --lanes codex \
  >/dev/null 2>&1 || RC=$?
eq "lançador sem --prova → exit 2 (uso)" "$RC" 2

echo "── E4: run_id, sobreposição, lock ──"

# re-execução do mesmo ciclo: run_id novo, run antigo intacto no run-dir dele
PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex 'PARECER="parecer do run A"'
JA="$(lanca "$PD" "$CFG")"; STA="$(jq -r '.status_paths[0]' <<<"$JA")"; espera "$STA" 25
cfg "$CFG" codex 'PARECER="parecer do run B"'
JB="$(lanca "$PD" "$CFG")"; STB="$(jq -r '.status_paths[0]' <<<"$JB")"; espera "$STB" 25
RA="$(jq -r .run_id <<<"$JA")"; RB="$(jq -r .run_id <<<"$JB")"
if [ "$RA" != "$RB" ]; then ok "re-execução gera run_id diferente"
else falha "re-execução gera run_id diferente" "$RA == $RB"; fi
eq "status antigo mantém o run_id dele" "$(campo "$STA" .run_id)" "$RA"
if grep -q "run A" "$(jq -r .parecer "$STA")"; then ok "run-dir antigo continua íntegro após o run novo"
else falha "run-dir antigo continua íntegro" "parecer do run A foi alterado"; fi
eq "alias canônico do status aponta o run novo" \
   "$(campo "$PD/.intent/.status-c1-codex.json" .run_id)" "$RB"

# dois roda-lanes sobrepostos: o run antigo termina depois e NÃO toca os aliases
PD="$(monta_fase)"; CA="$PD/cfgA"; CB="$PD/cfgB"
cfg "$CA" codex "SLEEP=3" 'PARECER="parecer do run lento"'
cfg "$CB" codex "SLEEP=0" 'PARECER="parecer do run rapido"'
JA="$(lanca "$PD" "$CA")"; JB="$(lanca "$PD" "$CB")"
STA="$(jq -r '.status_paths[0]' <<<"$JA")"; STB="$(jq -r '.status_paths[0]' <<<"$JB")"
espera "$STB" 25; espera "$STA" 30; sleep 1
ALIAS="$PD/pareceres/01-parecer-codex-c1.md"
if grep -q "run rapido" "$ALIAS" 2>/dev/null
then ok "run sobreposto: alias canônico ficou com o run DONO do ponteiro"
else falha "run sobreposto: alias canônico" "conteúdo: $(head -1 "$ALIAS" 2>/dev/null)"; fi
if grep -q "run lento" "$(jq -r .parecer "$STA")" 2>/dev/null
then ok "run sobreposto: o run órfão publicou só no run-dir dele"
else falha "run sobreposto: run-dir do órfão" "parecer do run lento sumiu"; fi
eq "run sobreposto: alias do status é do run dono" \
   "$(campo "$PD/.intent/.status-c1-codex.json" .run_id)" "$(jq -r .run_id <<<"$JB")"

# ordem: quando o `.done` existe, o status já está completo e legível
if [ -f "$PD/.intent/.done-c1-codex" ]; then
  eq "status completo antes do alias .done" \
     "$(campo "$PD/.intent/.status-c1-codex.json" .complete)" true
else falha "alias .done publicado" "marcador ausente"; fi

# lock órfão: lock com PID morto → o próximo run prossegue
PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex 'PARECER="depois do lock orfao"'
( : ) & MORTO=$!; wait "$MORTO" 2>/dev/null   # PID garantidamente morto
mkdir -p "$PD/.intent/.lock-c1"; echo "$MORTO" > "$PD/.intent/.lock-c1/pid"
J="$(lanca "$PD" "$CFG" || true)"
ST="$(jq -r '.status_paths[0] // empty' <<<"${J:-{}}" 2>/dev/null || true)"
if [ -n "$ST" ] && espera "$ST" 25; then ok "lock órfão (PID morto) detectado — run novo prossegue"
else falha "lock órfão detectado" "lançador não conseguiu o lock"; fi

# duas lanes (o par real codex+agy) no mesmo run
PD="$(monta_fase)"; CFG="$PD/cfg"
cfg "$CFG" codex "NONCE=sim"; cfg "$CFG" agy "NONCE=sim"
J="$(lanca "$PD" "$CFG" "codex agy")"
eq "par codex+agy → 2 pids" "$(jq -r '.pids|length' <<<"$J")" 2
VERDES=0
for i in 0 1; do
  ST="$(jq -r ".status_paths[$i]" <<<"$J")"
  espera "$ST" 25 && [ "$(campo "$ST" .usable)" = true ] && VERDES=$((VERDES+1))
done
eq "par codex+agy → 2 status usable" "$VERDES" 2
for lane in codex agy; do
  espera "$PD/.intent/.done-c1-$lane" 25
  if [ -f "$PD/.intent/.done-c1-$lane" ] && [ -f "$PD/pareceres/01-parecer-$lane-c1.md" ]
  then ok "par codex+agy → aliases da lane $lane promovidos"
  else falha "aliases da lane $lane" "faltou .done ou parecer canônico"; fi
done

echo "── compatibilidade dos roda-*.sh sem as flags novas ──"
for s in roda-agy.sh roda-codex.sh roda-lanes.sh; do
  if bash -n "$RAIZ/skills/go-and-do/scripts/$s"; then ok "$s: bash -n limpo"
  else falha "$s: bash -n" "erro de sintaxe"; fi
done
# PATH mínimo REAL (coreutils/jq presentes, codex e agy fora) → rota rc 5 de sempre
VAZIO=/usr/bin:/bin
if PATH="$VAZIO" command -v codex >/dev/null 2>&1 || PATH="$VAZIO" command -v agy >/dev/null 2>&1; then
  falha "bancada de compatibilidade" "codex/agy visíveis em $VAZIO — teste inconclusivo"
fi
for lane in agy codex; do
  PD="$(monta_fase)"
  RC=0; PATH="$VAZIO" bash "$RAIZ/skills/go-and-do/scripts/roda-$lane.sh" \
    "$PD" 01 1 "$PD/.intent/briefing-c1.md" >/dev/null 2>&1 || RC=$?
  eq "roda-$lane.sh sem flags novas → exit 5 (revisor ausente)" "$RC" 5
  eq "roda-$lane.sh sem flags novas → espelho no caminho canônico de sempre" \
     "$(jq -r '.revisor_ausente // "?"' "$PD/pareceres/.roda-$lane-c1.json" 2>/dev/null || echo "?")" "$lane"
  RC=0; bash "$RAIZ/skills/go-and-do/scripts/roda-$lane.sh" "$PD" >/dev/null 2>&1 || RC=$?
  eq "roda-$lane.sh com argumentos faltando → exit 2 (uso)" "$RC" 2
done

echo
TOTAL=$((OK + FALHAS))
printf '%s testes, %s verdes, %s vermelhos\n' "$TOTAL" "$OK" "$FALHAS"
[ "$FALHAS" = 0 ]
