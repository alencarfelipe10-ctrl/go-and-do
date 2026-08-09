#!/usr/bin/env bash
# dev-server.sh — sobe/derruba o dev server do projeto (decisões 4.B + adendo 09/08).
#
# Absorve a Sub-rotina B inteira: probe/uso/persistência de receita de launch
# (`run-<nome>/SKILL.md`, formato do /run-skill-generator nativo), heurística por tipo
# de projeto, waiter de prontidão, PID em disco, kill limpo da árvore. Bônus de
# construção: as restrições "nunca invocar /run nem /run-skill-generator" deixam de ser
# prosa vigiada — shell script não invoca skill por natureza.
#
# Uso: dev-server.sh up   [--projeto DIR] [--timeout S]
#      dev-server.sh down [--projeto DIR]
#
# up:  receita achada (grep ^description: com launch/subir/rodar/dev nos SKILL.md de
#      .claude/skills/*/ do dir até a raiz git) → usa comando/porta/env dela; sem
#      receita → heurística (Expo → web:8081 com CI=1 BROWSER=none; web comum → dev/
#      start em 3000/5173/8080) → espera a porta responder → SUCESSO SEM RECEITA →
#      persiste run-<nome>/SKILL.md com os valores constatados (P15). Estado em
#      .planning/.gad-dev-server.json (pid de grupo + porta).
# down: mata a ÁRVORE inteira (kill no process group — o Metro do Expo abre filhos).
#
# JSON: {status: up|ja_estava|falhou|down, porta, pid, receita, comando}. Exit 0 = ok ·
# 1 = não subiu no timeout (siga em code-only e registre a ressalva; no UAT, sem server
# os cenários de UI viram balde 3) · 2 = uso.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

ACAO="${1:-}"; shift || true
PROJ=""; TIMEOUT=90
while [ $# -gt 0 ]; do case "$1" in
  --projeto) PROJ="${2:-}"; shift 2 ;;
  --timeout) TIMEOUT="${2:-90}"; shift 2 ;;
  *) shift ;;
esac; done
ROOT="$(gad_project_root "${PROJ:-$PWD}")"
ESTADO="$ROOT/.planning/.gad-dev-server.json"
LOGF="$ROOT/.planning/.gad-dev-server.log"

