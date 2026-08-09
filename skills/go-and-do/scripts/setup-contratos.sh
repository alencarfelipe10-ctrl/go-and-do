#!/usr/bin/env bash
# setup-contratos.sh — retomada determinística da Etapa 1.5 (decisão 1.5-C).
#
# O "tem flag? já existe artefato?" sai da prosa: JSON {ui, ai} com
#   rodar    — flag presente e artefato ausente (o comando roda limpo; é a ausência do
#              arquivo que evita o AskUserQuestion "Existing UI-SPEC" do ui-phase)
#   pular    — flag presente e artefato JÁ existe (não chame o comando)
#   sem-flag — flag ausente (sub-passo não se aplica)
#
# Config NUNCA vence flag em silêncio (decisão do Felipe, sem consulta em runtime): com
# `--ui` presente e `workflow.ui_phase=false` na config do GSD, o script FLIPA a config
# para true e segue (idem --ai × workflow.ai_integration_phase). Flag explícita do dono
# expressa intenção atual; config genérica esquecida não a veta — o comportamento velho
# (comando sai sozinho, fase roda SEM contrato com um skip que ninguém lê) era
# degradação silenciosa, primo do fallback de modelo da F16. O flip entra no JSON
# (`config_corrigida`) e no run-log (linha informativa via auto-registro).
#
# Uso: setup-contratos.sh <phase_dir> <NN> [--ui] [--ai] [--dry-run]
#   --dry-run: decide e imprime, não flipa config nem grava evento (PC-12).
# Saída: JSON 1 linha + espelho PC-5. Exit 0 = decidiu · 2 = uso inválido.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; NN="${2:-}"; UI=false; AI=false; DRY=0
[ -n "$PD" ] && [ -n "$NN" ] || { echo "uso: setup-contratos.sh <phase_dir> <NN> [--ui] [--ai] [--dry-run]" >&2; exit 2; }
shift 2
while [ $# -gt 0 ]; do
  case "$1" in
    --ui) UI=true; shift ;;
    --ai) AI=true; shift ;;
    --dry-run) DRY=1; shift ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done
[ -d "$PD" ] || { echo "ERRO: phase_dir inexistente: $PD" >&2; exit 2; }
ROOT="$(gad_project_root "$PD")"

CORRIGIDA=()
decide() { # <flag_bool> <artefato> <config_key> → rodar|pular|sem-flag
  local flag="$1" art="$2" key="$3"
  if [ "$flag" != true ]; then echo sem-flag; return; fi
  if [ -f "$art" ]; then echo pular; return; fi
  # flag vence config: false → flipa para true, declarado
  local val
  val=$(cd "$ROOT" && gsd_run query config-get "$key" 2>/dev/null | tr -d ' \n\r' || true)
  if [ "$val" = "false" ]; then
    if [ "$DRY" = 0 ]; then
      (cd "$ROOT" && gsd_run query config-set "$key" true >/dev/null 2>&1) \
        && CORRIGIDA+=("${key#workflow.}") \
        || CORRIGIDA+=("${key#workflow.} (flip FALHOU — declare e siga com a flag)")
    else
      CORRIGIDA+=("${key#workflow.} (dry-run: flip não aplicado)")
    fi
  fi
  echo rodar
}

R_UI=$(decide "$UI" "$PD/$NN-UI-SPEC.md" workflow.ui_phase)
R_AI=$(decide "$AI" "$PD/$NN-AI-SPEC.md" workflow.ai_integration_phase)

CJ=$(printf '%s\n' ${CORRIGIDA[@]+"${CORRIGIDA[@]}"} | jq -R . | jq -cs 'map(select(length>0))')
[ "$DRY" = 0 ] && [ "$(jq 'length' <<<"$CJ")" -gt 0 ] \
  && gad_autoregistro "setup-contratos.sh" 0 "config corrigida: $(jq -cr 'join(", ")' <<<"$CJ")"
gad_json_out setup-contratos "$(jq -cn --arg ui "$R_UI" --arg ai "$R_AI" --argjson cc "$CJ" \
  '{ui:$ui, ai:$ai, config_corrigida:$cc}')"
