#!/usr/bin/env bash
# reconciliar-marcadores.sh — Etapa 4.1 da close-phase em forma de script (muta E assere).
# Uso: reconciliar-marcadores.sh <project_root> <N> [--check] [--sweep]
#   (sem flag)  aplica as correções e assere no fim — exit 1 se algo continuar divergente
#   --check     só imprime a matriz de marcadores (nenhuma mutação); exit 1 se divergente
#   --sweep     além da fase N, varre TODOS os marcadores de pausa de fases já fechadas
#               (phases/ e milestones/) — "todo marcador de pausa cuja fase fechou é lixo"
#
# Por quê (auditoria F20, 27/07/2026): a 4.1 era prosa sem asserção — a mesma skill que
# verifica o flip da VERIFICATION (Sub-rotina P) não verificava nada da reconciliação.
# Três modos de falha reais: STATE.md frontmatter `status: executing` intocado (o comando
# usado escrevia o corpo; só o `phase complete` nativo move o frontmatter); HANDOFF.json da
# F19 sobrevivendo ao fecho da F20 (a regra antiga era "aponta para outra fase → não toque";
# o predicado certo é "a fase do handoff está FECHADA?"); contagens do .continue-here.md
# meio-corrigidas (duas obrigações numa frase → metade executada).
#
# VIA NATIVA PRIMEIRO (decisão do dono, 27/07): `gsd_run phase complete N` escreve
# ROADMAP + REQUIREMENTS + STATE atomicamente (incl. frontmatter `status`) e é idempotente
# (validado em sandbox: re-run não duplica o carimbo). Fallback manual só se ele falhar.

set -u
ROOT="${1:?uso: reconciliar-marcadores.sh <project_root> <N> [--check] [--sweep]}"
N="${2:?falta o número da fase}"
MODE="apply"; SWEEP=0
for a in "${@:3}"; do
  case "$a" in
    --check) MODE="check" ;;
    --sweep) SWEEP=1 ;;
  esac
done
cd "$ROOT" || { echo "ERRO: project_root inexistente: $ROOT"; exit 2; }
PL="$ROOT/.planning"
[ -d "$PL" ] || { echo "ERRO: $PL inexistente (não é projeto GSD)"; exit 2; }

# ── gsd-tools (mesma cadeia de shim da skill) ──────────────────────────────────
GSD=""
for c in "$ROOT/gsd-core/bin/gsd-tools.cjs" "$ROOT/.claude/gsd-core/bin/gsd-tools.cjs" \
         "$HOME/.claude/gsd-core/bin/gsd-tools.cjs"; do
  [ -f "$c" ] && GSD="$c" && break
done
gsd_run() { [ -n "$GSD" ] && node "$GSD" "$@" 2>/dev/null; }

# ── helpers ────────────────────────────────────────────────────────────────────
DIVERGENTES=()
CORRIGIDOS=()

