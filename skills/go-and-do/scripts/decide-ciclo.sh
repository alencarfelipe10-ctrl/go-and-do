#!/usr/bin/env bash
# decide-ciclo.sh — parada por RENDIMENTO do loop de revisão adversarial (decisão 1.10).
#
# Os tetos viraram meta (1 de 9 rodadas multi-ciclo convergiu antes do teto) e os
# ciclos tardios rendem quase só C/D (11 A em 128 acionáveis nas 6 fases). Um ciclo
# custa ~US$5–8; um achado C custa 1 edit. Este script decide 100% mecanicamente se o
# ciclo seguinte roda — o coordenador obedece, sem julgamento.
#
# Uso: decide-ciclo.sh <phase_dir> <ciclo>
#
# Fonte: <phase_dir>/.intent/.vereditos-c<C>.txt, escrito pelo gad-verificador ao fim
# do ciclo — uma linha por achado: `id | classe | veredito | categoria`
#   classe   ∈ novo | reformulado | reaberto      (reformulado é eco, não sinal)
#   veredito ∈ confirmado | nao_sustentado | ja_coberto
#   categoria∈ A-produto | B-viabilidade | C-instrumentacao | D-documental |
#              E-decisao-do-dono | (vazia → conta como A/B, regra fail-up 1.8)
#
# Decisão (nesta ordem):
#   para-zerou           — nenhum achado novo/reaberto confirmado no ciclo
#   para-teto            — ciclo >= 4 (teto duro caiu de 5 para 4)
#   continua             — ciclo 1 (nunca é cortado) OU >=1 novo confirmado A/B
#   para-custo-marginal  — só C/D/E confirmados: viram LOTE ÚNICO de correção
#                          aplicado na saída, sem re-submeter aos revisores
#
# O motivo vai ao run-log (auto-registro; G.1 audita se a regra para cedo demais).
# Saída: JSON 1 linha + espelho PC-5. Exit 0 = decidiu · 3 = sem vereditos do ciclo
# (verificador não rodou — o confere-rotas.sh é quem cobra) · 2 = uso inválido.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; C="${2:-}"
[ -n "$PD" ] && [ -n "$C" ] || { echo "uso: decide-ciclo.sh <phase_dir> <ciclo>" >&2; exit 2; }
V="$PD/.intent/.vereditos-c$C.txt"
if [ ! -f "$V" ]; then
  gad_json_out decide-ciclo "$(jq -cn --arg c "$C" \
    '{ciclo:$c, decisao:"sem_dados", motivo:"vereditos do ciclo ausentes (.intent/.vereditos-c'"$C"'.txt) — gad-verificador não fechou o ciclo"}')" || true
  exit 3
fi

novos=0; novos_ab=0; lote_cd=()
while IFS='|' read -r id classe veredito categoria; do
  id=$(echo "$id" | tr -d ' '); classe=$(echo "$classe" | tr -d ' ')
  veredito=$(echo "$veredito" | tr -d ' '); categoria=$(echo "$categoria" | tr -d ' ')
  [ -n "$id" ] || continue
  [ "$veredito" = confirmado ] || continue
  case "$classe" in novo|reaberto) ;; *) continue ;; esac
  novos=$((novos+1))
  case "$categoria" in
    C-*|D-*|E-*) lote_cd+=("$id") ;;
    *) novos_ab=$((novos_ab+1)) ;;   # A-, B- e vazia (fail-up 1.8)
  esac
done < "$V"

CINT=$(printf '%s' "$C" | tr -cd '0-9'); : "${CINT:=1}"
if [ "$novos" = 0 ]; then
  DEC=para-zerou; MOT="ciclo $C: nenhum achado novo confirmado — convergiu"
elif [ "$CINT" -ge 4 ]; then
  DEC=para-teto; MOT="ciclo $C: teto duro de 4 ciclos atingido ($novos novos confirmados no ciclo)"
elif [ "$CINT" -le 1 ] || [ "$novos_ab" -gt 0 ]; then
  DEC=continua; MOT="ciclo $C: $novos_ab novo(s) A/B confirmado(s) — rendimento justifica o próximo ciclo"
else
  DEC=para-custo-marginal; MOT="ciclo $C: $novos novos confirmados, todos C/D/E — lote único de correção na saída, sem re-submeter"
fi

LOTE=$(printf '%s\n' ${lote_cd[@]+"${lote_cd[@]}"} | jq -R . | jq -cs 'map(select(length>0))')
gad_autoregistro "decide-ciclo.sh" 0 "$DEC ($MOT)" || true
gad_json_out decide-ciclo "$(jq -cn --arg c "$C" --arg d "$DEC" --arg m "$MOT" \
  --argjson n "$novos" --argjson ab "$novos_ab" --argjson l "$LOTE" \
  '{ciclo:$c, decisao:$d, motivo:$m, novos_confirmados:$n, novos_ab:$ab, lote_cde:$l}')"
