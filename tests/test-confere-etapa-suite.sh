#!/usr/bin/env bash
# test-confere-etapa-suite.sh — bancada do bloco «suíte final» da cancela da ETAPA 3 (45n,
# v2.5.4 — F24.5): a última suíte COMPLETA da etapa precisa estar verde e sem commit de
# código depois dela; a última onda precisa de gate próprio quando o projeto usa
# `roda-suite.sh --gate-onda`. Cobre também o escape sancionado do dono (suite-ressalva.sh).
#
# Sempre em `--dry-run` (nada é gravado no run-log, salvo onde o caso pede a rodada real) e
# em projeto de bancada (mktemp): nenhum projeto real é tocado.
#   bash tests/test-confere-etapa-suite.sh      · exit 0 = verde
set -u

RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
C="$RAIZ/skills/go-and-do/scripts/confere-etapa.sh"
SR="$RAIZ/skills/go-and-do/scripts/suite-ressalva.sh"

OK=0; FALHAS=0
ok()    { OK=$((OK+1)); printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }
casa()  { if printf '%s' "$2" | grep -qE "$3"; then ok "$1"; else falha "$1" "não casou /$3/ em: $(printf '%s' "$2" | head -c 220)"; fi; }

BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT

# ── copiado de tests/test-confere-etapa.sh (bloco «cancela 3: paralelismo observado») ──
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
  local extra=""
  [ "$4" = "retorno" ] && extra=',"fim_real":true'
  printf '{"ts":"%s","seq":%s,"sessao":"b","evento":"%s","etapa":"3 construcao","camada":1,"agente":"gsd-executor","origem":"hook","descricao":"%s"%s}\n' \
    "$3" "$2" "$4" "$5" "$extra" >> "$1"
}
confere3() { printf '%s' "$(bash "$C" 3 --projeto "$1" --fase 95 --dry-run 2>/dev/null | tail -1)"; }

# ── helpers do P5 ──
suite_tag() { # <root> <tag> <iniciado ISO> <rc|->
  local st="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)/gad-suite/$2"
  mkdir -p "$st"; echo 'uv run pytest -q' > "$st/cmd"; echo "$3" > "$st/iniciado"
  [ "$4" != - ] && echo "$4" > "$st/rc"; return 0
}
commit_codigo() { # <root> <arquivo> <msg> <data ISO> — commit com data fixa
  mkdir -p "$(dirname "$1/$2")"; echo x >> "$1/$2"; git -C "$1" add -A >/dev/null
  GIT_AUTHOR_DATE="$4" GIT_COMMITTER_DATE="$4" git -C "$1" -c user.email=t@t -c user.name=t commit -qm "$3" >/dev/null
}
# DESVIO (documentado no relatório): o manifest da etapa 3 (manifests/etapa-3.json) tem dois
# asserts INCONDICIONAIS alheios ao escopo do P5 (has_verification via SDK, summaries via
# glob de *-SUMMARY.md) que ficam FALHA em qualquer fixture de bancada sem VERIFICATION.md
# nem SUMMARY.md — inclusive nos casos do test-confere-etapa.sh existente (que não quebram
# porque só conferem ids específicos via assert_de, nunca a lista inteira). codigos() filtra
# só os 5 ids que este bloco pode produzir, para não acoplar esta bancada a ruído alheio.
SF_IDS='["suite_final_vermelha","suite_nao_relancada","suite_em_curso","suite_completa_ausente","ultima_onda_sem_gate"]'
codigos() { printf '%s' "$1" | jq -c --argjson ids "$SF_IDS" \
  '[.asserts[]? // empty | select(.resultado=="FALHA") | select(.id as $i | $ids|index($i)) | .id] // []'; }

