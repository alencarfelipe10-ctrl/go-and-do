#!/usr/bin/env bash
# spec-init.sh — passo 1+2 consolidados do gad-spec-phase (fork, tarefa 35 / ajuste S1).
#
# Uso (bloco bash do Step 1 do workflow):
#   bash "$NOSSO/spec-init.sh" "<PHASE>" [--pre-spec <arquivo>]
#
# Faz numa chamada só o que o workflow fazia em ~12 leituras: resolve o `gad-tools`
# (cascata curta — sem o preâmbulo de ~20 runtimes), chama `init phase-op` UMA vez e
# reaproveita os caminhos que ele devolve, e emite num resultado só:
#   · a entrada do ROADMAP da fase (Goal, critérios, seção inteira);
#   · a fatia do REQUIREMENTS.md (REQ-IDs da fase + os adjacentes citados dentro deles);
#   · os cabeçalhos do STATE.md + as seções que o Step 2 pede (decisões, bloqueios/
#     preocupações, adiados);
#   · os CABEÇALHOS do SPEC da fase anterior, como molde (nunca o corpo);
#   · o SPEC da própria fase, se já existe (rota "Update it" do Step 1);
#   · (R6) `goal_roadmap` + `issues` estruturadas + `req_ids_ausentes`.
# Grava `.planning/.spec-tmp/env.sh` (escalares + GAD_TOOLS + gad_run) para os blocos bash
# seguintes do workflow (5.5, 6.5, 7) — eles dão `source` nele em vez de re-resolver.
#
# GAD_TOOLS: se já vier do ambiente, é honrado (ponto de injeção dos testes). Senão, cascata
# curta: arquivo de estado da sessão → PATH → CLAUDE_CONFIG_DIR → GAD_RUNTIME_DIR/git toplevel.
#
# ── FORMATO DA SAÍDA ────────────────────────────────────────────────────────────
# Seções delimitadas em texto rotulado (mesma gramática do `discuss-init.sh` — "um texto,
# um comportamento"): cada seção abre com `=== <NOME> ===` na coluna 0 e vai até o próximo
# `=== `. A primeira seção, `INIT`, é o JSON cru do `init phase-op`. Nada de JSON aninhado
# em volta: o workflow lê prosa, e um bloco só evita um segundo parser.
# Seções, nesta ordem:
#   INIT · PHASE_ENTRY · ROADMAP_SECTION · REQUIREMENTS_SLICE · STATE_HEADINGS ·
#   STATE_SECTIONS · SPEC_ANTERIOR_HEADINGS · SPEC_ATUAL · PRE_SPEC · R6
# Desde o P10 (01/09/2026) o stdout é um ÍNDICE: o pacote inteiro fica em `.planning/.spec-tmp/`
# (section.md, reqs-slice.md, state-sections.md — caminhos exportados no env.sh) e as três seções
# grandes imprimem cabeçalho + tamanho + caminho + extrato curto. Motivo: na 24.4 real o corpo
# dava 68 KB (48 KB só o `### Decisions` do STATE), o Claude Code persiste stdout > ~50 KB em
# arquivo e o modelo gastava 3 turnos para reler. Teto duro de 20.480 B: passou, a seção mais
# longa é cortada com `[truncado: N B; veja o arquivo]`.
# Degrada sempre com `[fallback]`/`[warn]` em stderr; aborta (exit 2) sem `gad-tools` e, desde
# o P07 (01/09/2026), quando o `init phase-op` devolve dado ruim: JSON vazio/inválido, sem
# `phase_dir`, ou um campo `*_model` que não é apelido do Agent. Motivo: seguir com esse dado
# só adia a falha para o despacho do agente, sem o valor na mensagem.
set -u

PHASE=""; PRE_SPEC_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pre-spec) PRE_SPEC_ARG="${2:-}"; shift 2 || true ;;
    --pre-spec=*) PRE_SPEC_ARG="${1#--pre-spec=}"; shift ;;
    -*) echo "ERROR: flag desconhecida: $1" >&2; exit 2 ;;
    *) [ -z "$PHASE" ] && PHASE="$1" || { echo "ERROR: argumento extra: $1" >&2; exit 2; }; shift ;;
  esac
done
[ -n "$PHASE" ] || { echo "ERROR: uso: spec-init.sh <PHASE> [--pre-spec <arquivo>]" >&2; exit 2; }

# ── cascata curta do gad-tools ────────────────────────────────────────────────
_GAD_HOME=""; _GAD_STATE=""
for _c in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/gad-tools.cjs"; do
  [ -n "$_c" ] && [ -f "$_c" ] && _GAD_HOME="$(readlink -f "$(dirname "$(dirname "$(dirname "$(readlink -f "$_c")")")")" 2>/dev/null)" && break
