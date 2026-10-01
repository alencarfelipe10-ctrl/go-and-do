#!/usr/bin/env bash
# context-guard.sh — guarda estrutural do NN-CONTEXT.md (gad-discuss-phase, fork).
#
# Uso: context-guard.sh <CONTEXT.md> [--spec <SPEC.md>] [--reqs "R1 R2 R3"] [--root DIR] [--gad-lib DIR]
#
# Dois níveis de saída (decisão [C2-28], ok do Felipe em 25/08/2026):
#   WARN → exit 0  : qualidade e refs — path MISSING em <canonical_refs>, âncora órfã,
#                    Claude's Discretion vazio, <task/<plan dentro dos racionais.
#   FAIL → exit 2  : invariantes que só um renderer com bug produz — tag ausente,
#                    desbalanceada ou fora da ordem do template; <spec_lock> sem --spec
#                    (ou --spec sem <spec_lock>); SPEC ausente de <canonical_refs>;
#                    [R5c] artefato novo commitado do SPEC sem D-NN que o cubra;
#                    `### Claude's Discretion` / `## Deferred Ideas` ausentes; parser real
#                    (decisions.cjs extractDecisions) devolvendo could-not-parse.
# Nunca bloqueia por juízo de qualidade — só por corrupção determinística.
#
# Checagem 8 (C1, plano 2 / 05/09/2026) — repetição literal do SPEC: um bullet D-NN cuja
# maior corrida de palavras consecutivas presentes no SPEC chega a GUARD_SHINGLE (15) vira
# `WARN: D-NN repete <k> palavras do SPEC literalmente — use ponteiro (§C1)`. Medido na 24.4:
# 15 acusa exatamente as 6 cópias da PRE-SPEC (D-01, D-04, D-05, D-06, D-07, D-09) e nenhuma
# decisão útil; 12 acusaria também D-11, D-15, D-17, D-18, D-20, que só citam o mesmo
# arquivo:linha do SPEC. WARN, nunca FAIL: quem age é o passo 3 do intent-discuss.md.
#
# [R5c] Convenção de casamento artefato ↔ decisão (documentada aqui porque é o contrato
# que a guarda cobra): a seção `## Artefatos novos commitados` do SPEC é lida pelo
# bin/nosso/artefatos-novos.py — o MESMO parser que o discuss-init.sh usa para emitir as
# gray areas (R5b), justamente para a guarda nunca cobrar artefato que o init não mostrou.
# Um artefato está COBERTO quando o **caminho aparece literalmente no texto de algum bullet
# `- **D-NN…`** dentro de <decisions> (crases ignoradas). É o casamento mais barato de
# escrever e de conferir: quem decide sobre um artefato cita o caminho dele. Seção vazia
# (ou ausente) → nada a cobrar.
set -u
GUARD_SHINGLE="${GUARD_SHINGLE:-15}"   # checagem 8: corrida mínima (em palavras) para avisar
CTX=""; SPEC=""; REQS=""; ROOT="."; LIB=""
while [ $# -gt 0 ]; do
  case "$1" in
    --spec) SPEC="$2"; shift 2 ;;
    --reqs) REQS="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    --gad-lib) LIB="$2"; shift 2 ;;
    -*) echo "[guard] unknown flag $1" >&2; exit 2 ;;
    *) CTX="$1"; shift ;;
  esac
done
[ -n "$CTX" ] && [ -f "$CTX" ] || { echo "[guard] FAIL: CONTEXT not found: $CTX"; exit 2; }
if [ -z "$LIB" ]; then
  _self="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
  LIB="$(dirname "$_self")/lib"
  [ -f "$LIB/decisions.cjs" ] || LIB="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/lib"
fi
fails=(); warns=()
fail() { fails+=("$1"); }
warn() { warns+=("$1"); }

