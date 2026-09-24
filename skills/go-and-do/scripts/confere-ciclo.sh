#!/usr/bin/env bash
# confere-ciclo.sh — piso mecânico contra omissão de achados em resumo de ciclo.
#
# Uso: confere-ciclo.sh <parecer-bruto.md> <resumo-do-ciclo(arquivo)>
#      confere-ciclo.sh --tabela [--perguntas MANIFESTO] [--vereditos ARQ]
#                       [--status-dir DIR] <parecer1.md> [parecer2.md ...]
#
#      confere-ciclo.sh --origem-vereditos <phase_dir> <C>
#
# 45(k)/J5 (F24.5) — PROVENIÊNCIA DO VEREDITO. O `.intent/.vereditos-c<C>.txt` é a única
# coisa que o fiscal da etapa 1 (confere-reconciliacao.sh) aceita como «este achado teve
# veredito». Na F24.5 o coordenador acrescentou três linhas a ele às 12:12, 57 min depois de o
# verificador do ciclo 1 ter fechado às 11:15 — honestamente declaradas no campo `classe`, mas
# escritas por quem julgava. Este modo fecha o arquivo: o verificador grava
# `.vereditos-c<C>.origem.json` {v, ciclo, run_id, agente, mode, ts, n_linhas, sha256} como
# último ato, e aqui o sha256 é recalculado. Divergiu = alguém escreveu depois.
#   Exit 0  — recibo presente e sha256 idêntico (ou ciclo sem vereditos: n/a).
#   Exit 1  — VEREDITO-SEM-ORIGEM (recibo ausente) ou VEREDITO-ALTERADO (sha divergente)
#             ou ROTA-DIVERGENTE (`mode` do recibo != `mode` da .rota-verificacao-c<C>.json).
#   Exit 2  — uso inválido.
#
# R8 (v2.2.0) — respostas dirigidas entram na MESMA contagem de brutos:
#   --perguntas   `.intent/.perguntas-c<C>.json` escrito pelo briefing-build.sh. Para
#                 cada Q do manifesto, por lane usável: `sim`/`incerto` = bruto;
#                 Q ausente, duplicada ou malformada = bruto `incerto` (nunca zero);
#                 `não` com evidência real = `nao_provisorio` — conta como bruto até o
#                 verificador sustentar a exclusão (contagem conservadora pré-rota, E5a).
#                 `não — N/A`/reticências/"porque não" = bruto `incerto`.
#   --vereditos   `.intent/runs/c<C>/<run_id>/vereditos-dirigidos.json`
#                 (`[{lane,qid,raw,verdict,evidence}]`): só `supported_no` com evidência
#                 tira a Q da contagem (vira `dirigida-excluida`).
#   --status-dir  diretório com os `.status-c<C>-<lane>.json` do roda-lanes.sh: lane
#                 `usable:false` não tem suas Q contadas (já é `sem_parecer`).
# A tabela ganha a coluna `elicitacao` (estrutural | dirigida | dirigida-ausente |
# nao_provisorio | nao_irrelevante_fundamentado | dirigida-excluida) e
# `achados_estruturais_total` JÁ INCLUI os dirigidos.
#   R4 (plano 3, 05/09): `não — irrelevante para o Goal: <efeito>, ver <AC-nn|R-n|arquivo:linha>`
#   ganha o rótulo `nao_irrelevante_fundamentado` e o contador `irrelevante_fundamentada` no
#   JSON; não pode ser rebaixada a `incerto`, mas CONTINUA contando até o `supported_no`.
#
# C7 (01/09) — coluna `categoria` própria. A tabela passou a ter 5 colunas:
#   | lane | linha | achado (trecho) | categoria | elicitacao |
# A tag da taxonomia (`[A-produto]`, `[B-viabilidade]`, … — ver prompts/categorias-achados.md)
# é extraída da linha COMPLETA do parecer, ANTES do truncamento em 100 caracteres, e sai
# sem colchetes na coluna `categoria`. Antes disso o confere-rotas.sh procurava a tag no
# trecho já cortado: se o revisor escrevesse a explicação antes da tag, o corte a
# descartava e o achado era acusado de "sem categoria" tendo categoria. Coluna vazia
# agora significa ausência de verdade. As linhas de resposta dirigida (R8) saem com a
# coluna vazia por desenho — a categoria delas nasce no verificador.
# A linha `achados_estruturais_total:` NÃO mudou de formato (registra-ciclo.sh a lê).
#
# P15 (01/09) — cancela `parecer_informe`. Um parecer com corpo substantivo (>= 12 linhas
# não vazias fora do frontmatter, do canário e do filtro RUIDO, ou >= 500 caracteres de
# corpo) e ZERO achados extraídos deixa de ser "0 achados": na F24.4 quatro pareceres reais
# da convergência (c4 agy/codex, c5 e c6 codex) saíram assim, e o decide-ciclo.sh leu o zero
# como convergência. A tabela ganha a linha `parecer_informe: <lane> devolver|reprovada`:
#   devolver  — 1ª vez no ciclo: o coordenador relança SÓ a lane com
#               `roda-lanes.sh … --reformata <lane>` (que grava o marcador
#               `pareceres/.reformat-<lane>-c<C>`);
#   reprovada — o marcador já existe (2ª vez): grava `.reformat-<lane>-c<C>.reprovada`, põe
#               `usable:false, rc_reason:parecer_informe` no `.status-c<C>-<lane>.json`
#               (com --status-dir) e um evento `incidente` no run-log (uma vez).
# Pareceres da convergência (`NN-planrev-parecer-…`) usam o marcador `.reformat-planrev-<lane>-c<C>`.
# `### Achado 0 — nenhum achado novo` é o gabarito de "zero achados, parecer válido": não
# conta como achado e não dispara a cancela (linha `sem_achado_novo: <lane>`).
#
# --tabela (v1.8.0): extrai dos pareceres o esqueleto dos achados estruturais em
# markdown (| lane | linha | trecho |) — piso de enumeração para a fusão do
# verificador: cada linha emitida precisa de destino na tabela final do ciclo.
# Mesma heurística de detecção do modo padrão; mesmo limite honesto (prosa pura
# sem marcador/ID/ref é indetectável). Exit 0 sempre que houver >=1 parecer legível.
#
# O que faz: extrai do parecer bruto tudo que é ESTRUTURALMENTE um achado
# (linhas/headings com marcador de severidade, IDs cN-XN, refs arquivo:linha em
# seções de risco) e confere se cada um tem rastro no resumo do ciclo
# (CYCLE_SUMMARY). Saída: coberto / NAO-COBERTO por achado + contagem final.
# Exit 0 = tudo coberto · exit 1 = há NAO-COBERTO (a regra do prompt manda ler
# o parecer bruto na íntegra) · exit 2 = uso/arquivo inválido.
#
# Limite honesto (por desenho): achado escrito em prosa pura, sem marcador, sem
# ID e sem ref de arquivo, é INDETECTÁVEL aqui — foi exatamente o caso do HIGH
# omitido no ciclo 2 da F20-ox (02/08). Por isso este script é o PISO, não o
# teto: qualquer NAO-COBERTO, contagem menor que a do parecer, ou série de
# achados em redução → leitura obrigatória do parecer bruto (regra no prompt).

