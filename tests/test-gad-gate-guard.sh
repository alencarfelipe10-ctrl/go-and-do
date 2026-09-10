#!/usr/bin/env bash
# test-gad-gate-guard.sh — bancada do hook `hooks/gad-gate-guard.sh` e do script
# `skills/go-and-do/scripts/pre-gate.sh` (v2.5.4, tarefa 45p — F24.5 23:50: gate duro
# dentro da janela de silêncio, sem commit, sem HANDOFF; espelhos 6h velhos).
#
# Alimenta o hook REAL com JSON no stdin, num projeto de fixture (git init + ponteiro
# `.gad-rodada-ativa.json` + run-log com checkpoint), e confere stdout (envelope
# `hookSpecificOutput`), exit (sempre 0) e o `incidente` apendado no run-log.
#
# Uso: bash tests/test-gad-gate-guard.sh
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
REPO="$(dirname -- "$AQUI")"
HOOK="${GAD_HOOK:-$REPO/hooks/gad-gate-guard.sh}"
PREGATE="$REPO/skills/go-and-do/scripts/pre-gate.sh"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 1; }
[ -f "$PREGATE" ] || { echo "script não encontrado: $PREGATE"; exit 1; }
command -v python3 >/dev/null || { echo "python3 ausente"; exit 1; }
command -v jq >/dev/null || { echo "jq ausente"; exit 1; }

falhas=0; ok=0
ok()  { ok=$((ok+1));       echo "PASS: $1"; }
bad() { falhas=$((falhas+1)); echo "FAIL: $1${2:+ — $2}"; }

PAI=$(mktemp -d) || exit 1
trap 'rm -rf "$PAI"' EXIT
export RUNLOG_SEM_ESPELHO=1
export GAD_SCRIPTS_DIR_TESTE="$REPO/skills/go-and-do/scripts"
SESS="bancada0-0000-0000-gateguard"

# ── projeto de fixture: git + ponteiro + run-log com checkpoint da etapa 3 ─────────────
PROJ="$PAI/proj"; PD="$PROJ/.planning/phases/24-teste"; RL="$PD/24-RUN-LOG.jsonl"
mkdir -p "$PD"
git -C "$PROJ" init -q
git -C "$PROJ" -c user.email=t@t -c user.name=t commit --allow-empty -qm base >/dev/null 2>&1
printf '{"ts":"x","seq":1,"sessao":"b","evento":"run","etapa":"0 abertura"}\n{"ts":"x","seq":2,"sessao":"b","evento":"checkpoint","etapa":"3 construcao"}\n' > "$RL"
printf '{"session_id":"%s","fase":"24","nn":"24","phase_dir":"%s","runlog":"%s","args":{}}\n' \
  "$SESS" "$PD" "$RL" > "$PROJ/.planning/.gad-rodada-ativa.json"
git -C "$PROJ" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm "fixture inicial" >/dev/null 2>&1

payload() { # $1 sessão $2 tool_name
  local s="${1:-$SESS}" t="${2:-AskUserQuestion}"
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"questions":[]}}' \
    "$s" "$PROJ" "$t"
}

chama_hook() { # $1 sessão $2 tool_name → imprime allow|deny|<outro>
  local resp rc s="${1:-$SESS}" t="${2:-AskUserQuestion}"
  resp=$(payload "$s" "$t" | GAD_HORA_FALSA="${GAD_HORA_FALSA:-}" bash "$HOOK" 2>/dev/null); rc=$?
  [ "$rc" = 0 ] || { echo "exit$rc"; return; }
  [ -z "$resp" ] && { echo allow; return; }
  printf '%s' "$resp" | python3 -c '
import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]
assert d["hookEventName"]=="PreToolUse"
r=d["permissionDecisionReason"]
assert r.startswith("[gad-gate-guard]"), r
print(d["permissionDecision"]+"|"+r)' 2>/dev/null || echo envelope-invalido
}
n_inc() { grep -c '"origem":"gad-gate-guard.sh"' "$RL" 2>/dev/null || true; }

