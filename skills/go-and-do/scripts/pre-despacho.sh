#!/usr/bin/env bash
# pre-despacho.sh — cancela de SAÍDA de toda etapa que despacha subagente (decisão 2.C).
#
# Num bloco atômico: gate de contexto (Sub-rotina A absorvida — teto absoluto 400k,
# parar > compactar) + extras da etapa (lidos do manifest) + evento no run-log. A camada 0
# roda isto ANTES de despachar e obedece o campo `despacho` do JSON — não decide.
#
# Uso: pre-despacho.sh <etapa> [--fase N] [--projeto DIR] [--dry-run]
#   <etapa> casa com scripts/manifests/etapa-<etapa>.json (string opaca — "1.5" e "2.5"
#   nunca viram int, PC-9). Sem --fase/--projeto, lê o ponteiro da rodada ativa
#   (.planning/.gad-rodada-ativa.json, escrito pelo abre-rodada.sh).
#
# Campo `despacho` do JSON (política 100% em script, aprovada 08/08):
#   ok                   — despache com prompts/<etapa>.md.
#   stop                 — contexto >= teto: o evento `stop` já foi gravado, a linha de
#                          handoff está no campo `handoff`; repasse-a ao dono e PARE.
#                          (fail-closed por LÓGICA; exit 3)
#   bloqueio_sem_revisor — só etapa 2.5: NENHUM revisor externo instalado. A fase NÃO
#                          continua sem revisão adversarial (decisão do Felipe 09/08,
#                          PC-6) — pergunte ao dono como proceder. (exit 4)
#   Contexto `unknown` — falha ABERTA declarada: `despacho: ok` com `contexto.reason`
#   preenchido; anuncie "gate não mediu, confiando na retomabilidade" e siga (freio que
#   falha fechado por defeito de MEDIÇÃO pararia rodadas saudáveis).
#
# Campos informativos: `janela_silencio` (23h–07h local — hard gate vira pausa graciosa,
# S.I) · `revisores` (2.5: presença individual; UM ausente = segue com o outro, disclosed)
# · `git_remote` (6: gatilho da rota B de ship, 6.E — julgamento fica na camada 0).
#
# Escritor único (T.2): este script grava o CHECKPOINT da etapa (fotografia do contexto +
# abertura da janela; kv despacho=autorizado). O ciclo de vida fino de cada Agent() é do
# hook gad-lifecycle.sh (eventos despacho/retorno) — nunca daqui.
# Saída: JSON 1 linha + espelho .planning/.gad-last-pre-despacho.json (PC-5). Exit 0=ok.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

ETAPA="${1:-}"; shift || true
[ -n "$ETAPA" ] || { echo "uso: pre-despacho.sh <etapa> [--fase N] [--projeto DIR] [--dry-run]" >&2; exit 2; }
FASE=""; PROJ=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fase)    FASE="${2:-}"; shift 2 ;;
    --projeto) PROJ="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

MANIFEST="$GAD_SCRIPTS_DIR/manifests/etapa-$ETAPA.json"
[ -f "$MANIFEST" ] || { echo "ERRO: manifest inexistente para etapa \"$ETAPA\" ($MANIFEST)" >&2; exit 2; }
RUNLOG_ETAPA=$(jq -r '.runlog_etapa' "$MANIFEST")

ROOT="$(gad_project_root "${PROJ:-$PWD}")"
PONTEIRO="$ROOT/.planning/.gad-rodada-ativa.json"

# fase/NN/fase_dir: ponteiro da rodada > flags > descoberta no disco
NN=""; PHASE_DIR=""
if [ -z "$FASE" ] && [ -f "$PONTEIRO" ]; then
  FASE=$(jq -r '.fase // empty' "$PONTEIRO")
  NN=$(jq -r '.nn // empty' "$PONTEIRO")
  PHASE_DIR=$(jq -r '.phase_dir // empty' "$PONTEIRO")
fi
[ -n "$FASE" ] || { echo "ERRO: fase desconhecida — sem ponteiro de rodada e sem --fase" >&2; exit 2; }
[ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ] || PHASE_DIR=$(gad_phase_dir "$ROOT" "$FASE") \
  || { echo "ERRO: fase $FASE não encontrada em $ROOT/.planning/phases/" >&2; exit 2; }
[ -n "$NN" ] || NN=$(basename "$PHASE_DIR" | grep -o '[0-9][0-9.]*' | head -1)

# ── gate de contexto (Sub-rotina A absorvida) ────────────────────────────────
linha=$("$GAD_SCRIPTS_DIR/context-check.sh" 2>/dev/null || echo "tokens=0 limit=0 pct=0 status=unknown reason=context-check-falhou")
tokens=$(printf '%s' "$linha" | sed -n 's/.*tokens=\([0-9]*\).*/\1/p')
limite=$(printf '%s' "$linha" | sed -n 's/.*limit=\([0-9]*\).*/\1/p')
pct=$(printf '%s' "$linha"    | sed -n 's/.*pct=\([0-9]*\).*/\1/p')
status=$(printf '%s' "$linha" | sed -n 's/.*status=\([a-z]*\).*/\1/p')
reason=$(printf '%s' "$linha" | sed -n 's/.*reason=\(.*\)$/\1/p')

# ── janela de silêncio (S.I): 23h–07h local ──────────────────────────────────
hora=$(date +%H)
silencio=false
case "$hora" in 23|00|01|02|03|04|05|06) silencio=true ;; esac

