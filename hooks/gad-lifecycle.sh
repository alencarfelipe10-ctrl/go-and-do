#!/usr/bin/env bash
# gad-lifecycle.sh — hook PreToolUse/PostToolUse (matcher Agent|Task|SendMessage) da go-and-do.
# Decisões G.2/T.2 do gad-major-update: o ciclo de vida de TODO despacho de subagente
# entra no run-log SEM participação do modelo — PreToolUse grava `despacho`, PostToolUse
# grava `retorno`, com camada de origem (0→1 vs 1→2), agente e modelo/effort. Escritor
# único: este hook é o ÚNICO escritor de despacho/retorno. Desde a auditoria da F24
# (10/08) o SendMessage também entra: retomada de subagente vivo gera despacho/retorno
# com "retomada":true (o 2º retorno do gad-intent pós-gate ficava invisível).
#
# Instalação (fora do repo — passo documentado no README):
#   ln -s <clone>/hooks/gad-lifecycle.sh ~/.claude/hooks/gad-lifecycle.sh
#   + registro no ~/.claude/settings.json (PreToolUse e PostToolUse, matcher
#     "Agent|Task|SendMessage")
#
# Vive no settings GLOBAL e dispara em qualquer sessão/projeto — por isso os guards
# (PC-3): acha o ponteiro leve .planning/.gad-rodada-ativa.json a partir do cwd
# (1 stat; fallback raiz git), compara session_id e verifica que a rodada não parou.
# Qualquer guard falhando → no-op em milissegundos, exit 0 SEMPRE (telemetria jamais
# bloqueia um despacho).
#
# ── Camada de origem (fix da falha 1 da auditoria F24, 10/08) ─────────────────────────
# O transcript_path do input é SEMPRE o da sessão principal — mesmo quando quem despacha
# é um subagente (F24: 34/34 eventos saíram camada 0, incluindo 12 filhos de spawnDepth
# 2). A detecção real:
#   retorno  — o meta.json do subagente (subagents/agent-*.meta.json) casa pelo
#              tool_use_id e traz spawnDepth (camada = spawnDepth-1) e model. Fonte
#              autoritativa, mecânica.
#   despacho — o meta ainda não existe no PreToolUse; a camada vem da contagem de
#              despachos ABERTOS (sem retorno) no run-log cujo agente tem capacidade de
#              despachar (def com `Agent` em tools:, ou general-purpose). Camada 0
#              despacha com 0 hosts abertos; um host de camada 1 aberto ⇒ o novo
#              despacho nasce dele (camada 1). Heurística: colide só se dois hosts
#              rodarem em paralelo (a camada 1 é serial por construção).

IN=$(cat 2>/dev/null) || exit 0
[ -n "$IN" ] || exit 0

CWD=$(jq -r '.cwd // empty' <<<"$IN" 2>/dev/null) || exit 0
[ -n "$CWD" ] || exit 0

P="$CWD/.planning/.gad-rodada-ativa.json"
if [ ! -f "$P" ]; then
  ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
  P="$ROOT/.planning/.gad-rodada-ativa.json"
  [ -f "$P" ] || exit 0
fi

SESS=$(jq -r '.session_id // empty' <<<"$IN" 2>/dev/null)
PSESS=$(jq -r '.session_id // empty' "$P" 2>/dev/null)
[ -n "$SESS" ] && [ "$SESS" = "$PSESS" ] || exit 0

RL=$(jq -r '.runlog // empty' "$P"); NN=$(jq -r '.nn // empty' "$P")
PD=$(jq -r '.phase_dir // empty' "$P")
[ -n "$RL" ] && [ -n "$NN" ] && [ -n "$PD" ] || exit 0
# rodada pausada (stop foi o último evento) → no-op; o ponteiro some no stop, este é
# só o cinto de segurança para corrida entre o stop e a remoção
[ -f "$RL" ] && tail -n1 "$RL" 2>/dev/null | grep -q '"evento":"stop"' && exit 0

