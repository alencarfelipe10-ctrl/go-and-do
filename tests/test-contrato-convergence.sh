#!/usr/bin/env bash
# test-contrato-convergence.sh — tarefa 55 (EST-02, 23/09/2026): a etapa 2.5 (convergência do
# plano) deixa de rodar num `general-purpose` herdando o modelo da sessão e passa a ser
# despachada pela def própria `gad-plan` (mesma def da etapa 2, com cache de 1 h) — decisão já
# tomada, não reaberta aqui. Este é um teste de CONTRATO: confere que o texto do workflow e da
# def do agente refletem a troca, não o comportamento em runtime.
#
#   55b — pipeline_index e o bloco da etapa 2.5 citam o agente `gad-plan`, não mais "subagent"
#         genérico
#   55b — Sub-rotina H (lista de defs que nunca despacham como general-purpose) inclui a 2.5
#   55b — agents/gad-plan.md descreve também a etapa 2.5
#   bash tests/test-contrato-convergence.sh      · exit 0 = verde
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
W="$AQUI/../skills/go-and-do/workflow.md"
A="$AQUI/../agents/gad-plan.md"
C="$AQUI/../skills/go-and-do/prompts/convergence.md"
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; falhas=$((falhas+1)); }
tem()  { grep -qF -- "$2" "$1" && ok "$3" || erro "$3"; }
nao()  { grep -qF -- "$2" "$1" && erro "$3 (literal ainda presente: $2)" || ok "$3"; }

echo "== workflow.md"
tem "$W" '| 2.5 | plan convergence | 🔒 ⏭️ agent `gad-plan` + `prompts/convergence.md` (PC-6 fail-closed) |' \
  "pipeline_index: etapa 2.5 cita o agente gad-plan"
tem "$W" 'Dispatch the agent `gad-plan`' \
  "bloco da etapa 2.5: despacha o agente gad-plan (mesma prosa de dispatch da etapa 2)"
tem "$W" '`gad-plan` for 2 and 2.5' \
  "Sub-rotina H: a lista de defs próprias inclui a 2.5 sob gad-plan"
nao "$W" 'Dispatch via Sub-rotina H with `prompts/convergence.md`: the subagent hosts' \
  "a frase antiga de despacho genérico (\"the subagent hosts\") saiu"

echo "== agents/gad-plan.md"
tem "$A" '2.5' "descrição do gad-plan cita a etapa 2.5"
tem "$A" 'prompts/convergence.md' "descrição do gad-plan cita prompts/convergence.md"
grep -q '^model: claude-opus-5-5$' "$A" && ok "modelo pinado intacto (claude-opus-5-5)" || erro "modelo do gad-plan mudou"
grep -q '^effort: medium$' "$A" && ok "effort intacto (medium)" || erro "effort do gad-plan mudou"
grep -q '^  cacheTtl: 1h$' "$A" && ok "cacheTtl intacto (1h)" || erro "cacheTtl do gad-plan mudou"
grep -q '^tools: Read, Write, Edit, Bash, Grep, Glob, Skill, Agent$' "$A" && ok "tools intactas" || erro "tools do gad-plan mudaram"

echo "== prompts/convergence.md"
tem "$C" 'agente gad-plan' "cabeçalho do prompt nota o hospedeiro (agente gad-plan)"

echo
[ "$falhas" -eq 0 ] && echo "test-contrato-convergence: TUDO OK" || echo "test-contrato-convergence: $falhas falha(s)"
[ "$falhas" -eq 0 ]