roadmap_fechada() {  # fase $1 tem checkbox [x] no ROADMAP?
  grep -qE "^- \[x\] \*\*Phase ${1}[:.]" "$PL/ROADMAP.md" 2>/dev/null
}
verification_passed() {  # alguma VERIFICATION da fase $1 está passed?
  local d
  for d in "$PL"/phases/${1}-* "$PL"/phases/0${1}-* "$PL"/phases/*-${1}-*; do
    [ -d "$d" ] || continue
    grep -qE '^status:[[:space:]]*"?(passed|pass)"?' "$d"/*-VERIFICATION.md 2>/dev/null && return 0
  done
  return 1
}
fase_fechada() { roadmap_fechada "$1" || verification_passed "$1"; }

json_field() { python3 -c "
import json,sys
try: print(json.load(open(sys.argv[1])).get(sys.argv[2],''))
except Exception: print('')" "$1" "$2" 2>/dev/null; }

# ── 1. ROADMAP + STATE + REQUIREMENTS (via nativa) ─────────────────────────────
STATE_STATUS=$(grep -m1 -E '^status:' "$PL/STATE.md" 2>/dev/null | sed -E 's/^status:[[:space:]]*"?([a-zA-Z_-]+)"?.*/\1/')
STATE_CUR=$(grep -m1 -E '^current_phase:' "$PL/STATE.md" 2>/dev/null | sed -E 's/[^0-9.]*//g')
PRECISA_COMPLETE=0
if ! roadmap_fechada "$N"; then
  DIVERGENTES+=("ROADMAP: Phase $N sem checkbox [x]"); PRECISA_COMPLETE=1
fi
if [ "$STATE_CUR" = "$N" ] && [ "$STATE_STATUS" != "planning" ] && [ "$STATE_STATUS" != "complete" ]; then
  DIVERGENTES+=("STATE.md: current_phase=$N com status=$STATE_STATUS (fase fechada deveria ter transicionado)"); PRECISA_COMPLETE=1
fi
if [ "$MODE" = "apply" ] && [ "$PRECISA_COMPLETE" = "1" ]; then
  OUT=$(gsd_run phase complete "$N")
  if printf '%s' "$OUT" | grep -q '"roadmap_updated": *true'; then
    CORRIGIDOS+=("phase complete $N (nativo): ROADMAP+STATE+REQUIREMENTS")
    printf '%s\n' "$OUT" | grep -o '"warnings": *\[[^]]*\]' | grep -v '\[\]' | head -3
  else
    # fallback manual mínimo: checkbox do ROADMAP (o resto fica divergente e o assert acusa)
    HOJE=$(date +%F)
    sed -i -E "s/^- \[ \] (\*\*Phase ${N}[:.])/- [x] \1/" "$PL/ROADMAP.md" 2>/dev/null
    grep -qE "^- \[x\] \*\*Phase ${N}[:.]" "$PL/ROADMAP.md" \
      && CORRIGIDOS+=("ROADMAP: checkbox [x] via fallback manual (phase complete falhou — STATE pode seguir divergente)")
  fi
  gsd_run query state.sync >/dev/null
fi

# ── 2. marcadores de pausa (HANDOFF.json + .continue-here.md da raiz) ──────────
for M in "$PL/HANDOFF.json" "$PL/.continue-here.md"; do
  [ -e "$M" ] || continue
  case "$M" in
    *.json) P=$(json_field "$M" phase) ;;
    *)      P=$(grep -m1 -oE '(^phase:|Fase|phase)[[:space:]]*"?[0-9]+' "$M" 2>/dev/null | grep -oE '[0-9]+' | head -1) ;;
  esac
  if [ -z "$P" ]; then
    DIVERGENTES+=("$(basename "$M"): existe mas sem fase identificável — avalie à mão")
    continue
  fi
  if fase_fechada "$P"; then
    if [ "$MODE" = "apply" ]; then
      rm -f "$M" && CORRIGIDOS+=("$(basename "$M") removido (apontava para fase $P, já fechada)")
    else
      DIVERGENTES+=("$(basename "$M"): marcador de pausa da fase $P, que já está FECHADA")
    fi
  fi
done