# 1) Tags: presentes, balanceadas, na ordem do template.
ORDER="domain spec_lock decisions canonical_refs code_context specifics deferred"
seq=""
for t in $ORDER; do
  o=$(grep -c "^<$t>\s*$" "$CTX"); c=$(grep -c "^</$t>\s*$" "$CTX")
  if [ "$t" = "spec_lock" ]; then
    if [ -n "$SPEC" ] && [ "$o" -ne 1 ]; then fail "<spec_lock> expected (SPEC given) but found $o"; fi
    if [ -z "$SPEC" ] && [ "$o" -ne 0 ]; then fail "<spec_lock> present without SPEC"; fi
    [ "$o" -eq "$c" ] || fail "<spec_lock> unbalanced ($o open / $c close)"
  else
    [ "$o" -eq 1 ] || fail "<$t> expected exactly once, found $o"
    [ "$c" -eq 1 ] || fail "</$t> expected exactly once, found $c"
  fi
done
actual=$(grep -oE '^<(domain|spec_lock|decisions|canonical_refs|code_context|specifics|deferred)>' "$CTX" | tr -d '<>' | tr '\n' ' ')
expected=""
for t in $ORDER; do
  if [ "$t" = "spec_lock" ] && [ -z "$SPEC" ]; then continue; fi
  expected="$expected$t "
done
[ "$actual" = "$expected" ] || fail "tag order '$actual' ≠ template order '$expected'"

# 2) Headings estruturais.
grep -q "^### Claude's Discretion" "$CTX" || grep -q "^### Claude’s Discretion" "$CTX" || fail "missing '### Claude's Discretion'"
grep -q "^## Deferred Ideas" "$CTX" || fail "missing '## Deferred Ideas'"

# 3) SPEC em <canonical_refs>.
if [ -n "$SPEC" ]; then
  sb=$(basename "$SPEC")
  sed -n '/^<canonical_refs>/,/^<\/canonical_refs>/p' "$CTX" | grep -q -- "$sb" || fail "SPEC $sb not listed in <canonical_refs>"
fi

# 4) Parser real.
if [ -f "$LIB/decisions.cjs" ]; then
  PJ=$(node -e '
const fs=require("fs");const d=require(process.argv[1]);
const r=d.extractDecisions(fs.readFileSync(process.argv[2],"utf8"));
console.log(JSON.stringify({outcome:r.outcome,total:r.decisions.length,trackable:r.decisions.filter(x=>x.trackable).length,
 tags:r.decisions.map(x=>({id:x.id,tags:x.tags||[]}))}));' "$LIB/decisions.cjs" "$CTX" 2>/dev/null) || PJ='{"outcome":"error"}'
  OUTCOME=$(printf '%s' "$PJ" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).outcome)}catch{console.log("error")}})')
  case "$OUTCOME" in
    parsed|none-present) ;;
    could-not-parse) fail "decisions.cjs: could-not-parse (a D-NN bullet is malformed)" ;;
    *) warn "decisions.cjs could not run ($PJ)" ;;
  esac
else
  warn "decisions.cjs not found under $LIB — parser check skipped"
fi

# 4.5) [R5c] Artefatos novos commitados do SPEC × D-NN que os cubra.
if [ -n "$SPEC" ] && [ -f "$SPEC" ]; then
  _EXTRATOR="$(dirname "$(readlink -f "$0")")/artefatos-novos.py"
  if [ -f "$_EXTRATOR" ]; then
    # texto dos bullets de decisão, sem crases — é aí que o caminho tem de aparecer
    _DECS=$(sed -n '/^<decisions>/,/^<\/decisions>/p' "$CTX" | grep -E '^\s*-\s+\*\*D-[0-9]+' | tr -d '`')
    while IFS= read -r _art; do
      [ -n "$_art" ] || continue
      case "$_DECS" in
        *"$_art"*) ;;
        *) fail "new committed artifact '$_art' (SPEC § Artefatos novos commitados) has no D-NN citing it in <decisions>" ;;
      esac
    done < <(python3 "$_EXTRATOR" "$SPEC")
  else
    warn "artefatos-novos.py not found next to this script — R5 artifact check skipped"
  fi
fi

