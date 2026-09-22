#!/usr/bin/env bash
# test-confere-etapa.sh — bancada dos asserts da ETAPA 1 acrescentados na v2.2.0:
#   R2  `r2_pre_spec`            — falhas do confere-pre-spec.sh reprovam; EXTENSAO-SUSPEITA
#                                  é aviso e sai em `extrai.r2_avisos` (vai ao briefing)
#   R6  `r6_missing_requirement` — id do ROADMAP ausente do REQUIREMENTS reprova, a não ser
#       `r6_phase_without_req_id`  que haja sino ESTRUTURADO (`req_ausente: <id>` /
#                                  `fase_sem_req`); menção em prosa não conta
#
# Em `--dry-run` (nada é gravado no run-log) na maior parte dos casos, e em projeto de bancada
# (mktemp) sempre — os casos do J5/fence rodam também sem a flag, para exercitar lock e fence:
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
# desde a fiação P19 a cancela passa --exige-origem: "conforme" inclui `[origem: …]` nos ACs
# (a ok-SPEC.md fica como "spec antiga" — o test-confere-pre-spec.sh depende disso)
sed -i 's/^\(- AC-0[12] — .*\)$/\1 [origem: PS-01]/' "$PD/99-SPEC.md"
J="$(confere "$R" 99)"
eq "SPEC conforme (ACs com origem) → r2_pre_spec ok" "$(assert_de "$J" r2_pre_spec)" "ok"
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

# ═══════════════════════════════════════ R2 × origem dos ACs (P12, fiação P19)
# A cancela passa `--exige-origem` sempre e `--reqs` quando o REQUIREMENTS.md existe:
# AC sem `[origem: …]` reprova mesmo em SPEC sem o marcador `spec-origem`; id inexistente
# reprova; REQ-ID sem REQUIREMENTS.md para conferir vira aviso em `extrai.r2_avisos`.
echo "── R2: origem dos ACs (--exige-origem / --reqs) ──"
IFS='|' read -r R PD <<<"$(monta r2origem 99)"
cp "$FP/ok-PRE-SPEC.md" "$PD/99-PRE-SPEC.md"; cp "$FP/ok-SPEC.md" "$PD/99-SPEC.md"
J="$(confere "$R" 99)"
eq "SPEC antiga (ACs sem origem) → AC-SEM-ORIGEM reprova a cancela" "$(assert_de "$J" r2_pre_spec)" "FALHA"
casa "…e o detalhe nomeia o código" \
     "$(printf '%s' "$J" | jq -r '.asserts[]|select(.id=="r2_pre_spec")|.detalhe')" 'AC-SEM-ORIGEM'
sed -i 's/^\(- AC-0[12] — .*\)$/\1 [origem: PS-01]/' "$PD/99-SPEC.md"
J="$(confere "$R" 99)"
eq "ACs com [origem: PS-01] → r2_pre_spec ok"  "$(assert_de "$J" r2_pre_spec)" "ok"
sed -i 's/^\(- AC-02 — .*\)\[origem: PS-01\]$/\1[origem: PS-99]/' "$PD/99-SPEC.md"
J="$(confere "$R" 99)"
eq "origem PS-99 (fora do bloco) → AC-ORIGEM-INEXISTENTE reprova" "$(assert_de "$J" r2_pre_spec)" "FALHA"
casa "…nomeado no detalhe" \
     "$(printf '%s' "$J" | jq -r '.asserts[]|select(.id=="r2_pre_spec")|.detalhe')" 'AC-ORIGEM-INEXISTENTE'
sed -i 's/\[origem: PS-99\]/[origem: BANC-01]/' "$PD/99-SPEC.md"
J="$(confere "$R" 99)"
eq "REQ-ID BANC-01 conferido no REQUIREMENTS.md (--reqs) → ok" "$(assert_de "$J" r2_pre_spec)" "ok"
eq "…sem aviso ORIGEM-NAO-CONFERIDA" \
   "$(printf '%s' "$J" | jq -r '[.extrai.r2_avisos[]|select(startswith("ORIGEM-NAO-CONFERIDA"))]|length')" "0"
rm -f "$R/.planning/REQUIREMENTS.md"
J="$(confere "$R" 99)"
eq "sem REQUIREMENTS.md → r2 continua ok (REQ-ID não é falha)" "$(assert_de "$J" r2_pre_spec)" "ok"
casa "…e ORIGEM-NAO-CONFERIDA sai em extrai.r2_avisos (vai ao briefing)" \
     "$(printf '%s' "$J" | jq -r '.extrai.r2_avisos|join("|")')" 'ORIGEM-NAO-CONFERIDA'

# ═══════════════════════════════════ R2 sem PRE-SPEC (modo sem pré-spec, D7c / plano 1)
# Fase sem NN-PRE-SPEC.md (SPEC do dono, ou gerado sem insumo): o SPEC passa pelas mesmas
# conferências de forma, com id `r2_spec_sem_pre_spec`. Hoje a fase saía sem item r2 nenhum.
echo "── R2: fase sem PRE-SPEC → r2_spec_sem_pre_spec ──"
IFS='|' read -r R PD <<<"$(monta r2sempre 99)"
cp "$FP/spec-sem-pre.md" "$PD/99-SPEC.md"
J="$(confere "$R" 99)"
eq "sem PRE-SPEC: item r2_spec_sem_pre_spec presente (era ausente)" \
   "$(printf '%s' "$J" | jq -r '[.asserts[]|select(.id=="r2_spec_sem_pre_spec")]|length')" "1"
eq "…e r2_pre_spec não aparece"  "$(assert_de "$J" r2_pre_spec)" "<ausente>"
eq "origens fora do REQUIREMENTS da bancada (R2, DESC-01, CANC-v3x-01) → FALHA" "$(assert_de "$J" r2_spec_sem_pre_spec)" "FALHA"
printf '# SPEC do dono\n\n- [ ] AC-01 — o DRE agrega por responsável-mês. [origem: BANC-01]\n- [ ] AC-02 — o Δ fecha em zero. [origem: AC-01]\n' > "$PD/99-SPEC.md"
J="$(confere "$R" 99)"
eq "SPEC do dono com origens conferidas no REQUIREMENTS → ok" "$(assert_de "$J" r2_spec_sem_pre_spec)" "ok"
eq "…extrai.r2_status = ok"  "$(printf '%s' "$J" | jq -r .extrai.r2_status)" "ok"
sed -i 's/\[origem: AC-01\]/[origem: PS-01]/' "$PD/99-SPEC.md"
J="$(confere "$R" 99)"
eq "origem PS-nn numa fase sem PRE-SPEC → FALHA" "$(assert_de "$J" r2_spec_sem_pre_spec)" "FALHA"
casa "…com a mensagem própria" \
     "$(printf '%s' "$J" | jq -r '.asserts[]|select(.id=="r2_spec_sem_pre_spec")|.detalhe')" 'a fase não tem PRE-SPEC'

