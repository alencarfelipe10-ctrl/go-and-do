#!/usr/bin/env bash
# test-confere-plano.sh — bancada do confere-plano.sh (P06, consertos F24.4).
#
# Régua: os arquivos tocados pelos commits do plano (tag `tipo(<fase>-<plano>[-slug]):`)
# têm de caber em `files_modified` ∪ `files_deleted` do PLAN.md; e tem de haver um commit
# de tarefa por `<task>` (fora checkpoint), contando só os anteriores ao commit de
# metadados `docs(<plano>): complete … plan`. Os casos reproduzem em repositório sintético
# o que o histórico real da F24.4 mostrou (02: 1 commit p/ 3 tarefas; 08: 2 arquivos fora).
#   bash tests/test-confere-plano.sh      · exit 0 = verde
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/confere-plano.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-plano-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else erro "$1" "esperado [$3], obtido [$2]"; fi; }

# repo <nome> → raiz de um repositório git com a fase 7 e o PLAN 7-01
repo() {
  local r="$TMP/$1"
  mkdir -p "$r/.planning/phases/7-bancada"
  git init -q "$r"; git -C "$r" config user.email t@t; git -C "$r" config user.name t
  printf '%s' "$r"
}
plano() { # <root> <files_modified yaml lines> [tasks_xml] → escreve 7-01-PLAN.md
  { printf -- '---\nphase: "7"\nplan: 01\nwave: 1\n%s\nautonomous: true\n---\n' "$2"
    printf '<tasks>\n%s\n</tasks>\n' "${3:-<task type="auto">a</task>
<task type="auto" tdd="true">b</task>
<task type="auto">c</task>}"
  } > "$1/.planning/phases/7-bancada/7-01-PLAN.md"
  git -C "$1" add -A; git -C "$1" commit -qm 'docs(7): planos'
}
commit() { # <root> <msg> <arquivo...>
  local r="$1" m="$2"; shift 2
  for f in "$@"; do mkdir -p "$r/$(dirname "$f")"; date +%N >> "$r/$f"; done
  git -C "$r" add -A; git -C "$r" commit -qm "$m"
}
roda() { saida=$("$SCRIPT" "$1/.planning/phases/7-bancada" 7-01 2>/dev/null); rc=$?; saida=$(printf '%s' "$saida" | tail -1); }
campo() { printf '%s' "$saida" | jq -r "$1"; }

echo "== (a) um commit por tarefa, tudo na lista → ok"
R=$(repo a); plano "$R" 'files_modified:
  - src/a.py
  - src/b.py'
commit "$R" 'feat(7-01): tarefa 1' src/a.py
commit "$R" 'test(7-01-slug): tarefa 2' src/b.py
commit "$R" 'fix(7-01): tarefa 3' src/a.py src/b.py
commit "$R" 'docs(7-01): complete bancada plan' .planning/STATE.md .planning/phases/7-bancada/7-01-SUMMARY.md
commit "$R" 'fix(7-01): correção pós-gate' src/a.py
roda "$R"
eq "veredito ok, exit 0"              "$(campo .veredito)/$rc" "ok/0"
eq "tasks=3 commits=5 commits_tarefa=3 (o pós-metadados não é tarefa)" \
   "$(campo '"\(.tasks)/\(.commits)/\(.commits_tarefa)"')" "3/5/3"
eq "espelho .planning/.gad/last-confere-plano-7-01.json gravado" \
   "$(jq -r .plan "$R/.planning/.gad/last-confere-plano-7-01.json")" "7-01"

echo "== (b) arquivo fora da lista → FORA-DA-LISTA com os caminhos (caso 24.4-08)"
R=$(repo b); plano "$R" 'files_modified:
  - src/a.py'
commit "$R" 'feat(7-01): t1' src/a.py
commit "$R" 'test(7-01): t2' src/a.py
commit "$R" 'fix(7-01): t3 mexe fora' tests/golden/x.py tests/golden/y.py .planning/ROADMAP.md
roda "$R"
eq "veredito falha, exit 1"           "$(campo .veredito)/$rc" "falha/1"
eq "codigos = [FORA-DA-LISTA]"        "$(campo '.codigos|join(",")')" "FORA-DA-LISTA"
eq "fora_da_lista nomeia os dois (artefatos .planning/** não contam)" \
   "$(campo '.fora_da_lista|join(",")')" "tests/golden/x.py,tests/golden/y.py"

