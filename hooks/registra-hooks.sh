#!/usr/bin/env bash
# registra-hooks.sh — registra (idempotente) no ~/.claude/settings.json os hooks da go-and-do
# que não estavam no README até a v2.5.3:
#   SubagentStop               → gad-lifecycle.sh  (fim real do subagente; v2.5.4, tarefa 45g)
#   PreToolUse/AskUserQuestion → gad-gate-guard.sh (cerimônia antes de gate duro; v2.5.4, 45p)
# É o DONO quem roda isto, na sessão dele (`! bash hooks/registra-hooks.sh`): a skill nunca edita
# o settings por conta própria.
# Uso: registra-hooks.sh [--dry-run | --confere] [--settings <arquivo>]
#   --dry-run imprime o que faria e não grava. Sem ele: faz backup em <settings>.bak-<epoch> e
#   regrava. Exit 0 ok · 1 nada a fazer (já registrado) · 2 erro.
#   --confere (tarefa 8 do mapa-gad): SÓ LÊ — nunca grava nem faz backup. Confere se o arquivo
#   $HOME/.claude/hooks/gad-lifecycle.sh existe e se o gad-lifecycle está registrado em
#   PreToolUse e PostToolUse (matcher que inclua `Agent`) e em SubagentStop. Para rodar na
#   instalação ou atualização da skill: pega o hook faltando antes da primeira rodada.
#   ATENÇÃO — exit diferente do modo normal: no --confere, 0 = tudo certo · 1 = FALTA algo
#   (uma linha `falta: …` por item faltante) · 2 = erro de uso ou settings ausente/ilegível.
set -euo pipefail
DRY=0; CONF=0; SET="$HOME/.claude/settings.json"
USO="uso: registra-hooks.sh [--dry-run | --confere] [--settings <arquivo>]"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --confere) CONF=1; shift ;;
    --settings) [ $# -ge 2 ] || { echo "$USO" >&2; exit 2; }; SET="$2"; shift 2 ;;
    *) echo "$USO" >&2; exit 2 ;;
  esac
done
if [ "$DRY$CONF" = 11 ]; then echo "$USO (--dry-run e --confere são excludentes)" >&2; exit 2; fi
[ -f "$SET" ] || { echo "settings não encontrado: $SET" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 ausente" >&2; exit 2; }

if [ "$CONF" = 1 ]; then
  set +e
  python3 - "$SET" "$HOME/.claude/hooks/gad-lifecycle.sh" <<'CONFERE'
import json, os, sys
p, arq = sys.argv[1], sys.argv[2]
try:
    s = json.load(open(p, encoding="utf-8"))
except Exception as e:
    print(f"settings ilegível: {p}: {e}", file=sys.stderr); sys.exit(2)
hooks = s.get("hooks") or {}

def matcher_tem_agent(m):
    # matcher ausente, vazio ou "*" casa toda ferramenta — Agent inclusive
    if m in (None, "", "*"):
        return True
    return "Agent" in [t.strip() for t in str(m).split("|")]

def registrado(ev, exige_agent):
    for h in hooks.get(ev) or []:
        if exige_agent and not matcher_tem_agent(h.get("matcher")):
            continue
        for c in h.get("hooks") or []:
            if "gad-lifecycle.sh" in (c.get("command") or ""):
                return True
    return False

faltas = []
if not os.path.isfile(arq):
    faltas.append(f"falta: arquivo do hook {arq}")
for ev in ("PreToolUse", "PostToolUse"):
    if not registrado(ev, True):
        faltas.append(f"falta: gad-lifecycle.sh em {ev} com matcher que inclua Agent")
if not registrado("SubagentStop", False):
    faltas.append("falta: gad-lifecycle.sh em SubagentStop")
if faltas:
    print("\n".join(faltas)); sys.exit(1)
print("ok: gad-lifecycle presente e registrado em PreToolUse, PostToolUse e SubagentStop")
CONFERE
  exit $?
fi

python3 - "$SET" "$DRY" <<'PY'
import json, shutil, sys, time
p, dry = sys.argv[1], sys.argv[2] == "1"
s = json.load(open(p, encoding="utf-8"))
hooks = s.setdefault("hooks", {})
LIFE = 'bash "$HOME/.claude/hooks/gad-lifecycle.sh"'
GATE = 'bash "$HOME/Projetos-Vox-AI/go-and-do/hooks/gad-gate-guard.sh"'

def tem(ev, trecho, matcher=None):
    for h in hooks.get(ev, []):
        if matcher is not None and (h.get("matcher") or "") != matcher:
            continue
        for c in h.get("hooks", []):
            if trecho in c.get("command", ""):
                return True
    return False

acoes = []
if not tem("SubagentStop", "gad-lifecycle.sh"):
    hooks.setdefault("SubagentStop", []).append(
        {"hooks": [{"type": "command", "command": LIFE, "timeout": 5}]})
    acoes.append("SubagentStop → gad-lifecycle.sh")
if not tem("PreToolUse", "gad-gate-guard.sh", "AskUserQuestion"):
    hooks.setdefault("PreToolUse", []).append(
        {"matcher": "AskUserQuestion", "hooks": [{"type": "command", "command": GATE, "timeout": 10}]})
    acoes.append("PreToolUse[AskUserQuestion] → gad-gate-guard.sh")
if not acoes:
    print("nada a fazer: hooks já registrados"); sys.exit(1)
print(("(dry-run) " if dry else "") + "registrando: " + "; ".join(acoes))
if dry:
    sys.exit(0)
bak = f"{p}.bak-{int(time.time())}"
shutil.copy2(p, bak)
with open(p, "w", encoding="utf-8") as f:
    json.dump(s, f, indent=2, ensure_ascii=False); f.write("\n")
print(f"gravado; backup em {bak}")
PY