# ═══════════════════════════════ R2 × classe do critério (plano 1, P-04): só por marcador
# O gate não passa --exige-classe. SPEC sem `<!-- spec-classe: v1 -->` mas com tag/bloco de
# classe (SPEC do dono fora do molde) → os códigos de classe saem como AVISO e não reprovam;
# com o marcador, reprovam.
echo "── R2: classe só por marcador (resposta 2 do dono) ──"
IFS='|' read -r R PD <<<"$(monta r2classe 99)"
rm -f "$R/.planning/REQUIREMENTS.md"   # as fixtures de classe citam R2/PS-nn/AA-n, não os ids da bancada
cp "$FP/anexo-PRE-SPEC.md" "$PD/99-PRE-SPEC.md"; cp "$FP/classe-sem-marcador-SPEC.md" "$PD/99-SPEC.md"
J="$(confere "$R" 99)"
eq "sem marcador: avisos de classe NÃO reprovam (r2_pre_spec ok)" "$(assert_de "$J" r2_pre_spec)" "ok"
casa "…e chegam ao briefing em extrai.r2_avisos" \
     "$(printf '%s' "$J" | jq -r '.extrai.r2_avisos|join("|")')" 'AC-SEM-CLASSE .*\(aviso: SPEC sem'
casa "…junto com a bandeira AC-ORIGEM-REPETIDA" \
     "$(printf '%s' "$J" | jq -r '.extrai.r2_avisos|join("|")')" 'AC-ORIGEM-REPETIDA'
cp "$FP/classe-SPEC.md" "$PD/99-SPEC.md"
J="$(confere "$R" 99)"
eq "com o marcador: os mesmos códigos reprovam" "$(assert_de "$J" r2_pre_spec)" "FALHA"
casa "…nomeados no detalhe" \
     "$(printf '%s' "$J" | jq -r '.asserts[]|select(.id=="r2_pre_spec")|.detalhe')" 'EXIGIDO-SEM-REGUA|AC-SEM-CLASSE|GOAL-SEM-COBERTURA'
cp "$FP/classe-ok-SPEC.md" "$PD/99-SPEC.md"
J="$(confere "$R" 99)"
eq "SPEC do molde novo, limpo → ok" "$(assert_de "$J" r2_pre_spec)" "ok"

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

# ═════════════════════════════════ cancela da ETAPA 3 × paralelismo (P04, 01/09)
# Mede pelo run-log quantos executores de cada onda planejada (>=2 planos) estiveram
# abertos juntos; reprova só `use_worktrees_alterado` (true no pré-despacho → false no
# fecho). O run-log sintético reproduz as grafias e o despacho órfão do arquivo real da
# F24.4 (despacho negado pelo sentinel fica sem retorno).
echo "── cancela 3: paralelismo observado ──"

plano3() { # <pd> <plan> <wave> [dep]
  { printf -- '---\nphase: "95"\nplan: %s\ntype: execute\nwave: %s\ndepends_on: [%s]\nfiles_modified:\n  - src/%s.py\nautonomous: true\n---\n' \
      "$2" "$3" "${4:-}" "$2"; } > "$1/95-$2-PLAN.md"
}
monta3() { # <nome> → ecoa "<root>|<phase_dir>"
  local root="$BASE/$1" pd="$BASE/$1/.planning/phases/95-bancada"
  mkdir -p "$pd"; git init -q "$root" >/dev/null 2>&1
  printf '{"workflow":{"use_worktrees":true}}\n' > "$root/.planning/config.json"
  plano3 "$pd" 01 1; plano3 "$pd" 02 1; plano3 "$pd" 03 2 '"95-01"'
  printf '%s|%s' "$root" "$pd"
}
ev() { # <arquivo> <seq> <ts> <evento> <descricao> [fim_real: true|false — só para retorno; default true]
  local fr=""
  [ "$4" = retorno ] && fr=",\"fim_real\":${6:-true}"
  printf '{"ts":"%s","seq":%s,"sessao":"b","evento":"%s","etapa":"3 construcao","camada":1,"agente":"gsd-executor","origem":"hook","descricao":"%s"%s}\n' \
    "$3" "$2" "$4" "$5" "$fr" >> "$1"
}
confere3() { printf '%s' "$(bash "$C" 3 --projeto "$1" --fase 95 --dry-run 2>/dev/null | tail -1)"; }

IFS='|' read -r R PD <<<"$(monta3 c3serial)"
RL="$PD/95-RUN-LOG.jsonl"
ev "$RL" 1 2026-09-01T10:00:00-03:00 despacho "Execute plan 01 of phase 95"      # negado (sem retorno)
ev "$RL" 2 2026-09-01T10:01:00-03:00 despacho "Execute plan 01 of phase INS-95"
ev "$RL" 3 2026-09-01T10:30:00-03:00 retorno  "Execute plan 01 of phase INS-95"
ev "$RL" 4 2026-09-01T10:31:00-03:00 despacho "Execute plan 95-02"
ev "$RL" 5 2026-09-01T11:00:00-03:00 retorno  "Execute plan 95-02"
J="$(confere3 "$R")"
eq "serial: onda 1 simultaneos_max 1 (o despacho órfão não conta como aberto)" \
   "$(printf '%s' "$J" | jq -c '.extrai.paralelismo_observado["1"].simultaneos_max')" "1"
eq "…despachados 2 (as três grafias de descricao resolvem)" \
   "$(printf '%s' "$J" | jq -c '.extrai.paralelismo_observado["1"].despachados')" "2"
eq "…serializacao_observada [\"1\"]" "$(printf '%s' "$J" | jq -c '.extrai.serializacao_observada')" '["1"]'
eq "…onda 2 (1 plano) não entra"   "$(printf '%s' "$J" | jq -c '.extrai.paralelismo_observado["2"] // "ausente"')" '"ausente"'
eq "…serialização não reprova" "$(assert_de "$J" use_worktrees_alterado)" "<ausente>"
eq "…C3: duracao_onda_s 3600 (10:00 → 11:00) e plano_mais_lento_s 1740 (o 01 relançado às 10:01)" \
   "$(printf '%s' "$J" | jq -c '.extrai.paralelismo_observado["1"]|[.duracao_onda_s,.plano_mais_lento_s]')" '[3600,1740]'
bash "$C" 3 --projeto "$R" --fase 95 >/dev/null 2>&1
casa "…C2: fora do dry-run a onda serializada vira incidente no run-log (origem=confere-etapa.sh)" "$(cat "$RL")" \
     '"evento":"incidente".*"origem":"confere-etapa.sh".*onda 1 serializada: 2 planos despachados.*janela entre despachos 1860s'
eq "…um incidente por onda serializada (1)" "$(grep -c 'onda 1 serializada' "$RL")" "1"