set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gad-caminhos.sh"   # v2.10.1: caminhos da fase
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gsd-shim.sh" 2>/dev/null && trap 'gad_autoregistro "confere-ciclo.sh" "$?"' EXIT || true

SEV='HIGH|MEDIUM|LOW|CRITICAL|BLOCKER|ALTA|ALTO|M[ÉE]DIA|M[ÉE]DIO|BAIXA|BAIXO|CR[ÍI]TIC'

# extrai_achados <parecer>: linhas "nlinha:texto" dos achados estruturais.
# 1º os headings de achado (### 1. Titulo · ### Achado 1: ...) — formato real dos
# pareceres codex/agy; se o parecer não usa headings numerados, cai para bullets
# com severidade (qualquer caixa) ou IDs cN-XN. Prosa pura segue indetectável.
# Linhas que NÃO são achado (fix F22, 04/08 — exit 1 falso-positivo no ciclo 4):
# a linha do canário (prova_leitura:/PROVA-...) e rubricas de classificação de risco
# ("Nível Geral de Risco: LOW", "Overall Risk", "Risk Level") casavam nos padrões.
# Fix F24 (10/08): "- **Confiança:** alta" casava na SEV ("alta") e headings de SEÇÃO
# do parecer ("### 1. Parecer de Convergência...") casavam no padrão numerado —
# inflavam a tabela com ruído e escondiam a subcontagem dos achados reais.
# R1 (plano 3, 05/09): a linha de campo `vinculo_goal:` de cada achado cita AC-nn e, às
# vezes, o id de um achado anterior (`ver c1-02`) — no fallback sem headings ela seria
# contada como achado pelo padrão `cN-NN`. É campo do achado, não achado.
RUIDO='^[0-9]+:(prova_leitura:|.*\*\*Token de Leitura|.*PROVA-|[[:space:]]*[*-]?[[:space:]]*\*{0,2}vinculo_goal:)|n[íi]vel (geral )?de risco|risco geral|overall risk|risk level|confian[çc]a|^[0-9]+:#{2,4} +[0-9]+[.:] *(parecer|resumo|metodologia|conclus)'

# `### Achado 0 …` é o gabarito de "nenhum achado novo" (P15): sai da lista aqui.
ACHADO_ZERO='^[0-9]+:#{2,4} +Achado +0([^0-9]|$)'

