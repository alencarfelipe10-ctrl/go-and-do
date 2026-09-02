#!/usr/bin/env bash
# confere-ciclo.sh — piso mecânico contra omissão de achados em resumo de ciclo.
#
# Uso: confere-ciclo.sh <parecer-bruto.md> <resumo-do-ciclo(arquivo)>
#      confere-ciclo.sh --tabela [--perguntas MANIFESTO] [--vereditos ARQ]
#                       [--status-dir DIR] <parecer1.md> [parecer2.md ...]
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
# nao_provisorio | dirigida-excluida) e `achados_estruturais_total` JÁ INCLUI os dirigidos.
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
RUIDO='^[0-9]+:(prova_leitura:|.*\*\*Token de Leitura|.*PROVA-)|n[íi]vel (geral )?de risco|risco geral|overall risk|risk level|confian[çc]a|^[0-9]+:#{2,4} +[0-9]+[.:] *(parecer|resumo|metodologia|conclus)'

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
  marc="$dir/.reformat-${fam}${lane}-c${c}"; rep="$marc.reprovada"
  if [ ! -e "$marc" ]; then
    echo "parecer_informe: ${lane} devolver"
    return 0
  fi
  echo "parecer_informe: ${lane} reprovada"
  if [ -n "$sd" ]; then
    st="$sd/.status-c${c}-${lane}.json"
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
      python3 - <<'PY'
import json, os, re, sys, unicodedata

MAN = os.environ["GAD_MAN"]; VER = os.environ.get("GAD_VER", "")
SD  = os.environ.get("GAD_SD", ""); LANES = os.environ.get("GAD_LANES", "")

def norm(s):
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[\s*`_.,;:!?()\[\]-]+", " ", s).strip().lower()

resumo = {"brutas": 0, "excluidas": 0, "nao_provisorio": 0, "total": 0, "avisos": []}
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
        st = os.path.join(SD, ".status-c%s-%s.json" % (ciclo, lane))
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
            if evid in FRACA or len(evid) < 3 or re.fullmatch(r"[. ]*", evid or "."):
                r = "incerto"
            else:
                k = (lane, qid)
                v = VD.get(k)
                if VER and v and k not in DUP and v.get("verdict") == "supported_no" \
                   and str(v.get("evidence") or "").strip():
                    rot, conta = "dirigida-excluida", False
                    resumo["excluidas"] += 1
                else:
                    rot = "nao_provisorio"
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
