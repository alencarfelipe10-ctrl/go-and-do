#!/usr/bin/env bash
# test-gad-bash-guard.sh — bancada do hook `hooks/gad-bash-guard.sh` (P05 da rodada de
# consertos da F24.4): nega comando em segundo plano/desprendido de subagente dentro de
# uma rodada ativa; allow silencioso fora dela.
#
# Alimenta o hook REAL com JSON no stdin, num projeto de fixture (git init + ponteiro
# `.gad-rodada-ativa.json` + run-log), e confere stdout (envelope `hookSpecificOutput`),
# exit (sempre 0) e o `incidente` apendado no run-log. O bloco "comandos reais" repete os
# 33 comandos de fundo colhidos do transcript da F24.4 (fixtures/gad-bash-guard/).
#
# Uso: bash tests/test-gad-bash-guard.sh      ($GAD_HOOK sobrescreve o hook sob teste)
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
REPO="$(dirname -- "$AQUI")"
HOOK="${GAD_HOOK:-$REPO/hooks/gad-bash-guard.sh}"
FIX="$AQUI/fixtures/gad-bash-guard/comandos-reais-24.4.json"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 1; }
[ -f "$FIX" ] || { echo "fixture ausente: $FIX"; exit 1; }
command -v python3 >/dev/null || { echo "python3 ausente"; exit 1; }

falhas=0; ok=0
ok()  { ok=$((ok+1));       echo "PASS: $1"; }
bad() { falhas=$((falhas+1)); echo "FAIL: $1${2:+ — $2}"; }

PAI=$(mktemp -d) || exit 1
trap 'rm -rf "$PAI"' EXIT
export RUNLOG_SEM_ESPELHO=1
SESS="bancada0-0000-0000-bashguard"

# ── projeto de fixture: git + ponteiro + run-log com checkpoint da etapa 3 ─────────────
PROJ="$PAI/proj"; PD="$PROJ/.planning/phases/24-teste"; RL="$PD/24-RUN-LOG.jsonl"
mkdir -p "$PD"; git -C "$PROJ" init -q
printf '{"ts":"x","seq":1,"sessao":"b","evento":"run","etapa":"0 abertura"}\n{"ts":"x","seq":2,"sessao":"b","evento":"checkpoint","etapa":"3 construcao"}\n' > "$RL"
printf '{"session_id":"%s","fase":"24","nn":"24","phase_dir":"%s","runlog":"%s","args":{}}\n' \
  "$SESS" "$PD" "$RL" > "$PROJ/.planning/.gad-rodada-ativa.json"
git -C "$PROJ" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1
git -C "$PROJ" worktree add -q "$PAI/wt" HEAD 2>/dev/null
rm -f "$PAI/wt/.planning/.gad-rodada-ativa.json"   # como no real: o ponteiro é gitignored

# chama <cmd> [bg:true|false|-] [agente|-] [cwd] [session] → imprime allow|deny
chama() {
  local cmd="$1" bg="${2:--}" ag="${3:-gsd-executor}" cwd="${4:-$PROJ}" sess="${5:-$SESS}"
  local out
  out=$(python3 - "$cmd" "$bg" "$ag" "$cwd" "$sess" <<'PY'
import json,sys
cmd,bg,ag,cwd,sess=sys.argv[1:6]
d={"session_id":sess,"cwd":cwd,"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":cmd}}
if bg in("true","false"): d["tool_input"]["run_in_background"]=(bg=="true")
if ag!="-": d["agent_type"]=ag; d["agent_id"]="a0"
print(json.dumps(d))
PY
  ) || { echo erro; return; }
  local resp rc
  resp=$(printf '%s' "$out" | bash "$HOOK" 2>/dev/null); rc=$?
  [ "$rc" = 0 ] || { echo "exit$rc"; return; }
  [ -z "$resp" ] && { echo allow; return; }
  printf '%s' "$resp" | python3 -c '
import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]
assert d["hookEventName"]=="PreToolUse" and d["permissionDecisionReason"].startswith("[gad-bash-guard]")
print(d["permissionDecision"])' 2>/dev/null || echo envelope-invalido
}
n_inc() { grep -c '"origem":"gad-bash-guard.sh"' "$RL" 2>/dev/null || true; }

