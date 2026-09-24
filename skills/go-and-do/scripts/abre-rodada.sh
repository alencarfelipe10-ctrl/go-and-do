#!/usr/bin/env bash
# abre-rodada.sh — abertura atômica da rodada /go-and-do (decisões 0.1 + 0.2 + adendos).
#
# Encadeia TUDO que é determinístico na abertura e devolve UM JSON. A Etapa 0 vira
# 2 turnos: (1) rodar isto; (2) o modelo interpreta o JSON, espelha a TaskList e obedece
# `etapa_1`/`etapa_2` — o único julgamento que fica, de propósito.
#
# Uso: abre-rodada.sh <N> [--ui] [--ai] [--no-ship] [--vault <perfil>] [--obs texto até a próxima flag]
#                     [--projeto DIR] [--dry-run]
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
#      agnóstico à versão que o criou, PC-2) · `etapa_2` = pular|despachar|continuar-2.4b
#      (2.A; `continuar-2.4b` — S-11, tarefa 48l — quando há `NN-PLAN.md` com
#      `autonomous: false` e a fase ainda não tem `has_verification`: a marca de
#      resolução é o próprio frontmatter virar `autonomous: true`, `nao_autonomos_pendentes`
#      no JSON lista os planos)
#   6. detecção de vault (5.E-h): fase com UI (--ui ou UI-SPEC), sem --vault e com UAT
#      ainda não executado, com termos de login no ROADMAP/SPEC/CONTEXT/PRE-SPEC →
#      `vault_alerta` para a camada 0 perguntar ANTES de gastar a fase
#   7. conferência do hook gad-lifecycle no settings (PC-4): só telemetria (`--kv
#      hook_instalado` no evento `run`); não entra no JSON do modelo
#   8. retrato da TaskList (S.C): tarefa → estado desejado, calculado do disco — a
#      camada 0 só espelha com TaskCreate/TaskUpdate
#   9. grava evento `run` (session_id, versão da skill, modelo da camada 0, hook,
#      cc_version) +
#      ponteiro leve .planning/.gad/rodada-ativa.json (PC-3 — é como o hook global acha
#      o run-log em ms; o stop/fecho da rodada o remove). v2.10.1 (56(a)): grava SÓ o novo
#      e apaga o legado .planning/.gad-rodada-ativa.json (dois apontadores divergentes
#      seriam pior que nenhum).
#  10. limpeza (56(c)): apaga os `.planning/.gad-last-*.json` órfãos (ninguém lê desde o
#      8828baa) e as cópias velhas `.planning/.gad/last-<slug-de-cópia>.json` (a cópia mora
#      no cache desde a 56(f)). SÓ o que não está no índice do git: o rastreado sai em
#      `legado_rastreado` e o README ensina o comando de uma linha — o script nunca muda
#      o índice. Saída: `limpeza: [...]` (apagados) e `legado_rastreado: [...]`.
#
# Saída: JSON 1 linha + espelho last-abre-rodada.json no cache fora do git (PC-5; o caminho é
# a 1ª chave, `espelho`).
# Exit: 0 ok · 2 argumento/portão · 3 contexto stop · 4 fase não encontrada (fora do
#       ROADMAP) · 5 fase no ROADMAP mas diretório irresolúvel (phase_dir e
#       expected_phase_dir vazios no init.phase-op).

set -euo pipefail
shopt -s nullglob
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

cc_version() { claude --version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -1 || echo desconhecida; }

