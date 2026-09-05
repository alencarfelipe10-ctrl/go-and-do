#!/usr/bin/env bash
# correcoes-commit.sh — o commit por ciclo das correções da intenção (E2b, v2.2.0).
#
# POR QUE ESTE SCRIPT EXISTE
# O `.intent/.correcoes-c<C>` que o coordenador escreve é código gerado por LLM num
# turno. A parte git disso — índice temporário, árvore candidata, validação por blobs,
# promoção da ref — é onde um erro corrompe o repositório do usuário. Ela mora AQUI,
# testada, e o script gerado só a chama no fim.
#
# O PROBLEMA REAL (24.3): o commit do ciclo precisa incluir ROADMAP.md/REQUIREMENTS.md
# quando o ciclo resolveu issue R6 ou reconciliou o Goal — mas esses arquivos podem já
# estar SUJOS no worktree por trabalho do usuário anterior ao ciclo. `git commit --only`
# comitaria o arquivo inteiro, levando junto a edição do usuário. Aqui, para um doc já
# sujo, comita-se SÓ o delta do ciclo.
#
# USO
#   correcoes-commit.sh <phase_dir> <C> --inicio \
#       --artefatos <SPEC> <CONTEXT> <INTENT-REVIEW> [--docs <ROADMAP> <REQUIREMENTS>]
#       → grava `git hash-object -w` do estado pré-ciclo de TODOS os alvos e o patch
#         pré-ciclo do usuário (`HEAD..worktree`) em `.intent/.correcoes-c<C>.base.json`
#         + `.intent/.correcoes-c<C>.pre-<n>.patch`. Exit 3 se um alvo estiver
#         staged / unmerged / intent-to-add no índice real (`pre_dirty` é do worktree,
#         não do índice — um alvo staged tornaria a promoção ambígua).
#
#   correcoes-commit.sh <phase_dir> <C> --ids "<id[:caminho]>[,...]" \
#       --artefatos <SPEC> <CONTEXT> <INTENT-REVIEW> [--docs <ROADMAP> <REQUIREMENTS>]
#       → fecha o ciclo: monta a árvore candidata, VALIDA, e só então promove.
#       O `--ids` aceita DUAS formas (C1, conserto de 01/09/2026):
#         · `"c1-01,c1-02"`         → só os ids. Forma CANÔNICA.
#         · `"c1-01:<caminho>,..."` → a parte depois do `:` é o CAMINHO DO ARQUIVO ALVO
#           daquela correção (não um hash — o hash não existe ainda no instante em que
#           o coordenador monta a flag; era por isso que ele saía vazio em 100% das
#           entradas). Use esta forma quando o ciclo tocou MAIS DE UM arquivo, para
#           dizer qual correção mexeu em qual. Um valor que não bate com nenhum caminho
#           comitado é ignorado em silêncio e a entrada cai na forma só-ids.
#
#   correcoes-commit.sh <phase_dir> <C> --vazio
#       → o ciclo não teve correção: grava `.intent/.correcoes-c<C>.vazio` (o marcador
#         explícito que o gate do briefing-build.sh aceita no lugar do `.aplicado`).
#
# PIPELINE (sem `git commit` — ele avançaria HEAD antes da validação)
#   read-tree HEAD (índice temporário)  →  conteúdo candidato por alvo:
#     · alvo limpo antes do ciclo → o worktree inteiro é o delta do ciclo
#     · doc já sujo antes do ciclo → `git merge-file` com base = blob pré-ciclo,
#       ours = HEAD, theirs = worktree ⇒ HEAD + SÓ o delta do ciclo; conflito do
#       merge-file = sobreposição real entre a edição do usuário e a do ciclo → exit 3
#   update-index --cacheinfo  →  write-tree  →  commit-tree -p HEAD_pré  →
#   VALIDAÇÃO INDEPENDENTE (não reusa o merge-file): reaplica o patch pré-ciclo do
#     usuário sobre o blob candidato com `git apply` e exige blob idêntico ao worktree
#     final — comparação de BLOBS, nunca de texto de diff (inserção do ciclo acima do
#     hunk do usuário muda offsets sem mudar conteúdo)  →
#   update-ref HEAD <candidato> <HEAD_pré>  →  update-index --cacheinfo no índice REAL
#     só das entradas comitadas (o commit sob GIT_INDEX_FILE deixaria o `.git/index`
#     com os blobs antigos e o próximo commit reverteria os artefatos).
#   Qualquer falha antes do update-ref: nada promovido, HEAD e `.git/index` byte a byte
#   inalterados, exit 3.
#
# Grava `.intent/.correcoes-c<C>.aplicado` (atômico, tmp + mv), SEMPRE no mesmo nome —
# uma correção pós-releitura (`c<C>b`) sobrescreve IN-PLACE com o commit e os hashes
# novos, e a nova releitura sobrescreve `.releitura-c<C>.json`; o briefing-build.sh lê
# só o nome fixo, então não há ciclo "b" pendurado no gate:
#   {v:1, ciclo, ids, correcoes:[{id,hash}], commit, caminhos:[...],
#    hash_ausente:[...], blobs:[{path, blob_commit, blob_worktree}], mensagem}
# — insumo do `--mudancas`, do R1 (releitura) e do T3.
#
# CAMPO `hash` (C1, 01/09/2026) — quem preenche é ESTE script, porque só ele tem a
# informação. Não é o sha do commit (esse já está em `commit`, seria redundante): é o
# **blob sha do arquivo alvo depois da correção**, o mesmo `blob_commit` que a releitura
# (intent-releitura.md) e o gate do briefing-build.sh conferem. Ordem de preenchimento:
#   1. caminho declarado na forma `id:<caminho>` e presente entre os comitados → o blob dele;
#   2. senão, se o ciclo comitou EXATAMENTE UM caminho → o blob desse caminho;
#   3. senão (0 ou >1 caminhos, sem declaração) → `hash: ""` E o id entra em
#      `hash_ausente[]`, para que a ausência seja auditável em vez de silenciosa.
# `hash_ausente` é gravado SEMPRE (mesmo vazio): a presença da chave é o que distingue
# um `.aplicado` novo de um anterior a este conserto — o leitor usa isso como válvula.
#
# ÍNDICE DE DECISÕES (C6/C3, plano 2, 05/09/2026): o `.planning/DECISIONS-INDEX.md` só era
# regravado no `finalize` do discuss; uma emenda de ciclo no CONTEXT deixava o índice stale
# (inspired: 265.467 B em disco × 267.368 B regenerados). Quando o projeto JÁ TEM o índice e
# um `*-CONTEXT.md` está entre os artefatos, o índice entra como alvo no `--inicio` (senão o
# fecho o recusaria como "alvo novo no meio do ciclo") e, no fecho, é regenerado antes da
# árvore candidata sempre que o blob do CONTEXT mudou. Gerador: `$GAD_DECISIONS_INDEX` ou
# `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gsd-core/bin/nosso/decisions-index.py`; ausente
# (projeto sem o fork) → nada acontece, em silêncio. Índice inexistente → não é criado aqui.
#
# Exit 0 ok · 2 uso inválido · 3 recusa/falha (nada promovido).