# v2.5.4 (45e): retorno só da chamada (fim_real:false, Agent assíncrono) NÃO fecha o despacho —
# a onda sai nao_medido e NUNCA vira "serializada" (F24.5: 12 incidentes falsos)
IFS='|' read -r R PD <<<"$(monta3 c3async)"
RL="$PD/95-RUN-LOG.jsonl"
ev "$RL" 1 2026-09-09T15:15:43-03:00 despacho "Execute plan 01 of phase INS-95"
ev "$RL" 2 2026-09-09T15:15:46-03:00 retorno  "Execute plan 01 of phase INS-95" false
ev "$RL" 3 2026-09-09T15:16:51-03:00 despacho "Execute plan 02 of phase INS-95"
ev "$RL" 4 2026-09-09T15:16:53-03:00 retorno  "Execute plan 02 of phase INS-95" false
J="$(confere3 "$R")"
eq "async: onda 1 simultaneos_max null" "$(printf '%s' "$J" | jq -c '.extrai.paralelismo_observado["1"].simultaneos_max')" "null"
casa "…nao_medido explica (sem retorno real)" "$(printf '%s' "$J" | jq -r '.extrai.paralelismo_observado["1"].nao_medido')" 'sem retorno real'
eq "…despachados 2" "$(printf '%s' "$J" | jq -c '.extrai.paralelismo_observado["1"].despachados')" "2"
eq "…serializacao_observada []" "$(printf '%s' "$J" | jq -c '.extrai.serializacao_observada')" '[]'
bash "$C" 3 --projeto "$R" --fase 95 >/dev/null 2>&1
eq "…zero incidente de onda serializada" "$(grep -c 'serializada' "$RL")" "0"
# misto: retorno de chamada E retorno real — o real fecha, a onda mede
IFS='|' read -r R PD <<<"$(monta3 c3misto)"
RL="$PD/95-RUN-LOG.jsonl"
ev "$RL" 1 2026-09-09T15:15:43-03:00 despacho "Execute plan 01 of phase INS-95"
ev "$RL" 2 2026-09-09T15:15:46-03:00 retorno  "Execute plan 01 of phase INS-95" false
ev "$RL" 3 2026-09-09T15:16:51-03:00 despacho "Execute plan 02 of phase INS-95"
ev "$RL" 4 2026-09-09T15:16:53-03:00 retorno  "Execute plan 02 of phase INS-95" false
ev "$RL" 5 2026-09-09T15:37:00-03:00 retorno  "Execute plan 01 of phase INS-95" true
ev "$RL" 6 2026-09-09T15:44:00-03:00 retorno  "Execute plan 02 of phase INS-95" true
J="$(confere3 "$R")"
eq "misto: simultaneos_max 2 (os dois abertos entre 15:16:51 e 15:37)" "$(printf '%s' "$J" | jq -c '.extrai.paralelismo_observado["1"].simultaneos_max')" "2"
eq "…sem nao_medido" "$(printf '%s' "$J" | jq -c '.extrai.paralelismo_observado["1"].nao_medido // "ausente"')" '"ausente"'
eq "…duracao_onda_s 1697 (15:15:43 → 15:44:00)" "$(printf '%s' "$J" | jq -c '.extrai.paralelismo_observado["1"].duracao_onda_s')" "1697"
# (47f) largura: janela 15:15:43 → 15:44:00 = 1697 s = 28 min; os dois ficam abertos de
# 15:16:51 a 15:37:00 (1209 s), então largura 1 = 1697-1209 = 488 s = 8 min (28 %).
eq "…largura.janela_executores_min 28"  "$(printf '%s' "$J" | jq -c '.extrai.largura.janela_executores_min')" "28"
eq "…largura.minutos_em_largura_1 8"    "$(printf '%s' "$J" | jq -c '.extrai.largura.minutos_em_largura_1')" "8"
eq "…largura.pct_largura_1 28"          "$(printf '%s' "$J" | jq -c '.extrai.largura.pct_largura_1')" "28"
# onda sem retorno real → pct null, nunca 0 (régua advisory, não cota)
eq "async: largura.pct_largura_1 null"  "$(printf '%s' "$(confere3 "$(cd "$BASE/c3async" && pwd)")" | jq -c '.extrai.largura.pct_largura_1')" "null"

IFS='|' read -r R PD <<<"$(monta3 c3paralelo)"
RL="$PD/95-RUN-LOG.jsonl"
ev "$RL" 1 2026-09-01T10:00:00-03:00 despacho "Execute plan 01 of phase 95"
ev "$RL" 2 2026-09-01T10:00:05-03:00 despacho "Execute plan 02 of phase 95"
ev "$RL" 3 2026-09-01T10:30:00-03:00 retorno  "Execute plan 01 of phase 95"
ev "$RL" 4 2026-09-01T10:31:00-03:00 retorno  "Execute plan 02 of phase 95"
J="$(confere3 "$R")"
eq "paralelo: simultaneos_max 2"       "$(printf '%s' "$J" | jq -c '.extrai.paralelismo_observado["1"].simultaneos_max')" "2"
eq "…janela_despachos_s 5"             "$(printf '%s' "$J" | jq -c '.extrai.paralelismo_observado["1"].janela_despachos_s')" "5"
eq "…serializacao_observada vazia"     "$(printf '%s' "$J" | jq -c '.extrai.serializacao_observada')" '[]'
eq "…C3: duracao_onda_s 1860 × plano_mais_lento_s 1855 (razão ≈ 1: paralelismo real)" \
   "$(printf '%s' "$J" | jq -c '.extrai.paralelismo_observado["1"]|[.duracao_onda_s,.plano_mais_lento_s]')" '[1860,1855]'
eq "…C3: extrai.suite sem lançamentos = zeros" "$(printf '%s' "$J" | jq -c '.extrai.suite')" '{"lancamentos":0,"recusados":0,"tempo_total_s":0,"tags":[],"fora_da_fase":[]}'
mkdir -p "$R/.git/gad-suite/suite" "$R/.git/gad-suite/gate-onda-1"
printf 'uv run pytest -n 4 -q -rf\n' > "$R/.git/gad-suite/suite/cmd"; date -Is -d '-100 seconds' > "$R/.git/gad-suite/suite/iniciado"; echo 1 > "$R/.git/gad-suite/suite/rc"; printf 'x\ny\n' > "$R/.git/gad-suite/suite/recusados"
printf 'uv run pytest tests/unit/test_a.py -rf\n' > "$R/.git/gad-suite/gate-onda-1/cmd"; date -Is -d '-30 seconds' > "$R/.git/gad-suite/gate-onda-1/iniciado"; echo 0 > "$R/.git/gad-suite/gate-onda-1/rc"
J="$(confere3 "$R")"
eq "…C3: extrai.suite conta lançamentos (2), recusados pelo lock (2) e as tags" "$(printf '%s' "$J" | jq -c '.extrai.suite|{lancamentos,recusados,tags}')" '{"lancamentos":2,"recusados":2,"tags":["gate-onda-1","suite"]}'
casa "…tempo_total_s ≈ 130 (iniciado → mtime do rc)" "$(printf '%s' "$J" | jq -r '.extrai.suite.tempo_total_s')" '^1[23][0-9]$'

IFS='|' read -r R PD <<<"$(monta3 c3um)"
RL="$PD/95-RUN-LOG.jsonl"
ev "$RL" 1 2026-09-01T10:00:00-03:00 despacho "Execute plan 01 of phase 95"
J="$(confere3 "$R")"
eq "1 só despacho na onda de 2 → não prova serialização" "$(printf '%s' "$J" | jq -c '.extrai.serializacao_observada')" '[]'

