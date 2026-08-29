#!/usr/bin/env bash
# test-gad-lifecycle.sh — bancada dos gates de prevenção do hook `hooks/gad-lifecycle.sh`
# (E7 = override de model/effort · E3 = retomada de filho encerrado e 2º despacho).
#
# Alimenta o hook REAL com JSON no stdin, num ambiente de fixture completo (HOME e cwd
# temporários, ponteiro `.gad-rodada-ativa.json`, run-log em tmp, defs reais de
# `agents/`, transcript + subagents/*.meta.json sintéticos) e confere três coisas por
# caso: o stdout (envelope `hookSpecificOutput` do CC 2.1.251), o exit code (sempre 0) e
# o que foi — ou não foi — apendado no run-log.
#
# Uso:  tests/test-gad-lifecycle.sh [--gera-golden]
#   --gera-golden  regrava `fixtures/gad-lifecycle/golden-normal.jsonl` a partir do hook
#                  apontado por $GAD_HOOK (usado uma vez, com o hook PRÉ-mudança, para
#                  que o teste de regressão compare contra o comportamento antigo).
#   $GAD_HOOK      caminho do hook sob teste (default: hooks/gad-lifecycle.sh do repo).
set -u

AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
REPO="$(dirname -- "$AQUI")"
HOOK="${GAD_HOOK:-$REPO/hooks/gad-lifecycle.sh}"
FIX="$AQUI/fixtures/gad-lifecycle"
GOLDEN="$FIX/golden-normal.jsonl"
GERA=0; [ "${1:-}" = "--gera-golden" ] && GERA=1

command -v jq >/dev/null 2>&1 || { echo "jq ausente — bancada não pode rodar"; exit 1; }
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 1; }

falhas=0; ok=0
ok()  { ok=$((ok+1));       echo "PASS: $1"; }
bad() { falhas=$((falhas+1)); echo "FAIL: $1${2:+ — $2}"; }

SESS="bancada0-0000-0000-gadlife"

# ───────────────────────── ambiente de fixture ─────────────────────────
# Cada cenário nasce num sandbox novo: HOME próprio (defs + run-log.sh), projeto próprio
# (ponteiro + phase_dir), transcript próprio (subagents/ para as metas).
PAI=$(mktemp -d) || exit 1
trap 'rm -rf "$PAI"' EXIT
monta() {
  T=$(mktemp -d -p "$PAI") || exit 1
  H="$T/home"; PROJ="$T/proj"; PD="$PROJ/.planning/phases/99-teste"
  RL="$PD/99-RUN-LOG.jsonl"
  TP="$H/.claude/projects/proj/$SESS.jsonl"; SUB="${TP%.jsonl}/subagents"
  mkdir -p "$H/.claude/agents" "$H/.claude/skills/go-and-do" "$PD" \
           "$PROJ/.planning" "$SUB"
  ln -s "$REPO/skills/go-and-do/scripts" "$H/.claude/skills/go-and-do/scripts"
  for d in "$REPO"/agents/gad-*.md; do ln -s "$d" "$H/.claude/agents/$(basename "$d")"; done
  printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-5"}}' > "$TP"
  jq -cn --arg s "$SESS" --arg pd "$PD" --arg rl "$RL" \
    '{session_id:$s, fase:"99 teste", nn:"99", phase_dir:$pd, runlog:$rl}' \
    > "$PROJ/.planning/.gad-rodada-ativa.json"
  : > "$RL"
}
meta() { # $1=id hex  $2=agentType  $3=toolUseId  $4=spawnDepth
  jq -cn --arg at "$2" --arg tu "$3" --argjson sd "$4" \
    '{agentType:$at, toolUseId:$tu, spawnDepth:$sd, model:"claude-opus-5"}' \
    > "$SUB/agent-$1-x.meta.json"
}

# ───────────────────────── payloads ─────────────────────────
p_agent() { # $1=subagent_type  $2=model(""=ausente)  $3=effort("")  $4=tool_use_id
  jq -cn --arg cwd "$PROJ" --arg s "$SESS" --arg tp "$TP" --arg ag "$1" \
         --arg m "${2:-}" --arg e "${3:-}" --arg tu "${4:-tu-000}" '
    {hook_event_name:"PreToolUse", tool_name:"Agent", cwd:$cwd, session_id:$s,
     transcript_path:$tp, tool_use_id:$tu,
     tool_input: ({subagent_type:$ag, description:"caso de bancada"}
        + (if $m == "" then {} else {model:$m} end)
        + (if $e == "" then {} else {effort:$e} end))}'
}
p_post() { # $1=subagent_type  $2=tool_use_id
  jq -cn --arg cwd "$PROJ" --arg s "$SESS" --arg tp "$TP" --arg ag "$1" --arg tu "$2" '
    {hook_event_name:"PostToolUse", tool_name:"Agent", cwd:$cwd, session_id:$s,
     transcript_path:$tp, tool_use_id:$tu,
     tool_input:{subagent_type:$ag, description:"caso de bancada"},
     tool_response:{content:"ok"}}'
}
p_send() { # $1=to
  jq -cn --arg cwd "$PROJ" --arg s "$SESS" --arg tp "$TP" --arg to "$1" '
    {hook_event_name:"PreToolUse", tool_name:"SendMessage", cwd:$cwd, session_id:$s,
     transcript_path:$tp, tool_use_id:"tu-sm",
     tool_input:{to:$to, message:"continue"}}'
}

