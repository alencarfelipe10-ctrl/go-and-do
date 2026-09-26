#!/usr/bin/env bash
# test-numeros-da-fase.sh — bancada do numeros-da-fase.sh (46b, 46q, 47f).
#
# Cobre: o bloco estrutural, o `--conferir` (incluindo `CONTAGEM-x-ENUMERACAO`, 46b) e o modo
# `--executores` (46q/47f) nos seus caminhos de insumo ausente. O modo `--executores` lê
# transcripts de `~/.claude/projects/`; a bancada não fabrica transcripts reais — ela garante que
# a ausência sai como mensagem explícita e exit 0, nunca como zero com cara de medição.
#   bash tests/test-numeros-da-fase.sh      · exit 0 = verde
set -u
RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
S="$RAIZ/skills/go-and-do/scripts/numeros-da-fase.sh"
OK=0; FALHAS=0
ok()    { OK=$((OK+1)); printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }
casa()  { if printf '%s' "$2" | grep -qE "$3"; then ok "$1"; else falha "$1" "não casou /$3/ em: $(printf '%s' "$2" | head -c 200)"; fi; }

BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT
PD="$BASE/proj/.planning/phases/95-bancada"; mkdir -p "$PD"
git init -q "$BASE/proj"
plano() { printf -- '---\nphase: "95"\nplan: %s\nwave: %s\n---\n<tasks>\n</tasks>\n' "$1" "$2" > "$PD/95-$1-PLAN.md"; }
plano 01 1; plano 02 1; plano 03 2
: > "$PD/95-01-SUMMARY.md"

echo "── bloco estrutural ──"
OUT="$(bash "$S" "$PD" 95 2>&1)"
casa "planos_total = 3"         "$OUT" 'planos_total \(PLAN.md no disco\): 3'
casa "planos_com_summary = 1"   "$OUT" 'planos_com_summary: 1'
casa "ondas_distintas = 2"      "$OUT" 'ondas_distintas \(frontmatter wave\): 2'

echo "── FJ-01ENC: radiografia dos gates ──"
# sem artefato nenhum: a radiografia diz o que FALTA, nunca inventa «nenhum achado»
casa "sem REVIEW → nomeia a ausência"  "$OUT" 'code_review_fonte: nenhum 95-REVIEW'
cat > "$PD/95-REVIEW.md" <<'EOF'
---
findings:
  critical: 0
  warning: 2
  info: 3
status: issues_found
---
## Warnings
### WR-01: algo
### WR-02: outra coisa
EOF
cat > "$PD/95-REVIEW-FIX.iter3.md" <<'EOF'
---
iteration: 3
fixed: 1
skipped: 2
status: all_fixed
---
## Fechados
### WR-01 — consertado
## Deixados ABERTOS e declarados
- **WR-02** (processo) — fora deste conserto.
- **IN-07** — informativo, segue para a próxima fase.
EOF
cat > "$PD/95-SECURITY.md" <<'EOF'
---
status: verified
threats_open: 1
---
## Accepted Risks Log
| Risk | Threat | Justificativa |
|---|---|---|
| R-95-A | T-95-A | aceito em tempo de plano |
EOF
printf -- '---\nstatus: validated\nnyquist_compliant: true\n---\n' > "$PD/95-VALIDATION.md"
OUT="$(bash "$S" "$PD" 95 2>&1)"
casa "lê o arquivo de MAIOR iteração, não o 95-REVIEW.md" "$OUT" 'code_review_fonte: 95-REVIEW-FIX.iter3.md \(iteração 3\)'
casa "IDs abertos saem nomeados"                          "$OUT" 'code_review_ids_abertos \(2\): WR-02 IN-07'
casa "…e declara de onde saíram"                          "$OUT" 'abertos_fonte: Deixados ABERTOS'
casa "ameaças abertas do SECURITY"                        "$OUT" 'threats_open: 1'
casa "risco aceito pela tabela (não pelo cabeçalho)"       "$OUT" 'security_riscos_aceitos \(1\): R-95-A'
casa "veredito da validação"                              "$OUT" 'validacao: status=validated'
casa "sem UAT → nomeia a ausência"                        "$OUT" 'uat_placar: sem 95-UAT.md'

