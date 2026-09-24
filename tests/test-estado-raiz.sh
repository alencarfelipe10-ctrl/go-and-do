#!/usr/bin/env bash
# test-estado-raiz.sh — tarefa 56 (v2.10.1): estado da raiz da .planning.
#
# Cobre o B7 do plano: rodada nova grava SÓ o ponteiro novo; retomada com só o legado
# funciona (script E hook); novo tem precedência; a limpeza apaga órfão não rastreado e
# não toca rastreado; espelho de cópia cai no cache (fora do git) e o de estado continua
# em .planning/.gad/; `git status --porcelain` limpo depois de um ciclo de scripts;
# GAD_DRY_RUN=1 não escreve nada, nem no cache.
#
# Bancada isolada (mktemp), gsd-tools mockado como no test-abre-rodada.sh.
set -u

RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SC="$RAIZ/skills/go-and-do/scripts"
HOOK="$RAIZ/hooks/gad-lifecycle.sh"

OK=0; FALHAS=0
ok()    { OK=$((OK+1)); printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }
sim()   { if eval "$2"; then ok "$1"; else falha "$1" "falhou: $2"; fi; }

BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT
export RUNLOG_SEM_ESPELHO=1

# ── mock do gsd-tools (init.phase-op com fixture) ────────────────────────────
export RUNTIME_DIR="$BASE/runtime"
mkdir -p "$RUNTIME_DIR/gsd-core/bin"
cat > "$RUNTIME_DIR/gsd-core/bin/gsd-tools.cjs" <<'CJS'
const fs = require('fs');
const a = process.argv.slice(2);
if (a[0] === 'query' && a[1] === 'init.phase-op') { process.stdout.write(fs.readFileSync(process.env.GAD_FIXTURE, 'utf8')); process.exit(0); }
if (a[0] === 'query' && a[1] === 'roadmap.get-phase') { process.stdout.write('{"found":false}'); process.exit(0); }
if (a[0] === 'query' && a[1] === 'config-get') { process.stdout.write('true'); process.exit(0); }
process.exit(0);
CJS

projeto() { # <nome> → cria repo git com 1 fase (99-bancada) e exporta GAD_FIXTURE
  local r="$BASE/$1"
  mkdir -p "$r/.planning/phases/99-bancada"
  git init -q "$r"; git -C "$r" config user.name t; git -C "$r" config user.email t@t
  printf '# ROADMAP\n' > "$r/.planning/ROADMAP.md"
  printf '{}\n' > "$r/.planning/config.json"
  printf '# fase\n' > "$r/.planning/phases/99-bancada/.gitkeep"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q -m base
  printf '{"phase_found":true,"phase_number":"99","phase_name":"bancada","phase_dir":"%s","expected_phase_dir":null,"padded_phase":"99","planning_exists":true,"has_context":false,"has_plans":false,"has_research":false,"has_reviews":false,"has_verification":false,"plan_count":0}' \
    "$r/.planning/phases/99-bancada" > "$BASE/$1.fix.json"
  printf '%s' "$r"
}
abre() { # <root> [flags] → J = 1ª linha JSON
  local r="$1"; shift
  export GAD_FIXTURE="$BASE/$(basename -- "$r").fix.json"
  J=$( cd "$r" && CLAUDE_CODE_SESSION_ID="${SESS:-}" bash "$SC/abre-rodada.sh" 99 --projeto "$r" "$@" 2>/dev/null | head -1 )
}

echo "── 56(a): rodada nova grava só o caminho novo ──"
R=$(projeto novo)
abre "$R"
sim "ponteiro novo .planning/.gad/rodada-ativa.json existe"   "[ -f '$R/.planning/.gad/rodada-ativa.json' ]"
sim "ponteiro legado NÃO existe"                               "[ ! -e '$R/.planning/.gad-rodada-ativa.json' ]"
sim ".planning/.gad/.gitignore com * (56(d))"                  "grep -qx '\\*' '$R/.planning/.gad/.gitignore'"
eq  "git ls-files .planning/.gad sai vazio"                    "$(git -C "$R" ls-files .planning/.gad | wc -l | tr -d ' ')" "0"

