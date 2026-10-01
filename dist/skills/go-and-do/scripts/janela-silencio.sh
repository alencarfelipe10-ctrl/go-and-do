#!/usr/bin/env bash
# janela-silencio.sh — fonte única da verdade sobre a janela de silêncio noturna (23h–07h
# local), item B1 do PLANO-B-rotas.md (consertos F24.4).
#
# Diagnóstico que originou este script: o sensor da janela existia em dois lugares
# calculando a mesma regra por conta própria (pre-despacho.sh:76-79, que só GRAVA o
# resultado sem consumi-lo; notify-telegram.sh:98-101, que só decide o som da mensagem) —
# nenhum dos dois vira ATUAÇÃO sobre um gate duro. Este script não substitui o campo
# `janela_silencio` do checkpoint (informativo, mantido); ele dá ao orquestrador uma
# resposta binária e barata, via exit code, no momento exato da decisão de perguntar ou
# pausar.
#
# Regra (copiada literalmente de pre-despacho.sh:76-79 — não reescreva com outro
# critério; a divergência entre dois cálculos independentes é parte do problema que este
# script resolve): silêncio = true para as horas 23 e 00–06.
#
# Uso: janela-silencio.sh [--phase-dir <dir>]
#   --phase-dir é aceito por simetria com os outros scripts da skill (uniformidade de
#   invocação) mas não é usado no cálculo — a janela é de relógio, não de fase.
#
# Saída: uma linha JSON — {"hora": <0-23>, "silencio": true|false, "acao": "pausa"|"pergunta"}
#
# Exit code é o ponto do script:
#   0 — acao == "pergunta" (fora da janela; pode perguntar normalmente)
#   1 — acao == "pausa"    (dentro da janela; gate duro deve desviar para a Sub-rotina D)
#   2 — uso inválido
#
# Variável de ambiente GAD_HORA_FALSA (0-23): força a hora usada no cálculo, ignorando o
# relógio real. Existe SÓ para tornar este script testável sem esperar a hora certa —
# nunca defina isso fora de um teste.

set -u

while [ $# -gt 0 ]; do
  case "$1" in
    --phase-dir)
      [ $# -ge 2 ] || { echo "ERRO: --phase-dir exige valor" >&2; exit 2; }
      shift 2
      ;;
    *)
      echo "ERRO: uso: janela-silencio.sh [--phase-dir <dir>]" >&2
      exit 2
      ;;
  esac
done

if [ -n "${GAD_HORA_FALSA:-}" ]; then
  case "$GAD_HORA_FALSA" in
    ''|*[!0-9]*) echo "ERRO: GAD_HORA_FALSA deve ser um número 0-23 (veio '$GAD_HORA_FALSA')" >&2; exit 2 ;;
  esac
  hora=$((10#$GAD_HORA_FALSA))
  if [ "$hora" -lt 0 ] || [ "$hora" -gt 23 ]; then
    echo "ERRO: GAD_HORA_FALSA fora do intervalo 0-23 (veio '$GAD_HORA_FALSA')" >&2
    exit 2
  fi
else
  hora=$((10#$(date +%H)))
fi

# ── janela de silêncio (S.I): 23h–07h local — mesma regra de pre-despacho.sh:76-79 ──
# Comparação por VALOR, não por string: pre-despacho.sh casa "$hora" (saída de `date +%H`,
# sempre 2 dígitos, ex. "03") contra os literais 00|01|...|06|23 num `case`. Aqui `hora` já
# foi normalizado para decimal (10#...), então "3" nunca bateria contra o literal "03" —
# por isso o padrão de dois dígitos abaixo, para preservar a mesma régua sem reintroduzir
# esse ponto cego.
hora2=$(printf '%02d' "$hora")
silencio=false
case "$hora2" in 23|00|01|02|03|04|05|06) silencio=true ;; esac

if [ "$silencio" = true ]; then
  acao="pausa"
else
  acao="pergunta"
fi

printf '{"hora": %d, "silencio": %s, "acao": "%s"}\n' "$hora" "$silencio" "$acao"

[ "$acao" = "pergunta" ] && exit 0
exit 1
