#!/usr/bin/env bash
# test-commita-artefatos.sh — bancada do C4 (git add de diretório inteiro em uat-evidencia/).
#
# Régua: commita-artefatos.sh, modo "uat", só pode adicionar ao índice arquivos de
# uat-evidencia/ cuja extensão é evidência legítima de UAT (.pdf/.png, conferido contra
# uat-playbook.md — browser_save_pdf grava .pdf, browser_screenshot grava .png). Nunca
# .err/.log/.jsonl/.tmp/ocultos, nunca nada fora de uat-evidencia/, e nunca o diretório
# inteiro de uma vez. Teto de segurança: mais de 20 arquivos na seleção → RECUSA, nada
# entra no índice, exit != 0 — falhar visível é melhor que arrastar centenas em silêncio.
#
# Roda contra um repositório git DE MENTIRA criado em mktemp -d (nunca o repo real: este
# teste mexe com o índice git).

set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/commita-artefatos.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-c4-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

# repo_de_mentira <dir> — git init + config + 1 commit inicial, isolado em mktemp.
repo_de_mentira() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email "teste@example.com"
  git -C "$d" config user.name "teste"
  : > "$d/README.md"
  git -C "$d" add README.md
  git -C "$d" commit -qm "commit inicial"
}

echo "== (a) 3 válidos (.pdf/.png) + 2 .log → só os 3 entram no índice"
D="$TMP/a"; repo_de_mentira "$D"
mkdir -p "$D/fase/uat-evidencia"
echo a > "$D/fase/24-UAT.md"
: > "$D/fase/uat-evidencia/cenario-1.pdf"
: > "$D/fase/uat-evidencia/cenario-2.pdf"
: > "$D/fase/uat-evidencia/tela-3.png"
: > "$D/fase/uat-evidencia/debug.log"
: > "$D/fase/uat-evidencia/erro.err"
saida=$(cd "$D" && bash "$SCRIPT" "$D/fase" 24 uat 2>&1); rc=$?
staged=$(git -C "$D" diff --cached --name-only | sort)
esperado=$(printf 'fase/24-UAT.md\nfase/uat-evidencia/cenario-1.pdf\nfase/uat-evidencia/cenario-2.pdf\nfase/uat-evidencia/tela-3.png')
[ "$rc" = 0 ] && ok "exit 0" || erro "esperado exit 0, veio $rc" "$saida"
# o commit já rodou (STATUS=ok) — confere pelo git show em vez do índice (que esvazia após commit)
commitado=$(git -C "$D" show --stat --format= HEAD | sed -n 's/^ \(fase[^ ]*\).*/\1/p' | sort)
[ "$commitado" = "$esperado" ] && ok "commit trouxe só os 3 arquivos válidos + o NN-UAT.md" \
  || erro "commit divergente do esperado" "commitado=[$commitado] esperado=[$esperado]"
git -C "$D" ls-files | grep -q "\.log$\|\.err$" && erro ".log/.err foram parar no repositório" || ok ".log/.err nunca entraram"

echo "== (b) 25 arquivos válidos → recusa, índice vazio, exit != 0"
D="$TMP/b"; repo_de_mentira "$D"
mkdir -p "$D/fase/uat-evidencia"
echo a > "$D/fase/24-UAT.md"
i=1
while [ "$i" -le 25 ]; do : > "$D/fase/uat-evidencia/cenario-$i.pdf"; i=$((i+1)); done
saida=$(cd "$D" && bash "$SCRIPT" "$D/fase" 24 uat 2>&1); rc=$?
printf '%s' "$saida" | grep -q "RECUSA: uat-evidencia com 25 arquivos — acima do teto de 20; selecione à mão" \
  && ok "mensagem de recusa com a contagem certa" || erro "mensagem de recusa ausente/errada" "$saida"
[ "$rc" != 0 ] && ok "exit != 0 ($rc)" || erro "esperado exit != 0, veio $rc"
staged=$(git -C "$D" diff --cached --name-only)
[ -z "$staged" ] && ok "índice permanece vazio (nem o NN-UAT.md entrou)" || erro "índice não está vazio" "$staged"
[ "$(git -C "$D" log --oneline | wc -l)" = 1 ] && ok "nenhum commit novo foi criado" \
  || erro "um commit indevido foi criado"

echo "== (c) sem uat-evidencia/ → não falha"
D="$TMP/c"; repo_de_mentira "$D"
mkdir -p "$D/fase"
echo a > "$D/fase/24-UAT.md"
saida=$(cd "$D" && bash "$SCRIPT" "$D/fase" 24 uat 2>&1); rc=$?
[ "$rc" = 0 ] && ok "exit 0 sem uat-evidencia/" || erro "esperado exit 0, veio $rc" "$saida"
git -C "$D" show --stat --format= HEAD | grep -q "24-UAT.md" \
  && ok "NN-UAT.md ainda commitado normalmente" || erro "NN-UAT.md não foi commitado" "$saida"

