#!/usr/bin/env bash
# reconcilia-docs.sh — reconcilia os espelhos de estado do projeto DEPOIS do ship (6.5).
#
# Motivo (v2.1.9 — tarefa 32e/34a, 3ª reincidência F24→F24.3): quando o projeto shipa pela
# rota B (clean-room, sem remote no repo de trabalho) o gsd-ship não roda e NADA atualiza
# STATE.md/ROADMAP.md; mesmo na rota A o gsd-ship só toca 2 campos do STATE.md e nunca o
# checkbox do ROADMAP nem os arquivos de review. Resultado: 3 fases seguidas terminaram com
# STATE.md `executing`, ROADMAP `[ ]`, REVIEW.md `issues_found` com re-review clean e
# REVIEWS.md sem frontmatter. Este script faz o que o dono fazia à mão (11/08, 27/08).
#
# Uso: reconcilia-docs.sh [--fase N] [--projeto DIR] [--pr "#42 https://…"] [--proxima N]
#                         [--dry-run]
#   Sem --fase/--projeto lê o ponteiro da rodada ativa. Idempotente: o que já está
#   reconciliado não é tocado. Nunca apaga conteúdo; só troca campos de estado.
#
# O que reconcilia (cada item vira uma entrada em `acoes` do JSON de saída):
#   1. STATE.md   — frontmatter: status executing→between_phases · stopped_at · last_updated ·
#                   last_activity(_desc) · progress (fases [x] do ROADMAP; planos = PLAN×SUMMARY
#                   em .planning/phases/); corpo "## Current Position" (Phase/Plan/Status).
#   2. ROADMAP.md — `- [ ] **Phase N:` → `- [x] … (completed YYYY-MM-DD[, PR #n])`.
#   3. NN-REVIEW.md — se existe NN-REVIEW.iter<k>.md mais recente com `status: clean`,
#                   REVIEW.md ganha `status: clean` + `re_review:` apontando para ele.
#   4. NN-REVIEWS.md — sem frontmatter e com NN-CONVERGENCE.md presente → ganha o
#                   frontmatter mínimo (phase/type/reviewers/cycles_run) lido de lá.
# A cancela `confere-etapa.sh 6` reprova se o STATE.md ainda disser `executing` para a
# fase — este script roda ANTES dela (workflow 6.5, ambas as rotas).
# Saída: JSON 1 linha + espelho .planning/.gad/last-reconcilia-docs.json.
# Exit: 0 = rodou (reconciliar é best-effort; o que falhou vem em `pendentes`)
#       2 = uso inválido
#       3 = FORMATO-INESPERADO (B2, 31/08): o `current_phase` bate com a fase, mas o campo
#           `status` não é um token reconhecível — é uma frase (tipicamente entre aspas,
#           como em alencarOS: `status: "Fase 13 … PAUSADA…"`). Nesse formato o grep
#           literal `^status: *executing` NUNCA bate: o script achava que não havia o que
#           fazer e a cancela achava que estava tudo certo. Os dois compartilhavam o mesmo
#           ponto cego, e por isso "roda, passa" com o STATE.md errado era garantido.
#           Agora o caso é declarado em voz alta, em vez de virar um `pend` silencioso.

set -uo pipefail
shopt -s nullglob
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

FASE=""; PROJ=""; PR=""; PROX=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fase)    FASE="${2:-}"; shift 2 ;;
    --projeto) PROJ="${2:-}"; shift 2 ;;
    --pr)      PR="${2:-}"; shift 2 ;;
    --proxima) PROX="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(gad_project_root "${PROJ:-$PWD}")"
PONTEIRO="$ROOT/.planning/.gad-rodada-ativa.json"
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

HOJE=$(date +%F); AGORA=$(date -u +%FT%T.000Z)
ACOES="[]"; PEND="[]"
acao() { ACOES=$(jq -c --arg a "$1" '. + [$a]' <<<"$ACOES"); }
pend() { PEND=$(jq -c --arg a "$1" '. + [$a]' <<<"$PEND"); }
# edita in-place só fora do --dry-run
ed() { [ "$DRY" = 1 ] || sed -i "$1" "$2"; }

STATE="$ROOT/.planning/STATE.md"; ROADMAP="$ROOT/.planning/ROADMAP.md"
PRTXT=""; [ -n "$PR" ] && PRTXT=", PR ${PR%% *}"

# ── 2. ROADMAP.md (antes do STATE: o progresso conta os [x]) ────────────────
if [ -f "$ROADMAP" ]; then
  if grep -qE "^- \[ \] \*\*Phase ${FASE}:" "$ROADMAP"; then
    ed "s/^- \[ \] \*\*Phase ${FASE}:\(.*\*\*\)/- [x] **Phase ${FASE}:\1 (completed ${HOJE}${PRTXT})/" "$ROADMAP"
    acao "ROADMAP.md: Phase $FASE marcada [x] (completed $HOJE)"
  elif grep -qE "^- \[x\] \*\*Phase ${FASE}:" "$ROADMAP"; then
    :
  else
    pend "ROADMAP.md: linha '- [ ] **Phase $FASE:' não encontrada (formato diferente?)"
  fi
