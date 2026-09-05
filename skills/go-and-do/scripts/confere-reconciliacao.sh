#!/usr/bin/env bash
# confere-reconciliacao.sh — reconciliação mecânica VEREDITO × APLICADO da consultoria
# especializada de intenção, e trava de ordem releitura→correção na SAÍDA (item A5 do PLANO-A).
#
# Uso: confere-reconciliacao.sh <phase_dir> [<ciclo>] [--ordem] [--final]
#
# POR QUE ESTE SCRIPT EXISTE
# Os dois lados do dado já estavam gravados e ninguém os juntava:
#   · vereditos → <phase_dir>/.intent/.vereditos-c<C>.txt, uma linha por achado no
#     formato `id | classe | veredito | categoria`, com
#     veredito ∈ confirmado | nao_sustentado | ja_coberto | confirmado_irrelevante
#     (formato: decide-ciclo.sh, cabeçalho; `confirmado_irrelevante` = confirmado sem
#     vínculo ao Goal, registrado como dívida — R2 do plano 3, 05/09/2026);
#   · aplicados → <phase_dir>/.intent/.correcoes-c<C>.aplicado, JSON
#     {v,ciclo,ids,correcoes:[{id,hash}],commit,caminhos,blobs,mensagem}
#     (schema: correcoes-commit.sh, bloco de cabeçalho).
# O `decide-ciclo.sh` lê os vereditos só para decidir se o loop continua; o
# `confere-ciclo.sh` compara outra coisa (achados brutos × cobertura textual). A tabela
# de reconciliação de verdade era escrita EM PROSA pelo coordenador no NN-INTENT-REVIEW.md,
# sem checagem nenhuma. Na F24.4 passaram: um `confirmado` não aplicado, três aplicados
# sem veredito e um `nao_sustentado` APLICADO — inversão pura.
#
# CLASSIFICAÇÃO (por achado)
#   confirmado    + presente no .aplicado → ok
#   ja_coberto    + presente             → ok (legítimo: já coberto e a correção reforçou)
#   nao_sustentado+ presente             → INVERSAO                (o mais grave)
#   confirmado    + AUSENTE              → CONFIRMADO-NAO-APLICADO
#   presente no .aplicado sem veredito   → APLICADO-SEM-VEREDITO, salvo quando o id não
#     segue o padrão estrito `c<N>-<NN>` — aí é `fora-do-escopo` e NÃO conta (é o caso
#     das passadas "b" documentadas, `c<N>b-<NN>`, e de correções de outra origem).
#   nao_sustentado/ja_coberto + AUSENTE  → ok (não aplicar é o esperado)
#   confirmado_irrelevante + AUSENTE     → ok (a dispensa tira o ciclo, não obriga correção)
#   confirmado_irrelevante + presente    → DISPENSADO-APLICADO — classe declarada, NÃO
#     bloqueante («nada se descarta»: o coordenador pode corrigir um achado dispensado)
#
# RELEITURA-ABERTA (R9, plano 3): com --ordem, no último ciclo, `.releitura-c<C>.json` com
#   `v: 2` e `ok: false` é uma releitura que reprovou sem correção `c<C>b` — bloqueante
#   (o briefing do ciclo seguinte pegaria isso, mas o último ciclo não abre briefing).
#   Sem `v` → aviso legado (formato anterior ao R9, veredito não conferível).
#
# --ordem (A5b): a ordem releitura→commit só é travada na ABERTURA do ciclo seguinte
# (briefing-build.sh, gate E2c/R1). O furo é na SAÍDA: a rota `para-custo-marginal` aplica
# o lote C/D/E final sem re-submeter aos revisores e vai direto ao passo 7 — como não há
# ciclo novo, nenhum gate olha. Com --ordem comparamos, no último ciclo, o mtime do
# `.releitura-c<C>.json` com a data do commit registrado em `.correcoes-c<C>.aplicado`.
# Correção promovida DEPOIS da releitura = correção que ninguém releu → ORDEM-VIOLADA.
#
# D-NN-DESATUALIZADA (C3, plano 2 / 05/09/2026) — mexeu no SPEC, tem de olhar o CONTEXT.
# Na F24.4 quatro dos cinco ciclos emendaram critérios do SPEC sem tocar o CONTEXT, e seis
# decisões continuaram citando critérios que já não existiam. Dois detectores, ambos
# INFORMATIVOS (a lista é insumo da releitura, que devolve `ok: false` e dispara a correção
# `c<C>b`; um exit 1 aqui reprovaria a etapa antes do laço que conserta):
#   · por ciclo: `git diff -U20 <commit>^..<commit> -- <SPEC>` do `.correcoes-c<C>.aplicado`;
#     colhe os `AC-nn`/`R-n` citados nas linhas +/- e o AC dono de cada hunk; toda D-NN do
#     CONTEXT vigente que cita um desses ids, não foi tocada no mesmo commit (CONTEXT fora
#     dos `caminhos`, ou dentro mas com o bullet intacto) e não traz a tag `superada-c<N>`
#     → `D-NN-DESATUALIZADA c<C> <D-NN> — cita <ids> (SPEC mudou em <sha>); <motivo>`.
#   · `--final`: mesma régua entre os blobs selados `.intent/.base-SPEC.txt` /
#     `.base-CONTEXT.txt` (o original) e o worktree — pega o que mudou fora de um `.aplicado`
#     (o passe «b»): linhas `D-NN-DESATUALIZADA final <D-NN> — …`. Fase sem base selada →
#     `final: n/a`.
#   Uma linha por decisão, o id como terceiro token (a releitura e o plano 3 leem assim), e
#   a contagem em `informativos: D-NN-DESATUALIZADA=<n>`. Nunca entra no `exit`.
#
# SAÍDA: uma linha por achado fora do `ok`, mais um resumo com a contagem de cada classe
# e `reconciliacao: ok|falha` (e `ordem: ok|violada|n/a` quando --ordem).
#
# EXIT: 0 = tudo ok (ou n/a) · 1 = INVERSAO, CONFIRMADO-NAO-APLICADO,
#       APLICADO-SEM-VEREDITO, VEREDITO-ILEGIVEL, ORDEM-VIOLADA ou RELEITURA-ABERTA · 2 = uso inválido.
#       D-NN-DESATUALIZADA e DISPENSADO-APLICADO nunca mudam o exit (informativos por desenho).
#
# SOMENTE LEITURA: o script não escreve nada no projeto — por isso NÃO sourceia o
# lib/gsd-shim.sh nem instala o trap `gad_autoregistro` que os outros gates usam (aquele
# helper grava no run-log da fase; aqui isso violaria a regra 7 do item A5a e sujaria a
# telemetria de uma fase que a auditoria lê a posteriori). A única escrita é um
# `mktemp -d` em $TMPDIR para os diffs do detector C3, apagado no EXIT.

