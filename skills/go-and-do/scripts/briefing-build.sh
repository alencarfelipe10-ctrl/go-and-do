#!/usr/bin/env bash
# briefing-build.sh — monta o briefing dos revisores adversariais (decisões 1.6/1.7/1.8/1.9).
#
# O briefing deixa de ser redigido pelo coordenador: das peças, só a varredura reversa
# (e, no ciclo 2+, o "o que mudou") é julgamento — o resto é montagem. A missão tem
# texto CANÔNICO num lugar só (impossível nascer uma whitelist improvisada como a que
# ancorou o revisor na F21) e a taxonomia vem de prompts/categorias-achados.md (mesma
# régua do verificador).
#
# Uso: briefing-build.sh <phase_dir> <NN> <ciclo> [--varredura ARQ] [--mudancas ARQ]
#   --varredura  arquivo com a seção "Asserções existentes que esta fase falsifica"
#                (escrita pelo coordenador — único insumo de modelo do ciclo 1)
#   --mudancas   ciclo 2+: o que mudou desde o ciclo anterior + achados já resolvidos
#
# Monta <phase_dir>/.intent/briefing-c<C>.md com:
#   missão canônica + categorias · caminhos dos artefatos (dieta 1.9: SPEC/CONTEXT/
#   REQUIREMENTS ficam; ROADMAP vira trecho da fase N e adjacentes; PROJECT cortado) ·
#   livro-razão mecânico (grep 1:1 das decisões [auto] do SPEC/CONTEXT) · varredura ·
#   sinos lidos de .intent/ · LICOES-DE-INTENCAO.md com resposta obrigatória por lição ·
#   pedido de enumeração reversa + raio de explosão · canário de leitura (nonce gerado
#   AQUI, gravado em .intent/.prova-leitura-c<C>.txt; o valor nunca vai no briefing).
#
# Saída: JSON 1 linha + espelho PC-5. Exit 0 ok · 2 uso inválido.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; NN="${2:-}"; C="${3:-}"
[ -n "$PD" ] && [ -n "$NN" ] && [ -n "$C" ] || { echo "uso: briefing-build.sh <phase_dir> <NN> <ciclo> [--varredura ARQ] [--mudancas ARQ]" >&2; exit 2; }
shift 3
VARREDURA=""; MUDANCAS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --varredura) VARREDURA="${2:-}"; shift 2 ;;
    --mudancas)  MUDANCAS="${2:-}"; shift 2 ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done
[ -d "$PD" ] || { echo "ERRO: phase_dir inexistente: $PD" >&2; exit 2; }
ROOT="$(gad_project_root "$PD")"
mkdir -p "$PD/.intent"
OUT="$PD/.intent/briefing-c$C.md"
AVISOS=()

# ── canário de leitura: nonce nasce aqui, só no arquivo ──────────────────────
PROVA="$PD/.intent/.prova-leitura-c$C.txt"
NONCE="PROVA-$(od -An -N3 -tx1 /dev/urandom | tr -d ' ')"
echo "Token de prova de leitura do ciclo $C: $NONCE" > "$PROVA"

