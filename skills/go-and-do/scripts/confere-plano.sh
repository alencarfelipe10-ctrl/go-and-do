#!/usr/bin/env bash
# confere-plano.sh — o plano executado ficou dentro do que declarou? (P06, consertos F24.4)
#
# O executor do GSD é upstream (46 KB) e não lê `files_modified`; regra em prosa não
# segura. Na F24.4 o plano 02 juntou três tarefas num commit, o 06 juntou três e misturou
# teste com implementação, o 08 alterou dois arquivos fora da lista — e nada reclamou.
# Este script confere pelo git, no fecho da etapa 3, duas coisas:
#
#   1. Todo arquivo tocado pelos commits do plano está em `files_modified` ∪ `files_deleted`
#      do PLAN.md (artefatos de planejamento não contam: `.planning/**`, `*-SUMMARY.md`,
#      STATE.md, ROADMAP.md, REQUIREMENTS.md). Sobra → FORA-DA-LISTA. Arquivo fora da lista
#      é colisão invisível para o cálculo de ondas — por isso reprova a etapa.
#   2. Há pelo menos um commit por tarefa (`<task>` fora `checkpoint:*`). Contam os commits
#      de TAREFA: os que trazem a tag do plano no escopo convencional e vêm ANTES do commit
#      de metadados do executor (`docs(<plano>): complete … plan`, gsd-executor.md:790) —
#      correções pós-gate e docs vêm depois e não são tarefa. Menos → COMMITS-A-MENOS;
#      nenhum commit com a tag → SEM-COMMIT. `files_modified` vazio → LISTA-VAZIA.
#      Os quatro códigos reprovam a etapa 3 (A1, 04/09/2026): commit único para três
#      tarefas esconde qual tarefa quebrou e impede reverter só ela.
#
# Tag reconhecida no assunto do commit: `tipo(24.4-08): …` ou `tipo(24.4-08-slug): …`
# (formato do executor, `{type}({phase}-{plan}): …`). `docs(24.4): …` sem plano é do
# orquestrador e não conta; `tipo(08): …` sem a fase também não — no inspired essa forma
# nua puxava commits de fases antigas (`feat(06): …`) e inventava FORA-DA-LISTA. O git
# roda na raiz principal: commits feitos na cópia (worktree) chegam por merge e o filtro
# por mensagem os encontra.
#
#   3. (informativo — C7, plano 2, 05/09/2026) Toda D-NN que o PLAN.md cita aparece no
#      SUMMARY.md? Na F24.4 os PLANs citavam 23 decisões e os SUMMARYs 8 — 4 de 8 SUMMARYs
#      não citavam nenhuma — e o `check.decision-coverage-verify` seguia verde porque o seu
#      haystack inclui os PLANs. D-NN marcadas `informational` no CONTEXT (as decisões-ponteiro
#      da PRE-SPEC) não exigem tarefa, logo não exigem linha: saem da conta. Sobra →
#      `DECISAO-SEM-SUMMARY` em `informativos` (NUNCA em `codigos`: não muda `veredito` nem o
#      exit — promoção a falha só depois de uma fase real medida por M12). Sem SUMMARY ou sem
#      CONTEXT → `n/a`.
#
# Uso: confere-plano.sh <phase_dir> <plan_id>       (ex.: … 24.4-08)
# Saída: JSON de uma linha {plan, tasks, commits, commits_tarefa, fora_da_lista, veredito,
#        codigos, informativos, decisoes:{plan, summary, faltantes, informational}} + espelho
#        .planning/.gad/last-confere-plano-<plan>.json
# Exit: 0 ok · 1 falha (qualquer código) · 2 uso inválido. Quem aplica a reprovação à
# etapa é o confere-etapa.sh 3, que lê `codigos` (hoje todos reprovam); `informativos` só reporta.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PHASE_DIR="${1:-}"; PLAN="${2:-}"
[ -n "$PHASE_DIR" ] && [ -n "$PLAN" ] || { echo "uso: confere-plano.sh <phase_dir> <plan_id>" >&2; exit 2; }
[ -d "$PHASE_DIR" ] || { echo "ERRO: phase_dir inexistente: $PHASE_DIR" >&2; exit 2; }
PHASE_DIR="$(cd "$PHASE_DIR" && pwd -P)"
PLAN_F="$PHASE_DIR/$PLAN-PLAN.md"
[ -f "$PLAN_F" ] || { echo "ERRO: PLAN.md inexistente: $PLAN_F" >&2; exit 2; }
ROOT="$(gad_project_root "$PHASE_DIR")"
git -C "$ROOT" rev-parse --show-toplevel >/dev/null 2>&1 || { echo "ERRO: $ROOT não é repositório git" >&2; exit 2; }

