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
#   confirmado    + AUSENTE              → CONFIRMADO-NAO-APLICADO, salvo quando o id está
#     dispensado via `deferred-items.md` (S-2, tarefa 48b) — bloco (delimitado por heading)
#     que cita o id E traz o rótulo "Out of scope" (case-insensitive) — aí é
#     CONFIRMADO-FORA-DE-ESCOPO, informativo (conta em `ok`, nunca falha; a dispensa é uma
#     decisão registrada, não um furo). Lido de `<phase_dir>/deferred-items.md` e, em
#     fallback, `.planning/deferred-items.md` — os dois caminhos que o
#     confere-cardinalidade.sh já lê para as dívidas.
#   presente no .aplicado sem veredito   → APLICADO-SEM-VEREDITO, salvo quando o id não
#     segue o padrão estrito `c<N>-<NN>` — aí é `fora-do-escopo` e NÃO conta (é o caso
#     das passadas "b" documentadas, `c<N>b-<NN>`, e de correções de outra origem).
#   nao_sustentado/ja_coberto + AUSENTE  → ok (não aplicar é o esperado)
#   confirmado_irrelevante + AUSENTE     → ok (a dispensa tira o ciclo, não obriga correção)
#   confirmado_irrelevante + presente    → DISPENSADO-APLICADO — classe declarada, NÃO
#     bloqueante («nada se descarta»: o coordenador pode corrigir um achado dispensado)
#
# RELEITURA-ABERTA (R9, plano 3): com --ordem, no último ciclo, a releitura MAIS RECENTE do
#   ciclo (FM-F4RLR-10INT: `.releitura-c<C><letra>.json` se houve correção pós-releitura,
#   senão `.releitura-c<C>.json`) com `v: 2` e `ok: false` é uma releitura que reprovou sem
#   correção seguinte — bloqueante (o briefing do ciclo seguinte pegaria isso, mas o último
#   ciclo não abre briefing). Sem `v` → aviso legado (formato anterior ao R9, veredito não
#   conferível).
#
# --ordem (A5b): a ordem releitura→commit só é travada na ABERTURA do ciclo seguinte
# (briefing-build.sh, gate E2c/R1). O furo é na SAÍDA: a rota `para-custo-marginal` aplica
# o lote C/D/E final sem re-submeter aos revisores e vai direto ao passo 7 — como não há
# ciclo novo, nenhum gate olha. Com --ordem comparamos, no último ciclo, o mtime da releitura
# mais recente do ciclo com a data do commit registrado em `.correcoes-c<C>.aplicado`.
# Correção promovida DEPOIS da releitura = correção que ninguém releu → ORDEM-VIOLADA.
#
# COERÊNCIA DO DOCUMENTO ÚNICO (AC-40, plano 06-15 — substitui o detector D-NN-DESATUALIZADA
# de SPEC × CONTEXT: numa fase nova não há SPEC, e a deriva que sobra mora DENTRO do
# NN-CONTEXT.md, entre o texto e o bloco da máquina). Escrita livre + conferidor ao fim de
# cada ciclo: as emendas da consultoria continuam entrando por `correcoes.*` aplicados pelo
# coordenador, e a régua é o `confere-documento.py --coerencia` do fork, chamado pelo caminho
# do runtime `${GAD_CONFERE_DOCUMENTO:-$GAD_CFG_DIR/gad-core/bin/nosso/confere-documento.py}`
# (a variável é a costura do teste). Só vale para o NN-CONTEXT.md com a marca
# `<!-- gad:documento-unico: v1 -->` na linha 2; sem ela a coerência sai `n/a` (fase anterior
# ao ADR 0001 — o formato é cobrado pelo abre-rodada.sh e pela cancela da etapa 1).
#   · por ciclo (`<phase_dir> <C>`, a chamada do coordenador ao fim do ciclo): os commits de
#     correções do ciclo são o `commit`/`commits` do `.correcoes-c<C>.aplicado` mais os de
#     mensagem canônica `docs(fase NN): correções do ciclo C —` (a passada «b» sobrescreve o
#     .aplicado). Base do ciclo = pai do commit mais antigo; fim = o mais novo. Três réguas:
#       DOC-INTENCAO-EXTRA c<C> <arquivo> — entre os documentos de intenção da fase
#         (`*-CONTEXT.md`, `*-SPEC.md` exceto UI/AI, `*-PRE-SPEC.md`) algum commit do ciclo
#         mudou outro que não o NN-CONTEXT.md;
#       PROSA-BLOCO-DIVERGE|BLOCO-INVALIDO|ID-DUPLICADO c<C> <arquivo>:<linha> … — o
#         conferidor `--coerencia` sobre o NN-CONTEXT.md COMO FICOU no fim do ciclo (o blob
#         do commit, não o worktree: repetir a conferência depois dá o mesmo resultado, R7);
#       AC-RENUMERADO c<C> <AC-nn> — id presente na prosa («Critérios de aceite», linha
#         `- [ ] AC-nn`) E no gsd:acs da base do ciclo e ausente dos DOIS no fim (o sumiço de
#         um lado só já é PROSA-BLOCO-DIVERGE). Os ids AC-nn são estáveis depois de emenda.
#     Ciclo sem commit de correções, ou com o NN-CONTEXT.md intacto → `c<C>: sem emenda`
#     (R8 empty); limpo → `c<C>: só NN-CONTEXT.md mudou; coerência ok`.
#   · `--final`: a mesma régua sobre o documento VIGENTE (worktree) — o conferidor
#     `--coerencia` e o AC-RENUMERADO contra a base selada `.base-CONTEXT.txt` (sem base
#     resolvível, só o AC-RENUMERADO sai n/a). Linhas `<CODIGO> final …`; limpo → `final:
#     coerência ok`. A cancela da etapa 1 lê o `--final` como aviso.
#   · sem recorte de ciclo e sem `--final` (a chamada `--ordem` do R5 da cancela) a coerência
#     não roda — `coerencia: n/a (sem recorte de ciclo …)`: um ciclo antigo que fechou
#     divergente e foi consertado depois seria uma reprovação sem saída.
#
# SAÍDA: uma linha por achado fora do `ok`, mais um resumo com a contagem de cada classe
# e `reconciliacao: ok|falha` (e `ordem: ok|violada|n/a` quando --ordem; `coerencia:
# ok|falha (<contagens>)` quando a coerência rodou).
#
# EXIT: 0 = tudo ok (ou n/a) · 1 = INVERSAO, CONFIRMADO-NAO-APLICADO,
#       APLICADO-SEM-VEREDITO, VEREDITO-ILEGIVEL, ORDEM-VIOLADA, RELEITURA-ABERTA,
#       PROSA-BLOCO-DIVERGE, BLOCO-INVALIDO, ID-DUPLICADO, DOC-INTENCAO-EXTRA ou AC-RENUMERADO ·
#       2 = uso inválido ou conferidor do documento ausente/ilegível (ausência de garantia).
#       DISPENSADO-APLICADO e CONFIRMADO-FORA-DE-ESCOPO nunca mudam o exit (informativos).
#
# SOMENTE LEITURA: o script não escreve nada no projeto — por isso NÃO sourceia o
# lib/gad-shim.sh nem instala o trap `gad_autoregistro` que os outros gates usam (aquele
# helper grava no run-log da fase; aqui isso violaria a regra 7 do item A5a e sujaria a
# telemetria de uma fase que a auditoria lê a posteriori). A única escrita é um
# `mktemp -d` em $TMPDIR para os blobs da coerência, apagado no EXIT.

