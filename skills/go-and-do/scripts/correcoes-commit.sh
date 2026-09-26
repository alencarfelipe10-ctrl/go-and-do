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
#   correcoes-commit.sh <phase_dir> <C> --ids "<id[:caminho]>[,...]" [--adiados "<id>,..."] \
#       --artefatos <SPEC> <CONTEXT> <INTENT-REVIEW> [--docs <ROADMAP> <REQUIREMENTS>]
#       → fecha o ciclo: monta a árvore candidata, VALIDA, e só então promove.
#       O `--ids` aceita DUAS formas (C1, conserto de 01/09/2026):
#         · `"c1-01,c1-02"`         → só os ids. Forma CANÔNICA.
#         · `"c1-01:<caminho>,..."` → a parte depois do `:` é o CAMINHO DO ARQUIVO ALVO
#           daquela correção (não um hash — o hash não existe ainda no instante em que
#           o coordenador monta a flag; era por isso que ele saía vazio em 100% das
#           entradas). Use esta forma quando o ciclo tocou MAIS DE UM arquivo, para
#           dizer qual correção mexeu em qual. Um valor que não bate com nenhum caminho
#           comitado é RECUSA desde a F4 RLR (FM-05INT): era ignorado em silêncio e foi
#           assim que 18 ids do ciclo 1 saíram selados contra o arquivo errado.
#
#   TRAVA DE IDS (FM-04INT + FJ-05INT, F4 RLR) — antes de tocar o repositório, o fecho
#   confere `--ids`/`--adiados` contra `.intent/.vereditos-c<C>.txt`: id inexistente e id
#   DISPENSADO (`confirmado_irrelevante`) são recusados, e todo `confirmado` tem de sair
#   do ciclo corrigido (`--ids`) ou adiado (`--adiados`). Ids da releitura do mesmo ciclo
#   (`c<C>b-NN`) são aceitos por desenho. Ciclo sem arquivo de vereditos (o c0) → trava
#   inativa, declarada no stderr. Nenhuma recusa grava `.correcoes-c<C>.vazio` (FJ-04INT).
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
# Grava `.intent/.correcoes-c<C>.aplicado` (atômico, tmp + mv), SEMPRE no mesmo nome.
# A releitura seguinte (FM-F4RLR-10INT) já NÃO sobrescreve mais o `.releitura-c<C>.json`
# — grava `.releitura-c<C>b.json`, arquivo próprio; o `briefing-build.sh` (`caminho_releitura`)
# lê a rodada mais recente do ciclo, não mais um nome fixo só:
#   {v:1, ciclo, ids, correcoes:[{id,hash}], commit, caminhos:[...],
#    hash_ausente:[...], blobs:[{path, blob_commit, blob_worktree}], mensagem,
#    adiados:[...], commits:[...], rodadas:[{rodada, commit, ids, adiados, caminhos, blobs}]}
# — insumo do `--mudancas`, do R1 (releitura) e do T3.
#
# RODADAS DO MESMO CICLO (FM-F27INS-04INT + FJ-F27INS-03INT, tarefa 59 b2/b3). Uma correção
# pós-releitura (`c<C>b`, `c<C>c`…) é um SEGUNDO commit do mesmo ciclo. Antes, ela
# sobrescrevia o `.aplicado` inteiro — na F27 INS o commit 5d270b2 (c1-01) sumiu do registro,
# só o f2f67b4 ficou — e exigia que o coordenador repetisse `--ids` com TODOS os ids do ciclo
# (ele passou só o novo e levou a recusa «confirmado sem destino»). Agora:
#   · o `.aplicado` anterior do ciclo é HERDADO quando confere com o git: o arquivo é do mesmo
#     ciclo, todo commit dele existe e é ancestral do HEAD, e o `blob_commit` de cada caminho
#     é o blob daquele caminho no commit da rodada que o gravou. Não confere → nada é
#     herdado (aviso no stderr com o motivo) e vale o comportamento antigo: `--ids` completo;
#   · com herança, `--ids` leva SÓ os ids novos da rodada. Id repetido de rodada anterior é
#     redundante: fica com a entrada herdada (não é re-selado contra o arquivo da rodada nova
#     nem conferido pelo FM-05INT) — o prompt antigo mandava repetir e isso não pode quebrar.
#     Rodada sem nenhum id novo, ou sem nenhuma alteração, é RECUSA (exit 3) e o `.aplicado`
#     anterior fica intacto — antes, a rodada sem alteração caía no `--vazio` e APAGAVA o
#     registro das rodadas que já estavam no git;
#   · a trava de ids (3) confere o ciclo inteiro: ids e adiados herdados + os da rodada;
#   · UNIÃO de todas as rodadas: `ids`, `correcoes`, `hash_ausente`, `adiados` e `blobs`
#     (por caminho, a rodada mais nova vence); `commits` = todos os commits do ciclo, em ordem;
#     `rodadas` = o detalhe de cada uma (só o que ELA trouxe);
#   · SÓ A RODADA VIGENTE: `commit`, `caminhos`, `mensagem` — é contra eles que a releitura
#     da rodada é amarrada (`briefing-build.sh`: commit igual, conjunto de caminhos igual) e o
#     `confere-reconciliacao.sh --ordem` compara a data.
#   `.aplicado` anterior a este conserto (sem `rodadas`) vira a 1ª rodada sintetizada do
#   `commit`/`ids`/`caminhos`/`blobs` dele; os adiados saem da linha `adiados:` da `mensagem`.
#
# MENSAGEM DO COMMIT (FM-F27INS-04INT): assunto `docs(fase NN): correções do ciclo C — <ids>`
# (os ids NOVOS da rodada, sem o `:caminho`) — a forma que a skill documenta e que o
# `confere-reconciliacao.sh` procura com `--grep` (não mude o prefixo); o corpo leva
# `caminhos:` (a lista do diff, a de antes no assunto), `ids:`/`adiados:` como digitados e,
# numa rodada ≥ 2, `rodada:` + os ids herdados.
#
# CAMPO `hash` (C1, 01/09/2026) — quem preenche é ESTE script, porque só ele tem a
# informação. Não é o sha do commit (esse já está em `commit`, seria redundante): é o
# **blob sha do arquivo alvo depois da correção**, o mesmo `blob_commit` que a releitura
# (intent-releitura.md) e o gate do briefing-build.sh conferem. Ordem de preenchimento:
#   1. caminho declarado na forma `id:<caminho>` e presente entre os comitados → o blob dele;
#   2. senão, se o ciclo comitou EXATAMENTE UM caminho de correção → o blob desse caminho.
#      O `.planning/DECISIONS-INDEX.md` NÃO conta aqui: é índice regenerado por script (M5,
#      F24.5 — contá-lo como 2º caminho apagou o hash de 8 das 15 correções do ciclo 0);
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
[ -n "$PD" ] && [ -n "$C" ] || { echo "uso: correcoes-commit.sh <phase_dir> <C> --inicio|--ids ...|--vazio [--adiados ...] [--artefatos ...] [--docs ...]" >&2; exit 2; }
shift 2
[ -d "$PD" ] || { echo "ERRO: phase_dir inexistente: $PD" >&2; exit 2; }

