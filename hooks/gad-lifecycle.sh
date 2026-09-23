#!/usr/bin/env bash
# gad-lifecycle.sh — hook PreToolUse/PostToolUse (matcher Agent|Task|SendMessage) da go-and-do.
# Decisões G.2/T.2 do gad-major-update: o ciclo de vida de TODO despacho de subagente
# entra no run-log SEM participação do modelo — PreToolUse grava `despacho`, PostToolUse
# grava `retorno`, com camada de origem (0→1 vs 1→2), agente e modelo/effort. Escritor
# único: este hook é o ÚNICO escritor de despacho/retorno. Desde a auditoria da F24
# (10/08) o SendMessage também entra: retomada de subagente vivo gera despacho/retorno
# com "retomada":true (o 2º retorno do gad-intent pós-gate ficava invisível).
# v2.5.4 (45g): a tool Agent é assíncrona no CC ≥ 2.1.26x — o PostToolUse dispara no retorno
# da CHAMADA. Por isso o hook também é registrado em `SubagentStop` (matcher vazio), que grava
# o `retorno` de fim real (`fim_real:true`, `agent_id`, `duracao_s`); o retorno do PostToolUse
# fica com `fim_real:false`. Registro: `hooks/registra-hooks.sh`.
#
# Instalação (fora do repo — passo documentado no README):
#   ln -s <clone>/hooks/gad-lifecycle.sh ~/.claude/hooks/gad-lifecycle.sh
#   + registro no ~/.claude/settings.json (PreToolUse, PostToolUse e SubagentStop, matcher
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

SESS=$(jq -r '.session_id // empty' <<<"$IN" 2>/dev/null)
[ -n "$SESS" ] || exit 0

