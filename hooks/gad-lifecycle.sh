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
#              tool_use_id e traz spawnDepth e model. Fonte autoritativa, mecânica.
#   despacho — o meta ainda não existe no PreToolUse; a camada vem da contagem de
#              despachos ABERTOS (sem retorno) no run-log cujo agente tem capacidade de
#              despachar (def com `Agent` em tools:, ou general-purpose). Heurística:
#              colide só se dois hosts rodarem em paralelo (camada 1 é serial).
#   SEMÂNTICA (v2.1.9, tarefa 34d): `camada` = camada do AGENTE DESPACHADO = spawnDepth
#   (filho da camada 0 → 1; filho de um host de camada 1 → 2). Até a 2.1.8 o campo era
#   "camada de origem" (spawnDepth-1) e nunca chegava a 2 — reincidência do "camada:0 em
#   34/34" da F24 na F24.3. Despacho sem host aberto ⇒ 1; um host aberto ⇒ 2.
#   MODELO HERDADO (34j): despacho `general-purpose` sem `model` e sem def → grava o
#   modelo do transcript da sessão principal (camada 0) + modelo_herdado:true, em vez
#   de campo ausente (8/42 despachos cegos na F24.3).

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

# etapa = janela aberta (último checkpoint do run-log); sem janela = abertura.
# Calculada AQUI (e não mais junto da escrita) porque os gates abaixo também gravam.
ET=$(grep '"evento":"checkpoint"' "$RL" 2>/dev/null | tail -n1 \
     | sed -n 's/.*"etapa":"\([^"]*\)".*/\1/p')
: "${ET:=0 abertura}"

# ══ GATES DE PREVENÇÃO (E7 + E3 — v2.2.0, plano dos 27 ajustes da intenção) ═══════════
# Rodam ANTES de qualquer escrita no run-log. Um despacho negado NÃO pode deixar um
# evento `despacho` órfão: a camada_heuristica() conta despachos sem retorno, e o órfão
# jogaria o PRÓXIMO despacho legítimo para camada 2. Por isso a negativa grava só
# `incidente` — evento que o filtro da heurística (despacho|retorno) ignora.
#
# Resposta = contrato do Claude Code 2.1.251: exit 0 + stdout
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
#    "permissionDecisionReason":"…"}}
# O `decision: block` de topo (usado pelo gsd-agent-isolation-guard.js:488-493) está
# deprecado — não usar.
#
# FAIL-OPEN por herança: como todo o resto do hook, os gates só existem dentro de uma
# rodada ativa da /go-and-do (ponteiro presente, sessão casando, rodada não parada,
# run-log.sh instalado). Fora disso o hook já saiu em no-op lá em cima.

AGN="${AG%% *}"   # nome puro do agente/alvo (o AG do SendMessage pode vir com sufixo)

# caminho da def do agente, se existir (home primeiro, projeto depois)
gad_def() {
  local d
  for d in "$HOME/.claude/agents/$1.md" "$CWD/.claude/agents/$1.md"; do
    [ -f "$d" ] && { printf '%s' "$d"; return 0; }
  done
  return 1
}
# normalização mínima para comparar chamada × def: só espaço/aspas/caixa. NÃO se remove
# o prefixo `claude-` — normalizar demais só faz valores DIFERENTES compararem iguais, e
# o contrato do E7(a) é que `model`/`effort` sequer apareçam na chamada.
gad_norm() { printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -d '[:space:]"'; }

gad_nega() { # $1 = detalhe (vai para o incidente, o stderr e a razão do deny)
  bash "$RUNLOG_SH" "$PD" "$NN" incidente "$ET" \
    --kv origem=gad-lifecycle.sh --kv detalhe="$1" \
    --kv agente="$AGN" --kv tool="$TOOL" >/dev/null 2>&1
  printf 'gad-lifecycle: %s\n' "$1" >&2
  jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",
    permissionDecision:"deny", permissionDecisionReason:$r}}'
  exit 0
}