roda() { # $1=payload → OUT, RC, DELTA (linhas novas no run-log)
  local antes depois
  antes=$(wc -l < "$RL")
  OUT=$(printf '%s' "$1" | HOME="$H" CLAUDE_CODE_SESSION_ID="$SESS" \
        RUNLOG_SEM_ESPELHO=1 bash "$HOOK" 2>/dev/null); RC=$?
  depois=$(wc -l < "$RL")
  DELTA=$((depois - antes))
  ULT=$(tail -n1 "$RL" 2>/dev/null)
}

# ───────────────────────── asserts ─────────────────────────
# negado: exit 0 · stdout = envelope deny válido · run-log ganhou 1 `incidente` e
# NENHUM `despacho` (despacho órfão envenenaria a camada_heuristica).
esp_negado() { # $1=rótulo
  local e=""
  [ "$RC" = 0 ] || e="$e exit=$RC;"
  jq -e . >/dev/null 2>&1 <<<"$OUT" || e="$e stdout não é JSON;"
  [ "$(jq -r '.hookSpecificOutput.hookEventName // ""' <<<"$OUT" 2>/dev/null)" = PreToolUse ] \
    || e="$e hookEventName;"
  [ "$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<<"$OUT" 2>/dev/null)" = deny \
    ] || e="$e permissionDecision;"
  [ -n "$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"$OUT" 2>/dev/null)" ] \
    || e="$e razão vazia;"
  [ "$DELTA" = 1 ] || e="$e delta=$DELTA (esperado 1);"
  [ "$(jq -r '.evento // ""' <<<"$ULT" 2>/dev/null)" = incidente ] || e="$e último≠incidente;"
  grep -q '"evento":"despacho"' <<<"$ULT" && e="$e despacho órfão gravado;"
  [ -z "$e" ] && ok "$1" || bad "$1" "$e"
}
# passou: exit 0 · stdout vazio (nenhuma decisão) · run-log ganhou 1 `despacho`
esp_passou() { # $1=rótulo  $2=agente esperado
  local e=""
  [ "$RC" = 0 ] || e="$e exit=$RC;"
  [ -z "$OUT" ] || e="$e stdout não vazio ($OUT);"
  [ "$DELTA" = 1 ] || e="$e delta=$DELTA (esperado 1);"
  [ "$(jq -r '.evento // ""' <<<"$ULT" 2>/dev/null)" = despacho ] || e="$e último≠despacho;"
  [ "$(jq -r '.agente // ""' <<<"$ULT" 2>/dev/null)" = "$2" ] || e="$e agente errado;"
  [ -z "$e" ] && ok "$1" || bad "$1" "$e"
}

# ═════════════════════ 0. controle positivo ═════════════════════
# Sem isto, todo caso "passa" poderia estar passando pelos guards de no-op do hook
# (ponteiro ausente, sessão divergente, rodada parada, run-log.sh ausente).
monta
roda "$(p_agent gad-intent '' '' tu-ctl)"
esp_passou "controle positivo: Agent(gad-intent) limpo grava despacho" gad-intent
[ "$(jq -r '.camada // ""' <<<"$ULT")" = 1 ] \
  && ok "controle positivo: camada 1" || bad "controle positivo: camada 1" "camada=$(jq -r .camada <<<"$ULT")"

# ═════════════════════ 1. E7 — override de model/effort ═════════════════════
monta
roda "$(p_agent gad-spec fable '' tu-e7a)"
esp_negado "E7: Agent(gad-spec, model=fable) negado"
grep -q 'modelo_override' <<<"$ULT" \
  && ok "E7: incidente com detalhe modelo_override" || bad "E7: incidente com detalhe modelo_override"
# o despacho SEGUINTE (válido) volta a ser camada 1 — o `incidente` é invisível para a
# camada_heuristica (o filtro dela é evento==despacho or evento==retorno).
roda "$(p_agent gad-intent '' '' tu-e7a2)"
esp_passou "E7: despacho seguinte após o deny passa" gad-intent
[ "$(jq -r '.camada // ""' <<<"$ULT")" = 1 ] \
  && ok "E7: despacho seguinte classificado camada 1" \
  || bad "E7: despacho seguinte classificado camada 1" "camada=$(jq -r .camada <<<"$ULT")"

