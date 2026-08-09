#!/usr/bin/env bash
# spot-check-ponteiros.sh — verificação determinística de citações `arquivo:linha`.
#
# Uso: spot-check-ponteiros.sh <arquivo.md> [root ...]
#   Extrai todo padrão `caminho:linha` do arquivo, resolve o caminho e confere:
#   (a) o arquivo existe; (b) a linha existe.
#   Multi-root (auditoria 04/08 da F22: falsos-positivos MISSING-FILE em massa quando
#   o documento cita mais de uma árvore — repo + transcrições fora dele): pode passar
#   VÁRIAS raízes; um caminho relativo é tentado em cada uma, na ordem, e só é
#   MISSING-FILE se não existir em NENHUMA. Sem root → default: cwd.
#   Saída: uma linha por ponteiro QUEBRADO (`MISSING-FILE caminho:linha` ou
#   `MISSING-LINE caminho:linha (arquivo tem N linhas)`), e um sumário final
#   `OK <ok>/<total>`. Exit 0 sempre — é ferramenta de relato; o julgamento do que
#   fazer com um ponteiro quebrado é do modelo.
#
# Régua da skill: verificação vira script; julgamento fica no modelo.

set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gsd-shim.sh" 2>/dev/null && trap 'gad_autoregistro "spot-check-ponteiros.sh" "$?"' EXIT || true
DOC="${1:?uso: spot-check-ponteiros.sh <arquivo.md> [root ...]}"
shift
ROOTS=("$@")
[ ${#ROOTS[@]} -eq 0 ] && ROOTS=("$(pwd)")

[ -f "$DOC" ] || { echo "ERRO: arquivo não encontrado: $DOC" >&2; exit 2; }
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || { echo "ERRO: root não encontrado: $r" >&2; exit 2; }
done

# Padrão: sequência com pelo menos uma `/` ou extensão de arquivo, dois-pontos, número.
# Deduplicado para não recontar a mesma citação repetida.
grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9_]+:[0-9]+' "$DOC" | sort -u | while read -r ptr; do
  file="${ptr%:*}"; line="${ptr##*:}"
  # Resolve: absoluto como veio; relativo tentado em cada root, na ordem.
  path=""
  case "$file" in
    /*) [ -f "$file" ] && path="$file" ;;
    *)  for r in "${ROOTS[@]}"; do
          if [ -f "$r/$file" ]; then path="$r/$file"; break; fi
        done ;;
  esac
  if [ -z "$path" ]; then
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