{
  echo "# Briefing da revisão adversarial de intenção — fase $NN, ciclo $C"
  echo
  echo "## Missão"
  echo
  echo "Leia os artefatos E o código real e tente derrubar as decisões desta fase."
  echo "Seu tempo de leitura é finito — gaste-o na ordem: (1º) o que faria o software"
  echo "errar em produção, trair um requisito ou abrir/deixar aberta uma brecha de"
  echo "segurança [Produto]; (2º) o que faria a execução da fase falhar ou exigir"
  echo "retrabalho [Viabilidade]; (3º) o resto. Reporte todo achado que encontrar,"
  echo "inclusive incertos — mas classifique cada um: \`A-produto\`, \`B-viabilidade\`,"
  echo "\`C-instrumentacao\`, \`D-documental\`, \`E-decisao-do-dono\` (marque a categoria"
  echo "no título do achado, ex.: \`### Achado 3 [A-produto] — ...\`). Achados C e D da"
  echo "mesma classe de erro: reporte como UM item de classe com a lista de ocorrências."
  echo "Não há número certo de achados — zero achados A é um resultado válido se a"
  echo "intenção estiver sólida. Cada achado com: alegação, evidência (arquivo:linha"
  echo "quando houver) e confiança (alta/média/baixa)."
  echo
  cat "$GAD_SCRIPTS_DIR/../prompts/categorias-achados.md" 2>/dev/null \
    || AVISOS+=("categorias-achados.md ausente")
  echo
  echo "## Prova de leitura (obrigatória)"
  echo
  echo "Abra \`$PROVA\` e transcreva o token dele na primeira linha do parecer, no"
  echo "formato \`prova_leitura: <token>\`."
  echo
  echo "## Artefatos (leia dos caminhos — qualquer arquivo do repositório é elegível)"
  echo
  echo "- \`$PD/$NN-SPEC.md\`"
  echo "- \`$PD/$NN-CONTEXT.md\`"
  [ -f "$ROOT/.planning/REQUIREMENTS.md" ] && echo "- \`$ROOT/.planning/REQUIREMENTS.md\`"
  echo "- Repositório sob revisão: \`$ROOT\`"
  echo
  # ROADMAP: trecho da fase e adjacentes (dieta 1.9 — só a entrada da fase importa)
  RM="$ROOT/.planning/ROADMAP.md"
  if [ -f "$RM" ]; then
    echo "## Trecho do ROADMAP (fase atual e vizinhas)"
    echo
    mapfile -t H < <(grep -n '^### Phase ' "$RM" | cut -d: -f1)
    ALVO=$(grep -n "^### Phase ${NN#0}[:.]" "$RM" | head -1 | cut -d: -f1 || true)
    [ -z "$ALVO" ] && ALVO=$(grep -n "^### Phase $NN[:.]" "$RM" | head -1 | cut -d: -f1 || true)
    if [ -n "$ALVO" ]; then
      ini=$ALVO; fim=$(wc -l < "$RM")
      for i in "${!H[@]}"; do
        if [ "${H[$i]}" = "$ALVO" ]; then
          [ "$i" -gt 0 ] && ini=${H[$((i-1))]}
          [ $((i+2)) -lt ${#H[@]} ] && fim=$(( ${H[$((i+2))]} - 1 ))
          break
        fi
      done
      sed -n "${ini},${fim}p" "$RM"
    else
      AVISOS+=("fase $NN não achada no ROADMAP — trecho omitido")
    fi
    echo
  fi
  # Livro-razão mecânico: enumeração 1:1 das decisões [auto]
  echo "## Livro-razão de decisões automáticas (enumeração mecânica 1:1)"
  echo
  n_auto=0
  for f in "$PD/$NN-SPEC.md" "$PD/$NN-CONTEXT.md"; do
    [ -f "$f" ] || continue
    while IFS= read -r l; do
      echo "- \`$(basename "$f"):${l%%:*}\` — ${l#*:}"
      n_auto=$((n_auto+1))
    done < <(grep -n '\[auto\]' "$f" || true)
  done
  [ "$n_auto" = 0 ] && echo "*(nenhuma linha \`[auto]\` nos artefatos)*"
  echo
  # Varredura reversa (insumo de modelo)
  if [ -n "$VARREDURA" ] && [ -f "$VARREDURA" ]; then
    echo "## Asserções existentes que esta fase falsifica (varredura reversa)"
    echo
    cat "$VARREDURA"
    echo
  else
    AVISOS+=("varredura reversa ausente do briefing")
  fi
  # Sinos dos filhos (lidos do disco — 1.5)
  for s in "$PD/.intent/".sinos-*.txt; do
    [ -f "$s" ] || continue
    echo "## Sinos de $(basename "$s" | sed 's/^\.sinos-//; s/\.txt$//')"
    echo
    cat "$s"
    echo
  done
  # Lições com resposta obrigatória por lição (1.9 — medição embutida)
  LIC="$ROOT/.planning/LICOES-DE-INTENCAO.md"
  if [ -f "$LIC" ]; then
    echo "## Lições de fases anteriores (RESPOSTA OBRIGATÓRIA)"
    echo
    echo "Para CADA lição abaixo, responda explicitamente no parecer, em uma linha:"
    echo "\"lição N: esta intenção repete o padrão? sim/não — porquê\". Sem a resposta"
    echo "por lição o parecer está incompleto."
    echo
    cat "$LIC"
    echo
  fi
  # Pedidos adversariais canônicos
  echo "## Enumeração reversa (pedido adversarial)"
  echo
  echo "Enumere toda asserção existente no repositório que as mudanças prescritas"
  echo "tornam falsa ou insatisfazível — inclusive em arquivos que os artefatos não"
  echo "citam. Qualquer lista de arquivos neste briefing é ponto de partida, não"
  echo "fronteira."
  echo
  echo "## Raio de explosão"
  echo
  echo "Qual é o raio de explosão real desta fase — o que ela toca de compartilhado,"
  echo "que contrato cria ou muda, o que não tem análogo no código, quem depende dela"
  echo "nas fases seguintes? A intenção subestima esse raio?"
  # Ciclo 2+: o que mudou (insumo de modelo; NUNCA releitura integral dos artefatos)
  if [ -n "$MUDANCAS" ] && [ -f "$MUDANCAS" ]; then
    echo
    echo "## Ciclo $C — o que mudou desde o ciclo anterior (não repita o já resolvido)"
    echo
    cat "$MUDANCAS"
  fi
} > "$OUT"

AV_JSON=$(printf '%s\n' ${AVISOS[@]+"${AVISOS[@]}"} | jq -R . | jq -cs 'map(select(length>0))')
gad_json_out briefing-build "$(jq -cn --arg b "$OUT" --arg p "$PROVA" \
  --argjson na "$n_auto" --argjson lin "$(wc -l < "$OUT")" --argjson av "$AV_JSON" \
  '{briefing:$b, prova_leitura:$p, decisoes_auto:$na, linhas:$lin, avisos:$av}')"
