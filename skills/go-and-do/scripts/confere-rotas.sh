#!/usr/bin/env bash
# confere-rotas.sh — enforcement mecânico da rota de verificação da revisão adversarial
# (v1.8.2; decisão do dono 04/08 após a F22: ciclos c3=10 e c4=3 brutos verificados
# inline contra o teto de 2 — disclosure houve, rede não; a regra deixa de ser prosa).
#
# Uso: confere-rotas.sh <pareceres_dir>
#
# Para cada ciclo N presente no diretório (detectado pelos marcadores .done-cN-* ou
# pela tabela .tabela-cN.txt):
#   - SEM-TABELA  cN → o piso mecânico não rodou (a contagem de brutos do ciclo é
#     autorreportada — proibido desde a v1.8.2).
#   - VIOLACAO    cN → a tabela mostra >=3 achados brutos e não existe o marcador
#     .verificador-cN.done (o gad-verificador não rodou: rota inline fora do teto).
#   - ok          cN → rota respeitada (>=3 com verificador, ou <=2 em qualquer rota).
#
# Exit 0 = todas as rotas respeitadas · exit 1 = há SEM-TABELA/VIOLACAO (quem chamou
# NÃO aceita o fecho da etapa: despacha gad-verificador retroativo para os ciclos
# apontados e re-roda) · exit 2 = uso inválido.
#
# Régua da skill: verificação vira script; julgamento fica no modelo.

set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gsd-shim.sh" 2>/dev/null && trap 'gad_autoregistro "confere-rotas.sh" "$?"' EXIT || true
DIR="${1:?uso: confere-rotas.sh <pareceres_dir>}"
[ -d "$DIR" ] || { echo "ERRO: diretório não encontrado: $DIR" >&2; exit 2; }

ciclos=$(ls "$DIR"/.done-c*-* "$DIR"/.tabela-c*.txt 2>/dev/null \
  | grep -oE '\.(done|tabela)-c[0-9]+' | grep -oE '[0-9]+' | sort -un)
[ -n "$ciclos" ] || { echo "nenhum ciclo detectado em $DIR"; exit 0; }

falha=0
for N in $ciclos; do
  tabela="$DIR/.tabela-c$N.txt"
  if [ ! -f "$tabela" ]; then
    echo "SEM-TABELA c$N (confere-ciclo.sh --tabela não rodou; contagem autorreportada)"
    falha=1
    continue
  fi
  # brutos = linhas de achado da tabela markdown (exclui header, separador e ILEGÍVEL)
  brutos=$(grep -cE '^\| [a-z]+ \| L?[0-9]+ \|' "$tabela" || true)
  if [ "$brutos" -ge 3 ] && [ ! -f "$DIR/.verificador-c$N.done" ]; then
    echo "VIOLACAO c$N ($brutos brutos sem gad-verificador — rota inline fora do teto de 2)"
    falha=1
  else
    echo "ok c$N ($brutos brutos$([ -f "$DIR/.verificador-c$N.done" ] && echo ', verificador rodou'))"
  fi
done
exit $falha
