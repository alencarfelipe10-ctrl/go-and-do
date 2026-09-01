#!/usr/bin/env bash
# test-confere-etapa.sh — bancada dos asserts da ETAPA 1 acrescentados na v2.2.0:
#   R2  `r2_pre_spec`            — falhas do confere-pre-spec.sh reprovam; EXTENSAO-SUSPEITA
#                                  é aviso e sai em `extrai.r2_avisos` (vai ao briefing)
#   R6  `r6_missing_requirement` — id do ROADMAP ausente do REQUIREMENTS reprova, a não ser
#       `r6_phase_without_req_id`  que haja sino ESTRUTURADO (`req_ausente: <id>` /
#                                  `fase_sem_req`); menção em prosa não conta
#
# Sempre em `--dry-run` (nada é gravado no run-log) e em projeto de bancada (mktemp):
# nenhum projeto real é tocado. Os asserts do manifest (SPEC/CONTEXT/…) reprovam nesta
# bancada de propósito — cada caso afirma SÓ o assert que está sendo medido.
#   bash tests/test-confere-etapa.sh      · exit 0 = verde
set -u

RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
C="$RAIZ/skills/go-and-do/scripts/confere-etapa.sh"
S="$RAIZ/skills/go-and-do/scripts/setup-intencao.sh"
FS="$RAIZ/tests/fixtures/setup"
FP="$RAIZ/tests/fixtures/pre-spec"

OK=0; FALHAS=0
ok()    { OK=$((OK+1)); printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }
casa()  { if printf '%s' "$2" | grep -qE "$3"; then ok "$1"; else falha "$1" "não casou /$3/ em: $(printf '%s' "$2" | head -c 220)"; fi; }

BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT

monta() { # <nome> <NN> → ecoa "<root>|<phase_dir>"
  local root="$BASE/$1" pd
  mkdir -p "$root/.planning/phases"
  cp "$FS/ROADMAP.md" "$FS/REQUIREMENTS.md" "$root/.planning/"
  git init -q "$root" >/dev/null 2>&1
  pd="$root/.planning/phases/$2-bancada"; mkdir -p "$pd/.intent"
  printf '%s|%s' "$root" "$pd"
}
confere() { # <root> <fase> → JSON do confere-etapa (última linha)
  bash "$C" 1 --projeto "$1" --fase "$2" --dry-run 2>/dev/null | tail -1
}
assert_de() { printf '%s' "$1" | jq -r --arg id "$2" '(.asserts[]|select(.id==$id)|.resultado) // "<ausente>"'; }

# ═════════════════════════════════════════════════════════════════════ R2
echo "── R2: SPEC × PRE-SPEC na cancela ──"
IFS='|' read -r R PD <<<"$(monta r2 99)"
cp "$FP/ok-PRE-SPEC.md" "$PD/99-PRE-SPEC.md"; cp "$FP/ok-SPEC.md" "$PD/99-SPEC.md"
J="$(confere "$R" 99)"
eq "SPEC conforme → r2_pre_spec ok"      "$(assert_de "$J" r2_pre_spec)" "ok"
casa "EXTENSAO-SUSPEITA sai em extrai.r2_avisos (insumo do briefing)" \
     "$(printf '%s' "$J" | jq -r '.extrai.r2_avisos|join("|")')" 'EXTENSAO-SUSPEITA'

cp "$FP/ruim-SPEC.md" "$PD/99-SPEC.md"
J="$(confere "$R" 99)"
eq "MARCA-SEM-ID / ID-INEXISTENTE → r2_pre_spec FALHA" "$(assert_de "$J" r2_pre_spec)" "FALHA"
eq "e o veredito da etapa é fail"        "$(printf '%s' "$J" | jq -r .veredito)" "fail"

IFS='|' read -r R PD <<<"$(monta r2legacy 99)"
cp "$FP/sem-bloco-PRE-SPEC.md" "$PD/99-PRE-SPEC.md"; cp "$FP/ok-SPEC.md" "$PD/99-SPEC.md"
J="$(confere "$R" 99)"
eq "PRE-SPEC sem bloco e sem rota → FALHA" "$(assert_de "$J" r2_pre_spec)" "FALHA"
bash "$S" "$PD" 99 --pre-spec-route legacy --resposta "autorizo a rota antiga" >/dev/null 2>&1
J="$(confere "$R" 99)"
eq "rota legacy autorizada pelo dono → aviso, não falha" "$(assert_de "$J" r2_pre_spec)" "aviso"

# ═════════════════════════════════════════════════════════════════════ R6
echo "── R6: issues estruturadas na cancela ──"
IFS='|' read -r R PD <<<"$(monta r6a 97)"
J="$(confere "$R" 97)"
eq "id do ROADMAP ausente do REQUIREMENTS → FALHA" "$(assert_de "$J" r6_missing_requirement)" "FALHA"
casa "Goal extraído também no fecho" "$(printf '%s' "$J" | jq -r .extrai.goal_roadmap)" 'ausente do REQUIREMENTS'

