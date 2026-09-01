#!/usr/bin/env bash
# test-reconcilia-docs.sh — bancada do reconcilia-docs.sh, que até 31/08 não tinha teste
# nenhum. A régua vem do item B2 do PLANO-B (auditoria interina da F24.4):
#
#   O script reconciliava o STATE.md por um grep LITERAL (`^status: *executing`). Se o
#   `status` fosse uma frase em vez do token — formato real, medido no alencarOS:
#   `status: "Fase 13 … PAUSADA…"` — o grep não batia, o script não escrevia nada, saía 0,
#   e a cancela `confere-etapa.sh 6`, que usava o MESMO grep, dava verde. Os dois
#   compartilhavam o ponto cego, e "roda, passa com o STATE.md errado" era garantido.
#
# O que esta bancada afirma:
#   a) status: executing + current_phase batendo → reconcilia e os campos mudam
#   b) status como frase entre aspas          → FORMATO-INESPERADO e exit ≠ 0
#   c) current_phase divergente               → pend com os DOIS valores, exit 0
#   d) state_head presente                    → atualizado para o HEAD do repo do projeto
#   e) state_head ausente                     → NÃO criado, mas registrado em pendentes
#
# Tudo em projeto de bancada (mktemp): nenhum projeto real é tocado.
#   bash tests/test-reconcilia-docs.sh      · exit 0 = verde
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/reconcilia-docs.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-recdocs-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

# monta_projeto <nome> <valor do campo status> <valor do current_phase> <state_head:sim|nao>
#   Ecoa a raiz do projeto. O repositório nasce COM um commit — sem ele `git rev-parse
#   HEAD` falha e o caso do state_head reprovaria pelo motivo errado.
monta_projeto() {
  local nome="$1" st="$2" cp="$3" sh="$4"
  local root="$TMP/$nome"
  mkdir -p "$root/.planning/phases/24.4-bancada"
  : > "$root/.planning/phases/24.4-bancada/24.4-01-PLAN.md"
  {
    echo '---'
    echo 'gsd_state_version: 1.0'
    echo "current_phase: $cp"
    echo "status: $st"
    echo 'stopped_at: Phase 24.4 executing'
    echo 'last_updated: "2026-08-01T00:00:00.000Z"'
    echo 'last_activity: 2026-08-01'
    echo 'last_activity_desc: Phase 24.4 executing'
    [ "$sh" = sim ] && echo 'state_head: 0000000000000000000000000000000000000000'
    echo 'progress:'
    echo '  total_phases: 11'
    echo '  completed_phases: 8'
    echo '  total_plans: 69'
    echo '  completed_plans: 68'
    echo '  percent: 72'
    echo '---'
    echo
    echo '## Current Position'
    echo 'Phase: 24.4 — EXECUTING'
    echo 'Status: Executing Phase 24.4'
  } > "$root/.planning/STATE.md"
  printf -- '- [ ] **Phase 24.4: bancada**\n' > "$root/.planning/ROADMAP.md"
  git init -q "$root" >/dev/null 2>&1
  git -C "$root" -c user.email=b@b -c user.name=b commit -q --allow-empty -m base >/dev/null 2>&1
  printf '%s' "$root"
}
roda() { # <root> → grava saída em $SAIDA e código em $RC
  SAIDA=$(bash "$SCRIPT" --fase 24.4 --projeto "$1" 2>&1); RC=$?
}
campo() { grep -m1 -E "^$2:" "$1/.planning/STATE.md" | sed "s/^$2:[[:space:]]*//"; }

echo "== (a) status: executing + fase batendo → reconcilia"
R=$(monta_projeto a executing 24.4 sim); roda "$R"
[ "$RC" = 0 ] && ok "exit 0" || erro "esperado exit 0, veio $RC" "$SAIDA"
[ "$(campo "$R" status)" = between_phases ] \
  && ok "status executing → between_phases" || erro "status não mudou: $(campo "$R" status)"
