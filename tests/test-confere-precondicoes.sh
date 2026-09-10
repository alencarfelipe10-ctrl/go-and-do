#!/usr/bin/env bash
# test-confere-precondicoes.sh — bancada do confere-precondicoes.sh (45l, F24.5).
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"; REPO="$(dirname -- "$AQUI")"
S="$REPO/skills/go-and-do/scripts/confere-precondicoes.sh"
falhas=0; ok=0
ok()  { ok=$((ok+1)); echo "PASS: $1"; }
bad() { falhas=$((falhas+1)); echo "FAIL: $1${2:+ — $2}"; }
eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1" "esperado [$3] obtido [$2]"; }
PAI=$(mktemp -d); trap 'rm -rf "$PAI"' EXIT

monta() { # <nome> <fixtures:1|0> <use_worktrees:true|false|-> → ecoa "root|pd"
  local root="$PAI/$1" pd="$PAI/$1/.planning/phases/24.5-x"; mkdir -p "$pd"
  [ "$2" = 1 ] && printf 'initial-data/\n' > "$root/.planning/worktree-fixtures.txt"
  [ "$3" != - ] && printf '{"workflow":{"use_worktrees":%s}}\n' "$3" > "$root/.planning/config.json"
  printf '%s|%s' "$root" "$pd"
}
plano() { # <pd> <id> <isolation-line|-> <precondition-text|->
  { printf -- '---\nphase: "24.5"\nplan: "%s"\nwave: 1\n' "$2"
    [ "$3" != - ] && printf '%s\n' "$3"
    printf 'files_modified:\n  - a.py\nautonomous: true\n---\n\n# Plano\n\n<task type="auto">\n'
    [ "$4" != - ] && printf '  <precondition>%s</precondition>\n' "$4"
    printf '  <action>x</action>\n</task>\n'; } > "$1/24.5-$2-PLAN.md"
}
roda() { OUT=$(bash "$S" "$1" "$2" 2>/dev/null); RC=$?; }

echo "── com fixtures: reprova isolation: none e precondition SEM worktree"
IFS='|' read -r R PD <<<"$(monta a 1 -)"
plano "$PD" 01 'isolation: none' 'As bases de initial-data/ existem em disco e o plano roda SEM worktree.'
plano "$PD" 02 - 'As bases existem em disco; o plano roda SEM worktree.'
plano "$PD" 03 - 'Os caminhos chegam DENTRO do worktree pela cópia do passo 0. Este plano roda EM WORKTREE.'
plano "$PD" 04 'isolation: worktree' -
roda "$PD" "$R"
eq "exit 1" "$RC" 1
eq "veredito falha" "$(jq -r .veredito <<<"$OUT")" falha
eq "criterio fixtures" "$(jq -r .criterio <<<"$OUT")" fixtures
eq "planos 4" "$(jq -r .planos <<<"$OUT")" 4
eq "reprovados 01,02" "$(jq -r '[.planos_reprovados[].plan]|join(",")' <<<"$OUT")" "24.5-01,24.5-02"
eq "01 tem 2 motivos" "$(jq -r '.planos_reprovados[0].motivos|length' <<<"$OUT")" 2
eq "01 motivo 1 = isolation: none" "$(jq -r '.planos_reprovados[0].motivos[0]' <<<"$OUT")" "isolation: none"
eq "codigos" "$(jq -c .codigos <<<"$OUT")" '["PRECONDICAO-WORKTREE-OBSOLETA"]'

echo "── com fixtures, planos limpos: ok"
IFS='|' read -r R PD <<<"$(monta b 1 -)"
plano "$PD" 01 - 'Os caminhos chegam DENTRO do worktree.'
roda "$PD" "$R"; eq "exit 0" "$RC" 0; eq "veredito ok" "$(jq -r .veredito <<<"$OUT")" ok

echo "── sem fixtures, use_worktrees true: reprova pelo config"
IFS='|' read -r R PD <<<"$(monta c 0 true)"
plano "$PD" 01 'isolation: none' -
roda "$PD" "$R"; eq "exit 1" "$RC" 1; eq "criterio use_worktrees" "$(jq -r .criterio <<<"$OUT")" use_worktrees

echo "── sem fixtures nem use_worktrees: nao_se_aplica (lista, mas exit 0)"
IFS='|' read -r R PD <<<"$(monta d 0 -)"
plano "$PD" 01 'isolation: none' 'roda SEM worktree'
roda "$PD" "$R"; eq "exit 0" "$RC" 0; eq "nao_se_aplica" "$(jq -r .veredito <<<"$OUT")" nao_se_aplica
eq "…ainda lista o plano" "$(jq -r '.planos_reprovados|length' <<<"$OUT")" 1

echo "── uso inválido"
bash "$S" /nao/existe /tmp >/dev/null 2>&1; eq "exit 2" "$?" 2

echo "--------------------------------------------------"; echo "$ok ok / $falhas falhas"; [ "$falhas" -eq 0 ]
