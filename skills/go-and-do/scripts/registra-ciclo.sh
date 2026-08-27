#!/usr/bin/env bash
# registra-ciclo.sh — apêndice por-ciclo no NN-REVIEWS.md (decisão 2.5-D).
#
# O registro do ciclo é gravado no fim DO CICLO, não só no fecho — uma convergência que
# não fecha (caso 21/07: ~100min sem CONVERGENCE.md) não pode deixar os ciclos que
# rodaram sem rastro de modelo em artefato. Junta as evidências mecânicas dos espelhos
# dos roda-* + a tabela anti-omissão do confere-ciclo.sh.
#
# Uso: registra-ciclo.sh <phase_dir> <NN> <ciclo>
# Lê:  pareceres/.roda-codex-c<k>.json · pareceres/.roda-agy-c<k>.json (os que existirem)
#      + o frontmatter `models:`/`model_sources:` do NN-REVIEWS.md, se o workflow do GSD
#        o escreveu (1.11.0 #2295 — só nasce quando a lane rodou pelo review-lane-runner;
#        nas nossas lanes via roda-*.sh ele vem `unknown` ou ausente, e a evidência é a nossa)
#      + aterramento por citação (1.11.0 #3194): `citacoes_fonte` do JSON ou o carimbo
#        `[reviewed-without-source-citations]` no topo do parecer (quando o runner rodou)
# Grava: apêndice em <phase_dir>/NN-REVIEWS.md · pareceres/.tabela-c<k>.txt
# Exit 0 sempre que registrar; 2 = uso inválido.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; NN="${2:-}"; K="${3:-}"; ETAPA_SEL="${4:-}"
[ -n "$PD" ] && [ -n "$NN" ] && [ -n "$K" ] || { echo "uso: registra-ciclo.sh <phase_dir> <NN> <ciclo> [intencao|convergencia]" >&2; exit 2; }
PAR="$PD/pareceres"
REV="$PD/$NN-REVIEWS.md"

# tabela anti-omissão do ciclo (piso mecânico; a contagem de brutos vem DAQUI)
PARECERES=()
# dois batismos reais: NN-parecer-<lane>-cK.md (intenção) e NN-planrev-parecer-<lane>-cK.md
# (convergência — F24 ficou de fora do glob antigo e o registro saiu "0 brutos" verde).
# v2.1.9: o 4º argumento escolhe a FAMÍLIA — na F24.3 o c1 da convergência contou 10 brutos
# onde eram 2 porque o glob pegou também os pareceres do c1 da intenção (colisão de
# numeração). Sem o argumento: as duas famílias (compat) + aviso se ambas existirem.
FAM_INT=("$PAR/$NN-parecer-codex-c$K.md"         "$PAR/$NN-parecer-agy-c$K.md")
FAM_CONV=("$PAR/$NN-planrev-parecer-codex-c$K.md" "$PAR/$NN-planrev-parecer-agy-c$K.md")
case "$ETAPA_SEL" in
  intencao)     CANDIDATOS=("${FAM_INT[@]}") ;;
  convergencia) CANDIDATOS=("${FAM_CONV[@]}") ;;
  '')           CANDIDATOS=("${FAM_INT[@]}" "${FAM_CONV[@]}")
                _ni=0; _nc=0
                for f in "${FAM_INT[@]}";  do [ -s "$f" ] && _ni=1; done
                for f in "${FAM_CONV[@]}"; do [ -s "$f" ] && _nc=1; done
                [ "$_ni" = 1 ] && [ "$_nc" = 1 ] && echo "AVISO: c$K existe na intenção E na convergência — passe o 4º argumento (intencao|convergencia) para não misturar os brutos" >&2 ;;
  *) echo "uso: 4º argumento deve ser intencao|convergencia" >&2; exit 2 ;;
esac
for f in "${CANDIDATOS[@]}"; do
  [ -s "$f" ] && PARECERES+=("$f")