RUNLOG_SH="$HOME/.claude/skills/go-and-do/scripts/run-log.sh"
[ -f "$RUNLOG_SH" ] || exit 0

EV=$(jq -r '.hook_event_name // empty' <<<"$IN")
case "$EV" in
  PreToolUse)  TIPO=despacho ;;
  PostToolUse) TIPO=retorno ;;
  *) exit 0 ;;
esac

TOOL=$(jq -r '.tool_name // empty' <<<"$IN")
TUID=$(jq -r '.tool_use_id // empty' <<<"$IN")
TP=$(jq -r '.transcript_path // ""' <<<"$IN")
SUBDIR="${TP%.jsonl}/subagents"

RETOMADA=0
if [ "$TOOL" = "SendMessage" ]; then
  # retomada de subagente vivo (SendMessage): alvo = campo `to`; mensagens para fora
  # (outras sessões/canais) não têm meta local e caem no fallback camada 0 — aceitável,
  # a origem da retomada é a camada 0 mesmo.
  RETOMADA=1
  AG=$(jq -r '.tool_input.to // "?"' <<<"$IN" | tr -cd 'A-Za-z0-9_ ().-' | head -c 60)
  DESC=$(jq -r '.tool_input.message // ""' <<<"$IN" | head -c 120)
else
  AG=$(jq -r '.tool_input.subagent_type // "general-purpose"' <<<"$IN")
  DESC=$(jq -r '.tool_input.description // ""' <<<"$IN" | head -c 120)
fi

# def do agente tem capacidade de despacho? (tools: com Agent; sem def = general-purpose
# ou agente desconhecido de tools irrestritas → capaz)
despacha() {
  local ag="$1" def linha
  for def in "$HOME/.claude/agents/$ag.md" "$CWD/.claude/agents/$ag.md"; do
    if [ -f "$def" ]; then
      linha=$(grep -m1 -E '^tools:' "$def")
      [ -z "$linha" ] && return 0          # sem linha tools: = herda tudo
      grep -qE '(^|[ ,])Agent([ ,]|$)' <<<"$linha" && return 0 || return 1
    fi
  done
  return 0
}

