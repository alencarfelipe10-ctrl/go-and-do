#!/usr/bin/env bash
# test-contrato-intent-releitura.sh — FM-F4RLR-10INT: a passada `b` da releitura grava
# `.json` PRÓPRIO (`.releitura-c<C>b.json`), sem sobrescrever o da primeira rodada
# (`.releitura-c<C>.json`). Cobra o texto literal no prompt do filho (quem grava) e no
# despacho do coordenador (`prompts/intent.md`, quem lê o retorno e explica o marcador),
# na mesma grafia (`cNb`, minúsculo, sem separador) que `turnos-por-ciclo.py` já reconhece
# para `.correcoes-cNb`.
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
tem "$R" 'cat > "$IN/.releitura-<RODADA>.json.tmp"' "heredoc grava no nome da própria rodada, não mais fixo no ciclo"
tem "$R" 'mv -f "$IN/.releitura-<RODADA>.json.tmp" "$IN/.releitura-<RODADA>.json"' "mv atômico para .releitura-<RODADA>.json"
tem "$R" 'a rodada `c<C>b` (correção pós-releitura) grava um arquivo' "texto explícito: c<C>b grava arquivo próprio"
tem "$R" '`.releitura-c<C>b.json`, sem sobrescrever o da primeira rodada' "grafia exata .releitura-c<C>b.json, sem sobrescrever o da 1ª rodada"
tem "$R" 'gate do `briefing-build.sh` lê, para cada ciclo, o arquivo `b` quando ele existe' "explica ao filho que o consumidor prioriza o 'b'"

echo "== intent.md (quem despacha e explica o marcador)"
tem "$I" 'leva o nome da própria rodada (`.releitura-<rodada>.json`, igual ao `.done`)' "despacho: .json segue o rótulo da rodada, igual ao .done"
tem "$I" '`c<C>b` grava `.releitura-c<C>b.json`, próprio, sem sobrescrever o `.releitura-c<C>.json`' "despacho: grafia exata do arquivo da rodada b"

echo "== briefing-build.sh (quem lê)"
tem "$B" 'def caminho_releitura(IN, ciclo):' "resolvedor único (não duplicado nos dois pontos de leitura)"
tem "$B" '.releitura-c%sb.json' "resolvedor procura primeiro o sufixo b (mesma família \`cNb\` do .correcoes-cNb)"
tem "$B" 'rel_path = caminho_releitura(IN, prev)' "leitura do ciclo anterior (c>=2) passa pelo resolvedor"

echo
[ "$falhas" -eq 0 ] && echo "test-contrato-intent-releitura: TUDO OK" || echo "test-contrato-intent-releitura: $falhas falha(s)"
[ "$falhas" -eq 0 ]
