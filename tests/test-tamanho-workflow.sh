#!/usr/bin/env bash
# test-tamanho-workflow.sh — guarda contra regressão da tarefa 9(e) do mapa-gad (24/09/2026).
#
# O SKILL.md anexa o workflow.md por `@~/…`. Acima de um teto em tokens (bancada de 23/09 com
# Opus 5.5: 60 KB anexou, 66 KB não; hipótese forte = o mesmo limite de 25 mil tokens do Read,
# ≈ 2,43 B/token) o Claude Code DESCARTA o anexo EM SILÊNCIO, e o modelo passa a reler o
# arquivo em pedaços. Por isso o workflow foi dividido em núcleo anexado + um arquivo por etapa.
#
# Tetos (ALARME, NÃO MURO — nunca corte regra operativa para caber: mova o trecho para o
# arquivo de etapa, ou suba o teto justificando no commit):
#   · núcleo workflow.md            ≤ 53.000 bytes (≈ 22 mil tokens)
#   · cada workflow-etapa-*.md      ≤ 55.000 bytes (≈ 22 mil tokens; margem sobre os 25 mil
#                                     do Read, que é como a camada 0 lê as etapas)
# Integridade: cada <stage id> de `0 1 1.5 2 2.5 3 4 5 6` existe em exatamente UM arquivo
# (nada perdido, nada duplicado), e o arquivo de cada etapa ≠ 0 é workflow-etapa-<id>.md.
#   bash tests/test-tamanho-workflow.sh      · exit 0 = verde
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
D="$AQUI/../skills/go-and-do"
TETO_NUCLEO=53000
TETO_ETAPA=55000
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; falhas=$((falhas+1)); }
ALARME="alarme, não muro: mova o trecho para um arquivo de etapa"

echo "== tetos de tamanho"
n=$(wc -c < "$D/workflow.md")
if [ "$n" -le "$TETO_NUCLEO" ]; then ok "núcleo workflow.md: $n ≤ $TETO_NUCLEO bytes"
else erro "núcleo workflow.md: $n > $TETO_NUCLEO bytes — $ALARME (o anexo @ é descartado em silêncio acima do teto)"; fi
qtd=0
for f in "$D"/workflow-etapa-*.md; do
  [ -f "$f" ] || continue
  qtd=$((qtd+1))
  n=$(wc -c < "$f")
  if [ "$n" -le "$TETO_ETAPA" ]; then ok "$(basename "$f"): $n ≤ $TETO_ETAPA bytes"
  else erro "$(basename "$f"): $n > $TETO_ETAPA bytes — $ALARME (ou divida a etapa)"; fi
done
[ "$qtd" -gt 0 ] || erro "nenhum workflow-etapa-*.md encontrado"

echo "== cada <stage id> em exatamente um arquivo"
for id in 0 1 1.5 2 2.5 3 4 5 6; do
  achados=$(grep -lF "<stage id=\"$id\"" "$D/workflow.md" "$D"/workflow-etapa-*.md 2>/dev/null)
  c=$(printf '%s' "$achados" | grep -c .)
  esperado="$D/workflow-etapa-$id.md"; [ "$id" = 0 ] && esperado="$D/workflow.md"
  if [ "$c" = 1 ] && [ "$achados" = "$esperado" ]; then ok "stage $id → $(basename "$achados")"
  elif [ "$c" = 0 ]; then erro "stage $id PERDIDO (em nenhum arquivo)"
  else erro "stage $id em $c arquivo(s): $(printf '%s' "$achados" | xargs -n1 basename | tr '\n' ' ')(esperado: $(basename "$esperado"))"; fi
done
extra=$(grep -ho '<stage id="[^"]*"' "$D/workflow.md" "$D"/workflow-etapa-*.md \
  | sed 's/<stage id="//;s/"$//' | grep -vxE '0|1|1\.5|2|2\.5|3|4|5|6' || true)
[ -z "$extra" ] && ok "nenhum <stage id> fora da lista" || erro "stage(s) fora da lista: $extra"

echo "== o núcleo manda ler cada arquivo de etapa"
for id in 1 1.5 2 2.5 3 4 5 6; do
  grep -qF "\`workflow-etapa-$id.md\`" "$D/workflow.md" && ok "pipeline_index cita workflow-etapa-$id.md" \
    || erro "pipeline_index não cita workflow-etapa-$id.md"
done

echo
[ "$falhas" -eq 0 ] && echo "test-tamanho-workflow: tudo ok" || echo "test-tamanho-workflow: $falhas falha(s)"
[ "$falhas" -eq 0 ]
