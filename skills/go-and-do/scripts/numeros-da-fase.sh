#!/usr/bin/env bash
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gsd-shim.sh" 2>/dev/null && trap 'gad_autoregistro "numeros-da-fase.sh" "$?"' EXIT || true
# numeros-da-fase.sh — números da fase com FONTE ESTRUTURAL (tarefa 24(b), 01/08/2026).
#
# Motivação: 3ª reincidência de número "de memória" no resumo executivo (F21: ordinal do
# plano · F2-rlr: "6 ondas" com frontmatters declarando 9, "20 planos desta rodada" quando
# 2 SUMMARYs eram da rodada anterior, baseline "71 passing" sem fonte). As regras escritas
# da v1.4.1/v1.4.2 estavam em vigor e não seguraram — instrução compete com o contexto e
# às vezes perde. Este script torna a fonte mecânica: computa do disco, e confere o texto.
#
# Uso: numeros-da-fase.sh <phase_dir> <NN>                  → imprime o bloco de números
#      numeros-da-fase.sh <phase_dir> <NN> --conferir <md>  → confere todo "N plano(s)" e
#                                                             "N onda(s)" citado no arquivo
#                                                             contra o disco; divergência →
#                                                             lista no stdout e exit 1
# Fora do --conferir nunca falha (exit 0) — mesma filosofia do run-log.sh.