set -u

GAD_CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
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

# v2.10.1 (57): arquivos da intenção pelo helper (formato da fase). Só o helper de caminhos
# (sem side effect) — este gate continua sem o shim, pelo motivo do cabeçalho.
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gad-caminhos.sh"
IN="$(gad_fase_caminho "$PD" intent)"            # só para mensagens
IC() { gad_fase_caminho "$PD" "intent/$1"; }     # <nome novo relativo a intent/>
ciclos_de() { # <padrão novo com c*> [letra] → números de ciclo (só dígitos); com `letra`,
  local f c   # a letra da rodada (`c3b`) é descartada em vez de excluir o arquivo
  while IFS= read -r f; do
    c=$(gad_fase_curinga "$PD" "intent/$1" "$f"); [ -n "${2:-}" ] && c="${c%%[a-z]*}"
    case "$c" in ''|*[!0-9]*) ;; *) printf '%s\n' "$c" ;; esac
  done < <(gad_fase_glob "$PD" "intent/$1")
}

# ── quais ciclos ────────────────────────────────────────────────────────────────
ciclos=""
if [ -n "$CICLO" ]; then
  [ -f "$(IC "c$CICLO/vereditos.txt")" ] && ciclos="$CICLO"
else
  ciclos=$( { while IFS= read -r f; do c=$(gad_fase_curinga "$PD" 'intent/c*/vereditos.txt' "$f")
              case "$c" in ''|*[!0-9]*) ;; *) echo "$c" ;; esac
            done < <(gad_fase_glob "$PD" 'intent/c*/vereditos.txt'); } | sort -n)