done
[ -n "$_GAD_HOME" ] && _GAD_STATE="${TMPDIR:-/tmp}/gad-tools-path.$(id -u).$(printf '%s' "$_GAD_HOME" | md5sum | cut -c1-8)"
if [ -z "${GAD_TOOLS:-}" ] && [ -n "$_GAD_STATE" ] && [ -f "$_GAD_STATE" ]; then
  _cand="$(cat "$_GAD_STATE" 2>/dev/null || true)"; [ -n "$_cand" ] && [ -f "$_cand" ] && GAD_TOOLS="$_cand"
fi
if [ -z "${GAD_TOOLS:-}" ]; then
  _rt="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  for _c in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/gad-tools.cjs" \
            "$_rt/gad-core/bin/gad-tools.cjs" "$_rt/.claude/gad-core/bin/gad-tools.cjs"; do
    [ -f "$_c" ] && { GAD_TOOLS="$_c"; break; }
  done
fi
[ -n "${GAD_TOOLS:-}" ] && [ -f "$GAD_TOOLS" ] || {
  echo "ERRO: motor do go-and-do (gad-core) não encontrado (cascata curta: \$GAD_TOOLS, estado da sessão, CLAUDE_CONFIG_DIR, GAD_RUNTIME_DIR) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }
case "$GAD_TOOLS" in *.cjs) gad_run() { node "$GAD_TOOLS" "$@"; } ;; *) gad_run() { "$GAD_TOOLS" "$@"; } ;; esac
[ -n "$_GAD_STATE" ] && { printf '%s\n' "$GAD_TOOLS" > "$_GAD_STATE" 2>/dev/null || true; }

_py() { command -v python3 >/dev/null 2>&1 && python3 "$@"; }
_json() {  # lê JSON do stdin, imprime o campo pedido (vazio se ausente)
  python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: d={}
v=d.get(sys.argv[1]); print("" if v is None else v)' "$1" 2>/dev/null || true
}

