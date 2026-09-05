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
ev() { # <arquivo> <seq> <ts> <evento> <descricao>
  printf '{"ts":"%s","seq":%s,"sessao":"b","evento":"%s","etapa":"3 construcao","camada":1,"agente":"gsd-executor","origem":"hook","descricao":"%s"}\n' \
    "$3" "$2" "$4" "$5" >> "$1"
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
eq "…C3: extrai.suite sem lançamentos = zeros" "$(printf '%s' "$J" | jq -c '.extrai.suite')" '{"lancamentos":0,"recusados":0,"tempo_total_s":0,"tags":[]}'
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

echo "--------------------------------------------------"
echo "test-confere-etapa.sh: $OK ok / $FALHAS falha(s)"
[ "$FALHAS" -eq 0 ]
