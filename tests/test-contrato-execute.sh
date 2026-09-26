#!/usr/bin/env bash
# test-contrato-execute.sh — literais que o prompt da Etapa 3 (prompts/execute.md) tem de
# carregar. Régua de contrato, não de comportamento: o que se confere aqui é que uma reescrita
# futura não apague por acidente uma regra que custou uma fase real.
#
#   46r  — `done` só com o recibo do fiscal (`--sem-telemetria` + `.fence-3.ok`)
#   46t  — declarar `ARQUIVO-NAO-DECLARADO`, nunca reescrever o `files_modified` pós-execução
#   45n  — negativa de guarda não se contorna (`subprocess.run`)
#   45o  — instrumento sob julgamento é evidência, não alvo
#   47b  — o contrato de leitura (<required_reading>/<execution_context>) desce verbatim
#   47d  — o host não conserta código: conserto pós-merge vai a executor
#   47e  — a espera de filho `Agent` não é por waiter (a frase «não recebe notificações» caiu)
#   F4RLR FJ-01EXE — mesma frase de handoff pro gsd-verifier em execute.md e workflow-etapa-3.md §3.4
#   F4RLR FM-08EXE — escopo do commit por extenso no briefing (FM-08EXE)
#   bash tests/test-contrato-execute.sh      · exit 0 = verde
set -u
RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
P="$RAIZ/skills/go-and-do/prompts/execute.md"
OK=0; FALHAS=0
tem()  { if grep -qF -e "$2" "$P"; then OK=$((OK+1)); printf '  ✔ %s\n' "$1"; else FALHAS=$((FALHAS+1)); printf '  ✘ %s (literal ausente: %s)\n' "$1" "$2"; fi; }
nao()  { if grep -qF -e "$2" "$P"; then FALHAS=$((FALHAS+1)); printf '  ✘ %s (literal ainda presente: %s)\n' "$1" "$2"; else OK=$((OK+1)); printf '  ✔ %s\n' "$1"; fi; }

[ -f "$P" ] || { echo "prompts/execute.md ausente"; exit 2; }

tem "46r: a flag --sem-telemetria está no passo de fecho"        '--sem-telemetria'
tem "46r: o marcador fences/3.ok é o recibo (v2.10.1: .gad/fences/)" 'fences/3.ok'
tem "46r: o retorno de reprovação tem frase literal"             'reprovado pelo fiscal'
tem "46t: a resposta ao desvio é declarar"                       'ARQUIVO-NAO-DECLARADO: <caminho>'
tem "45n: contorno por subprocess é proibido"                    'subprocess.run'
tem "45n: conferência por contagem no passo 0"                   'COPIA-INCOMPLETA'
tem "45o: instrumento sob julgamento é evidência"                'Instrumento sob julgamento'
tem "46u: incidente se grava na hora"                            'Incidente se grava na hora'
tem "46u: hora de artefato vem do date -Is"                      'date -Is'
tem "47b: o contrato de leitura desce verbatim"          'vão **literais** no briefing'
tem "11e: marcador [gsd:dispatch] desce verbatim (GSD 1.14.0)" '[gsd:dispatch phase="{phase_number}" plan="{plan_id}"]'
tem "11e: plan_id copiado do phase-plan-index"           'copiado do `phase-plan-index`, nunca'
tem "11e: precedência da regra de stall sobre #4218"     'a regra desta skill prevalece'
tem "47b: a frase falsa do template é proibida"         'já vêm na sua'
tem "47d: o host não conserta código"                   'Você relança a suíte; você não conserta o código'
tem "47e: filho Agent acorda o pai"                              'encerre o turno'
nao "47e: a frase falsa de que não chegam notificações saiu"     'você **não recebe notificações**'
tem "FJ-01EXE: a mesma frase de handoff ao gsd-verifier"         'números medidos da suíte completa e o escopo de módulos tocados'
tem "FM-08EXE: escopo do commit por extenso no briefing"         'escopo dos seus commits: (NN-PP)'
tem "FM-F27INS-02EXE: commit do hospedeiro no escopo de um plano também exige a linha" 'A mesma regra vale quando é VOCÊ, o hospedeiro, quem commita'
tem "FM-F27INS-02EXE: motivo é obrigatório, negrito/crases são só enfeite aceito" 'negrito e crases no rótulo são aceitos pelo fiscal, mas o'
# o outro lado do FJ-01EXE: a camada 0 manda a MESMA frase no despacho do 3.4 (arquivo de etapa
# desde a divisão do workflow, tarefa 9 do mapa-gad)
W3="$RAIZ/skills/go-and-do/workflow-etapa-3.md"
if grep -qF -e 'suíte completa e o escopo de módulos tocados' "$W3"; then
  OK=$((OK+1)); printf '  ✔ %s\n' "FJ-01EXE: workflow-etapa-3.md §3.4 carrega a mesma frase"
else FALHAS=$((FALHAS+1)); printf '  ✘ %s\n' "FJ-01EXE: frase do handoff ausente em workflow-etapa-3.md"; fi

echo
echo "── resumo: $OK ok / $FALHAS falhas ──"
[ "$FALHAS" -eq 0 ]
