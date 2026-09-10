#!/usr/bin/env bash
# suite-ressalva.sh — o DONO aceita uma suíte final vermelha (45n, v2.5.4). Grava no frontmatter
# do NN-VERIFICATION.md `suite_final: vermelha` e `suite_ressalva: "<motivo>"` e registra
# incidente; com isso o confere-etapa.sh 3 rebaixa SUITE-FINAL-VERMELHA a informativo.
# Só o dono manda rodar isto (decisão registrada no NN-DECISOES.md por quem executa).
# Uso: suite-ressalva.sh <phase_dir> <NN> "<motivo em 1 linha>"
# Exit: 0 gravado · 2 uso inválido / VERIFICATION ausente.
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"
PD="${1:-}"; NN="${2:-}"; MOT="${3:-}"
[ -n "$PD" ] && [ -n "$NN" ] && [ -n "$MOT" ] || { echo "uso: suite-ressalva.sh <phase_dir> <NN> \"<motivo>\"" >&2; exit 2; }
VER="$PD/$NN-VERIFICATION.md"
[ -f "$VER" ] || { echo "VERIFICATION ausente: $VER" >&2; exit 2; }
head -n1 "$VER" | grep -q '^---$' || { echo "VERIFICATION sem frontmatter: $VER" >&2; exit 2; }
MOT1=$(printf '%s' "$MOT" | tr '\n' ' ' | sed 's/"/\\"/g' | cut -c1-300)
python3 - "$VER" "$MOT1" <<'PY'
import re, sys
p, mot = sys.argv[1], sys.argv[2]
t = open(p, encoding="utf-8").read()
fm, resto = t.split("\n---", 1)          # fm começa com "---\n"
fm = re.sub(r"^suite_final:.*\n?", "", fm, flags=re.M)
fm = re.sub(r"^suite_ressalva:.*\n?", "", fm, flags=re.M)
fm = fm.rstrip("\n") + f'\nsuite_final: vermelha\nsuite_ressalva: "{mot}"'
open(p, "w", encoding="utf-8").write(fm + "\n---" + resto)
PY
ET=$(grep '"evento":"checkpoint"' "$PD/$NN-RUN-LOG.jsonl" 2>/dev/null | tail -n1 | sed -n 's/.*"etapa":"\([^"]*\)".*/\1/p') || true
gad_runlog "$PD" "$NN" incidente "${ET:-3 construcao}" --kv origem=suite-ressalva.sh \
  --kv detalhe="suíte final vermelha aceita pelo dono: $MOT1" >/dev/null 2>&1 || true
jq -cn --arg v "$VER" --arg m "$MOT1" '{gravado:true, verification:$v, suite_final:"vermelha", suite_ressalva:$m}'
