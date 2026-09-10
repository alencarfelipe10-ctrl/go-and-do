#!/usr/bin/env bash
# confere-precondicoes.sh — reprova PLAN.md que carrega a premissa obsoleta «este plano roda
# SEM worktree» / `isolation: none` num projeto que já resolve arquivos gitignored dentro do
# worktree (`.planning/worktree-fixtures.txt`, copiado pelo passo 0 do despacho — execute.md)
# ou que declara `workflow.use_worktrees: true`.
#
# Origem: F24.5 (09/09/2026). Os 9 planos nasceram com a premissa (7× `isolation: none`, 13×
# precondition "roda SEM worktree"), resolvida desde 27/07 (e031313a); atravessou planner,
# 2 plan-checkers, plan-gate e 4 pareceres externos. Fiscalizar por cancela, não por releitura.
#
# Uso: confere-precondicoes.sh <phase_dir> <project_root>
# Saída: JSON de 1 linha
#   {"fase_dir":…, "criterio":"fixtures|use_worktrees|nenhum", "planos":N,
#    "planos_reprovados":[{"plan":"24.5-01","motivos":["isolation: none","precondition nega worktree: «…»"]}],
#    "veredito":"ok|falha|nao_se_aplica", "codigos":["PRECONDICAO-WORKTREE-OBSOLETA"]}
# Exit: 0 ok/nao_se_aplica · 1 falha · 2 uso inválido.
# nao_se_aplica = o projeto não tem fixtures nem use_worktrees:true (então "sem worktree" pode
# ser verdade) — não é o script quem decide isso.
set -euo pipefail
shopt -s nullglob
PD="${1:-}"; ROOT="${2:-}"
[ -n "$PD" ] && [ -d "$PD" ] && [ -n "$ROOT" ] && [ -d "$ROOT" ] \
  || { echo "uso: confere-precondicoes.sh <phase_dir> <project_root>" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq ausente" >&2; exit 2; }

CRIT=nenhum
[ -s "$ROOT/.planning/worktree-fixtures.txt" ] && CRIT=fixtures
if [ "$CRIT" = nenhum ] && [ -f "$ROOT/.planning/config.json" ] \
   && [ "$(jq -r '.workflow.use_worktrees // false' "$ROOT/.planning/config.json" 2>/dev/null)" = true ]; then
  CRIT=use_worktrees
fi

# padrões (case-insensitive) de precondition que nega worktree — os que ocorreram na F24.5 mais
# as grafias óbvias; `roda EM worktree` (a forma corrigida) não casa
RX_PRE='sem worktree|without (a )?worktree|no worktree|fora d[oe] worktree|na (á|a)rvore principal|n(ã|a)o (roda|rodar|usa|usar) (em )?worktree'

REPROV='[]'; N=0
for f in "$PD"/*-PLAN.md; do
  N=$((N+1))
  plan=$(basename "$f" | sed 's/-PLAN\.md$//')
  motivos='[]'
  # frontmatter = entre a 1ª e a 2ª linha `---`
  if awk 'NR==1 && $0!="---"{exit 1} NR>1 && $0=="---"{exit 0} NR>1{print}' "$f" 2>/dev/null \
     | grep -qiE '^isolation:[[:space:]]*none[[:space:]]*$'; then
    motivos=$(jq -c '. + ["isolation: none"]' <<<"$motivos")
  fi
  # preconditions: uma tag por linha (o planner escreve inline); junta linhas para o caso multilinha
  while IFS= read -r pre; do
    [ -n "$pre" ] || continue
    if printf '%s' "$pre" | grep -qiE "$RX_PRE"; then
      trecho=$(printf '%s' "$pre" | sed 's/<[^>]*>//g' | tr -s ' ' | cut -c1-120)
      motivos=$(jq -c --arg t "$trecho" '. + ["precondition nega worktree: «" + $t + "»"]' <<<"$motivos")
    fi
  done < <(tr '\n' ' ' < "$f" | grep -oi '<precondition>[^<]*</precondition>')
  if [ "$(jq 'length' <<<"$motivos")" -gt 0 ]; then
    REPROV=$(jq -c --arg p "$plan" --argjson m "$motivos" '. + [{plan:$p, motivos:$m}]' <<<"$REPROV")
  fi
done

if [ "$CRIT" = nenhum ]; then
  VER=nao_se_aplica; COD='[]'
elif [ "$(jq 'length' <<<"$REPROV")" -gt 0 ]; then
  VER=falha; COD='["PRECONDICAO-WORKTREE-OBSOLETA"]'
else
  VER=ok; COD='[]'
fi
# quando não se aplica, ainda listamos o que achamos (informativo), mas exit 0
jq -cn --arg pd "$PD" --arg c "$CRIT" --argjson n "$N" --argjson r "$REPROV" --arg v "$VER" --argjson cod "$COD" \
  '{fase_dir:$pd, criterio:$c, planos:$n, planos_reprovados:$r, veredito:$v, codigos:$cod}'
[ "$VER" = falha ] && exit 1
exit 0
