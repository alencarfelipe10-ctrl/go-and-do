#!/usr/bin/env bash
# test-pre-despacho.sh — bancada do bloco de paralelismo do `pre-despacho.sh 3` (P04, 01/09):
#   · `workflow.use_worktrees: false` / `parallelization: false` → bloqueio_paralelismo, exit 4
#   · `--interactive` nos args da rodada → exit 4
#   · base-check rebaixando (remoto sem origin/HEAD, sem baseRef) com onda de ≥2 planos → exit 4
#     com a `message` real; fora do --dry-run o `set-baseref` aplica `head`, registra no
#     NN-DECISOES.md e o despacho sai ok com `baseref_aplicado: true`
#   · repositório sem remoto (o caso do inspired) → ok, `should_degrade: false` (P02)
#   · ondas de 1 plano → `nota: n/a`
#
# Projeto de bancada em mktemp; o gsd-tools real é chamado (phase-plan-index, base-check,
# set-baseref). CONTEXT_TOKEN_LIMIT alto para o gate de contexto da sessão nunca virar stop.
#   bash tests/test-pre-despacho.sh      · exit 0 = verde
set -u

RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
P="$RAIZ/skills/go-and-do/scripts/pre-despacho.sh"
export CONTEXT_TOKEN_LIMIT=99000000

OK=0; FALHAS=0
ok()    { OK=$((OK+1)); printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }
casa()  { if printf '%s' "$2" | grep -qE "$3"; then ok "$1"; else falha "$1" "não casou /$3/ em: $(printf '%s' "$2" | head -c 240)"; fi; }

BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT

plano() { # <phase_dir> <nn> <plan> <wave> [dep]
  { printf -- '---\nphase: "%s"\nplan: %s\ntype: execute\nwave: %s\ndepends_on: [%s]\nfiles_modified:\n  - src/%s.py\nautonomous: true\n---\n\n# Plano %s\n' \
      "$2" "$3" "$4" "${5:-}" "$3" "$3"; } > "$1/$2-$3-PLAN.md"
}
monta() { # <nome> <largura da onda 1: 1|2> → ecoa "<root>|<phase_dir>"
  local root="$BASE/$1" pd
  mkdir -p "$root/.planning/phases" "$root/.claude"
  git init -q "$root" >/dev/null 2>&1
  git -C "$root" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base >/dev/null 2>&1
  printf '{"workflow":{"use_worktrees":true},"parallelization":{"enabled":true}}\n' > "$root/.planning/config.json"
  printf '{"permissions":{"allow":[]}}\n' > "$root/.claude/settings.local.json"
  pd="$root/.planning/phases/99-bancada"; mkdir -p "$pd" "$root/.planning/.gad"
  # C1 (plano 4): o bloco exige o portão §13a-bis passado NESTA fase — a bancada nasce com o espelho
  printf '{"passed":true,"falhas":[],"avisos":[],"resumo":{"fase":"99","planos":3,"ondas":2,"razao":0.67,"largura_max":2}}\n' > "$root/.planning/.gad/last-plan-gate.json"
  plano "$pd" 99 01 1
  [ "$2" = 2 ] && plano "$pd" 99 02 1
  plano "$pd" 99 03 2 '"99-01"'
  jq -cn --arg pd "$pd" --arg rl "$pd/99-RUN-LOG.jsonl" \
    '{session_id:"bancada", fase:"99", nn:"99", phase_dir:$pd, runlog:$rl, args:{ui:false,ai:false,no_ship:false,vault:false,obs:""}}' \
    > "$root/.planning/.gad-rodada-ativa.json"
  printf '%s|%s' "$root" "$pd"
}
roda() { # <root> [flags] → J (última linha) e RC
  local root="$1"; shift
  J=$(cd "$root" && bash "$P" 3 --projeto "$root" "$@" 2>/dev/null | tail -1); RC=${PIPESTATUS[0]}
  RC=$(cd "$root" && bash "$P" 3 --projeto "$root" "$@" >/dev/null 2>&1; echo $?)
}
cfg() { jq -c "$2" "$1/.planning/config.json" > "$1/.planning/c.tmp" && mv "$1/.planning/c.tmp" "$1/.planning/config.json"; }
remoto_sem_head() { # <root> — origin apontando para um bare sem HEAD resolvível
  git clone -q --bare "$1" "$1.git" >/dev/null 2>&1
  git -C "$1" remote add origin "$1.git"
  git -C "$1" fetch -q origin >/dev/null 2>&1
  git -C "$1" symbolic-ref -d refs/remotes/origin/HEAD >/dev/null 2>&1 || true
}