else
  pend "ROADMAP.md ausente"
fi

# ── 1. STATE.md ──────────────────────────────────────────────────────────────
# Lê os dois campos como VALOR (e não por grep literal) para poder distinguir "o status é
# outro token" de "o status nem é um token". Trim de espaços e de \r à direita.
campo_state() { # <nome do campo> → valor cru, sem o prefixo e sem espaços nas bordas
  grep -m1 -E "^$1: " "$STATE" 2>/dev/null \
    | sed -e "s/^$1:[[:space:]]*//" -e 's/[[:space:]]*$//' -e 's/\r$//'
}
FORMATO_INESPERADO=0
if [ -f "$STATE" ]; then
  ST_VAL=$(campo_state status); CP_VAL=$(campo_state current_phase)
  # token = uma única palavra nua (sem aspas, sem espaço): `executing`, `between_phases`…
  ST_TOKEN=0; printf '%s' "$ST_VAL" | grep -qE '^[A-Za-z_][A-Za-z0-9_-]*$' && ST_TOKEN=1
  CP_OK=0; [ "$CP_VAL" = "$FASE" ] && CP_OK=1
  if [ "$ST_TOKEN" = 1 ] && [ "$ST_VAL" = executing ] && [ "$CP_OK" = 1 ]; then
    # progress: o STATE.md conta só o MILESTONE atual (o ROADMAP acumula todos), então
    # o incremento é relativo ao que já estava lá: +1 fase; +planos desta fase (teto =
    # total_plans). Heurística declarada — o GSD recalcula no próximo `state.update`.
    num() { grep -m1 -E "^  $1: *[0-9]+" "$STATE" | grep -oE '[0-9]+$' || echo 0; }
    tot=$(num total_phases); done_f=$(( $(num completed_phases) + 1 )); [ "$done_f" -gt "$tot" ] && done_f=$tot
    tp=$(num total_plans); np=0; for f in "$PHASE_DIR"/*-PLAN.md; do np=$((np+1)); done
    cp=$(( $(num completed_plans) + np )); [ "$cp" -gt "$tp" ] && cp=$tp
    pct=0; [ "$tot" -gt 0 ] && pct=$(( done_f * 100 / tot ))
    prox="${PROX:-}"; proxtxt=""; [ -n "$prox" ] && proxtxt=" — next: Phase $prox"
    ed "s/^status: *executing.*/status: between_phases/" "$STATE"
    ed "s|^stopped_at: .*|stopped_at: Phase $FASE shipped${PR:+ (PR ${PR%% *} merged $HOJE)}$proxtxt|" "$STATE"
    ed "s/^last_updated: .*/last_updated: \"$AGORA\"/" "$STATE"
    ed "s/^last_activity: .*/last_activity: $HOJE/" "$STATE"
    ed "s/^last_activity_desc: .*/last_activity_desc: Phase $FASE shipped${PR:+ (PR ${PR%% *} merged)}/" "$STATE"
    ed "s/^  completed_phases: .*/  completed_phases: $done_f/" "$STATE"
    ed "s/^  total_plans: .*/  total_plans: $tp/" "$STATE"
    ed "s/^  completed_plans: .*/  completed_plans: $cp/" "$STATE"
    ed "s/^  percent: .*/  percent: $pct/" "$STATE"
    # corpo: "## Current Position"
    ed "s/^\(Phase: .*\) — EXECUTING$/\1 — SHIPPED${PR:+ (PR ${PR%% *} merged $HOJE)}/" "$STATE"
    ed "s/^Plan: [0-9]* of $np$/Plan: $np of $np/" "$STATE"
    ed "s/^Status: Executing Phase .*/Status: Between phases$proxtxt/" "$STATE"
    ed "s/^Last Activity Description: .*/Last Activity Description: Phase $FASE shipped${PR:+ (PR ${PR%% *} merged)}/" "$STATE"
    acao "STATE.md: executing → between_phases (fases $done_f/$tot, planos $cp/$tp, $pct%)"

    # state_head: o outro sintoma da auditoria da F24.4 — o script simplesmente não
    # conhecia o campo. Só se ATUALIZA o que já existe; não se inventa campo em artefato
    # do GSD. O HEAD é o do repositório do PROJETO ($ROOT), nunca o da skill.
    if grep -qE '^state_head:' "$STATE"; then
      HEAD_ATUAL=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)
      if [ -n "$HEAD_ATUAL" ]; then
        ed "s/^state_head: .*/state_head: $HEAD_ATUAL/" "$STATE"
        acao "STATE.md: state_head → ${HEAD_ATUAL:0:12}"
      else
        pend "STATE.md: state_head presente, mas o HEAD de $ROOT é ilegível (repo sem commit?) — não atualizado"
      fi
    else
      pend "STATE.md: campo state_head ausente — NÃO criado (não se inventa campo do GSD)"
    fi

    # Coerência stopped_at × last_activity_desc: na F24.4 os dois ficaram de épocas
    # diferentes por terem sido tocados por chamadas distintas que bateram parcialmente na
    # condição. Aqui os dois são reescritos na MESMA passada (os `ed` acima), então a
    # incoerência só pode reaparecer se um deles não existir no arquivo — é isso que se
    # declara. Guarda estreita de propósito: não há checador semântico de coerência.
    tem_sa=0; grep -qE '^stopped_at:' "$STATE" && tem_sa=1
    tem_lad=0; grep -qE '^last_activity_desc:' "$STATE" && tem_lad=1
    if [ "$tem_sa" != "$tem_lad" ]; then
      pend "STATE.md: stopped_at e last_activity_desc não coexistem (stopped_at=$tem_sa, last_activity_desc=$tem_lad) — só o presente foi reescrito; a coerência entre os dois não pôde ser garantida na mesma passada"
    fi
  elif [ "$ST_TOKEN" = 1 ] && [ "$ST_VAL" = between_phases ]; then
    :
  elif [ "$ST_TOKEN" = 0 ] && [ "$CP_OK" = 1 ]; then
    # O caso que hoje passa em silêncio: a fase é a certa, mas o `status` é uma frase.
    echo "FORMATO-INESPERADO: status não é um token reconhecível ('$(printf '%s' "$ST_VAL" | cut -c1-90)')" >&2
    pend "FORMATO-INESPERADO: STATE.md da fase $FASE tem status em formato não reconhecível ('$(printf '%s' "$ST_VAL" | cut -c1-80)') — nem o reconciliador nem a cancela conseguem julgá-lo; conserte à mão"
    FORMATO_INESPERADO=1
  else
    pend "STATE.md: não casa com a fase $FASE — current_phase esperado '$FASE', encontrado '$CP_VAL'; status encontrado '$(printf '%s' "$ST_VAL" | cut -c1-60)' — não tocado"
  fi
