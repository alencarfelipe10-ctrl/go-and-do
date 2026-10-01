#!/usr/bin/env bash
# discuss-hooks-filter.sh — D1 da onda 2 (fork seletivo do gad-discuss-phase).
#
# Filtro MECÂNICO do envelope de `gad_run loop render-hooks discuss:post --raw`.
# NÃO despacha nada: o despacho é do modelo (Skill/Agent/…), como manda
# `references/loop-hook-dispatch.md`. Este script só classifica.
#
# O que faz:
#   1. Em `--auto` com `features.mempalace_capture_on_auto_discuss` != true,
#      remove SÓ a entrada cujo `ref.skill == "mempalace-capture"`
#      (literal conferido em bin/lib/capability-registry.cjs:2495).
#      Fora do --auto nada é removido.
#   2. Separa em `nao_despachaveis` o que o host `gad-discuss` não consegue
#      despachar (não tem a tool `Agent`): `step` com `ref.agent` e
#      `gate` com `check.agentVerdict`.
#   3. Separa em `rejeitados` o que é manifesto malformado:
#      `gate.check.agentVerdict` com `blocking: true`
#      (capability-validator.cjs:2802-2806 proíbe), `gate.check` sem
#      exatamente um de query/predicate/agentVerdict, e `ref.command`/
#      `check.query` que não casam com ^[a-z][a-z0-9-]*( [a-z][a-z0-9-]*)*$.
#      A validação é IN-CONTEXT (python), nunca por interpolação em shell.
#   4. `activeHooks` sai com TODOS os `kind` que sobraram, verbatim
#      (contribution, ref.skill, ref.command, gate query/predicate) —
#      nunca só as formas nomeadas.
#
# Fail closed: se um item rejeitado for `gate` com `blocking: true`, o exit é 3
# e o workflow PARA (não há como avaliar a guarda, então não se segue em frente).
#
# Uso:
#   discuss-hooks-filter.sh [--json <arquivo>] [--auto|--no-auto]
#                           [--capture-on <true|false>] [--point <ponto>]
#
#   --json        lê o envelope de um arquivo (ou `-` para stdin) em vez de
#                 chamar o render-hooks. É o seam dos testes: funciona sem
#                 nada instalado e sem GAD_TOOLS.
#   --auto        força o modo auto. Sem a flag, o modo vem de $ARGUMENTS
#                 (a mesma convenção do workflow: " --auto " na string).
#   --capture-on  força o valor da chave. Sem a flag, vem de
#                 `gad_run query config-get features.mempalace_capture_on_auto_discuss
#                  --default false --raw`; sem gad-tools, assume false.
#
# Saída: JSON compacto (uma linha) em stdout: as chaves escalares do envelope,
#   `activeHooks` filtrado + `nao_despachaveis` + `rejeitados` + `filtrados`, e
#   `envelope` = caminho do envelope INTEIRO gravado em $T/hooks-envelope.json
#   ($T do env.sh; sem ele, .planning/.discuss-tmp ou um mktemp). Nos arrays, cada
#   hook traz só id/kind/blocking/onError/into/ref e `check.query`/`check.predicate`/
#   `fragment.inline`/`rendered` cortados em 200 chars (`truncado: true` quando cortou).
#   Motivo (P18): o stdout dos scripts do fork tem teto de 20 KB — acima disso o
#   texto entra inteiro na conversa a cada turno; o dado completo fica no arquivo.
# Logs em stderr. Exit: 0 ok · 2 uso/JSON inválido · 3 rejeitado bloqueante.
set -u

JSON_FILE=""; MODO_AUTO=""; CAPTURE_ON=""; POINT="discuss:post"
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON_FILE="${2:-}"; shift 2 ;;
    --auto) MODO_AUTO=true; shift ;;
    --no-auto) MODO_AUTO=false; shift ;;
    --capture-on) CAPTURE_ON="${2:-}"; shift 2 ;;
    --point) POINT="${2:-}"; shift 2 ;;
    *) echo "[hooks-filter] flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

# modo auto: flag > $ARGUMENTS
if [ -z "$MODO_AUTO" ]; then
  case " ${ARGUMENTS:-} " in *" --auto "*) MODO_AUTO=true ;; *) MODO_AUTO=false ;; esac
fi

# gad_run só é resolvido quando realmente precisamos dele
_tem_gad() { [ -n "${GAD_TOOLS:-}" ] && [ -f "${GAD_TOOLS:-}" ]; }
gad_run() {
  _tem_gad || return 127
  case "$GAD_TOOLS" in *.cjs) node "$GAD_TOOLS" "$@" ;; *) "$GAD_TOOLS" "$@" ;; esac
}

# 1. envelope
if [ -n "$JSON_FILE" ]; then
  if [ "$JSON_FILE" = "-" ]; then ENVELOPE=$(cat)
  elif [ -f "$JSON_FILE" ]; then ENVELOPE=$(cat "$JSON_FILE")
  else echo "[hooks-filter] arquivo não encontrado: $JSON_FILE" >&2; exit 2; fi