set -u

PD=""; CICLO=""; ORDEM=0; FINAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ordem) ORDEM=1; shift ;;
    --final) FINAL=1; shift ;;
    -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
    --*) echo "flag desconhecida: $1" >&2; exit 2 ;;
    *)
      if [ -z "$PD" ]; then PD="$1"
      elif [ -z "$CICLO" ]; then CICLO="$1"
      else echo "argumento extra: $1" >&2; exit 2; fi
      shift ;;
  esac
done

[ -n "$PD" ] || { echo "uso: confere-reconciliacao.sh <phase_dir> [<ciclo>] [--ordem] [--final]" >&2; exit 2; }
[ -d "$PD" ] || { echo "ERRO: phase_dir inexistente: $PD" >&2; exit 2; }
case "$CICLO" in ""|*[!0-9]*) [ -z "$CICLO" ] || { echo "ERRO: ciclo deve ser numérico: $CICLO" >&2; exit 2; } ;; esac

IN="$PD/.intent"

# ── quais ciclos ────────────────────────────────────────────────────────────────
ciclos=""
if [ -n "$CICLO" ]; then
  [ -f "$IN/.vereditos-c$CICLO.txt" ] && ciclos="$CICLO"
else
  ciclos=$(ls "$IN"/.vereditos-c*.txt 2>/dev/null \
    | sed -n 's/.*\.vereditos-c\([0-9][0-9]*\)\.txt$/\1/p' | sort -n)
fi