fi

if [ -z "$ciclos" ]; then
  # Sem vereditos não há o que reconciliar. Não inventamos falha em fase sem ciclos
  # (regra 6 do A5a) — mas a ausência é declarada, nunca silenciosa.
  echo "reconciliacao: n/a (nenhum .vereditos-c*.txt em $IN$([ -n "$CICLO" ] && echo " para o ciclo $CICLO"))"
  # ATENÇÃO — não saia aqui quando `--ordem` foi pedido: uma fase com a consultoria
  # especializada pulada ainda tem ciclo 0 (`.correcoes-c0.aplicado` + `.releitura-c0.json`)
  # e uma correção promovida depois daquela releitura é exatamente o que este gate existe
  # para pegar. Sair 0 aqui seria reportar verde no caso a conferir (fail-open).
  # Idem para a coerência do documento único: com recorte de ciclo ela roda mesmo sem
  # vereditos (é o ciclo sem emenda que registra «sem emenda», R8), e o --final também.
  [ "$ORDEM" = 1 ] || [ "$FINAL" = 1 ] || [ -n "$CICLO" ] || [ -n "$(gad_fase_glob "$PD" 'intent/c*/correcoes.aplicado')" ] || exit 0
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

# S-2 (tarefa 48b): um achado `confirmado` ausente do .aplicado com dispensa GRAVADA no
# deferred-items.md (rótulo "Out of scope", case-insensitive) é uma decisão registrada, não
# um furo — mesmos dois arquivos que o confere-cardinalidade.sh já lê para as dívidas (da
# fase e, em fallback, o do projeto/.planning): `pd/deferred-items.md` e
# `dirname(dirname(pd))/deferred-items.md`. Checagem por BLOCO (heading `#…`, não o arquivo
# inteiro): o id e o rótulo têm de aparecer no mesmo item, senão um "Out of scope" de outro
# achado dispensaria este por engano.
fora_de_escopo() { # <id>
  local id="$1" f
  for f in "$PD/deferred-items.md" "$(dirname -- "$(dirname -- "$PD")")/deferred-items.md"; do
    [ -f "$f" ] || continue
    if awk -v id="$id" '
        function flush() { if (bloco ~ id && tolower(bloco) ~ /out of scope/) achou=1 }
        /^#/ { flush(); bloco="" }
        { bloco = bloco "\n" $0 }
        END { flush(); if (achou) print "sim" }
      ' "$f" 2>/dev/null | grep -q sim; then
      return 0
    fi
  done
  return 1
}

# Terceiro campo fora do enum: classe própria e declarada, nunca absorvida no contador
# `ok` (mesmo fail-closed do SEM-INSUMO do confere-rotas.sh).
veredito_ilegivel() { # <ciclo> <id> <veredito lido>
  echo "VEREDITO-ILEGIVEL c$1 $2 — terceiro campo '$3' fora de confirmado|nao_sustentado|ja_coberto|confirmado_irrelevante"
  n_ileg=$((n_ileg+1)); falha=1
}

n_ok=0; n_inv=0; n_cna=0; n_asv=0; n_fora=0; n_ileg=0; n_disp=0; n_disp_ap=0; n_escopo=0
falha=0

