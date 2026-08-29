#!/usr/bin/env bash
# abre-rodada.sh — abertura atômica da rodada /go-and-do (decisões 0.1 + 0.2 + adendos).
#
# Encadeia TUDO que é determinístico na abertura e devolve UM JSON. A Etapa 0 vira
# 2 turnos: (1) rodar isto; (2) o modelo interpreta o JSON, espelha a TaskList e obedece
# `etapa_1`/`etapa_2` — o único julgamento que fica, de propósito.
#
# Uso: abre-rodada.sh <N> [--ui] [--ai] [--no-ship] [--vault] [--obs "texto"]
#                     [--projeto DIR] [--dry-run]
#      abre-rodada.sh --registra-aninhamento <ok|falha>   (grava o resultado do probe
#                     S.H com a versão do CC — cache versão-condicionado)
#
# Estágios (falha em QUALQUER um → exit != 0 com motivo e NADA meio-escrito; o evento
# `run` e o ponteiro só nascem se tudo antes passou):
#   1. parse fail-closed dos argumentos (0.1: flag desconhecida/número ausente = erro)
#   2. portões de entrada (gsd-tools resolvível · .planning existe · fase no ROADMAP)
#   3. retrato do disco (init.phase-op N) — diretório = `phase_dir`, ou `expected_phase_dir`
#      quando a fase está no ROADMAP mas ainda não tem pasta (nunca um nome inventado) —
#      + detecção do NN-PRE-SPEC.md (insumo
#      pré-travado pelo usuário → campo `pre_spec` no JSON, repassado à Etapa 1)
#   4. gate de contexto embutido (adendo 0.2: a Etapa 1 NÃO roda gate próprio;
#      status=stop → exit 3 com instrução de retomar fresh)
#   5. decisões de retomada mecânicas: `etapa_1` = pular|despachar|continuar_pergunta
#      (retrato × frontmatter do NN-INTENT-REVIEW.md — por EXISTÊNCIA de artefato,
#      agnóstico à versão que o criou, PC-2) · `etapa_2` = pular|despachar (2.A)
#   6. detecção de vault (5.E-h): fase com cara de UI autenticada sem --vault →
#      `vault_alerta` para a camada 0 perguntar ANTES de gastar a fase
#   7. probe de aninhamento (S.H): cache versão-condicionado do CC em
#      ~/.claude/.gad-aninhamento.json; versão diferente → `probe_necessario` (a camada
#      0 roda o probe e registra com --registra-aninhamento)
#   8. conferência do hook gad-lifecycle no settings (PC-4): ausente → degradação
#      DECLARADA (`hook_instalado: false` no JSON + no evento run; asserts de despacho
#      viram informativos)
#   9. retrato da TaskList (S.C): tarefa → estado desejado, calculado do disco — a
#      camada 0 só espelha com TaskCreate/TaskUpdate
#  10. grava evento `run` (session_id, versão da skill, modelo da camada 0, hook) +
#      ponteiro leve .planning/.gad-rodada-ativa.json (PC-3 — é como o hook global acha
#      o run-log em ms; o stop/fecho da rodada o remove)
#
# Saída: JSON 1 linha + espelho .planning/.gad/last-abre-rodada.json (PC-5).
# Exit: 0 ok · 2 argumento/portão · 3 contexto stop · 4 fase não encontrada (fora do
#       ROADMAP) · 5 fase no ROADMAP mas diretório irresolúvel (phase_dir e
#       expected_phase_dir vazios no init.phase-op).

set -euo pipefail
shopt -s nullglob
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

ANIN_CACHE="$HOME/.claude/.gad-aninhamento.json"
cc_version() { claude --version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -1 || echo desconhecida; }

# ── modo --registra-aninhamento ──────────────────────────────────────────────
if [ "${1:-}" = "--registra-aninhamento" ]; then
  res="${2:-}"
  case "$res" in ok|falha) ;; *) echo "uso: --registra-aninhamento <ok|falha>" >&2; exit 2 ;; esac
  jq -cn --arg v "$(cc_version)" --arg r "$res" --arg ts "$(date -Is)" \
    '{cc_version:$v, resultado:$r, ts:$ts}' > "$ANIN_CACHE"
  echo "aninhamento=$res registrado para CC $(cc_version)"
  exit 0
fi