if [ -z "$ciclos" ]; then
  # Sem vereditos não há o que reconciliar. Não inventamos falha em fase sem ciclos
  # (regra 6 do A5a) — mas a ausência é declarada, nunca silenciosa.
  echo "reconciliacao: n/a (nenhum .vereditos-c*.txt em $IN$([ -n "$CICLO" ] && echo " para o ciclo $CICLO"))"
  # ATENÇÃO — não saia aqui quando `--ordem` foi pedido: uma fase com a consultoria
  # especializada pulada ainda tem ciclo 0 (`.correcoes-c0.aplicado` + `.releitura-c0.json`)
  # e uma correção promovida depois daquela releitura é exatamente o que este gate existe
  # para pegar. Sair 0 aqui seria reportar verde no caso a conferir (fail-open).
  # Idem para o detector de D-NN desatualizadas: o c0 da 24.4 não tem vereditos e é
  # justamente onde o SPEC mais mudou.
  [ "$ORDEM" = 1 ] || [ "$FINAL" = 1 ] || ls "$IN"/.correcoes-c*.aplicado >/dev/null 2>&1 || exit 0
fi

# ── helpers ─────────────────────────────────────────────────────────────────────
# ids promovidos de um ciclo, um por linha (jq quando disponível; fallback textual).
ids_aplicados() { # <arquivo .aplicado>
  local f="$1"
  [ -f "$f" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r '(.ids // [])[]' "$f" 2>/dev/null && return 0
  fi
  sed -n 's/.*"ids"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$f" \
    | tr ',' '\n' | tr -d ' "'
}

campo_json() { # <arquivo> <chave>  → primeiro valor string da chave
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -1
}

# Um id é "achado de revisor" só no padrão estrito c<N>-<NN>. Anotar frouxo aqui faria
# as passadas "b" (c1b-01…) inundarem a saída como APLICADO-SEM-VEREDITO.
id_de_achado() { printf '%s' "$1" | grep -qE '^c[0-9]+-[0-9]+$'; }

curto() { printf '%s' "${1:-}" | cut -c1-8; }  # hash abreviado para a saída

# Terceiro campo fora do enum: classe própria e declarada, nunca absorvida no contador
# `ok` (mesmo fail-closed do SEM-INSUMO do confere-rotas.sh).
veredito_ilegivel() { # <ciclo> <id> <veredito lido>
  echo "VEREDITO-ILEGIVEL c$1 $2 — terceiro campo '$3' fora de confirmado|nao_sustentado|ja_coberto|confirmado_irrelevante"
  n_ileg=$((n_ileg+1)); falha=1
}

n_ok=0; n_inv=0; n_cna=0; n_asv=0; n_fora=0; n_ileg=0; n_disp=0; n_disp_ap=0
falha=0

# ── reconciliação, ciclo a ciclo ────────────────────────────────────────────────
ultimo_ciclo=""
for C in $ciclos; do
  ultimo_ciclo="$C"
  V="$IN/.vereditos-c$C.txt"
  A="$IN/.correcoes-c$C.aplicado"
  Z="$IN/.correcoes-c$C.vazio"

  aplicados=$(ids_aplicados "$A")
  commit_c=$(campo_json "$A" commit)

  if [ ! -f "$A" ]; then
    if [ -f "$Z" ]; then
      echo "nota c$C: ciclo marcado vazio (.correcoes-c$C.vazio) — nenhuma correção promovida"
    else
      echo "nota c$C: sem .correcoes-c$C.aplicado — nenhuma correção promovida"
    fi
  fi

  vistos=""
  # 1) lado dos vereditos
  while IFS= read -r linha; do
    case "$linha" in ''|'#'*) continue ;; esac
    id=$(printf '%s' "$linha"   | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$1); print $1}')
    ver=$(printf '%s' "$linha"  | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')
    [ -n "$id" ] || continue
    vistos="$vistos $id"
    if printf '%s\n' "$aplicados" | grep -qxF "$id"; then
      case "$ver" in
        nao_sustentado)
          echo "INVERSAO c$C $id veredito=nao_sustentado — mas foi aplicado${commit_c:+ no commit $(curto "$commit_c")}"
          n_inv=$((n_inv+1)); falha=1 ;;
        confirmado|ja_coberto) n_ok=$((n_ok+1)) ;;
        confirmado_irrelevante)
          echo "DISPENSADO-APLICADO c$C $id veredito=confirmado_irrelevante — corrigido mesmo sem vínculo ao Goal (não bloqueante)"
          n_disp=$((n_disp+1)); n_disp_ap=$((n_disp_ap+1)) ;;
        *) veredito_ilegivel "$C" "$id" "$ver" ;;
      esac
    else
      case "$ver" in
        confirmado)
          echo "CONFIRMADO-NAO-APLICADO c$C $id veredito=confirmado — ausente do .correcoes-c$C.aplicado"
          n_cna=$((n_cna+1)); falha=1 ;;
        nao_sustentado|ja_coberto) n_ok=$((n_ok+1)) ;;
        confirmado_irrelevante) n_ok=$((n_ok+1)); n_disp=$((n_disp+1)) ;;
        # Fail-closed dos dois lados: absorver uma linha ilegível no contador `ok` só
        # porque o achado não foi aplicado inflaria o verde em silêncio.
        *) veredito_ilegivel "$C" "$id" "$ver" ;;
      esac
    fi
  done < "$V"

  # 2) lado dos aplicados sem linha de veredito
  for id in $aplicados; do
    [ -n "$id" ] || continue
    case " $vistos " in *" $id "*) continue ;; esac
    if id_de_achado "$id"; then
      echo "APLICADO-SEM-VEREDITO c$C $id — promovido sem linha em .vereditos-c$C.txt"
      n_asv=$((n_asv+1)); falha=1
    else
      n_fora=$((n_fora+1))
    fi
  done
