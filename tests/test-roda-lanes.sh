#!/usr/bin/env bash
# test-roda-lanes.sh — bancada do item E4 (roda-lanes.sh + flags novas dos roda-*.sh).
#
# Roda em bancada ISOLADA: as lanes são dublês (tests/fixtures/roda-lanes/stub), Codex e
# agy nunca são chamados. Autônomo — pode ser rodado direto ou pelo tests/roda.sh.
# Sincronização por ARQUIVO (P15): o dublê espera `WAIT_FOR=<arquivo>` e sinaliza
# `STARTED=<arquivo>`; o teste espera marcadores com teto folgado (30 s) e só então afirma.
# Nada de `sleep N` como barreira — sob carga a ordem de chegada invertia e o teste caía
# por corrida, não por defeito.
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
  local f="$1" t="${2:-30}" i
  for ((i = 0; i < t * 10; i++)); do [ -f "$f" ] && return 0; sleep 0.1; done
  return 1
}
espera_morrer() { # <pid> [segundos] → 0 quando o processo não existe mais
  local p="$1" t="${2:-30}" i
  for ((i = 0; i < t * 10; i++)); do kill -0 "$p" 2>/dev/null || return 0; sleep 0.1; done
  return 1
}
campo() { jq -r "$2" "$1" 2>/dev/null || echo "<sem-status>"; }

lanca() { # <phase_dir> <cfgdir> [lanes] → ecoa o JSON do lançador
  local pd="$1" cfgd="$2" lanes="${3:-codex}"
  STUB_CFG="$cfgd" bash "$LANES" "$pd" 01 1 "$pd/.intent/briefing-c1.md" \
    --prova "$pd/.intent/.prova-leitura-c1.txt" --lanes "$lanes"
}

echo "── E4: predicados do status ──"

# 1. retorno < 1 s + 2. lanes vivas depois do retorno (o dublê segura no WAIT_FOR)
PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex "STARTED=$PD/.started" "WAIT_FOR=$PD/.libera"
T0=$(date +%s%N); J="$(lanca "$PD" "$CFG")"; T1=$(date +%s%N)
MS=$(( (T1 - T0) / 1000000 ))
if [ "$MS" -lt 1000 ]; then ok "lançador retorna em < 1 s (${MS} ms)"
else falha "lançador retorna em < 1 s" "levou ${MS} ms"; fi
PID="$(jq -r '.pids[0]' <<<"$J")"
espera "$PD/.started" 30 || falha "dublê começou" "marcador .started nunca apareceu"
if kill -0 "$PID" 2>/dev/null; then ok "supervisor vivo após o retorno da tool (pid $PID)"
else falha "supervisor vivo após o retorno da tool" "pid $PID já morto"; fi
if jq -e '.run_id and (.pids|length==1) and (.status_paths|length==1)' <<<"$J" >/dev/null
then ok "JSON de retorno traz run_id, pids e status_paths"
else falha "JSON de retorno" "$J"; fi
: > "$PD/.libera"
ST="$(jq -r '.status_paths[0]' <<<"$J")"; espera "$ST" 30