# ── extras da etapa (declarados no manifest, executados aqui) ────────────────
extras="{}"
# retomada por marcador (2.5-C: grep de frontmatter — artefato presente = etapa já feita)
RET_ARQ=$(jq -r '.pre.retomada.arquivo // empty' "$MANIFEST")
if [ -n "$RET_ARQ" ]; then
  RET_ARQ=$(printf '%s' "$RET_ARQ" | sed "s|{fase}|$PHASE_DIR|; s|{nn}|$NN|")
  RET_RE=$(jq -r '.pre.retomada.regex' "$MANIFEST")
  if [ -f "$RET_ARQ" ] && grep -qE "$RET_RE" "$RET_ARQ"; then
    gad_json_out pre-despacho "$(jq -cn --arg e "$ETAPA" \
      '{etapa:$e, despacho:"pular", motivo:"marcador de retomada presente — etapa já concluída em rodada anterior"}')"
    exit 0
  fi
fi
# gate de config (2.5-C: config off → skip declarado na origem, evento no run-log)
CFG_KEY=$(jq -r '.pre.config_gate // empty' "$MANIFEST")
if [ -n "$CFG_KEY" ]; then
  CFG_VAL=$(cd "$ROOT" && gsd_run query config-get "$CFG_KEY" 2>/dev/null | tr -d ' \n\r' || true)
  if [ "$CFG_VAL" = "false" ]; then
    [ "$DRY" = 1 ] || gad_runlog "$PHASE_DIR" "$NN" skip "$RUNLOG_ETAPA (config $CFG_KEY off)"
    gad_json_out pre-despacho "$(jq -cn --arg e "$ETAPA" --arg k "$CFG_KEY" \
      '{etapa:$e, despacho:"skip_config", motivo:("config " + $k + " = false — degradação declarada, siga sem despachar")}')"
    exit 0
  fi
fi
if [ "$(jq -r '.pre.revisores // false' "$MANIFEST")" = "true" ]; then
  cx=false; ag=false
  command -v codex >/dev/null 2>&1 && cx=true
  command -v agy   >/dev/null 2>&1 && ag=true
  extras=$(jq -cn --argjson cx "$cx" --argjson ag "$ag" \
    --argjson prev "$extras" '$prev + {revisores: {codex: $cx, agy: $ag}}')
  if [ "$cx" = false ] && [ "$ag" = false ]; then
    # PC-6: sem NENHUM revisor externo a fase não continua — fail-closed com pergunta
    resumo="bloqueio_sem_revisor: nenhum revisor externo instalado (codex, agy)"
    [ "$DRY" = 1 ] || gad_runlog "$PHASE_DIR" "$NN" script "$RUNLOG_ETAPA" \
      --kv script=pre-despacho.sh --kv exit=4 --kv resumo="$resumo"
    gad_json_out pre-despacho "$(jq -cn --arg e "$ETAPA" --argjson x "$extras" \
      '{etapa:$e, despacho:"bloqueio_sem_revisor",
        pergunta_ao_dono:"A revisão adversarial exige >=1 revisor externo (codex ou agy) e nenhum está instalado. Instalar um deles e continuar, ou abortar a fase?"} + $x')"
    exit 4
  fi
fi
if [ "$(jq -r '.pre.git_remote // false' "$MANIFEST")" = "true" ]; then
  gr=false
  [ -n "$(git -C "$ROOT" remote 2>/dev/null)" ] && gr=true
  extras=$(jq -cn --argjson gr "$gr" --argjson prev "$extras" '$prev + {git_remote: $gr}')
fi

# ── política de limite (2.C) ─────────────────────────────────────────────────
if [ "$status" = "stop" ]; then
  handoff="Contexto em $((tokens/1000))k (teto $((limite/1000))k) — pausa graciosa. Retome numa sessão nova com: /go-and-do $FASE"
  if [ "$DRY" = 0 ]; then
    gad_runlog "$PHASE_DIR" "$NN" stop "$RUNLOG_ETAPA" \
      "$tokens" "$pct" "" "$limite" "" "contexto em $((tokens/1000))k"
    rm -f "$PONTEIRO"   # PC-3: rodada parada não arma mais o hook
  fi
  gad_json_out pre-despacho "$(jq -cn --arg e "$ETAPA" --arg h "$handoff" \
    --argjson t "${tokens:-0}" --argjson p "${pct:-0}" --argjson l "${limite:-0}" --argjson x "$extras" \
    '{etapa:$e, despacho:"stop", contexto:{tokens:$t,pct:$p,limit:$l,status:"stop"}, handoff:$h} + $x')"
  exit 3
fi

# ok (ou unknown declarado): abre a janela da etapa e autoriza o despacho
[ "$DRY" = 1 ] || gad_runlog "$PHASE_DIR" "$NN" checkpoint "$RUNLOG_ETAPA" \
  "$tokens" "$pct" "" "$limite" --kv despacho=autorizado
gad_json_out pre-despacho "$(jq -cn --arg e "$ETAPA" --arg st "${status:-unknown}" --arg rz "$reason" \
  --arg pr "prompts" --argjson t "${tokens:-0}" --argjson p "${pct:-0}" --argjson l "${limite:-0}" \
  --argjson sil "$silencio" --argjson x "$extras" \
  '{etapa:$e, despacho:"ok",
    contexto:({tokens:$t,pct:$p,limit:$l,status:$st} + (if $rz != "" then {reason:$rz} else {} end)),
    janela_silencio:$sil} + $x')"