MODO=fim; IDS=""; ADIADOS=""; NN=""; ART=(); DOCS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --inicio) MODO=inicio; shift ;;
    --vazio)  MODO=vazio;  shift ;;
    --ids)    IDS="${2:-}"; shift 2 ;;
    --adiados) ADIADOS="${2:-}"; shift 2 ;;
    --nn)     NN="${2:-}";  shift 2 ;;
    --artefatos) shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do ART+=("$1"); shift; done ;;
    --docs)      shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do DOCS+=("$1"); shift; done ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

# v2.10.1 (57): arquivos do ciclo pelo helper (formato da fase): `.gad/intent/c<C>/…` no
# novo, `.intent/.<x>-c<C>…` no antigo.
CI() { gad_fase_caminho "$PD" "intent/c$C/$1"; }
mkdir -p "$(dirname -- "$(CI correcoes.base.json)")"
BASE="$(CI correcoes.base.json)"

# ── herança do `.aplicado` anterior do MESMO ciclo (t59 b2/b3; ver cabeçalho) ──────
# aplicado_confere <arquivo> <root> → exit 0 se o arquivo é do ciclo $C e confere com o git
# (todo commit existe e é ancestral do HEAD; cada blob_commit bate com o blob do caminho no
# commit da rodada que o gravou). Senão, exit 1 e o motivo no stdout.
aplicado_confere() {
  local f="$1" root="$2" ciclo sha p b real
  jq -e 'type=="object"' "$f" >/dev/null 2>&1 || { echo "JSON ilegível"; return 1; }
  ciclo=$(jq -r '.ciclo // empty | tostring' "$f")
  [ "$ciclo" = "$C" ] || { echo "arquivo do ciclo «$ciclo», não do $C"; return 1; }
  [ -n "$(jq -r '.commit // empty' "$f")" ] || { echo "sem commit"; return 1; }
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    git -C "$root" cat-file -e "$sha^{commit}" 2>/dev/null || { echo "commit $sha não existe no repositório"; return 1; }
    git -C "$root" merge-base --is-ancestor "$sha" HEAD 2>/dev/null || { echo "commit $sha não é ancestral do HEAD"; return 1; }
  done < <(jq -r '((.rodadas // []) | map(.commit)) + [.commit] | unique | .[]' "$f")
  while IFS=$'\t' read -r sha p b; do
    [ -n "$p" ] && [ -n "$b" ] || continue
    real=$(git -C "$root" rev-parse "$sha:$p" 2>/dev/null) || real=""
    [ "$real" = "$b" ] || { echo "blob de $p no commit $sha ($real) != blob_commit gravado ($b)"; return 1; }
  done < <(jq -r 'if (.rodadas // [] | length) > 0
                  then .rodadas[] | .commit as $c | (.blobs // [])[] | [$c, .path, .blob_commit] | @tsv
                  else .commit as $c | (.blobs // [])[] | [$c, .path, .blob_commit] | @tsv end' "$f")
  # com `rodadas`, o topo tem de ser a união delas: `commit` = o da última rodada e `blobs`
  # = o selo mais novo de cada caminho (quem edita um lado só é pego aqui)
  jq -e 'if (.rodadas // [] | length) == 0 then true else
           (.commit == .rodadas[-1].commit)
           and ((reduce ((.rodadas[].blobs // [])[]) as $b ({}; .[$b.path] = $b.blob_commit))
                == (reduce ((.blobs // [])[]) as $b ({}; .[$b.path] = $b.blob_commit)))
         end' "$f" >/dev/null 2>&1 \
    || { echo "topo (commit/blobs) incoerente com as rodadas"; return 1; }
  return 0
}

if [ "$MODO" = vazio ]; then
  # `--vazio` num ciclo que JÁ tem rodada comitada apagaria o registro dela: recusa.
  if [ -f "$(CI correcoes.aplicado)" ] \
     && aplicado_confere "$(CI correcoes.aplicado)" "$(gad_project_root "$PD")" >/dev/null; then
    echo "RECUSA: o ciclo $C já tem correção comitada ($(jq -r .commit "$(CI correcoes.aplicado)" | cut -c1-8)) — «--vazio» apagaria o registro dela. Rodada sem alteração não se registra." >&2
    exit 3
  fi
  printf '{"v":1,"ciclo":"%s","motivo":"ciclo sem correção factual","ts":"%s"}\n' \
    "$C" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$(CI correcoes.vazio.tmp)" \
    && mv -f "$(CI correcoes.vazio.tmp)" "$(CI correcoes.vazio)"
  rm -f "$(CI correcoes.aplicado)"
  gad_json_out correcoes-commit "$(jq -cn --arg c "$C" \
    --arg m "$(CI correcoes.vazio)" '{ciclo:$c, modo:"vazio", marcador:$m}')"
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
REL=(); AUSENTES_INICIO=()
for a in "${ALVOS[@]}"; do
  if [ ! -f "$a" ]; then
    # M4 (F24.5): no `--inicio` o INTENT-REVIEW do ciclo ainda não existe — ele nasce DENTRO
    # do ciclo. Alvo ausente aqui é «arquivo novo», não erro: `blob_pre` fica vazio e o fecho
    # o trata como delta inteiro do ciclo. Nos modos `--ids`/`--vazio` a ausência segue erro.
    if [ "$MODO" = inicio ]; then AUSENTES_INICIO+=("$a"); continue; fi
    echo "ERRO: alvo inexistente: $a" >&2; exit 3
  fi
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
  # FM-05INT (F4 RLR): `.base.json` já existente com o MESMO head_pre é o estado
  # pré-ciclo verdadeiro — um segundo `--inicio` no mesmo HEAD (re-selo) regravaria
  # `blob_pre` com o arquivo JÁ EMENDADO e o delta do ciclo sumiria. Preserva-se.
  # HEAD diferente = passada nova de verdade (a `c<C>b` roda depois do commit do ciclo):
  # aí o estado pré-passada é outro e a base é refeita.
  if [ -f "$BASE" ] && [ "$(jq -r '.head_pre // empty' "$BASE" 2>/dev/null)" = "$HEADP" ]; then
    echo "nota: $BASE já existe no mesmo HEAD — base pré-ciclo preservada (re-selo não sobrescreve)" >&2
    gad_json_out correcoes-commit "$(jq -cn --arg c "$C" --arg b "$BASE" --arg h "$HEADP" \
      '{ciclo:$c, modo:"inicio", base:$b, head_pre:$h, preservada:true}')"
    exit 0
  fi
  ENTRADAS=()
  i=0
  for r in "${REL[@]}"; do
    blob=$(git -C "$ROOT" hash-object -w -- "$ROOT/$r") || { echo "ERRO: hash-object falhou em $r" >&2; exit 3; }
    head_blob=$(git -C "$ROOT" rev-parse "HEAD:$r" 2>/dev/null || echo "")
    sujo=false; patch=""
    if [ -n "$head_blob" ] && [ "$head_blob" != "$blob" ]; then
      sujo=true
      patch="$(CI correcoes.pre-$i.patch)"
      git -C "$ROOT" diff --no-color -- "$r" > "$patch" 2>/dev/null || true
    fi
    ENTRADAS+=("$(jq -cn --arg p "$r" --arg b "$blob" --arg h "$head_blob" \
      --argjson s "$sujo" --arg pt "$patch" \
      '{path:$p, blob_pre:$b, blob_head:$h, sujo_antes:$s, patch:$pt}')")
    i=$((i+1))
  done
  for a in ${AUSENTES_INICIO[@]+"${AUSENTES_INICIO[@]}"}; do
    r=$(python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' "$a" "$ROOT")
    case " ${REL[*]:-} " in *" $r "*) continue ;; esac
    ENTRADAS+=("$(jq -cn --arg p "$r" \
      '{path:$p, blob_pre:"", blob_head:"", sujo_antes:false, patch:"", ausente_no_inicio:true}')")
    REL+=("$r")
  done
  DOCS_JSON=$(printf '%s\n' ${DOCS_REL[@]+"${DOCS_REL[@]}"} | jq -R . | jq -cs 'map(select(length>0))')
  ALVOS_JSON=$(printf '%s\n' ${ENTRADAS[@]+"${ENTRADAS[@]}"} | jq -cs 'map(select(. != null))')
  jq -cn --arg c "$C" --arg h "$HEADP" --argjson a "$ALVOS_JSON" --argjson d "$DOCS_JSON" \
    '{v:1, ciclo:$c, head_pre:$h, alvos:$a, docs:$d}' > "$BASE.tmp" && mv -f "$BASE.tmp" "$BASE"
  gad_json_out correcoes-commit "$(jq -cn --arg c "$C" --arg b "$BASE" --arg h "$HEADP" \
    --argjson n "${#REL[@]}" '{ciclo:$c, modo:"inicio", base:$b, head_pre:$h, alvos:$n}')"
  exit 0
fi

# ─────────────────────────── modo fim (o commit) ────────────────────────────
[ -f "$BASE" ] || { echo "RECUSA: $BASE ausente — rode --inicio ANTES do ciclo (sem o estado pré-ciclo não dá para separar o delta do usuário do delta do ciclo)" >&2; exit 3; }
[ -n "$IDS" ] || { echo "ERRO: --ids obrigatório no fecho do ciclo" >&2; exit 2; }

APL="$(CI correcoes.aplicado)"
lista_ids() { printf '%s' "${1:-}" | tr ',' '\n' | sed 's/:.*$//; s/^[ \t]*//; s/[ \t]*$//' | grep -v '^$' || true; }
HER_ON=0; HER_IDS=""; HER_ADI=""; HER_N=0
if [ -f "$APL" ]; then
  if motivo=$(aplicado_confere "$APL" "$ROOT"); then
    HER_ON=1
    HER_IDS=$(jq -r '(.ids // [])[]' "$APL")
    HER_ADI=$(jq -r 'if has("adiados") then (.adiados // [])[]
                     else ((.mensagem // "") | split("\n") | map(select(startswith("adiados: ")))
                           | (.[0] // "adiados: ") | ltrimstr("adiados: ") | split(",")
                           | map(sub(":.*$";"") | gsub("^\\s+|\\s+$";"")) | map(select(length>0)) | .[]) end' "$APL")
    HER_N=$(jq -r 'if (.rodadas // [] | length) > 0 then (.rodadas | length) else 1 end' "$APL")
    echo "nota: rodada $((HER_N+1)) do ciclo $C — herdados do .aplicado (conferido contra o git): ids $(printf '%s' "$HER_IDS" | paste -sd, -)${HER_ADI:+; adiados $(printf '%s' "$HER_ADI" | paste -sd, -)}" >&2
  else
    echo "aviso: $APL existe mas NÃO confere com o git ($motivo) — nada herdado; --ids tem de trazer todos os ids do ciclo" >&2
  fi
fi
# tokens desta rodada: id já herdado é redundante (fica a entrada da rodada que o gravou)
IDS_NOVOS=""; REPETIDOS=()
IFS=',' read -r -a _TOK_ALL <<< "$IDS"
for tok in ${_TOK_ALL[@]+"${_TOK_ALL[@]}"}; do
  _cid=$(printf '%s' "${tok%%:*}" | sed 's/^[ \t]*//; s/[ \t]*$//')
  [ -n "$_cid" ] || continue
  if [ "$HER_ON" = 1 ] && printf '%s\n' "$HER_IDS" | grep -qxF "$_cid"; then
    REPETIDOS+=("$_cid"); continue
  fi
  IDS_NOVOS="${IDS_NOVOS:+$IDS_NOVOS,}$tok"
done
[ ${#REPETIDOS[@]} -eq 0 ] || echo "nota: id(s) de rodada anterior repetido(s) em --ids — ficam com a entrada herdada: ${REPETIDOS[*]}" >&2
if [ -z "$IDS_NOVOS" ]; then
  echo "RECUSA: --ids não traz nenhum id novo nesta rodada do ciclo $C (todos já estão no .aplicado: ${REPETIDOS[*]})." >&2
  echo "        a emenda de uma rodada pós-releitura leva id próprio (c${C}b-NN) ou o id do achado que ela fecha." >&2
  exit 3
fi
ADI_NOVOS=$(lista_ids "$ADIADOS" | { if [ "$HER_ON" = 1 ]; then grep -vxF -f <(printf '%s\n' "$HER_ADI" | grep -v '^$' || echo '__nenhum__') || true; else cat; fi; })

# ── trava de ids (FM-04INT + FJ-05INT + FJ-04INT, auditoria F4 RLR) ──────────
# A reconciliação (confere-reconciliacao.sh) só acusa DEPOIS do commit: id inventado,
# achado dispensado promovido e confirmado sem destino já estavam no repositório quando
# o gate falava. As três travas abaixo conferem o MESMO que ele, e recusam ANTES de o
# script tocar o repositório — nada fica pela metade e nenhum marcador `.vazio` nasce de
# um aborto por erro (a recusa sai aqui, muito antes do fallback de ciclo sem alteração).
# Fonte dos vereditos: `.intent/.vereditos-c<C>.txt`, `id | classe | veredito | categoria`
# (mesma leitura do confere-reconciliacao.sh). Ciclo sem arquivo de vereditos (o c0, que
# não passa pela consultoria) → trava inativa, declarada no stderr, nunca silenciosa.
VERED="$(CI vereditos.txt)"
if [ -f "$VERED" ]; then
  declare -A VER_DE=()
  VALIDOS=()
  while IFS= read -r linha; do
    case "$linha" in ''|'#'*) continue ;; esac
    _id=$(printf '%s' "$linha"  | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$1); print $1}')
    _ver=$(printf '%s' "$linha" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')
    [ -n "$_id" ] || continue
    VER_DE["$_id"]="$_ver"
    case "$_ver" in confirmado_irrelevante) ;; *) VALIDOS+=("$_id") ;; esac
  done < "$VERED"

  # lista plana dos ids informados (sem o `:caminho`) e dos adiados
  IDS_PLANOS=$(lista_ids "$IDS")
  ADI_PLANOS=$(lista_ids "$ADIADOS")

  # (1) id inexistente · (2) id dispensado — as duas conferências sobre --ids e --adiados
  for _lote in ids adiados; do
    case "$_lote" in ids) _conj="$IDS_PLANOS" ;; *) _conj="$ADI_PLANOS" ;; esac
    while IFS= read -r cid; do
      [ -n "$cid" ] || continue
      # correção nascida da RELEITURA do mesmo ciclo (`c<C>b-NN`): id legítimo que não
      # existe no arquivo de vereditos por desenho — a releitura roda depois dele.
      case "$cid" in
        c"$C"b-*) continue ;;
      esac
      _v="${VER_DE[$cid]:-}"
      if [ -z "$_v" ]; then
        echo "RECUSA: id '$cid' (--$_lote) não existe nos vereditos do ciclo $C ($VERED)." >&2
        echo "        ids válidos: ${VALIDOS[*]:-<nenhum>}" >&2
        echo "        (correção de releitura do mesmo ciclo usa a forma c${C}b-NN)" >&2
        exit 3
      fi
      # No lote `--adiados` o dispensado e tolerado: dispensa JA E divida por definicao,
      # e recusar ali so custaria um turno do coordenador. A porta fechada e a promocao.
      if [ "$_v" = confirmado_irrelevante ] && [ "$_lote" = adiados ]; then continue; fi
      if [ "$_v" = confirmado_irrelevante ]; then
        echo "RECUSA: id '$cid' foi DISPENSADO pelo verificador (confirmado_irrelevante) — dispensa não se promove." >&2
        echo "        o destino dele é uma linha de dívida (planejamento, code-review ou dono); se você discorda," >&2
        echo "        marque a linha como «contestada» com o motivo, mas não a promova no ciclo." >&2
        exit 3
      fi
    done <<EOF_IDS
$_conj
EOF_IDS
  done

  # (3) achado confirmado sem destino: nem corrigido (--ids) nem adiado (--adiados) — no
  # ciclo INTEIRO: o que as rodadas anteriores já levaram (herança conferida) conta.
  SEM_DESTINO=()
  for _id in "${!VER_DE[@]}"; do
    [ "${VER_DE[$_id]}" = confirmado ] || continue
    printf '%s\n' "$IDS_PLANOS" "$HER_IDS" | grep -qxF "$_id" && continue
    printf '%s\n' "$ADI_PLANOS" "$HER_ADI" | grep -qxF "$_id" && continue
    SEM_DESTINO+=("$_id")
  done
  if [ ${#SEM_DESTINO[@]} -gt 0 ]; then
    echo "RECUSA: ${#SEM_DESTINO[@]} achado(s) CONFIRMADO(s) sem destino no ciclo $C: $(printf '%s ' "${SEM_DESTINO[@]}")" >&2
    echo "        todo confirmado sai do ciclo corrigido (--ids) ou adiado (--adiados «id,...»)." >&2
    exit 3
  fi
else
  echo "nota: ciclo $C sem $VERED — trava de ids inativa (ciclo sem consultoria especializada)" >&2
fi

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

if [ ${#COMITADOS[@]} -eq 0 ] && [ "$HER_ON" = 1 ]; then
  falhar "a rodada $((HER_N+1)) do ciclo $C não alterou nenhum alvo — nada a registrar; o .aplicado das rodadas anteriores fica como está (ids novos sem emenda: $(lista_ids "$IDS_NOVOS" | paste -sd, -))"
fi
if [ ${#COMITADOS[@]} -eq 0 ]; then
  echo "aviso: ciclo $C nao alterou nenhum alvo — gravando marcador .vazio" >&2
  rm -rf "$T"; trap - EXIT
  exec "$0" "$PD" "$C" --vazio
fi

# ── FM-05INT: caminho declarado tem de estar no diff ────────────────────────
# `--ids "id:<caminho>"` com caminho que o ciclo não comitou era ignorado EM SILÊNCIO e
# a entrada caía na regra do caminho único — foi assim que 18 ids do ciclo 1 saíram
# selados contra o arquivo errado. Agora é recusa, antes de qualquer promoção.
DECL_FORA=()
IFS=',' read -r -a _TOK_CHECK <<< "$IDS_NOVOS"
for tok in ${_TOK_CHECK[@]+"${_TOK_CHECK[@]}"}; do
  case "$tok" in *:*) ;; *) continue ;; esac
  _cid="${tok%%:*}"; _decl="${tok#*:}"
  [ -n "$_decl" ] || continue
  _dn="$_decl"
  if [ -e "$_decl" ]; then
    _dn=$(python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' "$_decl" "$ROOT" 2>/dev/null) || _dn="$_decl"
  fi
  case " ${COMITADOS[*]} " in *" $_dn "*) continue ;; esac
  DECL_FORA+=("$_cid:$_decl")
done
if [ ${#DECL_FORA[@]} -gt 0 ]; then
  falhar "caminho declarado ausente do diff do ciclo $C: ${DECL_FORA[*]} — comitados: ${COMITADOS[*]}"
fi

# ── MGTm-01INT: deriva documental conferida por script, antes do commit ─────
# Ponteiro decisão→critério, contagem por extenso × lista e carimbo «revalidada no
# ciclo N». SÓ ACUSA: a reescrita automática espera uma fase real sem ruído, e um
# parser de contagem que errasse bloquearia o ciclo inteiro. A lista sai no stderr e
# o número entra no JSON de saída, para o coordenador decidir em 1 turno.
REVALIDA_N=0; REVALIDA_TXT=""
if [ -f "$GAD_SCRIPTS_DIR/revalida-documentos.sh" ]; then
  REVALIDA_TXT=$(bash "$GAD_SCRIPTS_DIR/revalida-documentos.sh" "$PD" "$C" 2>/dev/null) || true
  [ -z "$REVALIDA_TXT" ] || {
    REVALIDA_N=$(printf '%s\n' "$REVALIDA_TXT" | grep -c .)
    echo "AVISO revalida-documentos ($REVALIDA_N): deriva documental no ciclo $C —" >&2
    printf '%s\n' "$REVALIDA_TXT" | sed 's/^/  /' >&2
  }
fi

# Mensagem (FM-F27INS-04INT): ids NOVOS da rodada no assunto — a forma documentada —, a
# LISTA DE ARQUIVOS DO DIFF no corpo (FM-05INT da F4: 7 commits traziam mensagem divergente
# do que tocavam; a lista continua saindo do diff, não do que o coordenador digitou). O
# DECISIONS-INDEX entra porque ele é, de fato, parte do que o commit muda.
RODADA="c$C"
if [ "$HER_ON" = 1 ]; then
  _letras=bcdefghijklmnopqrstuvwxyz
  RODADA="c$C${_letras:$((HER_N-1)):1}"
fi
MSG="docs(fase $NN): correções do ciclo $C — $(lista_ids "$IDS_NOVOS" | paste -sd, - | sed 's/,/, /g')"
MSG="$MSG"$'\n\n'"caminhos: $(printf '%s, ' "${COMITADOS[@]}" | sed 's/, $//')"
MSG="$MSG"$'\n'"ids: $IDS_NOVOS${ADIADOS:+$'\n'adiados: $ADIADOS}"
if [ "$HER_ON" = 1 ]; then
  MSG="$MSG"$'\n'"rodada: $RODADA (herdados das anteriores: $(printf '%s' "$HER_IDS" | paste -sd, -))"
fi
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
# M5 (F24.5): o índice de decisões é regenerado por script, nunca é alvo de correção — contá-lo
# como «2º caminho» apagou o hash de 8 das 15 correções do ciclo 0 da 24.5. A regra 2 (caminho
# único) passa a contar só os caminhos que NÃO são derivados.
COMITADOS_COR=()
for r in ${COMITADOS[@]+"${COMITADOS[@]}"}; do
  [ "$r" = "$IDX_REL" ] && continue
  COMITADOS_COR+=("$r")
done
UNICO=""
[ ${#COMITADOS_COR[@]} -eq 1 ] && UNICO="${COMITADOS_COR[0]}"

COR_ENTRADAS=(); AUSENTES=()
IFS=',' read -r -a TOKENS_ID <<< "$IDS_NOVOS"
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
  echo "aviso: ${#AUSENTES[@]} correção(ões) sem hash (ciclo comitou ${#COMITADOS_COR[@]} caminhos de correção e o id não declarou qual): ${AUSENTES[*]} — declaradas em hash_ausente[]" >&2
fi
IDS_JSON=$(lista_ids "$IDS_NOVOS" | jq -R 'select(length>0)' | jq -cs .)
ADI_JSON=$(printf '%s\n' "$ADI_NOVOS" | jq -R 'select(length>0)' | jq -cs .)
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
# herança (t59 b2/b3): a rodada anterior conferida entra como base da união
if [ "$HER_ON" = 1 ]; then
  HER_JSON=$(jq -c --argjson adi "$(printf '%s\n' "$HER_ADI" | jq -R 'select(length>0)' | jq -cs .)" '
    {ids: (.ids // []), correcoes: (.correcoes // []), hash_ausente: (.hash_ausente // []),
     adiados: $adi, blobs: (.blobs // []),
     rodadas: (if (.rodadas // [] | length) > 0 then .rodadas
               else [{rodada: ("c" + (.ciclo|tostring)), commit: .commit, ids: (.ids // []),
                      adiados: $adi, caminhos: (.caminhos // []), blobs: (.blobs // [])}] end)}' "$APL")
else
  HER_JSON='{"ids":[],"correcoes":[],"hash_ausente":[],"adiados":[],"blobs":[],"rodadas":[]}'
fi
jq -cn --arg c "$C" --arg commit "$CAND" --arg msg "$MSG" --arg rod "$RODADA" \
  --argjson ids "$IDS_JSON" --argjson cor "$COR_JSON" --argjson cam "$CAM_JSON" \
  --argjson bl "$BLOBS_JSON" --argjson aus "$AUS_JSON" --argjson adi "$ADI_JSON" \
  --argjson h "$HER_JSON" \
  '($h.rodadas + [{rodada:$rod, commit:$commit, ids:$ids, adiados:$adi, caminhos:$cam, blobs:$bl}]) as $rs
   | {v:1, ciclo:$c,
      ids: ($h.ids + ($ids - $h.ids)),
      correcoes: ($h.correcoes + ($cor | map(select(.id as $i | ($h.ids | index($i)) == null)))),
      commit:$commit, caminhos:$cam,
      hash_ausente: ($h.hash_ausente + ($aus - $h.hash_ausente)),
      blobs: (reduce ($h.blobs + $bl)[] as $b ({}; .[$b.path] = $b) | [.[]]),
      mensagem:$msg,
      adiados: ($h.adiados + ($adi - $h.adiados)),
      commits: ($rs | map(.commit)),
      rodadas: $rs}' \
  > "$APL.tmp" && mv -f "$APL.tmp" "$APL"
rm -f "$(CI correcoes.vazio)"

gad_autoregistro "correcoes-commit.sh" 0 "$RODADA commit $CAND (${#COMITADOS[@]} caminhos)" || true
gad_json_out correcoes-commit "$(jq -cn --arg c "$C" --arg commit "$CAND" --arg a "$APL" \
  --argjson cam "$CAM_JSON" --argjson rev "$REVALIDA_N" --arg rod "$RODADA" \
  --argjson her "$([ "$HER_ON" = 1 ] && echo true || echo false)" \
  '{ciclo:$c, modo:"fim", rodada:$rod, herdou:$her, commit:$commit, caminhos:$cam, aplicado:$a, revalida_avisos:$rev}')"