dir="$1"; nn="$2"
[ -n "$dir" ] && [ -n "$nn" ] || { echo "uso: numeros-da-fase.sh <phase_dir> <NN> [--conferir <md>]"; exit 0; }
case "$dir" in
  /*) ;;
  *) _root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$_root" ] && dir="$_root/$dir" ;;
esac

plans=$(ls "$dir/$nn"-*-PLAN.md 2>/dev/null)
sums=$(ls "$dir/$nn"-*-SUMMARY.md 2>/dev/null)
n_plans=$(printf '%s\n' $plans | grep -c PLAN 2>/dev/null); [ -n "$plans" ] || n_plans=0
n_sums=$(printf '%s\n' $sums | grep -c SUMMARY 2>/dev/null); [ -n "$sums" ] || n_sums=0
n_gap=0; gap_sem_summary=0
for p in $plans; do
  if awk '/^---$/{c++} c==1 && /^gap_closure: true/{found=1} END{exit !found}' "$p" 2>/dev/null; then
    n_gap=$((n_gap+1))
    s="${p%-PLAN.md}-SUMMARY.md"
    [ -f "$s" ] || gap_sem_summary=$((gap_sem_summary+1))
  fi
done
# ondas: valores distintos de `wave:` no frontmatter dos PLANs
waves=$(for p in $plans; do awk '/^---$/{c++} c==1 && /^wave:/{print $2}' "$p" 2>/dev/null; done | sort -n -u)
n_waves=$(printf '%s\n' "$waves" | grep -c . 2>/dev/null)
max_wave=$(printf '%s\n' "$waves" | tail -n1)
waves_linha=$(printf '%s' "$waves" | tr '\n' ' ')
# SUMMARYs por dia (mtime) — separa "da fase" de "desta rodada"
por_dia=$(for s in $sums; do date -r "$s" +%F 2>/dev/null; done | sort | uniq -c | awk '{print $2": "$1}' | tr '\n' ';' | sed 's/;$//;s/;/ · /g')

if [ "${3:-}" = "--executores" ]; then
  # Medição PRIMÁRIA do paralelismo (46q): relógio dos transcripts dos executores, não o run-log.
  # O run-log depende do hook SubagentStop; o transcript existe sempre. Fonte de verdade quando os
  # dois discordam (F24.5: o medidor leu 78 min como «5 s»).
  # Uma fase RETOMADA tem mais de uma sessão, e os executores podem estar em qualquer uma delas
  # (F24.5: a sessão do run-log é a da retomada, `acd3c396`, e os 9 executores estão na original,
  # `1036b8fe`). Por isso varrem-se TODAS as pastas `*/subagents` do projeto e filtra-se pelo NN na
  # `description` do executor. `--sessao <id>` restringe a uma sessão quando se quiser.
  sess="${4:-}"; [ "$sess" = "--sessao" ] && sess="${5:-}"
  proj="$HOME/.claude/projects/$(printf '%s' "$(cd "$(dirname "$dir")" && git rev-parse --show-toplevel 2>/dev/null || echo "$dir")" | sed 's#/#-#g')"
  [ -d "$proj" ] || { echo "executores: projeto não localizado em $proj — medição primária indisponível"; exit 0; }
  SUB=$(ls -d "$proj"/*"$sess"*/subagents 2>/dev/null | tr '\n' ':')
  [ -n "$SUB" ] || { echo "executores: subagents/ não localizado (sessão ${sess:-todas}, projeto $proj) — medição primária indisponível"; exit 0; }
  python3 - "$SUB" "$nn" <<'PYEX'
import glob, json, os, sys
from datetime import datetime
subs = [x for x in sys.argv[1].split(":") if x]
nn = sys.argv[2]
linhas = []
for meta in sorted(m for s in subs for m in glob.glob(os.path.join(s, "*.meta.json"))):
    try:
        m = json.load(open(meta))
    except Exception:
        continue
    if m.get("agentType") != "gsd-executor":
        continue
    # só executores de PLANO DESTA FASE: os consertos pós-merge nascem com outra `description`
    # e não entram na conta de largura; executores de outra fase na mesma sessão, tampouco.
    desc = str(m.get("description", ""))
    if not desc.startswith("Execute plan ") or nn not in desc:
        continue
    j = meta[:-10] + ".jsonl"
    ts = []
    try:
        for ln in open(j, errors="replace"):
            i = ln.find('"timestamp":"')
            if i >= 0:
                ts.append(ln[i + 13:ln.find('"', i + 13)])
    except OSError:
        continue
    if not ts:
        continue
    t0, t1 = min(ts), max(ts)
    linhas.append((t0, t1, m.get("description", "?")))
linhas.sort()
print("== executores (medição primária: min/max de timestamp dos agent-*.jsonl) ==")
for t0, t1, d in linhas:
    dur = (datetime.fromisoformat(t1.replace("Z", "+00:00"))
           - datetime.fromisoformat(t0.replace("Z", "+00:00"))).total_seconds()
    print(f"{d}: {t0} -> {t1} ({int(dur/60)} min)")
# simultâneos reais: maior nº de janelas sobrepostas
evs = []
for t0, t1, _ in linhas:
    evs.append((t0, 1)); evs.append((t1, -1))
evs.sort()
cur = mx = 0
for _, d in evs:
    cur += d; mx = max(mx, cur)
print(f"simultaneos_max_primario: {mx} (de {len(linhas)} executores)")

# (47f) minutos em largura 1: soma dos intervalos com exatamente um executor aberto.
marcos = sorted({t for t0, t1, _ in linhas for t in (t0, t1)})


def n_abertos(t):
    return sum(1 for t0, t1, _ in linhas if t0 <= t < t1)


larg1 = larg0 = total = 0.0
for a, b in zip(marcos, marcos[1:]):
    dt = (datetime.fromisoformat(b.replace("Z", "+00:00"))
          - datetime.fromisoformat(a.replace("Z", "+00:00"))).total_seconds()
    total += dt
    n = n_abertos(a)
    if n == 1:
        larg1 += dt
    elif n == 0:
        larg0 += dt
print(f"janela_executores_min: {int(total/60)}")
print(f"minutos_em_largura_1: {int(larg1/60)} ({int(100*larg1/total) if total else 0}% da janela)")
print(f"minutos_sem_executor: {int(larg0/60)} (host esperando gate, merge, suíte)")
PYEX
  exit 0
fi

# ── FJ-01ENC: radiografia dos gates ─────────────────────────────────────────
# A F4 RLR fechou com WR-09 aberto e 16 Info abertos, e os DOIS resumos executivos
# disseram que as rodadas «fecharam os avisos restantes» — o escritor narrou em prosa
# sem abrir o 04-REVIEW*. Aqui os vereditos dos gates saem prontos, no bloco que o
# escritor já é obrigado a copiar. Info vai como CONTAGEM (+ os IDs que o leitor
# declarou abertos), nunca como lista narrada.
# Leitores ÚNICOS: lib/review-maior.py (code review) · lib/riscos-aceitos.py (security) ·
# uat-fiscal.py (placar do UAT). Nenhum segundo parser.
LIBD="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
radiografia_gates() { # <phase_dir> <NN>
  local pd="$1" nn="$2" rv sec val uat
  echo "-- radiografia dos gates (FJ-01ENC — cite ID por ID, não «todos fechados») --"
  rv=$(python3 "$LIBD/lib/review-maior.py" "$pd" "$nn" 2>/dev/null) || rv=""
  if [ -n "$rv" ] && printf '%s' "$rv" | jq -e '.arquivo' >/dev/null 2>&1; then
    printf 'code_review_fonte: %s (iteração %s) · status: %s\n' \
      "$(jq -r '.arquivo' <<<"$rv")" "$(jq -r '.iteracao // "?"' <<<"$rv")" "$(jq -r '.status // "?"' <<<"$rv")"
    printf 'code_review_severidade: critical=%s warning=%s info=%s total=%s skipped=%s fixed=%s\n' \
      "$(jq -r '.critical // "n/d"' <<<"$rv")" "$(jq -r '.warning // "n/d"' <<<"$rv")" \
      "$(jq -r '.info // "n/d"' <<<"$rv")" "$(jq -r '.total // "n/d"' <<<"$rv")" \
      "$(jq -r '.skipped // "n/d"' <<<"$rv")" "$(jq -r '.fixed // "n/d"' <<<"$rv")"
    printf 'code_review_ids_abertos (%s): %s\n' \
      "$(jq -r '(.abertos//[])|length' <<<"$rv")" \
      "$(jq -r 'if ((.abertos//[])|length)==0 then "nenhum declarado aberto" else (.abertos|join(" ")) end' <<<"$rv")"
    printf 'code_review_abertos_fonte: %s\n' "$(jq -r '(.abertos_fonte//[])|join(" · ")' <<<"$rv")"
  else
    echo "code_review_fonte: nenhum ${nn}-REVIEW*.md na pasta da fase"
  fi
  sec="$pd/$nn-SECURITY.md"
  if [ -f "$sec" ]; then
    printf 'security_status: %s · threats_open: %s\n' \
      "$(grep -m1 '^status:' "$sec" | sed 's/^status: *//' || true)" \
      "$(grep -m1 '^threats_open:' "$sec" | sed 's/^threats_open: *//' || true)"
    local ra; ra=$(python3 "$LIBD/lib/riscos-aceitos.py" "$sec" 2>/dev/null) || ra='[]'
    printf 'security_riscos_aceitos (%s): %s\n' "$(jq 'length' <<<"$ra" 2>/dev/null || echo 0)" \
      "$(jq -r 'if length==0 then "nenhum" else map(.[0:60])|join(" · ") end' <<<"$ra" 2>/dev/null || echo '?')"
  else
    echo "security_status: sem $nn-SECURITY.md"
  fi
  val="$pd/$nn-VALIDATION.md"
  if [ -f "$val" ]; then
    printf 'validacao: status=%s nyquist_compliant=%s\n' \
      "$(grep -m1 '^status:' "$val" | sed 's/^status: *//' || true)" \
      "$(grep -m1 '^nyquist_compliant:' "$val" | sed 's/^nyquist_compliant: *//' || echo 'n/d')"
  else
    echo "validacao: sem $nn-VALIDATION.md"
  fi
  uat="$pd/$nn-UAT.md"
  if [ -f "$uat" ]; then
    printf 'uat_placar: %s\n' \
      "$(python3 "$LIBD/uat-fiscal.py" "$uat" "$pd" 2>/dev/null | jq -r '.summary_novo // "n/d"' 2>/dev/null || echo 'n/d')"
  else
    echo "uat_placar: sem $nn-UAT.md"
  fi
  # FJ-02INT (metade etapa 6): a fase que fechou com `intent_review: aprovado_com_ressalva`
  # tem as dívidas dessa ressalva como aceite pendente — mesma régua do WR-09 acima, ID por
  # ID. Leitor único: confere-cardinalidade.sh (medido.dividas.na_secao), o mesmo do FM-09INT.
  local ir="$pd/$nn-INTENT-REVIEW.md"
  if [ -f "$ir" ] && grep -qE '^intent_review: aprovado_com_ressalva' "$ir"; then
    local card cardrc=0; card=$(bash "$LIBD/confere-cardinalidade.sh" "$pd" "$nn" --json 2>/dev/null) || cardrc=$?
    jq -e . >/dev/null 2>&1 <<<"$card" || card='{"medido":{}}'
    printf 'intent_ressalva_dividas (%s): %s\n' \
      "$(jq -r '(.medido.dividas.na_secao//[])|length' <<<"$card")" \
      "$(jq -r 'if ((.medido.dividas.na_secao//[])|length)==0 then "nenhuma nomeada (ressalva sem dívida)" else (.medido.dividas.na_secao|join(" ")) end' <<<"$card")"
  fi
}

if [ "$3" != "--conferir" ]; then
  echo "== numeros-da-fase (fonte estrutural — copie DAQUI, nunca de memória) =="
  echo "planos_total (PLAN.md no disco): $n_plans"
  echo "planos_com_summary: $n_sums"
  echo "planos_gap_closure: $n_gap (sem SUMMARY: $gap_sem_summary)"
  echo "planos_originais (total - gap): $((n_plans - n_gap))"
  echo "ondas_distintas (frontmatter wave): $n_waves — valores: ${waves_linha:-nenhum}"
  echo "summaries_por_dia (mtime): ${por_dia:-nenhum} — 'desta rodada' = só os do(s) dia(s) da rodada"
  echo "testes: NÃO derivável daqui — cite contagem de testes SÓ com fonte nomeada (arquivo/log + ponteiro)"
  radiografia_gates "$dir" "$nn"
  exit 0
fi

# ── modo --conferir ─────────────────────────────────────────────────────────
alvo="$4"
[ -f "$alvo" ] || { echo "conferir: arquivo inexistente ($alvo)"; exit 0; }
falhas=0
# (46b) contagem × enumeração: "8 linhas:" seguido de 7 bullets. Na F24.5 o
# NN-RELATORIOS-EVIDENCIA.md dizia «8 linhas» e enumerava 7, e a frase foi ao prompt do UAT intacta.
#
# Escopo estreitado depois de medir (11/09): a forma «número em QUALQUER linha × itens da seção ##
# inteira» dava 96 acusações em 19 dos 39 artefatos da 24.5 — ruído, não achado. A regra que fica é
# a que reproduz o caso real e só ele: a frase tem de TERMINAR em `:` (é uma introdução de lista) e
# a lista tem de começar nas duas linhas seguintes; conta-se o bloco CONTÍGUO de itens, não a seção.
python3 - "$alvo" <<'PYCONT' || falhas=$((falhas+1))
import re, sys
linhas = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
RE_N = re.compile(r"\b([0-9]{1,3}) (linhas?|itens?|achados?|testes?|arquivos?|cen[áa]rios?|alunos?)\b", re.I)
RE_IT = re.compile(r"^\s*(?:[-*]|[0-9]+\.)\s+\S")
ruim = 0
for i, l in enumerate(linhas):
    if not l.rstrip().endswith(":"):
        continue
    m = RE_N.search(l)
    if not m:
        continue
    j = i + 1
    while j < len(linhas) and j <= i + 2 and not linhas[j].strip():
        j += 1
    if j >= len(linhas) or not RE_IT.match(linhas[j]):
        continue
    itens = 0
    while j < len(linhas) and (RE_IT.match(linhas[j]) or linhas[j].startswith(("  ", "\t"))):
        if RE_IT.match(linhas[j]):
            itens += 1
        j += 1
    if itens and int(m.group(1)) != itens:
        print(f"CONTAGEM-x-ENUMERACAO {sys.argv[1]}:{i + 1} «{m.group(0)}» × {itens} item(ns) na lista que ela introduz")
        ruim += 1
sys.exit(1 if ruim else 0)
PYCONT

# conjuntos válidos: contagens estruturais + parciais por dia
validos_planos="$n_plans $n_sums $n_gap $((n_plans - n_gap))"
for d in $(for s in $sums; do date -r "$s" +%F 2>/dev/null; done | sort | uniq -c | awk '{print $1}'); do
  validos_planos="$validos_planos $d"
done
validos_ondas="$n_waves $max_wave"
while read -r m; do
  num="${m%% *}"; palavra="${m#* }"
  case "$palavra" in
    plano*) conjunto="$validos_planos"; rotulo="planos" ;;
    onda*)  conjunto="$validos_ondas";  rotulo="ondas"  ;;
  esac
  hit=0
  for v in $conjunto; do [ "$num" = "$v" ] && hit=1; done
  if [ "$hit" -eq 0 ]; then
    echo "⚠️ DIVERGÊNCIA: \"$m\" no resumo não bate com nenhuma fonte estrutural de $rotulo (válidos: $conjunto)"
    falhas=$((falhas+1))
  fi
done < <(grep -oE '[0-9]+ (planos?|ondas?)' "$alvo" | sort -u)

# ── FJ-F27INS-02ENC: sobras desejáveis (por código) e «como desfazer» das decisões ──
# automáticas — só sobre o RESUMO EXECUTIVO em modo final (é ele que traz a seção de
# transparência das decisões e é ele que o dono lê no hand-back); outro alvo (ex.: as
# bancadas com bom.md/ruim.md/enum.md) não entra nesta régua nova.
case "$alvo" in
  *-RESUMO-EXECUTIVO.md)
    if grep -qm1 '^go_and_do_resumo: final' "$alvo" 2>/dev/null; then
      verif="$dir/$nn-VERIFICATION.md"
      if [ -f "$verif" ]; then
        secao=$(awk '/^## Desejáveis pendentes/{f=1;next} /^#{1,2} /{if(f)exit} f' "$verif")
        if [ -n "$secao" ] && ! printf '%s\n' "$secao" | grep -qiE '^[[:space:]]*(Todos os desej[áa]veis[^.]*\.[[:space:]]*)?\*{0,2}Nenhum desej[áa]vel pendente\b'; then
          for ac in $(printf '%s\n' "$secao" | grep -oE 'AC-[0-9]+' | sort -u); do
            if ! grep -qF "$ac" "$alvo"; then
              echo "⚠️ SOBRA-AUSENTE: $ac está na \"## Desejáveis pendentes\" do $nn-VERIFICATION.md mas não aparece (pelo código) no resumo"
              falhas=$((falhas+1))
            fi
          done
        fi
      fi
      dec="$dir/$nn-DECISOES.md"
      if [ -f "$dec" ]; then
        n_desfazer=$(grep -cE '^[[:space:]]*Desfazer:' "$dec" 2>/dev/null); n_desfazer=${n_desfazer:-0}
        n_no_resumo=$(grep -cio 'desfaz' "$alvo" 2>/dev/null); n_no_resumo=${n_no_resumo:-0}
        if [ "$n_desfazer" -gt 0 ] && [ "$n_no_resumo" -eq 0 ]; then
          echo "⚠️ DESFAZER-AUSENTE: $nn-DECISOES.md tem $n_desfazer decisão(ões) automática(s) com \"Desfazer:\" mas o resumo não traz nenhum \"como desfazer\""
          falhas=$((falhas+1))
        fi
      fi
    fi
    ;;
esac

if [ "$falhas" -eq 0 ]; then
  echo "conferir: OK — todo \"N planos/ondas\" do documento bate com o disco"
  exit 0
fi
echo "conferir: $falhas divergência(s) — corrija com o bloco do numeros-da-fase.sh e regere/emende"
exit 1