else
  pend "STATE.md ausente"
fi

# ── 3. NN-REVIEW.md × re-review clean ────────────────────────────────────────
REVIEW="$PHASE_DIR/$NN-REVIEW.md"
if [ -f "$REVIEW" ] && grep -qE '^status: *issues_found' "$REVIEW"; then
  ult=$(ls -t "$PHASE_DIR/$NN-REVIEW.iter"*.md 2>/dev/null | head -1)
  if [ -n "$ult" ] && grep -qE '^status: *clean' "$ult"; then
    ts=$(grep -m1 -E '^reviewed:' "$ult" | sed 's/^reviewed:[[:space:]]*//')
    ed "s|^status: *issues_found.*|status: clean\nre_review: $(basename "$ult") (${ts:-sem ts} — clean)|" "$REVIEW"
    acao "$NN-REVIEW.md: status clean (re-review $(basename "$ult"))"
  fi
fi

# ── 4. NN-REVIEWS.md sem frontmatter ─────────────────────────────────────────
REVIEWS="$PHASE_DIR/$NN-REVIEWS.md"; CONV="$PHASE_DIR/$NN-CONVERGENCE.md"
if [ -f "$REVIEWS" ] && ! grep -qE '^---' "$REVIEWS"; then
  if [ -f "$CONV" ]; then
    cic=$(grep -m1 -E '^ciclos:' "$CONV" | sed 's/^ciclos:[[:space:]]*//' | tr -cd '0-9')
    rev=$(grep -m1 -E '^revisores_efetivos:' "$CONV" | sed 's/^revisores_efetivos:[[:space:]]*//')
    fm="---\nphase: $NN\ntype: plan-review-convergence\nreviewers: ${rev:-[codex, agy]}\ncycles_run: ${cic:-0}\n---\n\n# Revisão cruzada do plano — Fase $NN\n"
    if [ "$DRY" = 0 ]; then
      { printf '%b' "$fm"; cat "$REVIEWS"; } > "$REVIEWS.tmp" && mv "$REVIEWS.tmp" "$REVIEWS"
    fi
    acao "$NN-REVIEWS.md: frontmatter adicionado (cycles_run ${cic:-0})"
  else
    pend "$NN-REVIEWS.md sem frontmatter e sem $NN-CONVERGENCE.md para derivar"
  fi
fi

n_ac=$(jq 'length' <<<"$ACOES"); n_pe=$(jq 'length' <<<"$PEND")
[ "$DRY" = 1 ] || gad_autoregistro "reconcilia-docs.sh" 0 "fase $FASE: $n_ac ação(ões), $n_pe pendente(s)" || true
gad_json_out reconcilia-docs "$(jq -cn --arg f "$FASE" --argjson a "$ACOES" --argjson p "$PEND" --argjson d "$DRY" \
  --argjson fi "$FORMATO_INESPERADO" \
  '{fase:$f, acoes:$a, pendentes:$p, dry_run:($d==1), formato_inesperado:($fi==1)}')"
[ "$FORMATO_INESPERADO" = 0 ] || exit 3
exit 0
