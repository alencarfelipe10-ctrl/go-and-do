#!/usr/bin/env bash
# roda-lanes.sh — lançador assíncrono das lanes adversariais da intenção (item E4).
#
# Uso: roda-lanes.sh <phase_dir> <NN> <C> <briefing> --prova <arquivo> [--lanes "codex agy"]
#                    [--familia intencao|convergencia]
#      roda-lanes.sh <phase_dir> <NN> <C> <briefing> --prova <arquivo> --reformata <lane>
#                    ^ devolução (P15): relança SÓ a lane cujo parecer o confere-ciclo.sh
#                    marcou `parecer_informe … devolver`, com o briefing original mais o
#                    bloco `## Reformatação obrigatória`, gravado em
#                    `.intent/briefing-c<C>-reformat-<lane>.md`. Grava o marcador durável
#                    `pareceres/.reformat-<lane>-c<C>` (run_id + ts); se ele já existe a
#                    devolução é recusada (exit 4) — a 2ª ocorrência é reprovação da lane,
#                    decidida pelo confere-ciclo.sh, não uma 3ª tentativa (cada relance
#                    custa um ciclo de revisor).
#      roda-lanes.sh --supervisiona <lane> <run_dir> <phase_dir> <NN> <C> <briefing> <prova>
#                    ^ modo INTERNO (o lançador se re-invoca); não chame à mão.
#      roda-lanes.sh <phase_dir> <NN> <C> --esperar [<lane>] [--familia intencao|convergencia]
#                    ^ E4/48(c): bloqueia (loop `until … sleep`, sancionado) até o(s)
#                    `.status-c<C>-<lane>.json` do ciclo ATUAL existirem e terem o MESMO
#                    `run_id` do ponteiro `.run-atual-c<C>` — um status de RUN ANTERIOR do
#                    mesmo ciclo (sobreposição) não conta como pronto (mesma checagem que o
#                    passo 0 do intent-verifica.md faz à mão). Sem `<lane>`, espera as lanes
#                    do PRÓPRIO run atual (lidas de `runs/c<C>/<run_id>/supervisor-*.out`,
#                    que nascem no lançamento — nunca `GAD_LANES_LANES`/"codex agy" fixo: uma
#                    devolução P15 `--reformata codex` troca o run-atual para um que só tem
#                    codex, e esperar as duas de sempre travaria 590 s pelo agy de um run que
#                    não existe); com `<lane>` (codex|agy), espera só aquela — permite ao
#                    verificador processar o parecer do Codex
#                    enquanto ainda espera o agy (o overlap documentado no passo 0). Teto
#                    `GAD_ESPERAR_TIMEOUT` (default e MÁXIMO 590 — a tool Bash mata em 600 s);
#                    passo `GAD_ESPERAR_PASSO` (default 15 s). Imprime 1 linha JSON no fim.
#                    Exit: 0 = pronto · 124 = timeout · 2 = uso errado (ponteiro do ciclo
#                    ausente, ou argumento faltando).
#
# O que resolve: hoje `roda-codex.sh`/`roda-agy.sh` gravam em caminhos canônicos fixos
# (`pareceres/NN-parecer-<lane>-c<C>.md`, `.roda-<lane>-c<C>.json`, `.log`, `.err`), então
# dois runs sobrepostos do mesmo ciclo misturam parecer e evidência de modelo. Aqui cada
# invocação ganha um `run_id` e TUDO que ela produz vive em
#   <phase_dir>/.intent/runs/c<C>/<run_id>/
# (parecer, espelho, log, err, status). Os caminhos canônicos viram ALIASES, promovidos
# só pelo supervisor que ainda é dono do `run_id` gravado no ponteiro
# `<phase_dir>/.intent/.run-atual-c<C>` — checagem e promoção sob o MESMO lock por ciclo
# (`mkdir` + PID gravado + detecção de lock órfão por `kill -0`). Supervisor órfão
# publica só no run-dir dele e sai; o run-dir é imutável depois de finalizado, então um
# verificador antigo continua lendo o run antigo intacto.
#
# Retorna em < 1 s com `{run_id, pids, status_paths}` no stdout. Os supervisores seguem
# vivos: `nohup … & disown`, com stdin/stdout/stderr redirecionados EXPLICITAMENTE para
# arquivos do run-dir — `nohup` só redireciona o que está ligado a terminal, e sob o pipe
# do Bash tool o descritor herdado manteria a tool aberta.
#
# Dois eixos no status (a FÓRMULA é a autoridade, não o exit code da lane):
#   usable      = parecer_nao_vazio && fresco && parecer_legivel
#   independent = nonce_ok && modelo_ok
# Espelho ausente/malformado com parecer íntegro → `usable:true, mirror_valid:false` e
# `modelo_ok:false` (sem espelho não há evidência de modelo) → `independent:false`; o
# conteúdo do parecer é MANTIDO. rc 6 só por modelo divergente → `usable:true,
# independent:false`. rc 5 (CLI ausente), timeout, morte do filho sem parecer válido,
# stdout vazio, parecer obsoleto ou ilegível → `usable:false`.
#   nonce_ok — o supervisor confere, para TODAS as lanes por igual, se o token de
#     `--prova` (extraído com `grep -oE 'PROVA-[0-9a-f]+'`) aparece no parecer; o
#     `prova_leitura: ok` do espelho, quando existe, tem precedência.
#   modelo_ok — `!degradado` do espelho (o `roda-agy.sh` compara a evidência de modelo do
#     log). O `roda-codex.sh` não emite `degradado`: sem o campo, `modelo_ok` é true e o
#     banner fica no espelho como evidência.
#   `log` no status é `null` quando a lane não escreveu log (caso do codex, cuja evidência
#     de modelo é o banner do stderr) — nunca um caminho que não existe.
#
# Ordem obrigatória no fim: status (tmp + `mv` dentro do run-dir) ANTES do alias `.done`
# — o `intent-verifica.md` passo 0 ainda espera marcador, e status meio-escrito atrás de
# um marcador precoce seria regressão.
#
# ⚠️ SIGKILL no SUPERVISOR não é trapável (rc 137). Nesse caso nenhum status é gravado e
# só o deadline do verificador recupera — não há promessa de status aqui.
#
# Ambiente (bancada): GAD_LANES_DIR = diretório dos `roda-<lane>.sh` (default: o deste
# script) · GAD_LANES_LANES = lista de lanes (default "codex agy") · GAD_LANE_TIMEOUT =
# teto em segundos do filho (default 660; os `roda-*.sh` já têm o seu de 600).
#
# Família (v2.6.0, 45 m/45 j): a MESMA mecânica serve as duas rodadas de revisão da fase.
#   intencao     (default) — base `<phase_dir>/.intent`, aliases `NN-parecer-<lane>-c<C>.md`
#                            e `.roda-<lane>-c<C>.json`. Comportamento histórico, byte a byte.
#   convergencia            — base `<phase_dir>/.convergencia`, aliases
#                            `NN-planrev-parecer-<lane>-c<C>.md` e `.roda-planrev-<lane>-c<C>.json`.
# Sem isso a 2.5 sobrescrevia o espelho da 1 no mesmo ciclo: na F24.5 os pareceres saíram com
# nomes distintos e os espelhos NÃO (um só `.roda-codex-c1.json` para as duas etapas).
#
# Exit do lançador: 0 = lanes lançadas · 2 = uso.

