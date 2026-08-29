#!/usr/bin/env bash
# test-fase.sh — abre-fase.sh contra o `init.phase-op` REAL do gsd-tools, numa bancada
# sintética no scratchpad (ROADMAP mínimo: `### Phase NN: nome` + `**Goal:**`).
#
# O que se prova:
#   1. fase no ROADMAP sem diretório  → dir = expected_phase_dir, criado sob demanda
#   2. o nome do arquivo sai do `padded_phase`, não do argumento (fase 2 → 02-PRE-SPEC.md)
#   3. arquivo já no disco            → existe=true (a skill entra em modo revisão)
#   4. fase fora do ROADMAP           → phase_found=false e exit 4 (nunca `$NN-nova`)
#   5. --inserir sem --apos           → recusa explicando que o GSD calcula o decimal
set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib-bancada.sh"

A="$SKILL/scripts/abre-fase.sh"
RAIZ=$(bancada fase)

echo "-- fase no ROADMAP, diretório ainda inexistente"
J=$(bash "$A" 99 --raiz "$RAIZ"); rc=$?
[ "$rc" = 0 ] && ok "exit 0" || erro "exit 0" "obtido $rc"
[ "$(jq_campo "$J" phase_found)" = "true" ] && ok "phase_found=true" || erro "phase_found=true" "$J"
DIR=$(jq_campo "$J" dir)
case "$DIR" in
  "$RAIZ"/.planning/phases/99-*) ok "dir = expected_phase_dir do GSD ($(basename "$DIR"))" ;;
  *) erro "dir = expected_phase_dir" "$DIR" ;;
esac
case "$DIR" in *-nova) erro "dir não pode ser o fallback \$NN-nova" "$DIR" ;; esac
[ "$(jq_campo "$J" existe)" = "false" ] && ok "existe=false antes de escrever" || erro "existe=false" "$J"
[ -d "$DIR" ] && erro "sem --criar o script não pode criar o diretório" "$DIR existe" || ok "sem --criar nada é criado no disco"

echo "-- --criar cria o diretório"
J=$(bash "$A" 99 --raiz "$RAIZ" --criar)
DIR=$(jq_campo "$J" dir)
[ -d "$DIR" ] && ok "--criar fez mkdir -p" || erro "--criar fez mkdir -p" "$DIR ausente"
[ "$(jq_campo "$J" criado)" = "true" ] && ok "criado=true" || erro "criado=true" "$J"

echo "-- padded_phase manda no nome do arquivo (fase 2 → 02-PRE-SPEC.md)"
J=$(bash "$A" 2 --raiz "$RAIZ" --criar)
[ "$(jq_campo "$J" padded)" = "02" ] && ok "padded=02 para a fase 2" || erro "padded=02" "$J"
ALVO=$(jq_campo "$J" alvo)
case "$ALVO" in
  */02-PRE-SPEC.md) ok "alvo termina em 02-PRE-SPEC.md (é o que o abre-rodada.sh procura)" ;;
  *) erro "alvo = <dir>/02-PRE-SPEC.md" "$ALVO" ;;
esac
[ "$ALVO" = "$(jq_campo "$J" dir)/02-PRE-SPEC.md" ] && ok "alvo = dir + padded + -PRE-SPEC.md" \
  || erro "alvo = dir + padded + -PRE-SPEC.md" "$ALVO"

echo "-- arquivo já existente → modo revisão"
molde "$ALVO" 02 "Fase de um digito"
J=$(bash "$A" 2 --raiz "$RAIZ")
[ "$(jq_campo "$J" existe)" = "true" ] && ok "existe=true com o arquivo no disco" || erro "existe=true" "$J"

echo "-- fase fora do ROADMAP"
J=$(bash "$A" 77 --raiz "$RAIZ"); rc=$?
[ "$rc" = 4 ] && ok "exit 4 para fase ausente do ROADMAP" || erro "exit 4" "obtido $rc"
[ "$(jq_campo "$J" phase_found)" = "false" ] && ok "phase_found=false" || erro "phase_found=false" "$J"
[ -z "$(jq_campo "$J" dir)" ] && ok "dir nulo (nada de \$NN-nova)" || erro "dir nulo" "$J"

echo "-- --inserir sem --apos é recusado"
saida=$(bash "$A" 98.1 --raiz "$RAIZ" --inserir "Fase nova" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "exit 2" || erro "exit 2 em --inserir sem --apos" "obtido $rc"
echo "$saida" | grep -q "calcula o decimal" \
  && ok "a recusa explica que o GSD calcula o decimal a partir da fase anterior" \
  || erro "mensagem da recusa" "$saida"

echo "-- --inserir: quem calcula o número é o GSD (phase.insert real na bancada)"
RAIZ2=$(bancada fase-insert)
J=$(bash "$A" 98.1 --raiz "$RAIZ2" --inserir "Fase inserida de teste" --apos 98 --criar); rc=$?
[ "$rc" = 0 ] && ok "exit 0" || erro "exit 0 no --inserir" "exit=$rc
$J"
[ "$(jq_campo "$J" numero_atribuido)" = "98.1" ] && ok "numero_atribuido=98.1 (98 + 1º decimal)" \
  || erro "numero_atribuido" "$J"
[ "$(jq_campo "$J" padded)" = "98.1" ] && ok "padded=98.1 (o ponto é a convenção)" || erro "padded=98.1" "$J"
grep -q '^### Phase 98.1:.*(INSERTED)' "$RAIZ2/.planning/ROADMAP.md" \
  && ok "ROADMAP ganhou a entrada com o marcador (INSERTED)" || erro "entrada no ROADMAP"
[ -d "$(jq_campo "$J" dir)" ] && ok "diretório da fase existe" || erro "diretório da fase"
case "$(jq_campo "$J" alvo)" in
  */98.1-PRE-SPEC.md) ok "alvo = 98.1-PRE-SPEC.md" ;;
  *) erro "alvo = 98.1-PRE-SPEC.md" "$(jq_campo "$J" alvo)" ;;
esac

echo "-- projeto sem .planning"
saida=$(bash "$A" 99 --raiz "${RAIZ}-inexistente" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "exit 2 fora de projeto GSD" || erro "exit 2 fora de projeto GSD" "obtido $rc/$saida"

fim