# 5) Âncoras (tag rN / scN no bullet) ∈ REQS ∪ {none}.
#    A tag pode vir HIFENADA (`R-1`, `SC-9`) quando a decisão nasceu do PRE-SPEC da
#    /go-and-do; REQS é sempre canônico (discuss-init.sh só aceita `^R[0-9]+$`). Então o
#    hífen cai ANTES do `sort -u` — assim `R1` e `R-1` no mesmo bullet viram um token só e
#    não geram dois WARNs para a mesma âncora. `\b` protege `DESC-01`/`RESID-01`/`PS-01`.
if [ -n "$REQS" ]; then
  for a in $(sed -n '/^<decisions>/,/^<\/decisions>/p' "$CTX" | grep -oE '^\s*-\s+\*\*D-[0-9]+\s*\[[^]]*\]' | grep -oE '\b(R|SC)-?[0-9]+\b' | sed -E 's/^(R|SC)-/\1/' | sort -u); do
    case " $REQS " in *" $a "*) ;; *) warn "orphan anchor $a (not in REQ_IDS: $REQS)" ;; esac
  done
fi

# 6) Refs em disco.
while IFS= read -r p; do
  p=${p%% §*}
  case "$p" in http*|"") continue ;; esac
  [ -e "$ROOT/$p" ] || [ -e "$p" ] || warn "MISSING ref: $p"
done < <(sed -n '/^<canonical_refs>/,/^<\/canonical_refs>/p' "$CTX" | grep -oE '^- `[^`]+`' | sed 's/^- `//;s/`$//')

# 7) Discretion vazio / strings perigosas nos racionais.
disc=$(sed -n "/^### Claude.s Discretion/,/^###\|^<\/decisions>/p" "$CTX" | sed '1d;$d' | grep -cE '^\s*-\s+\S' || true)
[ "${disc:-0}" -gt 0 ] || warn "Claude's Discretion is empty"
sed -n '/^<decisions>/,/^<\/decisions>/p' "$CTX" | grep -qiE '<task\b|<plan\b|</plan>' && warn "plan/task tag text inside <decisions>"

# 8) Repetição literal do SPEC dentro de um bullet D-NN (advisory — ver cabeçalho).
if [ -n "$SPEC" ] && [ -f "$SPEC" ] && [ "${GUARD_SHINGLE:-0}" -gt 0 ] 2>/dev/null; then
  while IFS= read -r _l; do
    [ -n "$_l" ] && warn "$_l"
  done < <(python3 - "$CTX" "$SPEC" "$GUARD_SHINGLE" <<'PY8'
import re, sys, unicodedata
ctx, spec, n = open(sys.argv[1], encoding="utf-8").read(), open(sys.argv[2], encoding="utf-8").read(), int(sys.argv[3])
def norm(t):
    t = unicodedata.normalize("NFKD", t.lower())
    return re.findall(r"[a-z0-9]+", "".join(c for c in t if not unicodedata.combining(c)))
m = re.search(r"<decisions>\n(.*?)\n</decisions>", ctx, re.S)
if not m or n <= 0:
    sys.exit(0)
st = norm(spec)
grams = {tuple(st[i:i + n]) for i in range(len(st) - n + 1)}
bul, cur = [], None
for ln in m.group(1).splitlines():
    h = re.match(r"^\s*-\s+\*\*(D-[0-9A-Za-z_-]+)(?:\s*\[[^\]]*\])?[^:*]*:\*\*\s*(.*)$", ln)   # forma colon do decisions.cjs
    if h:
        cur = [h.group(1), [h.group(2)]]; bul.append(cur); continue
    if cur and ln.startswith("  "):
        cur[1].append(ln)
    elif ln.startswith("###") or not ln.strip():
        cur = None
for did, lines in bul:
    toks = norm("\n".join(lines)); best = run = 0
    for i in range(len(toks) - n + 1):
        if tuple(toks[i:i + n]) in grams:
            run = run + 1 if run else n; best = max(best, run)
        else:
            run = 0
    if best >= n:
        print(f"{did} repete {best} palavras do SPEC literalmente — use ponteiro (§C1)")
PY8
)
fi

for w in "${warns[@]:-}"; do [ -n "$w" ] && echo "[guard] WARN: $w"; done
if [ ${#fails[@]} -gt 0 ]; then
  for f in "${fails[@]}"; do echo "[guard] FAIL: $f"; done
  echo "[guard] CONTEXT rejected: ${#fails[@]} structural failure(s) — $CTX"
  exit 2
fi
echo "[guard] OK: $CTX (${#warns[@]} warning(s))"
exit 0
