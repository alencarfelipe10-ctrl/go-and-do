#!/usr/bin/env bash
# confere-arquivos-novos.sh — lista os arquivos que os PLAN.md declaram tocar e que AINDA
# NÃO existem no repositório. Insumo mecânico do julgamento 2.E (pattern-mapper) do
# prompts/plan.md e da cancela `mapper_pulado` da camada 0 (workflow.md 2.4).
#
# Origem: F24.5 (09/09/2026), reincidente da F24.3. O host pulou o mapper com a frase que o
# próprio prompt chama de armadilha («fase só modifica arquivos»), e os planos criavam
# scripts/capturar_baseline_245.py e scripts/medir_caminho_boletagem_245.py. A cancela do
# fiscal entregou `mapper_pulado` à camada 0, que não fez nada com o campo.
#
# Uso: confere-arquivos-novos.sh <phase_dir> <project_root> [--ref <commit>]
#   --ref  commit contra o qual a existência é medida (default: HEAD). Numa fase já
#          executada, HEAD já tem os arquivos — use o commit anterior à execução para
#          reproduzir o julgamento.
# Saída: JSON de 1 linha
#   {"fase_dir":…, "ref":"HEAD", "planos":N, "declarados":M,
#    "novos_producao":[…], "novos_teste":[…], "novos_planning":[…],
#    "veredito":"mapper_obrigatorio|mapper_opcional", "codigos":["ARQUIVO-NOVO-DE-PRODUCAO"]}
# Exit: 0 sempre (é insumo de julgamento, não cancela) · 2 uso inválido.
#
# Régua: `novos_producao` = declarado, ausente no ref, FORA de `.planning/` e fora dos
# caminhos de teste (`tests/`, `test/`, `spec/`, basename `test_*`/`*_test.*`/`*.test.*`).
# `.planning/` nunca conta: artefato de planejamento não tem padrão de código a seguir.
# Testes saem em balde próprio e NÃO obrigam o mapper (decisão do dono, 11/09/2026:
# «só arquivo de produção; teste novo vira sino»): hoje eles viram sino, não cancela.
set -euo pipefail
shopt -s nullglob
PD="${1:-}"; ROOT="${2:-}"; shift 2 2>/dev/null || true
REF="HEAD"
while [ $# -gt 0 ]; do case "$1" in --ref) REF="${2:-HEAD}"; shift 2 ;; *) shift ;; esac; done
[ -n "$PD" ] && [ -d "$PD" ] && [ -n "$ROOT" ] && [ -d "$ROOT" ] \
  || { echo "uso: confere-arquivos-novos.sh <phase_dir> <project_root> [--ref <commit>]" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq ausente" >&2; exit 2; }

# declarados: itens do bloco `files_modified:` do frontmatter de cada PLAN.md
declarados() {
  awk '
    /^files_modified:[[:space:]]*$/ { dentro=1; next }
    dentro && /^[[:space:]]*-[[:space:]]+/ { sub(/^[[:space:]]*-[[:space:]]+/,""); gsub(/^["'\'']|["'\'']$/,""); print; next }
    dentro && /^[^[:space:]-]/ { dentro=0 }
  ' "$1"
}

N=0; TODOS=()
for f in "$PD"/*-PLAN.md; do
  N=$((N+1))
  while IFS= read -r p; do [ -n "$p" ] && TODOS+=("$p"); done < <(declarados "$f")
done
M=${#TODOS[@]}

PROD='[]'; TST='[]'; PLN='[]'
if [ "$M" -gt 0 ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    git -C "$ROOT" cat-file -e "$REF:$p" 2>/dev/null && continue   # já existe no ref
    case "$p" in
      .planning/*)               PLN=$(jq -c --arg p "$p" '. + [$p]' <<<"$PLN") ;;
      tests/*|test/*|spec/*)     TST=$(jq -c --arg p "$p" '. + [$p]' <<<"$TST") ;;
      *)
        b="$(basename -- "$p")"
        case "$b" in
          test_*|*_test.*|*.test.*) TST=$(jq -c --arg p "$p" '. + [$p]' <<<"$TST") ;;
          *)                        PROD=$(jq -c --arg p "$p" '. + [$p]' <<<"$PROD") ;;
        esac ;;
    esac
  done < <(printf '%s\n' "${TODOS[@]}" | sort -u)
fi

if [ "$(jq 'length' <<<"$PROD")" -gt 0 ]; then
  VER=mapper_obrigatorio; COD='["ARQUIVO-NOVO-DE-PRODUCAO"]'
else
  VER=mapper_opcional; COD='[]'
fi
jq -cn --arg pd "$PD" --arg r "$REF" --argjson n "$N" --argjson m "$M" \
       --argjson pr "$PROD" --argjson t "$TST" --argjson pl "$PLN" \
       --arg v "$VER" --argjson cod "$COD" \
  '{fase_dir:$pd, ref:$r, planos:$n, declarados:$m, novos_producao:$pr,
    novos_teste:$t, novos_planning:$pl, veredito:$v, codigos:$cod}'
exit 0
