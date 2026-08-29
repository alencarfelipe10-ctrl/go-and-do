#!/usr/bin/env bash
# test-molde.sh — o esqueleto do `--so-molde`.
#
# O que se prova:
#   1. as 11 seções do §3 do plano estão lá, na ordem, com "— nada —"
#   2. as marcas do bloco existem e o bloco nasce vazio (`[]`)
#   3. COMPORTAMENTO REAL, contra o plano: `confere-pre-spec.sh --so-bloco` APROVA o
#      esqueleto (exit 0, `entradas=0`). Não existe código BLOCO-VAZIO no script — `[]`
#      é um array bem-formado e o laço de entradas roda zero vez. Quem cobra decisão é o
#      passo 6 da skill (revisão + ok do dono), não o script. Este teste trava o
#      comportamento observado para que uma mudança futura no confere apareça aqui.
#   4. o esqueleto passa limpo no confere-pii.sh (o cabeçalho cita "Claude", que é termo
#      permitido — se alguém tirar a lista de permitidos, este teste cai)
set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib-bancada.sh"

RAIZ=$(bancada molde)
ALVO="$RAIZ/99-PRE-SPEC.md"
molde "$ALVO" 99 "Fase sintética da bancada"

echo "-- 11 seções na ordem"
esperadas=(
  "## 1. A fase em uma página (versão para leigo)"
  "## 2. Origem — o fato que motivou (fonte, data)"
  "## 3. O que já existe no código (arquivo:linha)"
  "## 4. Medições"
  "## 5. Decisões do dono"
  "## 6. Hipóteses falsificadas / opções descartadas"
  "## 7. Regras de negócio ditadas pelo cliente (citação → regra)"
  "## 8. Fora de escopo"
  "## 9. Aberto deliberadamente — o que o spec/discuss deve fechar"
  "## 10. Ressalvas (o que as medições NÃO provam)"
  "## 11. Referências"
)
anterior=0
for s in "${esperadas[@]}"; do
  n=$(grep -nF "$s" "$ALVO" | head -1 | cut -d: -f1)
  if [ -z "$n" ]; then
    erro "seção presente: $s"
  elif [ "$n" -le "$anterior" ]; then
    erro "seção fora de ordem: $s (linha $n, anterior $anterior)"
  else
    ok "seção $s (linha $n)"
    anterior=$n
  fi
done

echo "-- placeholders substituídos e seções vazias marcadas"
grep -q '{{' "$ALVO" && erro "sobrou placeholder {{…}}" "$(grep -n '{{' "$ALVO")" \
  || ok "nenhum placeholder {{…}} sobrou"
grep -q '^# Fase 99 — Fase sintética da bancada — PRE-SPEC$' "$ALVO" \
  && ok "título montado com número e nome da fase" || erro "título do documento" "$(head -1 "$ALVO")"
[ "$(grep -c -- '— nada —' "$ALVO")" -ge 8 ] \
  && ok "seções vazias marcadas '— nada —' (nunca removidas)" || erro "marcação '— nada —'"
grep -q 'NÃO é o SPEC' "$ALVO" && ok "preâmbulo declara que não é o SPEC" || erro "preâmbulo"
grep -q 'só por número/papel' "$ALVO" && ok "preâmbulo declara a regra de PII" || erro "regra de PII no preâmbulo"

echo "-- marcas e bloco vazio"
grep -q '<!-- gad:decisoes:begin v1 -->' "$ALVO" && ok "marca de abertura" || erro "marca de abertura"
grep -q '<!-- gad:decisoes:end -->'      "$ALVO" && ok "marca de fecho"    || erro "marca de fecho"
sed -n '/gad:decisoes:begin/,/gad:decisoes:end/p' "$ALVO" | grep -q '^\[\]$' \
  && ok "bloco nasce vazio ([])" || erro "bloco vazio"

echo "-- confere-pre-spec.sh --so-bloco contra o esqueleto (comportamento real)"
saida=$(bash "$CONFERE" --so-bloco "$ALVO" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "exit 0 — bloco vazio é bem-formado, o script NÃO reprova" \
  || erro "exit 0 esperado (não existe código BLOCO-VAZIO)" "exit=$rc
$saida"
echo "$saida" | grep -q 'entradas=0' && ok "resumo reporta entradas=0" || erro "entradas=0" "$saida"
echo "$saida" | grep -q 'pre_spec_bloco: ok' && ok "estado 'ok' (o gate de conteúdo é o passo 6)" \
  || erro "pre_spec_bloco: ok" "$saida"
echo "$saida" | grep -q 'BLOCO-VAZIO' \
  && erro "o script emitiu BLOCO-VAZIO — contrato mudou, atualize a skill e o README" "$saida" \
  || ok "nenhum código BLOCO-VAZIO existe (documentado no README)"

echo "-- nome de fase com metacaractere (o passo 4 não usa sed)"
HOSTIL="$RAIZ/hostil-PRE-SPEC.md"
molde "$HOSTIL" 24.4 'Resultado (DRE) — receita/desconto & rateio'
grep -qF '# Fase 24.4 — Resultado (DRE) — receita/desconto & rateio — PRE-SPEC' "$HOSTIL" \
  && ok "nome com '/' e '&' entra íntegro no título" || erro "nome hostil no título" "$(head -1 "$HOSTIL")"
grep -q '{{' "$HOSTIL" && erro "sobrou placeholder no caso hostil" || ok "nenhum placeholder sobrou"

echo "-- PII do esqueleto"
bash "$SKILL/scripts/confere-pii.sh" "$ALVO" >/dev/null 2>&1 \
  && ok "esqueleto passa limpo no confere-pii.sh" \
  || erro "esqueleto acusado pelo confere-pii.sh" "$(bash "$SKILL/scripts/confere-pii.sh" "$ALVO" 2>&1)"

fim
