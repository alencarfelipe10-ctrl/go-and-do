#!/usr/bin/env bash
# discuss-init.sh — passo 1 consolidado do gad-discuss-phase, o comando único de intenção do
# documento único (fork; plano 06-13 — D-08, D-09, D-12; AC-04..AC-08).
#
# Uso (a partir do bloco bash do `initialize`, após o preâmbulo resolver GAD_TOOLS/gad_run):
#   GAD_TOOLS=… ARGUMENTS="$ARGUMENTS" bash "$NOSSO/discuss-init.sh" "<PHASE>" [--insumo <arq> …] [--text]
#
# 1. BARREIRA SEM DONO — antes de qualquer escrita (nem `.planning/.discuss-tmp/`, nem depósito,
#    nem CONTEXT): `--auto`, `--chain`, `--batch`, `--assumptions`, `--power`, `--all` ou
#    `--analyze` no ARGUMENTS (ou como flag deste script), ou `workflow._auto_chain_active: true`
#    na config → imprime `BARREIRA: sem-dono (<motivo>)` e sai 3. O documento único só nasce com
#    o dono presente. `--text` e `workflow.discuss_mode` não barram (o modo de discuss da config é
#    ignorado: é sempre o comando único).
# 2. INSUMOS — `--insumo <arq>` (repetível): arquivo regular dentro da raiz do projeto (o cwd,
#    de onde todo caminho `.planning/…` é relativo), inclusive um `NN-PRE-SPEC.md` antigo, lido
#    pelo modelo como TEXTO; nenhum conversor do formato antigo roda. Fora da raiz, symlink que
#    sai dela, inexistente ou diretório → exit 2, antes de qualquer escrita.
# 3. init.phase-op conferido (P07: JSON vazio/inválido, sem `phase_dir`, `*_model` que não é
#    apelido do Agent → exit 2).
# 4. ESTADO DA INTENÇÃO (lido do depósito `<phase_dir>/<NN>-DISCUSS-CHECKPOINT.json` via
#    `checkpoint-write.py show`, da existência do `<NN>-CONTEXT.md`, da marca na linha 2 e do
#    sha256):
#      nova          sem depósito e sem CONTEXT
#      retomar       depósito sem aprovação (queda no meio da entrevista: a linha DEPOSITO mostra
#                    áreas feitas, pendentes e ids já decididos — nada respondido é perguntado de novo)
#      gravar        depósito aprovado e CONTEXT ausente ou com sha ≠ aprovado (queda na gravação:
#                    renderiza de novo e promove, sem nova pergunta)
#      finalizar     depósito aprovado e CONTEXT com o sha aprovado (falta só o fecho)
#      existe-novo   sem depósito e CONTEXT com a marca `<!-- gad:documento-unico: v1 -->` na linha 2
#      existe-antigo sem depósito e CONTEXT sem a marca
#    Os dois `existe-*` NÃO ESCREVEM NADA (nem o diretório temporário): o workflow diz ao dono o
#    que existe e pergunta se refaz.
# 5. Para os demais estados: `.planning/.discuss-tmp/` (= $T) recriado, roadmap get-phase
#    (goal/criteria), check-batch, canonical refs do ROADMAP, hooks discuss:pre, chaves de config,
#    [P08] contexto prévio em $T/prior.txt e $T/env.sh (escalares + gad_run; ESTADO_INTENCAO,
#    INSUMOS, INSUMOS_N, CKPT, CONTEXT_PATH, RASCUNHO=$T/rascunho/<NN>-CONTEXT.md, TEXT_MODE).
#
# O init não lê SPEC, não gera lote do PRE-SPEC, não gera áreas por artefato novo e não detecta
# advisor (plano 06-13). Exit: 0 ok · 1 uso/gad-tools ausente · 2 dado ruim (init, insumo,
# depósito ilegível) · 3 barreira sem dono.
set -u
BARREIRA_FLAGS="--auto --chain --batch --assumptions --power --all --analyze"
_barra() { local f; for f in $BARREIRA_FLAGS; do case "$1" in "$f"|"$f="*) printf '%s' "$f"; return 0 ;; esac; done; return 1; }
barreira() {
  echo "BARREIRA: sem-dono ($1)"
  echo "[barreira] o documento único de intenção só é gravado com o dono presente ($1): rode /gad-discuss-phase você mesmo, sem modo automático — nada foi escrito" >&2
  exit 3
}
# 1a. barreira pelos argumentos (do usuário em ARGUMENTS e deste script) — nada foi lido nem escrito ainda
BARRA=""; TEXT_MODE=false
for _a in "$@"; do [ -n "$BARRA" ] || BARRA=$(_barra "$_a") || true; done
set -f
for _a in ${ARGUMENTS:-}; do
  [ -n "$BARRA" ] || BARRA=$(_barra "$_a") || true
  [ "$_a" = "--text" ] && TEXT_MODE=true
