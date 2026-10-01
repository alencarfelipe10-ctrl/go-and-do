#!/usr/bin/env bash
# discuss-init.sh — passo 1 consolidado do gad-discuss-phase (fork, tarefa 3b).
#
# Uso (a partir do bloco bash do `initialize`, após o preâmbulo resolver GAD_TOOLS/gad_run):
#   GAD_TOOLS=… ARGUMENTS="$ARGUMENTS" bash "$NOSSO/discuss-init.sh" "<PHASE>" [--pre-spec <arquivo>]
#
# O `--pre-spec` é OVERRIDE, não gatilho: sem ele o script AUTODETECTA
# `<phase_dir>/*-PRE-SPEC.md` (mesmo comportamento do `spec-init.sh` irmão).
#
# Faz, numa chamada só: init.phase-op → roadmap get-phase (goal/criteria/section) →
# check-batch (blocking / SPEC / checkpoint) → extração do SPEC (bloco gsd:reqs em 3 estados,
# gsd:scope ou regex bilíngue, files, Regression Surface) → canonical refs do ROADMAP
# (gramática v3) → advisor lazy (perde para --auto) → render dos hooks discuss:pre →
# [D5b] PRE-SPEC (autodetectado no phase_dir, ou apontado por --pre-spec): lê SÓ o bloco
# `gad:decisoes` (nunca o arquivo inteiro — o PRE-SPEC não entra na janela do filho) e gera
# .discuss-tmp/pre-spec-batch.json, o insumo do `checkpoint-write.py map-pre-spec`. Filtro
# estrito `kind == decisao_dono`: `fato_medido` NUNCA vira decisão (vai só para a lista do
# briefing/SPEC). Sem PRE-SPEC no phase_dir → `PRE_SPEC_STATE=ausente` e nada é gerado; bloco
# ausente dentro de um PRE-SPEC existente → também `ausente`, e o eco distingue os dois pelo
# `file=` (o fail-closed é do coordenador, §0.5, que já parou antes).
# [R5b] gray areas obrigatórias por artefato novo commitado, lidas da seção do SPEC pelo
# artefatos-novos.py (o MESMO parser do context-guard.sh) →
# chaves de config → [P08] contexto prévio (STATE/PROJECT/REQUIREMENTS/índice de decisões/
# spikes/TODOs) em .discuss-tmp/prior.txt → grava .planning/.discuss-tmp/env.sh (escalares + gad_run) para os blocos
# seguintes. Tudo degrada para o comportamento upstream com log [fallback]/[warn]. Aborta por
# gad-tools ausente (exit 1) e, desde o P07 (01/09/2026), com exit 2 quando o `init.phase-op`
# devolve dado ruim: JSON vazio/inválido, sem `phase_dir`, ou um campo `*_model` que não é
# apelido do Agent. Motivo: seguir com esse dado só adia a falha para o despacho do agente.
set -u
PHASE=""; PRE_SPEC_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pre-spec) PRE_SPEC_ARG="${2:?--pre-spec requires a file}"; shift 2 ;;
    -*) echo "ERROR: unknown flag $1" >&2; exit 1 ;;
    *) [ -z "$PHASE" ] && PHASE="$1" || { echo "ERROR: unexpected argument $1" >&2; exit 1; }; shift ;;
  esac
done
[ -n "$PHASE" ] || { echo "ERROR: phase number required" >&2; exit 1; }
[ -n "${GAD_TOOLS:-}" ] && [ -f "$GAD_TOOLS" ] || { echo "ERROR: GAD_TOOLS not set — run the Step 1 preamble first" >&2; exit 1; }
case "$GAD_TOOLS" in *.cjs) gad_run() { node "$GAD_TOOLS" "$@"; } ;; *) gad_run() { "$GAD_TOOLS" "$@"; } ;; esac
NOSSO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
_json() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const v=JSON.parse(s)[process.argv[1]];console.log(v==null?"":v)})' "$1"; }