echo "── 56(f): espelho de cópia no cache, fora do git ──"
CACHE="$(git -C "$R" rev-parse --path-format=absolute --git-path gad-cache)"
eq  "abre-rodada: 1ª chave do JSON é espelho"                  "$(jq -r 'keys_unsorted[0]' <<<"$J")" "espelho"
eq  "…e aponta para o cache do git"                            "$(jq -r .espelho <<<"$J")" "$CACHE/last-abre-rodada.json"
sim "…o arquivo existe no cache"                               "[ -s '$CACHE/last-abre-rodada.json' ]"
sim "…e NÃO em .planning/.gad/"                                "[ ! -e '$R/.planning/.gad/last-abre-rodada.json' ]"

echo "── 56(f): espelho de estado continua em .planning/.gad/ ──"
( cd "$R" && . "$SC/lib/gsd-shim.sh" && gad_json_out pre-despacho '{"etapa":"6","rota":"handback"}' >/dev/null
  gad_json_out setup-contratos '{"ok":true}' >/dev/null )
sim "pre-despacho (estado) em .planning/.gad/last-pre-despacho.json" "[ -s '$R/.planning/.gad/last-pre-despacho.json' ]"
sim "…e não no cache"                                          "[ ! -e '$CACHE/last-pre-despacho.json' ]"
sim "setup-contratos (cópia) no cache"                         "[ -s '$CACHE/last-setup-contratos.json' ]"
eq  "veredito-end lê o estado pelo helper → handback"          "$(bash -c ". '$SC/lib/veredito-end.sh'; gad_veredito_end '$R' '6 encerramento'")" "handback"
printf '{"evento":"checkpoint","etapa":"1 intencao"}\n' >> "$R/.planning/phases/99-bancada/99-RUN-LOG.jsonl"
if bash "$SC/janela-silencio.sh" >/dev/null 2>&1; then
  sim "pre-gate grava o marcador de estado em .planning/.gad/" "( cd '$R' && bash '$SC/pre-gate.sh' '$R/.planning/phases/99-bancada' 99 'p?' >/dev/null 2>&1 ); [ -s '$R/.planning/.gad/last-pre-gate.json' ]"
else ok "pre-gate: janela de silêncio agora (23h–07h) — marcador não se aplica"; fi

echo "── git status limpo depois de um ciclo de scripts ──"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -q -m "fase" >/dev/null 2>&1 || true
( cd "$R" && bash "$SC/confere-etapa.sh" 0 --projeto "$R" >/dev/null 2>&1 || true )
abre "$R"
( cd "$R" && bash "$SC/commita-artefatos.sh" "$R/.planning/phases/99-bancada" 99 evidencia >/dev/null 2>&1 || true )
# O run-log é reescrito pelo próprio auto-registro do commita-artefatos DEPOIS do commit
# (comportamento de sempre, decisão de 21/09): fica fora desta régua, que é da 56.
PORC="$(git -C "$R" status --porcelain --untracked-files=all | grep -v -- '-RUN-LOG.jsonl$' || true)"
eq  "git status --porcelain vazio (estado ignorado, cache fora)" "$(printf '%s' "$PORC" | grep -c . || true)" "0"
[ -z "$PORC" ] || echo "     sujos: $PORC"
eq  "git ls-files .planning/.gad continua vazio"               "$(git -C "$R" ls-files .planning/.gad | wc -l | tr -d ' ')" "0"

echo "── GAD_DRY_RUN=1: nada escrito, nem no cache ──"
R2=$(projeto seco)
C2="$(git -C "$R2" rev-parse --path-format=absolute --git-path gad-cache)"
( cd "$R2" && GAD_DRY_RUN=1 bash -c ". '$SC/lib/gsd-shim.sh'; gad_json_out setup-contratos '{\"ok\":true}'; gad_json_out pre-despacho '{\"x\":1}'" >/dev/null )
sim "GAD_DRY_RUN=1: sem .planning/.gad/"                        "[ ! -e '$R2/.planning/.gad' ]"
sim "…sem cache"                                                "[ ! -e '$C2' ]"
abre "$R2" --dry-run
sim "abre-rodada --dry-run: sem .planning/.gad/ (nem ponteiro)" "[ ! -e '$R2/.planning/.gad' ]"
sim "…sem ponteiro legado"                                      "[ ! -e '$R2/.planning/.gad-rodada-ativa.json' ]"

