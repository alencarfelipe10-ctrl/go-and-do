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
#   gad_fase_formato / gad_fase_inicia / gad_fase_caminho / gad_fase_glob /
#   gad_fase_curinga / gad_fase_legado_rel / gad_fase_lanes_garante / gad_fase_de_base
#   (ver o bloco «PASTA DA FASE» mais abaixo; CLI para prompts: scripts/caminho-fase.sh)

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
# ── TRAVA DE GATE REPROVADO (t59 · FM-F27INS-01ENC) ───────────────────────────
# A trava diz «esta etapa está reprovada AGORA» — é estado da rodada, não evidência. Até a
# v2.10.1 ela morava na pasta da fase (`.gad/gates/<id>.json` / `.gate-fail-<id>.json`), que
# o commita-artefatos commita: cada reprovação ia para o git e o pass deixava uma exclusão
# órfã (F27 INS: 6 de 6). Agora ela mora no estado ignorado da rodada, por fase:
#   <root>/.planning/.gad/gates/<nome da pasta da fase>/<id>.json
# Por 1 release quem LÊ a trava confere também o caminho antigo (rodada aberta pela v2.10.1).
# A evidência de gate (`gates/<id>-evidencia.txt`) NÃO muda: continua na pasta da fase.
#   gad_trava_caminho <pd> <id>   → onde gravar (caminho novo)
#   gad_trava_caminhos <pd> <id>  → novo e antigo, 1 por linha (para ler e para apagar)
_gad_raiz_da_fase() { # <pd> → raiz do projeto: o que vem antes de /.planning/, senão git
  local pd="${1%/}"
  case "$pd" in */.planning/*) printf '%s' "${pd%%/.planning/*}" ;; *) _gad_raiz_de "$pd" ;; esac
}
gad_trava_caminho() { # <pd> <id>
  local pd="${1%/}"
  printf '%s/gates/%s/%s.json' "$(gad_estado_dir "$(_gad_raiz_da_fase "$pd")")" "$(basename -- "$pd")" "${2:-}"
}
gad_trava_caminhos() { # <pd> <id>
  gad_trava_caminho "$1" "$2"; printf '\n'
  gad_fase_caminho "$1" "gates/${2:-}.json"; printf '\n'
}

# ── LISTA DA PASTA SUJA (t59 · L10) ───────────────────────────────────────────
# O fiscal (confere-etapa.sh, bloco FM-06INT) cortava a lista de arquivos da fase fora de
# commit em 350 caracteres no `detalhe`; a lista inteira passa a morar no estado ignorado da
# rodada, por fase e por etapa, para o banner da §6.5 listar tudo:
#   <root>/.planning/.gad/pasta-suja/<nome da pasta da fase>/<etapa>.txt
# (<etapa> = o argumento do fiscal — `5`, `4-code-review`…; espaço e `/` viram `_`).
#   gad_pasta_suja_caminho <pd> <etapa>
gad_pasta_suja_caminho() { # <pd> <etapa>
  local pd="${1%/}" et="${2:-}"
  et="${et// /_}"; et="${et//\//_}"
  printf '%s/pasta-suja/%s/%s.txt' "$(gad_estado_dir "$(_gad_raiz_da_fase "$pd")")" "$(basename -- "$pd")" "$et"
}

# ── EVIDÊNCIA DO UAT CITADA EM CENÁRIO (t59 · FM-F27INS-01UAT) ────────────────
# Fase sem tela prova com a saída de um comando, gravada em texto (`cenario-10.txt`); o modo
# uat do commita-artefatos só reconhecia .pdf/.png e a prova ficou fora do git (F27 INS).
# Fonte única de «qual arquivo de uat-evidencia/ o NN-UAT.md cita» — o commita-artefatos
# (modo uat) e o confere-etapa.sh (classe DURA) leem daqui. Cita = campo `evidencia:` ou
# qualquer menção `uat-evidencia/<nome>` no NN-UAT.md. Só entra arquivo regular, visível,
# que exista DENTRO de <pd>/uat-evidencia/ (o campo pode apontar para fora do git com o
# motivo — workflow-etapa-6.md 6.3b; esse não é cobrado). Qualquer extensão: a citação é a
# seleção explícita, e é ela que limita o volume (risco anotado no FM-F27INS-01UAT).
#   gad_uat_evidencias_citadas <pd> <NN> → caminhos absolutos, 1 por linha, sem repetição
gad_uat_evidencias_citadas() { # <pd> <NN>
  local pd="${1%/}" nn="${2:-}" uat c abs ev
  uat="$pd/$nn-UAT.md"
  [ -f "$uat" ] && [ -d "$pd/uat-evidencia" ] || return 0
  ev="$(cd -P -- "$pd/uat-evidencia" 2>/dev/null && pwd)" || return 0
  { sed -n 's/^[[:space:]]*evidencia:[[:space:]]*//p' "$uat"
    grep -oE 'uat-evidencia/[^][:space:]`"'"'"'()<>|,;]+' "$uat" || true
  } | while IFS= read -r c; do
    c="${c%%[[:space:]]*}"; c="${c#[\`\"\']}"; c="${c%[\`\"\'.:]}"
    [ -n "$c" ] || continue
    case "$c" in /*) abs="$c" ;; *) abs="$pd/$c" ;; esac
    [ -f "$abs" ] || continue
    abs="$(cd -P -- "$(dirname -- "$abs")" 2>/dev/null && pwd)/$(basename -- "$abs")" || continue
    case "$abs" in "$ev"/*) : ;; *) continue ;; esac
    case "$(basename -- "$abs")" in .*) continue ;; esac
    printf '%s\n' "$abs"
  done | LC_ALL=C sort -u
}

gad_rastreado() { # <root> <arquivo>
  git -C "$1" ls-files --error-unmatch -- "$2" >/dev/null 2>&1
}

# ═════════════════════════════════════════════════════════════════════════════
# PASTA DA FASE (tarefa 57, v2.10.1) — uma entrada oculta por fase: `.gad/`
# ═════════════════════════════════════════════════════════════════════════════
# A tabela caminho antigo → novo (INVENTARIO.md §A2) vive SÓ aqui (e no gêmeo Python).
# Todo caminho de evidência é nomeado pelo seu NOME NOVO, relativo a `<phase_dir>/.gad/`:
#   intent/c<K>/<nome>   convergencia/c<K>/<nome>   intent/<nome>   (arquivos da revisão)
#   lanes/<nome>         (ex-pareceres/.<nome>)     fences/<etapa>.ok  gates/<etapa>.json
#   plan-checker/<nome>  pos-ship/<nome>            uat/<nome>
# e o helper devolve o caminho REAL conforme o formato da fase:
#   novo   (existe <phase_dir>/.gad/FORMATO) → <phase_dir>/.gad/<rel>
#   antigo (qualquer outra fase)             → o nome de sempre (`.intent/.vereditos-c1.txt`…)
# Globs passam intactos (`intent/c*/vereditos.txt` ↔ `.intent/.vereditos-c*.txt`).
#
#   gad_fase_formato <pd>            → novo|antigo
#   gad_fase_tem_legado <pd>         → exit 0 se a fase já tem evidência no formato antigo
#   gad_fase_inicia <pd>             → decide o formato de uma fase SEM evidência: cria
#                                      .gad/FORMATO + .gad/lanes/.gitignore; imprime o formato
#   gad_fase_caminho <pd> <rel>      → caminho real (também: <pd> <tipo> <ciclo> <nome>)
#   gad_fase_legado_rel <rel>        → só a tradução para o nome antigo (relativo à fase)
#   gad_fase_glob <pd> <relpadrão>   → arquivos que casam (1 por linha, ordenados)
#   gad_fase_curinga <pd> <relpadrão com 1 *> <arquivo> → o trecho casado pelo `*`
#   gad_fase_lanes_garante <pd>      → (formato novo) .gad/lanes/ + .gitignore da divisão
#                                      commitado × ignorado de sempre (`codex-*`, `*.launch.log`)
# Uma fase NUNCA mistura os dois formatos: quem decide é quem abre a fase (abre-rodada.sh).

GAD_FASE_FORMATO_TEXTO='go-and-do: evidência desta fase no formato 2 (pasta .gad/, v2.10.1). Não apague: sem este arquivo os scripts leem o formato antigo.'

gad_fase_formato() { # <pd>
  [ -f "${1:-}/.gad/FORMATO" ] && printf 'novo' || printf 'antigo'
}

gad_fase_tem_legado() { # <pd> → exit 0 = há evidência no formato antigo
  local pd="${1:-}" f
  [ -d "$pd" ] || return 1
  for f in "$pd/.intent" "$pd/.convergencia" "$pd/.plan-checker"; do [ -e "$f" ] && return 0; done
  compgen -G "$pd/.fence-*.ok" >/dev/null 2>&1 && return 0
  compgen -G "$pd/.gate-fail-*" >/dev/null 2>&1 && return 0
  compgen -G "$pd/.pos-ship-*" >/dev/null 2>&1 && return 0
  compgen -G "$pd/.uat-*" >/dev/null 2>&1 && return 0
  # qualquer dotfile em pareceres/ (e em subpastas: o layout ainda mais velho do oxmuscle,
  # `pareceres/conv/.done-*`, que o confere-rotas.sh já trata como legado)
  [ -d "$pd/pareceres" ] && [ -n "$(find "$pd/pareceres" -name '.*' ! -name '.gitkeep' -print -quit 2>/dev/null)" ] && return 0
  return 1
}

gad_fase_lanes_garante() { # <pd> → só no formato novo; idempotente
  local pd="${1:-}" d
  [ "$(gad_fase_formato "$pd")" = novo ] || return 0
  d="$pd/.gad/lanes"
  mkdir -p "$d" 2>/dev/null || return 1
  [ -f "$d/.gitignore" ] || printf '%s\n' \
    '# go-and-do v2.10.1: a MESMA divisão commitado × ignorado de pareceres/ (regras que os' \
    '# projetos tinham no .gitignore da raiz para pareceres/.codex-* e pareceres/*.launch.log).' \
    'codex-*' '*.launch.log' > "$d/.gitignore" 2>/dev/null || true
  return 0
}

gad_fase_inicia() { # <pd> → imprime novo|antigo; cria o marcador numa fase sem evidência
  local pd="${1:-}"
  [ -n "$pd" ] || return 1
  if [ -f "$pd/.gad/FORMATO" ]; then gad_fase_lanes_garante "$pd"; printf 'novo'; return 0; fi
  if gad_fase_tem_legado "$pd"; then printf 'antigo'; return 0; fi
  mkdir -p "$pd/.gad" 2>/dev/null || { printf 'antigo'; return 0; }
  printf '%s\n' "$GAD_FASE_FORMATO_TEXTO" > "$pd/.gad/FORMATO"
  gad_fase_lanes_garante "$pd"
  printf 'novo'
}

# tradução nome novo → nome antigo (relativo à pasta da fase). Aceita globs.
gad_fase_legado_rel() { # <rel>
  local rel="${1:-}" b r k n base ext
  case "$rel" in
    intent|convergencia) printf '.%s' "$rel"; return 0 ;;
    intent/*|convergencia/*)
      b="${rel%%/*}"; r="${rel#*/}"
      if [[ "$r" =~ ^c([0-9*?\[][^/]*)(/(.*))?$ ]]; then
        k="${BASH_REMATCH[1]}"; n="${BASH_REMATCH[3]}"
        case "$n" in
          '')            printf '.%s' "$b" ;;                               # a pasta do ciclo
          runs)          printf '.%s/runs/c%s' "$b" "$k" ;;
          runs/*)        printf '.%s/runs/c%s/%s' "$b" "$k" "${n#runs/}" ;;
          briefing.md)   printf '.%s/briefing-c%s.md' "$b" "$k" ;;
          'briefing*.md') printf '.%s/briefing-c%s*.md' "$b" "$k" ;;          # principal + devoluções
          briefing-*.md) printf '.%s/briefing-c%s-%s' "$b" "$k" "${n#briefing-}" ;;
          status-*)      printf '.%s/.status-c%s-%s' "$b" "$k" "${n#status-}" ;;
          done-*)        printf '.%s/.done-c%s-%s' "$b" "$k" "${n#done-}" ;;
          ciclo.json)    printf '.%s/.ciclo%s.json' "$b" "$k" ;;
          *) base="${n%%.*}"; ext="${n#"$base"}"
             printf '.%s/.%s-c%s%s' "$b" "$base" "$k" "$ext" ;;
        esac
      else
        case "$r" in
          pre-spec-route.json) printf '.%s/%s' "$b" "$r" ;;
          *)                   printf '.%s/.%s' "$b" "$r" ;;
        esac
      fi ;;
    lanes)          printf 'pareceres' ;;
    lanes/*)        printf 'pareceres/.%s' "${rel#lanes/}" ;;
    fences/*)       printf '.fence-%s' "${rel#fences/}" ;;
    gates/*)        printf '.gate-fail-%s' "${rel#gates/}" ;;
    plan-checker|plan-checker/*) printf '.%s' "$rel" ;;
    pos-ship/*)     printf '.pos-ship-%s' "${rel#pos-ship/}" ;;
    uat/*)          printf '.uat-%s' "${rel#uat/}" ;;
    *)              printf '.gad/%s' "$rel" ;;   # sem equivalente antigo (ex.: FORMATO)
  esac
}

gad_fase_caminho() { # <pd> <rel>  |  <pd> <tipo> <ciclo> <nome>
  local pd="${1%/}" rel
  if [ $# -ge 4 ]; then rel="$2/c$3/$4"; elif [ $# -eq 3 ]; then rel="$2/$3"; else rel="${2:-}"; fi
  if [ "$(gad_fase_formato "$pd")" = novo ]; then printf '%s/.gad/%s' "$pd" "$rel"
  else printf '%s/%s' "$pd" "$(gad_fase_legado_rel "$rel")"; fi
}

gad_fase_glob() { # <pd> <relpadrão> → matches, 1 por linha, ordenados (nada se não houver)
  local pat; pat="$(gad_fase_caminho "$1" "$2")"
  compgen -G "$pat" 2>/dev/null | LC_ALL=C sort -V || true
}

gad_fase_curinga() { # <pd> <relpadrão com um único *> <arquivo> → o trecho do *
  local pat pre suf f
  pat="$(gad_fase_caminho "$1" "$2")"; pre="${pat%%\**}"; suf="${pat#*\*}"
  f="${3#"$pre"}"; printf '%s' "${f%"$suf"}"
}

# phase_dir a partir de um diretório de trabalho da revisão (a base `.intent`/`.gad/intent`,
# `.convergencia`/`.gad/convergencia`, `pareceres`/`.gad/lanes`) — para scripts que recebem
# a base e não a fase (`--status-dir`, confere-rotas.sh).
gad_fase_de_base() { # <dir>
  local d="${1%/}"
  case "$d" in
    */.gad/intent|*/.gad/convergencia|*/.gad/lanes) printf '%s' "${d%/.gad/*}" ;;
    */.intent|*/.convergencia|*/pareceres)         printf '%s' "${d%/*}" ;;
    *) printf '%s' "$d" ;;
  esac
}

# Arquivo pelo NOME NOVO a partir de uma base de trabalho (o que `--status-dir` e o
# confere-rotas.sh recebem). Base reconhecida (`.intent`, `.gad/intent`, `pareceres`…) →
# helper normal pela fase; base qualquer (fixture, pasta avulsa) → nome ANTIGO direto nela.
gad_fase_arq_da_base() { # <base> <rel>
  local b="${1%/}" pd
  pd="$(gad_fase_de_base "$b")"
  if [ "$pd" != "$b" ]; then gad_fase_caminho "$pd" "$2"
  else printf '%s/%s' "$b" "$(basename -- "$(gad_fase_legado_rel "$2")")"; fi
}
