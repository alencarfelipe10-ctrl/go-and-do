#!/usr/bin/env bash
# limpa-intencao.sh — a limpeza do fecho da etapa de intenção (passo 7b do prompts/intent.md,
# política 1.5), sem depender do shell de quem chama.
#
# POR QUE ESTE SCRIPT EXISTE (FM-F27INS-08INT, tarefa 59 b7)
# O passo 7b fazia a limpeza inline: `setopt nullglob … rm -f $(G 'intent/sinos-*.txt') …`.
# O padrão sai do `caminho-fase.sh` como TEXTO com `*`, e quem expande é o shell do
# coordenador — sob zsh a expansão não aconteceu (F27 INS, run-log seq 84): briefings,
# listas de sinos e a varredura entraram no commit de artefatos e tiveram de sair num
# commit manual. Aqui a expansão é do bash deste script (`gad_fase_glob`, o mesmo helper de
# caminhos do `caminho-fase.sh`), qualquer que seja o shell que o chamou.
#
# CONTRATO (fixado na onda 0 da tarefa 59; a L3 grava no intent.md a linha que o chama)
#   limpa-intencao.sh "<phase_dir>"      — um argumento só
#   Apaga EXATAMENTE os 4 alvos de sempre, nos dois formatos de fase (novo `.gad/intent/…`,
#   antigo `.intent/.…`):
#     intent/sinos-*.txt · intent/c*/briefing*.md · intent/varredura.md · intent/c*/mudancas.md
#   Não alargue: tudo o mais em intent/ SOBREVIVE (lista no passo 7b do intent.md — insumo da
#   /audit-gad e dos gates). Só arquivos regulares; pasta nunca.
#
# Exit 0 = limpo (nada casou → silêncio) · 2 = uso inválido ou <phase_dir> inexistente.

set -uo pipefail
AQUI="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
. "$AQUI/lib/gsd-shim.sh" 2>/dev/null && trap 'gad_autoregistro "limpa-intencao.sh" "$?"' EXIT || true
. "$AQUI/lib/gad-caminhos.sh"

[ $# -eq 1 ] && [ -n "${1:-}" ] || { echo "uso: limpa-intencao.sh <phase_dir>" >&2; exit 2; }
PD="${1%/}"
[ -d "$PD" ] || { echo "ERRO: phase_dir inexistente: $PD" >&2; exit 2; }

ALVOS=('intent/sinos-*.txt' 'intent/c*/briefing*.md' 'intent/varredura.md' 'intent/c*/mudancas.md')

n=0
for padrao in "${ALVOS[@]}"; do
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    { [ -f "$f" ] || [ -L "$f" ]; } || continue
    rm -f -- "$f" && n=$((n+1))
  done < <(gad_fase_glob "$PD" "$padrao")
done

[ "$n" -eq 0 ] || echo "limpa-intencao: $n arquivo(s) de trabalho removido(s) de $(gad_fase_caminho "$PD" intent)"
exit 0
