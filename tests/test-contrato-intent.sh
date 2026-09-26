#!/usr/bin/env bash
# test-contrato-intent.sh — tarefa 59, lane L16 (26/09/2026). Teste de CONTRATO do prompt do
# coordenador da intenção (`prompts/intent.md`) contra os fiscais que mudaram na t59: confere o
# texto, não o comportamento em runtime. Cada bloco exige a instrução nova e barra a antiga.
#
#   A3 (FM-F27INS-07INT) — o `confere-cardinalidade.sh` (via `cardinalidade_etapa_1`) reprova
#       toda dívida com id da «## Dívidas registradas» que falte no `deferred-items.md`; o prompt
#       não pode mais mandar a dívida C/D «só à seção».
#   A2 (FM-F27INS-09INT) — o `c0/ciclo.json` tem 4 estados (`levado_aos_consultores` + `destino`,
#       aceito pelo `briefing-build.sh` e pelo `confere-sinos.sh`); o prompt dá o schema de 4 e
#       não manda mais contornar o «gap FM-09INT».
#   bash tests/test-contrato-intent.sh      · exit 0 = verde
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SK="$AQUI/../skills/go-and-do"
I="$SK/prompts/intent.md"
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; falhas=$((falhas+1)); }
tem()  { grep -qF -- "$2" "$1" && ok "$3" || erro "$3"; }
nao()  { grep -qF -- "$2" "$1" && erro "$3 (literal ainda presente: $2)" || ok "$3"; }

echo "== A3 · FM-07INT: toda dívida com id vai ao deferred-items.md"
tem "$I" '**Toda dívida com id da seção vai também a' "passo 7: a regra nova, sem recorte por categoria"
tem "$I" 'qualquer categoria (A, B, C ou D), e também as linhas' "passo 7: vale para C/D e para as linhas do ciclo 0 acrescentadas à mão"
tem "$I" 'em qualquer categoria (A, B, C ou D — FM-07INT' "passo 5 (dispensa registrada): a mesma regra"
tem "$I" '`deferred-items.md` — a categoria não isenta.' "o prompt nomeia o fiscal que reprova"
nao "$I" 'Achado C/D vai só à seção' "a instrução antiga (C/D só à seção) saiu"
nao "$I" 'quando a categoria for `A-produto` ou `B-viabilidade`' "o recorte antigo por categoria saiu do passo 5"
nao "$I" 'Achado de categoria `A-produto` ou `B-viabilidade` vai também a' "o recorte antigo por categoria saiu do passo 7"

echo "== A2 · FM-09INT: sino do ciclo 0 com estado final levado_aos_consultores"
tem "$I" 'descartado|aberto|levado_aos_consultores","correcao_id"' "schema do c0/ciclo.json com os 4 estados"
tem "$I" 'já aqui como `levado_aos_consultores`, com o campo `destino`' "o estado é gravado no passo 2 (o arquivo não se edita depois do gate do c1)"
tem "$I" '= o próprio id do sino (`"destino":"c0-02"`)' "destino = o próprio id, forma aceita pelo confere-sinos.sh"
tem "$I" 'levado_aos_consultores → <achado ou dívida em que virou>`' "linha c0-NN do INTENT-REVIEW com o destino"
tem "$I" '`c0-NN | <sino> | <disposicao> → <destino>`' "passo 7: linhas do ciclo 0 com disposicao e destino"
nao "$I" 'gap FM-09INT' "o contorno do «gap FM-09INT» saiu"
nao "$I" 'o ciclo 0 só tem `corrigido|descartado|aberto`' "a frase do schema de 3 estados saiu"
nao "$I" '| corrigido|aberto`' "a linha c0-NN antiga (corrigido|aberto) saiu"
nao "$I" '`descartado`/`aberto` proíbem o' "a regra do correcao_id cobre os 3 estados sem correção"

echo
[ "$falhas" -eq 0 ] && echo "test-contrato-intent: TUDO OK" || echo "test-contrato-intent: $falhas falha(s)"
[ "$falhas" -eq 0 ]
