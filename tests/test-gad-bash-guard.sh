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
echo "── nega: sleep cru (45i, F24.5); permite o waiter until"
for c in 'sleep 300' 'for i in $(seq 1 60); do sleep 5; done; echo fim' 'cd /x && sleep 30 && ls' \
         "timeout 590 bash -c 'for i in \$(seq 1 10); do sleep 5; done'"; do
  r=$(chama "$c"); [ "$r" = deny ] && ok "deny: $(printf '%q' "$c")" || bad "deny esperado: $(printf '%q' "$c")" "$r"
done
for c in "timeout 590 bash -c 'until [ -s .intent/.releitura-c1.done ]; do sleep 15; done'" \
         'until [ -s x.done ]; do sleep 15; done' 'while ! [ -s x ]; do sleep 10; done' \
         'echo "sleep 5" > nota.txt' 'grep -n sleep script.sh'; do
  r=$(chama "$c"); [ "$r" = allow ] && ok "allow: $(printf '%q' "$c")" || bad "allow esperado: $(printf '%q' "$c")" "$r"
done
r=$(chama 'sleep 300' - -); [ "$r" = allow ] && ok "allow: sleep na sessão principal (sem agent_type)" || bad "sessão principal" "$r"
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
echo "── roda-suite.sh (plano 4 / A2): o fundo mora dentro do script, não no comando da tool"
r=$(chama "bash \$HOME/.claude/gsd-core/bin/nosso/roda-suite.sh --lancar --cmd 'uv run pytest -n 4 -q' --tag suite"); [ "$r" = allow ] && ok "allow: bash roda-suite.sh --lancar (sem & no comando)" || bad "roda-suite --lancar" "$r"
r=$(chama 'bash roda-suite.sh --lancar --cmd "uv run pytest" &'); [ "$r" = deny ] && ok "deny: roda-suite.sh … & (o & de fundo continua negado)" || bad "roda-suite &" "$r"
printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","agent_type":"gsd-executor","tool_input":{"command":"sleep 1 &"}}' "$SESS" "$PROJ" | bash "$HOOK" 2>/dev/null | grep -q 'roda-suite.sh' && ok "a mensagem de negativa aponta o roda-suite.sh" || bad "mensagem sem roda-suite.sh"

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

# ── P-01/P-02: a receita que o prompt PRESCREVE tem de passar no guard ────────────────
# Extraído do arquivo do prompt, nunca copiado à mão: prompt e teste não podem divergir
# em silêncio (lição da v2.3.0 — nunca parafrasear literal que um gate grepa).
echo "── receitas prescritas pelos prompts (P-01/P-02)"
PROMPTS="$REPO/skills/go-and-do/prompts"
bloco_bash() { # <arquivo> <n-do-bloco a partir de 1> → conteúdo do n-ésimo ```bash … ```
  awk -v want="$2" '
    /^[[:space:]]*```bash[[:space:]]*$/ { n++; if (n==want) { dentro=1; next } }
    /^[[:space:]]*```[[:space:]]*$/     { if (dentro) { exit } }
    dentro { print }' "$1"
}

CONV_LANCA=$(bloco_bash "$PROMPTS/convergence.md" 1)
CONV_ESPERA=$(bloco_bash "$PROMPTS/convergence.md" 2)
CR_LANE=$(bloco_bash "$PROMPTS/code-review.md" 1)
[ -n "$CONV_LANCA" ] && [ -n "$CONV_ESPERA" ] && [ -n "$CR_LANE" ] \
  || bad "extração dos blocos bash dos prompts" "algum bloco saiu vazio"

[ "$(chama "$CONV_LANCA")"  = allow ] && ok "convergence.md §2 — lançador passa no guard" \
  || bad "convergence.md §2 — lançador" "$(chama "$CONV_LANCA")"
[ "$(chama "$CONV_ESPERA")" = allow ] && ok "convergence.md §2 — waiter passa no guard" \
  || bad "convergence.md §2 — waiter" "$(chama "$CONV_ESPERA")"
[ "$(chama "$CR_LANE")"     = allow ] && ok "code-review.md passo 1 — lane Codex passa no guard" \
  || bad "code-review.md passo 1" "$(chama "$CR_LANE")"

# regressão: as receitas ANTIGAS continuam negadas (o guard não foi afrouxado)
ANTIGO_2LANES='( $HOME/.claude/skills/go-and-do/scripts/roda-codex.sh "/pd" "24" 1 /b ) &
( $HOME/.claude/skills/go-and-do/scripts/roda-agy.sh   "/pd" "24" 1 /b ) &
wait'
ANTIGO_SEM_TOUCH='( $HOME/.claude/skills/go-and-do/scripts/roda-codex.sh "/pd" "24" review /b --out /o ) &'
[ "$(chama "$ANTIGO_2LANES")"    = deny ] && ok "receita antiga de 2 lanes em & segue negada" \
  || bad "receita antiga de 2 lanes" "$(chama "$ANTIGO_2LANES")"
[ "$(chama "$ANTIGO_SEM_TOUCH")" = deny ] && ok "subshell & sem touch segue negado" \
  || bad "subshell & sem touch" "$(chama "$ANTIGO_SEM_TOUCH")"
[ "$(chama "$CONV_ESPERA" true)" = deny ] && ok "waiter com run_in_background=true é negado" \
  || bad "waiter com run_in_background" "$(chama "$CONV_ESPERA" true)"