# ── 1. parse fail-closed (0.1) ───────────────────────────────────────────────
exige_valor() { case "${2-}" in ''|--*) echo "ERRO: $1 exige um valor" >&2; exit 2 ;; esac; }
FASE=""; UI=false; AI=false; NO_SHIP=false; VAULT=false; VAULT_PROFILE=""; OBS=""; PROJ=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ui) UI=true; shift ;;
    --ai) AI=true; shift ;;
    --no-ship) NO_SHIP=true; shift ;;
    --vault) exige_valor --vault "${2-}"; VAULT=true; VAULT_PROFILE="$2"; shift 2 ;;
    --obs) shift
      while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do OBS="${OBS:+$OBS }$1"; shift; done
      [ -n "$OBS" ] || { echo "ERRO: --obs exige um texto" >&2; exit 2; } ;;
    --projeto) exige_valor --projeto "${2-}"; PROJ="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --*) echo "ERRO: flag desconhecida: $1 (aceitas: --ui --ai --no-ship --vault --obs --projeto --dry-run)" >&2; exit 2 ;;
    *) [ -z "$FASE" ] && FASE="$1" || { echo "ERRO: argumento extra: $1" >&2; exit 2; }; shift ;;
  esac
done
case "$FASE" in
  ('') echo "ERRO: número da fase ausente. Uso: abre-rodada.sh <N> [flags] (o número vem antes do --obs)" >&2; exit 2 ;;
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
# Inventário da fase (D7): só relata o que existe no disco — a decisão de rota é do
# setup-intencao.sh. SPEC e CONTEXT presentes vencem o PRE-SPEC (o insumo não trava
# uma intenção já escrita), e o coordenador declara o inventário no primeiro turno.
sn() { [ -f "$1" ] && echo sim || echo nao; }
INVENTARIO="spec=$(sn "$PHASE_DIR/$NN-SPEC.md") context=$(sn "$PHASE_DIR/$NN-CONTEXT.md") pre_spec=$(sn "$PHASE_DIR/$NN-PRE-SPEC.md")"
tem() { [ -e "$PHASE_DIR/$NN-$1" ] && echo true || echo false; }
gr()  { grep -qE "$2" "$PHASE_DIR/$NN-$1" 2>/dev/null && echo true || echo false; }

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
IR_FILE=""; [ -f "$PHASE_DIR/$NN-INTENT-REVIEW.md" ] && IR_FILE="$PHASE_DIR/$NN-INTENT-REVIEW.md"
IR_ESTADO=""
[ -n "$IR_FILE" ] && IR_ESTADO=$(grep -m1 '^intent_review:' "$IR_FILE" | sed 's/^intent_review: *//' | tr -d ' \r' || true)
# Item 4 (F4 RLR): `aprovado_com_ressalva` fecha a etapa 1 tanto quanto done/skipped —
# senão uma fase fechada com ressalva reabre a etapa 1 ao retomar.
if [ "$HAS_PLANS" = "true" ] || [ "$IR_ESTADO" = "done" ] || [ "$IR_ESTADO" = "skipped" ] || [ "$IR_ESTADO" = "aprovado_com_ressalva" ]; then
  ETAPA1=pular
elif [ "$IR_ESTADO" = "needs_decision" ]; then
  ETAPA1=continuar_pergunta
else
  ETAPA1=despachar   # sem artefato, ou blocked → re-tenta
fi