# ── 1. parse fail-closed (0.1) ───────────────────────────────────────────────
FASE=""; UI=false; AI=false; NO_SHIP=false; VAULT=false; OBS=""; PROJ=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ui) UI=true; shift ;;
    --ai) AI=true; shift ;;
    --no-ship) NO_SHIP=true; shift ;;
    --vault) VAULT=true; shift ;;
    --obs) OBS="${2:-}"; shift 2 ;;
    --projeto) PROJ="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --*) echo "ERRO: flag desconhecida: $1 (aceitas: --ui --ai --no-ship --vault --obs --projeto --dry-run)" >&2; exit 2 ;;
    *) [ -z "$FASE" ] && FASE="$1" || { echo "ERRO: argumento extra: $1" >&2; exit 2; }; shift ;;
  esac
done
case "$FASE" in
  ('') echo "ERRO: número da fase ausente. Uso: abre-rodada.sh <N> [flags]" >&2; exit 2 ;;
  (*[!0-9.]*) echo "ERRO: fase \"$FASE\" não é um número (PC-9: aceita 999.3, não aceita texto)" >&2; exit 2 ;;
esac

# ── 2. portões de entrada ────────────────────────────────────────────────────
ROOT="$(gad_project_root "${PROJ:-$PWD}")"
[ -d "$ROOT/.planning" ] || { echo "ERRO: $ROOT não é projeto GSD (.planning ausente)" >&2; exit 2; }
_gsd_resolve || exit 2

# ── 3. retrato ───────────────────────────────────────────────────────────────
RETRATO=$(cd "$ROOT" && gsd_run query init.phase-op "$FASE" 2>/dev/null | jq -c \
  '{phase_found, phase_number, phase_name, phase_dir, expected_phase_dir, padded_phase, planning_exists,
    has_context, has_plans, has_research, has_reviews, has_verification, plan_count}') \
  || { echo "ERRO: retrato falhou (init.phase-op $FASE)" >&2; exit 2; }
[ "$(jq -r '.phase_found' <<<"$RETRATO")" = "true" ] \
  || { echo "ERRO: fase $FASE não está no ROADMAP deste projeto" >&2; exit 4; }
PHASE_DIR=$(jq -r '.phase_dir // empty' <<<"$RETRATO")
NN=$(jq -r '.padded_phase // empty' <<<"$RETRATO")
# fase no ROADMAP cujo diretório ainda não existe no disco: o próprio GSD diz onde ele
# DEVE nascer (`expected_phase_dir`, já com o prefixo do projeto — ex. RLR-03-deploy).
# Nunca inventar nome: o antigo fallback "$NN-nova" produzia um diretório que nenhum
# workflow do GSD encontra, e o PRE-SPEC do dono ficava invisível.
if [ -z "$PHASE_DIR" ]; then
  PHASE_DIR=$(jq -r '.expected_phase_dir // empty' <<<"$RETRATO")
fi
[ -n "$PHASE_DIR" ] || {
  echo "ERRO: fase $FASE está no ROADMAP mas o diretório não pôde ser resolvido (phase_dir e expected_phase_dir vazios em init.phase-op $FASE) — confira o ROADMAP com /gsd-phase, ou produza o insumo com /gad-pre-spec $FASE" >&2
  exit 5
}

# PRE-SPEC: insumo pré-travado pelo usuário (sessão interativa anterior à rodada).
# Detecção por existência exata, sem glob — se existe, a Etapa 1 o usa como insumo
# do spec/discuss e a camada 0 o declara no sumário executivo.
PRE_SPEC=""
[ -f "$PHASE_DIR/$NN-PRE-SPEC.md" ] && PRE_SPEC="$PHASE_DIR/$NN-PRE-SPEC.md"

# ── 4. gate de contexto embutido ─────────────────────────────────────────────
linha=$("$GAD_SCRIPTS_DIR/context-check.sh" 2>/dev/null || echo "tokens=0 limit=0 pct=0 status=unknown reason=context-check-falhou")
tokens=$(sed -n 's/.*tokens=\([0-9]*\).*/\1/p' <<<"$linha")
limite=$(sed -n 's/.*limit=\([0-9]*\).*/\1/p' <<<"$linha")
pct=$(sed -n 's/.*pct=\([0-9]*\).*/\1/p'      <<<"$linha")
status=$(sed -n 's/.*status=\([a-z]*\).*/\1/p' <<<"$linha")
reason=$(sed -n 's/.*reason=\(.*\)$/\1/p'      <<<"$linha")
CONTEXTO=$(jq -cn --argjson t "${tokens:-0}" --argjson p "${pct:-0}" --argjson l "${limite:-0}" \
  --arg st "${status:-unknown}" --arg rz "$reason" \
  '{tokens:$t,pct:$p,limit:$l,status:$st} + (if $rz != "" then {reason:$rz} else {} end)')