elif [ -n "${DISCUSS_POST_HOOKS_JSON:-}" ]; then
  ENVELOPE="$DISCUSS_POST_HOOKS_JSON"
else
  ENVELOPE=$(gad_run loop render-hooks "$POINT" --raw 2>/dev/null) || ENVELOPE=""
  if [ -z "$ENVELOPE" ]; then
    echo "[hooks-filter] render-hooks $POINT não devolveu nada — falha fechada" >&2
    exit 2
  fi
fi

# 2. chave da config (só consultada quando o modo é auto e não veio por flag)
if [ -z "$CAPTURE_ON" ]; then
  if [ "$MODO_AUTO" = true ]; then
    CAPTURE_ON=$(gad_run query config-get features.mempalace_capture_on_auto_discuss --default false --raw 2>/dev/null) || CAPTURE_ON=""
    [ -n "$CAPTURE_ON" ] || CAPTURE_ON=false
  else
    CAPTURE_ON=false
  fi
fi

# onde o envelope inteiro fica: $T (env.sh) > .planning/.discuss-tmp > mktemp
ENV_DIR="${T:-}"
[ -n "$ENV_DIR" ] && [ -d "$ENV_DIR" ] || { [ -d .planning/.discuss-tmp ] && ENV_DIR=.planning/.discuss-tmp || ENV_DIR=""; }
if [ -n "$ENV_DIR" ]; then ENV_OUT="$ENV_DIR/hooks-envelope.json"
else ENV_OUT=$(mktemp "${TMPDIR:-/tmp}/hooks-envelope.XXXXXX.json"); fi

MODO_AUTO="$MODO_AUTO" CAPTURE_ON="$CAPTURE_ON" POINT="$POINT" ENV_OUT="$ENV_OUT" \
python3 - "$ENVELOPE" <<'PY'
import json, os, re, sys

auto = os.environ["MODO_AUTO"] == "true"
capture_on = os.environ["CAPTURE_ON"].strip().lower() == "true"
point = os.environ["POINT"]

try:
    env = json.loads(sys.argv[1])
except Exception as e:                                    # noqa: BLE001
    print("[hooks-filter] envelope não é JSON válido: %s" % e, file=sys.stderr)
    sys.exit(2)
if not isinstance(env, dict):
    print("[hooks-filter] envelope não é um objeto JSON", file=sys.stderr)
    sys.exit(2)

hooks = env.get("activeHooks")
if hooks is None:
    hooks = []
if not isinstance(hooks, list):
    print("[hooks-filter] activeHooks não é lista — falha fechada", file=sys.stderr)
    sys.exit(2)

# mesmo regex do loop-hook-dispatch.md (ref.command e check.query), aplicado
# aqui dentro, nunca por interpolação em shell.
SEGURO = re.compile(r"^[a-z][a-z0-9-]*( [a-z][a-z0-9-]*)*$")

ativos, nao_desp, rejeitados, filtrados = [], [], [], []
bloqueante_rejeitado = False

def marca(destino, i, h, motivo):
    destino.append({"indice": i, "motivo": motivo, "entrada": h})

for i, h in enumerate(hooks):
    if not isinstance(h, dict):
        marca(rejeitados, i, h, "entrada não é objeto")
        continue
    kind = h.get("kind")
    ref = h.get("ref") if isinstance(h.get("ref"), dict) else {}

    # --- D1: só o mempalace-capture, só em --auto, só com a chave != true
    if ref.get("skill") == "mempalace-capture":
        if auto and not capture_on:
            filtrados.append({"indice": i, "motivo": "capture_on_auto_discuss=false",
                              "entrada": h})
            continue

    if kind == "gate":
        check = h.get("check")
        blocking = h.get("blocking") is True
        if not isinstance(check, dict):
            marca(rejeitados, i, h, "gate.check não é objeto")
            bloqueante_rejeitado |= blocking
            continue
        presentes = [k for k in ("query", "predicate", "agentVerdict") if k in check]
        if len(presentes) != 1:
            marca(rejeitados, i, h,
                  "gate.check precisa de exatamente um de query/predicate/agentVerdict")
            bloqueante_rejeitado |= blocking
            continue
        tipo = presentes[0]
        if tipo == "agentVerdict":
            if blocking:
                # capability-validator.cjs:2802-2806 — agentVerdict força blocking:false
                marca(rejeitados, i, h,
                      "gate.check.agentVerdict com blocking:true (validator rejeita)")
                # NÃO conta como bloqueante fechado: agentVerdict é sempre
                # não-bloqueante por contrato; o manifesto é que está errado.
                continue
            marca(nao_desp, i, h, "agentVerdict: host gad-discuss não tem a tool Agent")
            continue
        if tipo == "query":
            q = check.get("query")
            if not isinstance(q, str) or not SEGURO.match(q):
                marca(rejeitados, i, h, "gate.check.query malformado")
                bloqueante_rejeitado |= blocking
                continue
        else:  # predicate — passa como argv único; só exigimos que seja string
            if not isinstance(check.get("predicate"), str):
                marca(rejeitados, i, h, "gate.check.predicate não é string")
                bloqueante_rejeitado |= blocking
                continue
        ativos.append(h)
        continue

    if kind == "step" or ref:
        alvos = [k for k in ("skill", "agent", "command") if k in ref]
        if len(alvos) != 1:
            marca(rejeitados, i, h, "step precisa de exatamente um de ref.skill/agent/command")
            continue
        if alvos[0] == "agent":
            marca(nao_desp, i, h, "ref.agent: host gad-discuss não tem a tool Agent")
            continue
        if alvos[0] == "command":
            c = ref.get("command")
            if not isinstance(c, str) or not SEGURO.match(c):
                marca(rejeitados, i, h, "ref.command malformado")
                continue
        ativos.append(h)
        continue

    # contribution e qualquer kind futuro: preservados verbatim
    ativos.append(h)