set -uo pipefail

GAD_LANES_SELF="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/$(basename -- "${BASH_SOURCE[0]}")"
# B1 (F4 RLR): sourcear o shim só pelo helper gad_autoregistro (gap apontado pelo R2 —
# o lançador não gravava evento `script` nenhum). Sourcear nunca falha (resolução do
# gsd-tools é lazy) — os dois `set` (aqui `-uo`, no shim `-euo`) não colidem porque o
# shim não muda `set` do caller.
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# Lock por ciclo (mkdir + PID) — com detecção de lock órfão
# ═══════════════════════════════════════════════════════════════════════════════
lane_lock() { # <lockdir> [tentativas]
  local ld="$1" tries="${2:-60}" i pid vazias=0
  for ((i = 0; i < tries; i++)); do
    if mkdir "$ld" 2>/dev/null; then
      echo $$ > "$ld/pid"
      return 0
    fi
    pid="$(cat "$ld/pid" 2>/dev/null || true)"
    if [ -z "$pid" ]; then
      # Janela entre o `mkdir` do dono e a gravação do pid: NÃO é lock órfão. Só depois
      # de 2 s de pid vazio o lock é dado como perdido (senão dois donos convivem).
      vazias=$((vazias + 1))
      [ "$vazias" -ge 20 ] && { rm -rf "$ld" 2>/dev/null || true; vazias=0; }
      sleep 0.1; continue
    fi
    vazias=0
    if ! kill -0 "$pid" 2>/dev/null; then
      # lock órfão: o dono morreu (kill -9) sem soltar. Remove e tenta de novo.
      rm -rf "$ld" 2>/dev/null || true
      continue
    fi
    sleep 0.1
  done
  return 1
}
lane_unlock() { rm -rf "${1:-}" 2>/dev/null || true; }

