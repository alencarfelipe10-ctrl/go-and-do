#!/usr/bin/env bash
# spot-check-ponteiros.sh — verificação determinística de citações `arquivo:linha`.
#
# Uso: spot-check-ponteiros.sh <arquivo.md> [project_root]
#   Extrai todo padrão `caminho:linha` do arquivo, resolve o caminho a partir de
#   project_root (default: cwd) e confere: (a) o arquivo existe; (b) a linha existe.
#   Saída: uma linha por ponteiro QUEBRADO (`MISSING-FILE caminho:linha` ou
#   `MISSING-LINE caminho:linha (arquivo tem N linhas)`), e um sumário final
#   `OK <ok>/<total>`. Exit 0 sempre — é ferramenta de relato; o julgamento do que
#   fazer com um ponteiro quebrado é do modelo.
#
# Régua da skill: verificação vira script; julgamento fica no modelo.

set -u
DOC="${1:?uso: spot-check-ponteiros.sh <arquivo.md> [project_root]}"
ROOT="${2:-$(pwd)}"

[ -f "$DOC" ] || { echo "ERRO: arquivo não encontrado: $DOC" >&2; exit 2; }
[ -d "$ROOT" ] || { echo "ERRO: project_root não encontrado: $ROOT" >&2; exit 2; }

total=0; ok=0
# Padrão: sequência com pelo menos uma `/` ou extensão de arquivo, dois-pontos, número.
# Deduplicado para não recontar a mesma citação repetida.
grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9_]+:[0-9]+' "$DOC" | sort -u | while read -r ptr; do
  file="${ptr%:*}"; line="${ptr##*:}"
  # Resolve: absoluto como veio; relativo a partir do ROOT.
  case "$file" in
    /*) path="$file" ;;
    *)  path="$ROOT/$file" ;;
  esac
  if [ ! -f "$path" ]; then
    echo "MISSING-FILE $ptr"
    continue
  fi
  nlines=$(wc -l < "$path")
  if [ "$line" -gt "$nlines" ]; then
    echo "MISSING-LINE $ptr (arquivo tem $nlines linhas)"
  fi
done > /tmp/spot-check-$$.out

broken=$(wc -l < /tmp/spot-check-$$.out)
total=$(grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9_]+:[0-9]+' "$DOC" | sort -u | wc -l)
cat /tmp/spot-check-$$.out
rm -f /tmp/spot-check-$$.out
echo "OK $((total - broken))/$total"
exit 0