set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; C="${2:-}"
[ -n "$PD" ] && [ -n "$C" ] || { echo "uso: correcoes-commit.sh <phase_dir> <C> --inicio|--ids ...|--vazio [--artefatos ...] [--docs ...]" >&2; exit 2; }
shift 2
[ -d "$PD" ] || { echo "ERRO: phase_dir inexistente: $PD" >&2; exit 2; }

MODO=fim; IDS=""; NN=""; ART=(); DOCS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --inicio) MODO=inicio; shift ;;
    --vazio)  MODO=vazio;  shift ;;
    --ids)    IDS="${2:-}"; shift 2 ;;
    --nn)     NN="${2:-}";  shift 2 ;;
    --artefatos) shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do ART+=("$1"); shift; done ;;
    --docs)      shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do DOCS+=("$1"); shift; done ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

IN="$PD/.intent"; mkdir -p "$IN"
BASE="$IN/.correcoes-c$C.base.json"

if [ "$MODO" = vazio ]; then
  printf '{"v":1,"ciclo":"%s","motivo":"ciclo sem correção factual","ts":"%s"}\n' \
    "$C" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$IN/.correcoes-c$C.vazio.tmp" \
    && mv -f "$IN/.correcoes-c$C.vazio.tmp" "$IN/.correcoes-c$C.vazio"
  rm -f "$IN/.correcoes-c$C.aplicado"
  gad_json_out correcoes-commit "$(jq -cn --arg c "$C" \
    --arg m "$IN/.correcoes-c$C.vazio" '{ciclo:$c, modo:"vazio", marcador:$m}')"
  exit 0
