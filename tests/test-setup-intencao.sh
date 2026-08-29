#!/usr/bin/env bash
# test-setup-intencao.sh — bancada do setup-intencao.sh na v2.2.0:
#   §0.5 rota do PRE-SPEC (fail-closed + estado durável em pre-spec-route.json)
#   R2   confere-pre-spec.sh <SPEC> <PRE-SPEC> embutido no retorno
#   R6   goal_roadmap + issues estruturadas (missing_requirement / phase_without_req_id)
#   T3   salvaguarda do blob-base em `entrada: revisao`
#
# Tudo em bancada ISOLADA (mktemp): nenhum projeto real é lido ou escrito. As fixtures do
# PRE-SPEC/SPEC são as mesmas do test-confere-pre-spec.sh (fase 99, sem PII).
#   bash tests/test-setup-intencao.sh      · exit 0 = verde
set -u

RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
S="$RAIZ/skills/go-and-do/scripts/setup-intencao.sh"
FS="$RAIZ/tests/fixtures/setup"
FP="$RAIZ/tests/fixtures/pre-spec"

OK=0; FALHAS=0
ok()    { OK=$((OK+1)); printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }
casa()  { if printf '%s' "$2" | grep -qE "$3"; then ok "$1"; else falha "$1" "não casou /$3/ em: $(printf '%s' "$2" | head -c 200)"; fi; }
nao_casa() { if printf '%s' "$2" | grep -qE "$3"; then falha "$1" "casou /$3/ e não devia"; else ok "$1"; fi; }

BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT

monta_proj() { # <nome> → ecoa a raiz (repo git, com ROADMAP/REQUIREMENTS da fixture)
  local root="$BASE/$1"
  mkdir -p "$root/.planning/phases"
  cp "$FS/ROADMAP.md" "$FS/REQUIREMENTS.md" "$root/.planning/"
  git init -q "$root" >/dev/null 2>&1
  printf '%s' "$root"
}
monta_fase() { # <root> <NN> → ecoa o phase_dir
  local pd="$1/.planning/phases/$2-bancada"; mkdir -p "$pd"; printf '%s' "$pd"
}
roda() { # <phase_dir> <NN> [flags...] → ecoa o JSON (última linha do stdout)
  local pd="$1" nn="$2"; shift 2
  bash "$S" "$pd" "$nn" "$@" 2>/dev/null | tail -1
}
campo() { printf '%s' "$1" | jq -r "$2" 2>/dev/null || printf '<json-invalido>'; }

# ═══════════════════════════════════════════════════ §0.5 — rota do PRE-SPEC
echo "── §0.5: rota do PRE-SPEC (fail-closed) ──"
R="$(monta_proj p05)"; PD="$(monta_fase "$R" 99)"

J="$(roda "$PD" 99)"
eq "sem PRE-SPEC → pre_spec_bloco: nao_aplicavel"   "$(campo "$J" .pre_spec_bloco)" "nao_aplicavel"
eq "sem PRE-SPEC → pre_spec_mode explícito (null)"  "$(campo "$J" .pre_spec_mode)"  "null"
eq "sem PRE-SPEC → sem needs_decision"              "$(campo "$J" .needs_decision)" "null"
eq "entrada: spec (não há SPEC no disco)"           "$(campo "$J" .entrada)"        "spec"

cp "$FP/sem-bloco-PRE-SPEC.md" "$PD/99-PRE-SPEC.md"
J="$(roda "$PD" 99)"
eq "PRE-SPEC sem bloco → pre_spec_bloco: ausente"   "$(campo "$J" .pre_spec_bloco)" "ausente"
eq "PRE-SPEC sem bloco → pre_spec_mode null (nunca defaulta)" "$(campo "$J" .pre_spec_mode)" "null"
casa "needs_decision traz as DUAS saídas do plano" "$(campo "$J" .needs_decision.texto)" \
     'pre-spec-migra\.py.*(OU|ou) autorizar a rota antiga'
casa "needs_decision cita o sino da rota antiga" "$(campo "$J" .needs_decision.texto)" 'pre_spec_sem_bloco'
eq "sem rota gravada ainda → rota: ausente"        "$(campo "$J" .pre_spec_rota.estado)" "ausente"

J="$(roda "$PD" 99 --pre-spec-route legacy --resposta "ok, roda pela rota antiga")"
eq "dono autoriza legacy → pre_spec_mode: legacy"  "$(campo "$J" .pre_spec_mode)" "legacy"
eq "legacy → sino obrigatório aceso"               "$(campo "$J" .sino_pre_spec_sem_bloco)" "true"
eq "legacy → a pergunta não volta"                 "$(campo "$J" .needs_decision)" "null"
eq "route.json gravado com a resposta do dono" \
   "$(jq -r '.mode + "|" + .resposta_dono' "$PD/.intent/pre-spec-route.json")" \
   "legacy|ok, roda pela rota antiga"

J="$(roda "$PD" 99)"
eq "chegada seguinte relê a rota do disco"          "$(campo "$J" .pre_spec_mode)" "legacy"
eq "rota relida é declarada válida"                 "$(campo "$J" .pre_spec_rota.estado)" "valida"