# camada heurística (Pre): nº de hosts despachadores com janela aberta no run-log.
# $1 opcional = agente a excluir (o próprio, no fallback do Post).
camada_heuristica() {
  local excl="${1:-}" ag n=0
  while IFS= read -r ag; do
    [ -n "$ag" ] || continue
    [ "$ag" = "$excl" ] && continue
    despacha "$ag" && n=$((n+1))
  done < <(jq -rs '
    [ .[] | select(.evento=="despacho" or .evento=="retorno") | select(.origem=="hook") ]
    | group_by(.agente + "|" + (.descricao // ""))
    | map(select(([.[] | select(.evento=="despacho")] | length)
               > ([.[] | select(.evento=="retorno")]  | length)))
    | .[][0].agente' "$RL" 2>/dev/null)
  [ "$n" -gt 2 ] && n=2
  echo "$n"
}

CAM=""; MODELO=""; EFFORT=""

# modelo do transcript do subagente: último request tem message.model — cobre o
# meta.json com "model":null (caso real F24: 12 retornos de general-purpose sem campo)
modelo_do_jsonl() {
  local j="$1"
  [ -f "$j" ] && grep -o '"model":"[^"]*"' "$j" 2>/dev/null | tail -n1 \
    | sed 's/.*:"\(.*\)"/\1/'
}

# retorno: meta.json do subagente é a fonte autoritativa (tool_use_id ↔ toolUseId)
if [ "$TIPO" = retorno ] && [ -n "$TUID" ] && [ -d "$SUBDIR" ]; then
  META=$(grep -l "\"toolUseId\":\"$TUID\"" "$SUBDIR"/*.meta.json 2>/dev/null | head -n1)
  if [ -n "$META" ]; then
    SD=$(jq -r '.spawnDepth // empty' "$META" 2>/dev/null)
    case "$SD" in (''|*[!0-9]*) ;; (*) CAM=$((SD-1)) ;; esac
    MODELO=$(jq -r '.model // empty' "$META" 2>/dev/null)
    [ -n "$MODELO" ] || MODELO=$(modelo_do_jsonl "${META%.meta.json}.jsonl")
  fi
fi
# retomada por SendMessage: meta do agentType alvo, ou — quando o `to` é o id hex do
# agente (retomada de subagente sem nome, F24: 5 pares aXXXX… sem campo) — pelo arquivo
if [ -z "$CAM" ] && [ "$RETOMADA" = 1 ] && [ -d "$SUBDIR" ]; then
  META=$(grep -l "\"agentType\":\"${AG%% *}\"" "$SUBDIR"/*.meta.json 2>/dev/null | tail -n1)
  if [ -z "$META" ]; then
    case "${AG%% *}" in
      (a[0-9a-f]*) META=$(ls "$SUBDIR/agent-${AG%% *}"*.meta.json 2>/dev/null | head -n1) ;;
    esac
  fi
  if [ -n "$META" ]; then
    SD=$(jq -r '.spawnDepth // empty' "$META" 2>/dev/null)
    case "$SD" in (''|*[!0-9]*) ;; (*) CAM=$((SD-1)) ;; esac
    MODELO=$(jq -r '.model // empty' "$META" 2>/dev/null)
    [ -n "$MODELO" ] || MODELO=$(modelo_do_jsonl "${META%.meta.json}.jsonl")
  fi
fi
# despacho (ou fallback do retorno sem meta): heurística dos hosts abertos
if [ -z "$CAM" ]; then
  if [ "$TIPO" = retorno ]; then CAM=$(camada_heuristica "$AG"); else CAM=$(camada_heuristica); fi
fi

# model explícito da chamada (fix da regressão 72% da F24: os gsd-* recebem o modelo
# por parâmetro do orquestrador — as defs deles NÃO têm `model:` — e o hook não lia)
if [ -z "$MODELO" ] && [ "$TOOL" != "SendMessage" ]; then
  MODELO=$(jq -r '.tool_input.model // empty' <<<"$IN")
fi

# modelo/effort da def do agente quando meta/chamada não trouxeram
if [ -z "$MODELO" ]; then
  for DEF in "$HOME/.claude/agents/${AG%% *}.md" "$CWD/.claude/agents/${AG%% *}.md"; do
    if [ -f "$DEF" ]; then
      MODELO=$(grep -m1 -E '^model:' "$DEF" | sed 's/^model:[[:space:]]*//' | tr -d ' \r')
      EFFORT=$(grep -m1 -E '^(effort|reasoning_effort):' "$DEF" | sed 's/^[a-z_]*:[[:space:]]*//' | tr -d ' \r')
      break
    fi
  done
fi

# ainda vazio num despacho = herança do pai (Agent sem `model`, sem def com model:) —
# rastro explícito em vez de campo ausente; o retorno preenche o id real via meta/jsonl
HERDADO=0
if [ -z "$MODELO" ] && [ "$TIPO" = despacho ]; then HERDADO=1; fi

# etapa = janela aberta (último checkpoint do run-log); sem janela = abertura
ET=$(grep '"evento":"checkpoint"' "$RL" 2>/dev/null | tail -n1 \
     | sed -n 's/.*"etapa":"\([^"]*\)".*/\1/p')
: "${ET:=0 abertura}"

bash "$RUNLOG_SH" "$PD" "$NN" "$TIPO" "$ET" \
  --camada "$CAM" \
  ${MODELO:+--modelo "$MODELO"} ${EFFORT:+--effort "$EFFORT"} \
  --kv agente="$AG" --kv origem=hook \
  $([ "$RETOMADA" = 1 ] && echo '--kv retomada=true') \
  $([ "$HERDADO" = 1 ] && echo '--kv modelo_herdado=true') \
  ${DESC:+--kv descricao="$DESC"} >/dev/null 2>&1

exit 0