echo "── 45o: escrita no instrumento sob julgamento (P-11)"
H="$HOME/.claude/skills/go-and-do"; A="$HOME/.claude/skills/audit-gad"
for c in "sed -i \"88d\" $H/scripts/confere-plano.sh" \
         "tee $H/prompts/plan.md < /tmp/x" \
         "echo x > $H/scripts/confere-ciclo.sh" \
         "echo x >> $A/workflow.md" \
         "cp /tmp/x.sh $H/scripts/confere-ciclo.sh" \
         "mv /tmp/x.md \$HOME/.claude/agents/gad-plan.md" \
         "patch -p1 $H/hooks/x.sh < /tmp/p.diff" \
         "python3 -c \"open('/home/u/.claude/skills/go-and-do/x','w')\"" \
         "sed -i s/a/b/ /home/u/Projetos/gsd-optimize/gen5-patches/manifesto.json"; do
  r=$(chama "$c")
  if [ "$r" = deny ]; then ok "deny instrumento: $(printf '%.60s' "$c")"; else bad "deny esperado (instrumento): $c" "$r"; fi
done
# a razão nomeia o motivo e a saída de evidência
resp=$(printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","agent_type":"gsd-executor","agent_id":"a0","tool_input":{"command":"sed -i 88d %s/scripts/confere-plano.sh"}}' "$SESS" "$PROJ" "$H" | bash "$HOOK" 2>/dev/null)
printf '%s' "$resp" | grep -q 'instrumento_sob_julgamento: escrita em' \
  && printf '%s' "$resp" | grep -q 'gate-fail-<etapa>-evidencia.txt' \
  && ok "razão do instrumento nomeia o motivo e o arquivo de evidência" \
  || bad "razão do instrumento" "$resp"

echo "── 45o: leitura, execução e destino de fora seguem liberados (o coração do item)"
for c in "bash $H/scripts/confere-etapa.sh 2" \
         "grep -n x $H/prompts/plan.md" \
         "cat /home/u/Projetos/gsd-optimize/gen5-patches/manifesto.json" \
         "cp $H/scripts/confere-ciclo.sh /tmp/x.sh" \
         "grep -n x $H/prompts/plan.md > /tmp/saida.txt"; do
  r=$(chama "$c"); [ "$r" = allow ] && ok "allow: $(printf '%.60s' "$c")" || bad "allow esperado: $c" "$r"
done
# fora de escopo: sessão do dono (sem agent_type) e projeto sem ponteiro
r=$(chama "sed -i s/a/b/ $H/scripts/confere-plano.sh" - -); [ "$r" = allow ] && ok "sem agent_type (dono) → allow" || bad "sem agent_type" "$r"
r=$(chama "sed -i s/a/b/ $H/scripts/confere-plano.sh" - gsd-executor "$PAI"); [ "$r" = allow ] && ok "sem ponteiro de rodada → allow" || bad "sem ponteiro" "$r"

echo "── 45n: rastro de git por subprocess (P-12) — allow + incidente"
verifica_rastro() { # <descrição> <cmd> <esperado allow|deny> <eventos esperados>
  local desc="$1" c="$2" esp="$3" nev="$4" a b r
  a=$(n_inc); r=$(chama "$c"); b=$(n_inc)
  if [ "$r" = "$esp" ] && [ "$b" = $((a+nev)) ]; then ok "$desc"
  else bad "$desc" "decisão=$r (esperado $esp); eventos=$((b-a)) (esperado $nev)"; fi
}
verifica_rastro "subprocess.run(['git'…]) → allow + 1 incidente" \
  "uv run python -c \"import subprocess; subprocess.run(['git','add','-A'])\"" allow 1
# LACUNA DECLARADA (45n): a regex do contrato casa a aspa NUA (["'] ). Quando o comando chega
# com a aspa ESCAPADA (`[\"git\"`, forma que aparece quando o .py vem dentro de outra string
# com aspas duplas), o rastro NÃO dispara. Não é negativa nenhuma — só rastro que falta.
# Registrado como pendência do P-12; alargar a regex é decisão do dono.
verifica_rastro "aspa escapada (\\\"git\\\") → allow, SEM rastro (lacuna declarada)" \
  'uv run python -c "import subprocess; subprocess.run([\"git\",\"add\"])"' allow 0
verifica_rastro "os.system(… git …) → allow + 1 incidente" \
  'python3 -c "import os; os.system(\"git commit -m x\")"' allow 1
verifica_rastro "sh -c \"… git …\" → allow + 1 incidente" \
  'sh -c "git status --short"' allow 1
verifica_rastro "git direto (sem Python) → allow, sem evento" 'git status --short' allow 0
verifica_rastro "subprocess.run([\"ls\"]) → allow, sem evento" \
  'python3 -c "import subprocess; subprocess.run([\"ls\"])"' allow 0
verifica_rastro "sh -c com github na URL → allow, sem evento (\\bgit\\b não casa github)" \
  'sh -c "curl https://github.com/x"' allow 0
verifica_rastro "heredoc com subprocess.run([\"git\"…]) → allow + 1 incidente" \
  "$(printf 'python3 - <<%s\nimport subprocess\nsubprocess.run(["git","log"])\nPY' "'PY'")" allow 1
verifica_rastro "negado pelo P-11 E com rastro → deny + 2 eventos" \
  "sh -c \"git log > \$HOME/.claude/skills/go-and-do/scripts/x.sh\"" deny 2
# o incidente traz o motivo canônico
tail -n5 "$RL" | grep -q '"motivo":"git_por_subprocess"' \
  && ok "incidente do rastro com motivo=git_por_subprocess" || bad "motivo do rastro" "$(tail -n1 "$RL")"
r=$(chama 'python3 -c "import subprocess; subprocess.run([\"git\",\"log\"])"' - -)
[ "$r" = allow ] && ok "fora de rodada (sem agent_type) → allow, sem rastro" || bad "fora de rodada" "$r"

echo; echo "resultado: $ok ok, $falhas falha(s)"
[ "$falhas" -eq 0 ]