extrai_achados() {
  local f="$1" h
  # "Achado N" vale com qualquer coisa depois do número — o formato real da F24
  # ("### Achado 6 [B-viabilidade] — ...") não tinha `.`/`:` e escapava da detecção
  h=$(grep -nE '^#{2,4} +(Achado +[0-9]+([ .:[]|$)|(Achado +)?([0-9]+[.:][^0-9]|[Cc][0-9]+-[0-9]+))' "$f" \
    | grep -viE '^[0-9]+:#{3,4} +[0-9.]*\s*(pontos? fortes|strengths|sugest|suggestion)' \
    | grep -viE "$RUIDO" | grep -vE "$ACHADO_ZERO")
  if [ -n "$h" ]; then printf '%s\n' "$h"; return; fi
  grep -inE "(^#{2,4} .*\\[?(${SEV})|^[*-] .*\`?\\*{0,2}(${SEV})|c[0-9]+-([a-z]+)?[0-9]+)" "$f" \
    | grep -viE '^\s*[0-9]+:\s*(#{2,4} )?[0-9.]*\s*(pontos? fortes|strengths|sugest|suggestion)' \
    | grep -viE "$RUIDO" | grep -vE "$ACHADO_ZERO"
}

# tem_achado_zero <parecer>: o revisor declarou literalmente que não há achado novo.
tem_achado_zero() { grep -qE '^#{2,4} +Achado +0([^0-9]|$)' "$1"; }

# parecer_substantivo <parecer>: corpo fora do frontmatter, do canário e do RUIDO com
# >= 12 linhas não vazias OU >= 500 caracteres. O piso de linhas sozinho deixava passar os
# 4 pareceres reais da F24.4 (7-8 linhas longas, 665-2145 bytes) — por isso o segundo eixo.
parecer_substantivo() {
  local corpo n c
  corpo=$(awk 'NR==1 && $0=="---"{fm=1; next} fm && $0=="---"{fm=0; next} !fm' "$1" \
    | grep -n . | grep -viE "$RUIDO" | sed 's/^[0-9]*://')
  n=$(printf '%s\n' "$corpo" | grep -c .)
  c=$(printf '%s' "$corpo" | wc -m | tr -d ' ')
  [ "$n" -ge 12 ] || [ "$c" -ge 500 ]
}

# cancela_parecer_informe <parecer> <lane> <ciclo> <status-dir|""> → ecoa a linha da tabela
cancela_parecer_informe() {
  local p="$1" lane="$2" c="$3" sd="$4" dir fam marc rep pd nn etapa st
  dir=$(dirname -- "$p"); pd=$(dirname -- "$dir")
  nn=$(basename -- "$p" | sed -E 's/^([0-9.]+)-.*$/\1/')
  fam=""; etapa="1 intencao"
  case "$(basename -- "$p")" in *-planrev-*) fam="planrev-"; etapa="2.5 convergencia" ;; esac
  marc="$(gad_fase_caminho "$pd" "lanes/reformat-${fam}${lane}-c${c}")"; rep="$marc.reprovada"
  if [ ! -e "$marc" ]; then
    echo "parecer_informe: ${lane} devolver"
    return 0
  fi
  echo "parecer_informe: ${lane} reprovada"
  if [ -n "$sd" ]; then
    st="$(gad_fase_arq_da_base "$sd" "intent/c${c}/status-${lane}.json")"
    if [ -s "$st" ] && jq -e . "$st" >/dev/null 2>&1; then
      jq -c '.usable=false | .independent=false | .rc_reason="parecer_informe"' "$st" > "$st.tmp" \
        && mv -f "$st.tmp" "$st"
    fi
  fi
  if [ ! -e "$rep" ]; then
    : > "$rep"
    bash "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/run-log.sh" "$pd" "$nn" incidente "$etapa" \
      --kv origem=confere-ciclo.sh --kv detalhe="lane ${lane} c${c}: parecer sem achados 2×" >/dev/null 2>&1 || true
  fi
}

