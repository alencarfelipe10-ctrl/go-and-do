#!/usr/bin/env bash
# test-confere-pre-spec.sh — suíte do confere-pre-spec.sh (R2 · R7 · S4 · §0.5).
# Cobre cada código do contrato + os casos nomeados no PLANO-execucao.md.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
S="$AQUI/../skills/go-and-do/scripts/confere-pre-spec.sh"
F="$AQUI/fixtures/pre-spec"
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

# roda <descrição> <exit esperado> <regex esperada|-> -- <args...>
roda() {
  local desc="$1" exp="$2" pad="$3"; shift 3; [ "$1" = "--" ] && shift
  local saida rc
  saida=$(bash "$S" "$@" 2>&1); rc=$?
  if [ "$rc" != "$exp" ]; then
    erro "$desc (exit)" "esperado exit=$exp, obtido exit=$rc
$saida"; return
  fi
  if [ "$pad" != "-" ] && ! echo "$saida" | grep -qE "$pad"; then
    erro "$desc (saída)" "esperava casar /$pad/
$saida"; return
  fi
  ok "$desc"
}
# nao_casa <descrição> <regex> -- <args...>
nao_casa() {
  local desc="$1" pad="$2"; shift 2; [ "$1" = "--" ] && shift
  local saida
  saida=$(bash "$S" "$@" 2>&1)
  if echo "$saida" | grep -qE "$pad"; then
    erro "$desc" "não deveria casar /$pad/
$saida"
  else
    ok "$desc"
  fi
}

echo "-- bloco (§0.5)"
roda "bloco válido com Unicode, ':', '#' e aspas → ok" 0 'pre_spec_bloco: ok' -- --so-bloco "$F/ok-PRE-SPEC.md"
roda "bloco ausente → exit 1 e estado 'ausente'" 1 'pre_spec_bloco: ausente' -- --so-bloco "$F/sem-bloco-PRE-SPEC.md"
roda "id duplicado no bloco → exit 2" 2 'BLOCO-INVALIDO.*ID-DUPLICADO PS-01' -- --so-bloco "$F/id-duplicado-PRE-SPEC.md"
roda "chave JSON duplicada (object_pairs_hook) → exit 2" 2 'chave duplicada no JSON do bloco' -- --so-bloco "$F/chave-duplicada-PRE-SPEC.md"
roda "JSON inválido → exit 2" 2 'JSON inválido' -- --so-bloco "$F/json-invalido-PRE-SPEC.md"
roda "fato_medido sem evidência reproduzível → falha (exit 2 no --so-bloco)" 2 'FATO-SEM-EVIDENCIA' -- --so-bloco "$F/fato-sem-evidencia-PRE-SPEC.md"

echo "-- SPEC × PRE-SPEC"
roda "SPEC conforme → exit 0 (aviso não reprova)" 0 'falhas=0' -- "$F/ok-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "Goal marcado com números de outras seções → só EXTENSAO-SUSPEITA, exit 0" 0 \
     'EXTENSAO-SUSPEITA .*ok-SPEC.md:5' -- "$F/ok-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "\`[pre-spec]\` sem id → MARCA-SEM-ID" 1 'MARCA-SEM-ID .*:5' -- "$F/ruim-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "marca citando PS inexistente → ID-INEXISTENTE" 1 'ID-INEXISTENTE .*PS-99' -- "$F/ruim-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "AC e MUST NOT só com ponteiro → 2× AC-POR-PONTEIRO (S4)" 1 'AC-POR-PONTEIRO=2' -- "$F/ruim-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "'campo aditivo opcional default None' sem None/default no PS → EXTENSAO-SUSPEITA" 1 \
     'EXTENSAO-SUSPEITA .*default, None' -- "$F/ruim-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "PS com ressalva e SPEC sem 'Limitações declaradas' → RESSALVA-SEM-LIMITACAO (R7)" 1 \
     'RESSALVA-SEM-LIMITACAO .*PS-01' -- "$F/ressalva-SPEC.md" "$F/ok-PRE-SPEC.md"
nao_casa "SPEC com a limitação declarada citando PS-01 → sem RESSALVA-SEM-LIMITACAO" \
     'RESSALVA-SEM-LIMITACAO' -- "$F/ok-SPEC.md" "$F/ok-PRE-SPEC.md"