# tabela de predicados: cada caso = um cfg + as asserções do status
caso() { # <nome> <cfg-linhas separadas por |> <usable> <independent> [mirror_valid] [rc_reason]
  local nome="$1" linhas="$2" eu="$3" ei="$4" emv="${5:-}" err="${6:-}"
  local pd cfgd j st
  pd="$(monta_fase)"; cfgd="$pd/cfg"; mkdir -p "$cfgd"
  printf '%s\n' "$linhas" | tr '|' '\n' > "$cfgd/codex.env"
  j="$(lanca "$pd" "$cfgd")"; st="$(jq -r '.status_paths[0]' <<<"$j")"
  if ! espera "$st" 30; then falha "$nome" "status nunca apareceu em $st"; return; fi
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

# timeout do filho sem parecer válido: o dublê espera um marcador que NUNCA é criado
PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex "WAIT_FOR=$PD/.nunca" "PARECER="
J="$(GAD_LANE_TIMEOUT=1 lanca "$PD" "$CFG")"; ST="$(jq -r '.status_paths[0]' <<<"$J")"
if espera "$ST" 30; then
  eq "timeout do filho → usable=false" "$(campo "$ST" .usable)" false
  eq "timeout do filho → rc_reason=timeout" "$(campo "$ST" .rc_reason)" timeout
else falha "timeout do filho" "status nunca apareceu"; fi

# kill -9 do filho sem parecer válido
caso "kill -9 do filho sem parecer" 'SUICIDA=sim|PARECER=' false false "" parecer_vazio

echo "── E4: 4 combinações nonce_ok × modelo_ok ──"
for n in sim nao; do for d in false true; do
  PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex "NONCE=$n" "DEGRADADO=$d" "RC=0"
  J="$(lanca "$PD" "$CFG")"; ST="$(jq -r '.status_paths[0]' <<<"$J")"
  espera "$ST" 30 || { falha "combo nonce=$n degradado=$d" "sem status"; continue; }
  ENON=false; [ "$n" = sim ] && ENON=true
  EMOD=true;  [ "$d" = true ] && EMOD=false
  EIND=false; [ "$ENON" = true ] && [ "$EMOD" = true ] && EIND=true
  eq "combo nonce=$n degradado=$d → nonce_ok" "$(campo "$ST" .nonce_ok)" "$ENON"
  eq "combo nonce=$n degradado=$d → modelo_ok" "$(campo "$ST" .modelo_ok)" "$EMOD"
  eq "combo nonce=$n degradado=$d → independent" "$(campo "$ST" .independent)" "$EIND"
done; done

# lane sem log próprio (caso do codex real) → `log: null`, nunca caminho inexistente
PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex "NOLOG=sim" "NONCE=sim"
J="$(lanca "$PD" "$CFG")"; ST="$(jq -r '.status_paths[0]' <<<"$J")"; espera "$ST" 30
eq "lane sem log → status.log = null" "$(campo "$ST" '.log // "null"')" null

# --prova obrigatório
PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex "NONCE=sim"
RC=0; STUB_CFG="$CFG" bash "$LANES" "$PD" 01 1 "$PD/.intent/briefing-c1.md" --lanes codex \
  >/dev/null 2>&1 || RC=$?
eq "lançador sem --prova → exit 2 (uso)" "$RC" 2

echo "── E4: run_id, sobreposição, lock ──"

# re-execução do mesmo ciclo: run_id novo, run antigo intacto no run-dir dele
PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex 'PARECER="parecer do run A"'
JA="$(lanca "$PD" "$CFG")"; STA="$(jq -r '.status_paths[0]' <<<"$JA")"; espera "$STA" 30
espera_morrer "$(jq -r '.pids[0]' <<<"$JA")" 30
cfg "$CFG" codex 'PARECER="parecer do run B"'
JB="$(lanca "$PD" "$CFG")"; STB="$(jq -r '.status_paths[0]' <<<"$JB")"; espera "$STB" 30
espera_morrer "$(jq -r '.pids[0]' <<<"$JB")" 30
RA="$(jq -r .run_id <<<"$JA")"; RB="$(jq -r .run_id <<<"$JB")"
if [ "$RA" != "$RB" ]; then ok "re-execução gera run_id diferente"
else falha "re-execução gera run_id diferente" "$RA == $RB"; fi
eq "status antigo mantém o run_id dele" "$(campo "$STA" .run_id)" "$RA"
if grep -q "run A" "$(jq -r .parecer "$STA")"; then ok "run-dir antigo continua íntegro após o run novo"
else falha "run-dir antigo continua íntegro" "parecer do run A foi alterado"; fi
eq "alias canônico do status aponta o run novo" \
   "$(campo "$PD/.intent/.status-c1-codex.json" .run_id)" "$RB"

# dois roda-lanes sobrepostos: o run antigo termina depois e NÃO toca os aliases.
# Barreiras: o run lento fica preso em WAIT_FOR até o rápido publicar; depois de solto,
# o teste espera o SUPERVISOR dele morrer (a promoção vem depois do status) e só aí afirma.
PD="$(monta_fase)"; CA="$PD/cfgA"; CB="$PD/cfgB"
cfg "$CA" codex "WAIT_FOR=$PD/.libera-lento" 'PARECER="parecer do run lento"'
cfg "$CB" codex 'PARECER="parecer do run rapido"'
JA="$(lanca "$PD" "$CA")"; JB="$(lanca "$PD" "$CB")"
STA="$(jq -r '.status_paths[0]' <<<"$JA")"; STB="$(jq -r '.status_paths[0]' <<<"$JB")"
espera "$STB" 30; espera_morrer "$(jq -r '.pids[0]' <<<"$JB")" 30
: > "$PD/.libera-lento"
espera "$STA" 30; espera_morrer "$(jq -r '.pids[0]' <<<"$JA")" 30
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
if [ -n "$ST" ] && espera "$ST" 30; then ok "lock órfão (PID morto) detectado — run novo prossegue"
else falha "lock órfão detectado" "lançador não conseguiu o lock"; fi

# duas lanes (o par real codex+agy) no mesmo run
PD="$(monta_fase)"; CFG="$PD/cfg"
cfg "$CFG" codex "NONCE=sim"; cfg "$CFG" agy "NONCE=sim"
J="$(lanca "$PD" "$CFG" "codex agy")"
eq "par codex+agy → 2 pids" "$(jq -r '.pids|length' <<<"$J")" 2
VERDES=0
for i in 0 1; do
  ST="$(jq -r ".status_paths[$i]" <<<"$J")"
  espera "$ST" 30 && [ "$(campo "$ST" .usable)" = true ] && VERDES=$((VERDES+1))
done
eq "par codex+agy → 2 status usable" "$VERDES" 2
for lane in codex agy; do
  espera "$PD/.intent/.done-c1-$lane" 30
  if [ -f "$PD/.intent/.done-c1-$lane" ] && [ -f "$PD/pareceres/01-parecer-$lane-c1.md" ]
  then ok "par codex+agy → aliases da lane $lane promovidos"
  else falha "aliases da lane $lane" "faltou .done ou parecer canônico"; fi
done


echo "── P15: cancela parecer_informe — devolve uma vez, reprova na segunda ──"
CONFERE="$RAIZ/skills/go-and-do/scripts/confere-ciclo.sh"
DECIDE="$RAIZ/skills/go-and-do/scripts/decide-ciclo.sh"
PROSA="$BASE/prosa.md"
{ echo "Parecer em prosa corrida, sem o gabarito de achado."
  for i in $(seq 1 14); do echo "Linha $i: a regra de cardinalidade do AC-41 contradiz a travessia exigida em src/x.py:$i."; done
} > "$PROSA"
roda_lane() { # <phase_dir> <cfgdir> [args extras…] → espera o supervisor e ecoa o JSON
  local pd="$1" cfgd="$2" j; shift 2
  j="$(STUB_CFG="$cfgd" bash "$LANES" "$pd" 01 1 "$pd/.intent/briefing-c1.md" \
        --prova "$pd/.intent/.prova-leitura-c1.txt" --lanes codex "$@")" || return $?
  espera "$(jq -r '.status_paths[0]' <<<"$j")" 30; espera_morrer "$(jq -r '.pids[0]' <<<"$j")" 30
  printf '%s\n' "$j"
}
tabela() { bash "$CONFERE" --tabela --status-dir "$1/.intent" "$1/pareceres/01-parecer-codex-c1.md"; }

# cenário A: prosa 2× → reprovada + incidente; decide-ciclo não converge
PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex "NONCE=sim" "CORPO=$PROSA"
J1="$(roda_lane "$PD" "$CFG")"
T1="$(tabela "$PD")"
eq "A: 1ª prosa → achados_estruturais_total 0" "$(sed -n 's/^achados_estruturais_total: *//p' <<<"$T1")" 0
eq "A: 1ª prosa → parecer_informe codex devolver" "$(grep '^parecer_informe:' <<<"$T1")" "parecer_informe: codex devolver"
eq "A: 1ª prosa não mexe no status (usable=true)" "$(campo "$PD/.intent/.status-c1-codex.json" .usable)" true
J2="$(roda_lane "$PD" "$CFG" --reformata codex)"
eq "A: --reformata relança só 1 lane" "$(jq -r '.pids|length' <<<"$J2")" 1
[ "$(jq -r .run_id <<<"$J1")" != "$(jq -r .run_id <<<"$J2")" ] && ok "A: devolução tem run_id próprio (a 1ª tentativa fica no run-dir dela)" \
  || falha "A: run_id da devolução" "igual ao da 1ª"
[ -f "$PD/pareceres/.reformat-codex-c1" ] && ok "A: marcador .reformat-codex-c1 gravado" || falha "A: marcador" "ausente"
BR="$PD/.intent/briefing-c1-reformat-codex.md"
grep -q '^## Reformatação obrigatória' "$BR" && grep -q 'Achado 0 — nenhum achado novo' "$BR" && grep -q 'Briefing de bancada' "$BR" \
  && ok "A: briefing da devolução = original + bloco de reformatação com o gabarito" \
  || falha "A: briefing da devolução" "$(head -3 "$BR" 2>/dev/null)"
T2="$(tabela "$PD")"
eq "A: 2ª prosa → parecer_informe codex reprovada" "$(grep '^parecer_informe:' <<<"$T2")" "parecer_informe: codex reprovada"
eq "A: lane reprovada → status usable=false" "$(campo "$PD/.intent/.status-c1-codex.json" .usable)" false
eq "A: lane reprovada → rc_reason=parecer_informe" "$(campo "$PD/.intent/.status-c1-codex.json" .rc_reason)" parecer_informe
[ -f "$PD/pareceres/.reformat-codex-c1.reprovada" ] && ok "A: marcador .reprovada gravado" || falha "A: .reprovada" "ausente"
RL="$PD/01-RUN-LOG.jsonl"
N_INC=$(grep -c '"evento":"incidente".*"origem":"confere-ciclo.sh","detalhe":"lane codex c1: parecer sem achados 2×"' "$RL" 2>/dev/null || echo 0)
eq "A: incidente no run-log (origem=confere-ciclo.sh)" "$N_INC" 1
tabela "$PD" >/dev/null
eq "A: re-rodar a tabela não duplica o incidente" "$(grep -c '"evento":"incidente"' "$RL")" 1
RC=0; STUB_CFG="$CFG" bash "$LANES" "$PD" 01 1 "$PD/.intent/briefing-c1.md" \
  --prova "$PD/.intent/.prova-leitura-c1.txt" --lanes codex --reformata codex >/dev/null 2>&1 || RC=$?
eq "A: 3ª tentativa (--reformata de novo) → exit 4" "$RC" 4
: > "$PD/.intent/.vereditos-c1.txt"
D="$(cd "$BASE" && bash "$DECIDE" "$PD" 1 2>/dev/null | tail -1)"
eq "A: decide-ciclo com lane reprovada NÃO dá para-zerou" "$(jq -r .decisao <<<"$D")" continua
eq "A: decide-ciclo lista a lane reprovada" "$(jq -r '.lanes_reprovadas|join(",")' <<<"$D")" codex
D4="$(cd "$BASE" && bash "$DECIDE" "$PD" 4 2>/dev/null | tail -1)"   # sem vereditos do c4 → exit 3
eq "A: controle — sem vereditos o decide-ciclo segue exit 3 (sem_dados)" "$(jq -r .decisao <<<"$D4")" sem_dados

# cenário B: prosa 1×, gabarito certo na 2ª → ciclo segue com os achados da 2ª
PD="$(monta_fase)"; CFG="$PD/cfg"; cfg "$CFG" codex "NONCE=sim" "CORPO=$PROSA"
roda_lane "$PD" "$CFG" >/dev/null
eq "B: 1ª prosa → devolver" "$(tabela "$PD" | grep '^parecer_informe:')" "parecer_informe: codex devolver"
BOM="$BASE/bom.md"
printf '### Achado 1 [B-viabilidade] — AC-41 contradiz a travessia\nEvidência: src/x.py:3\n### Achado 2 [D-documental] — contagem errada\nEvidência: SPEC.md:9\n' > "$BOM"
cfg "$CFG" codex "NONCE=sim" "CORPO=$BOM"
roda_lane "$PD" "$CFG" --reformata codex >/dev/null
T="$(tabela "$PD")"
eq "B: 2ª no gabarito → 2 achados contados" "$(sed -n 's/^achados_estruturais_total: *//p' <<<"$T")" 2
grep -q '^parecer_informe:' <<<"$T" && falha "B: parecer_informe indevido" "$T" || ok "B: sem parecer_informe na 2ª"
eq "B: status segue usable=true" "$(campo "$PD/.intent/.status-c1-codex.json" .usable)" true
[ -f "$PD/pareceres/.reformat-codex-c1.reprovada" ] && falha "B: .reprovada indevido" "" || ok "B: sem marcador .reprovada"
printf 'c1-A1 | novo | confirmado | B-viabilidade\n' > "$PD/.intent/.vereditos-c1.txt"
D="$(cd "$BASE" && bash "$DECIDE" "$PD" 1 2>/dev/null | tail -1)"
eq "B: decide-ciclo segue pelos achados da 2ª (continua, 0 reprovadas)" "$(jq -r '.decisao + "/" + (.lanes_reprovadas|length|tostring)' <<<"$D")" continua/0

# cenário C: `### Achado 0 — nenhum achado novo` = zero achados, parecer válido
PD="$(monta_fase)"; CFG="$PD/cfg"; ZERO="$BASE/zero.md"
{ echo "### Achado 0 — nenhum achado novo"; for i in $(seq 1 14); do echo "Justificativa $i: conferi src/x.py:$i e a emenda fecha."; done; } > "$ZERO"
cfg "$CFG" codex "NONCE=sim" "CORPO=$ZERO"
roda_lane "$PD" "$CFG" >/dev/null
T="$(tabela "$PD")"
eq "C: Achado 0 → total 0" "$(sed -n 's/^achados_estruturais_total: *//p' <<<"$T")" 0
eq "C: Achado 0 → sem_achado_novo, não parecer_informe" "$(grep -E '^(parecer_informe|sem_achado_novo):' <<<"$T")" "sem_achado_novo: codex"
: > "$PD/.intent/.vereditos-c1.txt"
D="$(cd "$BASE" && bash "$DECIDE" "$PD" 1 2>/dev/null | tail -1)"
eq "C: decide-ciclo converge (para-zerou) com Achado 0" "$(jq -r .decisao <<<"$D")" para-zerou

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