echo "── 56(c): limpeza apaga órfão não rastreado e não toca rastreado ──"
R3=$(projeto limpeza)
mkdir -p "$R3/.planning/.gad"
printf '{}\n' > "$R3/.planning/.gad-last-abre-rodada.json"          # órfão solto (antes do 8828baa)
printf '{}\n' > "$R3/.planning/.gad-last-confere-etapa.json"        # órfão rastreado (git)
printf '{}\n' > "$R3/.planning/.gad/last-confere-plano-99-01.json"  # cópia velha solta
printf '{}\n' > "$R3/.planning/.gad/last-varre-worktrees.json"      # cópia velha rastreada
printf '{"passed":true}\n' > "$R3/.planning/.gad/last-plan-gate.json" # estado: nunca some
git -C "$R3" add -f .planning/.gad-last-confere-etapa.json .planning/.gad/last-varre-worktrees.json
git -C "$R3" commit -q -m "legado rastreado"
abre "$R3"
sim "órfão .gad-last-abre-rodada.json apagado"                 "[ ! -e '$R3/.planning/.gad-last-abre-rodada.json' ]"
sim "cópia velha solta apagada"                                "[ ! -e '$R3/.planning/.gad/last-confere-plano-99-01.json' ]"
sim "rastreado .gad-last-confere-etapa.json intacto"          "[ -e '$R3/.planning/.gad-last-confere-etapa.json' ]"
sim "rastreado last-varre-worktrees.json intacto"             "[ -e '$R3/.planning/.gad/last-varre-worktrees.json' ]"
sim "estado last-plan-gate.json intacto"                       "[ -e '$R3/.planning/.gad/last-plan-gate.json' ]"
eq  "limpeza lista os 2 apagados"                              "$(jq -c '.limpeza|sort' <<<"$J")" '[".planning/.gad-last-abre-rodada.json",".planning/.gad/last-confere-plano-99-01.json"]'
eq  "legado_rastreado lista os 2 rastreados"                   "$(jq -c '.legado_rastreado|sort' <<<"$J")" '[".planning/.gad-last-confere-etapa.json",".planning/.gad/last-varre-worktrees.json"]'
eq  "o índice não mudou (nada staged)"                         "$(git -C "$R3" diff --cached --name-only | wc -l | tr -d ' ')" "0"

echo "── retomada: rodada aberta pela v2.10.0 (só o legado existe) ──"
R4=$(projeto legado)
PD4="$R4/.planning/phases/99-bancada"; RL4="$PD4/99-RUN-LOG.jsonl"
SESS="bancada-legado-0000"
jq -cn --arg s "$SESS" --arg pd "$PD4" --arg rl "$RL4" \
  '{session_id:$s, fase:"99", nn:"99", phase_dir:$pd, runlog:$rl, args:{ui:false,ai:false,no_ship:false,vault:false,obs:""}}' \
  > "$R4/.planning/.gad-rodada-ativa.json"
: > "$RL4"
OUT=$( cd "$R4" && bash "$SC/pre-despacho.sh" 2 --projeto "$R4" --dry-run 2>&1 | tail -1 )
sim "pre-despacho.sh resolve a fase pelo ponteiro legado"      "jq -e '.etapa==\"2\"' >/dev/null 2>&1 <<<'$OUT' && ! grep -q 'fase não' <<<'$OUT'"
# hook com payload PreToolUse de Agent: acha o ponteiro legado e grava o despacho
H4="$BASE/home4"; mkdir -p "$H4/.claude/skills/go-and-do" "$H4/.claude/agents" "$H4/.claude/projects/p"
ln -s "$SC" "$H4/.claude/skills/go-and-do/scripts"
for d in "$RAIZ"/agents/gad-*.md; do ln -s "$d" "$H4/.claude/agents/$(basename "$d")"; done
TP4="$H4/.claude/projects/p/$SESS.jsonl"; printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-5"}}' > "$TP4"
payload() { jq -cn --arg cwd "$1" --arg s "$SESS" --arg tp "$TP4" \
  '{hook_event_name:"PreToolUse", tool_name:"Agent", cwd:$cwd, session_id:$s, transcript_path:$tp,
    tool_use_id:"tu-1", tool_input:{subagent_type:"gad-explore", description:"bancada"}}'; }