monta25() { # <nome> <autonomo:true|false> [<autonomo2>] → root|phase_dir (etapa 2.5)
  local root="$BASE/$1" pd
  mkdir -p "$root/.planning/phases"
  git init -q "$root" >/dev/null 2>&1
  git -C "$root" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base >/dev/null 2>&1
  printf '{}\n' > "$root/.planning/config.json"
  pd="$root/.planning/phases/99-bancada"; mkdir -p "$pd"
  printf -- '---\nphase: "99"\nplan: 01\ntype: execute\nwave: 1\nautonomous: %s\n---\n\n# Plano\n' "$2" > "$pd/99-01-PLAN.md"
  if [ -n "${3:-}" ]; then
    printf -- '---\nphase: "99"\nplan: 02\ntype: execute\nwave: 1\nautonomous: %s\n---\n\n# Plano\n' "$3" > "$pd/99-02-PLAN.md"
  fi
  jq -cn --arg pd "$pd" --arg rl "$pd/99-RUN-LOG.jsonl" \
    '{session_id:"bancada", fase:"99", nn:"99", phase_dir:$pd, runlog:$rl, args:{ui:false,ai:false,no_ship:false,vault:false,obs:""}}' \
    > "$root/.planning/.gad-rodada-ativa.json"
  printf '%s|%s' "$root" "$pd"
}
roda25() { # <root> [flags] → J (última linha) e RC
  local root="$1"; shift
  J=$(cd "$root" && bash "$P" 2.5 --projeto "$root" "$@" 2>/dev/null | tail -1); RC=${PIPESTATUS[0]}
  RC=$(cd "$root" && bash "$P" 2.5 --projeto "$root" "$@" >/dev/null 2>&1; echo $?)
}

echo "── S-11 (tarefa 48l): pre-despacho.sh 2.5 trava com plano autonomous:false ──"
IFS='|' read -r R PD <<<"$(monta25 s11_bloqueia false)"
roda25 "$R" --dry-run
eq "autonomous:false pendente → exit 4"             "$RC" "4"
eq "…despacho bloqueio_plano_nao_resolvido"          "$(jq -r .despacho <<<"$J")" "bloqueio_plano_nao_resolvido"
casa "…motivo cita o plano 01"                       "$(jq -r .motivo <<<"$J")" '\b01\b'
casa "…pergunta ao dono orienta o 2.4b"              "$(jq -r .pergunta_ao_dono <<<"$J")" 'autonomous: true'

IFS='|' read -r R PD <<<"$(monta25 s11_lista_dois false false)"
roda25 "$R" --dry-run
casa "dois planos pendentes → motivo lista os dois"  "$(jq -r .motivo <<<"$J")" '01,02'

IFS='|' read -r R PD <<<"$(monta25 s11_ok true)"
roda25 "$R" --dry-run
D25=$(jq -r .despacho <<<"$J")
if [ "$D25" != "bloqueio_plano_nao_resolvido" ]; then ok "todos autonomous:true → não bloqueia por 2.4b (despacho=$D25)"
else falha "todos autonomous:true → não bloqueia por 2.4b" "despacho=$D25"; fi

IFS='|' read -r R PD <<<"$(monta25 s11_runlog false)"
roda25 "$R"
casa "…fora do dry-run grava o evento script exit=4 no run-log" "$(tail -n1 "$PD/99-RUN-LOG.jsonl")" '"evento":"script".*"exit":4'