# ── reconciliação, ciclo a ciclo ────────────────────────────────────────────────
ultimo_ciclo=""
for C in $ciclos; do
  ultimo_ciclo="$C"
  V="$(IC "c$C/vereditos.txt")"
  A="$(IC "c$C/correcoes.aplicado")"
  Z="$(IC "c$C/correcoes.vazio")"

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
          if fora_de_escopo "$id"; then
            echo "CONFIRMADO-FORA-DE-ESCOPO c$C $id veredito=confirmado — dispensado via deferred-items.md (rótulo «Out of scope»), não aplicado por decisão registrada (não bloqueante)"
            n_ok=$((n_ok+1)); n_escopo=$((n_escopo+1))
          else
            echo "CONFIRMADO-NAO-APLICADO c$C $id veredito=confirmado — ausente do .correcoes-c$C.aplicado"
            n_cna=$((n_cna+1)); falha=1
          fi ;;
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
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      c=$(gad_fase_curinga "$PD" 'intent/c*/correcoes.aplicado' "$f"); case "$c" in ''|*[!0-9]*) continue ;; esac
      [ -f "$(IC "c$c/vereditos.txt")" ] && continue
      echo "aviso: c$c tem .correcoes-c$c.aplicado sem .vereditos-c$c.txt — correções promovidas sem veredito registrado (não reconciliável)"
    done < <(gad_fase_glob "$PD" 'intent/c*/correcoes.aplicado')
  fi

  echo "resumo: ok=$n_ok INVERSAO=$n_inv CONFIRMADO-NAO-APLICADO=$n_cna APLICADO-SEM-VEREDITO=$n_asv VEREDITO-ILEGIVEL=$n_ileg fora-do-escopo=$n_fora dispensados=$n_disp dispensados_aplicados=$n_disp_ap confirmados_fora_de_escopo=$n_escopo"
  if [ "$falha" -eq 0 ]; then echo "reconciliacao: ok"; else echo "reconciliacao: falha"; fi
fi

# ── coerência do documento único (AC-40, plano 06-15; ver cabeçalho) ────────────
# Só lê git e arquivos; os blobs vão para um mktemp apagado no EXIT.
CONFERE="${GAD_CONFERE_DOCUMENTO:-$GAD_CFG_DIR/gad-core/bin/nosso/confere-documento.py}"
MARCA_DU='<!-- gad:documento-unico: v1 -->'
# Regra única da marca (WR-03 do code review da fase 6): linha 2 sem `\r` e sem espaço nas pontas == a marca —
# a mesma do abre-rodada.sh, do discuss-init.sh, do confere-documento.py e do plan-phase.md.
erro_uso=0; coer_rodou=0; coer_achados=""
ROOT_GIT=$(git -C "$PD" rev-parse --show-toplevel 2>/dev/null || true)
NN_PD=$(basename -- "$PD" | sed -nE 's/^([0-9]+(\.[0-9]+)*[A-Za-z]?)-.*$/\1/p')
if [ -n "$NN_PD" ]; then CTX_NOME="$NN_PD-CONTEXT.md"
else CTX_NOME=$(ls "$PD" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+)*[A-Za-z]?-CONTEXT\.md$' | head -1 || true); fi
NNF="${CTX_NOME%-CONTEXT.md}"
relativo() { python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' "$1" "$2" 2>/dev/null || true; }
tem_marca() { [ "$(LC_ALL=C sed -n '2{s/\r$//;s/^[[:space:]]*//;s/[[:space:]]*$//;p;q}' "$1" 2>/dev/null)" = "$MARCA_DU" ]; }
registra() { # <linha de achado> — imprime e guarda para o resumo
  printf '%s\n' "$1"; coer_achados="${coer_achados}${1}"$'\n'; falha=1
}

# Conferidor do fork sobre um arquivo; reescreve `CODIGO caminho:linha msg` como
# `CODIGO <rótulo> <basename>:<linha> msg` (o caminho do mktemp nunca aparece na saída).
coerencia_arq() { # <rótulo c<C>|final> <arquivo>  → return 0 ok · 1 achados · 2 erro
  local rot="$1" arq="$2" out rc=0 l
  if [ ! -f "$CONFERE" ]; then
    echo "ERRO: conferidor do documento único ausente: $CONFERE (GAD_CONFERE_DOCUMENTO ou o runtime)"
    return 2
  fi
  out=$(python3 "$CONFERE" --coerencia "$arq" 2>&1) || rc=$?
  case "$rc" in
    0) return 0 ;;
    1)
      while IFS= read -r l; do
        [ -n "$l" ] && registra "$l"
      done < <(printf '%s\n' "$out" | awk -v r="$rot" '
        $1 ~ /^(BLOCO-INVALIDO|ID-DUPLICADO|PROSA-BLOCO-DIVERGE)$/ { n = split($2, p, "/"); $2 = p[n]; $1 = $1 " " r; print }')
      falha=1; return 1 ;;
    *)
      echo "ERRO: confere-documento.py saiu $rc em $rot: $(printf '%s' "$out" | head -2 | tr '\n' ' ' | cut -c1-200)"
      return 2 ;;
  esac
}

