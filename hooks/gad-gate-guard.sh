#!/usr/bin/env bash
# gad-gate-guard.sh — hook PreToolUse (matcher AskUserQuestion) da go-and-do: cerimônia antes
# de um gate duro dentro de uma rodada ativa (v2.5.4, tarefa 45p — F24.5 23:50 e pendência 12
# da F24.4: pergunta na janela de silêncio, sem commit, sem HANDOFF; espelhos 6 h velhos).
#
# Nega quando (dentro de rodada ativa da própria sessão, não parada):
#   (a) `janela-silencio.sh` sai 1 (23h–07h): a rota é a Sub-rotina D (parada graciosa) com a
#       pergunta no handoff — não perguntar.
#   (b) não há `.planning/.gad/last-pre-gate.json` fresco: gravado pelo `pre-gate.sh` há menos de
#       15 min E com `head` == HEAD atual (o pre-gate commita os artefatos da fase; commit novo
#       depois dele = artefato novo sem commit → rode de novo).
# Fora disso: allow silencioso (exit 0, sem stdout). Qualquer erro interno → allow (fail-open).
# Registro: hooks.PreToolUse += {matcher:"AskUserQuestion", hooks:[{type:"command",
#   command:"bash \"$HOME/Projetos-Vox-AI/go-and-do/hooks/gad-gate-guard.sh\"", timeout:10}]}
#   — ou `bash hooks/registra-hooks.sh`.
# Envelope (CC 2.1.251+): {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#   "permissionDecision":"deny","permissionDecisionReason":"…"}}
# Teste: GAD_HORA_FALSA (lida pelo janela-silencio.sh) e GAD_GATE_AGORA (epoch "agora", só teste).

IN=$(cat 2>/dev/null) || exit 0
[ -n "$IN" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
[ "$(jq -r '.tool_name // empty' <<<"$IN")" = "AskUserQuestion" ] || exit 0
[ "$(jq -r '.hook_event_name // empty' <<<"$IN")" = "PreToolUse" ] || exit 0

CWD=$(jq -r '.cwd // empty' <<<"$IN"); [ -n "$CWD" ] || exit 0
# v2.10.1 (56(a)): ponteiro novo em .planning/.gad/rodada-ativa.json (precedência);
# o legado .planning/.gad-rodada-ativa.json vale por uma release.
P=""; ROOT=""
for _r in "$CWD" "$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"; do
  [ -n "$_r" ] || continue
  for _c in "$_r/.planning/.gad/rodada-ativa.json" "$_r/.planning/.gad-rodada-ativa.json"; do
    [ -f "$_c" ] && { P="$_c"; ROOT="$_r"; break 2; }
  done
done
[ -n "$P" ] || exit 0
SESS=$(jq -r '.session_id // empty' <<<"$IN"); PSESS=$(jq -r '.session_id // empty' "$P" 2>/dev/null)
[ -n "$SESS" ] && [ "$SESS" = "$PSESS" ] || exit 0
RL=$(jq -r '.runlog // empty' "$P"); NN=$(jq -r '.nn // empty' "$P"); PD=$(jq -r '.phase_dir // empty' "$P")
[ -n "$RL" ] && [ -n "$NN" ] && [ -n "$PD" ] || exit 0
[ -f "$RL" ] && tail -n1 "$RL" 2>/dev/null | grep -q '"evento":"stop"' && exit 0

SCRIPTS="${GAD_SCRIPTS_DIR_TESTE:-$HOME/.claude/skills/go-and-do/scripts}"
RUNLOG_SH="$SCRIPTS/run-log.sh"; JS="$SCRIPTS/janela-silencio.sh"
[ -f "$JS" ] || exit 0

ET=$(grep '"evento":"checkpoint"' "$RL" 2>/dev/null | tail -n1 | sed -n 's/.*"etapa":"\([^"]*\)".*/\1/p')
: "${ET:=0 abertura}"

nega() { # $1 = motivo curto  $2 = razão completa
  [ -f "$RUNLOG_SH" ] && bash "$RUNLOG_SH" "$PD" "$NN" incidente "$ET" \
    --kv origem=gad-gate-guard.sh --kv motivo="$1" --kv detalhe="$2" >/dev/null 2>&1
  printf 'gad-gate-guard: negado (%s)\n' "$1" >&2
  jq -cn --arg r "[gad-gate-guard] $2" '{hookSpecificOutput:{hookEventName:"PreToolUse",
    permissionDecision:"deny", permissionDecisionReason:$r}}'
  exit 0
}

# (a) janela de silêncio
bash "$JS" >/dev/null 2>&1; rc=$?
if [ "$rc" = 1 ]; then
  nega "janela_silencio" "gate duro dentro da janela de silêncio (23h–07h): não pergunte. Execute a Sub-rotina D (parada graciosa) com a pergunta pendente — opções + recomendação — no handoff e no resumo parcial; a retomada a reapresenta. (janela-silencio.sh exit 1; F24.5 23:50 e pendência 12 da F24.4.)"
fi

# (b) pre-gate fresco para o HEAD atual
M="$ROOT/.planning/.gad/last-pre-gate.json"
AGORA="${GAD_GATE_AGORA:-$(date +%s)}"
HEAD_ATUAL=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo "")
ok=0
if [ -f "$M" ]; then
  mts=$(jq -r '.ts_epoch // 0' "$M" 2>/dev/null); mhead=$(jq -r '.head // ""' "$M" 2>/dev/null)
  case "$mts" in (''|*[!0-9]*) mts=0 ;; esac
  [ $((AGORA - mts)) -le 900 ] && [ -n "$HEAD_ATUAL" ] && [ "$mhead" = "$HEAD_ATUAL" ] && ok=1
fi
if [ "$ok" = 0 ]; then
  nega "sem_pre_gate" "antes de um AskUserQuestion dentro da rodada, rode \`bash \$HOME/.claude/skills/go-and-do/scripts/pre-gate.sh \"$PD\" \"$NN\" \"<pergunta em 1 linha>\"\` — ele confere a janela de silêncio, commita os artefatos da fase (RUN-LOG, DECISOES, NOTIFICACOES, evidências de gate) e registra o pré-gate; depois pergunte. Marcador ausente, com mais de 15 min, ou de outro HEAD. (F24.5: pergunta das 23:50 sem commit e sem HANDOFF.)"
fi
exit 0