echo "── nega: fundo e desprendido"
for c in 'sleep 1 &' 'nohup uv run pytest &' "setsid bash -c 'x' &" $'uv run pytest &\ndisown' 'a & b' \
         '( uv run pytest ; touch .done ) & ( x ; touch y ) &' '( nohup uv run pytest ; touch .done ) &'; do
  r=$(chama "$c"); [ "$r" = deny ] && ok "deny: $(printf '%q' "$c")" || bad "deny esperado: $(printf '%q' "$c")" "$r"
done
r=$(chama 'uv run pytest -q' true); [ "$r" = deny ] && ok "deny: run_in_background=true" || bad "run_in_background=true" "$r"
echo "── nega: corpo de bash -c / eval (D1) e desprendimento fora do vocabulário inicial (D2)"
for c in 'bash -c "uv run pytest &"' 'eval "uv run pytest &"' 'screen -dm uv run pytest' 'tmux new -d "uv run pytest"' \
         'systemd-run --user uv run pytest' 'at now <<< "uv run pytest"' 'coproc uv run pytest'; do
  r=$(chama "$c"); [ "$r" = deny ] && ok "deny: $(printf '%q' "$c")" || bad "deny esperado: $(printf '%q' "$c")" "$r"
done

echo "── permite: formas legítimas"
for c in 'uv run pytest -x 2>&1 | tail' 'a && b' "echo 'x & y'" $'cat <<\'EOF\'\na & b\nEOF' "sed 's/&/x/'" \
         '( uv run pytest ; touch .done ) &' 'rm -f .done; ( uv run pytest -q > "$S/log" 2>&1 ; touch "$S/x.done" ) &' \
         'timeout 590 uv run pytest tests/ -q 2>&1 | tail -20' 'grep -n nohup arquivo.sh' 'echo "a & b" > f' \
         'cmd &>/dev/null' 'cmd 2>&1 | tee x |& cat' $'python3 - <<\'PY\'\nx = 1 & 2\nPY\necho fim' 'FOO=bar nohup_x=1 ls' \
         '# comentário com & e nohup
ls' 'bash -c "uv run pytest -x"' "echo 'screen -dm'" 'grep -n "tmux" arquivo'; do
  r=$(chama "$c"); [ "$r" = allow ] && ok "allow: $(printf '%q' "$c" | cut -c1-60)" || bad "allow esperado: $(printf '%q' "$c")" "$r"
done
r=$(chama 'uv run pytest -q' false); [ "$r" = allow ] && ok "allow: run_in_background=false" || bad "run_in_background=false" "$r"

echo "── escopo"
r=$(chama 'nohup x &' - -);                 [ "$r" = allow ] && ok "sem agent_type (sessão principal) → allow" || bad "sem agent_type" "$r"
r=$(chama 'nohup x &' - general-purpose);   [ "$r" = deny ]  && ok "host de camada 1 (general-purpose) → deny (F24.4: 3 nohup saíram dele)" || bad "general-purpose" "$r"
r=$(chama 'nohup x &' - gsd-executor "$PAI"); [ "$r" = allow ] && ok "sem ponteiro de rodada → allow" || bad "sem ponteiro" "$r"
r=$(chama 'nohup x &' - gsd-executor "$PAI/wt"); [ "$r" = deny ] && ok "cwd numa cópia (worktree): ponteiro achado na árvore principal → deny" || bad "worktree" "$r"
r=$(chama 'nohup x &' - gsd-executor "$PROJ" outra-sessao); [ "$r" = allow ] && ok "sessão diferente da rodada → allow" || bad "sessão diferente" "$r"
printf '{"ts":"x","seq":9,"sessao":"b","evento":"stop","etapa":"3 construcao"}\n' >> "$RL"
r=$(chama 'nohup x &'); [ "$r" = allow ] && ok "rodada parada (último evento stop) → allow" || bad "rodada parada" "$r"
sed -i '$d' "$RL"
r=$(printf 'isto não é json' | bash "$HOOK" 2>/dev/null; echo "rc=$?"); [ "$r" = "rc=0" ] && ok "input inválido → allow, exit 0 (fail-open)" || bad "fail-open" "$r"
r=$(printf '{"agent_type":"gsd-executor","cwd":"%s","tool_name":"Bash","tool_input":{"command":"x &"}}' "$PROJ" | bash "$HOOK" 2>/dev/null); [ -n "$r" ] && ok "sem session_id no input e no ponteiro → decide mesmo assim" || bad "session ausente" "$r"

