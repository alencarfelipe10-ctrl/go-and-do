#!/usr/bin/env bash
# discuss-render-guard.sh — guarda de render do documento único de intenção (fork, plano 06-13).
#
# Um ponto de invocação só, no passo `write_context`, ANTES de o rascunho ir ao dono:
#   1. render: `context-render.py $CKPT --out $RASCUNHO` (função pura do depósito);
#   2. conferência: `confere-documento.py $RASCUNHO` (com `--reqs <root>/.planning/REQUIREMENTS.md`
#      quando existe) — forma, conteúdo e coerência do documento (06-04);
#   3. PII: `confere-pii.sh $RASCUNHO` (com `--nomes $PII_NOMES` quando o ambiente ou o env.sh
#      trazem a lista dos nomes vistos nos insumos) — pessoas só por número ou papel.
# A guarda NUNCA promove: o NN-CONTEXT.md da fase só nasce por `context-render.py --promover`,
# depois do «ok» do dono gravado com `checkpoint-write.py aprovar`. Não roda a guarda antiga
# nem o gate de cobertura (o gate é do plan-phase). Pode rodar quantas vezes for preciso.
#
# Uso: discuss-render-guard.sh [--tmp DIR] [--root DIR]
#   --tmp   diretório temporário do discuss (default .planning/.discuss-tmp), de onde vem o
#           env.sh com CKPT/NOSSO/RASCUNHO (RASCUNHO ausente → $T/rascunho/<NN>-CONTEXT.md).
#   --root  raiz do projeto, onde mora .planning/REQUIREMENTS.md (default ".").
#
# Saída: UMA linha JSON em stdout
#   {"rascunho", "sha256", "falhas": [...], "pii": "limpo|achados", "ok": bool,
#    "falhas_omitidas": N, "log": "<caminho>"}
#   `falhas` traz, no máximo 50, linhas `CODIGO linha N: mensagem` do conferidor, `PII-… linha N:
#   trecho` do PII, `SECAO-VAZIA <slug>` (seção sem texto no depósito) e `RENDER …`; o resto é
#   contado em `falhas_omitidas` e tudo fica no log ($T/render-guard.log). Teto de 20 KB (P18).
# Exit: 0 só com ok: true · 1 reprovado (conferidor, PII, seção vazia ou render quebrado — falha
# fechada) · 2 uso ou env.sh ausente.
set -u

T_DIR=".planning/.discuss-tmp"; ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --tmp) T_DIR="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    *) echo "[render-guard] flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

[ -f "$T_DIR/env.sh" ] || { echo "[render-guard] $T_DIR/env.sh ausente — rode o initialize (discuss-init.sh)" >&2; exit 2; }
_PII_NOMES_AMBIENTE="${PII_NOMES:-}"
# shellcheck disable=SC1090
. "$T_DIR/env.sh"
T="${T:-$T_DIR}"
: "${CKPT:?CKPT ausente no env.sh}"; : "${NOSSO:?NOSSO ausente no env.sh}"
RASCUNHO="${RASCUNHO:-$T/rascunho/${padded_phase:-$PHASE}-CONTEXT.md}"
PII_NOMES="${PII_NOMES:-$_PII_NOMES_AMBIENTE}"
mkdir -p "$(dirname "$RASCUNHO")"

LOG="$T/render-guard.log"; : > "$LOG"
RJSON="$T/render-guard.render.json"; CJSON="$T/render-guard.confere.json"; PTXT="$T/render-guard.pii.txt"
: > "$RJSON"; : > "$CJSON"; : > "$PTXT"

# 1. render
python3 "$NOSSO/context-render.py" "$CKPT" --out "$RASCUNHO" > "$RJSON" 2>>"$LOG"; RENDER=$?
CONFERE=2; PII=2
if [ "$RENDER" -eq 0 ]; then
  # 2. conferidor (JSON completo em arquivo; o resumo vai ao log)
  C_ARGS=(); [ -f "$ROOT/.planning/REQUIREMENTS.md" ] && C_ARGS+=(--reqs "$ROOT/.planning/REQUIREMENTS.md")
  python3 "$NOSSO/confere-documento.py" "$RASCUNHO" ${C_ARGS[@]+"${C_ARGS[@]}"} --json > "$CJSON" 2>>"$LOG"; CONFERE=$?
  # 3. PII
  P_ARGS=(); [ -n "$PII_NOMES" ] && P_ARGS+=(--nomes "$PII_NOMES")
  bash "$NOSSO/confere-pii.sh" "$RASCUNHO" ${P_ARGS[@]+"${P_ARGS[@]}"} > "$PTXT" 2>>"$LOG"; PII=$?
  cat "$PTXT" >> "$LOG"
else
  echo "[render-guard] context-render.py falhou (exit $RENDER) — falha fechada" >> "$LOG"
fi

RENDER="$RENDER" CONFERE="$CONFERE" PII="$PII" RASCUNHO="$RASCUNHO" \
python3 - "$RJSON" "$CJSON" "$PTXT" "$LOG" <<'PY'
import json, os, re, sys
rjson, cjson, ptxt, log = sys.argv[1:5]
render, confere, pii = (int(os.environ[k]) for k in ("RENDER", "CONFERE", "PII"))
falhas, sha = [], ""
if render != 0:
    falhas.append(f"RENDER context-render.py saiu {render} (ver {log})")
else:
    r = json.load(open(rjson, encoding="utf-8"))
    sha = r.get("sha256", "")
    falhas += [f"SECAO-VAZIA {s}" for s in r.get("vazias") or []]
    try:
        c = json.load(open(cjson, encoding="utf-8"))
        falhas += [f"{f['codigo']} linha {f['linha']}: {f['mensagem']}" for f in c.get("falhas") or []]
    except (OSError, ValueError):
        c = None
    if confere not in (0, 1) or (confere == 1 and c is None):
        falhas.append(f"CONFERE confere-documento.py saiu {confere} (ver {log})")
    for l in open(ptxt, encoding="utf-8", errors="replace"):
        m = re.match(r"^(PII-[A-Z-]+)\s+\S+?:(\d+)\s+(.*)$", l.rstrip("\n"))
        if m:
            falhas.append(f"{m.group(1)} linha {m.group(2)}: {m.group(3)}")
    if pii not in (0, 1):
        falhas.append(f"PII confere-pii.sh saiu {pii} (ver {log})")
mostradas = [f[:200] for f in falhas[:50]]
ok = render == 0 and confere == 0 and pii == 0 and not falhas
print(json.dumps({"rascunho": os.environ["RASCUNHO"], "sha256": sha, "falhas": mostradas,
                  "pii": "limpo" if (render == 0 and pii == 0) else "achados", "ok": ok,
                  "falhas_omitidas": len(falhas) - len(mostradas), "log": log}, ensure_ascii=False))
sys.exit(0 if ok else 1)
PY