nao_casa "AC legítimo (com corpo) não vira AC-POR-PONTEIRO" \
     'AC-POR-PONTEIRO' -- "$F/ok-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "as 5 formas de ponteiro (seta, 'ver §', sem arquivo, sem seta) → 5× AC-POR-PONTEIRO (S4)" 1 \
     'AC-POR-PONTEIRO=5' -- "$F/ponteiros-SPEC.md" "$F/ok-PRE-SPEC.md"
nao_casa "AC que só TERMINA com a citação (corpo próprio) não é acusado" \
     'AC-POR-PONTEIRO .*ponteiros-SPEC.md:1[4-6] ' -- "$F/ponteiros-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "PRE-SPEC sem bloco no modo completo → exit 1 e BLOCO-AUSENTE" 1 'BLOCO-AUSENTE' -- \
     "$F/ok-SPEC.md" "$F/sem-bloco-PRE-SPEC.md"
roda "uma limitação declarada não absolve a outra ressalva (cobertura por linha, R7)" 1 \
     'RESSALVA-SEM-LIMITACAO=1' -- "$F/uma-limitacao-SPEC.md" "$F/duas-ressalvas-PRE-SPEC.md"
nao_casa "a PS coberta por \`PS-01 descartada: …\` não é acusada" \
     'RESSALVA-SEM-LIMITACAO .*PS-01' -- "$F/uma-limitacao-SPEC.md" "$F/duas-ressalvas-PRE-SPEC.md"

echo "-- origem dos ACs (P12)"
roda "SPEC com marcador: AC sem origem → AC-SEM-ORIGEM é FALHA" 1 'AC-SEM-ORIGEM .*origem-SPEC.md:14 AC-05' -- "$F/origem-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "PS-99 na origem → AC-ORIGEM-INEXISTENTE" 1 'AC-ORIGEM-INEXISTENTE .*:11 AC-02 cita PS-99' -- "$F/origem-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "AC que cita a si mesmo → AC-ORIGEM-INEXISTENTE" 1 'AC-ORIGEM-INEXISTENTE .*:16 AC-07 cita a si mesmo' -- "$F/origem-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "AC-42 (não existe na SPEC) → AC-ORIGEM-INEXISTENTE" 1 \
     'AC-ORIGEM-INEXISTENTE .*:17 AC-08 cita AC-42' -- "$F/origem-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "id fora do padrão na origem → AC-ORIGEM-INEXISTENTE" 1 "AC-ORIGEM-INEXISTENTE .*:17 AC-08 cita 'capítulo 3'" -- "$F/origem-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "corpo vazio, só a origem → AC-POR-PONTEIRO" 1 'AC-POR-PONTEIRO .*:15 ' -- "$F/origem-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "sem --reqs: R2/SC-1/DESC-01 aceitos com ORIGEM-NAO-CONFERIDA (aviso único)" 1 \
     'ORIGEM-NAO-CONFERIDA .*R2, SC-1, DESC-01' -- "$F/origem-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "contagem exata: 4 INEXISTENTE · 1 SEM-ORIGEM · 1 POR-PONTEIRO" 1 \
     'AC-ORIGEM-INEXISTENTE=4 · AC-POR-PONTEIRO=1 · AC-SEM-ORIGEM=1' -- "$F/origem-SPEC.md" "$F/ok-PRE-SPEC.md"
nao_casa "AC-01 (PS-01, R2), AC-03 e AC-04 (AC-01) não são acusados" \
     'INEXISTENTE .*:(10|12|13) ' -- "$F/origem-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "com --reqs: SC-1 fora do REQUIREMENTS → INEXISTENTE" 1 \
     'AC-ORIGEM-INEXISTENTE .*:12 AC-03 cita SC-1' -- --reqs "$F/origem-REQUIREMENTS.md" "$F/origem-SPEC.md" "$F/ok-PRE-SPEC.md"