done
set +f
[ -z "$BARRA" ] || barreira "$BARRA"

PHASE=""; INSUMO_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --insumo) INSUMO_ARGS+=("${2:?--insumo requires a file}"); shift 2 ;;
    --text) TEXT_MODE=true; shift ;;
    -*) echo "ERROR: unknown flag $1" >&2; exit 1 ;;
    *) [ -z "$PHASE" ] && PHASE="$1" || { echo "ERROR: unexpected argument $1" >&2; exit 1; }; shift ;;
  esac
done
[ -n "$PHASE" ] || { echo "ERROR: phase number required" >&2; exit 1; }
[ -n "${GAD_TOOLS:-}" ] && [ -f "$GAD_TOOLS" ] || { echo "ERROR: GAD_TOOLS not set — run the Step 1 preamble first" >&2; exit 1; }
case "$GAD_TOOLS" in *.cjs) gad_run() { node "$GAD_TOOLS" "$@"; } ;; *) gad_run() { "$GAD_TOOLS" "$@"; } ;; esac
NOSSO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
_json() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const v=JSON.parse(s)[process.argv[1]];console.log(v==null?"":v)})' "$1"; }
_sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

# 1b. barreira pela config (o /gad-autonomous e as cadeias ligam _auto_chain_active)
_AC=$(gad_run query config-get workflow._auto_chain_active --default false --raw 2>/dev/null || echo false)
[ "$_AC" = "true" ] && barreira "workflow._auto_chain_active"

# 2. insumos — validados antes de qualquer escrita
ROOT="$(pwd -P)"
INSUMOS=$(python3 - "$ROOT" ${INSUMO_ARGS[@]+"${INSUMO_ARGS[@]}"} <<'PY'
import os, sys
root, args = os.path.realpath(sys.argv[1]), sys.argv[2:]
out = []
for a in args:
    p = a if os.path.isabs(a) else os.path.join(root, a)
    r = os.path.realpath(p)
    if r != root and not r.startswith(root + os.sep):
        sys.exit(f"ERROR: --insumo {a}: fora da raiz do projeto ({root}) — recusado")
    if not os.path.isfile(r):
        sys.exit(f"ERROR: --insumo {a}: não é um arquivo regular existente — recusado")
    rel = os.path.relpath(r, root)
    if rel not in out:
        out.append(rel)
print("\n".join(out))
PY
) || exit 2
INSUMOS_N=$(printf '%s' "$INSUMOS" | grep -c . || true); INSUMOS_N=${INSUMOS_N:-0}

# 3. init.phase-op conferido (P07)
INIT=$(gad_run query init.phase-op "${PHASE}"); [[ "$INIT" == @file:* ]] && INIT=$(cat "${INIT#@file:}")
# Apelidos aceitos pelo Agent do Claude Code: opus|sonnet|haiku|fable (+ inherit). Um ID
# completo (ex.: claude-opus-4-8, de resolve_model_ids:true) é descartado pelo spawner.
_ERR=$(printf '%s' "$INIT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let d;try{d=JSON.parse(s)}catch{d=null}
if(!d||typeof d!=="object"||Array.isArray(d)||!Object.keys(d).length){console.log("init.phase-op devolveu JSON vazio ou inválido");return}
if(!d.phase_dir&&!d.expected_phase_dir){console.log("init.phase-op sem phase_dir nem expected_phase_dir");return}
for(const [k,v] of Object.entries(d)) if(k.endsWith("_model")&&!/^(opus|sonnet|haiku|fable|inherit)$/.test(String(v))){console.log("modelo inválido para o Agent: "+v+"; ajuste resolve_model_ids ou o catálogo (campo "+k+")");return}})' 2>/dev/null)
[ -z "$_ERR" ] || { echo "ERROR: $_ERR" >&2; exit 2; }
phase_dir=$(printf '%s' "$INIT" | _json phase_dir); [ -n "$phase_dir" ] || phase_dir=$(printf '%s' "$INIT" | _json expected_phase_dir)
padded_phase=$(printf '%s' "$INIT" | _json padded_phase); PHASE_NUMBER=$(printf '%s' "$INIT" | _json phase_number); phase_name=$(printf '%s' "$INIT" | _json phase_name)
[ -n "$padded_phase" ] || padded_phase="$PHASE"