if [ "$TIPO" = despacho ]; then
  if [ "$TOOL" = SendMessage ]; then
    # ── E3(a): retomada de filho ENCERRADO da etapa de intenção ──────────────────
    # O alvo é resolvido: nome literal, ou id `a<hex>` → agentType do meta.json (mesma
    # fonte que o bloco de camada usa mais abaixo). A decisão usa o tipo RESOLVIDO.
    ALVO="$AGN"
    case "$ALVO" in
      a[0-9a-f]*)
        _m=$(ls "$SUBDIR/agent-$ALVO"*.meta.json 2>/dev/null | head -n1)
        if [ -n "$_m" ]; then
          _at=$(jq -r '.agentType // empty' "$_m" 2>/dev/null)
          [ -n "$_at" ] && ALVO="$_at"
        fi ;;
    esac
    case "$ALVO" in
      gad-spec|gad-discuss)
        gad_nega "filho_encerrado: SendMessage para $ALVO (to=$AGN). Filho que devolveu 'done' não é acordado — a janela dele já morreu e a retomada recusta o contexto inteiro (203 k na F24.3). Correção de decisão = coordenador via checkpoint-write.py/context-render.py; pergunta de código nova = Agent(gad-explore)." ;;
    esac
  else
    # ── E7(b): model/effort na chamada divergindo da def que os pina ─────────────
    # ESCOPO: só os `gad-*`. O plano diz "agentes com def que pina" E "general-purpose/
    # gsd-* seguem livres" — e as duas cláusulas colidem: `gsd-mempalace-curator` pina
    # `model:` e é despachado pela capability do GSD, fora do nosso controle. Prevalece a
    # cláusula explícita: o gate cobre exatamente o que o E7(a) proíbe (`Agent` de gad-*
    # com model/effort). Dos 43 defs em ~/.claude/agents, 10 pinam model; 6 são gad-*.
    _cm=""; _ce=""
    case "$AGN" in gad-*)
      _cm=$(jq -r '.tool_input.model // empty' <<<"$IN")
      _ce=$(jq -r '.tool_input.effort // empty' <<<"$IN") ;;
    esac
    if [ -n "$_cm" ] || [ -n "$_ce" ]; then
      if _def=$(gad_def "$AGN"); then
        _dm=$(grep -m1 -E '^model:' "$_def" | sed 's/^model:[[:space:]]*//' | tr -d ' \r')
        _de=$(grep -m1 -E '^(effort|reasoning_effort):' "$_def" \
              | sed 's/^[a-z_]*:[[:space:]]*//' | tr -d ' \r')
        # só agentes cuja def PINA o modelo. `general-purpose` (sem def) e os `gsd-*`
        # (def sem `model:`, recebem o modelo por parâmetro do orquestrador) ficam livres.
        if [ -n "$_dm" ]; then
          _viola=""
          [ -n "$_cm" ] && [ "$(gad_norm "$_cm")" != "$(gad_norm "$_dm")" ] \
            && _viola="model=$_cm≠$_dm"
          [ -n "$_ce" ] && [ "$(gad_norm "$_ce")" != "$(gad_norm "$_de")" ] \
            && _viola="${_viola:+$_viola }effort=$_ce≠${_de:-<ausente>}"
          [ -n "$_viola" ] && gad_nega "modelo_override: chamada≠def em Agent($AGN) — $_viola. O modelo/effort dos agentes gad-* é pinado no frontmatter da def; passar model/effort na chamada é proibido (E7). Redespache sem os campos."
        fi
      fi
    fi
    # ── E3(b): 2º despacho do mesmo filho na mesma fase (artefato já existe) ─────
    # phase_dir e NN vêm do ponteiro .gad-rodada-ativa.json (PD/NN) — 1 stat cada.
    case "$AGN" in
      gad-discuss) [ -f "$PD/$NN-CONTEXT.md" ] && gad_nega "filho_encerrado: 2º Agent(gad-discuss) na fase $NN — $NN-CONTEXT.md já existe. A etapa de discuss já produziu o artefato; reabrir o filho refaz o trabalho. Edite o CONTEXT e re-rode context-guard.sh." ;;
      gad-spec)    [ -f "$PD/$NN-SPEC.md" ]    && gad_nega "filho_encerrado: 2º Agent(gad-spec) na fase $NN — $NN-SPEC.md já existe. A etapa de spec já produziu o artefato; reabrir o filho refaz o trabalho. Corrija o SPEC no coordenador." ;;
    esac
  fi
fi
# ══ fim dos gates ═════════════════════════════════════════════════════════════════════

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
  [ "$n" -gt 1 ] && n=1
  echo $((n+1))   # camada do despachado = hosts abertos + 1 (v2.1.9)
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
    case "$SD" in (''|*[!0-9]*) ;; (*) CAM=$SD ;; esac
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
    case "$SD" in (''|*[!0-9]*) ;; (*) CAM=$SD ;; esac
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
if [ -z "$MODELO" ] && [ "$TIPO" = despacho ]; then
  HERDADO=1
  # v2.1.9 (34j): o herdado é o modelo de quem despacha — para a camada 0 é o último
  # request do transcript principal; host de camada 1 herda o mesmo (o pai dele é a
  # camada 0). Fica como rastro mecânico, com a marca modelo_herdado ao lado.
  MODELO=$(modelo_do_jsonl "$TP")
fi

# ET (etapa da janela aberta) já foi calculada antes dos gates.

bash "$RUNLOG_SH" "$PD" "$NN" "$TIPO" "$ET" \
  --camada "$CAM" \
  ${MODELO:+--modelo "$MODELO"} ${EFFORT:+--effort "$EFFORT"} \
  --kv agente="$AG" --kv origem=hook \
  $([ "$RETOMADA" = 1 ] && echo '--kv retomada=true') \
  $([ "$HERDADO" = 1 ] && echo '--kv modelo_herdado=true') \
  ${DESC:+--kv descricao="$DESC"} >/dev/null 2>&1

exit 0