# FM-03EXE: o ponteiro leve é local à árvore (não versionado); um agente despachado numa
# cópia (worktree isolado) não o acha nem por show-toplevel (que resolve o toplevel DELE,
# não o da árvore principal). Caminho de falha, barato: 1 chamada git a mais só quando as
# duas primeiras tentativas falham OU acham um ponteiro de outra sessão (ponteiro tracked/
# obsoleto na cópia — visto em worktrees reais do RLR).
achar_ponteiro() {
  local cand="$CWD/.planning/.gad-rodada-ativa.json" root psess
  if [ -f "$cand" ]; then
    psess=$(jq -r '.session_id // empty' "$cand" 2>/dev/null)
    [ "$SESS" = "$psess" ] && { printf '%s' "$cand"; return 0; }
  fi
  root=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$root" ]; then
    cand="$root/.planning/.gad-rodada-ativa.json"
    if [ -f "$cand" ]; then
      psess=$(jq -r '.session_id // empty' "$cand" 2>/dev/null)
      [ "$SESS" = "$psess" ] && { printf '%s' "$cand"; return 0; }
    fi
  fi
  local common main
  common=$(git -C "$CWD" rev-parse --git-common-dir 2>/dev/null) || return 1
  case "$common" in
    /*) main=$(dirname "$common") ;;
    *)  main=$(cd "$CWD" 2>/dev/null && cd "$(dirname "$common")" 2>/dev/null && pwd -P) ;;
  esac
  [ -n "$main" ] || return 1
  cand="$main/.planning/.gad-rodada-ativa.json"
  [ -f "$cand" ] || return 1
  psess=$(jq -r '.session_id // empty' "$cand" 2>/dev/null)
  [ "$SESS" = "$psess" ] || return 1
  printf '%s' "$cand"
}
P=$(achar_ponteiro) || exit 0
[ -n "$P" ] || exit 0

RL=$(jq -r '.runlog // empty' "$P"); NN=$(jq -r '.nn // empty' "$P")
PD=$(jq -r '.phase_dir // empty' "$P")
[ -n "$RL" ] && [ -n "$NN" ] && [ -n "$PD" ] || exit 0
# rodada pausada (stop foi o último evento) → no-op; o ponteiro some no stop, este é
# só o cinto de segurança para corrida entre o stop e a remoção
[ -f "$RL" ] && tail -n1 "$RL" 2>/dev/null | grep -q '"evento":"stop"' && exit 0

RUNLOG_SH="$HOME/.claude/skills/go-and-do/scripts/run-log.sh"
[ -f "$RUNLOG_SH" ] || exit 0

EV=$(jq -r '.hook_event_name // empty' <<<"$IN")
# FIM_REAL: só o SubagentStop marca o fim de verdade do agente. Desde que a tool Agent virou
# assíncrona (CC 2.1.26x, "Async agent launched"), o PostToolUse dispara segundos após o
# despacho — o `retorno` dele é o retorno da CHAMADA (F24.5: 9 executores "encerrados" 2–5 s
# após nascer, 12 incidentes falsos de onda serializada). v2.5.4, tarefa 45g.
FIM_REAL=0
case "$EV" in
  PreToolUse)   TIPO=despacho ;;
  PostToolUse)  TIPO=retorno ;;
  SubagentStop) TIPO=retorno; FIM_REAL=1 ;;
  *) exit 0 ;;
esac

TOOL=$(jq -r '.tool_name // empty' <<<"$IN")
TUID=$(jq -r '.tool_use_id // empty' <<<"$IN")
TP=$(jq -r '.transcript_path // ""' <<<"$IN")
SUBDIR="${TP%.jsonl}/subagents"

RETOMADA=0; ISOL=""
# SubagentStop (docs do CC: session_id, agent_id, agent_type, transcript_path do AGENTE, cwd; sem
# tool_use_id). O meta.json do agente é `<transcript do agente sem .jsonl>.meta.json`; fallback:
# procurar por agent_id no diretório do transcript e em <transcript>/subagents/.
AGID=""; META_STOP=""; ATP=""
if [ "$EV" = SubagentStop ]; then
  AGID=$(jq -r '.agent_id // empty' <<<"$IN")
  ATP=$(jq -r '.agent_transcript_path // .transcript_path // ""' <<<"$IN")
  [ -n "$ATP" ] && [ -f "${ATP%.jsonl}.meta.json" ] && META_STOP="${ATP%.jsonl}.meta.json"
  if [ -z "$META_STOP" ] && [ -n "$AGID" ]; then
    for _d in "$(dirname "$ATP")" "$(dirname "$ATP")/subagents" "${ATP%.jsonl}/subagents"; do
      _m=$(ls "$_d"/agent-"${AGID#agent-}"*.meta.json 2>/dev/null | head -n1)
      [ -n "$_m" ] && { META_STOP="$_m"; break; }
    done
  fi
  TOOL="Agent"
  AG=$(jq -r '.agent_type // empty' <<<"$IN")
  # Medido na F24.5 (10/09, 1ª hora com o SubagentStop registrado): eventos a cada ~30 s com
  # agent_type vazio e SEM transcript/meta (agent_transcript_path inexistente) — subagentes
  # internos do CC (classificador do auto mode), não despachos da skill. Sem meta e sem tipo
  # não há o que registrar: no-op, senão o run-log ganha um `retorno` órfão por tool call.
  if [ -z "$META_STOP" ] && [ -z "$AG" ]; then exit 0; fi
  if [ -n "$META_STOP" ]; then
    _at=$(jq -r '.agentType // empty' "$META_STOP" 2>/dev/null); [ -n "$_at" ] && AG="$_at"
    DESC=$(jq -r '(.description // "")[0:120]' "$META_STOP" 2>/dev/null)
    [ "$(jq -r '.spawnedWithWorktree // false' "$META_STOP" 2>/dev/null)" = true ] && ISOL="worktree"
    TUID=$(jq -r '.toolUseId // empty' "$META_STOP" 2>/dev/null)
  else
    DESC=""
  fi
  : "${AG:=general-purpose}"
elif [ "$TOOL" = "SendMessage" ]; then
  # retomada de subagente vivo (SendMessage): alvo = campo `to`; mensagens para fora
  # (outras sessões/canais) não têm meta local e caem no fallback camada 0 — aceitável,
  # a origem da retomada é a camada 0 mesmo.
  RETOMADA=1
  AG=$(jq -r '.tool_input.to // "?"' <<<"$IN" | tr -cd 'A-Za-z0-9_ ().-' | head -c 60)
  DESC=$(jq -r '(.tool_input.message // "")[0:120]' <<<"$IN")
else
  AG=$(jq -r '.tool_input.subagent_type // "general-purpose"' <<<"$IN")
  DESC=$(jq -r '(.tool_input.description // "")[0:120]' <<<"$IN")
  # isolamento pedido no despacho (`isolation: "worktree"`): é o que permite ao
  # confere-etapa.sh 3 distinguir executor em cópia de executor na árvore principal.
  ISOL=$(jq -r '.tool_input.isolation // ""' <<<"$IN" | tr -cd 'a-z-' | head -c 20)
fi

# etapa = janela aberta (último checkpoint do run-log); sem janela = abertura.
# Calculada AQUI (e não mais junto da escrita) porque os gates abaixo também gravam.
# FM-04ENC: o checkpoint tem de ser DESTA SESSÃO — o grep global pegava o último checkpoint
# do ARQUIVO (podia ser de uma sessão anterior já encerrada), rotulando os eventos que
# chegam antes do 1º checkpoint da sessão nova com a etapa em que a sessão ANTERIOR parou
# (medido real: F4 RLR seq 485, script rotulado "6 encerramento" logo após o `run` de uma
# sessão nova que ainda não tinha checkpoint nenhum). O run-log.sh grava `sessao` com os 8
# primeiros caracteres do session id — mesmo corte aqui, para casar.
SESS8="${SESS:0:8}"
ET=$(grep "\"sessao\":\"$SESS8\"" "$RL" 2>/dev/null | grep '"evento":"checkpoint"' | tail -n1 \
     | sed -n 's/.*"etapa":"\([^"]*\)".*/\1/p')
: "${ET:=0 abertura}"

AGN="${AG%% *}"   # nome puro do agente/alvo (o AG do SendMessage pode vir com sufixo) —
# adiantado para o FM-02EXE logo abaixo; os gates E7/E3 mais adiante reusam a variável.

# FM-02EXE: 2ª defesa. Quando o despacho bloqueado é aceito pelo dono, o checkpoint da etapa
# só é gravado quando o workflow reabre a fase (texto em C3, fora desta lane) — até lá o
# gancho rotularia o despacho com a etapa velha (ou "0 abertura"). Alguns tipos de agente
# mapeiam para UMA etapa só e servem de defesa mecânica nesse intervalo; agentes que hospedam
# mais de uma etapa (ex.: gad-gates, que roda 4.1/4.1b/4.4/4.5) NÃO entram aqui — vale o
# checkpoint. Só corrige quando o ID da etapa aberta diverge do mapeado (não sobrescreve uma
# etapa já certa, e não interfere se o mapeado for múltiplo/desconhecido).
# SÓ no `despacho` (medido contra o RUN-LOG real do RLR, F3: um `retorno` de gad-execute
# pode legitimamente aterrissar com o checkpoint já em "4.1 code-review" — despacho de
# 7h atrás, camada 0 já tinha avançado a fase; sobrescrever o retorno para "3 construcao"
# jogaria o custo dele pra etapa errada. O despacho é o único momento em que "ainda não
# tem checkpoint aberto" é de fato um bug a corrigir — o retorno usa o checkpoint real.
case "$AGN" in
  gad-intent)  ET_TIPO="1 intencao" ;;
  # gad-plan passou a hospedar a etapa 2 E a 2.5 (convergência) na v2.9.0: não há etapa
  # única a corrigir — igual ao gad-gates, fica com o checkpoint real (senão um despacho
  # legítimo com checkpoint "2.5 convergencia" seria reescrito para "2 planejamento",
  # corrompendo a medição do host da 2.5).
  gad-execute) ET_TIPO="3 construcao" ;;
  # gad-gates serve a etapa 4 (4.1/4.1b/4.4/4.5) E a rota A do close (6); gad-plan serve a
  # 2 e a 2.5: nenhum dos dois tem etapa única a corrigir — não há mapa aqui.
  *)           ET_TIPO="" ;;