done
TABELA="$PAR/.tabela-c$K.txt"
if [ ${#PARECERES[@]} -gt 0 ]; then
  bash "$GAD_SCRIPTS_DIR/confere-ciclo.sh" --tabela "${PARECERES[@]}" > "$TABELA" 2>/dev/null || true
fi
BRUTOS=""
if [ -f "$TABELA" ]; then
  # contagem pela linha-total do próprio confere-ciclo (o grep antigo exigia lane
  # [a-z]+ pura e zerava quando a lane vinha com dígitos/hífens — guarda cega)
  BRUTOS=$(sed -n 's/^achados_estruturais_total: *//p' "$TABELA" | head -1 | tr -cd '0-9')
  [ -n "$BRUTOS" ] || BRUTOS=$( { grep -cE '^\| [^|]+ \| L?[0-9]+ \|' "$TABELA" || true; } | head -1 )
fi
: "${BRUTOS:=0}"
# guarda anti-cega: registrar um ciclo SEM parecer legível não pode parecer verde
if [ ${#PARECERES[@]} -eq 0 ]; then
  echo "AVISO: nenhum parecer legível para o ciclo $K em $PAR — contagem de brutos SEM MEDIÇÃO (não é zero)" >&2
fi

# modelo nativo do GSD (#2295): frontmatter `models:` do NN-REVIEWS.md, quando existe
nativo_modelo() { # <slug-gsd> → valor ou vazio
  [ -f "$REV" ] || return 0
  awk -v k="$1" '{sub(/\r$/,"")} NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit}
    /^models:/{m=1;next} /^[a-z_]+:/{m=0} m&&$1==k":"{sub(/^[^:]+: */,"");gsub(/"/,"");print;exit}' "$REV"
}
SEM_CITACAO=()
{
  echo
  echo "## Ciclo $K — registro mecânico (gad, $(date -Is))"
  echo
  for lane in codex agy; do
    J="$PAR/.roda-$lane-c$K.json"
    [ -s "$J" ] || continue   # -s, não -f: JSON de 0 bytes quebraria o jq sob set -e
    if [ "$lane" = codex ]; then
      echo "- **codex**: modelo_efetivo=\`$(jq -r '.modelo_efetivo' "$J")\` · fresco=$(jq -r '.fresco' "$J") · vazio=$(jq -r '.vazio' "$J")"
      b=$(jq -r '.banner // ""' "$J"); [ -n "$b" ] && echo "  - codex_model_evidencia: \`$b\`"
      NAT=$(nativo_modelo codex)
    else
      echo "- **agy**: prova_leitura=$(jq -r '.prova_leitura' "$J") · degradado=$(jq -r '.degradado' "$J") · vazio=$(jq -r '.vazio' "$J")"
      e=$(jq -r '.evidencia // ""' "$J"); [ -n "$e" ] && echo "  - agy_model_evidencia: \`$e\`"
      NAT=$(nativo_modelo antigravity)
    fi
    # modelo nativo (GSD #2295) × nossa evidência — o nativo só é informativo fora do runner
    if [ -n "$NAT" ]; then
      echo "  - ${lane}_modelo_nativo_gsd: \`$NAT\` (frontmatter models:, #2295)"
      [ "$NAT" = unknown ] && echo "  - 🔔 GSD não resolveu o modelo do $lane (unknown) — vale a evidência própria acima"
    fi
    # aterramento (GSD #3194): JSON do roda-* (nossa régua) OU carimbo do runner no parecer
    P=$(jq -r '.parecer // ""' "$J")
    CITA=$(jq -r 'if has("citacoes_fonte") then .citacoes_fonte else "n/a" end' "$J")
    if [ -s "$P" ] && grep -q "^> \\[reviewed-without-source-citations\\]" -- "$P"; then CITA=false; fi
    echo "  - ${lane}_citacoes_fonte: $CITA"
    if [ "$CITA" = false ]; then
      SEM_CITACAO+=("$lane")
      echo "  - ⚠️ [reviewed-without-source-citations] — revisou o texto colado, não o repositório: achados deste parecer são CORROBORAÇÃO, não sustentam ciclo novo sozinhos"
    fi
    jq -r '.sinos[]? | "  - 🔔 " + .' "$J"
  done
  if [ ${#PARECERES[@]} -eq 0 ]; then
    echo "- brutos na tabela do ciclo: **SEM MEDIÇÃO** (nenhum parecer legível — guarda não conta o que não leu)"
  else
    echo "- brutos na tabela do ciclo: $BRUTOS (\`pareceres/.tabela-c$K.txt\`)"
  fi
} >> "$REV"

if [ ${#PARECERES[@]} -eq 0 ]; then
  gad_autoregistro "registra-ciclo.sh" 1 "c$K registrado SEM parecer legível (brutos sem medição)" || true
else
  gad_autoregistro "registra-ciclo.sh" 0 "c$K registrado ($BRUTOS brutos)" || true
fi
SC=$(printf '%s\n' ${SEM_CITACAO[@]+"${SEM_CITACAO[@]}"} | jq -R . | jq -cs 'map(select(length>0))')
gad_json_out registra-ciclo "$(jq -cn --arg r "$REV" --arg t "$TABELA" --argjson b "$BRUTOS" --argjson sc "$SC" \
  '{reviews:$r, tabela:$t, brutos:$b, sem_citacao_fonte:$sc}')"