echo "── caso 1: fora de rodada (sem ponteiro) → allow, sem stdout"
mv "$PROJ/.planning/.gad-rodada-ativa.json" "$PAI/ponteiro.bak"
resp=$(payload | GAD_HORA_FALSA=12 bash "$HOOK" 2>/dev/null); rc=$?
[ "$rc" = 0 ] && [ -z "$resp" ] && ok "sem ponteiro → allow sem stdout" || bad "sem ponteiro" "rc=$rc resp=$resp"
mv "$PAI/ponteiro.bak" "$PROJ/.planning/.gad-rodada-ativa.json"

echo "── caso 2: sessão diferente → allow"
r=$(chama_hook "outra-sessao"); [ "$r" = allow ] && ok "sessão diferente → allow" || bad "sessão diferente" "$r"

echo "── caso 3: GAD_HORA_FALSA=23 → deny janela_silencio"
r=$(GAD_HORA_FALSA=23 chama_hook)
case "$r" in
  deny\|*) echo "$r" | grep -q "Sub-rotina D" && ok "janela de silêncio → deny com Sub-rotina D" || bad "razão sem Sub-rotina D" "$r" ;;
  *) bad "janela de silêncio deveria negar" "$r" ;;
esac
tail -n1 "$RL" | grep -q '"evento":"incidente".*"origem":"gad-gate-guard.sh".*"motivo":"janela_silencio"' \
  && ok "incidente gravado com origem e motivo=janela_silencio" || bad "incidente ausente/incorreto" "$(tail -n1 "$RL")"

echo "── caso 4: GAD_HORA_FALSA=12, sem marcador → deny sem_pre_gate"
rm -f "$PROJ/.planning/.gad/last-pre-gate.json" 2>/dev/null
r=$(GAD_HORA_FALSA=12 chama_hook)
case "$r" in
  deny\|*) echo "$r" | grep -q "pre-gate.sh" && ok "sem marcador → deny sem_pre_gate citando pre-gate.sh" || bad "razão sem pre-gate.sh" "$r" ;;
  *) bad "sem marcador deveria negar" "$r" ;;
esac
tail -n1 "$RL" | grep -q '"evento":"incidente".*"origem":"gad-gate-guard.sh".*"motivo":"sem_pre_gate"' \
  && ok "incidente gravado com motivo=sem_pre_gate" || bad "incidente sem_pre_gate ausente/incorreto" "$(tail -n1 "$RL")"

echo "── caso 5: pre-gate.sh roda com sucesso → hook allow"
saida=$(GAD_HORA_FALSA=12 bash "$PREGATE" "$PD" 24 "pergunta x" 2>/tmp/pregate-err-$$.log); rc_pg=$?
acao=$(printf '%s' "$saida" | jq -r '.acao' 2>/dev/null)
[ "$rc_pg" = 0 ] && [ "$acao" = "pergunta" ] && ok "pre-gate.sh exit 0, acao=pergunta" || bad "pre-gate.sh" "rc=$rc_pg saida=$saida $(cat /tmp/pregate-err-$$.log 2>/dev/null)"
rm -f /tmp/pregate-err-$$.log
msg=$(git -C "$PROJ" log -1 --format=%s)
[ "$msg" = "docs(fase 24): artefatos da fase antes do gate duro" ] && ok "commit do pré-gate com mensagem esperada" || bad "mensagem do commit" "$msg"
M="$PROJ/.planning/.gad/last-pre-gate.json"
HEAD_ATUAL=$(git -C "$PROJ" rev-parse HEAD)
[ -f "$M" ] && [ "$(jq -r '.head' "$M")" = "$HEAD_ATUAL" ] && ok "marcador existe com head = HEAD" || bad "marcador" "$(cat "$M" 2>/dev/null)"
r=$(GAD_HORA_FALSA=12 chama_hook); [ "$r" = allow ] && ok "hook allow após pre-gate.sh" || bad "hook deveria permitir após pre-gate" "$r"