# monta3 já grava config.json com use_worktrees; acrescenta test_command e faz o commit
# inicial dos planos+config (a data desse commit é anterior a qualquer suite_tag dos casos).
prep() { # <root> <pd> <test_command|->
  git -C "$1" config user.email t@t; git -C "$1" config user.name t
  if [ "$3" != - ]; then
    printf '%s\n' "$(jq -c --arg tc "$3" '.workflow.test_command=$tc' "$1/.planning/config.json")" > "$1/.planning/config.json"
  fi
  git -C "$1" add -A; git -C "$1" commit -qm 'docs(95): planos' >/dev/null
}
despacho_retorno() { # <run-log> — 1 despacho/retorno de executor às 10:00/10:30 de 2026-09-01
  ev "$1" 1 2026-09-01T10:00:00-03:00 despacho "Execute plan 01 of phase 95"
  ev "$1" 2 2026-09-01T10:30:00-03:00 retorno  "Execute plan 01 of phase 95"
}

echo "── cancela 3: suíte final (45n) ──"

# 1. Verde e limpa
IFS='|' read -r R PD <<<"$(monta3 sf1verde)"
prep "$R" "$PD" 'roda-suite.sh --gate-onda'
despacho_retorno "$PD/95-RUN-LOG.jsonl"
suite_tag "$R" gate-onda-1 2026-09-01T10:40:00-03:00 0
suite_tag "$R" gate-onda-2 2026-09-01T10:50:00-03:00 0
suite_tag "$R" suite       2026-09-01T11:00:00-03:00 0
J="$(confere3 "$R")"
eq "verde+limpa: suite_final.aplica true" "$(printf '%s' "$J" | jq -r '.extrai.suite_final.aplica')" "true"
eq "…sem código nenhum" "$(codigos "$J")" "[]"

# 2. Vermelha
IFS='|' read -r R PD <<<"$(monta3 sf2vermelha)"
prep "$R" "$PD" 'roda-suite.sh --gate-onda'
despacho_retorno "$PD/95-RUN-LOG.jsonl"
suite_tag "$R" gate-onda-1 2026-09-01T10:40:00-03:00 0
suite_tag "$R" gate-onda-2 2026-09-01T10:50:00-03:00 0
suite_tag "$R" suite       2026-09-01T11:00:00-03:00 1
J="$(confere3 "$R")"
eq "vermelha: FALHA suite_final_vermelha" "$(codigos "$J")" '["suite_final_vermelha"]'

# 3. Vermelha com ressalva do dono
IFS='|' read -r R PD <<<"$(monta3 sf3ressalva)"
prep "$R" "$PD" 'roda-suite.sh --gate-onda'
despacho_retorno "$PD/95-RUN-LOG.jsonl"
suite_tag "$R" gate-onda-1 2026-09-01T10:40:00-03:00 0
suite_tag "$R" gate-onda-2 2026-09-01T10:50:00-03:00 0
suite_tag "$R" suite       2026-09-01T11:00:00-03:00 1
printf -- '---\nphase: "95"\nsuite_final: vermelha\nsuite_ressalva: "aceito pelo dono"\n---\nbody\n' > "$PD/95-VERIFICATION.md"
J="$(confere3 "$R")"
eq "ressalva: sem FALHA" "$(codigos "$J")" "[]"
eq "…asserts tem suite_final INFORMATIVO" \
   "$(printf '%s' "$J" | jq -r '.asserts[]|select(.id=="suite_final")|.resultado')" "INFORMATIVO"
bash "$C" 3 --projeto "$R" --fase 95 >/dev/null 2>&1
casa "…fora do dry-run vira incidente (origem=confere-etapa.sh, aceita pelo dono)" \
     "$(cat "$PD/95-RUN-LOG.jsonl" 2>/dev/null)" \
     '"evento":"incidente".*"origem":"confere-etapa.sh".*aceita pelo dono'

