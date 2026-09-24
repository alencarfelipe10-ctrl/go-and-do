#!/usr/bin/env bash
# lib/veredito-end.sh — FM-04UAT (lado script, item 5 do relatório R2/B1): deriva o
# veredito do `end` id 6 do confere-etapa.sh. Fatorado do bloco inline de confere-etapa.sh
# (F4 RLR, rodada 3) para poder ser testado sem montar uma bancada de PASS real da etapa 6
# inteira (STATE.md, resumo, worktrees, git_remote — o que o R2 tentou e não terminou por
# tempo). confere-etapa.sh sourcea este arquivo; test-confere-etapa.sh sourcea DIRETO, sem
# passar pelo script inteiro, para o teste de integração do veredito=handback.
#
# A rota (pausa/handback/ship) é decidida no DESPACHO da etapa 6 por `pre-despacho.sh 6`
# (6.1) e sobrevive em `<root>/.planning/.gad/last-pre-despacho.json` — lida aqui em vez
# de recalculada, para não ter um 2º lugar que decide a rota.
[ -n "${_GAD_VEREDITO_END_LOADED:-}" ] && return 0 2>/dev/null
_GAD_VEREDITO_END_LOADED=1
# Caminho do espelho de ESTADO pelo helper único (v2.10.1). Sourceado direto pelo teste,
# sem o shim — por isso carrega o helper aqui mesmo (guard de duplo-source lá dentro).
. "$(dirname -- "${BASH_SOURCE[0]}")/gad-caminhos.sh"

gad_veredito_end() { # <root> <runlog_etapa> → stdout: "pass" | "handback"
  local root="${1:-}" etapa="${2%% *}" pd6
  if [ "$etapa" = "6" ] && [ -n "$root" ]; then
    pd6="$(gad_espelho_caminho "$root" pre-despacho)"
    if [ -f "$pd6" ] \
       && [ "$(jq -r '.etapa // ""' "$pd6" 2>/dev/null)" = "6" ] \
       && [ "$(jq -r '.paralelismo.rota // .rota // ""' "$pd6" 2>/dev/null)" = "handback" ]; then
      printf 'handback'
      return 0
    fi
  fi
  printf 'pass'
}