IFS='|' read -r R PD <<<"$(monta3 c3uw)"
mkdir -p "$R/.planning/.gad"; printf '{"use_worktrees":true}\n' > "$R/.planning/.gad/last-pre-despacho-3.json"
printf '{"workflow":{"use_worktrees":false}}\n' > "$R/.planning/config.json"
J="$(confere3 "$R")"
eq "use_worktrees true no pré-despacho → false no fecho: FALHA" "$(assert_de "$J" use_worktrees_alterado)" "FALHA"
eq "…extrai.use_worktrees {inicio:true, fecho:false}" "$(printf '%s' "$J" | jq -c '.extrai.use_worktrees')" '{"inicio":true,"fecho":false}'
# fora do --dry-run o incidente é gravado
bash "$C" 3 --projeto "$R" --fase 95 >/dev/null 2>&1
casa "…e o incidente vai ao run-log (origem=confere-etapa.sh)" "$(cat "$PD/95-RUN-LOG.jsonl" 2>/dev/null)" \
     '"evento":"incidente".*"origem":"confere-etapa.sh".*use_worktrees true→false'

IFS='|' read -r R PD <<<"$(monta3 c3sem_espelho)"
printf '{"workflow":{"use_worktrees":false}}\n' > "$R/.planning/config.json"
J="$(confere3 "$R")"
eq "sem espelho do pré-despacho → não acusa alteração" "$(assert_de "$J" use_worktrees_alterado)" "<ausente>"
eq "…inicio null"                          "$(printf '%s' "$J" | jq -c '.extrai.use_worktrees.inicio')" "null"

# ═════════════════════════════════ cancela da ETAPA 2 × plan_gate (P13, fiação P19)
# O manifest da etapa 2 extrai `plan_gate` do espelho `.planning/.gad/last-plan-gate.json`
# (tipo `json`, novo): informativo — passed/planos/ondas/largura_max/avisos. Espelho ausente
# → null e, fora do --dry-run, um `incidente` (o gate do fork sempre grava o espelho).
echo "── cancela 2: plan_gate (espelho do §13a-bis) ──"
monta2() { # <nome> → "<root>|<phase_dir>"
  local root="$BASE/$1" pd="$BASE/$1/.planning/phases/95-bancada"
  mkdir -p "$pd" "$root/.planning/.gad"; git init -q "$root" >/dev/null 2>&1
  plano3 "$pd" 01 1
  printf '%s|%s' "$root" "$pd"
}
confere2() { printf '%s' "$(bash "$C" 2 --projeto "$1" --fase 95 --dry-run 2>/dev/null | tail -1)"; }
IFS='|' read -r R PD <<<"$(monta2 c2sem)"
J="$(confere2 "$R")"
eq "sem last-plan-gate.json → extrai.plan_gate null" "$(printf '%s' "$J" | jq -c '.extrai.plan_gate')" "null"
bash "$C" 2 --projeto "$R" --fase 95 >/dev/null 2>&1
casa "…fora do --dry-run vira incidente no run-log" "$(cat "$PD/95-RUN-LOG.jsonl" 2>/dev/null)" \
     '"evento":"incidente".*"origem":"confere-etapa.sh".*plan_gate: last-plan-gate.json ausente'
IFS='|' read -r R PD <<<"$(monta2 c2com)"
printf '{"passed":true,"falhas":[],"avisos":[{"codigo":"CADEIA-QUASE-SERIAL","planos":["95-01"]}],"resumo":{"fase":"95","planos":11,"ondas":2,"razao":0.18,"largura_max":6}}\n' \
  > "$R/.planning/.gad/last-plan-gate.json"
J="$(confere2 "$R")"
eq "com espelho → {passed, fase, planos, ondas, razao, largura_max, avisos[].codigo}" \
   "$(printf '%s' "$J" | jq -c '.extrai.plan_gate')" '{"passed":true,"fase":"95","planos":11,"ondas":2,"razao":0.18,"largura_max":6,"avisos":["CADEIA-QUASE-SERIAL"]}'
eq "…e os extrai antigos seguem" "$(printf '%s' "$J" | jq -c '.extrai|has("nao_autonomos") and has("mapper_pulado")')" "true"

# ═══════════════════════════════ cancela da ETAPA 3 × escopo por plano (P06, 01/09)
# confere-plano.sh roda em cada plano com SUMMARY: FORA-DA-LISTA reprova a etapa,
# COMMITS-A-MENOS só extrai, cada plano reprovado vira `incidente`, e a falha de um plano
# não impede a conferência dos outros. Bancada com commits reais em repositório sintético.
echo "── cancela 3: escopo por plano (confere-plano.sh) ──"

monta3g() { # <nome> → "<root>|<phase_dir>" com 3 planos (01 ok · 02 fora da lista · 03 commits a menos)
  local root="$BASE/$1" pd="$BASE/$1/.planning/phases/95-bancada" p
  mkdir -p "$pd"; git init -q "$root" >/dev/null 2>&1
  git -C "$root" config user.email t@t; git -C "$root" config user.name t
  printf '{"workflow":{"use_worktrees":true}}\n' > "$root/.planning/config.json"
  plano3 "$pd" 01 1; plano3 "$pd" 02 1; plano3 "$pd" 03 2 '"95-01"'
  for p in 01 02 03; do printf '<tasks>\n<task type="auto">a</task>\n<task type="auto">b</task>\n</tasks>\n' >> "$pd/95-$p-PLAN.md"; done
  git -C "$root" add -A; git -C "$root" commit -qm 'docs(95): planos'
  c3() { local r="$1" m="$2"; shift 2; local f; for f in "$@"; do mkdir -p "$r/$(dirname "$f")"; date +%N >> "$r/$f"; done; git -C "$r" add -A; git -C "$r" commit -qm "$m"; }
  c3 "$root" 'feat(95-01): t1' src/01.py; c3 "$root" 'feat(95-01): t2' src/01.py
  c3 "$root" 'feat(95-02): t1' src/02.py; c3 "$root" 'fix(95-02): t2 fora' src/02.py src/intruso.py
  c3 "$root" 'feat(95-03): t1+t2' src/03.py
  c3 "$root" 'docs(95-03): complete t plan' .planning/phases/95-bancada/95-03-SUMMARY.md
  : > "$pd/95-01-SUMMARY.md"; : > "$pd/95-02-SUMMARY.md"
  printf '%s|%s' "$root" "$pd"
}
IFS='|' read -r R PD <<<"$(monta3g c3escopo)"
J="$(confere3 "$R")"
eq "FORA-DA-LISTA no plano 02 → escopo_planos FALHA"  "$(assert_de "$J" escopo_planos)" "FALHA"
casa "…e o detalhe nomeia plano e arquivo intruso" \
     "$(printf '%s' "$J" | jq -r '.asserts[]|select(.id=="escopo_planos")|.detalhe')" '95-02: FORA-DA-LISTA src/intruso.py'
eq "planos_conferidos.ok 1 (o 01) — a falha do 02 não derruba os outros" \
   "$(printf '%s' "$J" | jq -c '.extrai.planos_conferidos.ok')" "1"
