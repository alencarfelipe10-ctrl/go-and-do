#!/usr/bin/env bash
# decide-ciclo.sh — parada por RENDIMENTO do loop da consultoria especializada de
# intenção (decisão 1.10).
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
#   veredito ∈ confirmado | nao_sustentado | ja_coberto | confirmado_irrelevante
#              (confirmado_irrelevante = confirmado mas sem vínculo ao Goal — registrado
#              como dívida, não conta: R2/R3 do plano 3; o loop continua por proteção do
#              Goal, não por achado. O formato NÃO ganhou campo: um 5º campo cairia dentro
#              de `categoria` no `read` abaixo, em silêncio.)
#   categoria∈ A-produto | B-viabilidade | C-instrumentacao | D-documental |
#              E-decisao-do-dono | (vazia → conta como A/B, regra fail-up 1.8)
#
# Decisão (nesta ordem):
#   para-zerou           — nenhum achado novo/reaberto confirmado no ciclo E nenhuma lane
#                          reprovada por `parecer_informe` (P15: marcador
#                          pareceres/.reformat-<lane>-c<C>.reprovada ou status
#                          rc_reason=parecer_informe). Zero por parecer sem achados
#                          legíveis é silêncio, não convergência: cai em continua/para-teto.
#   para-teto            — ciclo >= 4 (teto duro caiu de 5 para 4)
#   continua             — ciclo 1 (nunca é cortado) · ciclo 2: >=1 novo confirmado A/B ·
#                          ciclo >=3 (S-2, tarefa 48b — aperto do rendimento): >=2 novos
#                          confirmados A/B, OU custo/achado <= teto (ver env abaixo)
#   para-rendimento       — só o caso GENUINAMENTE NOVO do aperto (ciclo >=3, exatamente
#                          1 novo A/B confirmado, sem custo/achado <= teto): esse achado
#                          ANTES da 48b comprava sozinho mais um ciclo; agora não compra,
#                          mas TAMBÉM vira lote (campo `lote_ab`, separado de `lote_cde`) —
#                          nunca se descarta achado. ⚠️ Rota NOVA para intent.md:624, que só
#                          conhece `para-custo-marginal → lote_cde`; ele precisa aprender
#                          `para-rendimento → lote_cde + lote_ab` (dependência de
#                          sequenciamento com a lane de prompts, não só documentação).
#   para-custo-marginal  — ciclo 2 só C/D/E, OU ciclo >=3 com 0 A/B (mesmo desfecho,
#                          byte-idêntico: `lote_ab` fica vazio nos dois casos, por isso NÃO
#                          ganha rótulo próprio) — vira LOTE ÚNICO de correção (`lote_cde`)
#                          aplicado na saída, sem re-submeter aos revisores
#
# Custo/achado (S-2, tarefa 48b — só pesa a partir do ciclo 3): o script não MEDE custo
# (não tem telemetria de tokens/USD); quem chama pode informar o gasto do ciclo por
# `GAD_CUSTO_CICLO` (USD, ponto flutuante; ausente/vazio = regra do custo não se aplica,
# só a contagem de novos A/B decide) contra o teto `GAD_CUSTO_POR_ACHADO_TETO` (default 3 —
# a régua do cabeçalho, "um ciclo custa ~US$5–8; um achado C custa 1 edit", ancora o
# ponto de equilíbrio; documentar mudança de default no CHANGELOG).
#
# O motivo vai ao run-log (auto-registro; G.1 audita se a regra para cedo demais).
# Saída: JSON 1 linha + espelho PC-5. Exit 0 = decidiu · 3 = sem vereditos do ciclo
# (verificador não rodou — o confere-rotas.sh é quem cobra) · 2 = uso inválido.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; C="${2:-}"
[ -n "$PD" ] && [ -n "$C" ] || { echo "uso: decide-ciclo.sh <phase_dir> <ciclo>" >&2; exit 2; }
V="$(gad_fase_caminho "$PD" "intent/c$C/vereditos.txt")"   # v2.10.1: helper (formato da fase)
if [ ! -f "$V" ]; then
  gad_json_out decide-ciclo "$(jq -cn --arg c "$C" \
    '{ciclo:$c, decisao:"sem_dados", motivo:"vereditos do ciclo ausentes (.intent/.vereditos-c'"$C"'.txt) — gad-verificador não fechou o ciclo"}')" || true
  exit 3
