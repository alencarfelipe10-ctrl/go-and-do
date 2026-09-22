#!/usr/bin/env bash
# commita-artefatos.sh — commits mecânicos do fecho da fase (decisão 6.A: os blocos
# bash prontos do 6.3b e do 6.5 viram funções de script — escritor único: script
# commita, modelo não digita git).
#
# Uso: commita-artefatos.sh <phase_dir> <NN> <uat|runlog|intencao>
#   uat    — NN-UAT.md + uat-evidencia/ (árvore limpa pro preflight do ship; caminhos
#            explícitos — NUNCA git add de diretório .planning inteiro nem .err/.log).
#            Em uat-evidencia/, a seleção é EXPLÍCITA por extensão de evidência
#            legítima de UAT (conferido contra uat-playbook.md: browser_save_pdf
#            grava .pdf, browser_screenshot grava .png — nenhum outro artefato do
#            playbook é gravado nesse diretório). Arquivos ocultos e qualquer outra
#            extensão (.err/.log/.jsonl/.tmp/…) nunca entram. Teto de segurança: mais
#            de 20 arquivos na seleção → RECUSA, nada é adicionado, exit 1 (C4 —
#            é melhor falhar visível do que arrastar centenas de arquivos em silêncio).
#   runlog — NN-RUN-LOG.jsonl + NN-DECISOES.md (fecho da rodada, 6.5) + evidência dura
#   evidencia — só a evidência dura (FM-06INT): .intent/, pareceres/, atestados
#            (.fence-*.ok), NN-RUN-LOG.jsonl, deferred-items.md e NN-DECISOES.md.
#            Medido na F4 RLR: 160 arquivos da pasta da fase — os selos dos ciclos 2/3/4,
#            os vereditos, os espelhos dos pareceres e os próprios atestados do fiscal —
#            nunca foram commitados; o run-log commitado tinha 49 linhas e o do disco 171.
#            Temporários (.tmp/.err/.log/.pyc/__pycache__/.tmp-parecer-*) nunca entram.
#
# Best-effort: sem git/nada staged → exit 0 com aviso (commit falhou não para fase).
# Exceção: o teto de segurança do uat-evidencia/ (acima) é falha DURA — exit 1.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; NN="${2:-}"; MODO="${3:-}"
[ -n "$PD" ] && [ -n "$NN" ] || { echo "uso: commita-artefatos.sh <phase_dir> <NN> <uat|runlog|intencao|evidencia>" >&2; exit 2; }
ROOT="$(gad_project_root "$PD")"
cd "$ROOT"

STATUS=ok

# ── FM-06INT: a evidência dura da fase ────────────────────────────────────────
# Uma fonte só para «o que a rodada tem obrigação de commitar». O fiscal
# (confere-etapa.sh, assert `pasta_da_fase_suja`) reprova exatamente este conjunto
# quando ele fica fora do git; tudo o mais ali é AVISO. Seleção sempre EXPLÍCITA —
# nunca `git add` de diretório do .planning inteiro.
gad_evidencia_dura() {
  local pd="$1" nn="$2" escopo="${3:-tudo}" f
  local -a ARQ=() DIRS=("$pd/.intent")
  # `sem_pareceres`: no modo `intencao` a seleção de pareceres/ já é explícita (só
  # `NN-parecer-*.md`) e um teste protege que o parecer da CONVERGÊNCIA
  # (`NN-planrev-parecer-*`) não entre no commit da intenção — ele é da etapa 2 e
  # entra no `evidencia`/`runlog` do fecho.
  [ "$escopo" = sem_pareceres ] || DIRS+=("$pd/pareceres")
  # .intent/ e pareceres/ inteiros, menos os temporários (medidos: .tmp-parecer-<lane>.md
  # some sozinho — FM-11INT — e .err/.log são ruído de execução, não evidência).
  local d
  for d in "${DIRS[@]}"; do
    [ -d "$d" ] || continue
    while IFS= read -r -d '' f; do ARQ+=("$f"); done < <(
      find "$d" -type f \
        ! -name '.tmp-parecer-*' ! -name '*.tmp' ! -name '*.err' ! -name '*.log' \
        ! -name '*.pyc' ! -path '*/__pycache__/*' -print0 2>/dev/null)
  done
  # Atestados do fiscal + run-log + dívidas + decisões (caminhos explícitos).
  while IFS= read -r -d '' f; do ARQ+=("$f"); done < <(
    find "$pd" -maxdepth 1 -type f -name '.fence-*.ok' -print0 2>/dev/null)
  for f in "$pd/$nn-RUN-LOG.jsonl" "$pd/deferred-items.md" "$pd/$nn-DECISOES.md" \
           "$ROOT/.planning/deferred-items.md"; do
    [ -f "$f" ] && ARQ+=("$f")
  done
  [ ${#ARQ[@]} -gt 0 ] || return 0
  # -f: o .gitignore do projeto costuma barrar dotdir; a evidência da fase é
  # deliberada e não pode sumir por causa de uma regra genérica.
  git add -f -- "${ARQ[@]}" 2>/dev/null || true
}

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
    # 46(p): o state.json do GSD muda durante a rodada e ficava modificado fora do commit
    # (árvore suja no preflight do ship, F24.5). Caminho explícito, nunca `git add .planning`.
    [ -f "$ROOT/.planning/state.json" ] && git add "$ROOT/.planning/state.json" 2>/dev/null || true
    gad_evidencia_dura "$PD" "$NN"
    MSG="docs(fase $NN): run-log, decisões e evidência da rodada" ;;
  evidencia)
    gad_evidencia_dura "$PD" "$NN"
    MSG="docs(fase $NN): evidência da rodada (intent, pareceres, atestados, run-log)" ;;
  intencao)
    # M6 (F24.5): `git commit --only` recusa arquivo NOVO (pareceres do 1º ciclo). `git add`
    # com pathspec explícito aceita novo e rastreado, e continua sem tocar no resto do
    # worktree sujo do usuário — que é o motivo de o `--only` ter sido escolhido em 2026-07.
    for f in "$PD/$NN-PRE-SPEC.md" "$PD/$NN-SPEC.md" "$PD/$NN-CONTEXT.md" "$PD/$NN-INTENT-REVIEW.md"; do
      [ -f "$f" ] && { git add -- "$f" 2>/dev/null || true; }
    done
    PAR=()
    if [ -d "$PD/pareceres" ]; then
      mapfile -d '' -t PAR < <(find "$PD/pareceres" -maxdepth 1 -type f \
        -name "$NN-parecer-*.md" ! -name '.*' -print0 2>/dev/null)
    fi
    [ ${#PAR[@]} -gt 0 ] && { git add -- "${PAR[@]}" 2>/dev/null || true; }
    gad_evidencia_dura "$PD" "$NN" sem_pareceres
    MSG="docs(fase $NN): consultoria especializada de intenção" ;;
  *) echo "modo desconhecido: $MODO (uat|runlog|intencao|evidencia)" >&2; exit 2 ;;
esac
if git diff --cached --quiet 2>/dev/null; then
  STATUS=nada_a_commitar
else
  git commit -m "$MSG" >/dev/null 2>&1 || STATUS=falhou
fi
gad_autoregistro "commita-artefatos.sh" 0 "$MODO: $STATUS" || true
gad_json_out commita-artefatos "$(jq -cn --arg m "$MODO" --arg s "$STATUS" '{modo:$m, commit:$s}')"