echo "── S-8 (tarefa 48i): confere-user-setup.sh acoplado ao gate 2.5 (informativo) ──"
IFS='|' read -r R PD <<<"$(monta25 s8_sem_setup true)"
roda25 "$R" --dry-run
eq "sem user_setup declarado → extras.user_setup.veredito nao_se_aplica" \
  "$(jq -r '.user_setup.veredito' <<<"$J")" "nao_se_aplica"

IFS='|' read -r R PD <<<"$(monta25 s8_pendente true)"
sed -i '/^autonomous: true$/i user_setup:\n  - service: stripe\n    env_vars:\n      - name: STRIPE_SECRET_KEY' "$PD/99-01-PLAN.md"
roda25 "$R" --dry-run
eq "user_setup pendente (sem .env) → extras.user_setup.veredito falha, mas despacho segue ok" \
  "$(jq -r '.user_setup.veredito' <<<"$J")" "falha"
eq "…e o despacho da 2.5 NÃO é bloqueado por isso (informativo)" "$(jq -r .despacho <<<"$J")" "ok"

echo "── S-9 (tarefa 48j): sino de tamanho no pre-despacho.sh 2 (SPEC/CONTEXT grandes) ──"
roda2() { # <root> [flags] → J (última linha) e RC (etapa 2, reusa monta25)
  local root="$1"; shift
  J=$(cd "$root" && bash "$P" 2 --projeto "$root" "$@" 2>/dev/null | tail -1); RC=${PIPESTATUS[0]}
  RC=$(cd "$root" && bash "$P" 2 --projeto "$root" "$@" >/dev/null 2>&1; echo $?)
}
IFS='|' read -r R PD <<<"$(monta25 s9_pequeno true)"
printf 'SPEC pequena\n' > "$PD/99-SPEC.md"
roda2 "$R" --dry-run
eq "SPEC pequena → sem sino_tamanho" "$(jq -r 'has("sino_tamanho")' <<<"$J")" "false"

IFS='|' read -r R PD <<<"$(monta25 s9_spec_grande true)"
python3 -c "open('$PD/99-SPEC.md','w').write('x'*70000)"
roda2 "$R" --dry-run
eq "exit 0 (alarme, não muro)" "$RC" "0"
eq "despacho continua ok" "$(jq -r .despacho <<<"$J")" "ok"
casa "sino_tamanho nomeia o arquivo e o teto de 60 KB" "$(jq -r .sino_tamanho <<<"$J")" '99-SPEC\.md.*~69 KB.*teto de leitura \(60 KB\)'

IFS='|' read -r R PD <<<"$(monta25 s9_context_grande true)"
python3 -c "open('$PD/99-CONTEXT.md','w').write('y'*65000)"
roda2 "$R" --dry-run
casa "CONTEXT grande também soa o sino" "$(jq -r .sino_tamanho <<<"$J")" '99-CONTEXT\.md'

IFS='|' read -r R PD <<<"$(monta25 s9_teto_custom true)"
printf 'SPEC de 20000 bytes\n' > "$PD/99-SPEC.md"
python3 -c "open('$PD/99-SPEC.md','a').write('z'*20000)"
roda2 "$R" --dry-run
eq "abaixo do teto default → sem sino" "$(jq -r 'has("sino_tamanho")' <<<"$J")" "false"
J=$(cd "$R" && GAD_TETO_BRIEFING_KB=10 bash "$P" 2 --projeto "$R" --dry-run 2>/dev/null | tail -1)
casa "GAD_TETO_BRIEFING_KB=10 aperta o teto → o mesmo arquivo agora soa o sino" "$(jq -r .sino_tamanho <<<"$J")" '99-SPEC\.md.*teto de leitura \(10 KB\)'