echo "== (c) três tarefas num commit → COMMITS-A-MENOS (caso 24.4-02)"
R=$(repo c); plano "$R" 'files_modified:
  - src/a.py'
commit "$R" 'test(7-01): tarefas 1+2+3 juntas' src/a.py
commit "$R" 'docs(7-01): complete bancada plan' .planning/phases/7-bancada/7-01-SUMMARY.md
commit "$R" 'fix(7-01): fix pós-gate 1' src/a.py
commit "$R" 'refactor(7-01): fix pós-gate 2' src/a.py
commit "$R" 'docs(7-01): registra no SUMMARY' .planning/phases/7-bancada/7-01-SUMMARY.md
roda "$R"
eq "codigos = COMMITS-A-MENOS (1 commits para 3 tarefas)" "$(campo '.codigos[0]')" "COMMITS-A-MENOS (1 commits para 3 tarefas)"
eq "commits=5 no total, mas commits_tarefa=1"  "$(campo '"\(.commits)/\(.commits_tarefa)"')" "5/1"
eq "fora_da_lista vazia"              "$(campo '.fora_da_lista|length')" "0"

echo "== (d) sem commit de metadados: todo commit não-docs conta como tarefa"
R=$(repo d); plano "$R" 'files_modified:
  - src/a.py'
commit "$R" 'feat(7-01): t1' src/a.py
commit "$R" 'docs(7-01): nota' .planning/phases/7-bancada/7-01-SUMMARY.md
commit "$R" 'feat(7-01): t2' src/a.py
commit "$R" 'feat(7-01): t3' src/a.py
roda "$R"
eq "commits_tarefa=3 → ok"            "$(campo '"\(.commits_tarefa)/\(.veredito)"')" "3/ok"

echo "== (e) nenhum commit com a tag → SEM-COMMIT; docs(7) e (01) nus não contam"
R=$(repo e); plano "$R" 'files_modified:
  - src/a.py'
commit "$R" 'docs(7): planos revistos' .planning/ROADMAP.md
commit "$R" 'feat(01): fase antiga com o mesmo número' src/velho.py
commit "$R" 'feat(7-010): outro plano' src/outro.py
roda "$R"
eq "codigos = [SEM-COMMIT], commits=0" "$(campo '"\(.codigos[0])/\(.commits)"')" "SEM-COMMIT/0"
eq "e o arquivo da fase antiga não vira FORA-DA-LISTA" "$(campo '.fora_da_lista|length')" "0"

echo "== (f) files_modified vazio → LISTA-VAZIA (caso 24-02)"
R=$(repo f); plano "$R" 'files_modified: []'
commit "$R" 'feat(7-01): t1' src/a.py
commit "$R" 'feat(7-01): t2' src/a.py
commit "$R" 'feat(7-01): t3' src/a.py
roda "$R"
eq "codigos = LISTA-VAZIA + FORA-DA-LISTA" "$(campo '.codigos|join(",")')" "LISTA-VAZIA,FORA-DA-LISTA"

echo "== (g) checkpoint não é tarefa; lista inline e files_deleted valem"
R=$(repo g); plano "$R" 'files_modified: [src/a.py, "src/b.py"]
files_deleted:
  - src/morto.py' '<task type="auto">a</task>
<task type="checkpoint:human-verify" gate="blocking-human">x</task>
<task type="auto">b</task>'
commit "$R" 'chore(7-01): nasce o morto' src/morto.py
git -C "$R" rm -q src/morto.py; git -C "$R" commit -qm 'feat(7-01): t1 apaga o morto'
commit "$R" 'feat(7-01): t2' src/a.py src/b.py
roda "$R"
eq "tasks=2 (checkpoint fora)"        "$(campo .tasks)" "2"
eq "veredito ok"                      "$(campo .veredito)" "ok"

echo "== (i) C7: PLAN cita D-NN que o SUMMARY não cita → DECISAO-SEM-SUMMARY (informativo, veredito intocado)"
ctx() { # <root> → 7-CONTEXT.md com D-01..D-03, D-03 informational
  printf '<decisions>\n## Implementation Decisions\n\n### A\n- **D-01 [auto, R1]:** a\n- **D-02 [auto, R1]:** b\n- **D-03 [pre-spec:PS-01, informational]:** ver SPEC\n\n### Claude'"'"'s Discretion\n- nada\n\n</decisions>\n' > "$1/.planning/phases/7-bancada/7-CONTEXT.md"
}
R=$(repo i); plano "$R" 'files_modified:
  - src/a.py'; ctx "$R"