eq "…falha lista 02 e 03"   "$(printf '%s' "$J" | jq -c '.extrai.planos_conferidos.falha')" '["95-02","95-03"]'
casa "…03 = COMMITS-A-MENOS (extraído)" "$(printf '%s' "$J" | jq -r '.extrai.planos_conferidos.codigos["95-03"][0]')" 'COMMITS-A-MENOS \(1 commits para 2 tarefas\)'
casa "…e COMMITS-A-MENOS entra na frase de reprovação (A1)" \
     "$(printf '%s' "$J" | jq -r '.asserts[]|select(.id=="escopo_planos")|.detalhe')" '95-03: COMMITS-A-MENOS \(1 commits para 2 tarefas\)'
bash "$C" 3 --projeto "$R" --fase 95 >/dev/null 2>&1
casa "…incidente por plano reprovado no run-log (origem=confere-plano.sh, plano 02)" \
     "$(cat "$PD/95-RUN-LOG.jsonl" 2>/dev/null)" '"evento":"incidente".*"origem":"confere-plano.sh".*"plano":"95-02".*FORA-DA-LISTA'
casa "…e também para o 03 (COMMITS-A-MENOS)" \
     "$(cat "$PD/95-RUN-LOG.jsonl" 2>/dev/null)" '"plano":"95-03".*COMMITS-A-MENOS'

IFS='|' read -r R PD <<<"$(monta3g c3escopo_so_menos)"
rm -f "$PD/95-02-SUMMARY.md"   # plano sem SUMMARY é pulado
J="$(confere3 "$R")"
eq "sem o 02: só COMMITS-A-MENOS → escopo_planos FALHA (A1: um commit por tarefa é cobrado)" "$(assert_de "$J" escopo_planos)" "FALHA"
eq "…planos_conferidos {ok:1, falha:[03]}" "$(printf '%s' "$J" | jq -c '.extrai.planos_conferidos|{ok,falha}')" '{"ok":1,"falha":["95-03"]}'
eq "…e o veredito da etapa é fail" "$(printf '%s' "$J" | jq -r .veredito)" "fail"

# ═══════════════════════════ cancela da ETAPA 3 × prova por reexecução (A4, plano 4, 05/09)
# "17 de 18 verdes" sem comando e saída na mesma seção `##`: aviso sem o marcador
# `<!-- gad_prova: v1 -->` (fase antiga), FALHA com ele; com a prova ao lado, passa.
# Os SUMMARYs sintéticos não têm PLAN.md par: o laço do confere-plano.sh os pula.
echo "── cancela 3: prova por reexecução (SUMMARY) ──"
IFS='|' read -r R PD <<<"$(monta3 c3prova)"
printf '%s\n' '---' 'phase: 95' 'plan: 07' '---' '# S' '## Next Phase Readiness' '- 17 dos 18 node IDs vermelhos atribuídos a este plano fecham verdes; o 18º aguarda o dono.' '## Self-Check' '- Cada arquivo tocado rodado isoladamente e verde: `test_a.py` (14 passed)' > "$PD/95-07-SUMMARY.md"
J="$(confere3 "$R")"
eq "sem marcador: prova_por_reexecucao = aviso"  "$(assert_de "$J" prova_por_reexecucao)" "aviso"
eq "…extrai.prova_avisos aponta 95-07-SUMMARY.md:7 (e não a linha 9, que traz a prova)" \
   "$(printf '%s' "$J" | jq -c '.extrai.prova_avisos|map("\(.arquivo):\(.linha)")')" '["95-07-SUMMARY.md:7"]'
sed -i '4a <!-- gad_prova: v1 -->' "$PD/95-07-SUMMARY.md"
J="$(confere3 "$R")"
eq "com marcador gad_prova: v1 → FALHA"           "$(assert_de "$J" prova_por_reexecucao)" "FALHA"
casa "…detalhe PROVA-SEM-REEXECUCAO com arquivo:linha e trecho" \
     "$(printf '%s' "$J" | jq -r '.asserts[]|select(.id=="prova_por_reexecucao")|.detalhe')" 'PROVA-SEM-REEXECUCAO: 95-07-SUMMARY.md:8 «17 dos 18'
bash "$C" 3 --projeto "$R" --fase 95 >/dev/null 2>&1
casa "…e o incidente vai ao run-log"              "$(cat "$PD/95-RUN-LOG.jsonl" 2>/dev/null)" '"evento":"incidente".*PROVA-SEM-REEXECUCAO em 95-07-SUMMARY.md:8'
printf '%s\n' '---' 'phase: 95' 'plan: 08' '---' '<!-- gad_prova: v1 -->' '# S' '## Verificação' '- 17 de 18 testes fecham verdes; o 18º é conhecido.' '$ uv run pytest tests/golden/test_x.py -q' '17 passed, 1 failed in 41.2s' > "$PD/95-08-SUMMARY.md"
rm -f "$PD/95-07-SUMMARY.md"
J="$(confere3 "$R")"
eq "afirmação com linha \$ comando e saída na mesma seção → sem assert (passa)" "$(assert_de "$J" prova_por_reexecucao)" "<ausente>"
eq "…prova_falhas vazio" "$(printf '%s' "$J" | jq -c '.extrai.prova_falhas')" '[]'

# ═══════════════════════════════════════════════════ J5 (45k) + fence (46j)
echo "── J5: proveniência do veredito na cancela da etapa 1 ──"
IFS='|' read -r R PD <<<"$(monta j5 99)"
printf 'c1-01 | novo | confirmado | A-produto\n' > "$PD/.intent/.vereditos-c1.txt"
J=$(confere "$R" 99)
eq "fase sem recibo em --dry-run → aviso, não FALHA (válvula da resposta 1 do dono)" \
   "$(assert_de "$J" j5_origem_c1)" "aviso"
J=$(bash "$C" 1 --projeto "$R" --fase 99 --sem-telemetria 2>/dev/null | tail -1)
eq "fase sem recibo fora do --dry-run → FALHA" "$(assert_de "$J" j5_origem_c1)" "FALHA"
printf '{"v":1,"ciclo":"1","run_id":"r","agente":"gad-verificador","mode":"child","ts":"t","n_linhas":1,"sha256":"%s"}\n' \
  "$(sha256sum "$PD/.intent/.vereditos-c1.txt" | cut -d' ' -f1)" > "$PD/.intent/.vereditos-c1.origem.json"
J=$(bash "$C" 1 --projeto "$R" --fase 99 --sem-telemetria 2>/dev/null | tail -1)
eq "recibo correto → ok" "$(assert_de "$J" j5_origem_c1)" "ok"
printf 'c1-02 | correcao | confirmado | D-documental\n' >> "$PD/.intent/.vereditos-c1.txt"
J=$(bash "$C" 1 --projeto "$R" --fase 99 --sem-telemetria 2>/dev/null | tail -1)
eq "linha acrescentada depois do recibo → VEREDITO-ALTERADO reprova a etapa 1" \
   "$(assert_de "$J" j5_origem_c1)" "FALHA"
casa "…com a mensagem literal" "$J" 'VEREDITO-ALTERADO c1'

