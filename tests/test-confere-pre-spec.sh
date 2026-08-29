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
roda "PRE-SPEC sem bloco no modo completo → exit 1 e BLOCO-AUSENTE" 1 'BLOCO-AUSENTE' -- \
     "$F/ok-SPEC.md" "$F/sem-bloco-PRE-SPEC.md"
roda "uma limitação declarada não absolve a outra ressalva (cobertura por linha, R7)" 1 \
     'RESSALVA-SEM-LIMITACAO=1' -- "$F/uma-limitacao-SPEC.md" "$F/duas-ressalvas-PRE-SPEC.md"
nao_casa "a PS coberta por \`PS-01 descartada: …\` não é acusada" \
     'RESSALVA-SEM-LIMITACAO .*PS-01' -- "$F/uma-limitacao-SPEC.md" "$F/duas-ressalvas-PRE-SPEC.md"

echo "test-confere-pre-spec.sh: $falhas falha(s)"
[ "$falhas" -eq 0 ]