# 4. Não relançada
IFS='|' read -r R PD <<<"$(monta3 sf4naorelancada)"
prep "$R" "$PD" 'roda-suite.sh --gate-onda'
despacho_retorno "$PD/95-RUN-LOG.jsonl"
suite_tag "$R" gate-onda-1 2026-09-01T10:40:00-03:00 0
suite_tag "$R" gate-onda-2 2026-09-01T10:50:00-03:00 0
suite_tag "$R" suite       2026-09-01T11:00:00-03:00 0
commit_codigo "$R" src/x.py "fix: x" 2026-09-01T11:30:00-03:00
J="$(confere3 "$R")"
eq "não relançada: FALHA suite_nao_relancada" "$(codigos "$J")" '["suite_nao_relancada"]'
casa "…sha do commit no detalhe" \
     "$(printf '%s' "$J" | jq -r '.asserts[]|select(.id=="suite_nao_relancada")|.detalhe')" 'fix: x'

IFS='|' read -r R PD <<<"$(monta3 sf4so_planning)"
prep "$R" "$PD" 'roda-suite.sh --gate-onda'
despacho_retorno "$PD/95-RUN-LOG.jsonl"
suite_tag "$R" gate-onda-1 2026-09-01T10:40:00-03:00 0
suite_tag "$R" gate-onda-2 2026-09-01T10:50:00-03:00 0
suite_tag "$R" suite       2026-09-01T11:00:00-03:00 0
commit_codigo "$R" .planning/nota.md "docs(95): nota" 2026-09-01T11:30:00-03:00
J="$(confere3 "$R")"
eq "commit só em .planning/ depois da suíte → sem falha" "$(codigos "$J")" "[]"

# 5. Última onda sem gate
IFS='|' read -r R PD <<<"$(monta3 sf5semgate)"
prep "$R" "$PD" 'roda-suite.sh --gate-onda'
despacho_retorno "$PD/95-RUN-LOG.jsonl"
suite_tag "$R" gate-onda-1 2026-09-01T10:40:00-03:00 0
suite_tag "$R" suite       2026-09-01T11:00:00-03:00 0
J="$(confere3 "$R")"
eq "onda 2 (última) sem gate-onda-2: FALHA ultima_onda_sem_gate" "$(codigos "$J")" '["ultima_onda_sem_gate"]'

IFS='|' read -r R PD <<<"$(monta3 sf5semgateflag)"
prep "$R" "$PD" '-'
despacho_retorno "$PD/95-RUN-LOG.jsonl"
suite_tag "$R" gate-onda-1 2026-09-01T10:40:00-03:00 0
suite_tag "$R" suite       2026-09-01T11:00:00-03:00 0
J="$(confere3 "$R")"
eq "sem --gate-onda no test_command → sem ultima_onda_sem_gate" "$(codigos "$J")" "[]"

# 6. Em curso
IFS='|' read -r R PD <<<"$(monta3 sf6emcurso)"
prep "$R" "$PD" 'roda-suite.sh --gate-onda'
despacho_retorno "$PD/95-RUN-LOG.jsonl"
suite_tag "$R" gate-onda-1 2026-09-01T10:40:00-03:00 0
suite_tag "$R" gate-onda-2 2026-09-01T10:50:00-03:00 0
suite_tag "$R" suite       2026-09-01T11:00:00-03:00 -
J="$(confere3 "$R")"
eq "sem rc: FALHA suite_em_curso" "$(codigos "$J")" '["suite_em_curso"]'

# 7. Não instrumentado
IFS='|' read -r R PD <<<"$(monta3 sf7naoinstrumentado)"
prep "$R" "$PD" 'uv run pytest -q'
despacho_retorno "$PD/95-RUN-LOG.jsonl"
J="$(confere3 "$R")"
eq "sem gad-suite/ e test_command sem roda-suite.sh: aplica false" \
   "$(printf '%s' "$J" | jq -r '.extrai.suite_final.aplica')" "false"
eq "…nada reprova" "$(codigos "$J")" "[]"

echo "── suite-ressalva.sh ──"