echo "── FM-05INT (metade fiscal): SPEC/CONTEXT mudou depois do último selo ──"
IFS='|' read -r R PD <<<"$(monta selo 99)"
printf 'spec v1\n' > "$PD/99-SPEC.md"
BLOB_V1=$(git -C "$R" hash-object -- "${PD#"$R"/}/99-SPEC.md")
REL="${PD#"$R"/}/99-SPEC.md"
cat > "$PD/.intent/.correcoes-c1.aplicado" <<EOF
{"v":1,"ciclo":"1","ids":["c1-01"],"correcoes":[{"id":"c1-01","hash":"$BLOB_V1"}],
 "commit":"deadbeef","caminhos":["$REL"],"hash_ausente":[],
 "blobs":[{"path":"$REL","blob_commit":"$BLOB_V1","blob_worktree":"$BLOB_V1"}]}
EOF
J=$(confere "$R" 99)
eq "selo intacto → sem spec_context_sem_selo" "$(assert_de "$J" spec_context_sem_selo)" "<ausente>"
printf 'spec v1\nlinha acrescentada por fora do selo\n' > "$PD/99-SPEC.md"
J=$(confere "$R" 99)
eq "SPEC editado depois do selo → AVISO" "$(assert_de "$J" spec_context_sem_selo)" "AVISO"
casa "…nomeia o arquivo e os dois blobs" "$J" '99-SPEC\.md: selado'

echo "── FJ-02INT (metade script): aprovado_com_ressalva exige dívida nomeada ──"
IFS='|' read -r R PD <<<"$(monta ressalva 99)"
cat > "$PD/99-INTENT-REVIEW.md" <<'EOF'
---
intent_review: aprovado_com_ressalva
---

## Dívidas registradas

| id | alegação | evidência | dono | destino |
|----|----------|-----------|------|---------|
EOF
J=$(confere "$R" 99)
eq "ressalva sem NENHUMA dívida nomeada → FALHA" "$(assert_de "$J" intent_ressalva_sem_divida)" "FALHA"
casa "…diz «sem NENHUMA dívida»" "$J" 'sem NENHUMA dívida'

cat > "$PD/99-INTENT-REVIEW.md" <<'EOF'
---
intent_review: aprovado_com_ressalva
---

## Dívidas registradas

| id | alegação | evidência | dono | destino |
|----|----------|-----------|------|---------|
| c1-04 | d | ev | Amplify | plan-phase |
EOF
J=$(confere "$R" 99)
eq "dívida nomeada mas ausente do deferred-items.md → FALHA" "$(assert_de "$J" intent_ressalva_sem_divida)" "FALHA"
casa "…nomeia c1-04" "$J" 'c1-04'
printf -- '- c1-04 — dívida\n' > "$PD/deferred-items.md"
J=$(confere "$R" 99)
eq "dívida nomeada e registrada no deferred-items.md → ok" "$(assert_de "$J" intent_ressalva_sem_divida)" "ok"

IFS='|' read -r R PD <<<"$(monta semressalva 99)"
printf 'intent_review: done\n' > "$PD/99-INTENT-REVIEW.md"
J=$(confere "$R" 99)
eq "sem aprovado_com_ressalva → assert calado" "$(assert_de "$J" intent_ressalva_sem_divida)" "<ausente>"

echo "── FM-09INT: fiação do confere-cardinalidade.sh dentro do fiscal da etapa 1 ──"
IFS='|' read -r R PD <<<"$(monta card 99)"
cat > "$PD/99-INTENT-REVIEW.md" <<'EOF'
---
intent_review: done
achados_confirmados: 3
achados_descartados: 0
achados_dispensados: 0
---

## Tabela de achados

| id | alegação | fontes | veredito | destino |
|----|----------|--------|----------|---------|
| c1-01 | a | codex | confirmado (A-produto) | correção |
EOF
J=$(confere "$R" 99)
eq "cabeçalho 3 × tabela 1 → cardinalidade_etapa_1 vira AVISO" "$(assert_de "$J" cardinalidade_etapa_1)" "AVISO"
casa "…o detalhe nomeia CARDINALIDADE confirmados" "$J" 'CARDINALIDADE confirmados'
eq "…e o EXTRAI carrega o medido da cardinalidade" "$(printf '%s' "$J" | jq -r '.extrai.cardinalidade.medido.cabecalho.confirmados')" "3"

IFS='|' read -r R PD <<<"$(monta card2 99)"
cat > "$PD/99-INTENT-REVIEW.md" <<'EOF'
---
intent_review: done
achados_confirmados: 1
achados_descartados: 0
achados_dispensados: 0
---

## Tabela de achados

| id | alegação | fontes | veredito | destino |
|----|----------|--------|----------|---------|
| c1-01 | a | codex | confirmado (A-produto) | correção |
EOF
J=$(confere "$R" 99)
eq "cabeçalho e tabela batendo → sem cardinalidade_etapa_1" "$(assert_de "$J" cardinalidade_etapa_1)" "<ausente>"

echo "── 46(j)/46(r): o fiscal deixa recibo (.fence-N.ok) ──"
# a bancada reprova de propósito (SPEC/CONTEXT ausentes) → serve para o ramo fail
IFS='|' read -r R PD <<<"$(monta fence 99)"
: > "$PD/.fence-1.ok"
bash "$C" 1 --projeto "$R" --fase 99 --dry-run >/dev/null 2>&1
[ -f "$PD/.fence-1.ok" ] && ok "--dry-run não apaga o fence" || falha "--dry-run apagou o fence"
bash "$C" 1 --projeto "$R" --fase 99 >/dev/null 2>&1
[ -f "$PD/.fence-1.ok" ] && falha "fail não apagou o fence" || ok "fail apaga o .fence-1.ok"
[ -f "$PD/.gate-fail-1.json" ] && ok "fail grava o lock" || falha "fail não gravou o lock"
rm -f "$PD/.gate-fail-1.json"
bash "$C" 1 --projeto "$R" --fase 99 --sem-telemetria >/dev/null 2>&1
[ -f "$PD/.gate-fail-1.json" ] && falha "--sem-telemetria criou o lock no fail" \
  || ok "--sem-telemetria no fail NÃO cria o lock"

# ramo pass: a etapa 0 tem manifest mínimo (ponteiro da rodada + evento `run`) e é onde
# o ramo pass do write site genérico do fence pode ser exercitado numa bancada.
IFS='|' read -r R PD <<<"$(monta fencepass 99)"
git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false add -A >/dev/null 2>&1
git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm base >/dev/null 2>&1
printf '{"fase":"99"}\n' > "$R/.planning/.gad-rodada-ativa.json"
RLP="$PD/99-RUN-LOG.jsonl"
printf '{"evento":"run","etapa":"0 abertura"}\n' > "$RLP"
if bash "$C" 0 --projeto "$R" --fase 99 --sem-telemetria >/dev/null 2>&1; then
  [ -f "$PD/.fence-0.ok" ] && ok "pass grava o .fence-<etapa>.ok" || falha "pass não gravou o fence"
  eq "head do fence == HEAD" "$(jq -r .head "$PD/.fence-0.ok" 2>/dev/null)" \
     "$(git -C "$R" rev-parse HEAD)"
  printf '{"etapa":"0","ts":"x","resumo":"falhas: teste"}\n' > "$PD/.gate-fail-0.json"
  n=$(wc -l < "$RLP")
  bash "$C" 0 --projeto "$R" --fase 99 --sem-telemetria >/dev/null 2>&1
  [ -f "$PD/.gate-fail-0.json" ] && ok "--sem-telemetria no pass PRESERVA o lock" \
    || falha "--sem-telemetria removeu o lock no pass"
  eq "--sem-telemetria no pass não escreve no run-log" "$(wc -l < "$RLP")" "$n"
  bash "$C" 0 --projeto "$R" --fase 99 >/dev/null 2>&1
  [ -f "$PD/.gate-fail-0.json" ] && falha "a rodada normal não removeu o lock" \
    || ok "a rodada normal depois do --sem-telemetria remove o lock"
  eq "…e grava 'pass pós-fail (lock removido)' exatamente uma vez" \
     "$(grep -c 'pass pós-fail (lock removido)' "$RLP" || true)" "1"