# ═══════════════════════════════════════════════════════════════════════════════
# Família de artefatos (45 m/45 j) — escritor único dos caminhos, para que supervisor
# e lançador nunca discordem sobre onde mora o run e como se chama o alias.
# ═══════════════════════════════════════════════════════════════════════════════
# v2.10.1 (57): os caminhos saem do helper único (lib/gad-caminhos.sh), conforme o formato
# da fase — `.gad/intent/c<C>/…` no novo, `.intent/.<x>-c<C>…` no antigo.
fam_tipo()   { case "$1" in convergencia) printf 'convergencia' ;; *) printf 'intent' ;; esac; }
fam_base()   { gad_fase_caminho "$2" "$(fam_tipo "$1")"; }
fam_arq()    { gad_fase_caminho "$2" "$(fam_tipo "$1")/c$3/$4"; }   # <fam> <pd> <C> <nome>
fam_prefixo(){ case "$1" in convergencia) printf 'planrev-' ;; *) printf '' ;; esac; }

# ═══════════════════════════════════════════════════════════════════════════════
# Modo ESPERAR (E4/48c) — espera sancionada do run ATUAL do ciclo, por lane ou por todas.
# ═══════════════════════════════════════════════════════════════════════════════
if [ "${4:-}" = "--esperar" ]; then
  PD="${1:-}"; NN="${2:-}"; C="${3:-}"
  shift 4
  LANE_ESP=""; FAMILIA_ESP="intencao"
  if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then LANE_ESP="$1"; shift; fi
  while [ $# -gt 0 ]; do case "$1" in
    --familia) FAMILIA_ESP="${2:-}"; shift 2 ;;
    *) echo "uso: roda-lanes.sh <phase_dir> <NN> <C> --esperar [<lane>] [--familia intencao|convergencia]" >&2; exit 2 ;;
  esac; done
  case "$FAMILIA_ESP" in intencao|convergencia) : ;; *)
    echo "uso: --familia deve ser intencao|convergencia (recebido: '$FAMILIA_ESP')" >&2; exit 2 ;;
  esac
  [ -n "$PD" ] && [ -n "$NN" ] && [ -n "$C" ] \
    || { echo "uso: roda-lanes.sh <phase_dir> <NN> <C> --esperar [<lane>] [--familia intencao|convergencia]" >&2; exit 2; }

  INTENT_ESP="$(fam_base "$FAMILIA_ESP" "$PD")"
  PONTEIRO_ESP="$(fam_arq "$FAMILIA_ESP" "$PD" "$C" run-atual)"
  [ -f "$PONTEIRO_ESP" ] \
    || { echo "ERRO: nenhuma rodada de lanes lançada para o ciclo $C (ponteiro ausente: $PONTEIRO_ESP) — chame o lançador antes de esperar" >&2; exit 2; }
  RUN_ATUAL="$(cat "$PONTEIRO_ESP" 2>/dev/null || true)"
  [ -n "$RUN_ATUAL" ] || { echo "ERRO: ponteiro de ciclo vazio ($PONTEIRO_ESP)" >&2; exit 2; }

  # Sem `<lane>`: deriva do PRÓPRIO run — não de GAD_LANES_LANES/"codex agy" fixo. Uma
  # devolução (P15, `--reformata codex`) troca o `.run-atual-c<C>` para um run que só tem
  # o codex; esperar as duas de sempre ficaria preso 590 s esperando o agy de um run que
  # nunca existiu. `supervisor-<lane>.out` nasce por `nohup … >>arquivo` no MOMENTO do
  # lançamento (antes de qualquer status) — é o inventário real e imediato do run.
  RUN_DIR_ESP="$(fam_arq "$FAMILIA_ESP" "$PD" "$C" "runs/$RUN_ATUAL")"
  LANES_ESP="$LANE_ESP"
  if [ -z "$LANES_ESP" ] && [ -d "$RUN_DIR_ESP" ]; then
    for sf in "$RUN_DIR_ESP"/supervisor-*.out; do
      [ -f "$sf" ] || continue
      b=$(basename -- "$sf"); b=${b#supervisor-}; b=${b%.out}
      LANES_ESP="${LANES_ESP:+$LANES_ESP }$b"
    done
  fi
  LANES_ESP="${LANES_ESP:-${GAD_LANES_LANES:-codex agy}}"
  TETO="${GAD_ESPERAR_TIMEOUT:-590}"
  case "$TETO" in ''|*[!0-9]*) TETO=590 ;; esac
  [ "$TETO" -gt 590 ] && TETO=590
  PASSO="${GAD_ESPERAR_PASSO:-15}"
  case "$PASSO" in ''|*[!0-9]*) PASSO=15 ;; esac

  T0=$(date +%s)
  for LN in $LANES_ESP; do
    ALIAS_STATUS="$(fam_arq "$FAMILIA_ESP" "$PD" "$C" "status-$LN.json")"
    # run_id tem de casar com o ponteiro ATUAL: um status de run anterior do mesmo ciclo
    # (sobreposição, ver cabeçalho do lançador) não conta como pronto.
    until [ -s "$ALIAS_STATUS" ] && [ "$(jq -r '.run_id // empty' "$ALIAS_STATUS" 2>/dev/null)" = "$RUN_ATUAL" ]; do
      NOW=$(date +%s)
      if [ $((NOW - T0)) -ge "$TETO" ]; then
        jq -cn --arg lane "$LN" --arg run "$RUN_ATUAL" --argjson el "$((NOW - T0))" \
          '{esperado:false, lane:$lane, run_id:$run, motivo:"timeout", elapsed_s:$el}'
        exit 124
      fi
      sleep "$PASSO"
    done
  done
  NOW=$(date +%s)
  jq -cn --arg run "$RUN_ATUAL" --argjson el "$((NOW - T0))" \
    --argjson lanes "$(printf '%s\n' $LANES_ESP | jq -R . | jq -cs .)" \
    '{esperado:true, run_id:$run, lanes:$lanes, elapsed_s:$el}'
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Modo SUPERVISOR (interno)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "${1:-}" = "--supervisiona" ]; then
  LANE="${2:-}"; RUN_DIR="${3:-}"; PD="${4:-}"; NN="${5:-}"; C="${6:-}"
  BRIEF="${7:-}"; PROVA="${8:-}"
  [ -n "$LANE" ] && [ -d "${RUN_DIR:-/nao-existe}" ] \
    || { echo "uso interno inválido" >&2; exit 2; }

  RUN_ID="$(basename -- "$RUN_DIR")"
  FAMILIA="${9:-intencao}"
  INTENT="$(fam_base "$FAMILIA" "$PD")"
  PREFIXO="$(fam_prefixo "$FAMILIA")"
  LOCK="$(fam_arq "$FAMILIA" "$PD" "$C" lock)"
  PONTEIRO="$(fam_arq "$FAMILIA" "$PD" "$C" run-atual)"

  PARECER="$RUN_DIR/parecer-$LANE.md"
  ESPELHO="$RUN_DIR/espelho-$LANE.json"
  LOG="$RUN_DIR/$LANE.log"
  ERR="$RUN_DIR/$LANE.err"
  STATUS="$RUN_DIR/status-$LANE.json"
  TMP_P="$RUN_DIR/.tmp-parecer-$LANE.md"
  TMP_E="$RUN_DIR/.tmp-espelho-$LANE.json"

  STATUS_ESCRITO=0

  grava_status() { # <rc> <rc_reason> <usable> <independent> <nonce_ok> <modelo_ok> <mirror_valid>
    jq -cn \
      --arg run_id "$RUN_ID" --arg rc "$1" --arg rr "$2" \
      --argjson u "$3" --argjson ind "$4" --argjson n "$5" --argjson m "$6" --argjson mv "$7" \
      --arg p "$PARECER" --arg e "$ESPELHO" --arg er "$ERR" \
      --argjson lg "$([ -s "$LOG" ] && jq -Rn --arg l "$LOG" '$l' || echo null)" \
      --arg lane "$LANE" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{run_id:$run_id, lane:$lane, complete:true, rc:($rc|tonumber), rc_reason:$rr,
        usable:$u, independent:$ind, nonce_ok:$n, modelo_ok:$m, mirror_valid:$mv,
        parecer:$p, espelho:$e, log:$lg, err:$er, ts:$ts}' > "$STATUS.tmp" \
      && mv -f "$STATUS.tmp" "$STATUS" && STATUS_ESCRITO=1
  }

  # Rede de segurança: qualquer saída anômala (menos SIGKILL) ainda deixa um status
  # completo — verificador esperando 12 min por nada é exatamente o que o E4 mata.
  # B1 (F4 RLR, gap apontado pelo R2): o supervisor é o único lugar com o exit REAL da
  # lane (o lançador volta em <1s, antes de a lane terminar) — grava o evento `script`
  # aqui, sempre, mesmo em abort. `rc` capturado ANTES de qualquer outro comando (mesma
  # lição do trap do confere-etapa.sh/spot-check: "$?" solto no corpo do trap pegaria o
  # exit do comando anterior do trap, não o do script).
  # gad_autoregistro resolve a raiz por $PWD (sem parâmetro de root) — o supervisor
  # nasce de `nohup … & disown` e pode herdar um cwd que não é a raiz do projeto; o
  # subshell com `cd "$PD"` (a pasta da fase, sempre dentro da raiz) garante a raiz
  # certa sem mexer no gsd-shim.sh.
  trap 'rc=$?; [ "$STATUS_ESCRITO" = 1 ] || grava_status 99 supervisor_abortou false false false false false; ( cd "$PD" 2>/dev/null && gad_autoregistro "roda-lanes.sh" "$rc" "lane=$LANE familia=$FAMILIA usable=${USABLE:-?} independent=${INDEPENDENT:-?}" )' EXIT

  LANES_DIR="${GAD_LANES_DIR:-$(dirname -- "$GAD_LANES_SELF")}"
  SCRIPT_LANE="$LANES_DIR/roda-$LANE.sh"
  if [ ! -f "$SCRIPT_LANE" ]; then
    grava_status 127 lane_inexistente false false false false false
    exit 0
  fi

  T0=$(date +%s)
  timeout "${GAD_LANE_TIMEOUT:-660}" bash "$SCRIPT_LANE" "$PD" "$NN" "$C" "$BRIEF" \
    --out "$TMP_P" --espelho "$TMP_E" --log "$LOG" --err "$ERR" \
    ${PROVA:+--prova "$PROVA"} </dev/null >/dev/null 2>>"$RUN_DIR/supervisor-$LANE.err"
  RC=$?

  # (3) finaliza tmp → caminhos estáveis do run-dir. Daqui em diante o run-dir é imutável.
  [ -e "$TMP_P" ] && mv -f "$TMP_P" "$PARECER"
  [ -e "$TMP_E" ] && mv -f "$TMP_E" "$ESPELHO"

  # FM-F4RLR-03CONV: o campo `parecer` do próprio espelho nasce apontando para o caminho
  # TEMPORÁRIO ($TMP_P), que o passo (3) acabou de apagar com o `mv`. Corrigir para o
  # caminho definitivo assim que ele existe — antes disso o espelho mente sobre onde o
  # parecer mora (e um consumidor que confiasse nele acharia arquivo inexistente).
  if [ -s "$ESPELHO" ] && jq -e 'has("parecer")' "$ESPELHO" >/dev/null 2>&1; then
    jq --arg p "$PARECER" '.parecer = $p' "$ESPELHO" > "$ESPELHO.tmp2" 2>/dev/null \
      && mv -f "$ESPELHO.tmp2" "$ESPELHO"
  fi

  # ── (2) valida o espelho e lê os predicados dele ────────────────────────────
  MIRROR_VALID=false; ESP_VAZIO=""; ESP_FRESCO=""; ESP_DEGRADADO=""; ESP_PROVA=""; ESP_AUSENTE=""
  ESP_TEM_EVIDENCIA=false; ESP_EVIDENCIA=""; ESP_PARECER_APONTADO=""
  if [ -s "$ESPELHO" ] && jq -e . "$ESPELHO" >/dev/null 2>&1; then
    ESP_AUSENTE="$(jq -r '.revisor_ausente // empty' "$ESPELHO" 2>/dev/null)"
    if [ -n "$ESP_AUSENTE" ]; then
      MIRROR_VALID=true   # espelho de `revisor_ausente` é válido, só não traz predicados
    elif jq -e 'has("parecer")' "$ESPELHO" >/dev/null 2>&1; then
      MIRROR_VALID=true
      ESP_VAZIO="$(jq -r 'if has("vazio") then (.vazio|tostring) else "" end' "$ESPELHO")"
      ESP_FRESCO="$(jq -r 'if has("fresco") then (.fresco|tostring) else "" end' "$ESPELHO")"
      ESP_DEGRADADO="$(jq -r 'if has("degradado") then (.degradado|tostring) else "" end' "$ESPELHO")"
      ESP_PROVA="$(jq -r '.prova_leitura // empty' "$ESPELHO")"
      # FM-F4RLR-11INT/03CONV: `evidencia` só existe no espelho do agy. Campo AUSENTE
      # (ex.: codex) não afirma nada sobre modelo; campo PRESENTE e vazio é falta real
      # de evidência no log — modelo_ok não pode ficar `true` por omissão nesse caso.
      ESP_TEM_EVIDENCIA="$(jq -r 'has("evidencia")' "$ESPELHO")"
      ESP_EVIDENCIA="$(jq -r '.evidencia // empty' "$ESPELHO")"
      # validação do espelho: o `parecer` que ele aponta precisa existir de fato.
      ESP_PARECER_APONTADO="$(jq -r '.parecer // empty' "$ESPELHO")"
      if [ -n "$ESP_PARECER_APONTADO" ] && [ ! -f "$ESP_PARECER_APONTADO" ]; then
        MIRROR_VALID=false
      fi
    fi
  fi

  # ── predicados do eixo `usable` ─────────────────────────────────────────────
  PARECER_NAO_VAZIO=false; [ -s "$PARECER" ] && PARECER_NAO_VAZIO=true
  if [ "$ESP_VAZIO" = true ]; then PARECER_NAO_VAZIO=false; fi

  FRESCO=false
  if [ "$PARECER_NAO_VAZIO" = true ]; then
    if [ -n "$ESP_FRESCO" ]; then
      [ "$ESP_FRESCO" = true ] && FRESCO=true
    else
      MT=$(stat -c %Y "$PARECER" 2>/dev/null || echo 0)
      [ "$MT" -ge "$T0" ] && FRESCO=true
    fi
  fi

  # ilegível = não legível pelo processo OU com byte NUL (parecer binário/truncado).
  # NUL, e não `chmod 000`: sob root o `-r` é sempre verdadeiro e o teste passaria errado.
  LEGIVEL=false
  if [ -r "$PARECER" ] && [ -s "$PARECER" ]; then
    if [ "$(tr -d '\000' < "$PARECER" | wc -c)" = "$(wc -c < "$PARECER" | tr -d ' ')" ]; then
      LEGIVEL=true
    fi
  fi

  USABLE=false
  [ "$PARECER_NAO_VAZIO" = true ] && [ "$FRESCO" = true ] && [ "$LEGIVEL" = true ] && USABLE=true

  # ── predicados do eixo `independent` ────────────────────────────────────────
  NONCE_OK=false
  if [ "$ESP_PROVA" = ok ]; then
    NONCE_OK=true
  elif [ -n "${PROVA:-}" ] && [ -f "$PROVA" ] && [ "$LEGIVEL" = true ]; then
    TOKEN="$(grep -oE 'PROVA-[0-9a-f]+' "$PROVA" 2>/dev/null | head -1 || true)"
    [ -n "$TOKEN" ] && grep -qF "$TOKEN" "$PARECER" 2>/dev/null && NONCE_OK=true
  fi

  MODELO_OK=true
  [ "$ESP_DEGRADADO" = true ] && MODELO_OK=false
  # FM-F4RLR-11INT: campo `evidencia` presente e vazio (agy sem linha de modelo no log) →
  # não se afirma modelo_ok por omissão, mesmo com degradado=false.
  [ "$ESP_TEM_EVIDENCIA" = true ] && [ -z "$ESP_EVIDENCIA" ] && MODELO_OK=false
  # Sem espelho válido não há evidência de modelo — não se afirma independência.
  [ "$MIRROR_VALID" = false ] && MODELO_OK=false

  INDEPENDENT=false
  [ "$NONCE_OK" = true ] && [ "$MODELO_OK" = true ] && INDEPENDENT=true
  [ "$USABLE" = false ] && INDEPENDENT=false

  # ── rc_reason (diagnóstico; nunca substitui a fórmula) ──────────────────────
  RR=ok
  if [ -n "$ESP_AUSENTE" ] || [ "$RC" = 5 ]; then RR=revisor_ausente
  elif [ "$RC" = 124 ] && [ "$USABLE" = false ]; then RR=timeout
  elif [ "$PARECER_NAO_VAZIO" = false ]; then RR=parecer_vazio
  elif [ "$LEGIVEL" = false ]; then RR=parecer_ilegivel
  elif [ "$FRESCO" = false ]; then RR=parecer_obsoleto
  elif [ "$MIRROR_VALID" = false ]; then RR=espelho_invalido
  elif [ "$ESP_DEGRADADO" = true ]; then RR=modelo_divergente
  elif [ "$NONCE_OK" = false ]; then RR=sem_prova_leitura
  fi

  grava_status "$RC" "$RR" "$USABLE" "$INDEPENDENT" "$NONCE_OK" "$MODELO_OK" "$MIRROR_VALID"

  # ── (4) promoção dos aliases canônicos — só o dono do ponteiro, sob o lock ───
  ALIAS_PARECER="$PD/pareceres/$NN-${PREFIXO}parecer-$LANE-c$C.md"
  ALIAS_ESPELHO="$(gad_fase_caminho "$PD" "lanes/roda-${PREFIXO}$LANE-c$C.json")"
  ALIAS_STATUS="$(fam_arq "$FAMILIA" "$PD" "$C" "status-$LANE.json")"
  ALIAS_DONE="$(fam_arq "$FAMILIA" "$PD" "$C" "done-$LANE")"

  if lane_lock "$LOCK" 100; then
    DONO="$(cat "$PONTEIRO" 2>/dev/null || true)"
    if [ "$DONO" = "$RUN_ID" ]; then
      mkdir -p "$PD/pareceres" "$(dirname -- "$ALIAS_ESPELHO")" "$(dirname -- "$ALIAS_STATUS")"
      # cópia + rename atômico: nunca `mv` do original — o run-dir tem de continuar
      # íntegro para um verificador antigo que ainda esteja lendo.
      [ -e "$PARECER" ] && cp -f "$PARECER" "$ALIAS_PARECER.tmp" && mv -f "$ALIAS_PARECER.tmp" "$ALIAS_PARECER"
      [ -e "$ESPELHO" ] && cp -f "$ESPELHO" "$ALIAS_ESPELHO.tmp" && mv -f "$ALIAS_ESPELHO.tmp" "$ALIAS_ESPELHO"
      cp -f "$STATUS" "$ALIAS_STATUS.tmp" && mv -f "$ALIAS_STATUS.tmp" "$ALIAS_STATUS"
      # o `.done` é o ÚLTIMO — o verificador espera por ele.
      : > "$ALIAS_DONE"
    fi
    lane_unlock "$LOCK"
  fi
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Modo LANÇADOR
# ═══════════════════════════════════════════════════════════════════════════════
PD="${1:-}"; NN="${2:-}"; C="${3:-}"; BRIEF="${4:-}"
PROVA=""; LANES_ARG=""; REFORMATA=""; FAMILIA="intencao"
[ -n "$PD" ] && [ -n "$NN" ] && [ -n "$C" ] && [ -f "${BRIEF:-/nao-existe}" ] \
  || { echo "uso: roda-lanes.sh <phase_dir> <NN> <C> <briefing> --prova <arquivo> [--lanes \"codex agy\"] [--reformata <lane>] [--familia intencao|convergencia]" >&2; exit 2; }
