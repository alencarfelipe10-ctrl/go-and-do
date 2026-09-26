#!/usr/bin/env bash
# test-contrato-intent-discuss.sh — presença dos textos do plano 2 (05/09/2026) no prompt do
# filho `gad-discuss`, no agente `gad-explore` e no `prompts/code-review.md`.
#
# O que se cobra aqui é literal que outro leitor grepa ou que o coordenador lê no retorno:
# o passo 0 aceita `explore:` e proíbe a leitura exploratória própria (C5, rota B); o retorno
# traz `leituras_proprias` e `criterios_nao_fecham`; o passo 3 manda tratar os WARN da guarda
# em `dedup_aplicada` (C1) e rebaixar prescrição a `nota` (C2); a seção «Critério que não fecha»
# fixa o prefixo `criterio_nao_fecha:` (C4); o explorador responde por requisito; o code-review
# reporta `decisoes_lidas` (C7).
#
# Tarefa 59/L3 (26/09): árvore fora da fase sai comitada/revertida antes do hand-back
# (FM-F27INS-11INT, retorno `arvore_extra`) e contradição entre decisões próprias é
# reconciliada antes do commit (FJ-F27INS-02INT); no intent.md: `--inicio` do
# `correcoes-commit.sh` não lista `<INTENT-REVIEW>` (FM-F27INS-03INT), a guarda estrutural
# roda com `--spec` depois de correção que toca o CONTEXT (FJ-F27INS-04INT), evidência de
# ciclo já consumida não se reescreve no fecho (FJ-F27INS-05INT), a limpeza do passo 7b chama
# `limpa-intencao.sh` em vez do glob na mão (b7), e achado citado em mais de um artefato é
# corrigido nos dois (FJ-F27INS-01INT).
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
P="$AQUI/../skills/go-and-do/prompts/intent-discuss.md"
E="$AQUI/../agents/gad-explore.md"
R="$AQUI/../skills/go-and-do/prompts/code-review.md"
I="$AQUI/../skills/go-and-do/prompts/intent.md"
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; falhas=$((falhas+1)); }
tem() { grep -qF -- "$2" "$1" && ok "$3" || erro "$3"; }

echo "== intent-discuss.md"
tem "$P" 'Quando o despacho trouxer `explore: <caminho>`' "passo 0: aceita o arquivo do explorador (rota B do C5)"
tem "$P" 'prefixo `leitura_propria: <arquivo> — <fato>`' "passo 0: leitura própria vai registrada com prefixo fixo"
tem "$P" 'leituras_proprias: <n arquivos do projeto' "retorno: campo leituras_proprias"
tem "$P" 'criterios_nao_fecham: <n; 0 quando nenhum>' "retorno: campo criterios_nao_fecham"
tem "$P" '[guard] WARN: D-NN repete … do SPEC' "passo 3: lê os WARN da checagem 8 da guarda"
tem "$P" 'conte-a em `dedup_aplicada`' "passo 3: WARN tratado conta em dedup_aplicada"
tem "$P" 'a receita desce para `nota`' "passo 3: prescrição vira invariante + modo de falha; receita em nota (C2)"
tem "$P" '## Critério que não fecha' "seção «Critério que não fecha» (C4)"
tem "$P" '`criterio_nao_fecha: <AC-nn|R-n> — <o que mediu> — <comando que reproduz>`' "prefixo exato do sino criterio_nao_fecha:"
grep -qE '^   [0-9]+\.|^[0-9]+\.' "$P" >/dev/null && ok "numeração dos passos preservada" || erro "numeração"
tem "$P" 'arvore_extra: <arquivo — comitado|revertido — porquê' "retorno: campo arvore_extra (FM-11INT), não vira sino"
tem "$P" 'reconcilie as duas decisões agora' "passo 4b: contradição entre decisões próprias reconciliada antes do commit (FJ-02INT)"
echo "== intent.md"
grep -qF 'listá-lo aqui faz o script recusar por alvo inexistente' "$I" && ok "--inicio não lista INTENT-REVIEW (FM-03INT)" || erro "--inicio ainda lista INTENT-REVIEW"
tem "$I" 'Re-rode a guarda estrutural, sempre com `--spec`' "guarda com --spec depois de correção no CONTEXT (FJ-04INT)"
tem "$I" 'Nunca conserte uma `FALHA` reescrevendo evidência de ciclo já consumida' "fecho não reescreve evidência de ciclo consumida (FJ-05INT)"
tem "$I" 'limpa-intencao.sh "<phase_dir>"' "passo 7b chama limpa-intencao.sh (b7)"
grep -qF 'setopt nullglob' "$I" && erro "passo 7b ainda tem o glob na mão (b7)" || ok "passo 7b sem o setopt nullglob antigo"
tem "$I" 'procure o mesmo ponto nos dois artefatos' "correção procura o mesmo ponto no SPEC e no CONTEXT (FJ-01INT)"
echo "== gad-explore.md"
tem "$E" 'uma conclusão por R-n, nunca por' "explorador responde por requisito quando a pergunta vem do discuss"
grep -q '^tools: Read, Bash, Grep, Glob$' "$E" && ok "ferramentas do explorador intactas (somente leitura)" || erro "tools do gad-explore mudaram"
echo "== code-review.md"
tem "$R" 'decisoes_lidas: sim | nao' "retorno do code-review declara decisoes_lidas (C7)"
tem "$R" '`phase_dir`: é por ele que o revisor lê o bloco `<decisions>`' "missão: confere que phase_dir chegou ao revisor"

echo
[ "$falhas" -eq 0 ] && echo "test-contrato-intent-discuss: TUDO OK" || echo "test-contrato-intent-discuss: $falhas falha(s)"
[ "$falhas" -eq 0 ]