IFS='|' read -r R PD <<<"$(monta25 s9_ambos_grandes true)"
python3 -c "open('$PD/99-SPEC.md','w').write('x'*70000)"
python3 -c "open('$PD/99-CONTEXT.md','w').write('y'*70000)"
roda2 "$R" --dry-run
casa "os dois grandes → sino nomeia os dois, separados por ; " "$(jq -r .sino_tamanho <<<"$J")" '99-SPEC\.md.*; .*99-CONTEXT\.md'

echo "── config nega o paralelismo ──"
IFS='|' read -r R PD <<<"$(monta cfg_uw 2)"
cfg "$R" '.workflow.use_worktrees=false'
roda "$R" --dry-run
eq "use_worktrees=false → exit 4"                 "$RC" "4"
eq "…despacho bloqueio_paralelismo"               "$(jq -r .despacho <<<"$J")" "bloqueio_paralelismo"
casa "…motivo nomeia a chave e o valor"           "$(jq -r .motivo <<<"$J")" 'workflow\.use_worktrees=false'
eq "…paralelismo.use_worktrees vem como booleano" "$(jq -c .paralelismo.use_worktrees <<<"$J")" "false"

IFS='|' read -r R PD <<<"$(monta cfg_par 2)"
cfg "$R" '.parallelization=false'
roda "$R" --dry-run
eq "parallelization=false (booleano) → exit 4"    "$RC" "4"
casa "…motivo"                                    "$(jq -r .motivo <<<"$J")" 'parallelization=false'

IFS='|' read -r R PD <<<"$(monta cfg_par_obj 2)"
cfg "$R" '.parallelization={enabled:false}'
roda "$R" --dry-run
eq "parallelization.enabled=false (objeto) → exit 4" "$RC" "4"

echo "── args da rodada ──"
IFS='|' read -r R PD <<<"$(monta args 2)"
jq '.args.obs="executar com --interactive"' "$R/.planning/.gad-rodada-ativa.json" > "$R/p.tmp" && mv "$R/p.tmp" "$R/.planning/.gad-rodada-ativa.json"
roda "$R" --dry-run
eq "--interactive nos args → exit 4"              "$RC" "4"
eq "…interactive_nos_args true"                   "$(jq -c .paralelismo.interactive_nos_args <<<"$J")" "true"

echo "── base da cópia ──"
IFS='|' read -r R PD <<<"$(monta sem_remoto 2)"
roda "$R" --dry-run
eq "sem remoto, onda de 2 → exit 0 (P02: no-remote não rebaixa)" "$RC" "0"
eq "…should_degrade false"                        "$(jq -c .paralelismo.should_degrade <<<"$J")" "false"
eq "…ondas_largas = [\"1\"]"                      "$(jq -c .paralelismo.ondas_largas <<<"$J")" '["1"]'
eq "…isolation medido"                            "$(jq -r .paralelismo.isolation <<<"$J")" "harness-worktree"

IFS='|' read -r R PD <<<"$(monta remoto_dry 2)"
remoto_sem_head "$R"
roda "$R" --dry-run
eq "remoto sem origin/HEAD, sem baseRef, --dry-run → exit 4" "$RC" "4"
eq "…should_degrade true"                         "$(jq -c .paralelismo.should_degrade <<<"$J")" "true"
casa "…a message real do base-check vai na saída" "$(jq -r .paralelismo.message <<<"$J")" 'origin/HEAD'
casa "…e na pergunta ao dono"                     "$(jq -r .pergunta_ao_dono <<<"$J")" 'origin/HEAD'
eq "…dry-run não aplica baseRef"                  "$(jq -c '.worktree // null' "$R/.claude/settings.local.json")" "null"
[ -f "$R/.planning/.gad/last-pre-despacho-3.json" ] && falha "dry-run não grava o espelho-3" "arquivo existe" || ok "dry-run não grava o espelho-3"

