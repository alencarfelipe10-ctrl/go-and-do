#!/usr/bin/env bash
# gad-lifecycle.sh — hook PreToolUse/PostToolUse (matcher Agent|Task) da go-and-do.
# Decisões G.2/T.2 do gad-major-update: o ciclo de vida de TODO despacho de subagente
# entra no run-log SEM participação do modelo — PreToolUse grava `despacho`, PostToolUse
# grava `retorno`, com camada de origem (0→1 vs 1→2), agente e modelo/effort lidos da
# def do agente. Escritor único: este hook é o ÚNICO escritor de despacho/retorno.
#
# Instalação (fora do repo — passo documentado no README):
#   ln -s <clone>/hooks/gad-lifecycle.sh ~/.claude/hooks/gad-lifecycle.sh
#   + registro no ~/.claude/settings.json (PreToolUse e PostToolUse, matcher "Agent|Task")
#
# Vive no settings GLOBAL e dispara em qualquer sessão/projeto — por isso os guards
# (PC-3): acha o ponteiro leve .planning/.gad-rodada-ativa.json a partir do cwd
# (1 stat; fallback raiz git), compara session_id e verifica que a rodada não parou.
# Qualquer guard falhando → no-op em milissegundos, exit 0 SEMPRE (telemetria jamais
# bloqueia um despacho).
#
# Camada de origem: o transcript_path de um subagente vive em .../subagents/agent-*.jsonl
# — se o despacho nasce lá, a origem é a camada 1 (despachando a 2); senão, camada 0.

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

AG=$(jq -r '.tool_input.subagent_type // "general-purpose"' <<<"$IN")
DESC=$(jq -r '.tool_input.description // ""' <<<"$IN" | head -c 120)
TP=$(jq -r '.transcript_path // ""' <<<"$IN")
case "$TP" in */subagents/*) CAM=1 ;; *) CAM=0 ;; esac

# modelo/effort da def do agente (mecânico; def ausente = campos omitidos)
MODELO=""; EFFORT=""
for DEF in "$HOME/.claude/agents/$AG.md" "$CWD/.claude/agents/$AG.md"; do
  if [ -f "$DEF" ]; then
    MODELO=$(grep -m1 -E '^model:' "$DEF" | sed 's/^model:[[:space:]]*//' | tr -d ' \r')
    EFFORT=$(grep -m1 -E '^(effort|reasoning_effort):' "$DEF" | sed 's/^[a-z_]*:[[:space:]]*//' | tr -d ' \r')
    break
  fi
done

# etapa = janela aberta (último checkpoint do run-log); sem janela = abertura
ET=$(grep '"evento":"checkpoint"' "$RL" 2>/dev/null | tail -n1 \
     | sed -n 's/.*"etapa":"\([^"]*\)".*/\1/p')
: "${ET:=0 abertura}"

bash "$RUNLOG_SH" "$PD" "$NN" "$TIPO" "$ET" \
  --camada "$CAM" \
  ${MODELO:+--modelo "$MODELO"} ${EFFORT:+--effort "$EFFORT"} \
  --kv agente="$AG" --kv origem=hook \
  ${DESC:+--kv descricao="$DESC"} >/dev/null 2>&1

exit 0