esac
ET_CORRIGIDA=0
if [ "$TIPO" = despacho ] && [ -n "$ET_TIPO" ] && [ "${ET%% *}" != "${ET_TIPO%% *}" ]; then
  ET_ANTERIOR="$ET"
  ET="$ET_TIPO"
  ET_CORRIGIDA=1
fi

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

# SubagentStop: o meta.json já foi localizado acima (META_STOP)
DUR=""
if [ "$FIM_REAL" = 1 ] && [ -n "$META_STOP" ]; then
  SD=$(jq -r '.spawnDepth // empty' "$META_STOP" 2>/dev/null)
  case "$SD" in (''|*[!0-9]*) ;; (*) CAM=$SD ;; esac
  MODELO=$(jq -r '.model // empty' "$META_STOP" 2>/dev/null)
  [ -n "$MODELO" ] || MODELO=$(modelo_do_jsonl "${META_STOP%.meta.json}.jsonl")
  # duração = agora − primeiro timestamp do transcript do agente
  _t0=$(grep -o '"timestamp":"[^"]*"' "${META_STOP%.meta.json}.jsonl" 2>/dev/null | head -n1 | sed 's/.*:"\(.*\)"/\1/')
  if [ -n "$_t0" ]; then
    _s0=$(date -d "$_t0" +%s 2>/dev/null || true); _s1=$(date +%s)
    [ -n "$_s0" ] && DUR=$((_s1 - _s0))
  fi