INIT=$(gad_run query init.phase-op "${PHASE}"); [[ "$INIT" == @file:* ]] && INIT=$(cat "${INIT#@file:}")
# ── conferência de entrada (P07): quem lê o init não segue com dado ruim ───────
# Apelidos aceitos pelo Agent do Claude Code: opus|sonnet|haiku|fable (+ inherit). Um ID
# completo (ex.: claude-opus-4-8, de resolve_model_ids:true) é descartado pelo spawner.
_ERR=$(printf '%s' "$INIT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let d;try{d=JSON.parse(s)}catch{d=null}
if(!d||typeof d!=="object"||Array.isArray(d)||!Object.keys(d).length){console.log("init.phase-op devolveu JSON vazio ou inválido");return}
if(!d.phase_dir&&!d.expected_phase_dir){console.log("init.phase-op sem phase_dir nem expected_phase_dir");return}
for(const [k,v] of Object.entries(d)) if(k.endsWith("_model")&&!/^(opus|sonnet|haiku|fable|inherit)$/.test(String(v))){console.log("modelo inválido para o Agent: "+v+"; ajuste resolve_model_ids ou o catálogo (campo "+k+")");return}})' 2>/dev/null)
[ -z "$_ERR" ] || { echo "ERROR: $_ERR" >&2; exit 2; }
phase_dir=$(printf '%s' "$INIT" | _json phase_dir); [ -n "$phase_dir" ] || phase_dir=$(printf '%s' "$INIT" | _json expected_phase_dir)
padded_phase=$(printf '%s' "$INIT" | _json padded_phase); PHASE_NUMBER=$(printf '%s' "$INIT" | _json phase_number); phase_name=$(printf '%s' "$INIT" | _json phase_name)
T=".planning/.discuss-tmp"; rm -rf "$T"; mkdir -p "$T"

# [1.3] phase entry — goal, criteria, section (canonical refs live in the section)
PHASE_JSON=$(gad_run roadmap get-phase "${PHASE}" 2>/dev/null || echo '{"found":false}')
_pn=$(printf '%s' "$PHASE_JSON" | _json phase_name 2>/dev/null || true); [ -n "$_pn" ] && phase_name="$_pn"   # init devolve o slug; o ROADMAP tem o nome
printf '%s' "$PHASE_JSON" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let j;try{j=JSON.parse(s)}catch{j={found:false}}const fs=require("fs"),T=process.argv[1];if(!j.found){console.error("[fallback] roadmap get-phase not found — read the ROADMAP.md phase entry manually");["goal","criteria"].forEach(n=>fs.writeFileSync(T+"/"+n+".txt",""));fs.writeFileSync(T+"/section.md","");process.exit(0)}fs.writeFileSync(T+"/goal.txt",(j.goal||"")+"\n");fs.writeFileSync(T+"/criteria.txt",(j.success_criteria||[]).map((c,i)=>"SC"+(i+1)+": "+c).join("\n")+"\n");fs.writeFileSync(T+"/section.md",(j.section||"")+"\n")})' "$T"