fi

ROOT="$(gad_project_root "$PD")"
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "ERRO: $ROOT não é um repositório git" >&2; exit 3; }

# índice de decisões como alvo (ver cabeçalho): só se já existe e há CONTEXT entre os artefatos
IDX_REL=".planning/DECISIONS-INDEX.md"; IDX_GEN="${GAD_DECISIONS_INDEX:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gsd-core/bin/nosso/decisions-index.py}"
IDX_ON=0; CTX_ALVO=""
for a in ${ART[@]+"${ART[@]}"}; do case "$a" in *-CONTEXT.md) CTX_ALVO="$a" ;; esac; done
if [ -n "$CTX_ALVO" ] && [ -f "$ROOT/$IDX_REL" ] && [ -f "$IDX_GEN" ]; then IDX_ON=1; ART+=("$ROOT/$IDX_REL"); fi

ALVOS=(${ART[@]+"${ART[@]}"} ${DOCS[@]+"${DOCS[@]}"})
[ ${#ALVOS[@]} -gt 0 ] || { echo "ERRO: nenhum alvo (--artefatos/--docs)" >&2; exit 2; }

# caminhos relativos à raiz, únicos, existentes
REL=()
for a in "${ALVOS[@]}"; do
  [ -f "$a" ] || { echo "ERRO: alvo inexistente: $a" >&2; exit 3; }
  r=$(python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' "$a" "$ROOT")
  case "$r" in ../*) echo "ERRO: alvo fora da raiz do repo: $a" >&2; exit 3 ;; esac
  case " ${REL[*]:-} " in *" $r "*) continue ;; esac
  REL+=("$r")
done
NDOCS=${#DOCS[@]}
DOCS_REL=()
if [ "$NDOCS" -gt 0 ]; then
  for ((i=${#REL[@]}-NDOCS; i<${#REL[@]}; i++)); do DOCS_REL+=("${REL[$i]}"); done
fi

# ── recusa: alvo staged / unmerged / intent-to-add no índice REAL ────────────
recusa_indice() {
  local r saida
  for r in "${REL[@]}"; do
    saida=$(git -C "$ROOT" diff --cached --name-only -- "$r" 2>/dev/null)
    [ -z "$saida" ] || { echo "RECUSA: $r está STAGED no índice real — a promoção seria ambígua (E2b [v7])" >&2; return 1; }
    saida=$(git -C "$ROOT" ls-files --unmerged -- "$r" 2>/dev/null)
    [ -z "$saida" ] || { echo "RECUSA: $r está UNMERGED" >&2; return 1; }
    # intent-to-add: aparece no índice sem blob válido
    if git -C "$ROOT" ls-files -- "$r" | grep -q .; then
      saida=$(git -C "$ROOT" diff-files --diff-filter=A --name-only -- "$r" 2>/dev/null)
      [ -z "$saida" ] || { echo "RECUSA: $r está intent-to-add" >&2; return 1; }
    fi
  done
  return 0
}
recusa_indice || exit 3

# ─────────────────────────── modo --inicio ──────────────────────────────────
if [ "$MODO" = inicio ]; then
  HEADP=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null) || { echo "ERRO: repo sem HEAD" >&2; exit 3; }
  ENTRADAS=()
  i=0
  for r in "${REL[@]}"; do
    blob=$(git -C "$ROOT" hash-object -w -- "$ROOT/$r") || { echo "ERRO: hash-object falhou em $r" >&2; exit 3; }
    head_blob=$(git -C "$ROOT" rev-parse "HEAD:$r" 2>/dev/null || echo "")
    sujo=false; patch=""
    if [ -n "$head_blob" ] && [ "$head_blob" != "$blob" ]; then
      sujo=true
      patch="$IN/.correcoes-c$C.pre-$i.patch"
      git -C "$ROOT" diff --no-color -- "$r" > "$patch" 2>/dev/null || true
    fi
    ENTRADAS+=("$(jq -cn --arg p "$r" --arg b "$blob" --arg h "$head_blob" \
      --argjson s "$sujo" --arg pt "$patch" \
      '{path:$p, blob_pre:$b, blob_head:$h, sujo_antes:$s, patch:$pt}')")
    i=$((i+1))
  done
  DOCS_JSON=$(printf '%s\n' ${DOCS_REL[@]+"${DOCS_REL[@]}"} | jq -R . | jq -cs 'map(select(length>0))')
  ALVOS_JSON=$(printf '%s\n' "${ENTRADAS[@]}" | jq -cs .)
  jq -cn --arg c "$C" --arg h "$HEADP" --argjson a "$ALVOS_JSON" --argjson d "$DOCS_JSON" \
    '{v:1, ciclo:$c, head_pre:$h, alvos:$a, docs:$d}' > "$BASE.tmp" && mv -f "$BASE.tmp" "$BASE"
  gad_json_out correcoes-commit "$(jq -cn --arg c "$C" --arg b "$BASE" --arg h "$HEADP" \
    --argjson n "${#REL[@]}" '{ciclo:$c, modo:"inicio", base:$b, head_pre:$h, alvos:$n}')"
  exit 0
fi

# ─────────────────────────── modo fim (o commit) ────────────────────────────
[ -f "$BASE" ] || { echo "RECUSA: $BASE ausente — rode --inicio ANTES do ciclo (sem o estado pré-ciclo não dá para separar o delta do usuário do delta do ciclo)" >&2; exit 3; }
[ -n "$IDS" ] || { echo "ERRO: --ids obrigatório no fecho do ciclo" >&2; exit 2; }

HEADP_GRAV=$(jq -r '.head_pre' "$BASE")
HEADP=$(git -C "$ROOT" rev-parse HEAD)
[ "$HEADP" = "$HEADP_GRAV" ] || {
  echo "RECUSA: HEAD mudou desde o --inicio ($HEADP_GRAV → $HEADP) — o ciclo não é mais isolável" >&2; exit 3; }

[ -n "$NN" ] || NN=$(basename "${ART[0]:-${ALVOS[0]}}" | sed -nE 's/^([0-9]+(\.[0-9]+)*)-.*$/\1/p')
[ -n "$NN" ] || NN="?"

T=$(mktemp -d "${TMPDIR:-/tmp}/gad-correcoes-XXXXXX")
trap 'rm -rf "$T"' EXIT
IDX="$T/idx"

falhar() { echo "RECUSA: $*" >&2; exit 3; }

GIT_INDEX_FILE="$IDX" git -C "$ROOT" read-tree HEAD || falhar "read-tree HEAD falhou"

# índice de decisões: regenera ANTES de montar a árvore, se o CONTEXT mudou neste ciclo
if [ "$IDX_ON" = 1 ]; then
  ctx_rel=$(python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' "$CTX_ALVO" "$ROOT")
  ctx_pre=$(jq -r --arg p "$ctx_rel" '.alvos[] | select(.path==$p) | .blob_pre' "$BASE")
  ctx_now=$(git -C "$ROOT" hash-object -- "$ROOT/$ctx_rel" 2>/dev/null || echo "")
  if [ -n "$ctx_pre" ] && [ "$ctx_now" != "$ctx_pre" ]; then
    python3 "$IDX_GEN" "$ROOT/.planning" >/dev/null 2>&1 \
      || echo "aviso: decisions-index.py falhou — índice segue como estava" >&2
  fi
fi

COMITADOS=(); MODOS=(); BLOBS_CAND=()
for r in "${REL[@]}"; do
  ent=$(jq -c --arg p "$r" '.alvos[] | select(.path==$p)' "$BASE")
  [ -n "$ent" ] || falhar "$r não estava no --inicio (alvo novo no meio do ciclo)"
  sujo=$(printf '%s' "$ent" | jq -r '.sujo_antes')
  blob_pre=$(printf '%s' "$ent" | jq -r '.blob_pre')
  patch=$(printf '%s' "$ent" | jq -r '.patch')
  blob_now=$(git -C "$ROOT" hash-object -- "$ROOT/$r") || falhar "hash-object falhou em $r"

  if [ "$blob_now" = "$blob_pre" ] && [ "$sujo" = false ]; then
    # nada mudou no ciclo e o arquivo estava limpo → não entra no commit
    continue
  fi

  if [ "$sujo" = true ]; then
    # doc já sujo antes do ciclo: comita SÓ o delta do ciclo
    if [ "$blob_now" = "$blob_pre" ]; then
      continue   # o ciclo não tocou o doc — a sujeira do usuário fica onde estava
    fi
    git -C "$ROOT" cat-file blob "HEAD:$r" > "$T/ours"     2>/dev/null || falhar "$r não existe no HEAD"
    git -C "$ROOT" cat-file blob "$blob_pre" > "$T/base"   || falhar "blob pré-ciclo de $r sumiu (hash-object -w não persistiu?)"
    cp -f "$ROOT/$r" "$T/theirs"                           || falhar "cópia do worktree de $r falhou"
    if ! git merge-file -q -p "$T/ours" "$T/base" "$T/theirs" > "$T/cand" 2>"$T/mf.err"; then
      falhar "$r: sobreposição real entre a edição pré-ciclo do usuário e a do ciclo (merge-file com conflito) — resolva à mão"
    fi
    cand_blob=$(git -C "$ROOT" hash-object -w -- "$T/cand") || falhar "hash-object do candidato de $r falhou"

    # VALIDAÇÃO INDEPENDENTE do merge-file (E2 [v8]): candidato + patch pré-ciclo do
    # usuário tem de reproduzir, BLOB A BLOB, o worktree final.
    [ -s "$patch" ] || falhar "$r: patch pré-ciclo ausente ($patch) — validação impossível"
    rm -rf "$T/recon.d"
    mkdir -p "$T/recon.d/$(dirname "$r")"
    cp -f "$T/cand" "$T/recon.d/$r"
    if ! (cd "$T/recon.d" && git apply -p1 --whitespace=nowarn "$patch" 2>/dev/null); then
      falhar "$r: o patch pré-ciclo do usuário NÃO reaplica sobre o candidato — o commit levaria (ou perderia) edição do usuário"
    fi
    recon_blob=$(git -C "$ROOT" hash-object -- "$T/recon.d/$r")
    [ "$recon_blob" = "$blob_now" ] || \
      falhar "$r: candidato + patch do usuário ($recon_blob) != worktree final ($blob_now)"
  else
    cand_blob=$(git -C "$ROOT" hash-object -w -- "$ROOT/$r") || falhar "hash-object de $r falhou"
  fi

  m=$(git -C "$ROOT" ls-tree HEAD -- "$r" | awk '{print $1}')
  [ -n "$m" ] || m=100644
  GIT_INDEX_FILE="$IDX" git -C "$ROOT" update-index --add --cacheinfo "$m,$cand_blob,$r" \
    || falhar "update-index falhou em $r"
  COMITADOS+=("$r"); MODOS+=("$m"); BLOBS_CAND+=("$cand_blob")
done

if [ ${#COMITADOS[@]} -eq 0 ]; then
  echo "aviso: ciclo $C nao alterou nenhum alvo — gravando marcador .vazio" >&2
  rm -rf "$T"; trap - EXIT
  exec "$0" "$PD" "$C" --vazio
fi

MSG="docs(fase $NN): correções do ciclo $C — $IDS"
TREE=$(GIT_INDEX_FILE="$IDX" git -C "$ROOT" write-tree) || falhar "write-tree falhou"
CAND=$(git -C "$ROOT" commit-tree "$TREE" -p "$HEADP" -m "$MSG") || falhar "commit-tree falhou"

# validação por blobs na árvore candidata (antes de mover a ref)
for i in "${!COMITADOS[@]}"; do
  b=$(git -C "$ROOT" rev-parse "$CAND:${COMITADOS[$i]}" 2>/dev/null) \
    || falhar "${COMITADOS[$i]} não está na árvore candidata"
  [ "$b" = "${BLOBS_CAND[$i]}" ] || falhar "${COMITADOS[$i]}: blob da árvore ($b) != candidato (${BLOBS_CAND[$i]})"
done

git -C "$ROOT" update-ref HEAD "$CAND" "$HEADP" || falhar "update-ref recusado (HEAD mudou por baixo)"

# índice REAL: só as entradas efetivamente comitadas (senão o próximo commit reverteria)
for i in "${!COMITADOS[@]}"; do
  git -C "$ROOT" update-index --add --cacheinfo "${MODOS[$i]},${BLOBS_CAND[$i]},${COMITADOS[$i]}" \
    || echo "AVISO: update-index do índice real falhou em ${COMITADOS[$i]}" >&2
done

# pós-condição: alvo limpo antes do ciclo não pode continuar sujo
for r in "${COMITADOS[@]}"; do
  sujo=$(jq -r --arg p "$r" '.alvos[] | select(.path==$p) | .sujo_antes' "$BASE")
  if [ "$sujo" = false ] && ! git -C "$ROOT" diff --quiet -- "$r"; then
    echo "AVISO PÓS-COMMIT: $r estava limpo antes do ciclo e continua sujo" >&2
  fi
done

# ── hash por correção (C1) ───────────────────────────────────────────────────
# O mapa caminho → blob candidato é o mesmo que alimentou o `update-index --cacheinfo`
# e que a validação por blobs acabou de conferir contra a árvore candidata: por isso
# usamos BLOBS_CAND (= blob_commit) e NÃO um `hash-object` do worktree — para um doc
# pré-sujo os dois diferem por desenho, e a releitura ancora no blob_commit.
declare -A BLOB_DE=()
for i in "${!COMITADOS[@]}"; do BLOB_DE["${COMITADOS[$i]}"]="${BLOBS_CAND[$i]}"; done
UNICO=""
[ ${#COMITADOS[@]} -eq 1 ] && UNICO="${COMITADOS[0]}"

COR_ENTRADAS=(); AUSENTES=()
IFS=',' read -r -a TOKENS_ID <<< "$IDS"
for tok in ${TOKENS_ID[@]+"${TOKENS_ID[@]}"}; do
  [ -n "$tok" ] || continue
  cid="${tok%%:*}"
  [ -n "$cid" ] || continue
  decl=""
  case "$tok" in *:*) decl="${tok#*:}" ;; esac
  h=""
  if [ -n "$decl" ]; then
    dnorm="$decl"
    # o coordenador pode declarar caminho absoluto ou relativo ao cwd; normaliza para
    # a forma relativa à raiz do repo, que é a chave do mapa
    if [ -e "$decl" ]; then
      dnorm=$(python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' "$decl" "$ROOT" 2>/dev/null) || dnorm="$decl"
    fi
    h="${BLOB_DE[$dnorm]:-}"
    # valor que não bate com caminho comitado nenhum (o antigo placeholder `<hash>`,
    # por exemplo) é ignorado: a entrada cai na regra do caminho único
    [ -n "$h" ] || h=""
  fi
  if [ -z "$h" ] && [ -n "$UNICO" ]; then h="${BLOB_DE[$UNICO]}"; fi
  [ -n "$h" ] || AUSENTES+=("$cid")
  COR_ENTRADAS+=("$(jq -cn --arg i "$cid" --arg h "$h" '{id:$i, hash:$h}')")
done
COR_JSON=$(printf '%s\n' ${COR_ENTRADAS[@]+"${COR_ENTRADAS[@]}"} | jq -cs .)
AUS_JSON=$(printf '%s\n' ${AUSENTES[@]+"${AUSENTES[@]}"} | jq -R . | jq -cs 'map(select(length>0))')
if [ ${#AUSENTES[@]} -gt 0 ]; then
  echo "aviso: ${#AUSENTES[@]} correção(ões) sem hash (ciclo comitou ${#COMITADOS[@]} caminhos e o id não declarou qual): ${AUSENTES[*]} — declaradas em hash_ausente[]" >&2
fi
IDS_JSON=$(printf '%s' "$IDS" | tr ',' '\n' | jq -R 'select(length>0) | split(":")[0]' | jq -cs .)
CAM_JSON=$(printf '%s\n' "${COMITADOS[@]}" | jq -R . | jq -cs .)
# Dois hashes por caminho comitado (resolução do conflito E2 x R1):
#   blob_commit    = o que a releitura relê (o commit do ciclo)
#   blob_worktree  = o worktree logo APÓS o commit — para um doc pré-sujo os dois
#                    DIFEREM por desenho (o patch do usuário ficou no worktree). O gate
#                    R1 compara releitura contra blob_commit e worktree contra
#                    blob_worktree; sem isso um ROADMAP legitimamente sujo acusaria
#                    "editado após a releitura" sem edição alguma.
BLOBS=()
for r in "${COMITADOS[@]}"; do
  bc=$(git -C "$ROOT" rev-parse "$CAND:$r")
  bw=$(git -C "$ROOT" hash-object -- "$ROOT/$r")
  BLOBS+=("$(jq -cn --arg p "$r" --arg c "$bc" --arg w "$bw" \
    '{path:$p, blob_commit:$c, blob_worktree:$w}')")
done
BLOBS_JSON=$(printf '%s\n' "${BLOBS[@]}" | jq -cs .)
APL="$IN/.correcoes-c$C.aplicado"
jq -cn --arg c "$C" --arg commit "$CAND" --arg msg "$MSG" \
  --argjson ids "$IDS_JSON" --argjson cor "$COR_JSON" --argjson cam "$CAM_JSON" \
  --argjson bl "$BLOBS_JSON" --argjson aus "$AUS_JSON" \
  '{v:1, ciclo:$c, ids:$ids, correcoes:$cor, commit:$commit, caminhos:$cam,
    hash_ausente:$aus, blobs:$bl, mensagem:$msg}' \
  > "$APL.tmp" && mv -f "$APL.tmp" "$APL"
rm -f "$IN/.correcoes-c$C.vazio"

gad_autoregistro "correcoes-commit.sh" 0 "c$C commit $CAND (${#COMITADOS[@]} caminhos)" || true
gad_json_out correcoes-commit "$(jq -cn --arg c "$C" --arg commit "$CAND" --arg a "$APL" \
  --argjson cam "$CAM_JSON" '{ciclo:$c, modo:"fim", commit:$commit, caminhos:$cam, aplicado:$a}')"
