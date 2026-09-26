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
roda "$(p_agent gad-intent claude-opus-5-5 medium tu-e7e)"
esp_passou "E7: model/effort IGUAIS à def passam" gad-intent

# ── 47a: a def nova `gad-execute` (host da etapa 3) entra nos mesmos trilhos ──
monta
roda "$(p_agent gad-execute '' '' tu-ex1)"
esp_passou "47a: Agent(gad-execute) sem model/effort passa" gad-execute
[ "$(jq -r '.camada // ""' <<<"$ULT")" = 1 ] \
  && ok "47a: gad-execute classificado camada 1 (tools: tem Agent)" \
  || bad "47a: gad-execute classificado camada 1" "camada=$(jq -r .camada <<<"$ULT")"
[ "$(jq -r '.modelo // ""' <<<"$ULT")" = claude-opus-5-5 ] \
  && ok "47a: modelo lido da def (claude-opus-5-5)" \
  || bad "47a: modelo lido da def" "modelo=$(jq -r .modelo <<<"$ULT")"
[ "$(jq -r '.effort // ""' <<<"$ULT")" = medium ] \
  && ok "47a: effort lido da def (medium)" \
  || bad "47a: effort lido da def" "effort=$(jq -r .effort <<<"$ULT")"

monta
roda "$(p_agent gad-execute sonnet '' tu-ex2)"
esp_negado "47a: Agent(gad-execute, model=sonnet) negado pelo E7(b) — o host fica em Opus"

# ── FM-03GAT (bloco D da F4 RLR): a def `gad-gates` (host dos gates 4.x e da rota A do close)
# entra nos mesmos trilhos; serve duas etapas, então NÃO corrige o checkpoint no despacho.
monta
roda "$(p_agent gad-gates '' '' tu-gt1)"
esp_passou "FM-03GAT: Agent(gad-gates) sem model/effort passa" gad-gates
[ "$(jq -r '.camada // ""' <<<"$ULT")" = 1 ] \
  && ok "FM-03GAT: gad-gates classificado camada 1 (tools: tem Agent)" \
  || bad "FM-03GAT: gad-gates classificado camada 1" "camada=$(jq -r .camada <<<"$ULT")"
[ "$(jq -r '.modelo // ""' <<<"$ULT")" = claude-opus-5-5 ] \
  && ok "FM-03GAT: modelo lido da def (claude-opus-5-5)" \
  || bad "FM-03GAT: modelo lido da def" "modelo=$(jq -r .modelo <<<"$ULT")"
[ "$(jq -r '.etapa_corrigida // false' <<<"$ULT")" = false ] \
  && ok "FM-03GAT: gad-gates não corrige o checkpoint (serve 4.x e 6)" \
  || bad "FM-03GAT: gad-gates não corrige o checkpoint" "$(jq -c . <<<"$ULT")"
monta
roda "$(p_agent gad-gates sonnet '' tu-gt2)"
esp_negado "FM-03GAT: Agent(gad-gates, model=sonnet) negado pelo E7(b) — o host fica em Opus"
grep -q 'cacheTtl: 1h' "$REPO/agents/gad-gates.md" "$REPO/agents/gad-contratos.md" 2>/dev/null \
  && [ "$(grep -l 'cacheTtl: 1h' "$REPO"/agents/gad-*.md | wc -l)" -eq 5 ] \
  && ok "FM-03GAT/06ENC: 5 hospedeiros com cacheTtl 1h (intent, contratos, plan, execute, gates)" \
  || bad "FM-03GAT/06ENC: hospedeiros com cacheTtl 1h" "$(grep -l 'cacheTtl: 1h' "$REPO"/agents/gad-*.md | tr '\n' ' ')"

# ── Item C (v2.9.0): gad-plan passou a hospedar a etapa 2 E a 2.5 (convergência) — igual ao
# gad-gates, é multi-etapa e NÃO entra no mapa do FM-02EXE (senão um despacho legítimo com
# checkpoint "2.5 convergencia" seria reescrito para "2 planejamento").
monta
: > "$RL"
printf '{"sessao":"%s","evento":"checkpoint","etapa":"2.5 convergencia"}\n' "${SESS:0:8}" >> "$RL"
roda "$(p_agent gad-plan '' '' tu-c1)"
esp_passou "C: Agent(gad-plan) com checkpoint 2.5 convergencia mantém a etapa (multi-etapa)" gad-plan
[ "$(jq -r '.etapa // ""' <<<"$ULT")" = "2.5 convergencia" ] \
  && ok "C: etapa continua 2.5 convergencia" || bad "C: etapa reescrita indevidamente" "$ULT"
