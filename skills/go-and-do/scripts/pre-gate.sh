#!/usr/bin/env bash
# pre-gate.sh — cerimônia obrigatória antes de um AskUserQuestion dentro da rodada (v2.5.4,
# 45p). 1) janela de silêncio → exit 1 com acao:pausa (a camada 0 vai para a Sub-rotina D);
# 2) commita os artefatos da fase por pathspec EXPLÍCITO (nunca .planning inteiro, nunca
# .err/.log); 3) grava .planning/.gad/last-pre-gate.json {ts, ts_epoch, head, pergunta}, que o
# hook gad-gate-guard.sh exige fresco (≤ 15 min, mesmo HEAD).
# Uso: pre-gate.sh <phase_dir> <NN> ["<pergunta em 1 linha>"]
# Saída: JSON 1 linha {acao:"pergunta"|"pausa", commit:<sha|null>, arquivos:<n>, marcador:<path>}
# Exit: 0 pode perguntar · 1 janela de silêncio (pausa) · 2 uso inválido. Commit que falha por
# nada staged não é erro (commit:null).
set -euo pipefail
shopt -s nullglob dotglob
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"
PD="${1:-}"; NN="${2:-}"; PERG="${3:-}"
[ -n "$PD" ] && [ -d "$PD" ] && [ -n "$NN" ] || { echo "uso: pre-gate.sh <phase_dir> <NN> [\"<pergunta>\"]" >&2; exit 2; }
ROOT="$(gad_project_root "$PD")"
ET=$(grep '"evento":"checkpoint"' "$PD/$NN-RUN-LOG.jsonl" 2>/dev/null | tail -n1 | sed -n 's/.*"etapa":"\([^"]*\)".*/\1/p'); : "${ET:=0 abertura}"

# 1) janela de silêncio
if ! bash "$GAD_SCRIPTS_DIR/janela-silencio.sh" >/dev/null 2>&1; then
  gad_runlog "$PD" "$NN" script "$ET" --kv script=pre-gate.sh --kv exit=1 --kv resumo="janela de silêncio: pausa" >/dev/null 2>&1 || true
  jq -cn --arg p "$PERG" '{acao:"pausa", motivo:"janela de silêncio (23h–07h): Sub-rotina D com a pergunta no handoff", pergunta:$p}'
  exit 1
fi

# 2) commit dos artefatos da fase (pathspec explícito)
ARQ=()
# v2.10.1 (57): os mesmos grupos pelo helper (formato da fase) — travas de gate, JSON/MD da
# pasta da intenção (no formato novo, também os das pastas de ciclo) e a trilha do checker;
# no formato novo entram ainda o marcador FORMATO e o .gitignore de lanes/.
_G=(); while IFS= read -r _f; do _G+=("$_f"); done < <(
  gad_fase_glob "$PD" 'gates/*.json'; gad_fase_glob "$PD" 'gates/*.txt'
  gad_fase_glob "$PD" 'intent/*.json'; gad_fase_glob "$PD" 'intent/*.md'
  [ "$(gad_fase_formato "$PD")" = novo ] || gad_fase_glob "$PD" 'intent/pre-spec-route.json'
  if [ "$(gad_fase_formato "$PD")" = novo ]; then
    gad_fase_glob "$PD" 'intent/c*/*.json'; gad_fase_glob "$PD" 'intent/c*/*.md'
    printf '%s\n' "$PD/.gad/FORMATO" "$PD/.gad/lanes/.gitignore"
  fi
  gad_fase_glob "$PD" 'plan-checker/*.yaml')
for f in "$PD"/*.md "$PD"/*.jsonl "$PD"/*.json "$PD"/*.txt "$PD"/pareceres/*.md ${_G[@]+"${_G[@]}"}; do
  case "$f" in *.err|*.log|*.tmp) continue ;; esac
  [ -f "$f" ] && ARQ+=("$f")
done
COMMIT=null; N=0
if [ "${#ARQ[@]}" -gt 0 ] && git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
  git -C "$ROOT" add -- "${ARQ[@]}" 2>/dev/null || true
  N=$(git -C "$ROOT" diff --cached --name-only | wc -l | tr -d ' ')
  if [ "$N" -gt 0 ]; then
    git -C "$ROOT" commit -q -m "docs(fase $NN): artefatos da fase antes do gate duro" >/dev/null 2>&1 \
      && COMMIT="\"$(git -C "$ROOT" rev-parse --short HEAD)\""
  fi
fi

# 3) marcador
gad_estado_garante "$ROOT"
M="$(gad_espelho_caminho "$ROOT" pre-gate)"
jq -cn --arg ts "$(date -Is)" --argjson e "$(date +%s)" --arg h "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo '')" \
  --arg p "$PERG" '{ts:$ts, ts_epoch:$e, head:$h, pergunta:$p}' > "$M"
gad_runlog "$PD" "$NN" script "$ET" --kv script=pre-gate.sh --kv exit=0 --kv resumo="pré-gate: $N arquivo(s) commitados" >/dev/null 2>&1 || true
jq -cn --argjson c "$COMMIT" --argjson n "$N" --arg m "$M" '{acao:"pergunta", commit:$c, arquivos:$n, marcador:$m}'
