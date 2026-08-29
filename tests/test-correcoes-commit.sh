#!/usr/bin/env bash
# test-correcoes-commit.sh — bancada do E2b (o commit por ciclo das correções).
#
# Régua: o commit do ciclo leva o delta DO CICLO e nada mais. Um doc que o usuário já
# havia sujado antes do ciclo continua sujo, com exatamente a mesma sujeira, depois.
# Falha → nada promovido: HEAD e .git/index byte a byte inalterados.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/correcoes-commit.sh"
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

REPO=""; PD=""
G() { git -C "$REPO" -c user.name=t -c user.email=t@t.io -c commit.gpgsign=false "$@"; }
RUN() { ( cd "$REPO" && bash "$SCRIPT" "$@" ); }

monta_repo() { # cria repo limpo com ROADMAP/REQUIREMENTS + fase 24.3
  REPO=$(mktemp -d "${TMPDIR:-/tmp}/gad-e2b-XXXXXX")
  PD="$REPO/.planning/phases/24.3-fase"
  mkdir -p "$PD" "$REPO/.planning"
  git -c init.defaultBranch=main init -q "$REPO"
  seq 1 20 | sed 's/^/linha /' > "$REPO/.planning/ROADMAP.md"
  echo "req base" > "$REPO/.planning/REQUIREMENTS.md"
  echo "spec base"    > "$PD/24.3-SPEC.md"
  echo "context base" > "$PD/24.3-CONTEXT.md"
  echo "review base"  > "$PD/24.3-INTENT-REVIEW.md"
  echo "arquivo do usuario" > "$REPO/alheio.txt"
  G add -A >/dev/null; G commit -qm base >/dev/null
}
limpa() { [ -n "$REPO" ] && rm -rf "$REPO"; }
trap limpa EXIT

ALVOS=(--artefatos "" "" "" --docs "" "")
set_alvos() {
  ALVOS=(--artefatos "$PD/24.3-SPEC.md" "$PD/24.3-CONTEXT.md" "$PD/24.3-INTENT-REVIEW.md"
         --docs "$REPO/.planning/ROADMAP.md" "$REPO/.planning/REQUIREMENTS.md")
}

echo "== E2b.1 — ROADMAP sujo só no worktree; inserção do ciclo ANTES do hunk do usuário"
monta_repo; set_alvos
sed -i '15s/.*/linha 15 EDITADA PELO USUARIO/' "$REPO/.planning/ROADMAP.md"   # sujeira pré-ciclo
# delta = CONTEÚDO das linhas +/- (nunca o texto do diff: a inserção do ciclo acima do
# hunk do usuário muda os offsets @@ sem mudar uma vírgula do que o usuário editou)
delta_conteudo() { G diff -U0 -- .planning/ROADMAP.md | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)'; }
DELTA_PRE=$(delta_conteudo)
RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1 || erro "--inicio falhou"
sed -i '2a linha inserida pelo ciclo' "$REPO/.planning/ROADMAP.md"            # delta do ciclo
echo "spec corrigida pelo ciclo" >> "$PD/24.3-SPEC.md"
saida=$(RUN "$PD" 1 --ids "c1-01:h1,c1-02:h2" "${ALVOS[@]}" 2>&1); rc=$?
if [ $rc -ne 0 ]; then erro "commit do ciclo falhou (rc=$rc)" "$saida"; else
  ok "commit do ciclo aceito"
  st=$(G diff --cached --name-only -- .planning/ROADMAP.md "$PD/24.3-SPEC.md")
  [ -z "$st" ] && ok "git diff --cached dos alvos vazio" || erro "índice ficou sujo" "$st"
  d=$(delta_conteudo)
  [ "$d" = "$DELTA_PRE" ] && ok "delta do worktree do ROADMAP = delta pré-ciclo" \
    || erro "o commit levou (ou perdeu) a edição do usuário"
  G diff --quiet -- "$PD/24.3-SPEC.md" && ok "SPEC (limpa antes) ficou limpa" \
    || erro "SPEC continua suja depois do commit"
  head_rm=$(G show HEAD:.planning/ROADMAP.md)
  case "$head_rm" in *"inserida pelo ciclo"*) ok "commit contém a inserção do ciclo" ;;
    *) erro "commit não contém a inserção do ciclo" ;; esac
  case "$head_rm" in *"EDITADA PELO USUARIO"*) erro "commit levou a edição do usuário" ;;
    *) ok "commit NÃO contém a edição do usuário" ;; esac
  apl="$PD/.intent/.correcoes-c1.aplicado"
  cam=$(jq -cr '.caminhos|sort|join(",")' "$apl" 2>/dev/null)
  [ "$cam" = ".planning/ROADMAP.md,.planning/phases/24.3-fase/24.3-SPEC.md" ] \
    && ok '.aplicado lista exatamente os caminhos comitados' || erro ".aplicado.caminhos" "$cam"
  ids=$(jq -cr '.correcoes|map(.id+":"+.hash)|join(",")' "$apl" 2>/dev/null)
  [ "$ids" = "c1-01:h1,c1-02:h2" ] && ok '.aplicado traz {id,hash} das correcoes' || erro "ids" "$ids"
  msg=$(G log -1 --pretty=%s)
  [ "$msg" = "docs(fase 24.3): correções do ciclo 1 — c1-01:h1,c1-02:h2" ] \
    && ok "mensagem canônica do commit" || erro "mensagem" "$msg"
