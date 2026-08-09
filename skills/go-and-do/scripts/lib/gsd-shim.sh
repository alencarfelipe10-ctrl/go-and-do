#!/usr/bin/env bash
# lib/gsd-shim.sh — biblioteca sourced dos scripts da go-and-do (S.E, reformulação major).
#
# Substitui o shim colável da antiga Sub-rotina E do workflow.md: com a abertura e os
# despachos mecanizados, quem consulta o SDK do GSD são os scripts — a camada 0 não cola
# mais bloco bash nenhum. Fonte única da resolução do gsd-tools + helpers comuns.
#
# Uso (sempre no topo do script, depois do set -euo pipefail):
#   . "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"
#
# O QUE DEFINE
#   gsd_run <args...>       — roda o gsd-tools.cjs resolvido (exit 1 com instrução de
#                             install se não achado em lugar nenhum — portão de entrada).
#   gad_project_root [dir]  — raiz git do projeto alvo (ou o próprio dir se não for git).
#   gad_phase_dir <root> <N>— diretório da fase N em .planning/phases/ (match pelo número
#                             no início do nome, com ou sem prefixo de projeto: "20-...",
#                             "INS-20-...", "RLR-02-..."). Vazio + exit 1 se não achar.
#   gad_json_out <slug> <json> — contrato de saída PC-5: imprime o JSON COMPACTO em 1
#                             linha no stdout E espelha em <root>/.planning/.gad-last-
#                             <slug>.json (o RTK capa stdout em ~50 linhas; o modelo lê
#                             do espelho se a linha vier truncada). Requer jq.
#   gad_runlog <args...>    — chama o run-log.sh do mesmo diretório de scripts (caminho
#                             resolvido por pwd -P — symlink-safe). Nunca falha o caller.
#   GAD_SCRIPTS_DIR         — diretório real (resolvido) de scripts/ da skill.
#
# Resolução do gsd-tools (mesma ordem do shim canônico que os comandos GSD usam):
#   1. <runtime>/gsd-core/bin/gsd-tools.cjs   (runtime = RUNTIME_DIR ou raiz git ou pwd)
#   2. <runtime>/.claude/gsd-core/bin/gsd-tools.cjs
#   3. gsd-tools no PATH
#   4. ~/.claude/gsd-core/bin/gsd-tools.cjs
# A resolução acontece na PRIMEIRA chamada de gsd_run (lazy): sourcear a lib nunca falha,
# então scripts que não consultam o SDK podem usá-la só pelos helpers.

# Guard de duplo-source (scripts podem sourcear uns aos outros no futuro).
[ -n "${_GAD_SHIM_LOADED:-}" ] && return 0 2>/dev/null
_GAD_SHIM_LOADED=1

GAD_SCRIPTS_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

GSD_TOOLS=""
_gsd_resolve() {
  [ -n "$GSD_TOOLS" ] && return 0
  local name="gsd-tools.cjs"
  local root="${RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  if [ -f "$root/gsd-core/bin/$name" ]; then
    GSD_TOOLS="$root/gsd-core/bin/$name"; _GSD_VIA=node
  elif [ -f "$root/.claude/gsd-core/bin/$name" ]; then
    GSD_TOOLS="$root/.claude/gsd-core/bin/$name"; _GSD_VIA=node
  elif command -v gsd-tools >/dev/null 2>&1; then
    GSD_TOOLS="$(command -v gsd-tools)"; _GSD_VIA=direct
  elif [ -f "$HOME/.claude/gsd-core/bin/$name" ]; then
    GSD_TOOLS="$HOME/.claude/gsd-core/bin/$name"; _GSD_VIA=node
  else
    echo "ERRO: gsd-tools.cjs não encontrado (runtime, .claude local, PATH, ~/.claude). Instale: npx -y @opengsd/gsd-core@latest --claude --local" >&2
    return 1
  fi
}

gsd_run() {
  _gsd_resolve || return 1
  if [ "$_GSD_VIA" = direct ]; then "$GSD_TOOLS" "$@"; else node "$GSD_TOOLS" "$@"; fi
}

gad_project_root() {
  local d="${1:-$PWD}"
  git -C "$d" rev-parse --show-toplevel 2>/dev/null || echo "$d"
}

# Fase N no disco sem passar pelo SDK (barato; o retrato completo continua sendo do
# init.phase-op). N é STRING OPACA (PC-9: "1.5"/"2.5"/"999.3" jamais viram int); a
# variante com zero à esquerda cobre nomes tipo RLR-01-fundacao sem aritmética.
gad_phase_dir() {
  local root="$1" n="$2" d pad
  case "$n" in [0-9]) pad="0$n" ;; *) pad="$n" ;; esac
  for d in "$root/.planning/phases/$n"-*   "$root/.planning/phases/$pad"-* \
           "$root/.planning/phases/"*"-$n"-* "$root/.planning/phases/"*"-$pad"-*; do
    [ -d "$d" ] && { echo "$d"; return 0; }
  done
  return 1
}

gad_json_out() {
  local slug="$1" json="$2" root compact
  compact="$(printf '%s' "$json" | jq -c . 2>/dev/null)" || compact=""
  [ -n "$compact" ] || {
    echo "ERRO: gad_json_out recebeu JSON inválido ou vazio ($slug)" >&2; return 1; }
  root="$(gad_project_root)"
  [ -d "$root/.planning" ] && printf '%s\n' "$compact" > "$root/.planning/.gad-last-$slug.json"
  printf '%s\n' "$compact"
}

# Telemetria nunca derruba o caller (mesma política do próprio run-log.sh).
gad_runlog() {
  bash "$GAD_SCRIPTS_DIR/run-log.sh" "$@" || true
}

# Auto-registro G.2-ii: todo script da skill grava o próprio resultado no run-log ao
# rodar DENTRO de uma rodada ativa (descoberta pelo ponteiro PC-3; sem rodada = no-op).
# Uso típico: trap 'gad_autoregistro "<nome>.sh" "$?"' EXIT
gad_autoregistro() { # <nome> <exit> [resumo]
  local root p nn pd rl et
  root="$(gad_project_root)" || return 0
  p="$root/.planning/.gad-rodada-ativa.json"
  [ -f "$p" ] || return 0
  nn=$(jq -r '.nn // empty' "$p" 2>/dev/null); pd=$(jq -r '.phase_dir // empty' "$p" 2>/dev/null)
  rl=$(jq -r '.runlog // empty' "$p" 2>/dev/null)
  [ -n "$nn" ] && [ -n "$pd" ] || return 0
  et=$(grep '"evento":"checkpoint"' "$rl" 2>/dev/null | tail -n1 \
       | sed -n 's/.*"etapa":"\([^"]*\)".*/\1/p'); : "${et:=0 abertura}"
  gad_runlog "$pd" "$nn" script "$et" \
    --kv script="$1" --kv exit="${2:-0}" ${3:+--kv resumo="$3"} >/dev/null
  return 0
}