printf '%s' "$SAIDA" | tail -1 | grep -q 'executing → between_phases' \
  && ok "a ação sai no JSON" || erro "ação ausente do JSON" "$SAIDA"
grep -q '^Status: Between phases' "$R/.planning/STATE.md" \
  && ok "o corpo 'Current Position' também foi reconciliado" || erro "corpo não tocado"

echo "== (d) state_head presente → atualizado para o HEAD do repo do PROJETO"
HEAD_REAL=$(git -C "$R" rev-parse HEAD)
[ "$(campo "$R" state_head)" = "$HEAD_REAL" ] \
  && ok "state_head = $(printf '%s' "$HEAD_REAL" | cut -c1-12)" \
  || erro "state_head não virou o HEAD" "obtido: $(campo "$R" state_head) / esperado: $HEAD_REAL"

echo "== (e) state_head ausente → NÃO criado, mas registrado em pendentes"
R=$(monta_projeto e executing 24.4 nao); roda "$R"
grep -q '^state_head:' "$R/.planning/STATE.md" \
  && erro "o script INVENTOU o campo state_head (proibido em artefato do GSD)" \
  || ok "campo ausente continua ausente"
printf '%s' "$SAIDA" | tail -1 | grep -q 'state_head ausente' \
  && ok "a ausência vira pendência declarada" || erro "ausência silenciosa" "$SAIDA"

echo "== (b) status como FRASE entre aspas → FORMATO-INESPERADO + exit ≠ 0"
# Formato real, copiado do alencarOS: é o que engana reconciliador e cancela ao mesmo tempo.
R=$(monta_projeto b '"Fase 24.4 EM EXECUÇÃO → PAUSADA (2026-08-31) — waves 1-2 concluídas"' 24.4 sim)
roda "$R"
[ "$RC" != 0 ] && ok "exit $RC (≠ 0) — deixou de passar em silêncio" \
  || erro "frase entre aspas ainda passa com exit 0" "$SAIDA"
printf '%s' "$SAIDA" | grep -q 'FORMATO-INESPERADO: status não é um token reconhecível' \
  && ok "diz FORMATO-INESPERADO com o valor encontrado" || erro "sem a mensagem" "$SAIDA"
grep -q '^status: "Fase 24.4' "$R/.planning/STATE.md" \
  && ok "e NÃO reescreveu o campo que não sabe interpretar" || erro "mexeu no status ilegível"

echo "== (c) current_phase divergente → pend com os dois valores, exit 0"
R=$(monta_projeto c executing 23 sim); roda "$R"
[ "$RC" = 0 ] && ok "exit 0 (não é erro de formato: é fase errada)" || erro "esperado 0, veio $RC" "$SAIDA"
J=$(printf '%s' "$SAIDA" | tail -1)
printf '%s' "$J" | grep -q "esperado '24.4'" && printf '%s' "$J" | grep -q "encontrado '23'" \
  && ok "a pendência traz o esperado E o encontrado (banner acionável)" || erro "pendência genérica" "$J"
[ "$(campo "$R" status)" = executing ] \
  && ok "e o STATE.md de outra fase não foi tocado" || erro "tocou STATE.md de fase alheia"

echo "== idempotência: status já between_phases → nada a fazer, exit 0"
R=$(monta_projeto i between_phases 24.4 sim); roda "$R"
[ "$RC" = 0 ] && ok "exit 0" || erro "esperado 0, veio $RC" "$SAIDA"
printf '%s' "$SAIDA" | tail -1 | grep -q 'FORMATO-INESPERADO' \
  && erro "token válido acusado como formato inesperado" "$SAIDA" \
  || ok "token reconhecido não vira FORMATO-INESPERADO"

echo
[ "$falhas" -eq 0 ] && echo "test-reconcilia-docs: TUDO OK" || echo "test-reconcilia-docs: $falhas falha(s)"
[ "$falhas" -eq 0 ]
