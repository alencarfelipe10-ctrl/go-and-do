#!/usr/bin/env bash
# test-contrato-intent-releitura.sh — FM-F4RLR-10INT: cada rodada de correção pós-releitura
# (`c<C>b`, `c<C>c`, …) grava `.json` PRÓPRIO (`.releitura-c<C>b.json`, …), sem sobrescrever
# o da rodada anterior do mesmo ciclo (`.releitura-c<C>.json`, primeira rodada). Cobra o
# texto literal no prompt do filho (quem grava) e no despacho do coordenador
# (`prompts/intent.md`, quem lê o retorno e explica o marcador), na mesma grafia (`cNb`,
# minúsculo, sem separador) que `turnos-por-ciclo.py` já reconhece para `.correcoes-cNb`,
# e no resolvedor do consumidor (`briefing-build.sh`, que lê a letra mais alta do ciclo).
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
R="$AQUI/../skills/go-and-do/prompts/intent-releitura.md"
I="$AQUI/../skills/go-and-do/prompts/intent.md"
B="$AQUI/../skills/go-and-do/scripts/briefing-build.sh"
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; falhas=$((falhas+1)); }
tem() { grep -qF -- "$2" "$1" && ok "$3" || erro "$3"; }

echo "== intent-releitura.md (quem grava)"
tem "$R" 'R=$(G intent/<RODADA>/releitura.json)' "heredoc grava no nome da própria rodada, não mais fixo no ciclo"
tem "$R" 'mv -f "$R.tmp" "$R"' "mv atômico para <RODADA>/releitura.json (v2.10.1: nome novo, resolvido pelo caminho-fase.sh)"
tem "$R" 'CADA rodada de correção pós-releitura (`c<C>b`, `c<C>c`, …)' "texto explícito: toda rodada pós-releitura grava arquivo próprio"
tem "$R" '`c<C>b/releitura.json`, `c<C>c/releitura.json`, …' "grafia exata .releitura-c<C>b.json (e cadeia c<C>c, …), sem sobrescrever a rodada anterior"
tem "$R" 'a rodada de letra mais alta que existir' "explica ao filho que o consumidor prioriza a letra mais alta"

echo "== intent.md (quem despacha e explica o marcador)"
tem "$I" 'leva o nome da própria rodada (`<rodada>/releitura.json`, igual ao `.done`)' "despacho: .json segue o rótulo da rodada, igual ao .done"
tem "$I" 'de correção pós-releitura (`c<C>b`, `c<C>c`, …) grava seu próprio arquivo' "despacho: grafia exata — toda rodada pós-releitura grava arquivo próprio"

echo "== briefing-build.sh (quem lê)"
tem "$B" 'def caminho_releitura(IN, ciclo):' "resolvedor único (não duplicado nos dois pontos de leitura)"
tem "$B" 'intent/c%s[a-z]/releitura.json' "resolvedor procura QUALQUER letra de rodada (mesma família \`cNb\`/\`cNc\` do .correcoes-cNb), pega a mais alta"
tem "$B" 'rel_path = caminho_releitura(IN, prev)' "leitura do ciclo anterior (c>=2) passa pelo resolvedor"

echo
[ "$falhas" -eq 0 ] && echo "test-contrato-intent-releitura: TUDO OK" || echo "test-contrato-intent-releitura: $falhas falha(s)"
[ "$falhas" -eq 0 ]
