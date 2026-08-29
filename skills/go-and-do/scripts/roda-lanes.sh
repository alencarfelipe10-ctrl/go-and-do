#!/usr/bin/env bash
# roda-lanes.sh — lançador assíncrono das lanes adversariais da intenção (item E4).
#
# Uso: roda-lanes.sh <phase_dir> <NN> <C> <briefing> --prova <arquivo> [--lanes "a b"]
#      roda-lanes.sh --supervisiona <lane> <run_dir> <phase_dir> <NN> <C> <briefing> <prova>
#                    ^ modo INTERNO (o lançador se re-invoca); não chame à mão.
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
# Exit do lançador: 0 = lanes lançadas · 2 = uso.

set -uo pipefail

GAD_LANES_SELF="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/$(basename -- "${BASH_SOURCE[0]}")"

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
# Modo SUPERVISOR (interno)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "${1:-}" = "--supervisiona" ]; then
  LANE="${2:-}"; RUN_DIR="${3:-}"; PD="${4:-}"; NN="${5:-}"; C="${6:-}"
  BRIEF="${7:-}"; PROVA="${8:-}"
  [ -n "$LANE" ] && [ -d "${RUN_DIR:-/nao-existe}" ] \
    || { echo "uso interno inválido" >&2; exit 2; }

  RUN_ID="$(basename -- "$RUN_DIR")"
  INTENT="$PD/.intent"
  LOCK="$INTENT/.lock-c$C"
  PONTEIRO="$INTENT/.run-atual-c$C"

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
  trap '[ "$STATUS_ESCRITO" = 1 ] || grava_status 99 supervisor_abortou false false false false false' EXIT

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

  # ── (2) valida o espelho e lê os predicados dele ────────────────────────────
  MIRROR_VALID=false; ESP_VAZIO=""; ESP_FRESCO=""; ESP_DEGRADADO=""; ESP_PROVA=""; ESP_AUSENTE=""
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
  ALIAS_PARECER="$PD/pareceres/$NN-parecer-$LANE-c$C.md"
  ALIAS_ESPELHO="$PD/pareceres/.roda-$LANE-c$C.json"
  ALIAS_STATUS="$INTENT/.status-c$C-$LANE.json"
  ALIAS_DONE="$INTENT/.done-c$C-$LANE"

  if lane_lock "$LOCK" 100; then
    DONO="$(cat "$PONTEIRO" 2>/dev/null || true)"
    if [ "$DONO" = "$RUN_ID" ]; then
      mkdir -p "$PD/pareceres"
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
PROVA=""; LANES_ARG=""
[ -n "$PD" ] && [ -n "$NN" ] && [ -n "$C" ] && [ -f "${BRIEF:-/nao-existe}" ] \
  || { echo "uso: roda-lanes.sh <phase_dir> <NN> <C> <briefing> --prova <arquivo> [--lanes \"codex agy\"]" >&2; exit 2; }
shift 4
while [ $# -gt 0 ]; do case "$1" in
  --prova) PROVA="${2:-}"; shift 2 ;;
  --lanes) LANES_ARG="${2:-}"; shift 2 ;;
  *) shift ;;
esac; done

# `--prova` é OBRIGATÓRIO: sem o token do briefing nenhuma lane consegue provar leitura,
# e as duas cairiam no fallback do roda-agy.sh — que faz append CONCORRENTE no mesmo
# briefing. Falhar aqui é melhor que um `nonce_ok:false` eterno parecendo culpa do revisor.
[ -n "$PROVA" ] && [ -f "$PROVA" ] \
  || { echo "uso: roda-lanes.sh … --prova <arquivo> (obrigatório; arquivo do briefing-build.sh)" >&2; exit 2; }

LANES="${LANES_ARG:-${GAD_LANES_LANES:-codex agy}}"
INTENT="$PD/.intent"
LOCK="$INTENT/.lock-c$C"
PONTEIRO="$INTENT/.run-atual-c$C"
mkdir -p "$INTENT/runs/c$C" "$PD/pareceres"

RUN_ID="$(date -u +%Y%m%dT%H%M%S)-$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
RUN_DIR="$INTENT/runs/c$C/$RUN_ID"
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
    "$BRIEF" "$PROVA" \
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