printf 'O SPEC menciona: FALTA-01 continua ausente do REQUIREMENTS.md e foi discutido.\n' \
  > "$PD/.intent/.sinos-spec.txt"
J="$(confere "$R" 97)"
eq "menção em PROSA não satisfaz o gate" "$(assert_de "$J" r6_missing_requirement)" "FALHA"

printf 'req_ausente: FALTA-01\n' >> "$PD/.intent/.sinos-spec.txt"
J="$(confere "$R" 97)"
eq "sino estruturado \`req_ausente: FALTA-01\` → aviso" "$(assert_de "$J" r6_missing_requirement)" "aviso"

rm -f "$PD/.intent/.sinos-spec.txt"
printf 'intent_review: done\n\n## Sinos\n\nreq_ausente: FALTA-01\n' > "$PD/97-INTENT-REVIEW.md"
J="$(confere "$R" 97)"
eq "sino sobrevivente no INTENT-REVIEW também vale (a limpeza 1.5 apaga os .sinos-*)" \
   "$(assert_de "$J" r6_missing_requirement)" "aviso"

rm -f "$PD/97-INTENT-REVIEW.md"
printf -- '- **FALTA-01**: requisito criado na etapa de spec.\n' >> "$R/.planning/REQUIREMENTS.md"
J="$(confere "$R" 97)"
eq "id criado no REQUIREMENTS → o assert some (issue resolvida)" \
   "$(assert_de "$J" r6_missing_requirement)" "<ausente>"
eq "e nenhuma issue sobra"  "$(printf '%s' "$J" | jq -r '.extrai.issues|length')" "0"

IFS='|' read -r R PD <<<"$(monta r6b 98)"
J="$(confere "$R" 98)"
eq "entrada sem REQ-ID → r6_phase_without_req_id FALHA" "$(assert_de "$J" r6_phase_without_req_id)" "FALHA"
printf 'fase_sem_req\n' > "$PD/.intent/.sinos-spec.txt"
J="$(confere "$R" 98)"
eq "sino \`fase_sem_req\` → aviso" "$(assert_de "$J" r6_phase_without_req_id)" "aviso"

IFS='|' read -r R PD <<<"$(monta r6c 99)"
J="$(confere "$R" 99)"
eq "entrada saudável → nenhum assert de R6"  "$(assert_de "$J" r6_missing_requirement)" "<ausente>"
eq "…nem o de fase sem requisito"            "$(assert_de "$J" r6_phase_without_req_id)" "<ausente>"
eq "…e r2 nem roda sem PRE-SPEC"             "$(printf '%s' "$J" | jq -r .extrai.r2_status)" "nao_aplicavel"

# ═════════════════════════════════════════════════════════════════════ R7
# R7 (proveniência T3, B4 — 31/08): cada achado `confirmado` da tabela do
# NN-INTENT-REVIEW.md tem de trazer a `proposicao` com os CINCO campos (artefato, ancora,
# span_linhas, texto, origem_texto). O formato da célula é o do arquivo real da F24.4: a
# coluna se chama `proposição` e a célula NÃO repete a chave — quem grepa `proposicao`
# literal mede zero e mata a regra. A escotilha de compatibilidade é o ponto delicado:
# arquivo SEM nenhuma proposição é fase anterior à régua → aviso, nunca falha.
echo "── R7: proveniência T3 (proposicao por achado confirmado) ──"

PROP_OK='`{artefato: SPEC, ancora: R3, span_linhas: [53,53], texto: "a frase | com pipe dentro", origem_texto: de_artefato_pos_ciclo}`'
PROP_MEIA='`{artefato: SPEC, ancora: R3, origem_texto: de_artefato_pos_ciclo}`'

tabela_ir() { # <arquivo> <celula c1-01> <celula c1-02> — monta um INTENT-REVIEW de bancada
  { printf 'intent_review: done\n\n'
    # tabela IRMÃ, sem coluna de proposição: não pode contaminar a contagem
    printf '| id | sino | disposição |\n|---|---|---|\n| c0-01 | sino qualquer | corrigido |\n\n'
    printf '| id | fontes | alegação | veredito | destino | ação tomada | proposição |\n'
    printf '|---|---|---|---|---|---|---|\n'
    printf '| c1-01 | codex | alegação um | confirmado | 1 | ação | %s |\n' "$2"
    printf '| c1-02 | agy | alegação dois | confirmado | 1 | ação | %s |\n' "$3"
    printf '| c1-03 | agy | alegação três | nao_sustentado | 2 | descartado | — |\n'
  } > "$1"
}

IFS='|' read -r R PD <<<"$(monta r7ok 99)"
tabela_ir "$PD/99-INTENT-REVIEW.md" "$PROP_OK" "$PROP_OK"
J="$(confere "$R" 99)"
eq "todos os confirmados com os 5 campos → ok" "$(assert_de "$J" r7_proposicao_t3)" "ok"
eq "e a tabela irmã sem coluna não entra na conta" \
   "$(printf '%s' "$J" | jq -r '.extrai.r7_confirmados')" "2"