[ "$(jq -r 'has("etapa_corrigida")' <<<"$ULT")" = false ] \
  && ok "C: gad-plan não corrige o checkpoint (serve 2 e 2.5)" || bad "C: etapa_corrigida indevida" "$ULT"

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
# FM-05UAT (F4 RLR, B1 §3): `agente=` no run-log tem de ser o TIPO (agentType do meta),
# não o id hex bruto do `to` — antes deste caso o hook gravava "a9f9f9" (o id), que é
# exatamente o rótulo cego que a auditoria pediu para corrigir.
esp_passou "E3a: SendMessage cujo alvo resolve para gad-verificador passa (agente=TIPO, não id)" gad-verificador

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

# ═════════════════════ 3b. isolation no evento despacho (P04, 01/09) ═════════════════════
monta
roda "$(p_agent gsd-executor '' '' tu-iso | jq -c '.tool_input.isolation="worktree"')"
esp_passou "isolation: Agent(gsd-executor, isolation=worktree) grava despacho" gsd-executor
[ "$(jq -r '.isolation // ""' <<<"$ULT")" = worktree ] \
  && ok "isolation: campo isolation=worktree no evento" || bad "isolation: campo isolation=worktree no evento" "$ULT"
roda "$(p_agent gsd-executor '' '' tu-iso2)"
[ "$(jq -r '.isolation // "ausente"' <<<"$ULT")" = ausente ] \
  && ok "isolation: sem o campo no tool_input, evento não o traz" || bad "isolation: sem o campo no tool_input, evento não o traz" "$ULT"

# ═════════════════════ 3c. F4-RLR bloco B2 ═════════════════════

# FM-02EXE: gad-execute despachado sem checkpoint desta sessão vira "3 construcao"
# (2ª defesa; corrige o rótulo, não valida contra ele). O evento traz a trilha.
monta
roda "$(p_agent gad-execute '' '' tu-fm02a)"
esp_passou "FM-02EXE: Agent(gad-execute) sem checkpoint corrige para etapa 3" gad-execute
[ "$(jq -r '.etapa // ""' <<<"$ULT")" = "3 construcao" ] \
  && ok "FM-02EXE: etapa corrigida para 3 construcao" || bad "FM-02EXE: etapa corrigida" "$ULT"
[ "$(jq -r '.etapa_corrigida // false' <<<"$ULT")" = true ] \
  && ok "FM-02EXE: etapa_corrigida=true na trilha" || bad "FM-02EXE: etapa_corrigida ausente" "$ULT"

# gad-gates hospeda 4.1/4.1b/4.4/4.5 — não mapeia para etapa única, então não corrige nada;
# vale o checkpoint (aqui, "0 abertura" por não haver checkpoint desta sessão).
monta
roda "$(p_agent gad-gates '' '' tu-fm02b)"
esp_passou "FM-02EXE: Agent(gad-gates) não mapeia — checkpoint prevalece" gad-gates
[ "$(jq -r '.etapa // ""' <<<"$ULT")" = "0 abertura" ] \
  && ok "FM-02EXE: gad-gates não corrige (etapa continua 0 abertura)" || bad "FM-02EXE: gad-gates corrigiu indevidamente" "$ULT"

# quando o checkpoint da SESSÃO já diz a etapa certa, nada muda (sem trilha)
monta
: > "$RL"
printf '{"sessao":"%s","evento":"checkpoint","etapa":"3 construcao"}\n' "${SESS:0:8}" >> "$RL"
roda "$(p_agent gad-execute '' '' tu-fm02c)"
esp_passou "FM-02EXE: checkpoint já correto não gera trilha" gad-execute
[ "$(jq -r 'has("etapa_corrigida")' <<<"$ULT")" = false ] \
  && ok "FM-02EXE: sem etapa_corrigida quando já batia" || bad "FM-02EXE: trilha desnecessária" "$ULT"