IFS='|' read -r R PD <<<"$(monta remoto_real 2)"
remoto_sem_head "$R"
roda "$R"
eq "mesmo repositório sem --dry-run → set-baseref head e exit 0" "$RC" "0"
eq "…baseref_aplicado true"                       "$(jq -c .paralelismo.baseref_aplicado <<<"$J")" "true"
eq "…settings.local.json ganhou worktree.baseRef" "$(jq -r '.worktree.baseRef' "$R/.claude/settings.local.json")" "head"
eq "…permissions preservadas"                     "$(jq -c '.permissions' "$R/.claude/settings.local.json")" '{"allow":[]}'
casa "…registrado no NN-DECISOES.md"              "$(cat "$PD/99-DECISOES.md" 2>/dev/null)" 'baseRef: head aplicado pelo pre-despacho'
eq "…espelho-3 com use_worktrees true"            "$(jq -c .use_worktrees "$R/.planning/.gad/last-pre-despacho-3.json")" "true"
casa "…checkpoint no run-log com paralelismo=ok"  "$(tail -n1 "$PD/99-RUN-LOG.jsonl")" '"evento":"checkpoint".*"paralelismo":"ok"'
roda "$R"
eq "2ª rodada: baseRef já estava → baseref_aplicado false" "$(jq -c .paralelismo.baseref_aplicado <<<"$J")" "false"
eq "…e o DECISOES.md não ganha entrada repetida"  "$(grep -c 'baseRef: head aplicado' "$PD/99-DECISOES.md")" "1"

echo "── ondas estreitas e bloqueio gravado ──"
IFS='|' read -r R PD <<<"$(monta estreita 1)"
roda "$R" --dry-run
eq "ondas de 1 plano → exit 0"                    "$RC" "0"
casa "…nota n/a"                                  "$(jq -r '.paralelismo.nota // ""' <<<"$J")" 'n/a'
eq "…ondas_largas vazio"                          "$(jq -c .paralelismo.ondas_largas <<<"$J")" '[]'
eq "…C2: sem_onda_larga true no espelho"          "$(jq -c .paralelismo.sem_onda_larga <<<"$J")" "true"
roda "$R"
casa "…C2: fora do dry-run toca o sino — incidente no run-log (origem=pre-despacho.sh)" "$(cat "$PD/99-RUN-LOG.jsonl")" '"evento":"incidente".*"origem":"pre-despacho.sh".*nenhuma onda com 2\+ planos'
eq "…e não bloqueia (exit 0)"                     "$RC" "0"

echo "── C1: portão de forma (§13a-bis) desta fase ──"
IFS='|' read -r R PD <<<"$(monta pg_ausente 2)"
rm -f "$R/.planning/.gad/last-plan-gate.json"
roda "$R" --dry-run
eq "sem last-plan-gate.json → exit 4"             "$RC" "4"
casa "…motivo plan_gate_ausente_ou_reprovado"     "$(jq -r .motivo <<<"$J")" 'plan_gate_ausente_ou_reprovado: last-plan-gate.json ausente'
casa "…pergunta ao dono: replanejar ou aceitar"   "$(jq -r .pergunta_ao_dono <<<"$J")" 'Replanejar.*aceitar o despacho'
IFS='|' read -r R PD <<<"$(monta pg_reprovado 2)"
printf '{"passed":false,"falhas":[{"codigo":"SOBREPOSICAO-NA-ONDA","planos":["99-01","99-02"]}],"avisos":[],"resumo":{"fase":"99"}}\n' > "$R/.planning/.gad/last-plan-gate.json"
roda "$R" --dry-run
eq "passed:false → exit 4"                        "$RC" "4"
casa "…motivo cita o código que reprovou"         "$(jq -r .motivo <<<"$J")" 'passed=false: SOBREPOSICAO-NA-ONDA'
IFS='|' read -r R PD <<<"$(monta pg_outra_fase 2)"
printf '{"passed":true,"falhas":[],"avisos":[],"resumo":{"fase":"98"}}\n' > "$R/.planning/.gad/last-plan-gate.json"
roda "$R" --dry-run
eq "passed:true mas resumo.fase de outra fase → exit 4" "$RC" "4"
casa "…motivo nomeia a fase do espelho"           "$(jq -r .motivo <<<"$J")" "é da fase '98', não da 99"
IFS='|' read -r R PD <<<"$(monta pg_prefixo 2)"
printf '{"passed":true,"falhas":[],"avisos":[],"resumo":{"fase":"INS-99"}}\n' > "$R/.planning/.gad/last-plan-gate.json"
roda "$R" --dry-run
eq "resumo.fase com prefixo de projeto (INS-99) casa com 99 → exit 0" "$RC" "0"
eq "…plan_gate_ok true no espelho"                "$(jq -c .paralelismo.plan_gate_ok <<<"$J")" "true"