# ── 3. .continue-here.md das pastas de fase ────────────────────────────────────
corrige_continue() {  # $1 = phase_dir  $2 = "arquivada?" (1 = milestone antigo)
  local d="$1" arq="${2:-0}" ch st tot
  ch="$d/.continue-here.md"; [ -f "$ch" ] || return 0
  st=$(grep -m1 -E '^status:' "$ch" | sed -E 's/^status:[[:space:]]*//')
  # fase do dir fechada? (arquivada em milestone = fechada por definição)
  if [ "$arq" = "1" ] || grep -qE '^status:[[:space:]]*"?(passed|pass)"?' "$d"/*-VERIFICATION.md 2>/dev/null; then
    tot=$(ls "$d"/*-SUMMARY.md 2>/dev/null | wc -l | tr -d ' ')
    tem_counts=0; grep -qE '^total_tasks:' "$ch" && tem_counts=1
    if [ "$MODE" = "apply" ]; then
      local mudou=0
      if [ "$st" != "resolved" ]; then
        if grep -qE '^status:' "$ch"; then
          sed -i -E '0,/^status:.*/s//status: resolved/' "$ch"
        elif [ "$(head -1 "$ch")" = "---" ]; then
          sed -i '1a status: resolved' "$ch"   # frontmatter sem campo status
        else
          # arquivo da era pré-frontmatter (prosa pura, caso INS-10): prepende um
          printf -- '---\nstatus: resolved\n---\n%s\n' "$(cat "$ch")" > "$ch"
        fi
        grep -qE '^status:[[:space:]]*resolved' "$ch" \
          && { CORRIGIDOS+=("$(basename "$d")/.continue-here.md: status → resolved"); mudou=1; }
      fi
      if [ "$tem_counts" = "1" ] && [ "$tot" -gt 0 ] 2>/dev/null; then
        if ! grep -qE "^total_tasks:[[:space:]]*$tot\$" "$ch" || ! grep -qE "^task:[[:space:]]*$tot\$" "$ch"; then
          sed -i -E "0,/^total_tasks:.*/s//total_tasks: $tot/" "$ch"
          sed -i -E "0,/^task:.*/s//task: $tot/" "$ch"
          CORRIGIDOS+=("$(basename "$d")/.continue-here.md: contagens → $tot/$tot (derivadas dos SUMMARY)")
          mudou=1
        fi
      fi
      # last_updated acompanha a edição — resolução com data velha mente sobre quando o
      # estado mudou (caso real F21, 28/07: 2 edições e o campo parado em 03:46Z)
      if [ "$mudou" = "1" ] && grep -qE '^last_updated:' "$ch"; then
        sed -i -E "0,/^last_updated:.*/s//last_updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)/" "$ch"
      fi
    else
      [ "$st" != "resolved" ] && DIVERGENTES+=("$(basename "$d")/.continue-here.md: status=${st:-ausente} numa fase fechada")
      if [ "$tem_counts" = "1" ] && [ "$tot" -gt 0 ] 2>/dev/null; then
        { ! grep -qE "^total_tasks:[[:space:]]*$tot\$" "$ch" || ! grep -qE "^task:[[:space:]]*$tot\$" "$ch"; } \
          && DIVERGENTES+=("$(basename "$d")/.continue-here.md: contagens ≠ $tot SUMMARYs no disco (fase fechada não pode afirmar pendência)")
      fi
    fi
  fi
}
# a fase N sempre; com --sweep, todas
for d in "$PL"/phases/${N}-* "$PL"/phases/0${N}-* "$PL"/phases/*-${N}-*; do
  [ -d "$d" ] && corrige_continue "$d" 0
done
if [ "$SWEEP" = "1" ]; then
  for d in "$PL"/phases/*/; do [ -d "$d" ] && corrige_continue "${d%/}" 0; done
  for d in "$PL"/milestones/*/*/; do [ -d "$d" ] && corrige_continue "${d%/}" 1; done
fi

# ── 4. asserção final (o que a 4.1 nunca teve) ─────────────────────────────────
FALHAS=()
roadmap_fechada "$N" || FALHAS+=("ROADMAP: Phase $N ainda sem [x]")
STATE_STATUS=$(grep -m1 -E '^status:' "$PL/STATE.md" 2>/dev/null | sed -E 's/^status:[[:space:]]*"?([a-zA-Z_-]+)"?.*/\1/')
STATE_CUR=$(grep -m1 -E '^current_phase:' "$PL/STATE.md" 2>/dev/null | sed -E 's/[^0-9.]*//g')
[ "$STATE_CUR" = "$N" ] && [ "$STATE_STATUS" != "planning" ] && [ "$STATE_STATUS" != "complete" ] \
  && FALHAS+=("STATE.md: status=$STATE_STATUS com current_phase=$N")
[ -e "$PL/HANDOFF.json" ] && { P=$(json_field "$PL/HANDOFF.json" phase); [ -n "$P" ] && fase_fechada "$P" && FALHAS+=("HANDOFF.json ainda aponta p/ fase fechada $P"); }
VALIDATE=$(gsd_run query state.validate | tr -d '\n' | head -c 200)

echo "── reconciliar-marcadores (fase $N, modo $MODE$([ $SWEEP = 1 ] && echo ' +sweep')) ──"
[ "${#CORRIGIDOS[@]}" -gt 0 ] && printf '  ✔ %s\n' "${CORRIGIDOS[@]}"
if [ "$MODE" = "check" ]; then
  [ "${#DIVERGENTES[@]}" -gt 0 ] && printf '  ✖ %s\n' "${DIVERGENTES[@]}" || echo "  ✔ nenhum marcador divergente"
  echo "  state.validate: ${VALIDATE:-indisponível}"
  [ "${#DIVERGENTES[@]}" -eq 0 ]; exit $?
else
  [ "${#FALHAS[@]}" -gt 0 ] && printf '  ✖ RESIDUAL: %s\n' "${FALHAS[@]}"
  echo "  state.validate: ${VALIDATE:-indisponível}"
  if [ "${#FALHAS[@]}" -eq 0 ]; then echo "  reconciliacao: ok"; exit 0
  else echo "  reconciliacao: parcial — reporte os residuais, não os esconda"; exit 1; fi
fi