# 4. estado da intenção — só leitura
CKPT="${phase_dir}/${padded_phase}-DISCUSS-CHECKPOINT.json"
CONTEXT_PATH="${phase_dir}/${padded_phase}-CONTEXT.md"
MARCA='<!-- gad:documento-unico: v1 -->'
DEPOSITO=""
if [ -f "$CKPT" ]; then
  DEPOSITO=$(python3 "$NOSSO/checkpoint-write.py" show "$CKPT" 2>/dev/null | python3 -c 'import json,sys
d = json.load(sys.stdin)
print(json.dumps({k: d.get(k) for k in ("areas_completed", "areas_remaining", "ids", "secoes", "aprovado_sha256")}, ensure_ascii=False))' 2>/dev/null) \
    || { echo "ERROR: depósito ilegível: $CKPT — mova-o de lado para recomeçar; nada foi escrito" >&2; exit 2; }
  APROV=$(printf '%s' "$DEPOSITO" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("aprovado_sha256") or "")')
  if [ -z "$APROV" ]; then ESTADO_INTENCAO=retomar
  elif [ -f "$CONTEXT_PATH" ] && [ "$(_sha "$CONTEXT_PATH")" = "$APROV" ]; then ESTADO_INTENCAO=finalizar
  else ESTADO_INTENCAO=gravar; fi
elif [ -f "$CONTEXT_PATH" ]; then
  # Regra única da marca (WR-02 da iteração 3 do code review da fase 6): o mesmo sed com LC_ALL=C dos outros leitores —
  # a expansão de parâmetro usava o [[:space:]] do locale do shell, que num locale UTF-8 apara também U+3000, U+2028….
  _L2=$(LC_ALL=C sed -n '2{s/\r$//;s/^[[:space:]]*//;s/[[:space:]]*$//;p;q}' "$CONTEXT_PATH" 2>/dev/null)
  if [ "$_L2" = "$MARCA" ]; then ESTADO_INTENCAO=existe-novo; else ESTADO_INTENCAO=existe-antigo; fi
else
  ESTADO_INTENCAO=nova
fi
if [ "$ESTADO_INTENCAO" = existe-novo ] || [ "$ESTADO_INTENCAO" = existe-antigo ]; then
  # R1 / AC-07: nada é escrito — o workflow pergunta ao dono se refaz
  printf '%s\n' "$INIT"
  echo "ESTADO_INTENCAO=$ESTADO_INTENCAO"
  echo "CONTEXT_PATH: $CONTEXT_PATH"
  echo "INSUMOS: n=$INSUMOS_N"
  exit 0
fi

# 5. a partir daqui o init escreve (só em $T)
T=".planning/.discuss-tmp"; rm -rf "$T"; mkdir -p "$T/rascunho"
RASCUNHO="$T/rascunho/${padded_phase}-CONTEXT.md"

# [1.3] phase entry — goal, criteria, section (canonical refs live in the section)
PHASE_JSON=$(gad_run roadmap get-phase "${PHASE}" 2>/dev/null || echo '{"found":false}')
_pn=$(printf '%s' "$PHASE_JSON" | _json phase_name 2>/dev/null || true); [ -n "$_pn" ] && phase_name="$_pn"   # init devolve o slug; o ROADMAP tem o nome
printf '%s' "$PHASE_JSON" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let j;try{j=JSON.parse(s)}catch{j={found:false}}const fs=require("fs"),T=process.argv[1];if(!j.found){console.error("[fallback] roadmap get-phase not found — read the ROADMAP.md phase entry manually");["goal","criteria"].forEach(n=>fs.writeFileSync(T+"/"+n+".txt",""));fs.writeFileSync(T+"/section.md","");process.exit(0)}fs.writeFileSync(T+"/goal.txt",(j.goal||"")+"\n");fs.writeFileSync(T+"/criteria.txt",(j.success_criteria||[]).map((c,i)=>"SC"+(i+1)+": "+c).join("\n")+"\n");fs.writeFileSync(T+"/section.md",(j.section||"")+"\n")})' "$T"

