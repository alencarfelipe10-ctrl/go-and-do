#!/usr/bin/env bash
# commita-artefatos.sh — commits mecânicos do fecho da fase (decisão 6.A: os blocos
# bash prontos do 6.3b e do 6.5 viram funções de script — escritor único: script
# commita, modelo não digita git).
#
# Uso: commita-artefatos.sh <phase_dir> <NN> <uat|runlog>
#   uat    — NN-UAT.md + uat-evidencia/ (árvore limpa pro preflight do ship; caminhos
#            explícitos — NUNCA git add de diretório .planning inteiro nem .err/.log).
#            Em uat-evidencia/, a seleção é EXPLÍCITA por extensão de evidência
#            legítima de UAT (conferido contra uat-playbook.md: browser_save_pdf
#            grava .pdf, browser_screenshot grava .png — nenhum outro artefato do
#            playbook é gravado nesse diretório). Arquivos ocultos e qualquer outra
#            extensão (.err/.log/.jsonl/.tmp/…) nunca entram. Teto de segurança: mais
#            de 20 arquivos na seleção → RECUSA, nada é adicionado, exit 1 (C4 —
#            é melhor falhar visível do que arrastar centenas de arquivos em silêncio).
#   runlog — NN-RUN-LOG.jsonl + NN-DECISOES.md (fecho da rodada, 6.5)
#
# Best-effort: sem git/nada staged → exit 0 com aviso (commit falhou não para fase).
# Exceção: o teto de segurança do uat-evidencia/ (acima) é falha DURA — exit 1.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; NN="${2:-}"; MODO="${3:-}"
[ -n "$PD" ] && [ -n "$NN" ] || { echo "uso: commita-artefatos.sh <phase_dir> <NN> <uat|runlog>" >&2; exit 2; }
ROOT="$(gad_project_root "$PD")"
cd "$ROOT"

STATUS=ok
case "$MODO" in
  uat)
    # Teto ANTES de qualquer git add: se recusar, o índice tem que sair vazio
    # (nem o NN-UAT.md entra) — falha visível e limpa, sem staging parcial.
    EVID=()
    if [ -d "$PD/uat-evidencia" ]; then
      mapfile -d '' -t EVID < <(find "$PD/uat-evidencia" -maxdepth 1 -type f \
        \( -iname '*.pdf' -o -iname '*.png' \) ! -name '.*' -print0)
    fi
    N=${#EVID[@]}
    if [ "$N" -gt 20 ]; then
      echo "RECUSA: uat-evidencia com $N arquivos — acima do teto de 20; selecione à mão" >&2
      gad_autoregistro "commita-artefatos.sh" 1 "uat: recusado ($N arquivos acima do teto)" || true
      gad_json_out commita-artefatos \
        "$(jq -cn --arg m "$MODO" --argjson n "$N" '{modo:$m, commit:"recusado", arquivos:$n}')" || true
      exit 1
    fi
    git add "$PD/$NN-UAT.md" 2>/dev/null || true
    if [ "$N" -gt 0 ]; then
      git add -- "${EVID[@]}" 2>/dev/null || true
    fi
    MSG="docs(fase $NN): artefatos do UAT (resultado + evidências)" ;;
  runlog)
    git add "$PD/$NN-RUN-LOG.jsonl" 2>/dev/null || true
    [ -f "$PD/$NN-DECISOES.md" ] && git add "$PD/$NN-DECISOES.md" 2>/dev/null || true
    MSG="docs(fase $NN): run-log e decisões da rodada" ;;
  *) echo "modo desconhecido: $MODO (uat|runlog)" >&2; exit 2 ;;
esac
if git diff --cached --quiet 2>/dev/null; then
  STATUS=nada_a_commitar
else
  git commit -m "$MSG" >/dev/null 2>&1 || STATUS=falhou
fi
gad_autoregistro "commita-artefatos.sh" 0 "$MODO: $STATUS" || true
gad_json_out commita-artefatos "$(jq -cn --arg m "$MODO" --arg s "$STATUS" '{modo:$m, commit:$s}')"
