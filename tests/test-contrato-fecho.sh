#!/usr/bin/env bash
# test-contrato-fecho.sh — tarefa 59, lane L10 (26/09/2026). Teste de CONTRATO do fecho dos
# hospedeiros e da ordem da etapa 5 — confere o texto, não o comportamento em runtime.
#
#   d1 (FM-F27INS-02PLAN, cobre FM-F27INS-04GAT) — todo hospedeiro commita a evidência
#       (`commita-artefatos.sh … evidencia`) DEPOIS de conferir os incidentes; quem roda o
#       próprio fiscal (execute, intent) commita ANTES dele (o recibo vale para o HEAD);
#       o close commita ANTES do ship (depois do merge não há branch).
#   c3 (FM-F27INS-06INT, cobre 05PLAN/07EXE/04UAT) — incidente gravado antes do `end`;
#       a camada 0 grava o retorno ANTES da cerca (§3.3 e §5.4).
#   resto do d2 (FM-F27INS-01UAT) — §5.4 passo 3 e §5.5 passo 6: commit do resultado ANTES
#       da cerca 5 (e de novo no pass, pelo carimbo que a cerca grava).
#   bash tests/test-contrato-fecho.sh      · exit 0 = verde
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SK="$AQUI/../skills/go-and-do"
P="$SK/prompts"
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; falhas=$((falhas+1)); }
tem()  { grep -qF -- "$2" "$1" && ok "$3" || erro "$3"; }
nao()  { grep -qF -- "$2" "$1" && erro "$3 (literal ainda presente: $2)" || ok "$3"; }
# antes <arquivo> <literal A> <literal B> <rótulo> — 1ª ocorrência de A vem antes da 1ª de B
antes() {
  local a b
  a=$(grep -nF -- "$2" "$1" | head -1 | cut -d: -f1); b=$(grep -nF -- "$3" "$1" | head -1 | cut -d: -f1)
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then ok "$4"; else erro "$4 (A=${a:-?} B=${b:-?})"; fi
}
EVID='commita-artefatos.sh "<phase_dir>" "<NN>" evidencia'

echo "== d1 + c3: fecho de cada hospedeiro"
for f in plan convergence execute code-review secure validate close intent; do
  tem "$P/$f.md" "$EVID" "$f.md: commita a evidência (modo evidencia)"
  tem "$P/$f.md" 'FM-F27INS-06INT' "$f.md: fecho cita o incidente na hora (FM-F27INS-06INT)"
done
# último passo = logo antes do «Devolva»; incidentes vêm antes do commit
for f in plan convergence code-review secure validate; do
  antes "$P/$f.md" 'Fecho: incidentes primeiro' "$EVID" "$f.md: incidentes antes do commit"
  antes "$P/$f.md" "$EVID" 'Devolva pelo `<return_contract>`' "$f.md: commit da evidência antes do «Devolva»"
done
# quem roda o próprio fiscal commita antes dele
antes "$P/execute.md" "$EVID" 'confere-etapa.sh" 3 \' "execute.md: commit da evidência antes do fiscal do passo 4"
antes "$P/execute.md" 'Fecho: incidentes primeiro' "$EVID" "execute.md: incidentes antes do commit"
tem   "$P/execute.md" 'intent/red-<NN>-<PP>-t<índice da task>.json' "execute.md: fecho usa o caminho RED da L4 (f3)"
antes "$P/intent.md" 'limpa-intencao.sh "<phase_dir>"' "$EVID" "intent.md: commit depois da limpeza do 7b"
antes "$P/intent.md" "$EVID" 'confere-etapa.sh 1 --fase <N>' "intent.md: commit antes do fiscal do passo 8"
tem   "$P/intent.md" 'Siga ao passo 7c.' "intent.md: o 7b segue para o 7c"
nao   "$P/intent.md" '(nesta versão, AVISO)' "intent.md: não descreve mais o tardio como AVISO"
# close: antes do ship
antes "$P/close.md" "$EVID" 'Invoque `Skill` → `close-phase`' "close.md: evidência commitada antes de invocar o close-phase"

echo "== c3: a camada 0 grava o retorno antes da cerca"
W3="$SK/workflow-etapa-3.md"
tem "$W3" 'before** your `confere-etapa.sh 3`' "§3.3: itens do retorno gravados antes da cerca 3"
W5="$SK/workflow-etapa-5.md"
antes "$W5" '**Incidents first.**' '**Commit the result**' "§5.4 passo 3: incidentes antes do commit"
antes "$W5" '**Commit the result**' '**Fence:** `confere-etapa.sh 5`' "§5.4 passo 3: commit antes da cerca 5"
antes "$W5" '**Fence:** `confere-etapa.sh 5`' '**Fence passed → commit again**' "§5.4 passo 3: commit de novo no pass"
nao   "$W5" 'Exit 1 → back to the SAME subagent. Do not ingest `NN-UAT.md`. **Fence passed →' "§5.4: a ordem antiga (cerca → commit) saiu"
grep -qF '5.6 re-run (`--reuat`) included' "$W5" && ok "§5.4: a ordem vale também para o --reuat da 5.6" \
  || erro "§5.4: a ordem vale também para o --reuat da 5.6"
antes "$W5" 'commit its result' '--fix-cycle`, which validates' "§5.5 passo 6: commit antes da cerca --fix-cycle"

echo "== cerca: isenção da etapa 5 removida, tardio duro"
CE="$SK/scripts/confere-etapa.sh"
nao "$CE" 'if [ "${ETAPA%% *}" != 5 ]; then' "confere-etapa.sh: a isenção da etapa 5 saiu"
tem "$CE" 'id:"incidente_tardio", resultado:"FALHA"' "confere-etapa.sh: incidente_tardio tem resultado FALHA"

echo
[ "$falhas" -eq 0 ] && { echo "test-contrato-fecho: TUDO OK"; exit 0; } || { echo "test-contrato-fecho: $falhas falha(s)"; exit 1; }