echo "── caso 6: commit novo depois do pré-gate → deny; novo pre-gate.sh → allow"
echo "x" >> "$PD/24-outra.md" 2>/dev/null || { mkdir -p "$PD"; echo "x" > "$PD/24-outra.md"; }
git -C "$PROJ" add -A >/dev/null 2>&1
git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm "commit novo qualquer" >/dev/null 2>&1
r=$(GAD_HORA_FALSA=12 chama_hook)
case "$r" in deny\|*) ok "commit novo → deny sem_pre_gate" ;; *) bad "commit novo deveria negar" "$r" ;; esac
GAD_HORA_FALSA=12 bash "$PREGATE" "$PD" 24 "pergunta y" >/dev/null 2>&1
r=$(GAD_HORA_FALSA=12 chama_hook); [ "$r" = allow ] && ok "novo pre-gate.sh → allow" || bad "novo pre-gate deveria permitir" "$r"

echo "── caso 7: marcador velho (ts_epoch = agora-1000) → deny"
AGORA_TESTE=$(date +%s)
jq --argjson e "$((AGORA_TESTE-1000))" '.ts_epoch=$e' "$M" > "$M.tmp" && mv "$M.tmp" "$M"
r=$(GAD_HORA_FALSA=12 GAD_GATE_AGORA="$AGORA_TESTE" chama_hook)
case "$r" in deny\|*) ok "marcador com > 15 min → deny" ;; *) bad "marcador velho deveria negar" "$r" ;; esac

echo "── caso 8: GAD_HORA_FALSA=0 e pre-gate.sh → exit 1, acao=pausa, marcador não criado"
rm -f "$M"
saida=$(GAD_HORA_FALSA=0 bash "$PREGATE" "$PD" 24 "pergunta z" 2>/dev/null); rc_pg=$?
acao=$(printf '%s' "$saida" | jq -r '.acao' 2>/dev/null)
[ "$rc_pg" = 1 ] && [ "$acao" = "pausa" ] && ok "pre-gate.sh na janela: exit 1, acao=pausa" || bad "pre-gate.sh janela" "rc=$rc_pg saida=$saida"
[ ! -f "$M" ] && ok "marcador NÃO criado na janela de silêncio" || bad "marcador não deveria existir" "$(cat "$M")"

echo "── caso 9: pre-gate.sh não adiciona .err/.log"
: > "$PD/x.err"; : > "$PD/y.log"
GAD_HORA_FALSA=12 bash "$PREGATE" "$PD" 24 "pergunta w" >/dev/null 2>&1
st=$(git -C "$PROJ" status --porcelain)
echo "$st" | grep -q '\?\? .*x\.err\|x\.err$' && echo "$st" | grep -q '\?\? .*y\.log\|y\.log$' \
  && ok ".err/.log continuam untracked após pre-gate.sh" || bad ".err/.log deveriam continuar untracked" "$st"
rm -f "$PD/x.err" "$PD/y.log"

echo "── caso 10: tool_name diferente (Bash) → allow"
r=$(GAD_HORA_FALSA=23 chama_hook "$SESS" Bash); [ "$r" = allow ] && ok "tool_name=Bash → allow" || bad "tool diferente deveria permitir" "$r"

echo "── caso 11: último evento do run-log = stop → allow"
printf '{"ts":"x","seq":9,"sessao":"b","evento":"stop","etapa":"3 construcao"}\n' >> "$RL"
r=$(GAD_HORA_FALSA=23 chama_hook); [ "$r" = allow ] && ok "rodada parada (stop) → allow" || bad "rodada parada deveria permitir" "$r"
sed -i '$d' "$RL"

echo; echo "resultado: $ok ok, $falhas falha(s)"
[ "$falhas" -eq 0 ]