# SÓ o despacho corrige — um RETORNO que aterrissa com o checkpoint já adiante (caso real,
# RLR F3 seq 660: gad-execute despachado na 2.5/3, retorno 7h depois com o checkpoint já em
# "4.1 code-review") não pode ser reatribuído pra "3 construcao": o custo é do momento em
# que o retorno chegou, não do momento do despacho.
monta
: > "$RL"
printf '{"sessao":"%s","evento":"checkpoint","etapa":"4.1 code-review"}\n' "${SESS:0:8}" >> "$RL"
roda "$(p_post gad-execute tu-fm02d)"
[ "$(jq -r '.etapa // ""' <<<"$ULT")" = "4.1 code-review" ] && [ "$(jq -r 'has("etapa_corrigida")' <<<"$ULT")" = false ] \
  && ok "FM-02EXE: retorno de gad-execute NÃO é reescrito para 3 construcao" \
  || bad "FM-02EXE: retorno reescrito indevidamente" "$ULT"

# FM-04ENC: checkpoint de uma sessão MORTA no mesmo arquivo não vaza para a sessão nova —
# evento antes do 1º checkpoint DESTA sessão sai "0 abertura" (sem o mapeamento do FM-02EXE
# entrando em jogo aqui: general-purpose não mapeia).
monta
: > "$RL"
printf '{"sessao":"velhasess","evento":"checkpoint","etapa":"5 uat"}\n' >> "$RL"
roda "$(p_agent general-purpose '' '' tu-fm04a)"
esp_passou "FM-04ENC: evento pré-checkpoint da sessão nova não herda etapa da antiga" general-purpose
[ "$(jq -r '.etapa // ""' <<<"$ULT")" = "0 abertura" ] \
  && ok "FM-04ENC: etapa = 0 abertura (não 5 uat)" || bad "FM-04ENC: etapa herdada da sessão anterior" "$ULT"

# FM-02GAT (parte do hook): checkpoint "4.1b re-review" é rótulo válido — o próximo evento
# de um agente que NÃO mapeia (general-purpose) preserva o rótulo tal como está.
monta
: > "$RL"
printf '{"sessao":"%s","evento":"checkpoint","etapa":"4.1b re-review"}\n' "${SESS:0:8}" >> "$RL"
roda "$(p_agent general-purpose '' '' tu-fm02gat)"
esp_passou "FM-02GAT: checkpoint 4.1b re-review reconhecido pelo gancho" general-purpose
[ "$(jq -r '.etapa // ""' <<<"$ULT")" = "4.1b re-review" ] \
  && ok "FM-02GAT: etapa = 4.1b re-review preservada" || bad "FM-02GAT: etapa 4.1b re-review perdida" "$ULT"

# FM-03EXE: agente despachado num WORKTREE sem ponteiro local acha o ponteiro na árvore
# principal via git-common-dir.
monta
git -c user.name=x -c user.email=x@x -C "$PROJ" init -q
git -c user.name=x -c user.email=x@x -C "$PROJ" commit -q --allow-empty -m x
WT="$PAI/$(basename "$T")-wt"
git -C "$PROJ" worktree add -q "$WT" -b "wt-$(basename "$T")" >/dev/null 2>&1
PROJ_REAL="$PROJ"; PROJ="$WT"
roda "$(p_agent gad-intent '' '' tu-fm03 | jq -c --arg wt "$WT" '.cwd=$wt')"
PROJ="$PROJ_REAL"
esp_passou "FM-03EXE: Agent despachado em worktree acha o ponteiro pela árvore principal" gad-intent

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

# ───────────────────────── v2.5.4: SubagentStop = fim real ─────────────────────────
echo "── SubagentStop grava retorno com fim_real:true; PostToolUse com fim_real:false ──"
monta
# meta + transcript do agente, como o CC grava: subagents/agent-<id>.meta.json e .jsonl
meta a0aaaa gsd-executor tu-stop-1 2
printf '%s\n' '{"type":"assistant","timestamp":"2026-09-09T15:15:44-03:00","message":{"model":"claude-sonnet-5"}}' > "$SUB/agent-a0aaaa-x.jsonl"
jq -c '. + {description:"Execute plan 01 of phase INS-99", spawnedWithWorktree:true, requestShape:"background"}' \
  "$SUB/agent-a0aaaa-x.meta.json" > "$SUB/tmp.json" && mv "$SUB/tmp.json" "$SUB/agent-a0aaaa-x.meta.json"
# 1) despacho + retorno da chamada (PostToolUse)
roda "$(p_agent gsd-executor "" "" tu-stop-1)"
roda "$(p_post gsd-executor tu-stop-1)"
ult=$(tail -n1 "$RL")
grep -q '"evento":"retorno"' <<<"$ult" && grep -q '"fim_real":false' <<<"$ult" \
  && ok "PostToolUse: retorno com fim_real:false" || bad "PostToolUse fim_real:false" "$ult"
