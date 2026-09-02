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
  pd="$root/.planning/phases/99-bancada"; mkdir -p "$pd"
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

IFS='|' read -r R PD <<<"$(monta bloqueio_runlog 2)"
cfg "$R" '.workflow.use_worktrees=false'
roda "$R"
eq "bloqueio fora do dry-run → exit 4"            "$RC" "4"
casa "…evento script exit=4 paralelismo=bloqueio no run-log" "$(tail -n1 "$PD/99-RUN-LOG.jsonl")" '"evento":"script".*"exit":4.*"paralelismo":"bloqueio"'

echo "--------------------------------------------------"
echo "test-pre-despacho.sh: $OK ok / $FALHAS falha(s)"
[ "$FALHAS" -eq 0 ]
