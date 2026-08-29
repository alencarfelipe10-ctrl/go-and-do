#!/usr/bin/env bash
# roda.sh — runner da suíte de testes da skill go-and-do.
#
# Uso: tests/roda.sh [padrão ...]
#   Sem argumento: descobre e roda TODO `tests/test-*.sh` (glob em tempo de execução —
#   nada é enumerado aqui; um teste novo aparece sozinho). Com argumento: roda só os
#   testes cujo nome de arquivo contém um dos padrões (substring simples).
#   Cada teste é um script bash independente: exit 0 = passou, ≠ 0 = falhou.
#   Saída: a saída de cada teste + resumo `N ok / M falhas`. Exit ≠ 0 se algo falhou.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
PADROES=("$@")

testes=()
for t in "$AQUI"/test-*.sh; do
  [ -f "$t" ] || continue
  if [ ${#PADROES[@]} -gt 0 ]; then
    casa=0
    for p in "${PADROES[@]}"; do
      case "$(basename "$t")" in *"$p"*) casa=1 ;; esac
    done
    [ "$casa" = 1 ] || continue
  fi
  testes+=("$t")
done

if [ ${#testes[@]} -eq 0 ]; then
  echo "nenhum teste encontrado em $AQUI (padrão: test-*.sh)"
  exit 1
fi

ok=0; falhas=0; nomes_falhos=()
for t in "${testes[@]}"; do
  nome=$(basename "$t")
  echo "=== $nome"
  if bash "$t"; then
    ok=$((ok+1))
  else
    falhas=$((falhas+1)); nomes_falhos+=("$nome")
  fi
  echo
done

echo "--------------------------------------------------"
echo "$ok ok / $falhas falhas  (de ${#testes[@]} testes)"
[ "$falhas" -eq 0 ] || printf 'falharam: %s\n' "${nomes_falhos[*]}"
[ "$falhas" -eq 0 ]