IFS='|' read -r R PD <<<"$(monta r7parcial 99)"
tabela_ir "$PD/99-INTENT-REVIEW.md" "$PROP_OK" "—"
J="$(confere "$R" 99)"
eq "adoção PARCIAL (metade com, metade sem) → FALHA" "$(assert_de "$J" r7_proposicao_t3)" "FALHA"
casa "e o id sem proposição é nomeado" \
     "$(printf '%s' "$J" | jq -r '.asserts[]|select(.id=="r7_proposicao_t3")|.detalhe')" 'c1-02'
# o lock só é gravado FORA do --dry-run: uma rodada real (ainda em projeto de bancada)
# prova que R7 usa a mesma mecânica de dente do gate que R2/R6.
bash "$C" 1 --projeto "$R" --fase 99 >/dev/null 2>&1
[ -f "$PD/.gate-fail-1.json" ] && ok ".gate-fail-1.json criado (mesma mecânica de R2/R6)" \
  || falha ".gate-fail-1.json criado (mesma mecânica de R2/R6)" "lock ausente em $PD"

IFS='|' read -r R PD <<<"$(monta r7vazio 99)"
tabela_ir "$PD/99-INTENT-REVIEW.md" "—" "—"
J="$(confere "$R" 99)"
eq "NENHUM achado com proposição → escotilha: aviso, não falha (fase anterior à régua)" \
   "$(assert_de "$J" r7_proposicao_t3)" "aviso"

IFS='|' read -r R PD <<<"$(monta r7incompleto 99)"
tabela_ir "$PD/99-INTENT-REVIEW.md" "$PROP_OK" "$PROP_MEIA"
J="$(confere "$R" 99)"
eq "confirmado com 3 dos 5 campos → FALHA" "$(assert_de "$J" r7_proposicao_t3)" "FALHA"
casa "e o detalhe diz quantos campos vieram" \
     "$(printf '%s' "$J" | jq -r '.asserts[]|select(.id=="r7_proposicao_t3")|.detalhe')" 'c1-02\(3/5\)'

IFS='|' read -r R PD <<<"$(monta r7ausente 99)"
J="$(confere "$R" 99)"
eq "sem NN-INTENT-REVIEW.md → R7 não inventa falha (outra regra cuida disso)" \
   "$(assert_de "$J" r7_proposicao_t3)" "<ausente>"

# ═════════════════════════════════════════════ cancela da ETAPA 6 × STATE.md (B2)
# A cancela do fecho usava o MESMO grep literal do reconcilia-docs.sh (`^status:
# *executing`) e por isso herdava o mesmo ponto cego: `status` escrito como FRASE em vez
# do token — formato real, medido no alencarOS — nunca batia, e a etapa dava verde com o
# STATE.md errado. Agora há dois asserts: `state_reconciliado` (o antigo) e
# `state_formato` (novo). Como a regra de "o que é um token" vive nos dois scripts, esta
# bancada trava o lado da CANCELA; o lado do reconciliador é o test-reconcilia-docs.sh.
echo "── cancela 6: STATE.md como valor, não como grep literal ──"

monta_state() { # <nome> <valor do status> → ecoa a raiz do projeto de bancada
  local root="$BASE/$1"
  mkdir -p "$root/.planning/phases/96-bancada"
  git init -q "$root" >/dev/null 2>&1
  { printf -- '---\ncurrent_phase: 96\nstatus: %s\n---\n' "$2"; } > "$root/.planning/STATE.md"
  printf '%s' "$root"
}
confere6() { printf '%s' "$(bash "$C" 6 --projeto "$1" --fase 96 --dry-run 2>/dev/null | tail -1)"; }

J="$(confere6 "$(monta_state s6frase '"Fase 96 EM EXECUÇÃO → PAUSADA (2026-08-31) — waves 1-2 concluídas"')")"
eq "status como FRASE + fase batendo → state_formato FALHA (o buraco do B2)" \
   "$(assert_de "$J" state_formato)" "FALHA"

J="$(confere6 "$(monta_state s6exec executing)")"
eq "status: executing → state_reconciliado FALHA (regressão: o comportamento antigo vale)" \
   "$(assert_de "$J" state_reconciliado)" "FALHA"
eq "…e token válido não é acusado de formato inesperado" "$(assert_de "$J" state_formato)" "<ausente>"

J="$(confere6 "$(monta_state s6ok between_phases)")"
eq "status: between_phases → nenhum dos dois asserts" "$(assert_de "$J" state_reconciliado)" "<ausente>"
eq "…nem o de formato"                                "$(assert_de "$J" state_formato)" "<ausente>"

echo "--------------------------------------------------"
echo "test-confere-etapa.sh: $OK ok / $FALHAS falha(s)"
[ "$FALHAS" -eq 0 ]