if [ "$status" = "stop" ]; then
  echo "ERRO: contexto em $((tokens/1000))k (teto $((limite/1000))k) JÁ NA ABERTURA — retome numa sessão fresh: /go-and-do $FASE" >&2
  exit 3
fi

# ── 5. retomada mecânica: etapa_1 e etapa_2 ─────────────────────────────────
HAS_PLANS=$(jq -r '.has_plans' <<<"$RETRATO")
IR_FILE=$(ls "$PHASE_DIR/$NN-INTENT-REVIEW.md" 2>/dev/null | head -1 || true)
IR_ESTADO=""
[ -n "$IR_FILE" ] && IR_ESTADO=$(grep -m1 '^intent_review:' "$IR_FILE" | sed 's/^intent_review: *//' | tr -d ' \r' || true)
if [ "$HAS_PLANS" = "true" ] || [ "$IR_ESTADO" = "done" ] || [ "$IR_ESTADO" = "skipped" ]; then
  ETAPA1=pular
elif [ "$IR_ESTADO" = "needs_decision" ]; then
  ETAPA1=continuar_pergunta
else
  ETAPA1=despachar   # sem artefato, ou blocked → re-tenta
fi
[ "$HAS_PLANS" = "true" ] && ETAPA2=pular || ETAPA2=despachar

# ── 6. vault (5.E-h) ─────────────────────────────────────────────────────────
VAULT_ALERTA=false; VAULT_TERMOS=""
if [ "$VAULT" = false ]; then
  VAULT_TERMOS=$(grep -m3 -ihoE 'login|autentica[çc][aã]o|senha|password|sign[ -]?in|sess[aã]o de usu[aá]rio' \
    "$PHASE_DIR/$NN-SPEC.md" "$PHASE_DIR/$NN-CONTEXT.md" 2>/dev/null | sort -u | paste -sd, - || true)
  [ -n "$VAULT_TERMOS" ] && VAULT_ALERTA=true
fi

# ── 7. aninhamento (S.H) — cache versão-condicionado ─────────────────────────
CCV=$(cc_version)
if [ -f "$ANIN_CACHE" ] && [ "$(jq -r '.cc_version' "$ANIN_CACHE" 2>/dev/null)" = "$CCV" ]; then
  ANIN=$(jq -c '{cc_version, resultado, de_cache: true}' "$ANIN_CACHE")
else
  ANIN=$(jq -cn --arg v "$CCV" '{cc_version:$v, resultado:"desconhecido", probe_necessario:true}')
fi

# ── 8. hook gad-lifecycle no settings (PC-4) ─────────────────────────────────
HOOK=false
grep -q "gad-lifecycle" "$HOME/.claude/settings.json" 2>/dev/null && HOOK=true

# ── 9. retrato da TaskList (S.C): tarefa → estado desejado, direto do disco ──
tl() { # tl <id> <descricao> <aplicavel true|false> <pronta true|false>
  jq -cn --argjson n "$1" --arg t "$2" --argjson a "$3" --argjson p "$4" \
    '{tarefa:$n, titulo:$t, estado:(if ($a|not) then "nao_aplicavel" elif $p then "completed" else "pending" end)}'
}
tem() { [ -e "$PHASE_DIR/$NN-$1" ] && echo true || echo false; }
gr()  { grep -qE "$2" "$PHASE_DIR/$NN-$1" 2>/dev/null && echo true || echo false; }
INTENQ=true; [ "$ETAPA1" = pular ] && [ "$(tem SPEC.md)" = false ] && INTENQ=false
TASKS=$(jq -cs '.' <<EOF
$(tl 1  "Intenção — SPEC" $INTENQ "$(tem SPEC.md)")
$(tl 2  "Intenção — CONTEXT" $INTENQ "$(tem CONTEXT.md)")
$(tl 3  "Revisão adversarial de intenção" $INTENQ "$(gr INTENT-REVIEW.md '^intent_review: (done|skipped)')")
$(tl 4  "Contrato de UI" $UI "$(tem UI-SPEC.md)")
$(tl 5  "Contrato de IA" $AI "$(tem AI-SPEC.md)")
$(tl 6  "Planejar" true "$HAS_PLANS")
$(tl 7  "Convergência do plano" true "$(gr CONVERGENCE.md '^convergence: done')")
$(tl 8  "Executar a fase" true "$(jq -r '.has_verification' <<<"$RETRATO")")
$(tl 9  "Code review" true "$(tem REVIEW.md)")
$(tl 10 "UI review" $UI "$(tem UI-REVIEW.md)")
$(tl 11 "Eval review" $AI "$(tem EVAL-REVIEW.md)")
$(tl 12 "Secure phase" true "$(gr SECURITY.md '^threats_open: 0')")
$(tl 13 "Validate phase" true "$(gr VALIDATION.md '^(nyquist_compliant: true|go_and_do_validate: done)')")
$(tl 14 "UAT automatizado" true "$(gr UAT.md '^pre_uat: executed')")
$(tl 15 "Encerramento + ship" true "$(gr RESUMO-EXECUTIVO.md '^go_and_do_resumo: final')")
EOF
)