nao_casa "com --reqs: R2 e DESC-01 conferidos, sem ORIGEM-NAO-CONFERIDA" \
     'ORIGEM-NAO-CONFERIDA|cita (R2|DESC-01)' -- --reqs "$F/origem-REQUIREMENTS.md" "$F/origem-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "sem marcador e sem flag: AC-SEM-ORIGEM vira AVISO (retrocompatível)" 1 \
     'AC-SEM-ORIGEM .*:13 AC-05 .*aviso' -- "$F/origem-sem-marcador-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "sem marcador e sem flag: os INEXISTENTE continuam FALHA" 1 \
     'falhas=5 .*AC-SEM-ORIGEM=1' -- "$F/origem-sem-marcador-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "sem marcador + --exige-origem: AC-SEM-ORIGEM volta a FALHA" 1 \
     'falhas=6 ' -- --exige-origem "$F/origem-sem-marcador-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "spec antiga (sem sufixo, sem marcador) → só avisos, exit 0" 0 \
     'AC-SEM-ORIGEM=2' -- "$F/ok-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "spec antiga + --exige-origem → exit 1" 1 'AC-SEM-ORIGEM=2' -- --exige-origem "$F/ok-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "--reqs inexistente → exit 2" 2 'ERRO: --reqs' -- --reqs "$F/nao-existe.md" "$F/ok-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "REQ-ID com segmento de versão (CANC-v3x-01) casa o padrão e é conferido no --reqs" 1 \
     'AC-ORIGEM-INEXISTENTE .*:17 AC-08 cita AC-42' -- --reqs "$F/origem-REQUIREMENTS.md" "$F/origem-SPEC.md" "$F/ok-PRE-SPEC.md"

echo "-- classe do critério (D2 · D4 · D9 · D10, plano 1)"
roda "SPEC com classe limpo (AA-n, Goal, diverge com porquê, Cobertura do Goal) → exit 0" 0 \
     'falhas=0 .*nenhum achado' -- "$F/classe-ok-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "AC-SEM-CLASSE: AC sem tag" 1 'AC-SEM-CLASSE .*:15 AC-05 sem ' -- "$F/classe-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "AC-SEM-CLASSE: prosa ≠ bloco gsd:acs" 1 "AC-SEM-CLASSE .*:17 AC-07: prosa diz .desejavel. e o bloco gsd:acs diz 'exigido'" -- "$F/classe-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "AC-SEM-CLASSE: AC ausente do bloco / entrada do bloco sem AC" 1 \
     'AC-SEM-CLASSE .*:20 AC-10 ausente do bloco' -- "$F/classe-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "…AC-11 só no bloco" 1 'AC-SEM-CLASSE .*AC-11 está no bloco gsd:acs e não é AC' -- "$F/classe-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "EXIGIDO-SEM-MOTIVO: [exigido] sem ': motivo'" 1 'EXIGIDO-SEM-MOTIVO .*:14 AC-04' -- "$F/classe-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "EXIGIDO-SEM-REGUA: exigido cuja única origem é outro AC" 1 'EXIGIDO-SEM-REGUA .*:13 AC-03' -- "$F/classe-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "EXIGIDO-DIVERGE-SEM-MOTIVO: [diverge: AA-2] sem porquê na prosa E no bloco (2 linhas)" 1 \
     'EXIGIDO-DIVERGE-SEM-MOTIVO=2' -- "$F/classe-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "GOAL-SEM-COBERTURA: efeito descoberto nomeado" 1 'GOAL-SEM-COBERTURA .*:22 efeito do Goal sem exigido que o cubra: 9 janelas' -- "$F/classe-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "AA-9 inexistente no Anexo A → AC-ORIGEM-INEXISTENTE com os itens existentes" 1 \
     'AC-ORIGEM-INEXISTENTE .*:18 AC-08 cita AA-9, e o Anexo A .* não tem o item 9. \(itens: \[1, 2, 3\]\)' -- "$F/classe-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "AC-ORIGEM-REPETIDA é bandeira: 2 grupos (R2 · PS-01), contam como aviso" 1 \
     'AC-ORIGEM-REPETIDA .*:12 AC-02, AC-10 têm o mesmo conjunto de origens \(R2\)' -- "$F/classe-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "contagem exata dos sinos de classe" 1 \
     'falhas=10 · avisos=3 .*AC-ORIGEM-REPETIDA=2 · AC-SEM-CLASSE=4 · EXIGIDO-DIVERGE-SEM-MOTIVO=2 · EXIGIDO-SEM-MOTIVO=1 · EXIGIDO-SEM-REGUA=1 · GOAL-SEM-COBERTURA=1' -- "$F/classe-SPEC.md" "$F/anexo-PRE-SPEC.md"