echo "── FJ-02INT: dívida da ressalva na radiografia ──"
if printf '%s' "$OUT" | grep -q 'intent_ressalva_dividas'; then
  falha "sem intent_review: aprovado_com_ressalva → linha ausente" "apareceu sem gatilho"
else
  ok "sem intent_review: aprovado_com_ressalva → linha ausente"
fi
cat > "$PD/95-INTENT-REVIEW.md" <<'EOF'
---
intent_review: aprovado_com_ressalva
---

## Dívidas registradas

| id | alegação | evidência | dono | destino |
|----|----------|-----------|------|---------|
| c1-09 | achado | ev | Amplify | plan-phase |
EOF
OUT_RES="$(bash "$S" "$PD" 95 2>&1)"
casa "ressalva → nomeia a dívida c1-09"                    "$OUT_RES" 'intent_ressalva_dividas \(1\): c1-09'
rm -f "$PD/95-INTENT-REVIEW.md"

echo "── --conferir: N planos/ondas ──"
printf '# R\n\nForam 3 planos em 2 ondas.\n' > "$BASE/bom.md"
bash "$S" "$PD" 95 --conferir "$BASE/bom.md" >/dev/null 2>&1
eq "documento coerente → exit 0" "$?" "0"
printf '# R\n\nForam 7 planos.\n' > "$BASE/ruim.md"
OUT="$(bash "$S" "$PD" 95 --conferir "$BASE/ruim.md" 2>&1)"; RC=$?
eq "documento divergente → exit 1" "$RC" "1"
casa "…nomeia a divergência"       "$OUT" 'DIVERGÊNCIA'

echo "── --conferir: CONTAGEM-x-ENUMERACAO (46b) ──"
cat > "$BASE/enum.md" <<'EOF'
# R

## Eleva

Composição das 8 linhas:

- a
- b
- c
- d
- e
- f
- g
EOF
OUT="$(bash "$S" "$PD" 95 --conferir "$BASE/enum.md" 2>&1)"; RC=$?
eq "8 anunciadas × 7 enumeradas → exit 1" "$RC" "1"
casa "…imprime o código e os dois números" "$OUT" 'CONTAGEM-x-ENUMERACAO .*«8 linhas» × 7 item'
# corrigido: 8 itens → silêncio
printf -- '- h\n' >> "$BASE/enum.md"
OUT="$(bash "$S" "$PD" 95 --conferir "$BASE/enum.md" 2>&1)"
eq "8 × 8 → sem acusação" "$(printf '%s' "$OUT" | grep -c CONTAGEM-x-ENUMERACAO)" "0"
# número solto em prosa, sem lista logo abaixo → não acusa (o escopo é a lista que a frase introduz)
printf '# R\n\nO relatório tem 8 linhas no total e nada mais.\n\n- a\n- b\n' > "$BASE/prosa.md"
OUT="$(bash "$S" "$PD" 95 --conferir "$BASE/prosa.md" 2>&1)"
eq "número em prosa sem dois-pontos → sem acusação" "$(printf '%s' "$OUT" | grep -c CONTAGEM-x-ENUMERACAO)" "0"

echo "── FJ-02ENC: sobras desejáveis (por código) + «como desfazer» das decisões ──"
cat > "$PD/95-VERIFICATION.md" <<'EOF'
## Desejáveis pendentes

AC-08, AC-10 e AC-12 seguem pendentes no Windows real (plano 95-06).
EOF
cat > "$PD/95-DECISOES.md" <<'EOF'
## Decisões automáticas da Etapa 3

- `[auto]` baseRef: aplicado.
  Desfazer: remover a chave X.