echo "── registro no run-log"
antes=$(n_inc); chama 'nohup uv run pytest -q > /tmp/x.log 2>&1 &' >/dev/null; depois=$(n_inc)
[ "$depois" = $((antes+1)) ] && ok "deny grava 1 incidente" || bad "incidente não gravado" "$antes → $depois"
tail -n1 "$RL" | grep -q '"evento":"incidente","etapa":"3 construcao","origem":"gad-bash-guard.sh","detalhe":"nohup uv run pytest -q > /tmp/x.log 2>&1 &","agente":"gsd-executor","motivo":"`nohup` como palavra de comando"' \
  && ok "incidente com etapa aberta, origem, detalhe, agente e motivo" || bad "campos do incidente" "$(tail -n1 "$RL")"
longo="nohup $(printf 'x%.0s' $(seq 1 200)) &"; chama "$longo" >/dev/null
[ "$(tail -n1 "$RL" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["detalhe"]))')" = 120 ] && ok "detalhe truncado a 120 chars" || bad "truncamento"
antes=$(n_inc); chama 'uv run pytest -q 2>&1 | tail' >/dev/null; [ "$(n_inc)" = "$antes" ] && ok "allow não grava nada" || bad "allow gravou"
antes=$(n_inc); chmod a-w "$PD" "$RL"; r=$(chama 'sleep 1 &'); chmod u+w "$PD" "$RL"
[ "$r" = deny ] && [ "$(n_inc)" = "$antes" ] && ok "run-log inescrevível: nada gravado e a decisão continua deny" || bad "decisão dependeu do registro" "$r $antes→$(n_inc)"

echo "── comandos reais da F24.4 (transcript 51f6da98; 32 deny + 1 heredoc do planner allow)"
res=$(python3 - "$FIX" "$HOOK" "$PROJ" "$SESS" <<'PY'
import json,subprocess,sys
fix,hook,proj,sess=sys.argv[1:5]
err=0
for o in json.load(open(fix)):
    d={"session_id":sess,"cwd":proj,"hook_event_name":"PreToolUse","tool_name":"Bash","agent_type":o["agente"],"agent_id":"a0","tool_input":o["tool_input"]}
    r=subprocess.run(["bash",hook],input=json.dumps(d),capture_output=True,text=True)
    dec="allow" if not r.stdout.strip() else json.loads(r.stdout)["hookSpecificOutput"]["permissionDecision"]
    if dec!=o["esperado"] or r.returncode!=0:
        err+=1; print(f"  divergente: {o['agente']} {o['ts']} esperado={o['esperado']} obtido={dec} exit={r.returncode}")
print("erros", err)
PY
)
echo "$res" | grep -q '^erros 0$' && ok "33/33 comandos reais decididos como esperado" || bad "comandos reais" "$res"

echo "── custo fora do escopo (< 50 ms)"
ms=$( { /usr/bin/time -f '%e' bash "$HOOK" <<<'{"cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"nohup x &"}}' >/dev/null; } 2>&1 )
python3 -c "import sys; sys.exit(0 if float('$ms')<0.05 else 1)" && ok "sessão principal: ${ms}s" || bad "lento" "${ms}s"
ms=$( { /usr/bin/time -f '%e' bash "$HOOK" <<<'{"cwd":"/tmp","agent_type":"gsd-executor","tool_name":"Bash","tool_input":{"command":"nohup x &"}}' >/dev/null; } 2>&1 )
python3 -c "import sys; sys.exit(0 if float('$ms')<0.05 else 1)" && ok "subagente fora de rodada: ${ms}s" || bad "lento" "${ms}s"

echo; echo "resultado: $ok ok, $falhas falha(s)"
[ "$falhas" -eq 0 ]