# [1.4] check-batch
_CH="${phase_dir}/.continue-here.md"; if [ -f "$_CH" ]; then BLOCKING=$(grep -ciE '\|\s*blocking\s*\|' "$_CH" || true); else BLOCKING=0; fi; BLOCKING=${BLOCKING:-0}
CHECKPOINT=$( [ -f "$CKPT" ] && echo true || echo false )
CHECKS=$(printf '{"blocking":%s,"checkpoint":%s}' "$BLOCKING" "$CHECKPOINT")

# [9.1] canonical refs from the ROADMAP entry — grammar v3; never invent a path
_L=$(grep -iE -m1 'canonical refs?' "$T/section.md" 2>/dev/null || true)
_L=$(printf '%s' "$_L" | sed -E 's/^[[:space:]]*[-*]?[[:space:]]*\**[Cc]anonical [Rr]efs?\**:?\**[[:space:]]*//')
if printf '%s' "$_L" | grep -q '`'; then _ITEMS=$(printf '%s' "$_L" | grep -oE '`[^`]+`' | tr -d '`'); else _ITEMS=$(printf '%s' "$_L" | tr ',' '\n'); fi
printf '%s\n' "$_ITEMS" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -v '^$' | while IFS= read -r it; do p=${it%% §*}; n=${it#"$p"}; n=${n# }; [ -e "$p" ] && echo "OK $p${n:+ [$n]}" || echo "MISSING $p"; done > "$T/refs-roadmap.txt"

# [8.1][C-16] pre-hooks rendered here; dispatched in the workflow's own step
DISCUSS_PRE_HOOKS_JSON=$(gad_run loop render-hooks discuss:pre --raw 2>/dev/null || echo '{"activeHooks":[]}')

LOG_ON=$(gad_run query config-get features.discussion_log --default false --raw 2>/dev/null || echo false)
TODO_THRESHOLD=$(gad_run query config-get features.todo_fold_threshold --default 0.4 --raw 2>/dev/null || echo 0.4)
# [C6] quantas fases entram INTEIRAS na vista do índice de decisões (advisory, nunca gate);
# as demais entram uma linha por D-NN com ponteiro. 1 = a fase anterior completa (~71 KB no
# inspired); 0 = só linhas (~43 KB). Fora do intervalo ou não numérico → 1.
INDEX_RECENT=$(gad_run query config-get features.decisions_index_recent --default 1 --raw 2>/dev/null || echo 1)
case "$INDEX_RECENT" in ''|*[!0-9]*) INDEX_RECENT=1 ;; esac

# [P08] contexto prévio — grava $T/prior.txt; o modelo lê o arquivo. Não vai para o stdout
# porque o índice de decisões sozinho pode passar de 200 KB e o stdout tem teto de 20 KB.
_MISS=0
{ echo "=== STATE.md (sections)"; grep '^## ' .planning/STATE.md 2>/dev/null || true
  for h in "Accumulated Context" "Deferred Items"; do _s=$(gad_run state get "$h" 2>/dev/null); case "$_s" in *'"error"'*|"") echo "[fallback] STATE section '$h' not found"; _MISS=1 ;; *) printf '%s\n' "$_s" ;; esac; done
  [ "${_MISS:-0}" = 1 ] && { echo "[fallback] reading STATE.md whole"; cat .planning/STATE.md 2>/dev/null || true; }
  echo "=== PROJECT.md (Core Value / Key Decisions / Constraints)"
  _P=$(sed -n -E '/^## (Core Value|Valor Central|Key Decisions|Decisões-Chave|Constraints|Restrições)/,/^## /p' .planning/PROJECT.md 2>/dev/null | grep -v -E '^## (Requirements|Requisitos|Context|Contexto|Evolution|Evolução|Current|Marco|Estado|What This Is|O Que É)' || true)
  if [ -n "$_P" ]; then printf '%s\n' "$_P"; else echo "[fallback] no known PROJECT.md headings — reading whole"; cat .planning/PROJECT.md 2>/dev/null || true; fi
  echo "=== REQUIREMENTS.md"; cat .planning/REQUIREMENTS.md 2>/dev/null || true
  echo "=== PRIOR DECISIONS"
  if [ -f .planning/DECISIONS-INDEX.md ]; then
    # [C6] vista recortada: o arquivo canônico fica completo em disco; o que entra na janela é a
    # vista, com ponteiro por decisão. Fail-open: gerador ausente ou falho → arquivo inteiro.
    python3 "$NOSSO/decisions-index.py" .planning --vista --recent "$INDEX_RECENT" --linha-max 160 --out "$T/index-vista.md" >/dev/null 2>&1 || true
    if [ -s "$T/index-vista.md" ]; then
      echo "[index] vista recortada de .planning/DECISIONS-INDEX.md ($(wc -c < "$T/index-vista.md") B de $(wc -c < .planning/DECISIONS-INDEX.md) B; recent=$INDEX_RECENT; texto completo no arquivo, ponteiro por decisão)"
      cat "$T/index-vista.md"
    else
      echo "[index] using .planning/DECISIONS-INDEX.md (vista falhou — arquivo inteiro)"; cat .planning/DECISIONS-INDEX.md
    fi
  else for f in $( (find .planning/phases -name "*-CONTEXT.md" -not -name "BACKLOG-CONTEXT.md" 2>/dev/null || true) | grep -v "/${padded_phase}-CONTEXT.md$" | sort -r | head -3); do echo "--- $f"; sed -n '/<decisions>/,/<\/decisions>/p;/<specifics>/,/<\/specifics>/p' "$f"; done; fi
  echo "=== SPIKES/SKETCHES"; ls ./.claude/skills/spike-findings-*/SKILL.md ./.claude/skills/sketch-findings-*/SKILL.md .planning/spikes/MANIFEST.md .planning/sketches/MANIFEST.md 2>/dev/null || true
  echo "=== TODO MATCHES (threshold $TODO_THRESHOLD)"; gad_run query todo.match-phase "${PHASE_NUMBER}"
} > "$T/prior.txt"