# 2) SubagentStop com transcript_path do agente
P_STOP=$(jq -cn --arg cwd "$PROJ" --arg s "$SESS" --arg tp "$SUB/agent-a0aaaa-x.jsonl" '
  {hook_event_name:"SubagentStop", cwd:$cwd, session_id:$s, agent_id:"a0aaaa", agent_type:"gsd-executor",
   transcript_path:$tp}')
roda "$P_STOP"
ult=$(tail -n1 "$RL")
[ "$DELTA" = 1 ] && ok "SubagentStop: 1 linha nova" || bad "SubagentStop: linhas novas" "$DELTA"
grep -q '"evento":"retorno"' <<<"$ult" && grep -q '"fim_real":true' <<<"$ult" \
  && ok "SubagentStop: retorno com fim_real:true" || bad "SubagentStop fim_real:true" "$ult"
grep -q '"camada":2' <<<"$ult" && ok "…camada 2 (spawnDepth do meta)" || bad "camada do meta" "$ult"
grep -q '"agente":"gsd-executor"' <<<"$ult" && ok "…agente do meta" || bad "agente" "$ult"
grep -q '"agent_id":"a0aaaa"' <<<"$ult" && ok "…agent_id" || bad "agent_id" "$ult"
grep -q '"descricao":"Execute plan 01 of phase INS-99"' <<<"$ult" && ok "…descricao do meta" || bad "descricao" "$ult"
grep -q '"isolation":"worktree"' <<<"$ult" && ok "…isolation worktree (spawnedWithWorktree)" || bad "isolation" "$ult"
grep -Eq '"duracao_s":[0-9]+' <<<"$ult" && ok "…duracao_s numérica" || bad "duracao_s" "$ult"
[ -z "$OUT" ] && ok "…sem stdout (SubagentStop não aceita envelope)" || bad "stdout no SubagentStop" "$OUT"
# 3) SubagentStop sem meta (agente desconhecido): ainda grava, agente = agent_type, sem quebrar
P_STOP2=$(jq -cn --arg cwd "$PROJ" --arg s "$SESS" --arg tp "$SUB/agent-zzz.jsonl" '
  {hook_event_name:"SubagentStop", cwd:$cwd, session_id:$s, agent_id:"zzz", agent_type:"Explore", transcript_path:$tp}')
roda "$P_STOP2"
ult=$(tail -n1 "$RL")
[ "$DELTA" = 1 ] && grep -q '"agente":"Explore"' <<<"$ult" && grep -q '"fim_real":true' <<<"$ult" \
  && ok "SubagentStop sem meta: grava com agent_type" || bad "SubagentStop sem meta" "$ult"
# 3b) SubagentStop sem meta E sem agent_type (subagente interno do CC, ex. classificador do
#     auto mode — F24.5 10/09: 4 linhas órfãs em 2 min) → no-op, nenhuma linha
P_STOP3=$(jq -cn --arg cwd "$PROJ" --arg s "$SESS" --arg tp "$SUB/agent-nada.jsonl" '
  {hook_event_name:"SubagentStop", cwd:$cwd, session_id:$s, agent_id:"nada", agent_type:"", transcript_path:$tp, agent_transcript_path:$tp}')
roda "$P_STOP3"
[ "$DELTA" = 0 ] && ok "SubagentStop sem meta e sem agent_type: no-op" || bad "SubagentStop interno do CC gravou linha" "$(tail -n1 "$RL")"
# 4) descrição multibyte cortada por caracteres, não bytes (45g)
D120=$(python3 -c 'print("ção"*50)')
P_MB=$(jq -cn --arg cwd "$PROJ" --arg s "$SESS" --arg tp "$TP" --arg d "$D120" '
  {hook_event_name:"PreToolUse", tool_name:"Agent", cwd:$cwd, session_id:$s, transcript_path:$tp,
   tool_use_id:"tu-mb", tool_input:{subagent_type:"gsd-executor", description:$d}}')
roda "$P_MB"
tail -n1 "$RL" | python3 -c 'import sys,json; d=json.loads(sys.stdin.buffer.read().decode("utf-8")); assert len(d["descricao"])==120, len(d["descricao"])' \
  && ok "descricao: 120 caracteres, UTF-8 íntegro" || bad "descricao multibyte" "$(tail -n1 "$RL" | cut -c1-200)"

# ───────── FM-05UAT: dedup do "único terminou" (retomada + SubagentStop do mesmo agente) ─────────
# PROVADO 10/09: um filho aninhado que encerra o TURNO com filho vivo é acordado de novo pela
# task-notification — o CC pode disparar SubagentStop mais de uma vez para o MESMO agent_id
# (turno encerrado ≠ agente morto). Sem dedup, cada disparo vira um `retorno fim_real:true`,
# contando a mesma finalização em dobro na auditoria (confere-etapa.sh 3).
echo "── FM-05UAT: dedup do único terminou (retomada + SubagentStop do mesmo agent_id) ──"
monta
meta a0dedup gad-verificador tu-dedup-1 2
printf '%s\n' '{"type":"assistant","timestamp":"2026-09-10T10:00:00-03:00","message":{"model":"claude-sonnet-5"}}' > "$SUB/agent-a0dedup-x.jsonl"

# 1) despacho inicial
roda "$(p_agent gad-verificador "" "" tu-dedup-1)"

# 2) 1º SubagentStop do agente — o "terminou" que deve valer
P_STOP_DUP=$(jq -cn --arg cwd "$PROJ" --arg s "$SESS" --arg tp "$SUB/agent-a0dedup-x.jsonl" '
  {hook_event_name:"SubagentStop", cwd:$cwd, session_id:$s, agent_id:"a0dedup",
   agent_type:"gad-verificador", transcript_path:$tp}')
roda "$P_STOP_DUP"
ult=$(tail -n1 "$RL")
grep -q '"fim_real":true' <<<"$ult" \
  && ok "dedup: 1º SubagentStop do agente grava fim_real:true" \
  || bad "dedup: 1º SubagentStop deveria gravar fim_real:true" "$ult"
SEQ1=$(jq -r '.seq' <<<"$ult")

# 3) retomada por SendMessage ao mesmo agente (id hex): despacho + retorno da CHAMADA com
#    retomada:true — nunca fim_real:true (a retomada não seta FIM_REAL).
roda "$(p_send a0dedup)"
esp_passou "dedup: SendMessage(to: a0dedup) retomada passa (despacho)" gad-verificador
P_SEND_POST=$(jq -cn --arg cwd "$PROJ" --arg s "$SESS" --arg tp "$TP" '
  {hook_event_name:"PostToolUse", tool_name:"SendMessage", cwd:$cwd, session_id:$s,
   transcript_path:$tp, tool_use_id:"tu-sm-dedup",
   tool_input:{to:"a0dedup", message:"continue"}, tool_response:{content:"ok"}}')
roda "$P_SEND_POST"
ult=$(tail -n1 "$RL")
grep -q '"evento":"retorno"' <<<"$ult" && grep -q '"fim_real":false' <<<"$ult" && grep -q '"retomada":true' <<<"$ult" \
  && ok "dedup: retorno da retomada (PostToolUse SendMessage) sai fim_real:false" \
  || bad "dedup: retorno da retomada" "$ult"

# 4) 2º SubagentStop do MESMO agent_id (fim de verdade) — não pode virar um 2º "terminou":
#    fim_real:false + duplicado_de:<seq do 1º fim_real:true>.
roda "$P_STOP_DUP"
ult=$(tail -n1 "$RL")
grep -q '"evento":"retorno"' <<<"$ult" && grep -q '"fim_real":false' <<<"$ult" \
  && ok "dedup: 2º SubagentStop do mesmo agent_id não é fim_real:true" \
  || bad "dedup: 2º SubagentStop deveria ser fim_real:false" "$ult"
[ "$(jq -r '.duplicado_de // empty' <<<"$ult")" = "$SEQ1" ] \
  && ok "dedup: duplicado_de aponta pro seq do 1º fim_real:true ($SEQ1)" \
  || bad "dedup: duplicado_de incorreto" "$ult (esperado duplicado_de=$SEQ1)"

# no run-log inteiro, só 1 fim_real:true para este agent_id
CNT=$(grep -F '"agent_id":"a0dedup"' "$RL" | grep -c '"fim_real":true')
[ "$CNT" = 1 ] && ok "dedup: exatamente 1 fim_real:true para agent_id a0dedup no run-log" \
  || bad "dedup: contagem de fim_real:true para a0dedup" "esperado 1, achei $CNT"

# ───────── t59 FM-F27INS-05INT: aviso assíncrono × parada com filho vivo × parada final ─────────
# Montado a partir do run-log real da F27 INS (grupo-inspired, sessão 2557efcc, seq 7–33):
#   seq 7/8   despacho gad-intent + retorno 1 s depois com o modelo da sessão principal (é o
#             aviso «Async agent launched», não retorno)
#   seq 13    gad-intent fim_real:true aos 47 s — parou para esperar o gad-spec (a70c…) VIVO
#   seq 18    gad-spec fim_real:true
#   seq 21…33 paradas seguintes do gad-intent saem duplicado_de:13 e o fim de verdade some
# Ids e descrições são os reais; o meta segue o formato real (agent-<id>.meta.json, sem sufixo).
echo "── t59 FM-F27INS-05INT: aviso assíncrono não grava; parada com filho vivo é provisória ──"
monta
HOST=a658bcaf96ef7e260; SPEC=a70c5bac6780dc18e; EXPL=a3f8fe0be223d14c3
D_HOST="Etapa 1 intenção fase 27"; D_SPEC="Gerar SPEC da fase 27"; D_EXPL="Explorar comportamento atual por R-n"
meta_real() { # $1=id $2=agentType $3=toolUseId $4=spawnDepth $5=descrição [$6=parentAgentId]
  jq -cn --arg at "$2" --arg tu "$3" --argjson sd "$4" --arg d "$5" --arg p "${6:-}" '
    {agentType:$at, description:$d, toolUseId:$tu} + (if $p == "" then {} else {parentAgentId:$p} end)
    + {spawnDepth:$sd, requestShape:"background", requestNonInteractive:true}' > "$SUB/agent-$1.meta.json"
  printf '%s\n' '{"type":"assistant","timestamp":"2026-09-25T10:01:33-03:00","message":{"model":"claude-opus-5-5"}}' \
    > "$SUB/agent-$1.jsonl"
}
p_pre_d() { # $1=subagent_type $2=descrição $3=tool_use_id
  jq -cn --arg cwd "$PROJ" --arg s "$SESS" --arg tp "$TP" --arg ag "$1" --arg d "$2" --arg tu "$3" '
    {hook_event_name:"PreToolUse", tool_name:"Agent", cwd:$cwd, session_id:$s, transcript_path:$tp,
     tool_use_id:$tu, tool_input:{subagent_type:$ag, description:$d}}'
}
p_post_async() { # $1=subagent_type $2=descrição $3=tool_use_id $4=agentId $5=forma (obj|str|content)
  jq -cn --arg cwd "$PROJ" --arg s "$SESS" --arg tp "$TP" --arg ag "$1" --arg d "$2" --arg tu "$3" \
         --arg id "$4" --arg f "$5" '
    ("Async agent launched successfully.\nagentId: " + $id + "\nThe agent is working in the background.") as $txt
    | {hook_event_name:"PostToolUse", tool_name:"Agent", cwd:$cwd, session_id:$s, transcript_path:$tp,
       tool_use_id:$tu, tool_input:{subagent_type:$ag, description:$d},
       tool_response: (if $f == "obj" then {isAsync:true, status:"async_launched", agentId:$id, description:$d}
                       elif $f == "str" then $txt
                       else {content:[{type:"text", text:$txt}]} end)}'
}
p_stop_real() { # $1=agent_id $2=agent_type
  jq -cn --arg cwd "$PROJ" --arg s "$SESS" --arg tp "$SUB/agent-$1.jsonl" --arg id "$1" --arg at "$2" '
    {hook_event_name:"SubagentStop", cwd:$cwd, session_id:$s, agent_id:$id, agent_type:$at,
     transcript_path:$tp, agent_transcript_path:$tp}'
}

# 1) despacho do host (camada 0 → 1) e o aviso assíncrono nas três formas: nenhuma linha
roda "$(p_pre_d gad-intent "$D_HOST" toolu_01Kxjc4xerbsEkXvzo6TV7gk)"
esp_passou "F27: despacho do gad-intent" gad-intent
meta_real "$HOST" gad-intent toolu_01Kxjc4xerbsEkXvzo6TV7gk 1 "$D_HOST"
for _f in obj str content; do
  roda "$(p_post_async gad-intent "$D_HOST" toolu_01Kxjc4xerbsEkXvzo6TV7gk "$HOST" "$_f")"
  [ "$DELTA" = 0 ] && [ "$RC" = 0 ] && [ -z "$OUT" ] \
    && ok "aviso «Async agent launched» ($_f): nenhuma linha no run-log" \
    || bad "aviso assíncrono ($_f) gravou" "delta=$DELTA rc=$RC $(tail -n1 "$RL")"
done
# PostToolUse de Agent síncrono (resposta sem o aviso) continua gravando fim_real:false
roda "$(p_post gsd-executor tu-sincrono)"
[ "$DELTA" = 1 ] && grep -q '"fim_real":false' <<<"$ULT" \
  && ok "PostToolUse síncrono (sem aviso) continua gravando retorno fim_real:false" \
  || bad "PostToolUse síncrono" "delta=$DELTA $ULT"

# 2) o host despacha o gad-spec: host sem retorno → camada 2 (hoje a F27 gravou 1, seq 11)
roda "$(p_pre_d gad-spec "$D_SPEC" toolu_019AuYxGp8qowTGMX7XK2cwK)"
esp_passou "F27: despacho do gad-spec pelo host" gad-spec
[ "$(jq -r .camada <<<"$ULT")" = 2 ] && ok "gad-spec despachado com o host aberto sai camada 2" \
  || bad "camada do gad-spec" "$ULT"
meta_real "$SPEC" gad-spec toolu_019AuYxGp8qowTGMX7XK2cwK 2 "$D_SPEC" "$HOST"
roda "$(p_post_async gad-spec "$D_SPEC" toolu_019AuYxGp8qowTGMX7XK2cwK "$SPEC" obj)"
[ "$DELTA" = 0 ] && ok "aviso assíncrono do gad-spec: nenhuma linha" || bad "aviso do gad-spec gravou" "$ULT"

# 3) host para esperando o gad-spec VIVO → parada provisória (era o seq 13 fim_real:true, 47 s)
roda "$(p_stop_real "$HOST" gad-intent)"
[ "$DELTA" = 1 ] && grep -q '"evento":"retorno"' <<<"$ULT" && grep -q '"fim_real":false' <<<"$ULT" \
  && ok "parada do host com filho vivo: retorno fim_real:false" || bad "parada com filho vivo" "$ULT"
[ "$(jq -r '.parada_provisoria' <<<"$ULT")" = true ] && [ "$(jq -r '.filhos_vivos' <<<"$ULT")" = 1 ] \
  && ok "…parada_provisoria:true, filhos_vivos:1" || bad "marcadores da parada provisória" "$ULT"
[ "$(jq -r '.duplicado_de // "nenhum"' <<<"$ULT")" = nenhum ] && grep -q "\"agent_id\":\"$HOST\"" <<<"$ULT" \
  && grep -Eq '"duracao_s":[0-9]+' <<<"$ULT" \
  && ok "…sem duplicado_de, com agent_id e duracao_s" || bad "parada provisória: campos" "$ULT"

# 4) host (ainda vivo) despacha o gad-explore depois da parada provisória → camada 2
#    (na F27, seq 19, saiu camada 1: o 1º stop já tinha «fechado» o host)
roda "$(p_pre_d gad-explore "$D_EXPL" toolu_explore)"
[ "$(jq -r .camada <<<"$ULT")" = 2 ] && ok "despacho após parada provisória: camada 2 (host segue aberto)" \
  || bad "camada após parada provisória" "$ULT"
meta_real "$EXPL" gad-explore toolu_explore 2 "$D_EXPL" "$HOST"

# 5) gad-spec termina de verdade (sem filho) → fim_real:true
roda "$(p_stop_real "$SPEC" gad-spec)"
grep -q '"fim_real":true' <<<"$ULT" && [ "$(jq -r '.parada_provisoria // false' <<<"$ULT")" = false ] \
  && ok "filho sem filho próprio: fim_real:true" || bad "fim do gad-spec" "$ULT"

# 6) host para de novo com o gad-explore vivo → provisória, filhos_vivos:1 (o gad-spec já fechou)
roda "$(p_stop_real "$HOST" gad-intent)"
grep -q '"fim_real":false' <<<"$ULT" && [ "$(jq -r '.filhos_vivos' <<<"$ULT")" = 1 ] \
  && ok "2ª parada com 1 filho vivo (o terminado não conta): provisória, filhos_vivos:1" \
  || bad "2ª parada provisória" "$ULT"

# 7) o gad-explore termina SEM SubagentStop no run-log (hook no-op, por ex.), mas a
#    task-notification dele chegou ao transcript do host → a próxima parada é o fim de verdade
printf '%s\n' "{\"type\":\"user\",\"message\":{\"content\":\"<task-notification>\\n<task-id>$EXPL</task-id>\\n<status>completed</status>\"}}" \
  >> "$SUB/agent-$HOST.jsonl"
roda "$(p_stop_real "$HOST" gad-intent)"
grep -q '"fim_real":true' <<<"$ULT" && [ "$(jq -r '.duplicado_de // "nenhum"' <<<"$ULT")" = nenhum ] \
  && [ "$(jq -r '.parada_provisoria // false' <<<"$ULT")" = false ] \
  && ok "parada sem filho vivo (task-notification no transcript do pai): fim_real:true" \
  || bad "parada final do host" "$ULT"
SEQ_FIM=$(jq -r .seq <<<"$ULT")

# 8) parada depois do fim (retomada) → duplicado_de aponta para a parada FINAL, não para a 1ª
roda "$(p_stop_real "$HOST" gad-intent)"
[ "$(jq -r '.duplicado_de // empty' <<<"$ULT")" = "$SEQ_FIM" ] && grep -q '"fim_real":false' <<<"$ULT" \
  && ok "parada pós-fim: duplicado_de = seq do fim real ($SEQ_FIM)" || bad "duplicado pós-fim" "$ULT (esperado $SEQ_FIM)"
for _id in "$HOST" "$SPEC"; do
  CNT=$(grep -F "\"agent_id\":\"$_id\"" "$RL" | grep -c '"fim_real":true')
  [ "$CNT" = 1 ] && ok "exatamente 1 fim_real:true para $_id" || bad "fim_real:true de $_id" "achei $CNT"
done
ESP=$(grep -F "\"descricao\":\"$D_HOST\"" "$RL" | grep -F '"evento":"retorno"' | grep -vc '"agent_id"')
[ "$ESP" = 0 ] \
  && ok "nenhum retorno do host sem agent_id (o aviso assíncrono não entrou)" \
  || bad "retorno espúrio do host" "$(grep -F "$D_HOST" "$RL" | grep retorno | head -3)"

# 9) host fechado → novo despacho da camada 0 volta a sair camada 1
roda "$(p_pre_d gad-plan "Etapa 2 planejamento fase 27" toolu_plan)"
[ "$(jq -r .camada <<<"$ULT")" = 1 ] && ok "depois do fim real do host, despacho da camada 0 sai camada 1" \
  || bad "camada depois do fim do host" "$ULT"

# 10) sessão anterior com despacho aberto (SubagentStop perdido) não contamina a sessão atual
monta
printf '%s\n' '{"ts":"2026-09-25T09:00:00-03:00","seq":1,"sessao":"outra000","evento":"despacho","etapa":"1 intencao","camada":1,"agente":"general-purpose","origem":"hook","descricao":"órfão da sessão anterior"}' > "$RL"
roda "$(p_pre_d gad-intent "$D_HOST" tu-sessao)"
[ "$(jq -r .camada <<<"$ULT")" = 1 ] && ok "despacho aberto de OUTRA sessão não empurra para camada 2" \
  || bad "heurística olhou outra sessão" "$ULT"

# 11) fail-open: SubagentStop com meta mas sem agent_id → sem a checagem de filhos, fim_real:true
monta
meta_real "$HOST" gad-intent tu-x 1 "$D_HOST"
meta_real "$SPEC" gad-spec tu-y 2 "$D_SPEC" "$HOST"
P_SEMID=$(jq -cn --arg cwd "$PROJ" --arg s "$SESS" --arg tp "$SUB/agent-$HOST.jsonl" '
  {hook_event_name:"SubagentStop", cwd:$cwd, session_id:$s, agent_type:"gad-intent", transcript_path:$tp}')
roda "$P_SEMID"
[ "$RC" = 0 ] && [ "$DELTA" = 1 ] && grep -q '"fim_real":true' <<<"$ULT" \
  && ok "fail-open: sem agent_id não há checagem de filhos (fim_real:true, como antes)" \
  || bad "fail-open sem agent_id" "rc=$RC delta=$DELTA $ULT"

echo "--------------------------------------------------"
echo "$ok ok / $falhas falhas"
[ "$falhas" -eq 0 ]