if [ "${1:-}" = "--origem-vereditos" ]; then
  PD="${2:-}"; C="${3:-}"
  [ -n "$PD" ] && [ -n "$C" ] || { echo "uso: confere-ciclo.sh --origem-vereditos <phase_dir> <C>" >&2; exit 2; }
  V="$(gad_fase_caminho "$PD" "intent/c$C/vereditos.txt")"
  O="$(gad_fase_caminho "$PD" "intent/c$C/vereditos.origem.json")"
  R="$(gad_fase_caminho "$PD" "intent/c$C/rota-verificacao.json")"
  if [ ! -f "$V" ]; then
    echo "origem_vereditos: n/a (sem .vereditos-c$C.txt)"; exit 0
  fi
  if [ ! -f "$O" ]; then
    echo "VEREDITO-SEM-ORIGEM c$C — .vereditos-c$C.txt existe sem .vereditos-c$C.origem.json (quem julgou não deixou recibo)"
    exit 1
  fi
  sha_disco=$(sha256sum "$V" | cut -d' ' -f1)
  sha_rec=$(jq -r '.sha256 // ""' "$O" 2>/dev/null || echo "")
  if [ "$sha_disco" != "$sha_rec" ]; then
    echo "VEREDITO-ALTERADO c$C — sha256 do arquivo ($sha_disco) != do recibo ($sha_rec): linha escrita depois de o verificador sair"
    exit 1
  fi
  modo_rec=$(jq -r '.mode // ""' "$O" 2>/dev/null || echo "")
  if [ -f "$R" ]; then
    modo_rota=$(jq -r '.mode // ""' "$R" 2>/dev/null || echo "")
    if [ -n "$modo_rota" ] && [ -n "$modo_rec" ] && [ "$modo_rec" != "$modo_rota" ]; then
      echo "ROTA-DIVERGENTE c$C — recibo diz mode=$modo_rec e .rota-verificacao-c$C.json diz mode=$modo_rota"
      exit 1
    fi
  fi
  echo "origem_vereditos: ok c$C (mode=$modo_rec, sha256 confere)"
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Modo --frescor (46 o, 45 m) — dente da regra «defeito conhecido se corrige ANTES do
# briefing seguinte» e de «replan não dispensa o juiz estrutural».
#
# Uso: confere-ciclo.sh --frescor <phase_dir> <NN> <ciclo>
# Saída: JSON de 1 linha
#   {"fase_dir":…, "ciclo":k, "briefing":…, "plan_mais_novo":…, "checker_mais_novo":…,
#    "veredito":"ok|falha|nao_se_aplica", "codigos":["BRIEFING-STALE","CHECKER-STALE",
#    "PREMISSA-CONHECIDA-SEM-CONSERTO"]}
# Exit: 0 ok/nao_se_aplica · 1 falha · 2 uso.
#
# Relógio = git, não mtime: um checkout/retomada reescreve mtime e falsearia o veredito
# (a fase 24.5 foi retomada em 10/09 e todos os mtimes mudaram). Só cai para mtime quando
# o arquivo não está no git — caso do briefing, que é untracked por desenho.
# nao_se_aplica: o ciclo 1 não tem ciclo anterior para ficar stale, e projeto com
# `plan_checker_enabled:false` não tem trilha .plan-checker/ — nos dois casos não se
# reprova por ausência.
# ═══════════════════════════════════════════════════════════════════════════════
if [ "${1:-}" = "--frescor" ]; then
  shift
  FPD="${1:-}"; FNN="${2:-}"; FK="${3:-}"
  [ -n "$FPD" ] && [ -d "$FPD" ] && [ -n "$FNN" ] && [ -n "$FK" ] \
    || { echo "uso: confere-ciclo.sh --frescor <phase_dir> <NN> <ciclo>" >&2; exit 2; }
  command -v jq >/dev/null || { echo "jq ausente" >&2; exit 2; }
  FROOT="$(cd "$FPD" && git rev-parse --show-toplevel 2>/dev/null || echo "")"

  # epoch de um caminho: data do último commit que o tocou; sem git, mtime.
  _fr_epoch() {
    local p="$1" e=""
    [ -e "$p" ] || { echo 0; return; }
    if [ -n "$FROOT" ]; then
      e="$(git -C "$FROOT" log -1 --format=%ct -- "$p" 2>/dev/null || true)"
    fi
    [ -n "$e" ] || e="$(stat -c %Y "$p" 2>/dev/null || echo 0)"
    echo "$e"
  }
  _fr_max() { # <glob...> → maior epoch e o caminho
    local melhor=0 quem="" f e
    for f in "$@"; do
      [ -e "$f" ] || continue
      e="$(_fr_epoch "$f")"
      if [ "$e" -gt "$melhor" ]; then melhor="$e"; quem="$f"; fi
    done
    printf '%s\t%s\n' "$melhor" "$quem"
  }

  # FM-F4RLR-01CONV: para iter-*.yaml o desempate NÃO pode ser a ordem alfabética do glob.
  # Causa real medida (não era iter9×iter10, que por acaso empata certo): quando dois
  # arquivos têm o MESMO epoch (commit em lote, comum no confere-etapa), _fr_max fica com
  # o primeiro do glob — e a ordem lexical de "iter-N.yaml" não é a ordem numérica de N
  # (ex.: iter-19.yaml < iter-2.yaml < iter-9.yaml alfabeticamente). Escolher pelo NÚMERO
  # da iteração, extraído do nome — nunca pela ordem em que o glob devolveu os arquivos.
  _fr_max_iter() { # <dir> → maior epoch e o caminho do iter-N.yaml de maior N
    local dir="$1" melhor=-1 quem="" f n
    while IFS= read -r f; do
      [ -e "$f" ] || continue
      n="$(basename "$f" .yaml)"; n="${n#iter-}"
      case "$n" in ''|*[!0-9]*) continue ;; esac
      if [ "$n" -gt "$melhor" ]; then melhor="$n"; quem="$f"; fi
    done < <(gad_fase_glob "$dir" 'plan-checker/iter-*.yaml')
    if [ -n "$quem" ]; then printf '%s\t%s\n' "$(_fr_epoch "$quem")" "$quem"
    else printf '0\t\n'; fi
  }

  # o briefing do ciclo k da convergência (untracked por desenho → mtime)
  FBRIEF="$FPD/pareceres/briefing-planrev-c$FK.md"
  [ -e "$FBRIEF" ] || FBRIEF="$(gad_fase_caminho "$FPD" "convergencia/c$FK/briefing.md")"

  IFS=$'\t' read -r PLAN_E PLAN_Q < <(_fr_max "$FPD"/*-PLAN.md)
  IFS=$'\t' read -r CHK_E  CHK_Q  < <(_fr_max_iter "$FPD")
  BRF_E=0; [ -e "$FBRIEF" ] && BRF_E="$(stat -c %Y "$FBRIEF" 2>/dev/null || echo 0)"

  FCOD='[]'; FVER=ok
  if [ "$PLAN_E" = 0 ]; then
    FVER=nao_se_aplica
  else
    # (ii) trilha do checker mais velha que o PLAN.md mais novo — só quando a trilha existe
    if [ "$CHK_E" != 0 ] && [ "$CHK_E" -lt "$PLAN_E" ]; then
      FCOD=$(jq -c '. + ["CHECKER-STALE"]' <<<"$FCOD"); FVER=falha
    fi
    # (i) briefing do ciclo k mais velho que o PLAN.md mais novo — só quando o briefing existe
    if [ "$BRF_E" != 0 ] && [ "$BRF_E" -lt "$PLAN_E" ]; then
      FCOD=$(jq -c '. + ["BRIEFING-STALE"]' <<<"$FCOD"); FVER=falha
    fi
    # (iii) incidente «premissa conhecida» sem commit de conserto anterior ao briefing
    FRL="$FPD/$FNN-RUN-LOG.jsonl"
    if [ -s "$FRL" ] && [ "$BRF_E" != 0 ] \
       && grep -q 'premissa conhecida' "$FRL" 2>/dev/null; then
      FCONS=0
      if [ -n "$FROOT" ]; then
        FCONS="$(git -C "$FROOT" log --format=%ct --since="@$((BRF_E-86400))" --until="@$BRF_E" \
                   --grep='^fix(' -- "$FPD" 2>/dev/null | head -1 || echo 0)"
      fi
      [ -n "$FCONS" ] || FCONS=0
      if [ "$FCONS" = 0 ]; then
        FCOD=$(jq -c '. + ["PREMISSA-CONHECIDA-SEM-CONSERTO"]' <<<"$FCOD"); FVER=falha
      fi
    fi
  fi

  jq -cn --arg pd "$FPD" --argjson k "$FK" --arg b "$FBRIEF" --arg p "$PLAN_Q" \
         --arg c "$CHK_Q" --arg v "$FVER" --argjson cod "$FCOD" \
    '{fase_dir:$pd, ciclo:$k, briefing:$b, plan_mais_novo:$p, checker_mais_novo:$c,
      veredito:$v, codigos:$cod}'
  [ "$FVER" = falha ] && exit 1
  exit 0
fi

if [ "${1:-}" = "--tabela" ]; then
  shift
  PERG=""; VERED=""; STATUSDIR=""; PARECERES=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --perguntas)  PERG="${2:-}";      shift 2 ;;
      --vereditos)  VERED="${2:-}";     shift 2 ;;
      --status-dir) STATUSDIR="${2:-}"; shift 2 ;;
      --*) echo "flag desconhecida: $1" >&2; exit 2 ;;
      *) PARECERES+=("$1"); shift ;;
    esac
  done
  [ "${#PARECERES[@]}" -ge 1 ] || { echo "uso: confere-ciclo.sh --tabela [--perguntas MAN] [--vereditos ARQ] [--status-dir DIR] <parecer.md> [...]" >&2; exit 2; }
  echo "| lane | linha | achado (trecho) | categoria | elicitacao |"
  echo "|---|---|---|---|---|"
  TOTAL=0
  LANES_TSV=""
  EXTRAS=()   # linhas parecer_informe:/sem_achado_novo: (saem depois do total)
  for P in "${PARECERES[@]}"; do
    [ -r "$P" ] || { echo "| $(basename "$P") | — | ILEGÍVEL |  | estrutural |"; continue; }
    # lane = último nome antes do -cN (fix F22: 22-parecer-plan-agy-c4.md → agy, não
    # plan; fix F24: 24-planrev-parecer-codex-c1.md → codex — o padrão antigo exigia
    # "NN-parecer-" no início e a lane virava o basename inteiro, zerando a contagem)
    LANE=$(basename "$P" | sed -E 's/^.*[-_]([a-z]+)-c[0-9]+\.md$/\1/; s/^[0-9]+-parecer-([a-z]+)[^a-z].*$/\1/; s/\.md$//')
    CICLO=$(basename "$P" | sed -nE 's/^.*-c([0-9]+)\.md$/\1/p')
    LANES_TSV="${LANES_TSV}${LANE}	${CICLO}	${P}
"
    LISTA=$(extrai_achados "$P")
    if [ -z "$LISTA" ]; then
      if tem_achado_zero "$P"; then
        EXTRAS+=("sem_achado_novo: ${LANE}")
      elif [ -n "$CICLO" ] && parecer_substantivo "$P"; then
        EXTRAS+=("$(cancela_parecer_informe "$P" "$LANE" "$CICLO" "$STATUSDIR")")
      else
        # FM-F4RLR-02CONV: zero achados, sem "Achado 0" declarado e sem corpo
        # substantivo — só vale como revisão se mostrar o que examinou. O teste
        # mecânico é: os caminhos `arquivo:linha` que o parecer cita EXISTEM no
        # repositório? Se cita ao menos um e nenhum existe, é MARCA (não descarte
        # automático — um parecer legítimo pode citar arquivo a criar), a lane vira
        # `sem_engajamento` e para de contar como revisor efetivo em revisores_efetivos
        # (grava-convergence.sh, fora desta lane, é quem consome o rótulo).
        FROOT_ENG="$(cd "$(dirname -- "$P")" && git rev-parse --show-toplevel 2>/dev/null || echo "")"
        CITADOS_ENG=$(grep -oP '(?<![/:])(?:[^\s:]*[/\\][^\s:]*|[^\s:]*\.[A-Za-z0-9]{1,16})(?=:[0-9]+)' \
          "$P" 2>/dev/null | sort -u || true)
        if [ -n "$CITADOS_ENG" ]; then
          ACHOU_ENG=0
          while IFS= read -r c; do
            [ -z "$c" ] && continue
            cp="$c"
            [ -n "$FROOT_ENG" ] && [ "${c#/}" = "$c" ] && cp="$FROOT_ENG/$c"
            [ -e "$cp" ] && { ACHOU_ENG=1; break; }
          done <<<"$CITADOS_ENG"
          # forma igual a `sem_achado_novo: <lane>` — grava-convergence.sh (lane B, fora
          # daqui) já sabe extrair o nome da lane com `sed 's/^sem_engajamento: //'`; o
          # motivo, livre-texto, entra numa 2ª linha para não quebrar esse parser.
          [ "$ACHOU_ENG" = 0 ] && EXTRAS+=("sem_engajamento: ${LANE}
# motivo: caminhos citados por ${LANE} não existem no repo")
        fi
      fi
    fi
    while IFS= read -r linha; do
      [ -n "$linha" ] || continue
      TOTAL=$((TOTAL+1))
      NL="${linha%%:*}"; TX="${linha#*:}"
      # Categoria: extraída da linha INTEIRA, antes de qualquer corte (C7). Sem colchetes.
      CAT=$(printf '%s' "$TX" | grep -oE '\[[A-E]-[A-Za-z0-9_-]+\]' | head -1 | tr -d '[]')
      # Truncamento em bash, não em `cut`: o `cut -c` do coreutils corta BYTES mesmo em
      # locale UTF-8 e parte caractere acentuado no meio — na F24.4 isso produziu byte
      # solto (`\xc3`) na tabela do planrev c2. A expansão `${var:0:100}` do bash conta
      # CARACTERES em locale UTF-8 (e, em locale C, degrada para o comportamento antigo,
      # nunca pior). Mesma ordem de antes: escapa o `|`, depois corta.
      TX=${TX//|/\\|}
      TX=${TX:0:100}
      echo "| ${LANE} | L${NL} | ${TX} | ${CAT} | estrutural |"
    done <<< "$LISTA"
  done

  # ── R8: respostas dirigidas viram brutos (sim/incerto/nao_provisorio) ───────
  DIR_JSON='{}'
  if [ -n "$PERG" ]; then
    DIR_OUT=$(GAD_MAN="$PERG" GAD_VER="$VERED" GAD_SD="$STATUSDIR" GAD_LANES="$LANES_TSV" \
      GAD_LIB="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib" \
      python3 - <<'PY'
import json, os, re, sys, unicodedata

MAN = os.environ["GAD_MAN"]; VER = os.environ.get("GAD_VER", "")
SD  = os.environ.get("GAD_SD", ""); LANES = os.environ.get("GAD_LANES", "")
sys.dont_write_bytecode = True
sys.path.insert(0, os.environ["GAD_LIB"])
import gad_caminhos  # v2.10.1: caminhos da fase (formato novo × antigo)

def norm(s):
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[\s*`_.,;:!?()\[\]-]+", " ", s).strip().lower()

resumo = {"brutas": 0, "excluidas": 0, "nao_provisorio": 0, "irrelevante_fundamentada": 0,
          "total": 0, "avisos": []}
linhas = []

try:
    with open(MAN, encoding="utf-8") as fh:
        man = json.load(fh)
    QIDS = list(man.get("qids") or [])
except Exception as e:
    # 5 colunas (C7): a coluna `categoria` sai vazia — dirigida não tem tag por desenho.
    print("| — | — | MANIFESTO ILEGÍVEL: %s |  | dirigida-ausente |" % e)
    resumo["brutas"] = 1
    resumo["avisos"].append("manifesto de perguntas ilegível")
    print(json.dumps(resumo, ensure_ascii=False))
    sys.exit(0)

# vereditos do gad-verificador: (lane, qid) -> verdict; duplicata invalida a entrada
VD, DUP = {}, set()
if VER:
    try:
        with open(VER, encoding="utf-8") as fh:
            dados = json.load(fh)
        itens = dados if isinstance(dados, list) else (dados.get("vereditos") or [])
        for it in itens:
            k = (it.get("lane"), it.get("qid"))
            if k in VD:
                DUP.add(k)
            VD[k] = it
    except Exception as e:
        resumo["avisos"].append("vereditos ilegíveis (%s) — todo `não` vira incerto" % e)

RE_Q = re.compile(r"^\s*(?:[-*+]\s*)?\*{0,2}\s*Q\s*(\d+)\s*\*{0,2}\s*[:：]\s*(.*)$",
                  re.IGNORECASE)
SEP  = re.compile(r"\s(?:—|–|--|-)\s")
FRACA = {"", "n a", "n/a", "na", "n/d", "nd", "nao", "nao aplicavel", "nao se aplica",
         "nenhuma", "nada", "porque nao", "pq nao", "obvio", "sem evidencia",
         "sem evidencias", "nao ha", "irrelevante"}
# R4 (plano 3) — "irrelevante, com evidência do Goal": a palavra sozinha continua vazia
# (fica em FRACA); com o efeito do Goal nomeado e uma citação (AC-nn, R-n, D-nn ou
# arquivo:linha) é resposta com lastro — ROTULADA aqui, julgada pelo verificador. O rótulo
# não tira a resposta da contagem: só `supported_no` com evidência faz isso (abaixo).
RE_IRRELEV_FORTE = re.compile(
    r"irrelevante\b.*\bgoal\b.*(?:AC-\d+|R-?\d+|D-\d+|[\w./-]+\.\w+:\d+)",
    re.IGNORECASE | re.DOTALL)

def le_respostas(path):
    """Linhas `- Q<n>: ...` da seção `## Respostas dirigidas` (fallback: arquivo todo)."""
    try:
        linhas_arq = open(path, encoding="utf-8").read().splitlines()
    except Exception:
        return {}, ["parecer ilegível: %s" % path]
    ini = None
    for i, l in enumerate(linhas_arq):
        if re.match(r"^#{1,6}\s*respostas dirigidas", norm(l)):
            ini = i + 1
            break
    avisos = []
    if ini is None:
        avisos.append("seção `## Respostas dirigidas` ausente em %s" % os.path.basename(path))
        trecho = list(enumerate(linhas_arq, 1))
    else:
        fim = len(linhas_arq)
        for j in range(ini, len(linhas_arq)):
            if re.match(r"^\s*#{1,2}\s+\S", linhas_arq[j]):
                fim = j
                break
        trecho = [(k + 1, linhas_arq[k]) for k in range(ini, fim)]
    out = {}
    for nl, l in trecho:
        m = RE_Q.match(l)
        if not m:
            continue
        qid = "Q%d" % int(m.group(1))
        out.setdefault(qid, []).append((nl, l.strip(), m.group(2)))
    return out, avisos

for entrada in LANES.strip().splitlines():
    partes = entrada.split("\t")
    if len(partes) != 3:
        continue
    lane, ciclo, path = partes
    if SD and ciclo:
        st = gad_caminhos.arq_da_base(SD, "intent/c%s/status-%s.json" % (ciclo, lane))
        if os.path.exists(st):
            try:
                if json.load(open(st, encoding="utf-8")).get("usable") is False:
                    resumo["avisos"].append("lane %s usable:false — Q não contam" % lane)
                    continue
            except Exception:
                resumo["avisos"].append("status da lane %s ilegível" % lane)
        else:
            resumo["avisos"].append("lane %s sem .status-c%s-%s.json" % (lane, ciclo, lane))

    respostas, avisos = le_respostas(path)
    resumo["avisos"].extend(avisos)
    vistos = set()

    for qid in QIDS + [q for q in respostas if q not in QIDS]:
        extra = qid not in QIDS
        if qid in vistos:
            continue
        vistos.add(qid)
        ocorr = respostas.get(qid, [])
        resumo["total"] += 1
        if not ocorr:
            linhas.append("| %s | — | %s NÃO RESPONDIDA (manifesto) |  | dirigida-ausente |"
                          % (lane, qid))
            resumo["brutas"] += 1
            continue
        nl, bruto, resto = ocorr[0]
        dup = len(ocorr) > 1
        m = SEP.split(resto, 1)
        cabeca = norm(m[0])
        evid = norm(m[1]) if len(m) > 1 else ""
        evid_bruto = m[1] if len(m) > 1 else ""   # sem norm(): o regex precisa do `:` e do `.`
        if cabeca in ("sim", "yes", "s"):
            r = "sim"
        elif cabeca in ("nao", "no", "n"):
            r = "nao"
        elif cabeca in ("incerto", "uncertain", "talvez", "maybe"):
            r = "incerto"
        else:
            r = "malformada"
        trecho = bruto.replace("|", "\\|")[:100]
        rot = "dirigida"
        conta = True
        if dup:
            r = "incerto"
            resumo["avisos"].append("%s/%s duplicada — vira incerto" % (lane, qid))
        if r == "nao":
            forte = bool(RE_IRRELEV_FORTE.search(evid_bruto))
            if forte:
                resumo["irrelevante_fundamentada"] = resumo.get("irrelevante_fundamentada", 0) + 1
            if not forte and (evid in FRACA or len(evid) < 3 or re.fullmatch(r"[. ]*", evid or ".")):
                r = "incerto"
            else:
                k = (lane, qid)
                v = VD.get(k)
                if VER and v and k not in DUP and v.get("verdict") == "supported_no" \
                   and str(v.get("evidence") or "").strip():
                    rot, conta = "dirigida-excluida", False
                    resumo["excluidas"] += 1
                else:
                    rot = "nao_irrelevante_fundamentado" if forte else "nao_provisorio"
                    resumo["nao_provisorio"] += 1
        if extra:
            resumo["avisos"].append("%s/%s fora do manifesto — contada assim mesmo" % (lane, qid))
        if conta:
            resumo["brutas"] += 1
        linhas.append("| %s | L%d | %s |  | %s |" % (lane, nl, trecho, rot))

for l in linhas:
    print(l)
print(json.dumps(resumo, ensure_ascii=False))
PY
) || { echo "ERRO: falha ao processar as respostas dirigidas" >&2; exit 2; }
    # linhas da tabela + última linha = JSON de resumo
    printf '%s\n' "$DIR_OUT" | sed '$d'
    DIR_JSON=$(printf '%s\n' "$DIR_OUT" | tail -1)
    NDIR=$(printf '%s' "$DIR_JSON" | sed -n 's/.*"brutas"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
    TOTAL=$((TOTAL + ${NDIR:-0}))
  fi
  echo
  echo "achados_estruturais_total: ${TOTAL}"
  [ -n "$PERG" ] && echo "dirigidas: $DIR_JSON"
  for x in ${EXTRAS[@]+"${EXTRAS[@]}"}; do [ -n "$x" ] && echo "$x"; done
  exit 0
fi

PARECER="${1:-}"; RESUMO="${2:-}"
[ -r "$PARECER" ] && [ -r "$RESUMO" ] || {
  echo "uso: confere-ciclo.sh <parecer-bruto.md> <resumo-do-ciclo>" >&2; exit 2; }


# 1) Linhas-achado do parecer (via extrai_achados: headings numerados primeiro,
#    fallback bullet-de-severidade/ID — formato real dos pareceres F20-ox, 02/08).
ACHADOS=$(extrai_achados "$PARECER")

if [ -z "$ACHADOS" ]; then
  if tem_achado_zero "$PARECER"; then
    echo "achados_estruturais: 0 (o parecer declara \`Achado 0 — nenhum achado novo\`)"
  elif parecer_substantivo "$PARECER"; then
    echo "achados_estruturais: 0 · parecer_informe (corpo substantivo sem achado no gabarito — devolva a lane com roda-lanes.sh --reformata)"
  else
    echo "achados_estruturais: 0 (nada detectável no parecer — aplique a regra de leitura do bruto)"
  fi
  exit 0
fi

TOTAL=0; NAOCOB=0
while IFS= read -r linha; do
  TOTAL=$((TOTAL+1))
  NLINHA="${linha%%:*}"; TEXTO="${linha#*:}"
  # 2) Tokens distintivos do achado: IDs, refs arquivo:linha, spans de código.
  TOKENS=$(printf '%s\n' "$TEXTO" | grep -oE 'c[0-9]+-[A-Z]+[0-9]*|[A-Za-z0-9_.-]+\.(ts|tsx|js|jsx|py|sh|mjs|cjs|md|sql|yml|yaml|json)(:[0-9]+)?|`[^`]{4,60}`' \
    | tr -d '`' | sort -u)
  COBERTO=false
  if [ -n "$TOKENS" ]; then
    while IFS= read -r t; do
      [ -n "$t" ] && grep -qF "$t" "$RESUMO" && { COBERTO=true; break; }
      # ref com :linha não bateu → tente só o arquivo (o resumo pode omitir a linha)
      base="${t%%:*}"
      [ "$base" != "$t" ] && grep -qF "$base" "$RESUMO" && { COBERTO=true; break; }
    done <<< "$TOKENS"
  fi
  if $COBERTO; then
    echo "coberto      L${NLINHA}: $(printf '%s' "$TEXTO" | cut -c1-90)"
  else
    NAOCOB=$((NAOCOB+1))
    echo "NAO-COBERTO  L${NLINHA}: $(printf '%s' "$TEXTO" | cut -c1-90)"
  fi
done <<< "$ACHADOS"

echo "---"
echo "achados_estruturais: ${TOTAL} · nao_cobertos: ${NAOCOB}"
[ "$NAOCOB" -eq 0 ] && exit 0 || exit 1
