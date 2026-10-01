#!/usr/bin/env bash
# hooks/lib/gad-projeto.sh — ajudante do marcador de projeto gad para os vigias shell (D-16, CONV-01).
#
# Uso (sempre executado por caminho absoluto, nunca carregado com source):
#   printf '%s' "$PAYLOAD_DO_HOOK" | bash "<hooks>/lib/gad-projeto.sh" || exit 0
# Sai 0 se o projeto do cwd do payload é gad (arquivo regular .planning/gad-projeto.json no cwd, na raiz do git ou
# na árvore principal), 1 se não é. Nunca imprime nada: stdout e stderr vão para /dev/null.
#
# Sem lógica própria: o stdin passa inteiro ao modo de execução direta do gad-projeto.js ao lado, e o node é achado
# pelo gad-node-runner.sh do mesmo jeito que para os vigias .js (primeiro argumento vazio). Assim o reconhecimento
# usa só bash, node e git, e o limite de 1 s por chamada de git é feito pelo próprio Node. Sem node o runner sai 127
# (diferente de 0, então não marcado, como os vigias .js nessa casa); quem chama trata todo código diferente de 0
# como não marcado.
exec bash "${BASH_SOURCE[0]%/*}/../gad-node-runner.sh" "" "${BASH_SOURCE[0]%/*}/gad-projeto.js" >/dev/null 2>&1
