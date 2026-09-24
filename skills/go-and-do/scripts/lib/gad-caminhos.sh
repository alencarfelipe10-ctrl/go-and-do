#!/usr/bin/env bash
# lib/gad-caminhos.sh — FONTE ÚNICA dos caminhos de estado da go-and-do (v2.10.1,
# tarefas 56 e 57). Sourced pelo lib/gsd-shim.sh; nenhum script escreve estes caminhos
# à mão. O gêmeo em Python é lib/gad_caminhos.py (mesma tabela, mesmos nomes).
#
# ── RAIZ DA .planning (tarefa 56) ─────────────────────────────────────────────
#   gad_estado_dir <root>        → <root>/.planning/.gad   (estado efêmero da rodada)
#   gad_estado_garante <root>    → cria a pasta + `.gitignore` com `*` (56(d): a pasta
#                                  inteira fica fora do git sem editar o .gitignore do
#                                  projeto; o próprio `.gitignore` também é ignorado)
#   gad_cache_dir <root>         → destino das CÓPIAS contra o corte do RTK (56(f)):
#                                  `git rev-parse --path-format=absolute --git-path gad-cache`
#                                  = `.git/gad-cache` no checkout principal e
#                                  `.git/worktrees/<n>/gad-cache` numa worktree (some junto
#                                  com ela). Fora do git: $XDG_CACHE_HOME/gad/<nome>-<hash>.
#   gad_eh_estado <slug>         → exit 0 se o espelho `last-<slug>.json` é ESTADO (algum
#                                  script, hook ou manifest decide por ele). Lista EXPLÍCITA
#                                  (inventário A1), nunca heurística.
#   gad_espelho_caminho <root> <slug> → onde mora `last-<slug>.json` (estado ou cache)
#   gad_rodada_ativa <root>      → ponteiro da rodada: o novo, ou o legado se só ele existir
#                                  (retomada de rodada aberta pela v2.10.0). Exit 1 = nenhum.
#   gad_rodada_ativa_novo <root> → caminho novo (para gravar)
#   gad_rodada_ativa_legado <root> → caminho antigo (para migrar/apagar)
#   gad_dev_server_estado <root> [json|log] → o novo, ou o legado se só ele existir
#
# ── PASTA DA FASE (tarefa 57) ────────────────────────────────────────────────
#   (ver o bloco «pasta da fase» mais abaixo)

[ -n "${_GAD_CAMINHOS_LOADED:-}" ] && return 0 2>/dev/null
_GAD_CAMINHOS_LOADED=1

# Inventário A1 (INVENTARIO.md, 24/09/2026): os únicos `last-*.json` que alguém lê para
# DECIDIR. pre-despacho → lib/veredito-end.sh · pre-despacho-3 → confere-etapa.sh
# (use_worktrees) · pre-gate → hooks/gad-gate-guard.sh · plan-gate → pre-despacho.sh +
# manifest etapa-2.json (gravado pelo fork, plan-gate.py). Todo outro slug é cópia.
GAD_ESTADO_SLUGS="pre-despacho pre-despacho-3 pre-gate plan-gate"

_gad_raiz_de() { # [dir] → raiz git do dir (ou o próprio dir fora do git)
  local d="${1:-$PWD}"
  git -C "$d" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$d"
}

gad_estado_dir() { printf '%s/.planning/.gad' "${1:-$(_gad_raiz_de)}"; }

gad_estado_garante() { # <root> → cria .planning/.gad/ + .gitignore `*` (idempotente)
  local d; d="$(gad_estado_dir "${1:-}")"
  mkdir -p "$d" 2>/dev/null || return 1
  [ -f "$d/.gitignore" ] || printf '%s\n' \
    '# go-and-do v2.10.1 (56(d)): estado efêmero da rodada — nunca vai para o git.' \
    '# Evidência da fase mora em .planning/phases/*/.gad/ e É commitada.' \
    '*' > "$d/.gitignore" 2>/dev/null || true
  return 0
}

gad_cache_dir() { # <root> → pasta das cópias (nunca aparece em git status)
  local root="${1:-$(_gad_raiz_de)}" d id
  d=$(git -C "$root" rev-parse --path-format=absolute --git-path gad-cache 2>/dev/null) || d=""
  if [ -n "$d" ]; then printf '%s' "$d"; return 0; fi
  # Fallback documentado (sem .git): cache do usuário, por projeto.
  id=$(printf '%s' "$root" | sha1sum 2>/dev/null | cut -c1-12)
  printf '%s/gad/%s-%s' "${XDG_CACHE_HOME:-$HOME/.cache}" "$(basename -- "$root")" "${id:-semhash}"
}

gad_eh_estado() { # <slug>
  case " $GAD_ESTADO_SLUGS " in *" ${1:-} "*) return 0 ;; esac
  return 1
}

gad_espelho_caminho() { # <root> <slug>
  local root="$1" slug="$2"
  if gad_eh_estado "$slug"; then printf '%s/last-%s.json' "$(gad_estado_dir "$root")" "$slug"
  else printf '%s/last-%s.json' "$(gad_cache_dir "$root")" "$slug"; fi
}

gad_rodada_ativa_novo()   { printf '%s/rodada-ativa.json' "$(gad_estado_dir "${1:-}")"; }
gad_rodada_ativa_legado() { printf '%s/.planning/.gad-rodada-ativa.json' "${1:-$(_gad_raiz_de)}"; }

gad_rodada_ativa() { # <root> → caminho existente (novo tem precedência); exit 1 se nenhum
  local root="${1:-$(_gad_raiz_de)}" n l
  n="$(gad_rodada_ativa_novo "$root")"; l="$(gad_rodada_ativa_legado "$root")"
  if [ -f "$n" ]; then printf '%s' "$n"; return 0; fi
  if [ -f "$l" ]; then printf '%s' "$l"; return 0; fi
  return 1
}

gad_dev_server_estado() { # <root> [json|log] → o novo, ou o legado se só ele existir
  local root="${1:-$(_gad_raiz_de)}" ext="${2:-json}" n l
  n="$(gad_estado_dir "$root")/dev-server.$ext"; l="$root/.planning/.gad-dev-server.$ext"
  if [ ! -e "$n" ] && [ -e "$l" ]; then printf '%s' "$l"; else printf '%s' "$n"; fi
}

# Arquivo rastreado pelo git? (a limpeza da 56(c) nunca toca o índice)
gad_rastreado() { # <root> <arquivo>
  git -C "$1" ls-files --error-unmatch -- "$2" >/dev/null 2>&1
}
