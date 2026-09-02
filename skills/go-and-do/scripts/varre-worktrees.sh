#!/usr/bin/env bash
# varre-worktrees.sh — varredura das cópias (worktrees) de um repositório: quais ficaram
# para trás, o que carregam, e, sob pedido, arquivar o trabalho em patches e remover.
#
# Contexto: o `gsd-tools worktree reap-orphans` só olha worktrees com arquivo `locked`
# e só remove as já incorporadas à base — é passivo por desenho. A cópia da 24.2 do
# inspired (2 commits, 461 linhas, sem `locked`) ficou 11 dias invisível para ele e para
# a go-and-do. Este script é o irmão do `varre-orfaos.sh` para cópias em vez de
# processos, com a mesma disciplina: relata por padrão, ações opt-in, teto por chamada.
#
# Uso: varre-worktrees.sh --projeto <raiz> [--arquivar] [--remover] [--max N]
#
#   Sem flag o script apenas RELATA. Base de comparação = branch atual da raiz.
#
# Classes (uma por cópia):
#   fantasma     registrada no git, diretório ausente
#   com-trabalho ≥ 1 commit à frente da base (pode também estar suja: campo `sujeira`)
#   suja         0 commits à frente, arquivos rastreados modificados sem commit
#   limpa        0 commits à frente, nada modificado
#   Arquivo não rastreado (`??`, o `.venv` da cópia real) não suja a cópia: não entra em
#   patch nem em diff; é contado à parte em `nao_rastreados`.
#
# --arquivar: com-trabalho → `git format-patch <base>..<branch>` em
#   .planning/.gad/worktrees-arquivo/<nome>/; sujeira → `nao-commitado.diff` na mesma
#   pasta; README.md com origem, base, data, contagem e o comando para reaplicar. A pasta
#   é gitignored (`.planning/.gad/`): os patches carregam código do projeto e ficam só
#   no disco do dono. Só arquivos rastreados entram — o format-patch não vê ignorados.
#
# --remover: `git worktree remove --force` + `git branch -D` + `git worktree prune`.
#   limpa sai sem arquivo. com-trabalho/suja exigem `--arquivar` na mesma chamada ou
#   pasta de arquivo já existente cujos patches apliquem (`git am`) num clone temporário
#   partindo do commit-base, e cujo diff passe em `git apply --check` (`git am --check`
#   não existe no git). A raiz
#   nunca é removida; a branch da base nunca é apagada. `--max` (padrão 3) limita quantas
#   remoções por chamada — um loop que remove tudo de uma vez é o pior desfecho.
#
# Saída: JSON de 1 linha {projeto, base, acao, worktrees:[{path, branch, head, classe,
#   commits, sujeira, nao_rastreados, idade_dias, existe, arquivado_em, removida, motivo}],
#   removidas} + espelho .planning/.gad/last-varre-worktrees.json.
# Exit: 0 = rodou (mesmo com cópias pendentes); 2 = uso inválido.
set -u
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

USO="uso: varre-worktrees.sh --projeto <raiz> [--arquivar] [--remover] [--max N]"
ROOT=""; ARQUIVAR=false; REMOVER=false; MAX=3
while [ $# -gt 0 ]; do
  case "$1" in
    --projeto) [ $# -ge 2 ] || { echo "$USO" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    --arquivar) ARQUIVAR=true; shift ;;
    --remover) REMOVER=true; shift ;;
    --max) [ $# -ge 2 ] || { echo "$USO" >&2; exit 2; }; MAX="$2"; shift 2 ;;
    *) echo "$USO" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT" ] || { echo "$USO" >&2; exit 2; }