fi

novos=0; novos_ab=0; disp=0; lote_cd=(); lote_ab=()
while IFS='|' read -r id classe veredito categoria; do
  id=$(echo "$id" | tr -d ' '); classe=$(echo "$classe" | tr -d ' ')
  veredito=$(echo "$veredito" | tr -d ' '); categoria=$(echo "$categoria" | tr -d ' ')
  [ -n "$id" ] || continue
  [ "$veredito" = confirmado_irrelevante ] && disp=$((disp+1))
  [ "$veredito" = confirmado ] || continue
  case "$classe" in novo|reaberto) ;; *) continue ;; esac   # reformulado nunca conta como novo
  novos=$((novos+1))
  case "$categoria" in
    C-*|D-*|E-*) lote_cd+=("$id") ;;
    *) novos_ab=$((novos_ab+1)); lote_ab+=("$id") ;;   # A-, B- e vazia (fail-up 1.8)
  esac
done < "$V"

# lanes reprovadas no ciclo (P15) — família da intenção apenas (a convergência tem
# marcador `.reformat-planrev-…` e não passa por aqui)
REPROV=()
while IFS= read -r m; do
  [ -e "$m" ] || continue
  l=$(gad_fase_curinga "$PD" "lanes/reformat-*-c$C.reprovada" "$m")
  case "$l" in planrev-*) continue ;; esac
  REPROV+=("$l")
done < <(gad_fase_glob "$PD" "lanes/reformat-*-c$C.reprovada")
while IFS= read -r st; do
  [ -s "$st" ] || continue
  [ "$(jq -r '.rc_reason // ""' "$st" 2>/dev/null)" = parecer_informe ] || continue
  l=$(gad_fase_curinga "$PD" "intent/c$C/status-*.json" "$st")
  case " ${REPROV[*]-} " in *" $l "*) ;; *) REPROV+=("$l") ;; esac
done < <(gad_fase_glob "$PD" "intent/c$C/status-*.json")
NREP=${#REPROV[@]}

CINT=$(printf '%s' "$C" | tr -cd '0-9'); : "${CINT:=1}"

# S-2 (tarefa 48b) — custo/achado, só usado a partir do ciclo 3 (ver cabeçalho). O script
# não mede custo: quem chama informa (opcional) por GAD_CUSTO_CICLO; ausente = a regra do
# custo não se aplica, só a contagem de novos A/B decide.
CUSTO="${GAD_CUSTO_CICLO:-}"
TETO_CUSTO="${GAD_CUSTO_POR_ACHADO_TETO:-3}"
custo_ok=false; CUSTO_POR_ACHADO=""
case "$CUSTO" in ''|*[!0-9.]*) CUSTO="" ;; esac
if [ -n "$CUSTO" ] && [ "$novos" -gt 0 ]; then
  CUSTO_POR_ACHADO=$(awk -v c="$CUSTO" -v n="$novos" 'BEGIN{printf "%.2f", c/n}')
  custo_ok=$(awk -v c="$CUSTO" -v n="$novos" -v t="$TETO_CUSTO" 'BEGIN{print (c/n<=t)?"true":"false"}')
fi

if [ "$novos" = 0 ] && [ "$NREP" = 0 ]; then
  DEC=para-zerou
  if [ "$disp" -gt 0 ]; then
    MOT="ciclo $C: nenhum achado novo com vínculo ao Goal — convergiu ($disp dispensado(s) registrado(s))"
  else
    MOT="ciclo $C: nenhum achado novo confirmado — convergiu"
  fi
elif [ "$novos" = 0 ] && [ "$CINT" -lt 4 ]; then
  DEC=continua; MOT="ciclo $C: zero achados, mas lane(s) reprovada(s) por parecer_informe (${REPROV[*]}) — zero por silêncio não é convergência"
elif [ "$CINT" -ge 4 ]; then
  DEC=para-teto; MOT="ciclo $C: teto duro de 4 ciclos atingido ($novos novos confirmados no ciclo)"
elif [ "$CINT" -le 1 ]; then
  DEC=continua; MOT="ciclo $C: ciclo 1 nunca é cortado ($novos_ab novo(s) A/B confirmado(s))"
