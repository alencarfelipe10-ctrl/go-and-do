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
#
# Tag reconhecida no assunto do commit: `tipo(24.4-08): …` ou `tipo(24.4-08-slug): …`
# (formato do executor, `{type}({phase}-{plan}): …`). `docs(24.4): …` sem plano é do
# orquestrador e não conta; `tipo(08): …` sem a fase também não — no inspired essa forma
# nua puxava commits de fases antigas (`feat(06): …`) e inventava FORA-DA-LISTA. O git
# roda na raiz principal: commits feitos na cópia (worktree) chegam por merge e o filtro
# por mensagem os encontra.
#
# Uso: confere-plano.sh <phase_dir> <plan_id>       (ex.: … 24.4-08)
# Saída: JSON de uma linha {plan, tasks, commits, commits_tarefa, fora_da_lista, veredito,
#        codigos} + espelho .planning/.gad/last-confere-plano-<plan>.json
# Exit: 0 ok · 1 falha (qualquer código) · 2 uso inválido. Quem decide o que reprova a
# etapa é o confere-etapa.sh 3, que lê `codigos`.

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
  --arg v "$VER" \
  '{plan:$plan, tasks:$t, commits:$c, commits_tarefa:$ct, fora_da_lista:$fora, veredito:$v, codigos:$cod}')
(cd "$ROOT" && gad_json_out "confere-plano-$PLAN" "$JSON")
[ "$VER" = ok ]