done

if [ -n "$ciclos" ]; then
  # Aplicados de ciclos que não têm vereditos nenhum (ex.: o c0 da F24.4) ficam fora da
  # enumeração por desenho — mas em aviso explícito, nunca em silêncio. Com recorte de
  # ciclo o aviso é suprimido: quem pediu um ciclo não quer o ruído dos outros.
  if [ -z "$CICLO" ]; then
    for f in "$IN"/.correcoes-c*.aplicado; do
      [ -f "$f" ] || continue
      c=$(printf '%s' "$f" | sed -n 's/.*\.correcoes-c\([0-9][0-9]*\)\.aplicado$/\1/p')
      [ -n "$c" ] || continue
      [ -f "$IN/.vereditos-c$c.txt" ] && continue
      echo "aviso: c$c tem .correcoes-c$c.aplicado sem .vereditos-c$c.txt — correções promovidas sem veredito registrado (não reconciliável)"
    done
  fi

  echo "resumo: ok=$n_ok INVERSAO=$n_inv CONFIRMADO-NAO-APLICADO=$n_cna APLICADO-SEM-VEREDITO=$n_asv VEREDITO-ILEGIVEL=$n_ileg fora-do-escopo=$n_fora dispensados=$n_disp dispensados_aplicados=$n_disp_ap"
  if [ "$falha" -eq 0 ]; then echo "reconciliacao: ok"; else echo "reconciliacao: falha"; fi
fi