antes=$(wc -l < "$RL4")
printf '%s' "$(payload "$R4")" | HOME="$H4" CLAUDE_CODE_SESSION_ID="$SESS" bash "$HOOK" >/dev/null 2>&1
sim "hook gad-lifecycle resolve a rodada pelo ponteiro legado" "[ \$(wc -l < '$RL4') -gt $antes ]"
# o próximo abre-rodada migra: grava o novo e apaga o legado
abre "$R4"
sim "próximo abre-rodada grava o novo"                         "[ -f '$R4/.planning/.gad/rodada-ativa.json' ]"
sim "…e apaga o legado"                                        "[ ! -e '$R4/.planning/.gad-rodada-ativa.json' ]"
eq  "…e o relata em limpeza"                                   "$(jq -r '.limpeza|index(".planning/.gad-rodada-ativa.json") != null' <<<"$J")" "true"

echo "── novo tem precedência sobre legado ──"
R5=$(projeto precedencia)
PD5="$R5/.planning/phases/99-bancada"; RL5="$PD5/99-RUN-LOG.jsonl"; : > "$RL5"
mkdir -p "$R5/.planning/.gad"
jq -cn --arg s "$SESS" --arg pd "$PD5" --arg rl "$RL5" '{session_id:$s, fase:"99", nn:"99", phase_dir:$pd, runlog:$rl, args:{}}' \
  > "$R5/.planning/.gad/rodada-ativa.json"
jq -cn --arg s "$SESS" '{session_id:$s, fase:"77", nn:"77", phase_dir:"/nao/existe", runlog:"/nao/existe/77-RUN-LOG.jsonl", args:{}}' \
  > "$R5/.planning/.gad-rodada-ativa.json"
eq  "gad_rodada_ativa devolve o novo"                          "$(bash -c ". '$SC/lib/gad-caminhos.sh'; gad_rodada_ativa '$R5'")" "$R5/.planning/.gad/rodada-ativa.json"
antes=$(wc -l < "$RL5")
printf '%s' "$(payload "$R5")" | HOME="$H4" CLAUDE_CODE_SESSION_ID="$SESS" bash "$HOOK" >/dev/null 2>&1
sim "hook usa o novo (grava no run-log da fase 99)"            "[ \$(wc -l < '$RL5') -gt $antes ]"
for g in gad-bash-guard gad-gate-guard; do
  sim "hook $g aceita o ponteiro novo (grep do caminho)"      "grep -q 'rodada-ativa.json' '$RAIZ/hooks/$g.sh' && grep -q '.gad/rodada-ativa.json' '$RAIZ/hooks/$g.sh'"
done

echo "── 56(b): dev-server lê o legado e grava o novo ──"
R6=$(projeto devserver)
printf '{"status":"up","pid":999999,"porta":1}\n' > "$R6/.planning/.gad-dev-server.json"
eq  "gad_dev_server_estado cai no legado quando só ele existe" "$(bash -c ". '$SC/lib/gad-caminhos.sh'; gad_dev_server_estado '$R6' json")" "$R6/.planning/.gad-dev-server.json"
( cd "$R6" && bash "$SC/dev-server.sh" down --projeto "$R6" >/dev/null 2>&1 )
sim "down apaga o estado legado"                               "[ ! -e '$R6/.planning/.gad-dev-server.json' ]"
eq  "sem estado → caminho novo"                                "$(bash -c ". '$SC/lib/gad-caminhos.sh'; gad_dev_server_estado '$R6' log")" "$R6/.planning/.gad/dev-server.log"

echo
echo "$OK ok / $FALHAS falhas"
[ "$FALHAS" -eq 0 ]