# S-11 (auditoria 48, tarefa 48l): plano `autonomous: false` sem resolução — a marca de
# resolução É o próprio frontmatter virando `autonomous: true` (workflow-etapa-2.md §2.4b: toda
# rota (a)/(b)/(c) "flips the plan to autonomous: true" antes de fechar o checkpoint).
# Fase JÁ verificada (`has_verification`) nunca reabre 2.4b: 3.1 do workflow diz que os
# planos chegam à etapa 3 já virados — reabrir aqui seria confundir plano arquivado.
NAO_AUTONOMOS_LIST=""
if [ "$HAS_PLANS" = "true" ] && [ "$(jq -r '.has_verification' <<<"$RETRATO")" != "true" ]; then
  for f in "$PHASE_DIR"/*-PLAN.md; do
    [ -f "$f" ] || continue
    grep -qE '^autonomous:[[:space:]]*false[[:space:]]*$' "$f" 2>/dev/null || continue
    b=$(basename -- "$f"); b="${b#$NN-}"; id="${b%-PLAN.md}"
    NAO_AUTONOMOS_LIST="${NAO_AUTONOMOS_LIST:+$NAO_AUTONOMOS_LIST,}$id"
  done
fi
if [ "$HAS_PLANS" = "true" ]; then
  if [ -n "$NAO_AUTONOMOS_LIST" ]; then ETAPA2=continuar-2.4b; else ETAPA2=pular; fi
else
  ETAPA2=despachar
fi

# ── 6. vault (5.E-h) ─────────────────────────────────────────────────────────
VAULT_ALERTA=false; VAULT_TERMOS=""
if [ "$VAULT" = false ] && { [ "$UI" = true ] || [ "$(tem UI-SPEC.md)" = true ]; } \
   && [ "$(gr UAT.md '^pre_uat: executed')" = false ]; then
  SECAO_ROADMAP=$(cd "$ROOT" && gsd_run query roadmap.get-phase "$FASE" 2>/dev/null | jq -r '.section // empty' 2>/dev/null || true)
  VAULT_TERMOS=$( { printf '%s\n' "$SECAO_ROADMAP"
                    cat "$PHASE_DIR/$NN-SPEC.md" "$PHASE_DIR/$NN-CONTEXT.md" "$PHASE_DIR/$NN-PRE-SPEC.md" 2>/dev/null; } \
    | grep -ioE 'login|autentica[çc][aã]o|senha|password|sign[ -]?in|sess[aã]o de usu[aá]rio' \
    | sort -u | head -5 | paste -sd, - || true)
  [ -n "$VAULT_TERMOS" ] && VAULT_ALERTA=true
fi

# ── 6b. observação pós-ship de fases anteriores + superfície de UAT (2.7.0) ───
# Item `bloqueia_proxima: sim` ainda sem `observado_em` em OUTRA fase → a camada 0
# pergunta antes de gastar a fase (mesmo molde do vault). A fase nomeada no
# `verificavel_em` do item é isenta — é nela que ele se observa.
POS_SHIP=$(python3 "$GAD_SCRIPTS_DIR/pos-ship.py" gate "$ROOT" "$FASE" 2>/dev/null || true)
jq -e '.pendentes' >/dev/null 2>&1 <<<"$POS_SHIP" || POS_SHIP='{"veredito":"ok","pendentes":[]}'
# contrato de UAT do projeto (como subir/dirigir a superfície sem segredo real)
UAT_SUPERFICIE=""; [ -f "$ROOT/.planning/uat-superficie.md" ] && UAT_SUPERFICIE="$ROOT/.planning/uat-superficie.md"

# versão do CC para o evento run (o probe de aninhamento S.H saiu na 2.6.3; o /cc-watch vigia)
CCV=$(cc_version)

# ── 7. hook gad-lifecycle no settings (PC-4) ─────────────────────────────────
HOOK=false
grep -q "gad-lifecycle" "$HOME/.claude/settings.json" 2>/dev/null && HOOK=true

# ── 8. retrato da TaskList (S.C): tarefa → estado desejado, direto do disco ──
tl() { # tl <id> <descricao> <aplicavel true|false> <pronta true|false>
  jq -cn --argjson n "$1" --arg t "$2" --argjson a "$3" --argjson p "$4" \
    '{tarefa:$n, titulo:$t, estado:(if ($a|not) then "nao_aplicavel" elif $p then "completed" else "pending" end)}'
}
INTENQ=true; [ "$ETAPA1" = pular ] && [ "$(tem SPEC.md)" = false ] && INTENQ=false
TASKS=$(jq -cs '.' <<EOF
$(tl 1  "Intenção — SPEC" $INTENQ "$(tem SPEC.md)")
$(tl 2  "Intenção — CONTEXT" $INTENQ "$(tem CONTEXT.md)")
$(tl 3  "Consultoria especializada de intenção" $INTENQ "$(gr INTENT-REVIEW.md '^intent_review: (done|skipped|aprovado_com_ressalva)')")
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

# ── 9. abertura de fato (fora do --dry-run): evento run + ponteiro ───────────
SESS="${CLAUDE_CODE_SESSION_ID:-}"
MODELO=""
if [ -n "$SESS" ]; then
  _tr=$(find "$HOME/.claude/projects" -name "${SESS}.jsonl" -type f 2>/dev/null | head -n1)
  [ -n "$_tr" ] && MODELO=$(jq -rs '[.[] | select(.type=="assistant") | .message.model] | last // ""' "$_tr" 2>/dev/null || true)
fi
ABERTA=false
# ── 9a. formato da evidência da fase (57(b), v2.10.1) ─────────────────────────
# Quem abre a fase decide: fase SEM nenhuma evidência no formato antigo nasce no formato
# novo (`.gad/FORMATO` + `.gad/lanes/.gitignore`); com evidência antiga fica antiga —
# uma fase nunca mistura os dois. O marcador é COMMITADO aqui, antes de qualquer etapa
# (a primeira evidência da Etapa 1 e as worktrees da Etapa 3 já nascem vendo o formato).
# Commit com pathspec explícito (`--only`): o que o dono tiver staged fica como estava.
FORMATO="$(gad_fase_formato "$PHASE_DIR")"; FORMATO_COMMIT=nao_aplicavel
if [ "$DRY" = 0 ]; then
  mkdir -p "$PHASE_DIR"
  FORMATO="$(gad_fase_inicia "$PHASE_DIR")"
  if [ "$FORMATO" = novo ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    _fm=("$PHASE_DIR/.gad/FORMATO" "$PHASE_DIR/.gad/lanes/.gitignore")
    if git -C "$ROOT" ls-files --error-unmatch -- "${_fm[@]}" >/dev/null 2>&1 \
       && git -C "$ROOT" diff --quiet HEAD -- "${_fm[@]}" 2>/dev/null; then
      FORMATO_COMMIT=ja_commitado
    else
      git -C "$ROOT" add -f -- "${_fm[@]}" 2>/dev/null || true
      if git -C "$ROOT" commit -q --only -m "docs(fase $NN): formato da evidência da fase (.gad/FORMATO, go-and-do v2.10.1)" \
           -- "${_fm[@]}" >/dev/null 2>&1; then FORMATO_COMMIT=ok; else FORMATO_COMMIT=falhou; fi
    fi
  fi
fi
if [ "$DRY" = 0 ]; then
  gad_estado_garante "$ROOT"
  jq -cn --arg sess "$SESS" --arg fase "$FASE" --arg nn "$NN" --arg pd "$PHASE_DIR" \
    --arg rl "$PHASE_DIR/$NN-RUN-LOG.jsonl" --arg ts "$(date -Is)" \
    --argjson ui "$UI" --argjson ai "$AI" --argjson ns "$NO_SHIP" --argjson va "$VAULT" --arg obs "$OBS" \
    --arg vp "$VAULT_PROFILE" \
    '{session_id:$sess, fase:$fase, nn:$nn, phase_dir:$pd, runlog:$rl, aberta_em:$ts,
      args:{ui:$ui, ai:$ai, no_ship:$ns, vault:$va, vault_profile:(if $vp == "" then null else $vp end), obs:$obs}}' \
    > "$(gad_rodada_ativa_novo "$ROOT")"
  gad_runlog "$PHASE_DIR" "$NN" run "0 abertura" \
    ${MODELO:+--modelo "$MODELO"} --camada 0 \
    --kv hook_instalado=$HOOK --kv etapa_1="$ETAPA1" --kv etapa_2="$ETAPA2" \
    --kv pre_spec="$([ -n "$PRE_SPEC" ] && echo detectado || echo ausente)" \
    --kv inventario="$INVENTARIO" --kv cc_version="$CCV"
  ABERTA=true
fi

# ── 10. limpeza da raiz da .planning (56(c)) ─────────────────────────────────
# Lista dos candidatos: órfãos `.gad-last-*` (convenção anterior ao 8828baa), o ponteiro
# legado e as cópias velhas em .planning/.gad/ (slug fora de GAD_ESTADO_SLUGS). Rastreado
# nunca é apagado nem desindexado: vai para `legado_rastreado`. --dry-run só lista o que
# está rastreado — não apaga nada.
LIMPEZA="[]"; LEGADO_RASTREADO="[]"
_cands=("$ROOT"/.planning/.gad-last-*.json "$(gad_rodada_ativa_legado "$ROOT")")
for _f in "$(gad_estado_dir "$ROOT")"/last-*.json; do
  _slug="$(basename -- "$_f" .json)"; _slug="${_slug#last-}"
  gad_eh_estado "$_slug" || _cands+=("$_f")
done
for _f in "${_cands[@]}"; do
  [ -e "$_f" ] || continue
  _rel="${_f#"$ROOT"/}"
  if gad_rastreado "$ROOT" "$_f"; then
    LEGADO_RASTREADO=$(jq -c --arg f "$_rel" '. + [$f]' <<<"$LEGADO_RASTREADO")
  elif [ "$DRY" = 0 ]; then
    rm -f -- "$_f" && LIMPEZA=$(jq -c --arg f "$_rel" '. + [$f]' <<<"$LIMPEZA")
  fi
done

SLUG=abre-rodada; [ "$DRY" = 1 ] && SLUG=abre-rodada-dry
gad_json_out "$SLUG" "$(jq -cn \
  --arg fase "$FASE" --arg nn "$NN" --arg pd "$PHASE_DIR" \
  --argjson ui "$UI" --argjson ai "$AI" --argjson ns "$NO_SHIP" --argjson va "$VAULT" --arg obs "$OBS" \
  --arg vp "$VAULT_PROFILE" \
  --argjson retrato "$RETRATO" --argjson ctx "$CONTEXTO" \
  --arg e1 "$ETAPA1" --arg e2 "$ETAPA2" \
  --argjson valerta "$VAULT_ALERTA" --arg vtermos "$VAULT_TERMOS" \
  --argjson tasks "$TASKS" --argjson aberta "$ABERTA" \
  --arg ps "$PRE_SPEC" --arg inv "$INVENTARIO" \
  --argjson posship "$POS_SHIP" --arg uats "$UAT_SUPERFICIE" --arg nal "$NAO_AUTONOMOS_LIST" \
  --argjson limp "$LIMPEZA" --argjson legr "$LEGADO_RASTREADO" \
  --arg fmt "$FORMATO" --arg fmc "$FORMATO_COMMIT" \
  '{args:{fase:$fase, ui:$ui, ai:$ai, no_ship:$ns, vault:$va, vault_profile:(if $vp == "" then null else $vp end), obs:$obs},
    retrato:$retrato, contexto:$ctx,
    pre_spec:(if $ps != "" then $ps else null end), inventario:$inv,
    etapa_1:$e1, etapa_2:$e2,
    nao_autonomos_pendentes:(if $nal == "" then [] else ($nal|split(",")) end),
    vault_alerta:(if $valerta then {alerta:true, termos:$vtermos,
      pergunta:"A fase parece ter login no navegador e a rodada veio sem --vault: sem credenciais, o UAT não verifica esses fluxos (balde 3). Informar um perfil de vault antes de começar?"} else false end),
    pos_ship_alerta:(if ($posship.pendentes|length) > 0 then {alerta:true, pendentes:$posship.pendentes,
      pergunta:"Há observação pós-ship de fase anterior marcada como bloqueante e ainda não observada. Abrir esta fase mesmo assim?"} else false end),
    uat_superficie:(if $uats == "" then null else $uats end),
    tasklist:$tasks,
    rodada:{aberta:$aberta, nn:$nn, phase_dir:$pd, formato_fase:$fmt, formato_commit:$fmc},
    limpeza:$limp, legado_rastreado:$legr}')"
