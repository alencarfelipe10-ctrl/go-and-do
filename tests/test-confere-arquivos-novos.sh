#!/usr/bin/env bash
# test-confere-arquivos-novos.sh — bancada do confere-arquivos-novos.sh (46 n, item P-07
# da rodada de consertos da F24.5). Fixtures controladas (mktemp + git init); nenhum
# projeto real é tocado.
#   bash tests/test-confere-arquivos-novos.sh
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
RAIZ="$(dirname -- "$AQUI")"
SCRIPT="$RAIZ/skills/go-and-do/scripts/confere-arquivos-novos.sh"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 1; }
command -v jq >/dev/null || { echo "jq ausente"; exit 1; }

OK=0; FALHAS=0
ok()    { OK=$((OK+1));      printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }

BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

monta() { # <nome> <linhas de files_modified...> → ecoa a raiz do projeto
  local nome="$1"; shift
  local r="$BASE/$nome"; local pd="$r/.planning/phases/24-t"
  mkdir -p "$pd" "$r/src" "$r/tests"
  printf 'ja-existe\n' > "$r/src/existente.py"
  G "$r" init -q
  { echo '---'; echo 'files_modified:'; for l in "$@"; do echo "  - $l"; done; echo '---'; echo corpo; } > "$pd/24-01-PLAN.md"
  G "$r" add -A >/dev/null 2>&1; G "$r" commit -qm base >/dev/null 2>&1
  printf '%s\n' "$r"
}
roda() { bash "$SCRIPT" "$1/.planning/phases/24-t" "$1" "${@:2}"; }

echo "── 46n: baldes e veredito ──"
R="$(monta caso1 src/existente.py src/novo.py tests/test_novo.py .planning/NOTA.md)"
J="$(roda "$R")"; RC=$?
eq "exit 0 (insumo, não cancela)" "$RC" 0
eq "arquivo novo de produção → mapper_obrigatorio" "$(jq -r .veredito <<<"$J")" mapper_obrigatorio
eq "código ARQUIVO-NOVO-DE-PRODUCAO" "$(jq -r '.codigos[0]' <<<"$J")" ARQUIVO-NOVO-DE-PRODUCAO
eq "só o arquivo novo de produção no balde de produção" "$(jq -c .novos_producao <<<"$J")" '["src/novo.py"]'
eq "teste novo vai para o balde de teste (decisão do dono: não obriga o mapper)" \
   "$(jq -c .novos_teste <<<"$J")" '["tests/test_novo.py"]'
eq ".planning/ nunca conta como produção" "$(jq -c .novos_planning <<<"$J")" '[".planning/NOTA.md"]'
eq "arquivo já existente no ref não aparece em balde nenhum" \
   "$(jq '[.novos_producao,.novos_teste,.novos_planning]|flatten|map(select(.=="src/existente.py"))|length' <<<"$J")" 0

echo "── só teste novo → mapper_opcional ──"
R="$(monta caso2 src/existente.py tests/test_a.py spec/b_test.py x/c.test.js)"
J="$(roda "$R")"
eq "nenhum arquivo novo de produção → mapper_opcional" "$(jq -r .veredito <<<"$J")" mapper_opcional
eq "codigos vazio" "$(jq -c .codigos <<<"$J")" '[]'
eq "os 3 caminhos de teste (tests/, spec/, basename *.test.*) no balde de teste" \
   "$(jq '.novos_teste|length' <<<"$J")" 3

echo "── fase sem PLAN.md ──"
R="$(monta caso3 src/existente.py)"; rm -f "$R/.planning/phases/24-t/24-01-PLAN.md"
J="$(roda "$R")"; RC=$?
eq "sem PLAN.md → exit 0" "$RC" 0
eq "sem PLAN.md → planos 0" "$(jq -r .planos <<<"$J")" 0
eq "sem PLAN.md → declarados 0" "$(jq -r .declarados <<<"$J")" 0
eq "sem PLAN.md → mapper_opcional" "$(jq -r .veredito <<<"$J")" mapper_opcional

echo "── PLAN.md sem bloco files_modified ──"
R="$(monta caso4 src/existente.py)"
printf -- '---\ntitulo: x\n---\ncorpo\n' > "$R/.planning/phases/24-t/24-01-PLAN.md"
J="$(roda "$R")"
eq "sem bloco files_modified → declarados 0, mapper_opcional" \
   "$(jq -r '"\(.declarados)/\(.veredito)"' <<<"$J")" "0/mapper_opcional"

echo "── --ref: fase já executada ──"
R="$(monta caso5 src/existente.py src/novo.py)"
BASE_REF="$(G "$R" rev-parse HEAD)"
printf 'agora existe\n' > "$R/src/novo.py"; G "$R" add -A >/dev/null 2>&1; G "$R" commit -qm exec >/dev/null 2>&1
eq "--ref HEAD depois da execução → mapper_opcional" "$(roda "$R" | jq -r .veredito)" mapper_opcional
eq "--ref no commit anterior → mapper_obrigatorio (é o que dá sentido à flag)" \
   "$(roda "$R" --ref "$BASE_REF" | jq -r .veredito)" mapper_obrigatorio

echo "── fora de repositório git: lado seguro ──"
R="$(monta caso6 src/existente.py src/novo.py)"; rm -rf "$R/.git"
J="$(roda "$R")"; RC=$?
eq "sem git → exit 0 (não quebra)" "$RC" 0
eq "sem git → tudo vira novo, empurrando para rodar o mapper (lado seguro)" \
   "$(jq -r .veredito <<<"$J")" mapper_obrigatorio

echo "── frontmatter «sujo»: linha em branco e comentário indentado dentro do bloco ──"
R="$(monta caso7 src/existente.py)"
printf -- '---\nfiles_modified:\n  - src/novo.py\n\n  # comentario indentado\n  - src/outro.py\noutra_chave: x\n  - src/fora.py\n---\n' \
  > "$R/.planning/phases/24-t/24-01-PLAN.md"
J="$(roda "$R")"
eq "linha em branco e comentário não fecham o bloco; chave nova fecha" \
   "$(jq -c .novos_producao <<<"$J")" '["src/novo.py","src/outro.py"]'

echo "── uso inválido ──"
bash "$SCRIPT" /nao/existe /tambem/nao >/dev/null 2>&1; eq "argumentos inválidos → exit 2" "$?" 2

echo
TOTAL=$((OK + FALHAS))
printf '%s testes, %s verdes, %s vermelhos\n' "$TOTAL" "$OK" "$FALHAS"
[ "$FALHAS" = 0 ]