printf '\n<!-- o dono editou o PRE-SPEC -->\n' >> "$PD/99-PRE-SPEC.md"
J="$(roda "$PD" 99)"
eq "PRE-SPEC mudou → rota invalidada pelo hash"     "$(campo "$J" .pre_spec_rota.estado)" "invalidada_por_hash"
eq "rota invalidada → pre_spec_mode volta a null"   "$(campo "$J" .pre_spec_mode)" "null"
casa "rota invalidada → a pergunta volta ao dono"   "$(campo "$J" .needs_decision.motivo)" 'invalidada_por_hash'

cp "$FP/ok-PRE-SPEC.md" "$PD/99-PRE-SPEC.md"
J="$(roda "$PD" 99)"
eq "bloco válido → pre_spec_bloco: ok"              "$(campo "$J" .pre_spec_bloco)" "ok"
eq "bloco válido → pre_spec_mode: structured"       "$(campo "$J" .pre_spec_mode)" "structured"
eq "bloco válido → sino da rota antiga apagado"     "$(campo "$J" .sino_pre_spec_sem_bloco)" "false"
eq "bloco válido → rota estruturada persistida"     "$(jq -r .mode "$PD/.intent/pre-spec-route.json")" "structured"

bash "$S" "$PD" 99 --pre-spec-route legacy >/dev/null 2>&1
eq "--pre-spec-route sem --resposta → exit 2 (a rota é decisão do dono)" "$?" "2"

# ═══════════════════════════════════════════════════════════════════ R2
echo "── R2: SPEC × PRE-SPEC ──"
R="$(monta_proj r2)"; PD="$(monta_fase "$R" 99)"
cp "$FP/ok-PRE-SPEC.md" "$PD/99-PRE-SPEC.md"
J="$(roda "$PD" 99)"
eq "sem SPEC ainda → r2: nao_aplicavel (chave sempre presente)" "$(campo "$J" .r2.status)" "nao_aplicavel"

cp "$FP/ok-SPEC.md" "$PD/99-SPEC.md"
J="$(roda "$PD" 99)"
eq "SPEC conforme → r2.status ok"                   "$(campo "$J" .r2.status)" "ok"
casa "EXTENSAO-SUSPEITA sai como AVISO (vai ao briefing)" "$(campo "$J" '.r2.avisos|join("|")')" 'EXTENSAO-SUSPEITA'
eq "aviso não vira falha"                           "$(campo "$J" '.r2.falhas|length')" "0"

cp "$FP/ruim-SPEC.md" "$PD/99-SPEC.md"
J="$(roda "$PD" 99)"
eq "SPEC ruim → r2.status falha"                    "$(campo "$J" .r2.status)" "falha"
casa "(a) MARCA-SEM-ID listada"                     "$(campo "$J" '.r2.falhas|join("|")')" 'MARCA-SEM-ID'
casa "(b) ID-INEXISTENTE listada"                   "$(campo "$J" '.r2.falhas|join("|")')" 'ID-INEXISTENTE'

# ═══════════════════════════════════════════════════════════════════ R6
echo "── R6: goal_roadmap + issues estruturadas ──"
R="$(monta_proj r6)"
J="$(roda "$(monta_fase "$R" 99)" 99)"
casa "Goal da entrada 99 extraído"                  "$(campo "$J" .goal_roadmap)" 'grão responsável-mês'
eq "entrada saudável → nenhuma issue"               "$(campo "$J" '.issues|length')" "0"
eq "ids lidos SÓ da linha **Requirements**"         "$(campo "$J" '.r6.req_ids|join(",")')" "BANC-01,BANC-02"
nao_casa "id citado em prosa (FALTA-01/CANC-02) não vira issue" "$(campo "$J" '.issues|tostring')" 'FALTA-01|CANC-02'

J="$(roda "$(monta_fase "$R" 98)" 98)"
eq "linha 'TBD (derivar na spec)' → phase_without_req_id" \
   "$(campo "$J" '[.issues[].tipo]|join(",")')" "phase_without_req_id"

J="$(roda "$(monta_fase "$R" 96)" 96)"
eq "entrada sem linha **Requirements** → phase_without_req_id" \
   "$(campo "$J" '[.issues[].tipo]|join(",")')" "phase_without_req_id"

J="$(roda "$(monta_fase "$R" 97)" 97)"
eq "id ausente do REQUIREMENTS → 1 missing_requirement" \
   "$(campo "$J" '[.issues[]|select(.tipo=="missing_requirement")|.id]|join(",")')" "FALTA-01"
nao_casa "o id que EXISTE não é acusado" "$(campo "$J" '.issues|tostring')" 'BANC-01'

J="$(roda "$(monta_fase "$R" 24)" 24)"
casa "'Phase 24' não casa com a entrada da 'Phase 24.3'" "$(campo "$J" .goal_roadmap)" 'Entrada-armadilha do lookahead'
J="$(roda "$(monta_fase "$R" 24.3)" 24.3)"
casa "'Phase 24.3' casa a entrada certa" "$(campo "$J" .goal_roadmap)" 'seu próprio responsável'