# ── 10. abertura de fato (fora do --dry-run): evento run + ponteiro ──────────
SESS="${CLAUDE_CODE_SESSION_ID:-}"
MODELO=""
if [ -n "$SESS" ]; then
  _tr=$(find "$HOME/.claude/projects" -name "${SESS}.jsonl" -type f 2>/dev/null | head -n1)
  [ -n "$_tr" ] && MODELO=$(jq -rs '[.[] | select(.type=="assistant") | .message.model] | last // ""' "$_tr" 2>/dev/null || true)
fi
ABERTA=false
if [ "$DRY" = 0 ]; then
  mkdir -p "$PHASE_DIR"
  jq -cn --arg sess "$SESS" --arg fase "$FASE" --arg nn "$NN" --arg pd "$PHASE_DIR" \
    --arg rl "$PHASE_DIR/$NN-RUN-LOG.jsonl" --arg ts "$(date -Is)" \
    --argjson ui "$UI" --argjson ai "$AI" --argjson ns "$NO_SHIP" --argjson va "$VAULT" --arg obs "$OBS" \
    '{session_id:$sess, fase:$fase, nn:$nn, phase_dir:$pd, runlog:$rl, aberta_em:$ts,
      args:{ui:$ui, ai:$ai, no_ship:$ns, vault:$va, obs:$obs}}' \
    > "$ROOT/.planning/.gad-rodada-ativa.json"
  gad_runlog "$PHASE_DIR" "$NN" run "0 abertura" \
    ${MODELO:+--modelo "$MODELO"} --camada 0 \
    --kv hook_instalado=$HOOK --kv etapa_1="$ETAPA1" --kv etapa_2="$ETAPA2" \
    --kv pre_spec="$([ -n "$PRE_SPEC" ] && echo detectado || echo ausente)"
  ABERTA=true
fi

gad_json_out abre-rodada "$(jq -cn \
  --arg fase "$FASE" --arg nn "$NN" --arg pd "$PHASE_DIR" \
  --argjson ui "$UI" --argjson ai "$AI" --argjson ns "$NO_SHIP" --argjson va "$VAULT" --arg obs "$OBS" \
  --argjson retrato "$RETRATO" --argjson ctx "$CONTEXTO" \
  --arg e1 "$ETAPA1" --arg e2 "$ETAPA2" \
  --argjson valerta "$VAULT_ALERTA" --arg vtermos "$VAULT_TERMOS" \
  --argjson anin "$ANIN" --argjson hook "$HOOK" --argjson tasks "$TASKS" --argjson aberta "$ABERTA" \
  --arg ps "$PRE_SPEC" \
  '{args:{fase:$fase, ui:$ui, ai:$ai, no_ship:$ns, vault:$va, obs:$obs},
    retrato:$retrato, contexto:$ctx,
    pre_spec:(if $ps != "" then $ps else null end),
    etapa_1:$e1, etapa_2:$e2,
    vault_alerta:(if $valerta then {alerta:true, termos:$vtermos,
      pergunta:"A fase parece ter UI autenticada e a rodada veio SEM --vault — sem credenciais o UAT queima a fase (24/31 balde-3 da série eram login). Confirmar vault antes de começar?"} else false end),
    aninhamento:$anin, hook_instalado:$hook,
    tasklist:$tasks,
    rodada:{aberta:$aberta, nn:$nn, phase_dir:$pd}}')"
