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
#   f–k) modo --pausa (P17): STATE.md escrito por último, apontando o commit WIP; um
#        commit próprio; `discrepancia_commits`; dry-run sem escrita; idempotente;
#        state_head desconhecido; frase → exit 3; `confere-etapa.sh pausa --pos-pausa`.
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
    echo 'Last activity: 2026-08-01 — Plano 24.4-08 concluído'
    echo 'Last Activity Description: Plano 24.4-08 concluído'
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

# ── modo --pausa (P17) ────────────────────────────────────────────────────────
CONFERE="$AQUI/../skills/go-and-do/scripts/confere-etapa.sh"
# monta_pausa <nome> <status> <sim|desconhecido>: projeto com o state_head apontando o
#   commit base (ou um sha inexistente), HANDOFF.json da fase e 5 commits depois (docs +
#   3 de tarefa + o WIP do pause-work) — é o "5 atrás" da F24.4 em miniatura. O corpo
#   tem Last activity/Last Activity Description como o STATE.md real, mas não "Stopped
#   at" — exercita o sed de reserva do stopped_at.
monta_pausa() {
  local root; root=$(monta_projeto "$1" "$2" 24.4 sim)   # sempre com state_head (o real tem)
  git -C "$root" config user.email b@b; git -C "$root" config user.name b
  [ "$3" = desconhecido ] || sed -i "s/^state_head: .*/state_head: $(git -C "$root" rev-parse HEAD)/" "$root/.planning/STATE.md"
  git -C "$root" add -A; git -C "$root" commit -qm "docs: state_head aponta o base" >/dev/null 2>&1
  for i in 1 2 3; do git -C "$root" commit -q --allow-empty -m "feat(24.4-10): tarefa $i" >/dev/null 2>&1; done
  printf '{"version":"1.0","phase":"24.4","plan":10,"task":2,"total_tasks":3,"status":"paused"}\n' > "$root/.planning/HANDOFF.json"
  git -C "$root" add .planning/HANDOFF.json; git -C "$root" commit -qm "wip: fase 24.4 pausada no plano 10 task 2/3" >/dev/null 2>&1
  printf '%s' "$root"
}
roda_pausa() { SAIDA=$(bash "$SCRIPT" --fase 24.4 --projeto "$1" --pausa "${@:2}" 2>&1); RC=$?; J=$(printf '%s' "$SAIDA" | tail -1); }

echo "== (g) --pausa --dry-run → relata a discrepância, não escreve, não commita"
R=$(monta_pausa g executing sim); WIP=$(git -C "$R" rev-parse HEAD); roda_pausa "$R" --dry-run
[ "$RC" = 0 ] && ok "exit 0" || erro "esperado 0, veio $RC" "$SAIDA"
[ "$(jq -r .discrepancia_commits <<<"$J")" = 5 ] && ok "discrepancia_commits: 5" || erro "discrepância errada" "$J"
[ "$(campo "$R" status)" = executing ] && ok "status não tocado" || erro "dry-run escreveu"
[ "$(git -C "$R" rev-parse HEAD)" = "$WIP" ] && [ -z "$(git -C "$R" status --porcelain)" ] \
  && ok "sem commit e árvore limpa" || erro "dry-run commitou ou sujou a árvore"

echo "== (k) confere-etapa.sh pausa --pos-pausa ANTES do reconcilia → fail"
CE=$(bash "$CONFERE" pausa --pos-pausa --fase 24.4 --projeto "$R" 2>&1); CRC=$?
[ "$CRC" = 1 ] && printf '%s' "$CE" | tail -1 | grep -q '"veredito":"fail"' \
  && ok "fail: status executing e state_head atrás" || erro "esperado fail/exit 1, veio $CRC" "$CE"

echo "== (f) --pausa → paused, state_head = WIP, um commit próprio, discrepância 5"
roda_pausa "$R"
[ "$RC" = 0 ] && ok "exit 0" || erro "esperado 0, veio $RC" "$SAIDA"
[ "$(campo "$R" status)" = paused ] && ok "status executing → paused" || erro "status: $(campo "$R" status)"
[ "$(campo "$R" state_head)" = "$WIP" ] && ok "state_head = commit WIP ($(cut -c1-12 <<<"$WIP"))" \
  || erro "state_head não é o WIP" "obtido $(campo "$R" state_head)"