fi
# retorno: meta.json do subagente é a fonte autoritativa (tool_use_id ↔ toolUseId)
if [ -z "$CAM" ] && [ "$TIPO" = retorno ] && [ -n "$TUID" ] && [ -d "$SUBDIR" ]; then
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
    # FM-05UAT (F4 RLR, B1 §3): a devolução ao mesmo subagente por SendMessage grava o
    # TIPO do agente (agentType do meta), nunca o `to` bruto — que na retomada por id
    # hex sem nome (F24: 5 pares a<hex>… sem campo) É o id, não o tipo. Quando `to` já
    # era o nome/tipo literal (1º grep acima casou), $_at sai igual a $AG — no-op.
    _at=$(jq -r '.agentType // empty' "$META" 2>/dev/null)
    [ -n "$_at" ] && AG="$_at"
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

# FM-05UAT (dedup do "único terminou"): o SubagentStop pode disparar mais de uma vez para
# o MESMO agente — quando o filho é "acordado" de novo por SendMessage (retomada) depois de
# um stop de turno que o CC emite sem o agente estar de fato morto (PROVADO 10/09: filho
# aninhado que encerra o turno com filho vivo é acordado pela task-notification). Duas
# linhas `fim_real:true` para o mesmo `agent_id` contam a MESMA finalização em dobro na
# auditoria (confere-etapa.sh 3, que fecha despacho só com fim_real:true). Chave = agent_id
# (vem direto do payload do SubagentStop, estável entre disparos do MESMO agente — tool_use_id
# e seq mudam a cada chamada). Só o PRIMEIRO fim_real:true de um agent_id vale; os seguintes
# viram fim_real:false + duplicado_de:<seq da linha original>.
DUP_SEQ=""
if [ "$FIM_REAL" = 1 ] && [ -n "$AGID" ] && [ -f "$RL" ]; then
  DUP_SEQ=$(grep -F "\"agent_id\":\"$AGID\"" "$RL" 2>/dev/null \
    | grep -F '"evento":"retorno"' | grep -F '"fim_real":true' | tail -n1 \
    | sed -n 's/.*"seq":\([0-9]*\).*/\1/p')
  [ -n "$DUP_SEQ" ] && FIM_REAL=0
fi

# fim_real: false no retorno do PostToolUse (retorno da CHAMADA, que é imediata com Agent
# assíncrono); true no SubagentStop (exceto o duplicado acima, rebaixado). Quem mede
# paralelismo (confere-etapa.sh 3) só fecha despacho com fim_real:true.
FR_KV=""
if [ "$TIPO" = retorno ]; then
  if [ "$FIM_REAL" = 1 ]; then FR_KV="--kv fim_real=true"; else FR_KV="--kv fim_real=false"; fi
fi
bash "$RUNLOG_SH" "$PD" "$NN" "$TIPO" "$ET" \
  --camada "$CAM" \
  ${MODELO:+--modelo "$MODELO"} ${EFFORT:+--effort "$EFFORT"} \
  --kv agente="$AG" --kv origem=hook $FR_KV \
  ${AGID:+--kv agent_id="$AGID"} ${DUR:+--kv duracao_s="$DUR"} \
  $([ "$RETOMADA" = 1 ] && echo '--kv retomada=true') \
  $([ "$HERDADO" = 1 ] && echo '--kv modelo_herdado=true') \
  $([ "$ET_CORRIGIDA" = 1 ] && printf -- '--kv etapa_corrigida=true --kv etapa_checkpoint=%s' "$(printf '%s' "$ET_ANTERIOR" | tr ' ' '_')") \
  ${DESC:+--kv descricao="$DESC"} ${ISOL:+--kv isolation="$ISOL"} \
  ${DUP_SEQ:+--kv duplicado_de="$DUP_SEQ"} >/dev/null 2>&1

exit 0