{ printf 'GAD_TOOLS=%q\n' "$GAD_TOOLS"; printf 'case "$GAD_TOOLS" in *.cjs) gad_run() { node "$GAD_TOOLS" "$@"; } ;; *) gad_run() { "$GAD_TOOLS" "$@"; } ;; esac\n'
  printf 'PHASE=%q\nphase_dir=%q\npadded_phase=%q\nPHASE_NUMBER=%q\nphase_name=%q\nNOSSO=%q\nT=%q\nLOG_ON=%q\nTODO_THRESHOLD=%q\nTEXT_MODE=%q\nESTADO_INTENCAO=%q\nINSUMOS=%q\nINSUMOS_N=%q\nCKPT=%q\nCONTEXT_PATH=%q\nRASCUNHO=%q\n' \
    "$PHASE" "$phase_dir" "$padded_phase" "$PHASE_NUMBER" "$phase_name" "$NOSSO" "$T" "$LOG_ON" "$TODO_THRESHOLD" "$TEXT_MODE" "$ESTADO_INTENCAO" "$INSUMOS" "$INSUMOS_N" "$CKPT" "$CONTEXT_PATH" "$RASCUNHO"
  # `. env.sh` define variáveis de SHELL; os scripts filhos (discuss-render-guard.sh e
  # companhia) rodam como PROCESSO e só enxergam o que estiver exportado.
  printf 'export GAD_TOOLS PHASE phase_dir padded_phase PHASE_NUMBER phase_name NOSSO T LOG_ON TODO_THRESHOLD TEXT_MODE ESTADO_INTENCAO INSUMOS INSUMOS_N CKPT CONTEXT_PATH RASCUNHO\n'; } > "$T/env.sh"

printf '%s\n' "$INIT"
echo "PHASE_GOAL: $(cat "$T/goal.txt")"; echo "PHASE_CRITERIA:"; cat "$T/criteria.txt"
echo "CHECKS: $CHECKS"
echo "ESTADO_INTENCAO=$ESTADO_INTENCAO"
[ -n "$DEPOSITO" ] && echo "DEPOSITO: $DEPOSITO"
echo "INSUMOS: n=$INSUMOS_N"; [ "$INSUMOS_N" -gt 0 ] && printf '%s\n' "$INSUMOS" | sed 's/^/  /'
echo "ROADMAP_REFS:"; cat "$T/refs-roadmap.txt"
echo "LOG_ON=$LOG_ON TODO_THRESHOLD=$TODO_THRESHOLD TEXT_MODE=$TEXT_MODE"
echo "PRIOR: $T/prior.txt bytes=$(wc -c < "$T/prior.txt")"
echo "PRE_HOOKS: $DISCUSS_PRE_HOOKS_JSON"