# ── init phase-op: UMA chamada, todos os caminhos ─────────────────────────────
INIT=$(gad_run init phase-op "${PHASE}" 2>/dev/null || echo '{}')
case "$INIT" in @file:*) INIT=$(cat "${INIT#@file:}" 2>/dev/null || echo '{}') ;; esac
# ── conferência de entrada (P07): quem lê o init não segue com dado ruim ───────
# Apelidos aceitos pelo Agent do Claude Code: opus|sonnet|haiku|fable (+ inherit). Um ID
# completo (ex.: claude-opus-4-8, de resolve_model_ids:true) é descartado pelo spawner.
_ERR=$(printf '%s' "$INIT" | python3 -c '
import json, re, sys
try: d = json.load(sys.stdin)
except Exception: d = None
if not isinstance(d, dict) or not d:
    print("init phase-op devolveu JSON vazio ou inválido"); sys.exit(0)
if not (d.get("phase_dir") or d.get("expected_phase_dir")):
    print("init phase-op sem phase_dir nem expected_phase_dir"); sys.exit(0)
for k, v in d.items():
    if k.endswith("_model") and not re.fullmatch(r"opus|sonnet|haiku|fable|inherit", str(v)):
        print(f"modelo inválido para o Agent: {v}; ajuste resolve_model_ids ou o catálogo (campo {k})"); sys.exit(0)
' 2>/dev/null)
[ -z "$_ERR" ] || { echo "ERROR: $_ERR" >&2; exit 2; }
phase_found=$(printf '%s' "$INIT" | _json phase_found)
phase_dir=$(printf '%s' "$INIT" | _json phase_dir); [ -n "$phase_dir" ] || phase_dir=$(printf '%s' "$INIT" | _json expected_phase_dir)
padded_phase=$(printf '%s' "$INIT" | _json padded_phase)
PHASE_NUMBER=$(printf '%s' "$INIT" | _json phase_number); [ -n "$PHASE_NUMBER" ] || PHASE_NUMBER="$PHASE"
phase_name=$(printf '%s' "$INIT" | _json phase_name)
phase_slug=$(printf '%s' "$INIT" | _json phase_slug)
state_path=$(printf '%s' "$INIT" | _json state_path)
requirements_path=$(printf '%s' "$INIT" | _json requirements_path)
roadmap_path=$(printf '%s' "$INIT" | _json roadmap_path)
response_language=$(printf '%s' "$INIT" | _json response_language)
commit_docs=$(printf '%s' "$INIT" | _json commit_docs)

T=".planning/.spec-tmp"; rm -rf "$T"; mkdir -p "$T"
NOSSO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# ── entrada do ROADMAP da fase ────────────────────────────────────────────────
PHASE_JSON=$(gad_run roadmap get-phase "${PHASE}" 2>/dev/null || echo '{"found":false}')
printf '%s' "$PHASE_JSON" | python3 -c '
import json,sys,os
T=sys.argv[1]
try: j=json.load(sys.stdin)
except Exception: j={"found":False}
if not j.get("found"):
    sys.stderr.write("[fallback] roadmap get-phase sem resultado — a seção vem do ROADMAP.md por regex\n")
    for n in ("goal","criteria"): open(os.path.join(T,n+".txt"),"w").write("")
    open(os.path.join(T,"section.md"),"w").write("")
    raise SystemExit(0)
open(os.path.join(T,"goal.txt"),"w").write((j.get("goal") or "")+"\n")
open(os.path.join(T,"criteria.txt"),"w").write("\n".join("SC%d: %s"%(i+1,c) for i,c in enumerate(j.get("success_criteria") or []))+"\n")
open(os.path.join(T,"section.md"),"w").write((j.get("section") or "")+"\n")
_pn=j.get("phase_name") or ""
open(os.path.join(T,"phase_name.txt"),"w").write(_pn+"\n")
' "$T" 2>>"$T/warn.txt" || true
_pn=$(head -1 "$T/phase_name.txt" 2>/dev/null || true); [ -n "$_pn" ] && phase_name="$_pn"

# ── R6 + seção do ROADMAP por regex (fallback e fonte das issues) ─────────────
[ -n "$roadmap_path" ] || roadmap_path=".planning/ROADMAP.md"
[ -n "$requirements_path" ] || requirements_path=".planning/REQUIREMENTS.md"
[ -n "$state_path" ] || state_path=".planning/STATE.md"

python3 - "$roadmap_path" "$requirements_path" "$PHASE_NUMBER" "$T" <<'PY' 2>>"$T/warn.txt" || true
import json, os, re, sys
roadmap, reqs, nn, T = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def ler(p):
    try: return open(p, encoding="utf-8", errors="replace").read()
    except Exception: return ""

linhas = ler(roadmap).split("\n")
# Heading de detalhe em INGLÊS (`### Phase NN`) — o parser do GAD e o nosso leem o mesmo.
# O lookahead impede que a fase 24 case com a entrada da 24.3.
rx_ini  = re.compile(r'^#{2,4}\s+Phase\s+' + re.escape(nn) + r'(?![\w.])', re.I)
rx_head = re.compile(r'^#{1,4}\s')
ini = next((i for i, l in enumerate(linhas) if rx_ini.match(l)), None)

saida = {"goal_roadmap": None, "issues": [], "requirements_line": None,
         "req_ids": [], "req_ids_ausentes": [], "roadmap_entrada": ini is not None}
secao = ""
if ini is None:
    saida["motivo"] = "nenhuma entrada `### Phase %s` no ROADMAP" % nn
else:
    fim = next((j for j in range(ini + 1, len(linhas)) if rx_head.match(linhas[j])), len(linhas))
    entrada = linhas[ini + 1:fim]
    secao = "\n".join(linhas[ini:fim])
    RX_GOAL = re.compile(r'^\*\*Goal[^:]*:\*{0,2}\s*(.*)$')
    RX_REQ  = re.compile(r'^\*\*Requirements?[^:]*:\*{0,2}\s*(.*)$', re.I)
    # Id de requisito: prefixo de 2+ maiúsculas + sufixo com dígito. Mesmas duas travas do
    # setup-intencao.sh (mata `D-nn` de decisões e `PRE-SPEC`/`MUST-NOT`).
    RX_ID   = re.compile(r'\b[A-Z]{2,}[A-Z0-9]*(?:-[A-Za-z0-9]+)+\b')
    aberto = False
    for l in entrada:
        if saida["goal_roadmap"] is None or aberto:
            m = RX_GOAL.match(l)
            if m and m.group(1).strip():
                saida["goal_roadmap"] = m.group(1).strip(); aberto = True
            elif aberto:
                if not l.strip() or l.lstrip().startswith(("**", "-", "|", ">")): aberto = False
                else: saida["goal_roadmap"] += " " + l.strip()
        if saida["requirements_line"] is None:
            m = RX_REQ.match(l)
            if m: saida["requirements_line"] = m.group(1).strip()
    ids = []
    if saida["requirements_line"]:
        for m in RX_ID.finditer(saida["requirements_line"]):
            if not re.search(r'\d', m.group(0).rsplit("-", 1)[-1]): continue
            if m.group(0) not in ids: ids.append(m.group(0))
    saida["req_ids"] = ids
    txt_reqs = ler(reqs)
    if not ids:
        saida["issues"].append({"tipo": "phase_without_req_id"})
    else:
        for i in ids:
            if not txt_reqs or not re.search(r'(?<![A-Za-z0-9-])' + re.escape(i) + r'(?![A-Za-z0-9-])', txt_reqs):
                saida["issues"].append({"tipo": "missing_requirement", "id": i})
                saida["req_ids_ausentes"].append(i)
        if not txt_reqs:
            saida["motivo"] = "REQUIREMENTS.md ausente — todo id citado conta como ausente"

open(os.path.join(T, "r6.json"), "w", encoding="utf-8").write(json.dumps(saida, ensure_ascii=False))
if secao and not (ler(os.path.join(T, "section.md")).strip()):
    open(os.path.join(T, "section.md"), "w", encoding="utf-8").write(secao + "\n")
if secao and not ler(os.path.join(T, "goal.txt")).strip() and saida["goal_roadmap"]:
    open(os.path.join(T, "goal.txt"), "w", encoding="utf-8").write(saida["goal_roadmap"] + "\n")

# ── fatia do REQUIREMENTS: blocos dos ids da fase + adjacentes citados neles ──
txt = ler(reqs)
fatia = []
if txt and saida["req_ids"]:
    ls = txt.split("\n")
    rxh = re.compile(r'^#{1,6}\s')
    def bloco_do(idx):
        ini_b = idx
        for k in range(idx, -1, -1):
            if rxh.match(ls[k]): ini_b = k; break
        else: ini_b = idx
        nivel = len(ls[ini_b]) - len(ls[ini_b].lstrip("#")) if rxh.match(ls[ini_b]) else 99
        fim_b = len(ls)
        for k in range(ini_b + 1, len(ls)):
            if rxh.match(ls[k]):
                n2 = len(ls[k]) - len(ls[k].lstrip("#"))
                if n2 <= nivel: fim_b = k; break
        return ini_b, fim_b
    vistos, blocos = set(), []
    fila = list(saida["req_ids"]); nivel_de = {i: 0 for i in fila}
    RX_ID = re.compile(r'\b[A-Z]{2,}[A-Z0-9]*(?:-[A-Za-z0-9]+)+\b')
    while fila:
        rid = fila.pop(0)
        if rid in vistos: continue
        vistos.add(rid)
        rx = re.compile(r'(?<![A-Za-z0-9-])' + re.escape(rid) + r'(?![A-Za-z0-9-])')
        alvo = next((i for i, l in enumerate(ls) if rx.search(l)), None)
        if alvo is None: continue
        a, b = bloco_do(alvo)
        corpo = ls[a:b]
        blocos.append((rid, nivel_de.get(rid, 0), corpo))
        if nivel_de.get(rid, 0) == 0:   # só um nível de adjacência
            for m in RX_ID.finditer("\n".join(corpo)):
                v = m.group(0)
                if re.search(r'\d', v.rsplit("-", 1)[-1]) and v not in vistos and v not in fila:
                    fila.append(v); nivel_de[v] = 1
    for rid, nv, corpo in blocos:
        fatia.append("--- %s%s ---" % (rid, "  (adjacente citado)" if nv else ""))
        fatia.extend(corpo); fatia.append("")
elif not txt:
    fatia.append("[warn] REQUIREMENTS.md não encontrado em %s" % reqs)
elif not saida["req_ids"]:
    fatia.append("[fallback] a entrada do ROADMAP não cita REQ-ID — leia o REQUIREMENTS.md inteiro (%s)" % reqs)
open(os.path.join(T, "reqs-slice.md"), "w", encoding="utf-8").write("\n".join(fatia) + "\n")
PY

# ── STATE: cabeçalhos + só as seções que o Step 2 pede ────────────────────────
: > "$T/state-headings.txt"; : > "$T/state-sections.md"
if [ -f "$state_path" ]; then
  grep -n '^##' "$state_path" > "$T/state-headings.txt" 2>/dev/null || true
  # decisões · bloqueios/preocupações · adiados — bilíngue, o heading varia por projeto
  while IFS= read -r h; do
    h=${h#*:}; h=$(printf '%s' "$h" | sed -E 's/^#+[[:space:]]*//')
    case "$(printf '%s' "$h" | tr 'A-ZÀ-Ý' 'a-zà-ý')" in
      *decis*|*decision*|*blocker*|*bloque*|*concern*|*preocupa*|*defer*|*adiad*|*postpon*)
        body=$(gad_run state get "$h" 2>/dev/null || true)
        if [ -z "$body" ]; then
          body=$(awk -v H="$h" 'BEGIN{p=0} /^##/{ if(p){exit}; t=$0; sub(/^#+[ \t]*/,"",t); if(t==H){p=1; print; next} } p{print}' "$state_path")
          [ -n "$body" ] && echo "[fallback] state get \"$h\" vazio — seção lida do arquivo" >&2
        fi
        { printf '## %s\n' "$h"; printf '%s\n\n' "$body"; } >> "$T/state-sections.md" ;;
    esac
  done < "$T/state-headings.txt"
else
  echo "[warn] STATE.md não encontrado em $state_path" >&2
fi

# ── SPEC da própria fase + cabeçalhos do SPEC anterior (molde) ────────────────
# `ls | grep -vE 'AI-SPEC|PRE-SPEC'` — o PRE-SPEC é insumo da /go-and-do, não é o SPEC.
SPEC_ATUAL=""
if [ -n "$phase_dir" ] && [ -d "$phase_dir" ]; then
  SPEC_ATUAL=$(ls "$phase_dir"/*-SPEC.md 2>/dev/null | grep -vE 'AI-SPEC|PRE-SPEC' | head -1 || true)
fi
SPEC_ANTERIOR=""
if [ -n "$phase_dir" ]; then
  SPEC_ANTERIOR=$(python3 - "$phase_dir" <<'PY' 2>/dev/null || true
import os, re, sys, glob
pd = sys.argv[1].rstrip("/")
base = os.path.dirname(pd) or "."
def num(d):
    m = re.match(r'^(\d+(?:\.\d+)?)', os.path.basename(d))
    return float(m.group(1)) if m else None
atual = num(pd)
cands = []
if atual is not None and os.path.isdir(base):
    for d in sorted(os.listdir(base)):
        p = os.path.join(base, d)
        if not os.path.isdir(p): continue
        n = num(p)
        if n is not None and n < atual: cands.append((n, p))
for _, p in sorted(cands, reverse=True):
    for f in sorted(glob.glob(os.path.join(p, "*-SPEC.md"))):
        if re.search(r'(AI-SPEC|PRE-SPEC)', os.path.basename(f)): continue
        print(f); raise SystemExit(0)
PY
)
fi
: > "$T/spec-anterior-headings.txt"
if [ -n "$SPEC_ANTERIOR" ] && [ -f "$SPEC_ANTERIOR" ]; then
  { echo "# molde: $SPEC_ANTERIOR"; grep -E '^#{1,6} ' "$SPEC_ANTERIOR"; } > "$T/spec-anterior-headings.txt"
fi

# ── PRE-SPEC ──────────────────────────────────────────────────────────────────
PRE_SPEC="$PRE_SPEC_ARG"
if [ -z "$PRE_SPEC" ] && [ -n "$phase_dir" ] && [ -d "$phase_dir" ]; then
  PRE_SPEC=$(ls "$phase_dir"/*-PRE-SPEC.md 2>/dev/null | head -1 || true)
fi
PRE_SPEC_BLOCO=ausente
if [ -n "$PRE_SPEC" ] && [ -f "$PRE_SPEC" ]; then
  grep -q '<!-- gad:decisoes:begin' "$PRE_SPEC" && PRE_SPEC_BLOCO=presente
else
  [ -n "$PRE_SPEC" ] && { echo "[warn] --pre-spec $PRE_SPEC não existe" >&2; PRE_SPEC=""; }
  PRE_SPEC_BLOCO=nao_aplicavel
fi

# ── env.sh para os blocos bash seguintes (5.5, 6.5, 7 dão `source`) ───────────
{ printf 'GAD_TOOLS=%q\n' "$GAD_TOOLS"
  printf 'case "$GAD_TOOLS" in *.cjs) gad_run() { node "$GAD_TOOLS" "$@"; } ;; *) gad_run() { "$GAD_TOOLS" "$@"; } ;; esac\n'
  printf 'PHASE=%q\nphase_dir=%q\npadded_phase=%q\nPHASE_NUMBER=%q\nphase_name=%q\nphase_slug=%q\nNOSSO=%q\nT=%q\nstate_path=%q\nrequirements_path=%q\nroadmap_path=%q\nresponse_language=%q\ncommit_docs=%q\nSPEC_ATUAL=%q\nSPEC_ANTERIOR=%q\nPRE_SPEC=%q\nPRE_SPEC_BLOCO=%q\nSPEC_PATH=%q\n' \
    "$PHASE" "$phase_dir" "$padded_phase" "$PHASE_NUMBER" "$phase_name" "$phase_slug" "$NOSSO" "$T" \
    "$state_path" "$requirements_path" "$roadmap_path" "$response_language" "$commit_docs" \
    "$SPEC_ATUAL" "$SPEC_ANTERIOR" "$PRE_SPEC" "$PRE_SPEC_BLOCO" \
    "${phase_dir}/${padded_phase}-SPEC.md"
  # P10: caminhos do pacote — o stdout é índice; quem precisar do corpo abre SÓ a seção, por aqui
  printf 'SECTION_MD=%q\nREQS_SLICE_MD=%q\nSTATE_SECTIONS_MD=%q\n' "$T/section.md" "$T/reqs-slice.md" "$T/state-sections.md"; } > "$T/env.sh"

# ── resultado único: índice com teto (P10) ────────────────────────────────────
# As 10 seções continuam (o teste grepa os rótulos). INIT, PHASE_ENTRY, STATE_HEADINGS,
# SPEC_ANTERIOR_HEADINGS, SPEC_ATUAL, PRE_SPEC e R6 saem inteiras (são pequenas). ROADMAP_SECTION,
# REQUIREMENTS_SLICE e STATE_SECTIONS saem como índice: cabeçalho, tamanho, caminho e extrato.
SI_PHASE_ENTRY="phase_found=${phase_found:-} phase_dir=${phase_dir} padded_phase=${padded_phase} phase_name=${phase_name}
response_language=${response_language} commit_docs=${commit_docs}
GOAL: $(cat "$T/goal.txt" 2>/dev/null)
CRITERIA:
$(cat "$T/criteria.txt" 2>/dev/null || true)"
if [ -n "$SPEC_ATUAL" ]; then SI_SPEC_ATUAL="existe: $SPEC_ATUAL"; else SI_SPEC_ATUAL="ausente"; fi
SI_PRE_SPEC="path=${PRE_SPEC:-} bloco=${PRE_SPEC_BLOCO}"; SI_INIT="$INIT"
export SI_INIT SI_PHASE_ENTRY SI_SPEC_ATUAL SI_PRE_SPEC
if ! python3 - "$T" "$state_path" <<'PY'
import os, re, sys
T, state_path = sys.argv[1], sys.argv[2]
TETO = 20480            # bytes; acima disso o Claude Code persiste o stdout em arquivo
EXTRATO_ROADMAP = 15    # primeiras linhas da seção do ROADMAP

def ler(p):
    try: return open(p, encoding="utf-8", errors="replace").read()
    except Exception: return ""
def tam(p):
    try: return os.path.getsize(p)
    except OSError: return 0
def ref(p): return "%s (%d B, %d linhas)" % (p, tam(p), ler(p).count("\n"))

secoes = []  # (nome, corpo sem o rótulo, caminho do arquivo ou None)
secoes.append(("INIT", os.environ.get("SI_INIT", "") + "\n", None))
secoes.append(("PHASE_ENTRY", os.environ.get("SI_PHASE_ENTRY", "") + "\n", None))

# ROADMAP_SECTION: as primeiras linhas + caminho
p = os.path.join(T, "section.md"); txt = ler(p)
if not txt.strip():
    corpo = ""
else:
    ls = txt.rstrip("\n").split("\n")
    corpo = "[índice] arquivo: %s — abaixo, as %d primeiras linhas\n" % (ref(p), min(EXTRATO_ROADMAP, len(ls)))
    corpo += "\n".join(ls[:EXTRATO_ROADMAP]) + "\n"
    if len(ls) > EXTRATO_ROADMAP:
        corpo += "[… +%d linhas: sed -n '%d,$p' %s]\n" % (len(ls) - EXTRATO_ROADMAP, EXTRATO_ROADMAP + 1, p)
secoes.append(("ROADMAP_SECTION", corpo, p))

# REQUIREMENTS_SLICE: só as linhas de id (`--- ID ---`), os headings dos blocos e avisos + caminho
p = os.path.join(T, "reqs-slice.md"); txt = ler(p)
if not txt.strip():
    corpo = ""
else:
    ls = txt.rstrip("\n").split("\n")
    rx = re.compile(r'^(--- |#{1,6} |\[warn\]|\[fallback\])')
    idx = [l for l in ls if rx.match(l)]
    corpo = "[índice] arquivo: %s — ids e títulos dos blocos; corpo de um bloco: grep -n -A20 'ID' no arquivo\n" % ref(p)
    corpo += "\n".join(idx) + "\n"
secoes.append(("REQUIREMENTS_SLICE", corpo, p))

secoes.append(("STATE_HEADINGS", ler(os.path.join(T, "state-headings.txt")), None))

# STATE_SECTIONS: decisões viram índice (uma linha por decisão); bloqueios e adiados inteiros
RX_DEC = re.compile(r'decis|decision', re.I)
def desembrulhar(b):
    # `gad-tools state get` devolve {"Heading": "corpo"} em JSON; o fallback awk devolve markdown.
    # O arquivo guarda o que veio; o stdout mostra o corpo legível nos dois casos.
    try:
        import json
        d = json.loads(b)
        if isinstance(d, dict) and d and all(isinstance(v, str) for v in d.values()):
            return "\n".join(d.values())
    except Exception:
        pass
    return b
def indice_decisoes(body):
    # devolve (n, omitidas, itens[(tag, linha)]) — uma linha por decisão; a renderização decide
    # quantas cabem (as antigas colapsam por rótulo, as recentes ficam inteiras)
    itens, n, omitidas = [], 0, 0
    for l in body.split("\n"):
        if re.match(r'^#{1,6}\s', l) and not l.startswith("## "):
            itens.append(("", l.strip())); continue     # subtítulos (grupos) ficam
        m = re.match(r'^[-*]\s+(.*\S)', l)
        if not m:
            if l.strip(): omitidas += 1
            continue
        n += 1
        plain = re.sub(r'\*\*|__|~~', '', m.group(1)).strip()
        mid = re.match(r'^(D-\d+[A-Za-z]?)\b\s*', plain)
        did = mid.group(1) if mid else "d%02d" % n
        if mid: plain = plain[mid.end():].lstrip(":—- ")
        # rótulos `[v3.1]`/`[Phase 13]` (o último não-`?` vence), depois o id do plano `13-02:`
        tag = ""
        while True:
            mtag = re.match(r'^\[([^\]]{1,40})\]\s*:?\s*', plain)
            if not mtag: break
            if mtag.group(1).strip() != "Phase ?" or not tag: tag = mtag.group(1).strip()
            plain = plain[mtag.end():]
        mpl = re.match(r'^(?:Plano\s+)?(\d+(?:\.\d+)?-\d+)\s*:?\s+', plain)
        plano = mpl.group(1) if mpl else ""
        if mpl: plain = plain[mpl.end():]
        k = plain.find(":")
        titulo = plain[:k].strip() if 0 < k <= 80 else plain[:70].rstrip() + ("…" if len(plain) > 70 else "")
        itens.append((tag or "sem rótulo", "- %s — %s%s" % (did, (plano + " · ") if plano else "", titulo)))
    return n, omitidas, itens

def render_indice(n, omitidas, itens, arq, orcamento):
    # agrupa por rótulo consecutivo; colapsa os grupos mais antigos até caber no orçamento
    grupos = []
    for tag, linha in itens:
        if not tag:
            grupos.append([None, [linha]]); continue
        if grupos and grupos[-1][0] == tag: grupos[-1][1].append(linha)
        else: grupos.append([tag, [linha]])
    def render(colapsados):
        out = []
        for i, (tag, ls) in enumerate(grupos):
            if tag is None: out.extend(ls)
            elif i < colapsados:
                ids = [re.match(r'- (\S+)', l).group(1) for l in ls]
                out.append("- [%s]: %d %s (%s–%s) — só no arquivo" % (tag, len(ls), "decisão" if len(ls) == 1 else "decisões", ids[0], ids[-1]))
            else:
                out.append("[%s]" % tag); out.extend(ls)
        return "\n".join(out) + "\n"
    # o corpo pode ser JSON de uma linha (state get) ou markdown (fallback): o awk fatia por
    # bullet nos dois casos; grep -n devolveria a linha inteira de dezenas de KB no primeiro
    cab = "[índice] %d decisões (%d linhas de corpo omitidas); corpo em %s — abra uma decisão por vez: awk -v RS='\\\\\\\\n- |\\n- ' '/trecho do título/' ARQUIVO\n" % (n, omitidas, ref(arq))
    c = 0
    while c < len(grupos) and len((cab + render(c)).encode("utf-8")) > orcamento: c += 1
    if c: cab = cab.rstrip("\n") + " (os %d rótulos mais antigos colapsados em 1 linha cada)\n" % c
    return cab + render(c)

p = os.path.join(T, "state-sections.md"); txt = ler(p)
DEC = None   # (heading, n, omitidas, itens) — renderizado no fim, com o orçamento que sobrar
if not txt.strip():
    corpo = ""
else:
    partes, atual = [], None
    for l in txt.split("\n"):
        if l.startswith("## "):
            h = l[3:].strip()
            # o fallback awk grava o heading dentro do corpo: `## X` seguido de `## X` é uma seção só
            if partes and partes[-1][0] == h and not "".join(partes[-1][1]).strip():
                continue
            atual = [h, []]; partes.append(atual)
        elif atual is not None:
            atual[1].append(l)
    corpo = ""
    for h, body in partes:
        b = desembrulhar("\n".join(body).strip("\n"))
        if RX_DEC.search(h) and DEC is None:
            DEC = (h,) + indice_decisoes(b)
            corpo += "## %s\n@@DECISOES@@\n" % h
        else:
            corpo += "## %s\n%s\n\n" % (h, b)
    di = os.path.join(os.path.dirname(state_path) or ".planning", "DECISIONS-INDEX.md")
    if os.path.isfile(di):
        fases = sum(1 for l in ler(di).split("\n") if l.startswith("## "))
        corpo += "DECISIONS-INDEX.md: %s (%d B, %d fases) — decisões dos CONTEXT.md por fase; abra uma fase: grep -n '^## Phase' e sed -n\n" % (di, tam(di), fases)
secoes.append(("STATE_SECTIONS", corpo, p))

p = os.path.join(T, "spec-anterior-headings.txt")
secoes.append(("SPEC_ANTERIOR_HEADINGS", ler(p) if tam(p) else "[nenhum SPEC de fase anterior — sem molde]\n", None))
secoes.append(("SPEC_ATUAL", os.environ.get("SI_SPEC_ATUAL", "ausente") + "\n", None))
secoes.append(("PRE_SPEC", os.environ.get("SI_PRE_SPEC", "") + "\n", None))
r6 = ler(os.path.join(T, "r6.json"))
secoes.append(("R6", (r6.rstrip("\n") if r6.strip() else "{}") + "\n\n", None))

def montar():
    return "".join("=== %s ===\n%s" % (n, c) for n, c, _ in secoes)
# índice das decisões: recebe o orçamento que sobra depois de tudo o mais (margem de 512 B)
if DEC is not None:
    i = next(k for k, sec in enumerate(secoes) if sec[0] == "STATE_SECTIONS")
    nome, corpo, arq = secoes[i]
    resto = len(montar().replace("@@DECISOES@@\n", "").encode("utf-8"))
    idx = render_indice(DEC[1], DEC[2], DEC[3], arq, TETO - resto - 512)
    secoes[i] = (nome, corpo.replace("@@DECISOES@@\n", idx + "\n"), arq)
# teto duro: corta a seção mais longa, quantas vezes for preciso, avisando
for _ in range(10):
    total = len(montar().encode("utf-8"))
    if total <= TETO: break
    i = max(range(len(secoes)), key=lambda k: len(secoes[k][1].encode("utf-8")))
    nome, corpo, arq = secoes[i]
    aviso = "[truncado: %d B; veja o arquivo %s]\n" % (len(corpo.encode("utf-8")), arq or "em .planning/.spec-tmp/")
    cabe = len(corpo.encode("utf-8")) - (total - TETO) - len(aviso.encode("utf-8"))
    cortado = corpo.encode("utf-8")[:max(cabe, 0)].decode("utf-8", "ignore")
    cortado = cortado[:cortado.rfind("\n") + 1] if "\n" in cortado else ""
    secoes[i] = (nome, cortado + aviso, arq)
sys.stdout.buffer.write(montar().encode("utf-8"))
PY
then
  # sem python3 (ou erro nele): degrada para o corpo inteiro, como antes do P10
  echo "[fallback] índice do stdout indisponível — corpo inteiro" >&2
  echo "=== INIT ==="; printf '%s\n' "$INIT"
  echo "=== PHASE_ENTRY ==="; printf '%s\n' "$SI_PHASE_ENTRY"
  echo "=== ROADMAP_SECTION ==="; cat "$T/section.md" 2>/dev/null || true
  echo "=== REQUIREMENTS_SLICE ==="; cat "$T/reqs-slice.md" 2>/dev/null || true
  echo "=== STATE_HEADINGS ==="; cat "$T/state-headings.txt" 2>/dev/null || true
  echo "=== STATE_SECTIONS ==="; cat "$T/state-sections.md" 2>/dev/null || true
  echo "=== SPEC_ANTERIOR_HEADINGS ==="
  if [ -s "$T/spec-anterior-headings.txt" ]; then cat "$T/spec-anterior-headings.txt"; else echo "[nenhum SPEC de fase anterior — sem molde]"; fi
  echo "=== SPEC_ATUAL ==="; echo "$SI_SPEC_ATUAL"
  echo "=== PRE_SPEC ==="; echo "$SI_PRE_SPEC"
  echo "=== R6 ==="; cat "$T/r6.json" 2>/dev/null || echo '{}'
  echo
fi
[ -s "$T/warn.txt" ] && cat "$T/warn.txt" >&2
exit 0