IFS='|' read -r R PD <<<"$(monta bloqueio_runlog 2)"
cfg "$R" '.workflow.use_worktrees=false'
roda "$R"
eq "bloqueio fora do dry-run → exit 4"            "$RC" "4"
casa "…evento script exit=4 paralelismo=bloqueio no run-log" "$(tail -n1 "$PD/99-RUN-LOG.jsonl")" '"evento":"script".*"exit":4.*"paralelismo":"bloqueio"'

# ── A4 (auditoria F4 RLR): etapa 6 — FM-01ENC · FJ-04ENC · MGTm-01ENC · FM-03ENC ──
IFS='|' read -r R PD <<<"$(monta enc6 1)"
cat > "$PD/99-SECURITY.md" <<'SEC'
---
status: secured
threats_open: 0
asvs_level: 2
---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Disposition |
|---|---|---|---|
| R-99-SC | T-99-SC | Nenhum pacote novo na fase | accept |
SEC
printf 'result: pass
' > "$PD/99-UAT.md"
printf '{"seq":1,"evento":"incidente","etapa":"5 uat","detalhe":"sleep barrado pela guarda"}
{"seq":2,"evento":"incidente","etapa":"6 encerramento","detalhe":"outro atrito"}
' > "$PD/99-RUN-LOG.jsonl"
J6=$(cd "$R" && CLAUDE_CODE_SESSION_ID= bash "$P" 6 --projeto "$R" --fase 99 --dry-run 2>/dev/null | tail -1)
printf '%s' "$J6" | jq -e . >/dev/null 2>&1   && ok "FM-03ENC: o stdout da etapa 6 é JSON válido (nada de prosa)"   || bad "FM-03ENC: stdout da etapa 6 não é JSON" "$J6"
casa "FM-01ENC: risco aceito sai da tabela Accepted Risks Log, não do cabeçalho"      "$(jq -c '.transparencia.riscos_aceitos' <<<"$J6")" 'R-99-SC'
eq "FM-01ENC: e a lista não sai vazia"    "$(jq '.transparencia.riscos_aceitos|length' <<<"$J6")" "1"
eq "FJ-04ENC: os DOIS incidentes entram na 6ª lista da transparência"    "$(jq '.transparencia.incidentes|length' <<<"$J6")" "2"
eq "MGTm-01ENC: sem NN-VERIFICATION.md commitado, verification_stale é false declarado"    "$(jq -c '.verification_stale.stale' <<<"$J6")" "false"
# SECURITY que fala em risco aceito e extrator vazio = leitor quebrado, não «nenhum»
printf -- '---
status: secured
---

## Accepted Risks Log

(tabela perdida na formatação)
' > "$PD/99-SECURITY.md"
J6=$(cd "$R" && bash "$P" 6 --projeto "$R" --fase 99 --dry-run 2>/dev/null | tail -1)
eq "FM-01ENC: lista vazia com SECURITY falando em risco aceito → suspeita declarada"    "$(jq -c '.transparencia.riscos_aceitos_lista_vazia_suspeita' <<<"$J6")" "true"

echo "--------------------------------------------------"
echo "test-pre-despacho.sh: $OK ok / $FALHAS falha(s)"
[ "$FALHAS" -eq 0 ]
