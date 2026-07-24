#!/bin/bash
# notify-telegram.sh — avisa no Telegram quando o Claude Code fica esperando você:
# uma pergunta interativa (AskUserQuestion) ou um pedido de permissão pendente.
#
# Instalação (hook Notification em ~/.claude/settings.json):
#   "Notification": [{ "matcher": "permission_prompt", "hooks": [{ "type": "command",
#     "command": "bash \"/caminho/para/tools/notify-telegram.sh\"", "timeout": 15, "async": true }] }]
#
# Credenciais (fora de qualquer repo), em ~/.config/telegram-notify/config, chmod 600:
#   TELEGRAM_BOT_TOKEN=...
#   TELEGRAM_CHAT_ID=...
#
# Janela de silêncio (23h–07h local): a mensagem chega igual, mas muda — sem som nem vibração.
# Contrato: este script NUNCA atrapalha a sessão — qualquer falha termina em exit 0, calada.

set -u

CONFIG="${TELEGRAM_NOTIFY_CONFIG:-$HOME/.config/telegram-notify/config}"
STATE_DIR="$HOME/.local/state/telegram-notify"
mkdir -p "$STATE_DIR" 2>/dev/null || true

[ -r "$CONFIG" ] || exit 0
# shellcheck source=/dev/null
source "$CONFIG" 2>/dev/null || exit 0
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

PAYLOAD=$(cat 2>/dev/null) || exit 0
NTYPE=$(printf '%s' "$PAYLOAD" | jq -r '.notification_type // empty' 2>/dev/null)
[ "$NTYPE" = "permission_prompt" ] || exit 0

CWD=$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$PAYLOAD" | jq -r '.transcript_path // empty' 2>/dev/null)

html_esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }
# O @html do jq escapa apóstrofo como &apos;/&#39;, que o Telegram não reconhece — desfaz.
unapos() { sed "s/&apos;/'/g; s/&#39;/'/g"; }
PROJETO=$(basename "${CWD:-sessão}" | html_esc)

# ── O que está pendente? O último tool_use do transcript decide. ─────────────
# Pergunta interativa → mensagem rica (pergunta + opções). Qualquer outra
# ferramenta → é um pedido de permissão travado nela.
#
# Corrida conhecida: a notificação pode disparar ANTES de o Claude Code gravar
# a entrada do AskUserQuestion no transcript (atraso medido: até ~6s). Por isso
# o loop: relê a cada 2s, por até 16s, até ver um AskUserQuestion como último
# tool_use. Permissão de verdade nunca vira AskUserQuestion — sai após o loop.
ler_ultimo_tool() {
  tail -n 300 "$TRANSCRIPT" 2>/dev/null | jq -c '
    select(.type == "assistant")
    | .message.content[]?
    | select(.type == "tool_use")
    | {name, input}' 2>/dev/null | tail -n 1
}

LAST_TOOL=""
if [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
  for _ in 1 2 3 4 5 6 7 8; do
    LAST_TOOL=$(ler_ultimo_tool)
    [ -n "$LAST_TOOL" ] && [ "$(printf '%s' "$LAST_TOOL" | jq -r '.name' 2>/dev/null)" = "AskUserQuestion" ] && break
    sleep 2
  done
fi

if [ -n "$LAST_TOOL" ] && [ "$(printf '%s' "$LAST_TOOL" | jq -r '.name' 2>/dev/null)" = "AskUserQuestion" ]; then
  TITULO="❓ <b>Pergunta esperando você</b> — <i>${PROJETO}</i>"
  DETALHE=$(printf '%s' "$LAST_TOOL" | jq -r '
    [ .input.questions[]?
      | ( (if (.header // "") != "" then "<b>" + (.header | @html) + "</b> — " else "" end)
          + ((.question // "") | @html) )
        + ( [ .options[]? | "\n  • " + ((.label // "") | @html) ] | join("") )
    ] | join("\n\n")' 2>/dev/null | unapos)
else
  TITULO="🔐 <b>Permissão travada</b> — <i>${PROJETO}</i>"
  DETALHE=$(printf '%s' "$LAST_TOOL" | jq -r '
    if .name == null then "O Claude Code está esperando uma aprovação sua no terminal."
    else
      "Ferramenta: <b>" + (.name | @html) + "</b>"
      + ( if .input.command? then "\n<code>" + (.input.command[0:200] | @html) + "</code>"
          elif .input.file_path? then "\n<code>" + (.input.file_path | @html) + "</code>"
          else "" end )
    end' 2>/dev/null | unapos)
fi
[ -n "$DETALHE" ] || DETALHE="O Claude Code está esperando você no terminal."

# ── Enriquecimento opcional: fase/etapa do run-log da go-and-do, se houver. ──
FASE_INFO=""
if [ -n "$CWD" ] && [ -d "$CWD/.planning/phases" ]; then
  RL=$(ls -t "$CWD"/.planning/phases/*/*-RUN-LOG.jsonl 2>/dev/null | head -n 1)
  if [ -n "$RL" ]; then
    FASE=$(basename "$(dirname "$RL")" | html_esc)
    ETAPA=$(tail -n 1 "$RL" 2>/dev/null | jq -r '.etapa // empty' 2>/dev/null | html_esc)
    FASE_INFO="📂 ${FASE}${ETAPA:+ · ${ETAPA}}"
  fi
fi

# ── Janela de silêncio: entrega muda entre 23h e 07h. ────────────────────────
H=$((10#$(date +%H)))
SILENT=false
{ [ "$H" -ge 23 ] || [ "$H" -lt 7 ]; } && SILENT=true

TEXT="${TITULO}"
[ -n "$FASE_INFO" ] && TEXT="${TEXT}
${FASE_INFO}"
TEXT="${TEXT}

${DETALHE}"
TEXT="${TEXT:0:3800}"

curl -s --max-time 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${TEXT}" \
  --data-urlencode "parse_mode=HTML" \
  --data-urlencode "disable_notification=${SILENT}" \
  > "$STATE_DIR/last-send.json" 2>/dev/null || true

# Fallback: se o HTML não passou (tag desequilibrada etc.), reenvia em texto puro.
if ! jq -e '.ok == true' "$STATE_DIR/last-send.json" >/dev/null 2>&1; then
  curl -s --max-time 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${TEXT}" \
    --data-urlencode "disable_notification=${SILENT}" \
    > "$STATE_DIR/last-send.json" 2>/dev/null || true
fi

exit 0
