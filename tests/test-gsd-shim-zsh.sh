#!/usr/bin/env bash
# test-gsd-shim-zsh.sh — FM-F27INS-01PLAN: o gsd-shim.sh acha a própria pasta
# também quando é sourceado por zsh (o hospedeiro do plan.md/intent.md), não só
# por bash. BASH_SOURCE não existe no zsh; sem plano B, GAD_SCRIPTS_DIR resolve
# para o cwd, e o restante do shim (gad-caminhos.sh) carrega do lugar errado.
#
# Uso: bash tests/test-gsd-shim-zsh.sh   · exit 0 = verde
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SHIM="$AQUI/../skills/go-and-do/scripts/lib/gsd-shim.sh"
SCRIPTS_DIR_ESPERADO="$(CDPATH= cd -- "$(dirname -- "$SHIM")/.." && pwd -P)"
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

echo "== (bash) source de fora do diretório do shim → GAD_SCRIPTS_DIR correto"
OUT_BASH=$(cd /tmp && bash -c ". \"$SHIM\" && printf '%s' \"\$GAD_SCRIPTS_DIR\"" 2>&1)
if [ "$OUT_BASH" = "$SCRIPTS_DIR_ESPERADO" ]; then
  ok "bash: GAD_SCRIPTS_DIR=$OUT_BASH"
else
  erro "bash: GAD_SCRIPTS_DIR esperado [$SCRIPTS_DIR_ESPERADO], obtido [$OUT_BASH]"
fi

echo "== (zsh) source de fora do diretório do shim → GAD_SCRIPTS_DIR correto (o caso real do hospedeiro)"
if command -v zsh >/dev/null 2>&1; then
  OUT_ZSH=$(cd /tmp && zsh -c ". \"$SHIM\" && printf '%s' \"\$GAD_SCRIPTS_DIR\"" 2>&1)
  if [ "$OUT_ZSH" = "$SCRIPTS_DIR_ESPERADO" ]; then
    ok "zsh: GAD_SCRIPTS_DIR=$OUT_ZSH"
  else
    erro "zsh: GAD_SCRIPTS_DIR esperado [$SCRIPTS_DIR_ESPERADO], obtido [$OUT_ZSH]"
  fi
else
  echo "  aviso — zsh ausente nesta máquina, pulando o caso real do hospedeiro"
fi

echo
if [ "$falhas" -eq 0 ]; then echo "OK — todos os casos passaram"; exit 0
else echo "FALHAS: $falhas"; exit 1; fi