nao_casa "classe é campo, não corpo: nenhum AC-POR-PONTEIRO nas fixtures de classe" \
     'AC-POR-PONTEIRO' -- "$F/classe-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "sem marcador e sem --exige-classe → tudo aviso, exit 0" 0 \
     'falhas=0 · avisos=13 .*AC-SEM-CLASSE=4' -- "$F/classe-sem-marcador-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "…cada aviso diz por quê é aviso" 0 'AC-SEM-CLASSE .*\(aviso: SPEC sem `<!-- spec-classe: v1 -->` e sem --exige-classe\)' -- "$F/classe-sem-marcador-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "sem marcador + --exige-classe → os mesmos viram FALHA" 1 'falhas=9 · avisos=4 ' -- --exige-classe "$F/classe-sem-marcador-SPEC.md" "$F/anexo-PRE-SPEC.md"
roda "AA-n sem seção Anexo A no PRE-SPEC → AC-ORIGEM-INEXISTENTE" 1 \
     'AC-ORIGEM-INEXISTENTE .*AC-01 cita AA-1 e .* não tem seção `## Anexo A`' -- "$F/classe-ok-SPEC.md" "$F/ok-PRE-SPEC.md"
roda "AA-n no modo sem pré-spec → AC-ORIGEM-INEXISTENTE 'a fase não tem PRE-SPEC'" 1 \
     'AC-ORIGEM-INEXISTENTE .*AC-01 cita AA-1 e a fase não tem PRE-SPEC' -- --sem-pre-spec "$F/classe-ok-SPEC.md"
nao_casa "SPEC anterior ao molde (sem tag, sem bloco, sem marcador) não recebe sino de classe algum" \
     'AC-SEM-CLASSE|GOAL-SEM-COBERTURA|EXIGIDO-|AC-ORIGEM-REPETIDA' -- "$F/origem-sem-marcador-SPEC.md" "$F/ok-PRE-SPEC.md"

echo "-- modo sem pré-spec (D7c)"
roda "SPEC sem PRE-SPEC, origens no REQUIREMENTS → limpo, exit 0, modo no resumo" 0 \
     'falhas=0 .*modo=sem-pre-spec' -- --sem-pre-spec --reqs "$F/origem-REQUIREMENTS.md" "$F/spec-sem-pre.md"
nao_casa "modo sem pré-spec: sem RESSALVA-SEM-LIMITACAO nem EXTENSAO-SUSPEITA (não há PS)" \
     'RESSALVA-SEM-LIMITACAO|EXTENSAO-SUSPEITA|BLOCO-AUSENTE' -- --sem-pre-spec --reqs "$F/origem-REQUIREMENTS.md" "$F/spec-sem-pre.md"
roda "modo sem pré-spec, sem --reqs: REQ-IDs aceitos com ORIGEM-NAO-CONFERIDA" 0 \
     'ORIGEM-NAO-CONFERIDA .*R2, DESC-01, CANC-v3x-01' -- --sem-pre-spec "$F/spec-sem-pre.md"
roda "modo sem pré-spec: AC sem origem → AC-SEM-ORIGEM (o marcador liga a falha)" 1 \
     'AC-SEM-ORIGEM .*origem-SPEC.md:14 AC-05' -- --sem-pre-spec "$F/origem-SPEC.md"
roda "modo sem pré-spec: origem PS-nn órfã → AC-ORIGEM-INEXISTENTE 'a fase não tem PRE-SPEC'" 1 \
     'AC-ORIGEM-INEXISTENTE .*:10 AC-01 cita PS-01 e a fase não tem PRE-SPEC' -- --sem-pre-spec "$F/origem-SPEC.md"
roda "modo sem pré-spec: marca [pre-spec:PS-nn] → ID-INEXISTENTE com a mesma mensagem" 1 \
     'ID-INEXISTENTE .*:6 marca cita PS-01 e a fase não tem PRE-SPEC' -- --sem-pre-spec "$F/origem-SPEC.md"
roda "modo sem pré-spec: SPEC inexistente → exit 2" 2 'ERRO: SPEC' -- --sem-pre-spec "$F/nao-existe.md"

echo "test-confere-pre-spec.sh: $falhas falha(s)"
[ "$falhas" -eq 0 ]