[ "$(git -C "$R" log -1 --format=%s)" = "docs(state): STATE.md reconciliado na pausa" ] \
  && [ "$(git -C "$R" rev-parse HEAD~1)" = "$WIP" ] \
  && ok "um commit próprio logo depois do WIP" || erro "commit próprio ausente ou fora de ordem" "$(git -C "$R" log --oneline -3)"
[ "$(git -C "$R" diff --name-only HEAD~1 HEAD)" = ".planning/STATE.md" ] \
  && ok "o commit próprio só carrega o STATE.md" || erro "commit próprio com outros arquivos"
campo "$R" stopped_at | grep -q "$(cut -c1-7 <<<"$WIP")" && ok "stopped_at cita o hash do WIP" || erro "stopped_at sem o hash" "$(campo "$R" stopped_at)"
[ "$(jq -r .discrepancia_commits <<<"$J")" = 5 ] && [ "$(jq -r .commit_proprio <<<"$J")" != null ] \
  && ok "JSON: discrepancia_commits 5 + commit_proprio" || erro "JSON incompleto" "$J"
[ -z "$(git -C "$R" status --porcelain)" ] && ok "árvore limpa depois" || erro "árvore suja"

echo "== (k2) confere-etapa.sh pausa --pos-pausa DEPOIS do reconcilia → pass"
CE=$(bash "$CONFERE" pausa --pos-pausa --fase 24.4 --projeto "$R" 2>&1); CRC=$?
[ "$CRC" = 0 ] && ok "pass (state_head = HEAD~1)" || erro "esperado pass, veio $CRC" "$CE"

echo "== (h) --pausa de novo → já reconciliado, nada a fazer, sem commit novo"
H=$(git -C "$R" rev-parse HEAD); roda_pausa "$R"
[ "$RC" = 0 ] && [ "$(jq -r .ja_reconciliado <<<"$J")" = true ] && [ "$(jq '.acoes|length' <<<"$J")" = 0 ] \
  && ok "ja_reconciliado: true, 0 ações" || erro "reincidiu" "$J"
[ "$(git -C "$R" rev-parse HEAD)" = "$H" ] && ok "sem commit novo" || erro "commitou de novo"

echo "== (i) state_head desconhecido neste repo → discrepância null + pendência"
R=$(monta_pausa i executing desconhecido); roda_pausa "$R"
[ "$RC" = 0 ] && ok "exit 0" || erro "esperado 0, veio $RC" "$SAIDA"
[ "$(jq -r .discrepancia_commits <<<"$J")" = null ] && printf '%s' "$J" | grep -q 'não existe neste repositório' \
  && ok "discrepancia_commits: null + pendência declarada" || erro "discrepância silenciosa" "$J"
[ "$(campo "$R" status)" = paused ] && ok "mesmo assim gravou paused (o HEAD real é legível)" || erro "não gravou"

echo "== (j) --pausa com status como FRASE → FORMATO-INESPERADO + exit 3, nada escrito"
R=$(monta_pausa j '"Fase 24.4 EM EXECUÇÃO → PAUSADA"' sim); H=$(git -C "$R" rev-parse HEAD); roda_pausa "$R"
[ "$RC" = 3 ] && ok "exit 3" || erro "esperado 3, veio $RC" "$SAIDA"
[ "$(git -C "$R" rev-parse HEAD)" = "$H" ] && grep -q '^status: "Fase 24.4' "$R/.planning/STATE.md" \
  && ok "sem commit e sem reescrever o status ilegível" || erro "mexeu no que não sabe ler"

echo
[ "$falhas" -eq 0 ] && echo "test-reconcilia-docs: TUDO OK" || echo "test-reconcilia-docs: $falhas falha(s)"
[ "$falhas" -eq 0 ]
