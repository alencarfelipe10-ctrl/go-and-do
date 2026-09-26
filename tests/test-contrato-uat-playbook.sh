#!/usr/bin/env bash
# test-contrato-uat-playbook.sh — literais que o uat-playbook.md tem de carregar porque o
# scripts/uat-fiscal.py (commit 1f8bd90) só reconhece estas duas grafias como escotilha/exceção
# declarável. Sem elas no playbook, o condutor do UAT não tem como fechar um cenário limpo e o
# gate novo (uat_pass_sem_sondagem / uat_pass_sem_evidencia) reprova sem saída declarável.
#
#   FJ-02UAT — escotilha «🔍 não se aplica: <motivo>» (sondagem)
#   FM-01UAT — exceção «ação sem saída» (evidência)
#   FM-F27INS-01EXE — «o UAT usa uma cópia da planilha» (26/09/2026): a fase 27 perdeu 32min24s
#     de suíte vermelha porque o UAT da F26 salvou por cima da planilha real (fora do git,
#     LGPD) em vez de usar uma cópia. A frase manda o condutor do UAT nunca escrever no
#     original.
#   bash tests/test-contrato-uat-playbook.sh      · exit 0 = verde
set -u
RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
P="$RAIZ/skills/go-and-do/uat-playbook.md"
OK=0; FALHAS=0
tem()  { if grep -qF -e "$2" "$P"; then OK=$((OK+1)); printf '  ✔ %s\n' "$1"; else FALHAS=$((FALHAS+1)); printf '  ✘ %s (literal ausente: %s)\n' "$1" "$2"; fi; }

[ -f "$P" ] || { echo "uat-playbook.md ausente"; exit 2; }

tem "FJ-02UAT: escotilha de sondagem não se aplica"   '🔍 não se aplica: <motivo>'
tem "FM-01UAT: exceção de evidência ação sem saída"   'ação sem saída'
tem "FM-F27INS-01EXE: UAT usa cópia da planilha"      'o UAT usa uma cópia da planilha'

echo
echo "── resumo: $OK ok / $FALHAS falhas ──"
[ "$FALHAS" -eq 0 ]