shift 4
while [ $# -gt 0 ]; do case "$1" in
  --prova) PROVA="${2:-}"; shift 2 ;;
  --lanes) LANES_ARG="${2:-}"; shift 2 ;;
  --reformata) REFORMATA="${2:-}"; shift 2 ;;
  --familia) FAMILIA="${2:-}"; shift 2 ;;
  *) shift ;;
esac; done
case "$FAMILIA" in
  intencao|convergencia) : ;;
  *) echo "uso: --familia deve ser intencao|convergencia (recebido: '$FAMILIA')" >&2; exit 2 ;;
esac

# `--prova` é OBRIGATÓRIO: sem o token do briefing nenhuma lane consegue provar leitura,
# e as duas cairiam no fallback do roda-agy.sh — que faz append CONCORRENTE no mesmo
# briefing. Falhar aqui é melhor que um `nonce_ok:false` eterno parecendo culpa do revisor.
[ -n "$PROVA" ] && [ -f "$PROVA" ] \
  || { echo "uso: roda-lanes.sh … --prova <arquivo> (obrigatório; arquivo do briefing-build.sh)" >&2; exit 2; }

LANES="${LANES_ARG:-${GAD_LANES_LANES:-codex agy}}"
INTENT="$(fam_base "$FAMILIA" "$PD")"
LOCK="$(fam_arq "$FAMILIA" "$PD" "$C" lock)"
PONTEIRO="$(fam_arq "$FAMILIA" "$PD" "$C" run-atual)"
gad_fase_lanes_garante "$PD"
mkdir -p "$(fam_arq "$FAMILIA" "$PD" "$C" runs)" "$PD/pareceres" "$(gad_fase_caminho "$PD" lanes)"