# ids AC-nn presentes na prosa E no gsd:acs da base e ausentes dos DOIS no atual.
ac_perdidos() { # <base> <atual>
  python3 - "$1" "$2" <<'PYA'
import json, re, sys
def ids(caminho):
    try:
        t = open(caminho, encoding="utf-8").read()
    except Exception:
        return None
    prosa, dentro = set(), False
    for ln in t.splitlines():
        if ln.startswith("## "):
            dentro = ln.startswith("## Critérios de aceite")
            continue
        m = re.match(r"^- \[[ xX]\] (AC-\d+)\b", ln) if dentro else None
        if m:
            prosa.add(m.group(1))
    bloco = set()
    m = re.search(r"<!-- gsd:acs:begin -->(.*?)<!-- gsd:acs:end -->", t, re.S)
    if m:
        try:
            bloco = {str(i.get("id")) for i in json.loads(m.group(1)) if isinstance(i, dict)}
        except Exception:
            bloco = set(re.findall(r'"id"\s*:\s*"(AC-\d+)"', m.group(1)))
    return prosa, bloco
b, a = ids(sys.argv[1]), ids(sys.argv[2])
if b is None or a is None:
    sys.exit(0)
for i in sorted((b[0] & b[1]) - (a[0] | a[1]), key=lambda x: int(re.sub(r"\D", "", x) or 0)):
    print(i)
PYA
}

if [ -z "$CICLO" ] && [ "$FINAL" != 1 ]; then
  echo "coerencia: n/a (sem recorte de ciclo — a coerência é por ciclo, <phase_dir> <C>, ou do documento vigente, --final)"
elif [ -z "$CTX_NOME" ]; then
  echo "coerencia: n/a (sem NN-CONTEXT.md em $PD)"
