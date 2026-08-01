#!/usr/bin/env bash
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

if [ "$3" != "--conferir" ]; then
  echo "== numeros-da-fase (fonte estrutural — copie DAQUI, nunca de memória) =="
  echo "planos_total (PLAN.md no disco): $n_plans"
  echo "planos_com_summary: $n_sums"
  echo "planos_gap_closure: $n_gap (sem SUMMARY: $gap_sem_summary)"
  echo "planos_originais (total - gap): $((n_plans - n_gap))"
  echo "ondas_distintas (frontmatter wave): $n_waves — valores: ${waves_linha:-nenhum}"
  echo "summaries_por_dia (mtime): ${por_dia:-nenhum} — 'desta rodada' = só os do(s) dia(s) da rodada"
  echo "testes: NÃO derivável daqui — cite contagem de testes SÓ com fonte nomeada (arquivo/log + ponteiro)"
  exit 0
fi

# ── modo --conferir ─────────────────────────────────────────────────────────
alvo="$4"
[ -f "$alvo" ] || { echo "conferir: arquivo inexistente ($alvo)"; exit 0; }
falhas=0
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
if [ "$falhas" -eq 0 ]; then
  echo "conferir: OK — todo \"N planos/ondas\" do documento bate com o disco"
  exit 0
fi
echo "conferir: $falhas divergência(s) — corrija com o bloco do numeros-da-fase.sh e regere/emende"
exit 1