EOF
printf -- '---\ngo_and_do_resumo: final\n---\n\nForam 3 planos em 2 ondas.\n' > "$PD/95-RESUMO-EXECUTIVO.md"
OUT="$(bash "$S" "$PD" 95 --conferir "$PD/95-RESUMO-EXECUTIVO.md" 2>&1)"; RC=$?
eq "AC pendente + Desfazer ausentes → exit 1" "$RC" "1"
casa "…nomeia AC-08"             "$OUT" 'SOBRA-AUSENTE: AC-08'
casa "…nomeia AC-10"             "$OUT" 'SOBRA-AUSENTE: AC-10'
casa "…nomeia AC-12"             "$OUT" 'SOBRA-AUSENTE: AC-12'
casa "…nomeia o desfazer ausente" "$OUT" 'DESFAZER-AUSENTE'
printf 'Sobras: AC-08, AC-10, AC-12 (plano 95-06). Como desfazer: remova a chave X.\n' >> "$PD/95-RESUMO-EXECUTIVO.md"
OUT="$(bash "$S" "$PD" 95 --conferir "$PD/95-RESUMO-EXECUTIVO.md" 2>&1)"
eq "citado por código + desfazer → sem SOBRA-AUSENTE"    "$(printf '%s' "$OUT" | grep -c SOBRA-AUSENTE)"    "0"
eq "citado por código + desfazer → sem DESFAZER-AUSENTE" "$(printf '%s' "$OUT" | grep -c DESFAZER-AUSENTE)" "0"
# «Nenhum desejável pendente»: os AC citados na prosa (já atendidos) não disparam a régua
cat > "$PD/95-VERIFICATION.md" <<'EOF'
## Desejáveis pendentes

Nenhum desejável pendente. AC-06 e AC-14 seguem com teste nomeado.
EOF
OUT="$(bash "$S" "$PD" 95 --conferir "$PD/95-RESUMO-EXECUTIVO.md" 2>&1)"
eq "Nenhum desejável pendente → sem SOBRA-AUSENTE" "$(printf '%s' "$OUT" | grep -c SOBRA-AUSENTE)" "0"
# alvo que NÃO é o resumo (mesma bancada 46b) não entra nesta régua nova, mesmo com as
# mesmas pendências no disco
rm -f "$PD/95-RESUMO-EXECUTIVO.md"
cat > "$PD/95-VERIFICATION.md" <<'EOF'
## Desejáveis pendentes

AC-08 segue pendente (plano 95-06).
EOF
OUT="$(bash "$S" "$PD" 95 --conferir "$BASE/bom.md" 2>&1)"
eq "alvo não é *-RESUMO-EXECUTIVO.md → régua nova não roda" "$(printf '%s' "$OUT" | grep -c 'SOBRA-AUSENTE\|DESFAZER-AUSENTE')" "0"
rm -f "$PD/95-VERIFICATION.md" "$PD/95-DECISOES.md"

echo "── --executores: insumo ausente ──"
OUT="$(HOME="$BASE/semhome" bash "$S" "$PD" 95 --executores 2>&1)"; RC=$?
eq "sem ~/.claude/projects do projeto → exit 0" "$RC" "0"
casa "…diz medição primária indisponível, nunca zero" "$OUT" 'medição primária indisponível'
mkdir -p "$BASE/fakehome/.claude/projects/$(printf '%s' "$BASE/proj" | sed 's#/#-#g')/sess-aaa/subagents"
OUT="$(HOME="$BASE/fakehome" bash "$S" "$PD" 95 --executores 2>&1)"; RC=$?
eq "subagents/ vazio → exit 0"          "$RC" "0"
casa "…cabeçalho da medição primária"   "$OUT" 'medição primária'
casa "…simultaneos_max_primario: 0"     "$OUT" 'simultaneos_max_primario: 0 \(de 0 executores\)'

echo
echo "── resumo: $OK ok / $FALHAS falhas ──"
[ "$FALHAS" -eq 0 ]
