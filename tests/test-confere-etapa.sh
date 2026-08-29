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

echo "--------------------------------------------------"
echo "test-confere-etapa.sh: $OK ok / $FALHAS falha(s)"
[ "$FALHAS" -eq 0 ]