# 8. suite-ressalva.sh
IFS='|' read -r R PD <<<"$(monta3 sf8ressalva)"
prep "$R" "$PD" '-'
printf -- '---\nphase: "95"\n---\nbody\n' > "$PD/95-VERIFICATION.md"
SAIDA="$(bash "$SR" "$PD" 95 "aceito pelo dono" 2>&1)"; RC=$?
eq "suite-ressalva.sh: exit 0" "$RC" "0"
eq "…retorna gravado:true" "$(printf '%s' "$SAIDA" | jq -r '.gravado')" "true"
eq "…uma linha suite_final: vermelha" "$(grep -c '^suite_final: vermelha$' "$PD/95-VERIFICATION.md")" "1"
eq "…uma linha suite_ressalva" "$(grep -c '^suite_ressalva: "aceito pelo dono"$' "$PD/95-VERIFICATION.md")" "1"
bash "$SR" "$PD" 95 "segunda tentativa" >/dev/null 2>&1
eq "…idempotente: continua UMA linha suite_final" "$(grep -c '^suite_final:' "$PD/95-VERIFICATION.md")" "1"
eq "…idempotente: continua UMA linha suite_ressalva" "$(grep -c '^suite_ressalva:' "$PD/95-VERIFICATION.md")" "1"

bash "$SR" "$PD" 96 "motivo" >/tmp/sf8-semver.txt 2>&1; RC=$?
eq "sem VERIFICATION (NN errado): exit 2" "$RC" "2"

echo "── contador de lançamentos filtrado pela fase (45f) ──"

# 11. lançamento anterior ao 1º despacho da etapa não conta
IFS='|' read -r R PD <<<"$(monta3 s11foradafase)"
prep "$R" "$PD" 'roda-suite.sh --gate-onda'
despacho_retorno "$PD/95-RUN-LOG.jsonl"          # 1º despacho: 2026-09-01T10:00:00-03:00
suite_tag "$R" gate-onda-7 2026-09-05T10:00:00-03:00 0   # bancada de OUTRA fase, DEPOIS
suite_tag "$R" velha       2026-08-20T09:00:00-03:00 0   # lançamento de fase anterior
suite_tag "$R" gate-onda-1 2026-09-01T10:40:00-03:00 0
J="$(confere3 "$R")"
eq "lancamentos conta só o desta etapa"  "$(printf '%s' "$J" | jq -r '.extrai.suite.lancamentos')" "2"
eq "fora_da_fase nomeia a tag velha"     "$(printf '%s' "$J" | jq -r '.extrai.suite.fora_da_fase|join(",")')" "velha"

echo "── colisão real entre planos da mesma onda (46t) ──"

# 9. dois planos da MESMA onda commitam o mesmo arquivo → colisao_real_onda
IFS='|' read -r R PD <<<"$(monta3 c9colisao)"
prep "$R" "$PD" '-'
commit_codigo "$R" src/hub.py 'feat(95-01): t1' 2026-09-01T10:05:00-03:00
commit_codigo "$R" src/hub.py 'feat(95-02): t1' 2026-09-01T10:06:00-03:00
J="$(confere3 "$R")"
eq "colisao_real_onda reprova"     "$(printf '%s' "$J" | jq -c '[.asserts[]?|select(.id=="colisao_real_onda")|.resultado]')" '["FALHA"]'
eq "…nomeia a onda e os dois planos" \
   "$(printf '%s' "$J" | jq -r '.extrai.colisao_real_onda[0]|"\(.onda)/\(.planos|join(","))/\(.arquivos|join(","))"')" \
   "1/95-01,95-02/src/hub.py"

# 10. planos de ONDAS diferentes no mesmo arquivo → não é colisão (as ondas são sequenciais)
IFS='|' read -r R PD <<<"$(monta3 c10ondas)"
prep "$R" "$PD" '-'
commit_codigo "$R" src/hub.py 'feat(95-01): t1' 2026-09-01T10:05:00-03:00
commit_codigo "$R" src/hub.py 'feat(95-03): t1' 2026-09-01T10:06:00-03:00
J="$(confere3 "$R")"
eq "ondas diferentes não colidem" "$(printf '%s' "$J" | jq -c '.extrai.colisao_real_onda')" '[]'

echo
echo "── resumo: $OK ok / $FALHAS falhas ──"
[ "$FALHAS" -eq 0 ]