# [1.4][2.1][4.1] check-batch — steps 2–4 become decisions over this JSON
_CH="${phase_dir}/.continue-here.md"; if [ -f "$_CH" ]; then BLOCKING=$(grep -ciE '\|\s*blocking\s*\|' "$_CH" || true); else BLOCKING=0; fi; BLOCKING=${BLOCKING:-0}
SPEC_PATH=$(ls "${phase_dir}"/*-SPEC.md 2>/dev/null | grep -v -E 'AI-SPEC|PRE-SPEC' | head -1 || true)   # PRE-SPEC = insumo da /go-and-do, não é o SPEC
SPEC_PATH=${SPEC_PATH#"$PWD"/}   # relative to the project root — it is what goes into <canonical_refs>
CHECKPOINT=$( [ -f "${phase_dir}/${padded_phase}-DISCUSS-CHECKPOINT.json" ] && echo true || echo false )
CHECKS=$(printf '{"blocking":%s,"spec":"%s","checkpoint":%s}' "$BLOCKING" "$SPEC_PATH" "$CHECKPOINT")
printf '%s' "$CHECKS" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>JSON.parse(s))' 2>/dev/null || { echo "[warn] CHECKS JSON invalid — fall back to per-step ls" >&2; CHECKS=""; }

# [3.1][3.2] SPEC — machine-readable block (valid / absent / invalid), scope, files, regression surface
REQ_STATE=none; REQ_COUNT=""; REQ_IDS=""; REGRESSION_EMPTY=""; SCOPE_SRC=""; : > "$T/spec-files.txt"; : > "$T/scope-in.txt"; : > "$T/scope-out.txt"
if [ -n "$SPEC_PATH" ]; then
  REQS_JSON=$(sed -n '/<!-- gsd:reqs:begin -->/,/<!-- gsd:reqs:end -->/p' "$SPEC_PATH" | sed '1d;$d')
  if [ -z "$REQS_JSON" ]; then REQ_STATE=absent; echo "[fallback] SPEC without machine-readable block — count requirements from prose" >&2
  elif _V=$(printf '%s' "$REQS_JSON" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let a;try{a=JSON.parse(s)}catch{process.exit(1)}if(!Array.isArray(a)||!a.length)process.exit(1);const ids=new Set(),files=new Set();for(const r of a){if(typeof r.text!=="string"||!r.text.trim()||r.text.includes("<"))process.exit(1);if(r.text_en!=null&&(typeof r.text_en!=="string"||!r.text_en.trim()||r.text_en.includes("<")))process.exit(1);if(typeof r.id!=="string"||!/^R[0-9]+$/.test(r.id)||ids.has(r.id))process.exit(1);ids.add(r.id);if(r.files!==undefined){if(!Array.isArray(r.files)||r.files.some(f=>typeof f!=="string"||!f||f.startsWith("/")||f.split("/").includes("..")))process.exit(1);r.files.forEach(f=>files.add(f))}}console.log(a.length+" "+[...ids].join(" "));process.stderr.write([...files].join("\n"))})' 2>"$T/spec-files.txt"); then
    REQ_STATE=valid; REQ_COUNT=${_V%% *}; REQ_IDS=${_V#* }
  else REQ_STATE=invalid; : > "$T/spec-files.txt"; echo "[warn] gsd:reqs block present but invalid — falling back to prose count" >&2; fi
  SCOPE_JSON=$(sed -n '/<!-- gsd:scope:begin -->/,/<!-- gsd:scope:end -->/p' "$SPEC_PATH" | sed '1d;$d')
  if [ -n "$SCOPE_JSON" ] && printf '%s' "$SCOPE_JSON" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let o;try{o=JSON.parse(s)}catch{process.exit(1)}const ok=k=>Array.isArray(o[k])&&o[k].every(x=>typeof x==="string");if(!ok("in")||!ok("out"))process.exit(1);const fs=require("fs");fs.writeFileSync(process.argv[1],o.in.map(x=>"- "+x).join("\n")+"\n");fs.writeFileSync(process.argv[2],o.out.map(x=>"- "+x).join("\n")+"\n")})' "$T/scope-in.txt" "$T/scope-out.txt" 2>/dev/null; then SCOPE_SRC=json
  else
    SCOPE_SRC=regex; _IN='^\*\*(In scope|Em escopo)[^*]*\*\*'; _OUT='^\*\*(Out of scope|Fora de escopo)[^*]*\*\*'
    _BND=$(sed -n '/^## Boundaries/,/^## [^B]/p' "$SPEC_PATH" | sed '$d')   # [C3-37] drop the terminating heading
    printf '%s\n' "$_BND" | sed -n -E "/$_IN/,/$_OUT/p" | sed '1d;$d' | grep -E '^\s*[-*]\s' > "$T/scope-in.txt" || true
    printf '%s\n' "$_BND" | sed -n -E "/$_OUT/,\$p" | sed '1d' | grep -E '^\s*[-*]\s' > "$T/scope-out.txt" || true
    if [ ! -s "$T/scope-in.txt" ] && [ ! -s "$T/scope-out.txt" ]; then printf '%s\n' "$_BND" | sed '1d' | grep -v '^\s*$' > "$T/scope-in.txt"; echo "[warn] scope labels not recognised — Boundaries copied whole" >&2; fi
    cat "$T/scope-in.txt" "$T/scope-out.txt" | grep -q '^## ' && echo "[warn] scope contains a heading" >&2
  fi
  _RS=$(sed -n '/^## Regression Surface/,/^## /p' "$SPEC_PATH"); _ROWS=$(printf '%s\n' "$_RS" | grep -cE '^\|[^-|]' || true)
  if [ "${_ROWS:-0}" -le 1 ] || printf '%s' "$_RS" | grep -q 'No existing assertions falsified'; then REGRESSION_EMPTY=true; else REGRESSION_EMPTY=false; fi
  # keep only files that exist (never read a phantom path)
  if [ -s "$T/spec-files.txt" ]; then grep -v '^$' "$T/spec-files.txt" | while IFS= read -r f; do [ -e "$f" ] && echo "$f" || echo "[warn] SPEC files: $f not on disk" >&2; done > "$T/spec-files.ok" ; mv "$T/spec-files.ok" "$T/spec-files.txt"; fi
fi

# [9.1] canonical refs from the ROADMAP entry — grammar v3; never invent a path
_L=$(grep -iE -m1 'canonical refs?' "$T/section.md" 2>/dev/null || true)
_L=$(printf '%s' "$_L" | sed -E 's/^[[:space:]]*[-*]?[[:space:]]*\**[Cc]anonical [Rr]efs?\**:?\**[[:space:]]*//')
if printf '%s' "$_L" | grep -q '`'; then _ITEMS=$(printf '%s' "$_L" | grep -oE '`[^`]+`' | tr -d '`'); else _ITEMS=$(printf '%s' "$_L" | tr ',' '\n'); fi
printf '%s\n' "$_ITEMS" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -v '^$' | while IFS= read -r it; do p=${it%% §*}; n=${it#"$p"}; n=${n# }; [ -e "$p" ] && echo "OK $p${n:+ [$n]}" || echo "MISSING $p"; done > "$T/refs-roadmap.txt"

# [1.2][C-04] advisor is lazy and loses to --auto
ADVISOR_MODE=false; AGENT_SKILLS_ADVISOR=""
if [ -f "$HOME/.claude/gad-core/USER-PROFILE.md" ]; then ADVISOR_MODE=true; AGENT_SKILLS_ADVISOR=$(gad_run query agent-skills gad-advisor-researcher 2>/dev/null || true); case " ${ARGUMENTS:-} " in *" --auto "*) ADVISOR_MODE=false; echo "[auto] advisor disabled (USER-PROFILE.md present, --auto wins)" >&2 ;; esac; fi

# [8.1][C-16] pre-hooks rendered here; dispatched in the workflow's own step
DISCUSS_PRE_HOOKS_JSON=$(gad_run loop render-hooks discuss:pre --raw 2>/dev/null || echo '{"activeHooks":[]}')
# [D5b] bloco gad:decisoes → pre-spec-batch.json (só decisao_dono)
# `--pre-spec` é override; sem ele, autodetecta no phase_dir (idem spec-init.sh).
PRE_SPEC="$PRE_SPEC_ARG"
if [ -z "$PRE_SPEC" ] && [ -n "$phase_dir" ] && [ -d "$phase_dir" ]; then
  PRE_SPEC=$(ls "$phase_dir"/*-PRE-SPEC.md 2>/dev/null | head -1 || true)
fi
PRE_SPEC_STATE=ausente; PRE_SPEC_BATCH=""; PRE_SPEC_N=0
if [ -n "$PRE_SPEC" ]; then
  if [ ! -f "$PRE_SPEC" ]; then
    # só é alcançável com --pre-spec: a autodetecção só devolve caminho existente.
    PRE_SPEC_STATE=arquivo_ausente; echo "[warn] --pre-spec: file not found: $PRE_SPEC" >&2
  else
    _OUT=$(python3 "$NOSSO/pre-spec-batch.py" "$PRE_SPEC" "$T/pre-spec-batch.json" 2>&1) && {
      PRE_SPEC_STATE=$(printf '%s' "$_OUT" | sed -n 's/^estado: //p')
      PRE_SPEC_N=$(printf '%s' "$_OUT" | sed -n 's/^decisoes: //p')
      [ "$PRE_SPEC_STATE" = "ok" ] && PRE_SPEC_BATCH="$T/pre-spec-batch.json"
    } || { PRE_SPEC_STATE=$(printf '%s' "$_OUT" | sed -n 's/^estado: //p'); }
    PRE_SPEC_STATE=${PRE_SPEC_STATE:-invalido}; PRE_SPEC_N=${PRE_SPEC_N:-0}
    printf '%s\n' "$_OUT" | grep -v '^estado: \|^decisoes: ' >&2 || true
  fi
fi

# [R5b] artefatos novos commitados do SPEC → uma gray area OBRIGATÓRIA por artefato
: > "$T/gray-areas-artefatos.txt"; ARTEFATOS_N=0
if [ -n "$SPEC_PATH" ]; then
  while IFS= read -r _art; do
    [ -n "$_art" ] || continue
    ARTEFATOS_N=$((ARTEFATOS_N+1))
    printf 'ARTEFATO %s | caminho final? · vai para diretório espelhado/público? · contém dado pessoal? · que precedente abre?\n' "$_art" >> "$T/gray-areas-artefatos.txt"
  done < <(python3 "$NOSSO/artefatos-novos.py" "$SPEC_PATH")
fi

LOG_ON=$(gad_run query config-get features.discussion_log --default false --raw 2>/dev/null || echo false)
TODO_THRESHOLD=$(gad_run query config-get features.todo_fold_threshold --default 0.4 --raw 2>/dev/null || echo 0.4)
# [C6] quantas fases entram INTEIRAS na vista do índice de decisões (advisory, nunca gate);
# as demais entram uma linha por D-NN com ponteiro. 1 = a fase anterior completa (~71 KB no
# inspired); 0 = só linhas (~43 KB). Fora do intervalo ou não numérico → 1.
INDEX_RECENT=$(gad_run query config-get features.decisions_index_recent --default 1 --raw 2>/dev/null || echo 1)
case "$INDEX_RECENT" in ''|*[!0-9]*) INDEX_RECENT=1 ;; esac

# [P08] contexto prévio — o bloco bash que morava no passo `load_prior_context` do workflow
# (decisões 5.1, 5.2, 5.4–5.6, 6.1; REQUIREMENTS.md íntegro por 5.3). Grava $T/prior.txt com
# o MESMO conteúdo que o bloco imprimia; o modelo lê o arquivo. Não vai para o stdout porque
# o índice de decisões sozinho pode passar de 200 KB e o stdout tem teto de 20 KB.
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
    # [C6] vista recortada: o arquivo canônico fica completo em disco (regra "nunca resumir"
    # rege o artefato); o que entra na janela é a vista, com ponteiro por decisão. Fail-open:
    # gerador ausente ou falho → arquivo inteiro, como antes.
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
  printf 'PHASE=%q\nphase_dir=%q\npadded_phase=%q\nPHASE_NUMBER=%q\nphase_name=%q\nNOSSO=%q\nT=%q\nSPEC_PATH=%q\nREQ_STATE=%q\nREQ_COUNT=%q\nREQ_IDS=%q\nREGRESSION_EMPTY=%q\nSCOPE_SRC=%q\nADVISOR_MODE=%q\nAGENT_SKILLS_ADVISOR=%q\nLOG_ON=%q\nTODO_THRESHOLD=%q\nPRE_SPEC=%q\nPRE_SPEC_STATE=%q\nPRE_SPEC_BATCH=%q\nPRE_SPEC_N=%q\nARTEFATOS_N=%q\nGRAY_ARTEFATOS=%q\nCKPT=%q\nCONTEXT_PATH=%q\n' \
    "$PHASE" "$phase_dir" "$padded_phase" "$PHASE_NUMBER" "$phase_name" "$NOSSO" "$T" "$SPEC_PATH" "$REQ_STATE" "$REQ_COUNT" "$REQ_IDS" "$REGRESSION_EMPTY" "$SCOPE_SRC" "$ADVISOR_MODE" "$AGENT_SKILLS_ADVISOR" "$LOG_ON" "$TODO_THRESHOLD" \
    "$PRE_SPEC" "$PRE_SPEC_STATE" "$PRE_SPEC_BATCH" "$PRE_SPEC_N" "$ARTEFATOS_N" "$T/gray-areas-artefatos.txt" \
    "${phase_dir}/${padded_phase}-DISCUSS-CHECKPOINT.json" "${phase_dir}/${padded_phase}-CONTEXT.md"
  # `. env.sh` define variáveis de SHELL; os scripts filhos (discuss-hooks-filter.sh e
  # companhia) rodam como PROCESSO e só enxergam o que estiver exportado. Sem isto o
  # hooks-filter falha fechado com "render-hooks discuss:post não devolveu nada".
  printf 'export GAD_TOOLS PHASE phase_dir padded_phase PHASE_NUMBER phase_name NOSSO T SPEC_PATH REQ_STATE REQ_COUNT REQ_IDS REGRESSION_EMPTY SCOPE_SRC ADVISOR_MODE AGENT_SKILLS_ADVISOR LOG_ON TODO_THRESHOLD PRE_SPEC PRE_SPEC_STATE PRE_SPEC_BATCH PRE_SPEC_N ARTEFATOS_N GRAY_ARTEFATOS CKPT CONTEXT_PATH\n'; } > "$T/env.sh"

printf '%s\n' "$INIT"
echo "PHASE_GOAL: $(cat "$T/goal.txt")"; echo "PHASE_CRITERIA:"; cat "$T/criteria.txt"
echo "CHECKS: $CHECKS"
echo "SPEC: state=$REQ_STATE count=$REQ_COUNT ids=[$REQ_IDS] scope=$SCOPE_SRC regression_empty=$REGRESSION_EMPTY files=$(grep -c . "$T/spec-files.txt" 2>/dev/null || true) pre_spec=$PRE_SPEC_STATE n=$PRE_SPEC_N"
echo "ROADMAP_REFS:"; cat "$T/refs-roadmap.txt"
echo "ADVISOR_MODE=$ADVISOR_MODE LOG_ON=$LOG_ON TODO_THRESHOLD=$TODO_THRESHOLD"
echo "PRE_SPEC: state=$PRE_SPEC_STATE decisoes=$PRE_SPEC_N batch=${PRE_SPEC_BATCH:-none} file=${PRE_SPEC:-none}"
echo "GRAY_AREAS_ARTEFATOS: $ARTEFATOS_N"; [ "$ARTEFATOS_N" -gt 0 ] && cat "$T/gray-areas-artefatos.txt"
echo "PRIOR: $T/prior.txt bytes=$(wc -c < "$T/prior.txt")"
echo "PRE_HOOKS: $DISCUSS_PRE_HOOKS_JSON"