RUN_ID="$(date -u +%Y%m%dT%H%M%S)-$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
RUN_DIR="$(fam_arq "$FAMILIA" "$PD" "$C" "runs/$RUN_ID")"

# ── devolução de uma lane (P15) ─────────────────────────────────────────────────
if [ -n "$REFORMATA" ]; then
  MARC="$(gad_fase_caminho "$PD" "lanes/reformat-$(fam_prefixo "$FAMILIA")$REFORMATA-c$C")"
  if [ -e "$MARC" ]; then
    echo "RECUSADO: lane $REFORMATA já foi devolvida uma vez no ciclo $C ($MARC). A 2ª ocorrência de parecer_informe reprova a lane (confere-ciclo.sh --tabela); não há 3ª tentativa." >&2
    exit 4
  fi
  BRIEF_R="$(fam_arq "$FAMILIA" "$PD" "$C" "briefing-reformat-$REFORMATA.md")"
  {
    cat "$BRIEF"
    echo
    echo "## Reformatação obrigatória"
    echo
    echo "Seu parecer anterior neste ciclo foi lido, mas nenhum achado nele segue o gabarito,"
    echo "então o contador mecânico o registrou como zero achados — e zero achados fecha o"
    echo "ciclo como convergência. Reescreva o mesmo parecer no gabarito abaixo, sem"
    echo "acrescentar nem retirar conteúdo."
    echo
    echo "- Cada achado: \`### Achado N [categoria] — título\` (categoria em A-produto,"
    echo "  B-viabilidade, C-instrumentacao, D-documental, E-decisao-do-dono), seguido de"
    echo "  alegação, evidência (arquivo:linha) e confiança."
    echo "- Sem achado novo: escreva literalmente \`### Achado 0 — nenhum achado novo\`."
    echo "- Mantenha a linha \`prova_leitura: <token>\` na primeira linha."
  } > "$BRIEF_R"
  BRIEF="$BRIEF_R"
  LANES="$REFORMATA"
  printf '%s %s\n' "$RUN_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MARC"