monta
roda "$(p_agent gad-spec fable '' tu-e7t | jq -c '.tool_name="Task"')"
esp_negado "E7: tool_name=Task (mesmo matcher) também é negado"

monta
roda "$(p_agent gad-intent '' high tu-e7b)"
esp_negado "E7: Agent(gad-intent, effort=high) negado (def pina medium)"

monta
roda "$(p_agent gad-intent '' '' tu-e7c)"
esp_passou "E7: Agent(gad-intent) sem model/effort passa" gad-intent

monta
roda "$(p_agent general-purpose opus '' tu-e7d)"
esp_passou "E7: Agent(general-purpose, model=opus) passa (sem def que pina)" general-purpose

monta
printf 'model: claude-sonnet-5\ntools: Read\n' > "$H/.claude/agents/gsd-mempalace-curator.md"
roda "$(p_agent gsd-mempalace-curator opus '' tu-e7f)"
esp_passou "E7: def gsd-* que pina model segue livre (escopo = gad-*)" gsd-mempalace-curator

monta
roda "$(p_agent gad-intent claude-opus-5 medium tu-e7e)"
esp_passou "E7: model/effort IGUAIS à def passam" gad-intent

# ═════════════════════ 2. E3a — SendMessage a filho encerrado ═════════════════════
monta
roda "$(p_send gad-discuss)"
esp_negado "E3a: SendMessage(to: gad-discuss) negado"

monta
meta a1b2c3 gad-spec tu-x 2
roda "$(p_send a1b2c3)"
esp_negado "E3a: SendMessage(to: a1b2c3…) cujo meta é gad-spec negado"

monta
meta a9f9f9 gad-verificador tu-y 2
roda "$(p_send a9f9f9)"
esp_passou "E3a: SendMessage cujo alvo resolve para gad-verificador passa" a9f9f9

monta
roda "$(p_send gad-verificador)"
esp_passou "E3a: SendMessage(to: gad-verificador) literal passa" gad-verificador

# ═════════════════════ 3. E3b — 2º despacho na mesma fase ═════════════════════
monta
roda "$(p_agent gad-discuss '' '' tu-e3b1)"
esp_passou "E3b: Agent(gad-discuss) sem NN-CONTEXT.md passa" gad-discuss
: > "$PD/99-CONTEXT.md"
roda "$(p_agent gad-discuss '' '' tu-e3b2)"
esp_negado "E3b: Agent(gad-discuss) com NN-CONTEXT.md existente negado"

monta
roda "$(p_agent gad-spec '' '' tu-e3b3)"
esp_passou "E3b: Agent(gad-spec) sem NN-SPEC.md passa" gad-spec
: > "$PD/99-SPEC.md"
roda "$(p_agent gad-spec '' '' tu-e3b4)"
esp_negado "E3b: Agent(gad-spec) com NN-SPEC.md existente negado"

# ═════════════════════ 4. regressão — cenário normal × golden ═════════════════════
# Sequência sem nenhum gate acionado; o run-log resultante (sem `ts`, que varia) deve ser
# byte a byte igual ao produzido pelo hook PRÉ-mudança.
cenario_normal() {
  monta
  meta b1 gad-intent tu-n1 1
  meta b2 gad-discuss tu-n2 2
  for pl in "$(p_agent gad-intent '' '' tu-n1)" "$(p_post gad-intent tu-n1)" \
            "$(p_agent gad-discuss '' '' tu-n2)" "$(p_post gad-discuss tu-n2)" \
            "$(p_send gad-verificador)"; do
    printf '%s' "$pl" | HOME="$H" CLAUDE_CODE_SESSION_ID="$SESS" RUNLOG_SEM_ESPELHO=1 \
      bash "$HOOK" >/dev/null 2>&1
  done
  jq -cS 'del(.ts)' "$RL"
}

if [ "$GERA" = 1 ]; then
  mkdir -p "$FIX"
  cenario_normal > "$GOLDEN"
  echo "golden regravado: $GOLDEN ($(wc -l < "$GOLDEN") linhas, hook=$HOOK)"
  exit 0
fi

if [ -f "$GOLDEN" ]; then
  ATUAL=$(cenario_normal)
  if diff -u "$GOLDEN" <(printf '%s\n' "$ATUAL") > "$PAI/diff.txt" 2>&1; then
    ok "regressão: cenário normal idêntico à golden ($(wc -l < "$GOLDEN") eventos)"
  else
    bad "regressão: cenário normal divergiu da golden" "$(head -20 "$PAI/diff.txt" | tr '\n' '|')"
  fi
else
  bad "regressão: golden ausente" "$GOLDEN"
fi

echo "--------------------------------------------------"
echo "$ok ok / $falhas falhas"
[ "$falhas" -eq 0 ]