fi
limpa

echo "== E2b.2 — arquivo alheio STAGED é preservado"
monta_repo; set_alvos
echo "mudanca do usuario" >> "$REPO/alheio.txt"; G add alheio.txt
RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1
echo "corrigido" >> "$PD/24.3-CONTEXT.md"
RUN "$PD" 1 --ids "c1-01" "${ALVOS[@]}" >/dev/null 2>&1 && ok "commit aceito com alheio staged" \
  || erro "commit recusado por causa de arquivo alheio staged"
G diff --cached --name-only | grep -qx alheio.txt \
  && ok "alheio.txt continua staged (não foi absorvido nem perdido)" \
  || erro "alheio.txt saiu do índice"
G show HEAD:alheio.txt | grep -q "mudanca do usuario" \
  && erro "alheio.txt foi comitado junto" || ok "alheio.txt NÃO foi comitado"
limpa

echo "== E2b.3 — alvo STAGED → exit 3"
monta_repo; set_alvos
echo "x" >> "$PD/24.3-SPEC.md"; G add "$PD/24.3-SPEC.md"
RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] && ok "--inicio recusa alvo staged (exit 3)" || erro "esperado exit 3, veio $rc"
limpa

echo "== E2b.4 — sobreposição REAL → exit 3 e nada promovido"
monta_repo; set_alvos
sed -i '15s/.*/linha 15 versao do usuario/' "$REPO/.planning/ROADMAP.md"
RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1
sed -i '15s/.*/linha 15 versao do ciclo/' "$REPO/.planning/ROADMAP.md"   # mesma linha
HEAD_ANTES=$(G rev-parse HEAD); IDX_ANTES=$(md5sum < "$REPO/.git/index")
saida=$(RUN "$PD" 1 --ids "c1-01" "${ALVOS[@]}" 2>&1); rc=$?
[ "$rc" = 3 ] && ok "sobreposição real recusada (exit 3)" || erro "esperado exit 3, veio $rc" "$saida"
[ "$(G rev-parse HEAD)" = "$HEAD_ANTES" ] && ok "HEAD inalterado" || erro "HEAD avançou numa recusa"
[ "$(md5sum < "$REPO/.git/index")" = "$IDX_ANTES" ] && ok ".git/index byte a byte inalterado" \
  || erro ".git/index mudou numa recusa"
[ -f "$PD/.intent/.correcoes-c1.aplicado" ] && erro ".aplicado gravado numa recusa" \
  || ok "nenhum .aplicado numa recusa"
limpa

echo "== E2b.5 — --vazio grava o marcador explícito"
monta_repo
RUN "$PD" 2 --vazio >/dev/null 2>&1
[ -f "$PD/.intent/.correcoes-c2.vazio" ] && ok '.correcoes-c2.vazio criado' || erro "marcador ausente"
limpa

echo "== E2b.6 — ciclo que não alterou nada cai no .vazio sozinho (caminho do gate E2c)"
monta_repo; set_alvos
RUN "$PD" 3 --inicio "${ALVOS[@]}" >/dev/null 2>&1
HEAD_ANTES=$(G rev-parse HEAD)
RUN "$PD" 3 --ids "c3-01" "${ALVOS[@]}" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok "fecho sem nenhuma alteração → exit 0" || erro "esperado 0, veio $rc"
[ -f "$PD/.intent/.correcoes-c3.vazio" ] && ok "grava .correcoes-c3.vazio automaticamente" \
  || erro "sem marcador .vazio"
[ -f "$PD/.intent/.correcoes-c3.aplicado" ] && erro ".aplicado gravado sem commit" || ok "nenhum .aplicado"
[ "$(G rev-parse HEAD)" = "$HEAD_ANTES" ] && ok "HEAD não avançou (commit vazio não nasce)" || erro "HEAD avançou"
limpa

echo
[ "$falhas" -eq 0 ] && echo "test-correcoes-commit: TUDO OK" || echo "test-correcoes-commit: $falhas falha(s)"
[ "$falhas" -eq 0 ]