# ── C3 — D-NN desatualizadas (informativo; ver cabeçalho) ───────────────────────
# Um bloco python por ser leitura de diff com estado (AC dono do hunk, bullet dono da linha);
# só lê git e arquivos — nada é escrito.
n_desat=0
ROOT_GIT=$(git -C "$PD" rev-parse --show-toplevel 2>/dev/null || true)
CTX_VIG=$(ls "$PD"/*-CONTEXT.md 2>/dev/null | head -1 || true)
SPEC_VIG=$(ls "$PD"/*-SPEC.md 2>/dev/null | grep -v -E 'AI-SPEC|PRE-SPEC' | head -1 || true)
desatualizadas() { # <rótulo: c<C>|final> <diff do SPEC (arquivo)> <diff do CONTEXT (arquivo, pode ser vazio)> <sha curto> <motivo quando o CONTEXT não mudou>
  python3 - "$@" "$CTX_VIG" <<'PYD'
import re, sys
rot, dspec, dctx, sha, motivo_ctx, ctx = sys.argv[1:7]
AC = re.compile(r"\bAC-\d+\b"); RN = re.compile(r"\bR-?(\d+)\b")
def ids(t):
    return set(AC.findall(t)) | {"R" + n for n in RN.findall(t)}
mudados = set()
for ln in open(dspec, encoding="utf-8", errors="replace"):
    if ln.startswith(("+++", "---", "diff ", "index ")):
        continue
    if ln.startswith("@@"):
        dono = None; continue
    corpo = ln[1:] if ln[:1] in "+- " else ln
    m = AC.search(corpo)
    if m:
        dono = m.group(0)          # AC dono do hunk = último id visto no contexto (-U20)
    if ln[:1] in "+-":
        mudados |= ids(corpo)
        if dono:
            mudados.add(dono)
if not mudados:
    print(f"nota {rot}: nenhum AC-nn/R-n mudou no SPEC — nada a conferir")
    sys.exit(0)
tocadas = set()
if dctx:
    dono = None
    for ln in open(dctx, encoding="utf-8", errors="replace"):
        if ln.startswith(("+++", "---", "diff ", "index ")):
            continue
        if ln.startswith("@@"):
            dono = None; continue
        corpo = ln[1:] if ln[:1] in "+- " else ln
        m = re.match(r"^\s*-\s+\*\*(D-[0-9A-Za-z_-]+)", corpo)
        if m:
            dono = m.group(1)
        if ln[:1] in "+-" and dono:
            tocadas.add(dono)
try:
    texto = open(ctx, encoding="utf-8").read()
except Exception:
    print(f"nota {rot}: CONTEXT vigente ausente — nada a conferir"); sys.exit(0)
m = re.search(r"<decisions>\n(.*?)\n</decisions>", texto, re.S)
bul, cur = [], None
for ln in (m.group(1) if m else "").splitlines():
    h = re.match(r"^\s*-\s+\*\*(D-[0-9A-Za-z_-]+)((?:\s*\[[^\]]*\])?)[^:*]*:\*\*", ln)
    if h:
        cur = [h.group(1), h.group(2), [ln]]; bul.append(cur); continue
    if cur and ln.startswith("  "):
        cur[2].append(ln)
    elif ln.startswith("###") or not ln.strip():
        cur = None
n = 0
for did, tags, lines in bul:
    if re.search(r"superada-c\d+", tags):
        continue
    cita = ids("\n".join(lines)) & mudados
    if not cita:
        continue
    if did in tocadas:
        continue
    n += 1
    motivo = motivo_ctx if not dctx else "bullet intacto no commit que mudou o SPEC"
    print(f"D-NN-DESATUALIZADA {rot} {did} — cita {', '.join(sorted(cita))} (SPEC mudou em {sha}); {motivo}")
print(f"desatualizadas {rot}: {n} (ids mudados no SPEC: {len(mudados)})")
PYD
}
if [ -n "$ROOT_GIT" ] && [ -n "$CTX_VIG" ]; then
  TMPD=$(mktemp -d "${TMPDIR:-/tmp}/gad-desat-XXXXXX"); trap 'rm -rf "$TMPD"' EXIT
  for A in "$IN"/.correcoes-c*.aplicado; do
    [ -f "$A" ] || continue
    c=$(printf '%s' "$A" | sed -n 's/.*\.correcoes-c\([0-9][0-9]*\)\.aplicado$/\1/p'); [ -n "$c" ] || continue
    [ -z "$CICLO" ] || [ "$c" = "$CICLO" ] || continue
    commit=$(campo_json "$A" commit); [ -n "$commit" ] || continue
    git -C "$ROOT_GIT" cat-file -e "$commit^{commit}" 2>/dev/null || { echo "nota c$c: commit $(curto "$commit") não está no repositório — D-NN desatualizadas não conferidas"; continue; }
    # A passada «b» sobrescreve o .aplicado IN-PLACE (correcoes-commit.sh, cabeçalho): o commit
    # registrado é o último do ciclo. Os anteriores têm a mensagem canônica do mesmo script
    # (`… correções do ciclo C — …`) e entram pelo grep no histórico — cada um com o seu diff.
    NNF=$(basename "$SPEC_VIG" | sed -nE 's/^([0-9]+(\.[0-9]+)*)-.*$/\1/p')   # `docs(fase 24.4): correções do ciclo C — …`
    commits=$( { git -C "$ROOT_GIT" log --format=%H --fixed-strings --grep="(fase ${NNF:-?}): correções do ciclo $c —" HEAD 2>/dev/null; printf '%s\n' "$commit"; } | awk '!v[$0]++' )
    SPEC_REL=$(python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' "$SPEC_VIG" "$ROOT_GIT" 2>/dev/null || true)
    CTX_REL=$(python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' "$CTX_VIG" "$ROOT_GIT" 2>/dev/null || true)
    for cm in $commits; do
      git -C "$ROOT_GIT" cat-file -e "$cm^{commit}" 2>/dev/null || continue
      spec_c=$(git -C "$ROOT_GIT" diff --name-only "$cm^..$cm" -- "$SPEC_REL" 2>/dev/null | head -1 || true)
      ctx_c=$(git -C "$ROOT_GIT" diff --name-only "$cm^..$cm" -- "$CTX_REL" 2>/dev/null | head -1 || true)
      [ -n "$spec_c" ] || { echo "nota c$c: SPEC fora dos caminhos do commit $(curto "$cm") — nada a conferir"; continue; }
      git -C "$ROOT_GIT" diff -U20 "$cm^..$cm" -- "$spec_c" > "$TMPD/spec-c$c.diff" 2>/dev/null || : > "$TMPD/spec-c$c.diff"
      dctx=""
      if [ -n "$ctx_c" ]; then dctx="$TMPD/ctx-c$c.diff"; git -C "$ROOT_GIT" diff -U0 "$cm^..$cm" -- "$ctx_c" > "$dctx" 2>/dev/null || : > "$dctx"
      else echo "nota c$c: CONTEXT ausente dos caminhos do commit $(curto "$cm")"; fi
      out=$(desatualizadas "c$c" "$TMPD/spec-c$c.diff" "$dctx" "$(curto "$cm")" "CONTEXT fora dos caminhos do ciclo")
      printf '%s\n' "$out"
      n_desat=$((n_desat + $(printf '%s\n' "$out" | grep -c '^D-NN-DESATUALIZADA ')))
    done
  done
  if [ "$FINAL" = 1 ]; then
    BS=$(cat "$IN/.base-SPEC.txt" 2>/dev/null | tr -d ' \n'); BC=$(cat "$IN/.base-CONTEXT.txt" 2>/dev/null | tr -d ' \n')
    if [ -z "$BS" ] || [ -z "$SPEC_VIG" ] || ! git -C "$ROOT_GIT" cat-file -e "$BS" 2>/dev/null; then
      echo "final: n/a (sem .base-SPEC.txt resolvível — fase anterior à selagem)"
    else
      # blob selado × ARQUIVO do worktree (não `git diff <blob> <blob>`: o worktree sujo não tem blob
      # no object store e o diff morreria em "bad object" — fail-open com «nada mudou»). Só leitura.
      git -C "$ROOT_GIT" cat-file blob "$BS" > "$TMPD/spec-base" 2>/dev/null || : > "$TMPD/spec-base"
      diff -U20 "$TMPD/spec-base" "$SPEC_VIG" > "$TMPD/spec-final.diff" 2>/dev/null || true
      dctx=""
      if [ -n "$BC" ] && git -C "$ROOT_GIT" cat-file -e "$BC" 2>/dev/null; then
        dctx="$TMPD/ctx-final.diff"; git -C "$ROOT_GIT" cat-file blob "$BC" > "$TMPD/ctx-base" 2>/dev/null || : > "$TMPD/ctx-base"
        diff -U0 "$TMPD/ctx-base" "$CTX_VIG" > "$dctx" 2>/dev/null || true
      fi
      out=$(desatualizadas "final" "$TMPD/spec-final.diff" "$dctx" "$(curto "$BS")→worktree" "CONTEXT sem base selada")
      printf '%s\n' "$out"
      n_desat=$((n_desat + $(printf '%s\n' "$out" | grep -c '^D-NN-DESATUALIZADA ')))
    fi
  fi
  echo "informativos: D-NN-DESATUALIZADA=$n_desat"
elif [ "$FINAL" = 1 ]; then
  echo "final: n/a (phase_dir fora de um repositório git ou sem CONTEXT)"
fi

# ── A5b — trava de ordem na saída ───────────────────────────────────────────────
if [ "$ORDEM" = 1 ]; then
  # O ciclo da ordem é derivado INDEPENDENTE da enumeração dos vereditos: uma fase com a
  # consultoria especializada pulada não tem `.vereditos-c*.txt` nenhum e ainda assim tem ciclo 0
  # com releitura e correção — é lá que a ordem pode quebrar sem ninguém ver.
  C="$CICLO"
  if [ -z "$C" ]; then
    C=$(ls "$IN"/.releitura-c*.json 2>/dev/null \
      | sed -n 's/.*\.releitura-c\([0-9][0-9]*\)\.json$/\1/p' | sort -n | tail -1)
  fi
  [ -n "$C" ] || C="$ultimo_ciclo"
  if [ -z "$C" ]; then
    C=$(ls "$IN"/.correcoes-c*.aplicado 2>/dev/null \
      | sed -n 's/.*\.correcoes-c\([0-9][0-9]*\)\.aplicado$/\1/p' | sort -n | tail -1)
  fi
  [ -n "$C" ] || { echo "ordem: n/a (nenhum ciclo com releitura ou correção em $IN)"; exit "$falha"; }
  R="$IN/.releitura-c$C.json"
  A="$IN/.correcoes-c$C.aplicado"
  # R9 (plano 3): o último ciclo não abre briefing, logo ninguém lê o veredito da releitura
  # dele. Aqui é o único gate que olha esse arquivo na saída.
  if [ -f "$R" ]; then
    if command -v jq >/dev/null 2>&1 && jq -e . "$R" >/dev/null 2>&1; then
      # `.ok // ""` não serve: o `//` do jq trata `false` como nulo e apagaria o veredito
      rel_v=$(jq -r 'if has("v") then (.v|tostring) else "" end' "$R")
      rel_ok=$(jq -r 'if has("ok") then (.ok|tostring) else "" end' "$R")
    else
      rel_v=$(sed -n 's/.*"v"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$R" | head -1)
      rel_ok=$(sed -n 's/.*"ok"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' "$R" | head -1)
    fi
    if [ -z "$rel_v" ]; then
      echo "aviso: releitura c$C em formato legado (v ausente) — veredito não conferível"
    elif [ "$rel_ok" = false ]; then
      echo "RELEITURA-ABERTA c$C — .releitura-c$C.json declara ok: false e nenhuma correção c${C}b fechou a emenda (último ciclo: nenhum briefing seguinte vai cobrar)"
      falha=1
    fi
  fi
  if [ ! -f "$R" ]; then
    echo "ordem: n/a (sem .releitura-c$C.json — a ausência de releitura é problema de outro gate)"
  elif [ ! -f "$A" ]; then
    echo "ordem: n/a (ciclo $C sem correção promovida)"
  else
    ts_rel=$(stat -c %Y "$R" 2>/dev/null || echo 0)
    hash_a=$(campo_json "$A" commit)
    hash_r=$(campo_json "$R" commit)
    fonte="commit"
    ts_cor=""
    if [ -n "$hash_a" ]; then
      root=$(git -C "$PD" rev-parse --show-toplevel 2>/dev/null || true)
      [ -n "$root" ] && ts_cor=$(git -C "$root" show -s --format=%ct "$hash_a" 2>/dev/null || true)
    fi
    # Fallback declarado: fora de um repositório git (ou com o hash já podado), a data do
    # commit não é resolvível — cai no mtime do próprio .aplicado, dizendo qual fonte usou.
    if [ -z "$ts_cor" ]; then
      ts_cor=$(stat -c %Y "$A" 2>/dev/null || echo 0); fonte="mtime"
    fi
    q_rel=$(date -d "@$ts_rel" +%H:%M:%S 2>/dev/null || echo "$ts_rel")
    q_cor=$(date -d "@$ts_cor" +%H:%M:%S 2>/dev/null || echo "$ts_cor")
    if [ "$ts_cor" -gt "$ts_rel" ]; then
      ids=$(ids_aplicados "$A" | tr '\n' ',' | sed 's/,$//')
      echo "ORDEM-VIOLADA: correção $ids aplicada após a releitura c$C — nunca relida (releitura $q_rel, correção $q_cor por $fonte)"
      if [ -n "$hash_r" ] && [ -n "$hash_a" ] && [ "$hash_r" != "$hash_a" ]; then
        echo "  corroboração: a releitura c$C declara commit $(curto "$hash_r") e o .aplicado registra $(curto "$hash_a") — a emenda relida não é a emenda final"
      fi
      echo "ordem: violada"
      falha=1
    else
      echo "ordem: ok (releitura c$C em $q_rel é posterior à correção em $q_cor por $fonte)"
    fi
  fi
fi

exit "$falha"