# ── frontmatter: files_modified / files_deleted (listas YAML de um nível) ─────
# Só o primeiro bloco `--- … ---`; as chaves são listas `- caminho` ou `[a, b]` inline.
lista_fm() { # <arquivo> <chave> → um caminho por linha
  awk -v k="$2" '
    NR==1 && $0=="---" { fm=1; next }
    fm && $0=="---" { exit }
    !fm { next }
    $0 ~ "^" k ":" {
      s=$0; sub("^" k ":[ \t]*", "", s)
      if (s ~ /^\[/) { gsub(/^\[|\]$/, "", s); n=split(s, a, ","); for (i=1;i<=n;i++){ gsub(/^[ \t"'\'']+|[ \t"'\'']+$/, "", a[i]); if (a[i]!="") print a[i] } ; exit }
      dentro=1; next
    }
    dentro && /^[ \t]+-[ \t]*/ { s=$0; sub(/^[ \t]+-[ \t]*/, "", s); gsub(/^["'\'']|["'\'']$/, "", s); sub(/[ \t]+#.*$/, "", s); if (s!="") print s; next }
    dentro { exit }
  ' "$1"
}
mapfile -t PERMITIDOS < <({ lista_fm "$PLAN_F" files_modified; lista_fm "$PLAN_F" files_deleted; } | sed 's#^\./##')

# tarefas: `<task …>` que não sejam checkpoint
N_TASKS=$({ grep -oE '<task([ >][^>]*)?>' "$PLAN_F" || true; } | { grep -vcE 'type="checkpoint' || true; })

# ── commits do plano ──────────────────────────────────────────────────────────
esc() { printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g'; }
TAG_RE="^[a-z]+\($(esc "$PLAN")(-[^)]*)?\)(!)?:"
mapfile -t COMMITS < <(git -C "$ROOT" log --format='%H%x09%s' --reverse -E --grep="$TAG_RE" 2>/dev/null || true)
N_COMMITS=${#COMMITS[@]}

# commits de tarefa: até o commit de metadados do executor (exclusive); docs nunca é tarefa
N_TAREFA=0
for c in ${COMMITS[@]+"${COMMITS[@]}"}; do
  s="${c#*	}"
  if printf '%s' "$s" | grep -qE '^docs\(.*\): *complete .* plan$'; then break; fi
  printf '%s' "$s" | grep -qE '^docs\(' && continue
  N_TAREFA=$((N_TAREFA+1))
done

# ── arquivos tocados − artefatos permitidos − lista do plano ──────────────────
tocados() {
  local c
  for c in ${COMMITS[@]+"${COMMITS[@]}"}; do
    git -C "$ROOT" show --name-only --format= "${c%%	*}" 2>/dev/null
  done | sed '/^$/d' | sort -u
}
FORA=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    .planning/*|*-SUMMARY.md|STATE.md|*/STATE.md|ROADMAP.md|*/ROADMAP.md|REQUIREMENTS.md|*/REQUIREMENTS.md) continue ;;
  esac
  dentro=0
  for p in ${PERMITIDOS[@]+"${PERMITIDOS[@]}"}; do
    # literal ou glob do próprio frontmatter (`src/x/**` vale como prefixo)
    if [ "$f" = "$p" ] || [[ "$f" == $p ]] || { [[ "$p" == *'**' ]] && [[ "$f" == "${p%\*\*}"* ]]; }; then dentro=1; break; fi
  done
  [ "$dentro" = 1 ] || FORA+=("$f")
done < <(tocados)

# ── PLAN ⊆ SUMMARY nas D-NN citadas (informativo) ─────────────────────────────
SUM_F="$PHASE_DIR/$PLAN-SUMMARY.md"; CTX_F=$(ls "$PHASE_DIR"/*-CONTEXT.md 2>/dev/null | head -1 || true)
D_PLAN="[]"; D_SUM="[]"; D_FALT="[]"; D_INFO="[]"; D_ESTADO="n/a"; INFORMATIVOS=()
dnn() { { grep -oE '\bD-[0-9]+\b' "$1" || true; } | sort -u; }
if [ -f "$SUM_F" ] && [ -n "$CTX_F" ] && [ -f "$CTX_F" ]; then
  D_ESTADO="ok"
  # informational: tag no bullet `- **D-NN [..., informational]:**` do CONTEXT
  INFO_IDS=$({ sed -n '/^<decisions>/,/^<\/decisions>/p' "$CTX_F" | grep -E '^\s*-\s+\*\*D-[0-9]+\s*\[[^]]*informational[^]]*\]' | grep -oE '\bD-[0-9]+\b' || true; } | sort -u)
  PL_IDS=$(dnn "$PLAN_F"); SM_IDS=$(dnn "$SUM_F")
  FALT=$(comm -23 <(printf '%s\n' "$PL_IDS" | sed '/^$/d') <(printf '%s\n' "$SM_IDS" | sed '/^$/d') | comm -23 - <(printf '%s\n' "$INFO_IDS" | sed '/^$/d'))
  tojson() { printf '%s\n' "$1" | sed '/^$/d' | jq -R . | jq -cs .; }
  D_PLAN=$(tojson "$PL_IDS"); D_SUM=$(tojson "$SM_IDS"); D_FALT=$(tojson "$FALT"); D_INFO=$(tojson "$INFO_IDS")
  if [ -n "$FALT" ]; then
    INFORMATIVOS+=("DECISAO-SEM-SUMMARY ($(printf '%s\n' "$FALT" | sed '/^$/d' | tr '\n' ' ' | sed 's/ $//'))")
  fi
fi

# ── veredito ──────────────────────────────────────────────────────────────────
CODIGOS=()
[ ${#PERMITIDOS[@]} -gt 0 ] || CODIGOS+=("LISTA-VAZIA")
[ ${#FORA[@]} -eq 0 ] || CODIGOS+=("FORA-DA-LISTA")
if [ "$N_COMMITS" -eq 0 ]; then CODIGOS+=("SEM-COMMIT")
elif [ "$N_TAREFA" -lt "$N_TASKS" ]; then CODIGOS+=("COMMITS-A-MENOS ($N_TAREFA commits para $N_TASKS tarefas)")
fi
VER=ok; [ ${#CODIGOS[@]} -eq 0 ] || VER=falha

JSON=$(jq -cn --arg plan "$PLAN" --argjson t "$N_TASKS" --argjson c "$N_COMMITS" --argjson ct "$N_TAREFA" \
  --argjson fora "$(printf '%s\n' ${FORA[@]+"${FORA[@]}"} | sed '/^$/d' | jq -R . | jq -cs .)" \
  --argjson cod "$(printf '%s\n' ${CODIGOS[@]+"${CODIGOS[@]}"} | sed '/^$/d' | jq -R . | jq -cs .)" \
  --argjson inf "$(printf '%s\n' ${INFORMATIVOS[@]+"${INFORMATIVOS[@]}"} | sed '/^$/d' | jq -R . | jq -cs .)" \
  --arg v "$VER" --arg de "$D_ESTADO" --argjson dp "$D_PLAN" --argjson ds "$D_SUM" --argjson df "$D_FALT" --argjson di "$D_INFO" \
  '{plan:$plan, tasks:$t, commits:$c, commits_tarefa:$ct, fora_da_lista:$fora, veredito:$v, codigos:$cod,
    informativos:$inf, decisoes:{estado:$de, plan:$dp, summary:$ds, faltantes:$df, informational:$di}}')
(cd "$ROOT" && gad_json_out "confere-plano-$PLAN" "$JSON")
[ "$VER" = ok ]