# envelope inteiro + classificação completa vão para o arquivo; o stdout é o resumo
completo = dict(env)
completo["activeHooks"] = ativos
completo["nao_despachaveis"] = nao_desp
completo["rejeitados"] = rejeitados
completo["filtrados"] = filtrados
env_out = os.environ["ENV_OUT"]
with open(env_out + ".tmp", "w", encoding="utf-8") as f:
    json.dump(completo, f, ensure_ascii=False, indent=2)
os.replace(env_out + ".tmp", env_out)

LIM = 200
def corta(s):
    s = s if isinstance(s, str) else json.dumps(s, ensure_ascii=False)
    return (s[:LIM], True) if len(s) > LIM else (s, False)

def compacta(h):
    """id/kind/blocking/onError/into/ref inteiros; check.query|predicate|agentVerdict e
    fragment.inline cortados em 200 chars. `ref` fica inteiro porque é a chave do despacho."""
    if not isinstance(h, dict):
        s, t = corta(h)
        return {"entrada": s, **({"truncado": True} if t else {})}
    c = {k: h[k] for k in ("id", "kind", "blocking", "onError", "into", "ref") if k in h}
    trunc = False
    ck = h.get("check")
    if isinstance(ck, dict):
        c["check"] = {}
        for k in ("query", "predicate", "agentVerdict"):
            if k in ck:
                c["check"][k], t = corta(ck[k]); trunc |= t
    fr = h.get("fragment")
    if isinstance(fr, dict) and "inline" in fr:
        s, t = corta(fr["inline"]); trunc |= t
        c["fragment"] = {"inline": s}
    extras = sorted(set(h) - set(c) - {"check", "fragment"})
    if extras:
        c["outras_chaves"] = extras
    if trunc:
        c["truncado"] = True
    return c

def compacta_marca(m):
    return {"indice": m["indice"], "motivo": m["motivo"], "entrada": compacta(m["entrada"])}

saida = {}
for k, v in env.items():
    if k == "activeHooks":
        continue
    if isinstance(v, (str, int, float, bool)) or v is None:
        s, t = corta(v) if isinstance(v, str) else (v, False)
        saida[k] = s
        if t:
            saida[k + "_truncado"] = True
    else:
        saida[k] = "<no arquivo>"
saida["activeHooks"] = [compacta(h) for h in ativos]
saida["nao_despachaveis"] = [compacta_marca(m) for m in nao_desp]
saida["rejeitados"] = [compacta_marca(m) for m in rejeitados]
saida["filtrados"] = [compacta_marca(m) for m in filtrados]
saida["envelope"] = env_out
saida["envelope_bytes"] = os.path.getsize(env_out)
texto = json.dumps(saida, ensure_ascii=False, separators=(",", ":"))
if len(texto.encode()) > 16384:
    # envelope com centenas de hooks: só o essencial em stdout, o resto está no arquivo
    saida["activeHooks"] = [{k: h[k] for k in ("id", "kind", "blocking", "ref") if k in h} for h in saida["activeHooks"]]
    for k in ("nao_despachaveis", "rejeitados", "filtrados"):
        saida[k] = [{"indice": m["indice"], "motivo": m["motivo"]} for m in saida[k]]
    saida["reduzido"] = True
    texto = json.dumps(saida, ensure_ascii=False, separators=(",", ":"))
print(texto)

if filtrados:
    print("[auto] %s: mempalace-capture filtrado (capture_on_auto_discuss=false)" % point,
          file=sys.stderr)
for r in rejeitados:
    print("[hooks-filter] rejeitado #%s: %s" % (r["indice"], r["motivo"]), file=sys.stderr)
for n in nao_desp:
    print("[hooks-filter] nao_despachavel #%s: %s" % (n["indice"], n["motivo"]), file=sys.stderr)

sys.exit(3 if bloqueante_rejeitado else 0)
PY