else
  TMPD=$(mktemp -d "${TMPDIR:-/tmp}/gad-coer-XXXXXX"); trap 'rm -rf "$TMPD"' EXIT

  # ── por ciclo ──
  if [ -n "$CICLO" ]; then
    c="$CICLO"
    if [ -z "$ROOT_GIT" ]; then
      echo "coerencia c$c: n/a (phase_dir fora de um repositório git)"
    else
      CTX_REL=$(relativo "$PD/$CTX_NOME" "$ROOT_GIT"); PD_REL=$(relativo "$PD" "$ROOT_GIT")
      A="$(IC "c$c/correcoes.aplicado")"
      listados=$( { if [ -f "$A" ]; then
                      if command -v jq >/dev/null 2>&1; then jq -r '(.commits // [])[]? // empty' "$A" 2>/dev/null || true; fi
                      campo_json "$A" commit
                    fi
                    git -C "$ROOT_GIT" log --format=%H --fixed-strings --grep="(fase ${NNF}): correções do ciclo $c —" HEAD 2>/dev/null || true
                  } | awk 'NF && !v[$0]++' )
      validos=""; fora=""
      for cm in $listados; do
        if git -C "$ROOT_GIT" cat-file -e "$cm^{commit}" 2>/dev/null; then validos="$validos $(git -C "$ROOT_GIT" rev-parse "$cm^{commit}")"
        else fora="$fora $(curto "$cm")"; fi
      done
      validos=$(printf '%s\n' $validos | awk 'NF && !v[$0]++' | tr '\n' ' ')
      if [ -z "$validos" ] && [ -n "$fora" ]; then
        echo "nota c$c: commit(s) do ciclo fora do repositório ($fora ) — coerência não conferida"
      elif [ -z "$validos" ]; then
        echo "c$c: sem emenda — nenhum commit de correções no ciclo"
      else
        # fim = o commit de que todos os outros descendem; início = o ancestral de todos
        # (ancestralidade, não data: dois commits da passada «b» no mesmo segundo empatariam).
        # Histórico não linear cai na data do commit (`rev-list --no-walk=sorted`).
        fim=""; ini=""
        for x in $validos; do
          e_fim=1; e_ini=1
          for y in $validos; do
            [ "$x" = "$y" ] && continue
            git -C "$ROOT_GIT" merge-base --is-ancestor "$y" "$x" 2>/dev/null || e_fim=0
            git -C "$ROOT_GIT" merge-base --is-ancestor "$x" "$y" 2>/dev/null || e_ini=0
          done
          [ "$e_fim" = 1 ] && [ -z "$fim" ] && fim="$x"
          [ "$e_ini" = 1 ] && [ -z "$ini" ] && ini="$x"
        done
        ordem_c=$(git -C "$ROOT_GIT" rev-list --no-walk=sorted $validos 2>/dev/null)
        [ -n "$fim" ] || fim=$(printf '%s\n' "$ordem_c" | head -1)
        [ -n "$ini" ] || ini=$(printf '%s\n' "$ordem_c" | tail -1)
        base=$(git -C "$ROOT_GIT" rev-parse --verify -q "$ini^" 2>/dev/null || git -C "$ROOT_GIT" hash-object -t tree /dev/null)
        mkdir -p "$TMPD/c$c"; ARQ_FIM="$TMPD/c$c/$CTX_NOME"
        if ! git -C "$ROOT_GIT" show "$fim:$CTX_REL" > "$ARQ_FIM" 2>/dev/null; then
          echo "coerencia c$c: n/a ($CTX_NOME ausente no fim do ciclo, commit $(curto "$fim"))"
        elif ! tem_marca "$ARQ_FIM"; then
          echo "coerencia c$c: n/a ($CTX_NOME fora do formato do documento único — fase anterior ao ADR 0001)"
        else
          coer_rodou=1; antes="$coer_achados"
          # (1) só o NN-CONTEXT.md muda entre os documentos de intenção da fase
          extras=$(for cm in $validos; do
                     git -C "$ROOT_GIT" diff-tree --no-commit-id --name-only -r --root "$cm" -- "$PD_REL" 2>/dev/null \
                       | while IFS= read -r p; do
                           [ "$(dirname -- "$p")" = "$PD_REL" ] || continue
                           b=$(basename -- "$p")
                           case "$b" in
                             "$CTX_NOME"|*-UI-SPEC.md|*-AI-SPEC.md) ;;
                             *-CONTEXT.md|*-SPEC.md) printf '%s\t%s\n' "$b" "$(curto "$cm")" ;;
                           esac
                         done
                   done | sort -u -t$'\t' -k1,1)
          while IFS=$'\t' read -r b sha; do
            [ -n "$b" ] || continue
            registra "DOC-INTENCAO-EXTRA c$c $b — documento de intenção mudado no commit $sha; no ciclo só o $CTX_NOME pode mudar"
          done <<<"$extras"
          # (2) texto × bloco e (3) ids estáveis — só quando o documento mudou no ciclo
          if [ -z "$(git -C "$ROOT_GIT" diff --name-only "$base" "$fim" -- "$CTX_REL" 2>/dev/null)" ]; then
            [ "$coer_achados" = "$antes" ] && echo "c$c: sem emenda — $CTX_NOME não mudou no ciclo"
          else
            coerencia_arq "c$c" "$ARQ_FIM"; rcc=$?
            [ "$rcc" -ge 2 ] && erro_uso=1
            if git -C "$ROOT_GIT" show "$base:$CTX_REL" > "$TMPD/c$c/base" 2>/dev/null; then
              while IFS= read -r id; do
                [ -n "$id" ] && registra "AC-RENUMERADO c$c $id — estava na prosa e no gsd:acs na base do ciclo ($(curto "$base")) e sumiu dos dois em $(curto "$fim")"
              done < <(ac_perdidos "$TMPD/c$c/base" "$ARQ_FIM")
            fi
            [ "$rcc" = 0 ] && [ "$coer_achados" = "$antes" ] && echo "c$c: só $CTX_NOME mudou; coerência ok"
          fi
        fi
      fi
    fi
  fi

  # ── --final: o documento vigente contra a base selada ──
  if [ "$FINAL" = 1 ]; then
    VIG="$PD/$CTX_NOME"
    if [ ! -f "$VIG" ]; then
      echo "final: n/a (sem $CTX_NOME em $PD)"
    elif ! tem_marca "$VIG"; then
      echo "final: n/a ($CTX_NOME fora do formato do documento único — fase anterior ao ADR 0001)"
    else
      coer_rodou=1; antes="$coer_achados"
      coerencia_arq final "$VIG"; rcf=$?
      [ "$rcf" -ge 2 ] && erro_uso=1
      BC=$(cat "$(IC base-CONTEXT.txt)" 2>/dev/null | tr -d ' \n\r' || true)
      if [ -n "$BC" ] && [ -n "$ROOT_GIT" ] && git -C "$ROOT_GIT" cat-file -e "$BC" 2>/dev/null \
         && git -C "$ROOT_GIT" cat-file blob "$BC" > "$TMPD/base-final" 2>/dev/null; then
        while IFS= read -r id; do
          [ -n "$id" ] && registra "AC-RENUMERADO final $id — estava na prosa e no gsd:acs da base selada ($(curto "$BC")) e sumiu dos dois no documento vigente"
        done < <(ac_perdidos "$TMPD/base-final" "$VIG")
      else
        echo "final: AC-RENUMERADO n/a (sem .base-CONTEXT.txt resolvível)"
      fi
      [ "$rcf" = 0 ] && [ "$coer_achados" = "$antes" ] && echo "final: coerência ok"
    fi
  fi

  if [ "$coer_rodou" = 1 ]; then
    cnt() { printf '%s' "$coer_achados" | { grep -c "^$1 " || true; }; }
    resumo_c="PROSA-BLOCO-DIVERGE=$(cnt PROSA-BLOCO-DIVERGE) BLOCO-INVALIDO=$(cnt BLOCO-INVALIDO) ID-DUPLICADO=$(cnt ID-DUPLICADO) DOC-INTENCAO-EXTRA=$(cnt DOC-INTENCAO-EXTRA) AC-RENUMERADO=$(cnt AC-RENUMERADO)"
    if [ "$erro_uso" = 1 ]; then echo "coerencia: erro (conferidor indisponível) — $resumo_c"
    elif [ -n "$coer_achados" ]; then echo "coerencia: falha ($resumo_c)"
    else echo "coerencia: ok ($resumo_c)"; fi
  fi
