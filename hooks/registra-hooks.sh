#!/usr/bin/env bash
# registra-hooks.sh — registra (idempotente) no ~/.claude/settings.json os hooks da go-and-do
# que não estavam no README até a v2.5.3:
#   SubagentStop               → gad-lifecycle.sh  (fim real do subagente; v2.5.4, tarefa 45g)
#   PreToolUse/AskUserQuestion → gad-gate-guard.sh (cerimônia antes de gate duro; v2.5.4, 45p)
# É o DONO quem roda isto, na sessão dele (`! bash hooks/registra-hooks.sh`): a skill nunca edita
# o settings por conta própria.
# Uso: registra-hooks.sh [--dry-run] [--settings <arquivo>]
#   --dry-run imprime o que faria e não grava. Sem ele: faz backup em <settings>.bak-<epoch> e
#   regrava. Exit 0 ok · 1 nada a fazer (já registrado) · 2 erro.
set -euo pipefail
DRY=0; SET="$HOME/.claude/settings.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --settings) SET="${2:-}"; shift 2 ;;
    *) echo "uso: registra-hooks.sh [--dry-run] [--settings <arquivo>]" >&2; exit 2 ;;
  esac
done
[ -f "$SET" ] || { echo "settings não encontrado: $SET" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 ausente" >&2; exit 2; }
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