fi

mkdir -p "$RUN_DIR"

# ponteiro: `mv` atômico sob o lock do ciclo. O lançador só escreve o ponteiro e solta
# — nunca espera nada antes de imprimir o JSON.
if lane_lock "$LOCK" 100; then
  printf '%s\n' "$RUN_ID" > "$PONTEIRO.tmp" && mv -f "$PONTEIRO.tmp" "$PONTEIRO"
  lane_unlock "$LOCK"
else
  echo "ERRO: não consegui o lock do ciclo $C ($LOCK)" >&2; exit 2
fi

PIDS=(); STATUS_PATHS=()
for LANE in $LANES; do
  nohup bash "$GAD_LANES_SELF" --supervisiona "$LANE" "$RUN_DIR" "$PD" "$NN" "$C" \
    "$BRIEF" "$PROVA" "$FAMILIA" \
    </dev/null >>"$RUN_DIR/supervisor-$LANE.out" 2>&1 &
  PID=$!
  PIDS+=("$PID")
  disown "$PID" 2>/dev/null || true
  STATUS_PATHS+=("$RUN_DIR/status-$LANE.json")
done

jq -cn --arg r "$RUN_ID" --arg d "$RUN_DIR" \
  --argjson p "$(printf '%s\n' "${PIDS[@]}" | jq -Rs 'split("\n")|map(select(length>0)|tonumber)')" \
  --argjson s "$(printf '%s\n' "${STATUS_PATHS[@]}" | jq -Rs 'split("\n")|map(select(length>0))')" \
  '{run_id:$r, run_dir:$d, pids:$p, status_paths:$s}'