porta_viva() { curl -sf -o /dev/null --max-time 2 "http://localhost:$1" 2>/dev/null || \
               curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://localhost:$1" 2>/dev/null | grep -qE '^[1-5]'; }

if [ "$ACAO" = down ]; then
  if [ -f "$ESTADO" ]; then
    PID=$(jq -r '.pid // empty' "$ESTADO")
    PORTA=$(jq -r '.porta // empty' "$ESTADO")
    # mata pela SESSÃO do setsid (pkill -s é escopado e seguro) + PID direto. NUNCA
    # derive pgid via ps (devolve o grupo do shell PAI — matar -pgid alheio derrubou
    # o orquestrador no aceite deste script).
    if [ -n "$PID" ]; then
      pkill -s "$PID" 2>/dev/null || true
      kill "$PID" 2>/dev/null || true
      sleep 1
    fi
    # cinto de segurança: sobrou listener na porta → mata pelo socket (a árvore do
    # Metro/npm nem sempre morre pelo pgid — provado no aceite deste script)
    if [ -n "$PORTA" ] && porta_viva "$PORTA" && command -v fuser >/dev/null 2>&1; then
      fuser -k "${PORTA}/tcp" >/dev/null 2>&1 || true
      sleep 1
    fi
    rm -f "$ESTADO"
    RESTO=false; [ -n "$PORTA" ] && porta_viva "$PORTA" && RESTO=true
    gad_json_out dev-server "$(jq -cn --argjson r "$RESTO" '{status:"down"} + (if $r then {aviso:"porta ainda responde — mate o processo manualmente"} else {} end)')"
  else
    gad_json_out dev-server '{"status":"down","nota":"nenhum estado — nada a derrubar"}'
  fi
  exit 0
fi
[ "$ACAO" = up ] || { echo "uso: dev-server.sh up|down [--projeto DIR] [--timeout S]" >&2; exit 2; }

# já de pé?
if [ -f "$ESTADO" ]; then
  P=$(jq -r '.porta // empty' "$ESTADO")
  if [ -n "$P" ] && porta_viva "$P"; then
    gad_json_out dev-server "$(jq -c '. + {status:"ja_estava"}' "$ESTADO")"
    exit 0
  fi
  rm -f "$ESTADO"
fi

# ── receita persistida (acelerador oportunista, não dependência) ─────────────
RECEITA=""; CMD=""; PORTAS=""; ENVS=""
d="$ROOT"
while :; do
  for sk in "$d"/.claude/skills/*/SKILL.md; do
    [ -f "$sk" ] || continue
    if grep -m1 '^description:' "$sk" | grep -qiE 'sobe|subir|rodar|launch|dev server|localhost'; then
      RECEITA="$sk"; break 2
    fi
  done
  [ "$d" = "$(dirname "$d")" ] && break
  git -C "$(dirname "$d")" rev-parse --show-toplevel >/dev/null 2>&1 || break
  d="$(dirname "$d")"
done
if [ -n "$RECEITA" ]; then
  CMD=$(grep -m1 -oE 'Comando: *`[^`]+`' "$RECEITA" | sed 's/Comando: *`//; s/`$//' || true)
  PORTAS=$(grep -m1 -oE 'Porta: *[0-9]+' "$RECEITA" | grep -oE '[0-9]+' || true)
  ENVS=$(grep -m1 -oE 'env: *[A-Z0-9_= ]+' "$RECEITA" | sed 's/env: *//' || true)
fi

# ── heurística (sem receita) ─────────────────────────────────────────────────
TIPO=""
if [ -z "$CMD" ]; then
  PKG="$ROOT/package.json"
  [ -f "$PKG" ] || { gad_json_out dev-server '{"status":"falhou","motivo":"sem receita e sem package.json — projeto não-Node? siga em code-only"}'; exit 1; }
  GER=npm
  [ -f "$ROOT/pnpm-lock.yaml" ] && GER=pnpm
  [ -f "$ROOT/yarn.lock" ] && GER=yarn
  [ -f "$ROOT/bun.lockb" ] && GER=bun
  if jq -e '.dependencies.expo // .devDependencies.expo' "$PKG" >/dev/null 2>&1 \
     || jq -r '.scripts // {} | to_entries[].value' "$PKG" 2>/dev/null | grep -q 'expo start'; then
    TIPO=expo; ENVS="CI=1 BROWSER=none"; PORTAS="8081 19006"; TIMEOUT=$(( TIMEOUT < 90 ? 90 : TIMEOUT ))
    if jq -r '.scripts.web // ""' "$PKG" | grep -q 'expo start --web'; then CMD="$GER run web"; else CMD="npx expo start --web"; fi
  else
    TIPO=web; PORTAS="3000 5173 8080"
    if jq -e '.scripts.dev' "$PKG" >/dev/null 2>&1; then CMD="$GER run dev"
    elif jq -e '.scripts.start' "$PKG" >/dev/null 2>&1; then CMD="$GER run start"
    else gad_json_out dev-server '{"status":"falhou","motivo":"package.json sem scripts dev/start"}'; exit 1; fi
  fi
fi

# ── sobe em process group próprio (o kill do down alcança a árvore) ──────────
( cd "$ROOT" && env $ENVS setsid bash -c "$CMD" >"$LOGF" 2>&1 </dev/null & echo $! > /tmp/.gad-ds-pid )
PID=$(cat /tmp/.gad-ds-pid); rm -f /tmp/.gad-ds-pid

# ── waiter de prontidão ──────────────────────────────────────────────────────
PORTA=""
fim=$(( $(date +%s) + TIMEOUT ))
while [ "$(date +%s)" -lt "$fim" ]; do
  for p in $PORTAS; do porta_viva "$p" && { PORTA="$p"; break 2; }; done
  kill -0 "$PID" 2>/dev/null || break   # processo morreu antes de abrir porta
  sleep 3
done
if [ -z "$PORTA" ]; then
  kill -- -"$PID" 2>/dev/null || true
  gad_json_out dev-server "$(jq -cn --arg c "$CMD" --arg l "$LOGF" \
    '{status:"falhou", comando:$c, motivo:"porta não respondeu no timeout — causas comuns: .env/banco/install ausente; deps de web do Expo (react-dom, react-native-web, @expo/metro-runtime)", log:$l}')"
  exit 1
fi

# ── persiste estado + receita (cold-start limpo sem receita → auto-persiste) ─
REC_STATUS=nenhuma
if [ -n "$RECEITA" ]; then
  REC_STATUS=usada
else
  NOME=$(jq -r '.name // "app"' "$ROOT/package.json" 2>/dev/null | tr -cd 'a-z0-9-'); : "${NOME:=app}"
  RD="$ROOT/.claude/skills/run-$NOME"
  if mkdir -p "$RD" 2>/dev/null; then
    cat > "$RD/SKILL.md" <<EOF
---
name: run-$NOME
description: Sobe o $NOME localmente para desenvolvimento/verificação (dev server em localhost:$PORTA)
---
# Como subir o $NOME
- Pré-requisitos: constatados no cold-start de $(date -I) (registre pegadinhas ao editar)
- Comando: \`$CMD\`${ENVS:+ (background, env: $ENVS)}
- Porta: $PORTA
- Derrubar: matar a árvore de processos inteira do comando acima (não só o PID pai)
EOF
    REC_STATUS=persistida
  fi
fi
jq -cn --argjson pid "$PID" --argjson porta "$PORTA" --arg c "$CMD" --arg r "$REC_STATUS" \
  '{status:"up", pid:$pid, porta:$porta, comando:$c, receita:$r}' > "$ESTADO"
gad_autoregistro "dev-server.sh" 0 "up porta=$PORTA receita=$REC_STATUS" || true
gad_json_out dev-server "$(cat "$ESTADO")"