else
  falha "bancada do ramo pass não passou na cancela da etapa 0" \
    "$(bash "$C" 0 --projeto "$R" --fase 99 --dry-run 2>/dev/null | tail -1 | jq -r '[.asserts[]|select(.resultado=="FALHA")|.id]|join(",")')"
fi


# ══════════════════════════════════════════ F4 RLR — regras gerais do fiscal
# FM-07INT/FM-04PLAN/FM-07GAT (incidente tardio) · FM-06INT (pasta suja) ·
# FM-04GAT (maior iteração + all_fixed com skipped) · FM-02ENC (local à frente).
echo "── F4 RLR: incidente tardio, pasta suja, review de maior iteração ──"

rl_linha() { # <evento> <etapa> <ts> [detalhe]
  printf '{"evento":"%s","etapa":"%s","ts":%s,"detalhe":"%s"}\n' "$1" "$2" "$3" "${4:-}"
}

# — incidente POSTERIOR ao `end` da própria etapa reprova
IFS='|' read -r R PD <<<"$(monta tardio 99)"
RL="$PD/99-RUN-LOG.jsonl"
{ rl_linha incidente "1 intencao" 1000 "na hora"
  rl_linha end       "1 intencao" 2000
  rl_linha incidente "1 intencao" 2500 "escrito no fecho, de memoria"; } > "$RL"
J="$(confere "$R" 99)"
# DECISÃO DO DONO (21/09): AVISO nesta release, dura na seguinte — medido em modo seco,
# o assert reprova quase toda etapa das 3 fases reais porque a prática de escrever
# incidente no fecho é real e ainda não passou por uma fase com os prompts novos.
eq "incidente depois do end da etapa → AVISO (dura na release seguinte)" "$(assert_de "$J" incidente_tardio)" "AVISO"
casa "o aviso diz quantos segundos depois" "$J" '\+500s do end'

# — incidente de OUTRA etapa não reprova esta (recorte medido em 21/09)
IFS='|' read -r R PD <<<"$(monta tardio_outra 99)"
RL="$PD/99-RUN-LOG.jsonl"
{ rl_linha end       "3 construcao" 2000
  rl_linha incidente "3 construcao" 2500 "tardio, mas da etapa 3"
  rl_linha incidente "1 intencao"   1000 "na hora"; } > "$RL"
J="$(confere "$R" 99)"
eq "tardio de outra etapa não reprova a etapa 1" "$(assert_de "$J" incidente_tardio)" "<ausente>"

# — rajada: >= 3 incidentes no mesmo segundo
IFS='|' read -r R PD <<<"$(monta rajada 99)"
RL="$PD/99-RUN-LOG.jsonl"
{ rl_linha incidente "1 intencao" 1500 a; rl_linha incidente "1 intencao" 1500 b
  rl_linha incidente "1 intencao" 1500 c; } > "$RL"
J="$(confere "$R" 99)"
# A rajada foi rebaixada junto: o assert é um só e o dono nomeou o assert.
eq "3 incidentes no mesmo segundo → AVISO" "$(assert_de "$J" incidente_tardio)" "AVISO"
casa "o aviso nomeia a rajada" "$J" 'incidentes no mesmo segundo'

# — run-log sadio não acusa nada
IFS='|' read -r R PD <<<"$(monta sadio 99)"
RL="$PD/99-RUN-LOG.jsonl"
{ rl_linha incidente "1 intencao" 1000 a; rl_linha incidente "1 intencao" 1200 b
  rl_linha end "1 intencao" 2000; } > "$RL"
J="$(confere "$R" 99)"
eq "run-log sadio → sem incidente_tardio" "$(assert_de "$J" incidente_tardio)" "<ausente>"

# — FM-06INT: arquivo da pasta da fase fora de commit reprova; temporário não
IFS='|' read -r R PD <<<"$(monta suja 99)"
( cd "$R" && git add -A >/dev/null 2>&1 && git -c user.name=t -c user.email=t@t.io \
    -c commit.gpgsign=false commit -qm base >/dev/null 2>&1 )
echo "parecer que ninguem commitou" > "$PD/99-parecer-codex.md"
J="$(confere "$R" 99)"
# AVISO, não FALHA: o workflow roda o fiscal ANTES do commita-artefatos.sh — como falha
# dura a etapa 5 entraria em impasse. Contradição levada ao dono (regra 6 do plano).
eq "arquivo novo na pasta da fase → AVISO" "$(assert_de "$J" pasta_da_fase_suja)" "AVISO"
casa "o aviso manda rodar o commita-artefatos" "$J" 'commita-artefatos\.sh'
rm -f "$PD/99-parecer-codex.md"
echo x > "$PD/.intent/rascunho.tmp"; echo y > "$PD/saida.log"
J="$(confere "$R" 99)"
eq "só temporários (.tmp/.log) → sem aviso de pasta suja" "$(assert_de "$J" pasta_da_fase_suja)" "<ausente>"
rm -f "$PD/.intent/rascunho.tmp" "$PD/saida.log"

# — FM-06INT, DECISÃO DO DONO (21/09): falha dura SÓ para a evidência dura, e o que a
#   própria etapa produz é isento. `.intent/` e `pareceres/` são produzidos pela etapa 1.
echo "selo do ciclo 1" > "$PD/.intent/.correcoes-c1.aplicado"
J="$(confere "$R" 99)"
eq "etapa 1: .intent/ fora de commit é ISENTO (é ela quem produz) → só AVISO" \
   "$(assert_de "$J" evidencia_fora_do_git)" "<ausente>"
eq "…e aparece no aviso de pasta suja" "$(assert_de "$J" pasta_da_fase_suja)" "AVISO"
J2="$(bash "$C" 3 --projeto "$R" --fase 99 --dry-run 2>/dev/null | tail -1)"
eq "etapa 3: .intent/ fora de commit → FALHA dura (evidencia_fora_do_git)" \
   "$(assert_de "$J2" evidencia_fora_do_git)" "FALHA"
casa "a falha dura nomeia o modo evidencia do commita-artefatos" "$J2" 'evidencia'
rm -f "$PD/.intent/.correcoes-c1.aplicado"

