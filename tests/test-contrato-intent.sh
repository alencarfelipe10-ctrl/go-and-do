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
#   Baixos do revisor L12 — B2 (FM-F27INS-04INT/FJ-F27INS-03INT): o `.aplicado` não é mais
#       sobrescrito in-place (herda `commits`/`rodadas`; a rodada «b» passa só os ids novos) ·
#       B3 (FM-F27INS-01ENC): a trava de gate mora em `.planning/.gad/gates/<fase>/<id>.json`.
#   bash tests/test-contrato-intent.sh      · exit 0 = verde
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SK="$AQUI/../skills/go-and-do"
I="$SK/prompts/intent.md"
RL="$SK/prompts/intent-releitura.md"
W1="$SK/workflow-etapa-1.md"
CF="$SK/scripts/caminho-fase.sh"
RD="$AQUI/../README.md"
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

echo "== B2 · .aplicado com rodadas (não sobrescrito in-place)"
tem "$I" '`--ids` só com os ids NOVOS desta rodada' "rodada «b»: --ids só com os novos"
tem "$I" 'rodadas anteriores do ciclo (`commits`, `rodadas`)' "intent.md descreve a herança"
nao "$I" 'sobrescrito in-place' "intent.md: «sobrescrito in-place» saiu"
nao "$I" 'que pode ser maior que o da primeira' "intent.md: releitura lista os caminhos da rodada, não a união"
tem "$RL" '`.aplicado` guarda todas as rodadas do ciclo (`commits`, `rodadas`)' "intent-releitura.md descreve o formato novo"
nao "$RL" 'foi sobrescrito' "intent-releitura.md: «foi sobrescrito» saiu"

echo "== B3 · trava de gate no estado ignorado da rodada"
tem "$W1" '`.planning/.gad/gates/<phase dir name>/<etapa>.json`' "workflow-etapa-1.md: caminho novo da trava"
nao "$W1" '`.gad/gates/<etapa>.json` lock' "workflow-etapa-1.md: caminho antigo saiu"
tem "$RD" 'a trava de gate reprovado mora em `.planning/.gad/gates/<pasta da fase>/<etapa>.json`, ignorada' "README: a trava fora da pasta commitada"
nao "$RD" '`gates/` (trava de gate reprovado)' "README: a trava não aparece mais como evidência commitada"
tem "$CF" 'resolva-a por' "caminho-fase.sh: aponta o helper da trava"
nao "$CF" 'fences/3.ok gates/5.json' "caminho-fase.sh --tabela: sem gates/5.json como exemplo da pasta da fase"

echo
[ "$falhas" -eq 0 ] && echo "test-contrato-intent: TUDO OK" || echo "test-contrato-intent: $falhas falha(s)"
[ "$falhas" -eq 0 ]