fi

# exit 2 (ausência de garantia) vence o 1: o chamador não pode ler «reprovou» como «conferiu».
codigo_saida() { if [ "$erro_uso" = 1 ]; then echo 2; else echo "$falha"; fi; }

# ── A5b — trava de ordem na saída ───────────────────────────────────────────────
if [ "$ORDEM" = 1 ]; then
  # O ciclo da ordem é derivado INDEPENDENTE da enumeração dos vereditos: uma fase com a
  # consultoria especializada pulada não tem `.vereditos-c*.txt` nenhum e ainda assim tem ciclo 0
  # com releitura e correção — é lá que a ordem pode quebrar sem ninguém ver.
  C="$CICLO"
  if [ -z "$C" ]; then
    # FM-F4RLR-10INT: o nome do arquivo agora pode carregar a letra da rodada
    # (`.releitura-c<N>b.json`, `.releitura-c<N>c.json`, …) — o número do CICLO continua
    # sendo só os dígitos logo após o `c`; a letra fica de fora da extração aqui.
    C=$(ciclos_de 'c*/releitura.json' letra | sort -n | tail -1)
  fi
  [ -n "$C" ] || C="$ultimo_ciclo"
  if [ -z "$C" ]; then
    C=$(ciclos_de 'c*/correcoes.aplicado' | sort -n | tail -1)
  fi
  [ -n "$C" ] || { echo "ordem: n/a (nenhum ciclo com releitura ou correção em $IN)"; exit "$(codigo_saida)"; }
  # FM-F4RLR-10INT: lê a rodada MAIS RECENTE do ciclo — a de letra mais alta
  # (.releitura-c<C>b.json, .releitura-c<C>c.json, …) quando existir, senão a normal
  # (.releitura-c<C>.json, 1ª rodada) — mesmo resolvedor do briefing-build.sh
  # (caminho_releitura), sem duplicar a lógica num 2º parser python.
  R=$(gad_fase_glob "$PD" "intent/c${C}[a-z]/releitura.json" | sort | tail -1)
  [ -n "$R" ] || R="$(IC "c$C/releitura.json")"
  A="$(IC "c$C/correcoes.aplicado")"
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
      echo "RELEITURA-ABERTA c$C — $(basename "$R") declara ok: false e nenhuma correção pós-releitura fechou a emenda (último ciclo: nenhum briefing seguinte vai cobrar)"
      falha=1
    fi
  fi
  if [ ! -f "$R" ]; then
    echo "ordem: n/a (sem $(basename "$R") — a ausência de releitura é problema de outro gate)"
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

exit "$(codigo_saida)"