[ -d "$ROOT" ] || { echo "USO-INVALIDO: '$ROOT' não é um diretório" >&2; exit 2; }
case "$MAX" in ''|*[!0-9]*) echo "USO-INVALIDO: --max exige inteiro" >&2; exit 2 ;; esac
ROOT=$(CDPATH= cd -- "$ROOT" && pwd -P) || exit 2
TOP=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null) || { echo "USO-INVALIDO: '$ROOT' não é repositório git" >&2; exit 2; }
TOP=$(CDPATH= cd -- "$TOP" && pwd -P)
[ "$TOP" = "$ROOT" ] || { echo "USO-INVALIDO: --projeto tem de ser a raiz do repositório ($TOP)" >&2; exit 2; }
# A raiz tem de ser a cópia principal: chamado de dentro de uma worktree, "raiz" e
# "fora da raiz" trocariam de lugar e a principal viraria candidata a remoção.
COMMON=$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)
case "$COMMON" in /*) ;; *) COMMON="$ROOT/$COMMON" ;; esac
COMMON=$(CDPATH= cd -- "$COMMON" && pwd -P)
[ "$COMMON" = "$ROOT/.git" ] || { echo "USO-INVALIDO: '$ROOT' é uma worktree, não a cópia principal" >&2; exit 2; }

BASE=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) || BASE=HEAD
BASE_SHA=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null) || { echo "USO-INVALIDO: raiz sem commit" >&2; exit 2; }
ARQ_RAIZ="$ROOT/.planning/.gad/worktrees-arquivo"
AGORA=$(date +%s)
HOJE=$(date +%Y-%m-%d)

ACAO=relato
if $ARQUIVAR && $REMOVER; then ACAO="arquivar+remover"
elif $ARQUIVAR; then ACAO=arquivar
elif $REMOVER; then ACAO=remover; fi

# ── leitura das cópias ────────────────────────────────────────────────────────
# `worktree list --porcelain`: blocos separados por linha vazia; a primeira linha é
# sempre a cópia principal.
LISTA=$(git -C "$ROOT" worktree list --porcelain 2>/dev/null) || { echo "ERRO: worktree list falhou" >&2; exit 2; }

ITENS=()   # JSON por cópia
N_REMOVIDAS=0

# conferir_arquivo <pasta> <base_commit> → 0 se os patches (e o diff) da pasta aplicam
# num clone temporário partindo do commit-base. É a prova exigida antes de apagar branch.
conferir_arquivo() {
  local pasta="$1" base="$2" tmp rc=0 p
  ls "$pasta"/*.patch >/dev/null 2>&1 || [ -s "$pasta/nao-commitado.diff" ] || return 1
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/gad-wt-check-XXXXXX") || return 1
  if ! git clone -q --no-checkout "$ROOT" "$tmp" 2>/dev/null; then rm -rf "$tmp"; return 1; fi
  git -C "$tmp" checkout -q --detach "$base" 2>/dev/null || { rm -rf "$tmp"; return 1; }
  for p in "$pasta"/*.patch; do
    [ -f "$p" ] || continue
    git -C "$tmp" am -q "$p" >/dev/null 2>&1 || { rc=1; break; }
  done
  if [ "$rc" = 0 ] && [ -s "$pasta/nao-commitado.diff" ]; then
    git -C "$tmp" apply --check "$pasta/nao-commitado.diff" >/dev/null 2>&1 || rc=1
  fi
  rm -rf "$tmp"
  return $rc
}

# arquivar <nome> <sha> <branch> <wt_path> <commits> <sujeira> <base_commit> → imprime a pasta
arquivar() {
  local nome="$1" sha="$2" branch="$3" wt="$4" commits="$5" sujeira="$6" base="$7" pasta n_patch=0
  pasta="$ARQ_RAIZ/$nome"
  mkdir -p "$pasta" || return 1
  rm -f "$pasta"/*.patch "$pasta/nao-commitado.diff"
  if [ "$commits" -gt 0 ]; then
    git -C "$ROOT" format-patch -q "$base..$sha" -o "$pasta" >/dev/null 2>&1 || return 1
    n_patch=$(ls "$pasta"/*.patch 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ "$sujeira" -gt 0 ] && [ -d "$wt" ]; then
    git -C "$wt" diff HEAD > "$pasta/nao-commitado.diff" 2>/dev/null || return 1
  fi
  {
    echo "# Arquivo da cópia \`$nome\`"
    echo
    echo "- origem: \`$wt\`"
    echo "- branch: \`${branch:-"(detached)"}\` · HEAD \`$sha\`"
    echo "- base da comparação: \`$BASE\` (\`$BASE_SHA\`) · commit-base (merge-base): \`$base\`"
    echo "- arquivado em: $HOJE por varre-worktrees.sh"
    echo "- commits arquivados: $n_patch · diff não commitado: $([ -s "$pasta/nao-commitado.diff" ] && echo sim || echo não)"
    echo
    echo "Para reaplicar, parta do commit-base (a base pode ter andado desde então; \`-3\` faz o merge a três vias):"
    echo
    echo '```'
    echo "git checkout -b resgate-$nome $base"
    [ "$n_patch" -gt 0 ] && echo "git am -3 \"$pasta\"/*.patch"
    [ -s "$pasta/nao-commitado.diff" ] && echo "git apply -3 \"$pasta/nao-commitado.diff\""
    echo '```'
  } > "$pasta/README.md"
  printf '%s' "$pasta"
}

processar() {
  local wt="$1" sha="$2" ref="$3" branch existe=true commits=0 sujeira=0 nao_rast=0 idade="null" classe base
  local arquivado_em="" removida=false motivo="" pasta nome
  branch="${ref#refs/heads/}"; [ "$ref" = "$branch" ] && branch=""   # detached ou vazio
  [ -d "$wt" ] || existe=false
  commits=$(git -C "$ROOT" rev-list --count "$BASE_SHA..$sha" 2>/dev/null || echo 0)
  base=$(git -C "$ROOT" merge-base "$BASE_SHA" "$sha" 2>/dev/null || echo "$BASE_SHA")
  if $existe; then
    sujeira=$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d ' ')
    nao_rast=$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null | grep -c '^??' || true)
  fi
  local ct; ct=$(git -C "$ROOT" log -1 --format=%ct "$sha" 2>/dev/null) && [ -n "$ct" ] && idade=$(( (AGORA - ct) / 86400 ))
  if ! $existe; then classe=fantasma
  elif [ "$commits" -gt 0 ]; then classe=com-trabalho
  elif [ "$sujeira" -gt 0 ]; then classe=suja
  else classe=limpa; fi
  nome="${branch:-detached-${sha:0:7}}"; nome="${nome//\//_}"

  # ── arquivar ──
  local precisa_arquivo=false
  { [ "$commits" -gt 0 ] || [ "$sujeira" -gt 0 ]; } && precisa_arquivo=true
  if $ARQUIVAR && $precisa_arquivo; then
    if pasta=$(arquivar "$nome" "$sha" "$branch" "$wt" "$commits" "$sujeira" "$base"); then
      arquivado_em="$pasta"
    else
      motivo="arquivo-falhou"
    fi
  fi

  # ── remover ──
  if $REMOVER && [ -z "$motivo" ]; then
    if [ "$N_REMOVIDAS" -ge "$MAX" ]; then
      motivo="teto-max-$MAX"
    elif $precisa_arquivo && [ -z "$arquivado_em" ]; then
      if [ -d "$ARQ_RAIZ/$nome" ] && conferir_arquivo "$ARQ_RAIZ/$nome" "$base"; then
        arquivado_em="$ARQ_RAIZ/$nome"
      else
        motivo="sem-arquivo-conferido"
      fi
    fi
    if [ -z "$motivo" ] && [ -n "$arquivado_em" ] && $ARQUIVAR && ! conferir_arquivo "$arquivado_em" "$base"; then
      motivo="arquivo-nao-reaplica"
    fi
    if [ -z "$motivo" ]; then
      local ok=true
      if $existe; then
        git -C "$ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || ok=false
      fi
      if $ok; then
        git -C "$ROOT" worktree prune >/dev/null 2>&1
        if [ -n "$branch" ] && [ "$branch" != "$BASE" ]; then
          git -C "$ROOT" branch -D "$branch" >/dev/null 2>&1 || motivo="branch-nao-apagada"
        fi
        removida=true; N_REMOVIDAS=$((N_REMOVIDAS+1))
      else
        motivo="remove-falhou"
      fi
    fi
  fi

  ITENS+=("$(jq -cn --arg p "$wt" --arg b "$branch" --arg h "$sha" --arg c "$classe" \
    --argjson n "$commits" --argjson s "$sujeira" --argjson u "$nao_rast" --argjson i "$idade" \
    --argjson e "$existe" --arg a "$arquivado_em" --argjson r "$removida" --arg m "$motivo" \
    '{path:$p, branch:$b, head:$h, classe:$c, commits:$n, sujeira:$s, nao_rastreados:$u,
      idade_dias:$i, existe:$e, arquivado_em:(if $a=="" then null else $a end),
      removida:$r, motivo:(if $m=="" then null else $m end)}')")
}

wt=""; sha=""; ref=""
flush() {
  [ -n "$wt" ] || return 0
  local real; real=$(CDPATH= cd -- "$wt" 2>/dev/null && pwd -P) || real="$wt"
  [ "$real" = "$ROOT" ] || processar "$wt" "$sha" "$ref"
  wt=""; sha=""; ref=""
}
while IFS= read -r linha; do
  case "$linha" in
    "worktree "*) flush; wt="${linha#worktree }" ;;
    "HEAD "*) sha="${linha#HEAD }" ;;
    "branch "*) ref="${linha#branch }" ;;
    "") flush ;;
  esac
done <<< "$LISTA"
flush

JSON=$(jq -cn --arg root "$ROOT" --arg base "$BASE" --arg acao "$ACAO" --argjson max "$MAX" \
  --argjson rem "$N_REMOVIDAS" \
  --argjson wts "$(printf '%s\n' ${ITENS[@]+"${ITENS[@]}"} | sed '/^$/d' | jq -cs .)" \
  '{projeto:$root, base:$base, acao:$acao, max:$max, worktrees:$wts, removidas:$rem}')
(cd "$ROOT" && gad_json_out "varre-worktrees" "$JSON")
exit 0