commit "$R" 'feat(7-01): t1 per D-01' src/a.py
commit "$R" 'feat(7-01): t2' src/a.py
commit "$R" 'feat(7-01): t3' src/a.py
printf -- '---\nphase: 7\nplan: 01\n---\n## Tasks\n- honra D-01, D-02 e D-03 (ver PLAN)\n' > "$R/.planning/phases/7-bancada/7-01-PLAN.md.tmp"
{ cat "$R/.planning/phases/7-bancada/7-01-PLAN.md"; printf '\nImplement per D-01 and per D-02; D-03 is the SPEC pointer.\n'; } > "$R/.planning/phases/7-bancada/7-01-PLAN.md.new"; mv "$R/.planning/phases/7-bancada/7-01-PLAN.md.new" "$R/.planning/phases/7-bancada/7-01-PLAN.md"; rm -f "$R/.planning/phases/7-bancada/7-01-PLAN.md.tmp"
printf -- '---\nphase: 7\nplan: 01\ndecisions-honored: [D-01]\n---\n# Summary\nHonrou D-01.\n' > "$R/.planning/phases/7-bancada/7-01-SUMMARY.md"
roda "$R"
eq "veredito ok (informativo não reprova), exit 0" "$(campo .veredito)/$rc" "ok/0"
eq "codigos vazio"                                  "$(campo '.codigos|length')" "0"
eq "informativos = DECISAO-SEM-SUMMARY (D-02)"      "$(campo '.informativos[0]')" "DECISAO-SEM-SUMMARY (D-02)"
eq "decisoes.faltantes = [D-02] (D-03 informational sai da conta)" "$(campo '.decisoes.faltantes|join(",")')" "D-02"
eq "decisoes.informational = [D-03]"                "$(campo '.decisoes.informational|join(",")')" "D-03"
eq "decisoes.plan = D-01,D-02,D-03 · summary = D-01" "$(campo '"\(.decisoes.plan|join(","))/\(.decisoes.summary|join(","))"')" "D-01,D-02,D-03/D-01"
# sem o filtro de informational a D-03 também faltaria — provado pela contagem bruta
eq "sem o filtro, faltariam 2 (D-02, D-03): o filtro é o que faz a diferença" \
   "$(campo '(.decisoes.plan - .decisoes.summary) | length')" "2"
# SUMMARY passa a citar as duas → limpo
printf -- '---\nphase: 7\nplan: 01\ndecisions-honored: [D-01, D-02]\n---\n# Summary\n' > "$R/.planning/phases/7-bancada/7-01-SUMMARY.md"
roda "$R"
eq "SUMMARY com decisions-honored: [D-01, D-02] → informativos vazio" "$(campo '.informativos|length')" "0"
echo "== (j) C7: sem SUMMARY ou sem CONTEXT → n/a"
rm -f "$R/.planning/phases/7-bancada/7-01-SUMMARY.md"; roda "$R"
eq "sem SUMMARY → decisoes.estado n/a, informativos vazio" "$(campo '"\(.decisoes.estado)/\(.informativos|length)"')" "n/a/0"
R=$(repo j); plano "$R" 'files_modified:
  - src/a.py'
commit "$R" 'feat(7-01): t1' src/a.py; commit "$R" 'feat(7-01): t2' src/a.py; commit "$R" 'feat(7-01): t3' src/a.py
printf -- '# Summary\n' > "$R/.planning/phases/7-bancada/7-01-SUMMARY.md"
roda "$R"
eq "sem CONTEXT → n/a (o filtro de informational precisa dele)" "$(campo '.decisoes.estado')" "n/a"

echo "== (h) uso inválido → exit 2"
"$SCRIPT" >/dev/null 2>&1; eq "sem argumentos" "$?" "2"
"$SCRIPT" "$TMP/a/.planning/phases/7-bancada" 7-99 >/dev/null 2>&1; eq "PLAN inexistente" "$?" "2"
"$SCRIPT" "$TMP/nao-existe" 7-01 >/dev/null 2>&1; eq "phase_dir inexistente" "$?" "2"

echo "--------------------------------------------------"
[ "$falhas" -eq 0 ] && echo "test-confere-plano.sh: verde" || echo "test-confere-plano.sh: $falhas falha(s)"
[ "$falhas" -eq 0 ]