# — atestado: o `.fence-N.ok` da PRÓPRIA etapa é isento; o de outra etapa é duro
echo ok > "$PD/.fence-1.ok"
J="$(confere "$R" 99)"
eq "atestado da própria etapa (.fence-1.ok na etapa 1) → isento" \
   "$(assert_de "$J" evidencia_fora_do_git)" "<ausente>"
J2="$(bash "$C" 3 --projeto "$R" --fase 99 --dry-run 2>/dev/null | tail -1)"
eq "atestado de OUTRA etapa fora de commit → FALHA dura" \
   "$(assert_de "$J2" evidencia_fora_do_git)" "FALHA"
rm -f "$PD/.fence-1.ok"

# — FM-01GAT: recibo do 4.1 vencido por commit de CÓDIGO posterior ao head aprovado
IFS='|' read -r R PD <<<"$(monta recibo 99)"
gitq() { git -C "$R" -c user.name=t -c user.email=t@t.io -c commit.gpgsign=false "$@" >/dev/null 2>&1; }
mkdir -p "$R/src"; echo v1 > "$R/src/fluxo.py"; gitq add -A; gitq commit -qm base
H=$(git -C "$R" rev-parse HEAD)
printf '{"v":1,"etapa":"4.1","fase":"99","head":"%s"}\n' "$H" > "$PD/.fence-4.1.ok"
J="$(bash "$C" 4-secure --projeto "$R" --fase 99 --dry-run 2>/dev/null | tail -1)"
eq "recibo do 4.1 com o head atual → não reprova" "$(assert_de "$J" recibo_4_1_vencido)" "<ausente>"
echo v2 > "$R/src/fluxo.py"; gitq add -A; gitq commit -qm "fix(WR-14): conserto depois do gate"
J="$(bash "$C" 4-secure --projeto "$R" --fase 99 --dry-run 2>/dev/null | tail -1)"
eq "commit de código depois do recibo → FALHA (o gate reabre)" \
   "$(assert_de "$J" recibo_4_1_vencido)" "FALHA"
casa "a falha nomeia o novo fiscal + novo end + novo recibo" "$J" 'novo fiscal'
# artefato da rodada NÃO vence o recibo: recibo vencido é código que mudou
gitq checkout -- . ; echo v2 > "$R/src/fluxo.py"; gitq add -A; gitq commit -qm x
H2=$(git -C "$R" rev-parse HEAD)
printf '{"v":1,"etapa":"4.1","fase":"99","head":"%s"}\n' "$H2" > "$PD/.fence-4.1.ok"
echo nota > "$PD/99-NOTA.md"; gitq add -A; gitq commit -qm "docs: artefato da rodada"
J="$(bash "$C" 4-secure --projeto "$R" --fase 99 --dry-run 2>/dev/null | tail -1)"
eq "commit só em .planning/ não vence o recibo" "$(assert_de "$J" recibo_4_1_vencido)" "<ausente>"
eq "o 4.1 não julga o próprio recibo" \
   "$(assert_de "$(bash "$C" 4-code-review --projeto "$R" --fase 99 --dry-run 2>/dev/null | tail -1)" recibo_4_1_vencido)" "<ausente>"

# — FM-04GAT: o 4.1 lê o arquivo de MAIOR iteração e reprova all_fixed com skipped
IFS='|' read -r R PD <<<"$(monta review 99)"
printf 'status: issues_found\ncritical: 2\nskipped: 0\n' > "$PD/99-REVIEW.md"
printf 'status: issues_found\ncritical: 1\nskipped: 0\n' > "$PD/99-REVIEW.iter3.md"
printf 'status: all_fixed\ncritical: 0\nskipped: 4\n'    > "$PD/99-REVIEW-FIX.iter4.md"
JR="$(bash "$C" 4-code-review --projeto "$R" --fase 99 --dry-run 2>/dev/null | tail -1)"
eq "leu o arquivo de maior iteração" \
  "$(printf '%s' "$JR" | jq -r '.extrai.review_maior_iteracao.arquivo')" "99-REVIEW-FIX.iter4.md"
eq "as contagens que a camada 0 lê vêm da maior iteração (não do REVIEW.md)" \
  "$(printf '%s' "$JR" | jq -r '.extrai.status')" "status: all_fixed"
eq "all_fixed com skipped > 0 → FALHA" "$(assert_de "$JR" all_fixed_com_skipped)" "FALHA"
printf 'status: all_fixed\ncritical: 0\nskipped: 0\n' > "$PD/99-REVIEW-FIX.iter4.md"
JR="$(bash "$C" 4-code-review --projeto "$R" --fase 99 --dry-run 2>/dev/null | tail -1)"
eq "all_fixed com skipped 0 → sem falha" "$(assert_de "$JR" all_fixed_com_skipped)" "<ausente>"
printf 'sem cabecalho nenhum\n' > "$PD/99-REVIEW-FIX.iter4.md"
JR="$(bash "$C" 4-code-review --projeto "$R" --fase 99 --dry-run 2>/dev/null | tail -1)"
eq "formato não reconhecido falha ALTO" "$(assert_de "$JR" review_formato)" "FALHA"

# ══════════════════════════════════════════ F4 RLR — FJ-01ENC (etapa 6)
# Os dois resumos da F4 RLR disseram que as rodadas «fecharam os avisos restantes» com
# WR-09 aberto. O fiscal da etapa 6 agora cobra ID por ID, da MESMA lista que o 4.1 lê.
echo "── F4 RLR: ID aberto do code review tem de aparecer no resumo (FJ-01ENC) ──"
monta_res() { # <nome> <texto do resumo> → raiz do projeto de bancada
  local root="$BASE/$1" pd
  mkdir -p "$root/.planning/phases/96-bancada"; git init -q "$root" >/dev/null 2>&1
  printf -- '---\ncurrent_phase: 96\nstatus: between_phases\n---\n' > "$root/.planning/STATE.md"
  pd="$root/.planning/phases/96-bancada"
  cat > "$pd/96-REVIEW-FIX.iter2.md" <<'MD'
---
iteration: 2
status: all_fixed
---
## Fechados
### WR-01 — consertado
## Deixados ABERTOS e declarados
- **WR-09** (processo) — fora deste conserto.
MD
  printf '%s\n' "$2" > "$pd/96-RESUMO-EXECUTIVO.md"
  printf '%s' "$root"
}
J="$(confere6 "$(monta_res resumo_sem 'As rodadas fecharam os avisos restantes.')")"
eq "resumo que não cita o ID aberto → FALHA" "$(assert_de "$J" resumo_sem_id_aberto)" "FALHA"
casa "…e o assert nomeia o ID que falta" "$J" 'WR-09'
J="$(confere6 "$(monta_res resumo_com 'Segue aberto: WR-09 (processo), sem conserto sem reescrever histórico.')")"
eq "resumo que cita WR-09 → sem acusação" "$(assert_de "$J" resumo_sem_id_aberto)" "<ausente>"
J="$(confere6 "$(monta_state s6semresumo between_phases)")"
eq "fase sem resumo ainda escrito → assert calado" "$(assert_de "$J" resumo_sem_id_aberto)" "<ausente>"

echo "--------------------------------------------------"
echo "test-confere-etapa.sh: $OK ok / $FALHAS falha(s)"
[ "$FALHAS" -eq 0 ]