echo "== (d) arquivos ocultos e extensões fora da lista nunca entram, mesmo abaixo do teto"
D="$TMP/d"; repo_de_mentira "$D"
mkdir -p "$D/fase/uat-evidencia"
echo a > "$D/fase/24-UAT.md"
: > "$D/fase/uat-evidencia/cenario-1.pdf"
: > "$D/fase/uat-evidencia/.oculto.pdf"
: > "$D/fase/uat-evidencia/dados.jsonl"
: > "$D/fase/uat-evidencia/tmp.tmp"
saida=$(cd "$D" && bash "$SCRIPT" "$D/fase" 24 uat 2>&1); rc=$?
[ "$rc" = 0 ] && ok "exit 0" || erro "esperado exit 0, veio $rc" "$saida"
commitado=$(git -C "$D" show --stat --format= HEAD | sed -n 's/^ \(fase[^ ]*\).*/\1/p' | sort)
esperado=$(printf 'fase/24-UAT.md\nfase/uat-evidencia/cenario-1.pdf')
[ "$commitado" = "$esperado" ] && ok "só o .pdf visível entrou; oculto/.jsonl/.tmp ficaram de fora" \
  || erro "seleção incorreta" "commitado=[$commitado] esperado=[$esperado]"

echo "== M6 (46 j) — modo `intencao`: aceita parecer NOVO e não absorve worktree sujo"
D="$TMP/m6"; repo_de_mentira "$D"
mkdir -p "$D/fase/pareceres"
echo spec    > "$D/fase/99-SPEC.md"
echo context > "$D/fase/99-CONTEXT.md"
echo review  > "$D/fase/99-INTENT-REVIEW.md"
echo parecer > "$D/fase/pareceres/99-parecer-codex-c1.md"
echo planrev > "$D/fase/pareceres/99-planrev-parecer-codex-c1.md"
echo "sujeira do usuario" > "$D/outro.txt"   # nunca deve entrar
saida=$(cd "$D" && bash "$SCRIPT" "$D/fase" 99 intencao 2>&1); rc=$?
[ "$rc" = 0 ] && ok "modo intencao: exit 0" || erro "esperado 0, veio $rc" "$saida"
commitado=$(git -C "$D" show --name-only --format= HEAD | grep . | sort)
esperado=$(printf 'fase/99-CONTEXT.md\nfase/99-INTENT-REVIEW.md\nfase/99-SPEC.md\nfase/pareceres/99-parecer-codex-c1.md' | sort)
[ "$commitado" = "$esperado" ] \
  && ok "commit leva os artefatos + o parecer NOVO da intenção, e só" \
  || erro "seleção divergente" "commitado=[$commitado] esperado=[$esperado]"
git -C "$D" ls-files | grep -q '^outro.txt$' && erro "absorveu o worktree sujo do usuário" \
  || ok "worktree sujo do usuário não entrou"
git -C "$D" ls-files | grep -q 'planrev' && erro "parecer da convergência entrou no commit da intenção" \
  || ok 'parecer planrev- (convergência) fica de fora'
printf '%s' "$saida" | grep -q '"modo":"intencao"' && ok "JSON de saída declara o modo" \
  || erro "JSON sem o modo" "$saida"

echo "== M6 — modo intencao sem pareceres/ (consultoria pulada)"
D="$TMP/m6b"; repo_de_mentira "$D"
mkdir -p "$D/fase"
echo spec > "$D/fase/99-SPEC.md"
saida=$(cd "$D" && bash "$SCRIPT" "$D/fase" 99 intencao 2>&1); rc=$?
[ "$rc" = 0 ] && ok "sem pareceres/: exit 0" || erro "esperado 0, veio $rc" "$saida"
git -C "$D" show --stat --format= HEAD | grep -q '99-SPEC.md' \
  && ok "commit leva só os artefatos existentes" || erro "SPEC não entrou" "$saida"

echo "== modo desconhecido segue reprovando"
saida=$(cd "$D" && bash "$SCRIPT" "$D/fase" 99 xpto 2>&1); rc=$?
[ "$rc" = 2 ] && printf '%s' "$saida" | grep -q 'uat|runlog|intencao' \
  && ok "modo desconhecido → exit 2 com a lista atualizada" || erro "esperado exit 2" "rc=$rc $saida"

echo
[ "$falhas" -eq 0 ] && echo "test-commita-artefatos: TUDO OK" || echo "test-commita-artefatos: $falhas falha(s)"
[ "$falhas" -eq 0 ]