elif [ "$CINT" -eq 2 ]; then
  if [ "$novos_ab" -gt 0 ]; then
    DEC=continua; MOT="ciclo $C: $novos_ab novo(s) A/B confirmado(s) — rendimento justifica o próximo ciclo"
  else
    DEC=para-custo-marginal; MOT="ciclo $C: $novos novos confirmados, todos C/D/E — lote único de correção na saída, sem re-submeter"
  fi
else
  # ciclo >= 3 (S-2, tarefa 48b: aperto do rendimento) — continua só com >=2 novos A/B, ou
  # custo/achado <= teto quando o chamador informou o custo do ciclo.
  if [ "$novos_ab" -ge 2 ]; then
    DEC=continua; MOT="ciclo $C: $novos_ab novos A/B confirmados (>=2, aperto do ciclo 3+) — rendimento justifica o próximo ciclo"
  elif [ "$custo_ok" = true ]; then
    DEC=continua; MOT="ciclo $C: custo/achado \$$CUSTO_POR_ACHADO <= teto \$$TETO_CUSTO (custo do ciclo \$$CUSTO / $novos achado(s)) — rendimento justifica o próximo ciclo"
  elif [ "$novos_ab" = 0 ]; then
    # 0 A/B: desfecho BYTE-IDÊNTICO ao "só C/D/E" do ciclo 2 (lote_ab fica vazio de
    # qualquer jeito) — não é caso novo para quem lê a decisão, então NÃO troca de rótulo.
    # intent.md:624 já sabe rotear `para-custo-marginal`; não precisa aprender um 2º nome
    # para o mesmo comportamento só porque o ciclo é >=3.
    DEC=para-custo-marginal
    MOT="ciclo $C: $novos novos confirmados, todos C/D/E (0 A/B — o aperto do ciclo 3+ também não compraria mais um ciclo) — lote único de correção na saída, sem re-submeter"
  else
    # caso GENUINAMENTE novo do aperto (S-2): 1 A/B confirmado (não chega a 2, nem custo
    # aceitável) que ANTES da 48b teria comprado mais um ciclo sozinho. Ele também vira
    # lote (campo `lote_ab`, separado de `lote_cde`) — mas sob rótulo PRÓPRIO, porque
    # intent.md:624 só roteia `para-custo-marginal → lote_cde`: essa rota precisa aprender
    # `para-rendimento → lote_cde + lote_ab` antes desta versão ir a produção (dependência
    # de sequenciamento com a lane de prompts, não só documentação).
    DEC=para-rendimento
    if [ -n "$CUSTO" ]; then
      MOT="ciclo $C: $novos_ab novo(s) A/B (<2) e custo/achado \$$CUSTO_POR_ACHADO > teto \$$TETO_CUSTO — aperto do ciclo 3+ não compra mais um ciclo; lote único na saída, sem re-submeter"
    else
      MOT="ciclo $C: $novos_ab novo(s) A/B (<2) e custo/achado não informado (GAD_CUSTO_CICLO ausente) — aperto do ciclo 3+ não compra mais um ciclo; lote único na saída, sem re-submeter"
    fi
  fi
fi

LOTE=$(printf '%s\n' ${lote_cd[@]+"${lote_cd[@]}"} | jq -R . | jq -cs 'map(select(length>0))')
if [ "$DEC" = para-rendimento ]; then
  LOTE_AB=$(printf '%s\n' ${lote_ab[@]+"${lote_ab[@]}"} | jq -R . | jq -cs 'map(select(length>0))')
else
  LOTE_AB='[]'
fi
REPJ=$(printf '%s\n' ${REPROV[@]+"${REPROV[@]}"} | jq -R . | jq -cs 'map(select(length>0))')
gad_autoregistro "decide-ciclo.sh" 0 "$DEC ($MOT)" || true
gad_json_out decide-ciclo "$(jq -cn --arg c "$C" --arg d "$DEC" --arg m "$MOT" \
  --argjson n "$novos" --argjson ab "$novos_ab" --argjson di "$disp" --argjson l "$LOTE" --argjson lab "$LOTE_AB" --argjson r "$REPJ" \
  '{ciclo:$c, decisao:$d, motivo:$m, novos_confirmados:$n, novos_ab:$ab, dispensados:$di, lote_cde:$l, lote_ab:$lab, lanes_reprovadas:$r}')"