J="$(roda "$(monta_fase "$R" 95)" 95)"
casa "Goal quebrado em 2 linhas é lido inteiro" "$(campo "$J" .goal_roadmap)" 'quebra no meio; segunda linha'
eq "D-11/D-q90-05 (prefixo de 1 letra) e PRE-SPEC (sem dígito no fim) não são requisitos" \
   "$(campo "$J" '.r6.req_ids|join(",")')" "BANC-01"
eq "…e por isso nenhuma issue nasce dela" "$(campo "$J" '.issues|length')" "0"

PD_R6="$(monta_fase "$R" 97b)"   # phase_dir virgem: prova que o --r6 não tem efeito colateral
J="$(bash "$S" --r6 "$(monta_fase "$R" 97)" 97 2>/dev/null | tail -1)"
eq "--r6 devolve as mesmas issues sem tocar o disco" \
   "$(campo "$J" '[.issues[].tipo]|join(",")')" "missing_requirement"
bash "$S" --r6 "$PD_R6" 97 >/dev/null 2>&1
[ -d "$PD_R6/.intent" ] \
  && falha "--r6 não pode criar .intent/" "criou" || ok "--r6 não cria .intent/ (sem efeito colateral)"

# ═══════════════════════════════════════════════════════════════════ T3
echo "── T3: salvaguarda do blob-base ──"
R="$(monta_proj t3)"; PD="$(monta_fase "$R" 99)"
printf '# SPEC da bancada\n'    > "$PD/99-SPEC.md"
printf '# CONTEXT da bancada\n' > "$PD/99-CONTEXT.md"   # SPEC+CONTEXT ⇒ entrada: revisao
mkdir -p "$PD/.intent"
git -C "$R" hash-object -- "$PD/99-SPEC.md" > "$PD/.intent/.gerado-SPEC.txt"

J="$(roda "$PD" 99)"
eq "entrada: revisao"                        "$(campo "$J" .entrada)" "revisao"
eq "SPEC intacto desde a geração → base gravada" \
   "$(campo "$J" '.t3[]|select(.artefato=="SPEC")|.status')" "gravado"
eq "a base gravada bate com o hash do artefato" \
   "$(cat "$PD/.intent/.base-SPEC.txt")" "$(git -C "$R" hash-object -- "$PD/99-SPEC.md")"
eq "blob existe de verdade no object-db" \
   "$(git -C "$R" cat-file -t "$(cat "$PD/.intent/.base-SPEC.txt")")" "blob"
eq "CONTEXT sem marcador .gerado-* → nao_medido" \
   "$(campo "$J" '.t3[]|select(.artefato=="CONTEXT")|.status')" "nao_medido"
casa "e o motivo é declarado, não chutado" \
   "$(campo "$J" '.t3[]|select(.artefato=="CONTEXT")|.motivo')" 'sem marcador \.gerado-CONTEXT'

J="$(roda "$PD" 99)"
eq "2ª chegada → base já existe, não reconstrói" \
   "$(campo "$J" '.t3[]|select(.artefato=="SPEC")|.status')" "ja_existe"

R="$(monta_proj t3b)"; PD="$(monta_fase "$R" 99)"
printf '# SPEC da bancada\n'    > "$PD/99-SPEC.md"
printf '# CONTEXT da bancada\n' > "$PD/99-CONTEXT.md"
mkdir -p "$PD/.intent"
git -C "$R" hash-object -- "$PD/99-SPEC.md" > "$PD/.intent/.gerado-SPEC.txt"
: > "$PD/.intent/.done-c1-codex"
J="$(roda "$PD" 99)"
eq "marcador de ciclo no disco → NÃO reconstrói (nao_medido)" \
   "$(campo "$J" '.t3[]|select(.artefato=="SPEC")|.status')" "nao_medido"
casa "motivo cita o marcador encontrado" \
   "$(campo "$J" '.t3[]|select(.artefato=="SPEC")|.motivo')" '\.done-c1-codex'
[ -f "$PD/.intent/.base-SPEC.txt" ] && falha "não podia ter gravado a base" "gravou" \
  || ok "nenhuma base gravada quando a revisão já começou"

R="$(monta_proj t3c)"; PD="$(monta_fase "$R" 99)"
printf '# SPEC da bancada\n'    > "$PD/99-SPEC.md"
printf '# CONTEXT da bancada\n' > "$PD/99-CONTEXT.md"
mkdir -p "$PD/.intent"; echo "0000000000000000000000000000000000000000" > "$PD/.intent/.gerado-SPEC.txt"
J="$(roda "$PD" 99)"
eq "artefato mudou desde a geração → nao_medido" \
   "$(campo "$J" '.t3[]|select(.artefato=="SPEC")|.status')" "nao_medido"
casa "motivo declara a divergência de hash" \
   "$(campo "$J" '.t3[]|select(.artefato=="SPEC")|.motivo')" 'mudou desde a geração'

echo "--------------------------------------------------"
echo "test-setup-intencao.sh: $OK ok / $FALHAS falha(s)"
[ "$FALHAS" -eq 0 ]
