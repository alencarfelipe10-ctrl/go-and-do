#!/usr/bin/env bash
# confere-reconciliacao.sh — reconciliação mecânica VEREDITO × APLICADO da revisão
# adversarial, e trava de ordem releitura→correção na SAÍDA (item A5 do PLANO-A).
#
# Uso: confere-reconciliacao.sh <phase_dir> [<ciclo>] [--ordem]
#
# POR QUE ESTE SCRIPT EXISTE
# Os dois lados do dado já estavam gravados e ninguém os juntava:
#   · vereditos → <phase_dir>/.intent/.vereditos-c<C>.txt, uma linha por achado no
#     formato `id | classe | veredito | categoria`, com
#     veredito ∈ confirmado | nao_sustentado | ja_coberto (formato: decide-ciclo.sh:11-16);
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
#
# --ordem (A5b): a ordem releitura→commit só é travada na ABERTURA do ciclo seguinte
# (briefing-build.sh, gate E2c/R1). O furo é na SAÍDA: a rota `para-custo-marginal` aplica
# o lote C/D/E final sem re-submeter aos revisores e vai direto ao passo 7 — como não há
# ciclo novo, nenhum gate olha. Com --ordem comparamos, no último ciclo, o mtime do
# `.releitura-c<C>.json` com a data do commit registrado em `.correcoes-c<C>.aplicado`.
# Correção promovida DEPOIS da releitura = correção que ninguém releu → ORDEM-VIOLADA.
#
# SAÍDA: uma linha por achado fora do `ok`, mais um resumo com a contagem de cada classe
# e `reconciliacao: ok|falha` (e `ordem: ok|violada|n/a` quando --ordem).
#
# EXIT: 0 = tudo ok (ou n/a) · 1 = INVERSAO, CONFIRMADO-NAO-APLICADO,
#       APLICADO-SEM-VEREDITO ou ORDEM-VIOLADA · 2 = uso inválido.
#
# SOMENTE LEITURA: o script não escreve nada em disco — por isso NÃO sourceia o
# lib/gsd-shim.sh nem instala o trap `gad_autoregistro` que os outros gates usam (aquele
# helper grava no run-log da fase; aqui isso violaria a regra 7 do item A5a e sujaria a
# telemetria de uma fase que a auditoria lê a posteriori).

set -u

PD=""; CICLO=""; ORDEM=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ordem) ORDEM=1; shift ;;
    -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
    --*) echo "flag desconhecida: $1" >&2; exit 2 ;;
    *)
      if [ -z "$PD" ]; then PD="$1"
      elif [ -z "$CICLO" ]; then CICLO="$1"
      else echo "argumento extra: $1" >&2; exit 2; fi
      shift ;;
  esac
done

[ -n "$PD" ] || { echo "uso: confere-reconciliacao.sh <phase_dir> [<ciclo>] [--ordem]" >&2; exit 2; }
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
  # ATENÇÃO — não saia aqui quando `--ordem` foi pedido: uma fase com a revisão
  # adversarial pulada ainda tem ciclo 0 (`.correcoes-c0.aplicado` + `.releitura-c0.json`)
  # e uma correção promovida depois daquela releitura é exatamente o que este gate existe
  # para pegar. Sair 0 aqui seria reportar verde no caso a conferir (fail-open).
  [ "$ORDEM" = 1 ] || exit 0
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

# Terceiro campo fora de confirmado|nao_sustentado|ja_coberto: classe própria e declarada,
# nunca absorvida no contador `ok` (mesmo fail-closed do SEM-INSUMO do confere-rotas.sh).
veredito_ilegivel() { # <ciclo> <id> <veredito lido>
  echo "VEREDITO-ILEGIVEL c$1 $2 — terceiro campo '$3' fora de confirmado|nao_sustentado|ja_coberto"
  n_ileg=$((n_ileg+1)); falha=1
}

n_ok=0; n_inv=0; n_cna=0; n_asv=0; n_fora=0; n_ileg=0
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
        *) veredito_ilegivel "$C" "$id" "$ver" ;;
      esac
    else
      case "$ver" in
        confirmado)
          echo "CONFIRMADO-NAO-APLICADO c$C $id veredito=confirmado — ausente do .correcoes-c$C.aplicado"
          n_cna=$((n_cna+1)); falha=1 ;;
        nao_sustentado|ja_coberto) n_ok=$((n_ok+1)) ;;
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

  echo "resumo: ok=$n_ok INVERSAO=$n_inv CONFIRMADO-NAO-APLICADO=$n_cna APLICADO-SEM-VEREDITO=$n_asv VEREDITO-ILEGIVEL=$n_ileg fora-do-escopo=$n_fora"
  if [ "$falha" -eq 0 ]; then echo "reconciliacao: ok"; else echo "reconciliacao: falha"; fi
fi

# ── A5b — trava de ordem na saída ───────────────────────────────────────────────
if [ "$ORDEM" = 1 ]; then
  # O ciclo da ordem é derivado INDEPENDENTE da enumeração dos vereditos: uma fase com a
  # revisão adversarial pulada não tem `.vereditos-c*.txt` nenhum e ainda assim tem ciclo 0
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
