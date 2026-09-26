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

echo "== F4RLR.A3 — modo evidencia leva a evidência dura e deixa o temporário de fora (FM-06INT)"
D="$TMP/evid"; repo_de_mentira "$D"
mkdir -p "$D/fase/.intent/runs/c1" "$D/fase/pareceres" "$D/.planning"
echo selo   > "$D/fase/.intent/.correcoes-c1.aplicado"
echo verd   > "$D/fase/.intent/.vereditos-c1.txt"
echo esp    > "$D/fase/.intent/runs/c1/espelho-agy.json"
echo ruido  > "$D/fase/.intent/agy.log"
echo tmp    > "$D/fase/.intent/.tmp-parecer-agy.md"
echo par    > "$D/fase/pareceres/99-planrev-parecer-codex-c1.md"
echo ok     > "$D/fase/.fence-4.1.ok"
echo '{}'   > "$D/fase/99-RUN-LOG.jsonl"
echo div    > "$D/fase/deferred-items.md"
echo dec    > "$D/fase/99-DECISOES.md"
saida=$(cd "$D" && bash "$SCRIPT" "$D/fase" 99 evidencia 2>&1); rc=$?
[ "$rc" = 0 ] && ok "modo evidencia: exit 0" || erro "esperado exit 0, veio $rc" "$saida"
vivos=$(git -C "$D" ls-files)
faltou=""
for esperado_f in \
  'fase/.intent/.correcoes-c1.aplicado' 'fase/.intent/.vereditos-c1.txt' \
  'fase/.intent/runs/c1/espelho-agy.json' 'fase/pareceres/99-planrev-parecer-codex-c1.md' \
  'fase/.fence-4.1.ok' 'fase/99-RUN-LOG.jsonl' 'fase/deferred-items.md' 'fase/99-DECISOES.md'; do
  printf '%s\n' "$vivos" | grep -qxF "$esperado_f" || faltou="$faltou $esperado_f"
done
[ -z "$faltou" ] && ok "selos, vereditos, espelhos, atestado, run-log, dívidas e decisões entraram" \
  || erro "evidência dura ficou fora do commit" "faltou:$faltou"
printf '%s\n' "$vivos" | grep -q 'tmp-parecer\|agy\.log' \
  && erro "temporário (.tmp-parecer-*/.log) entrou na evidência" "$vivos" \
  || ok "temporários (.tmp-parecer-*, .log) ficaram de fora"

echo "== t59 FM-F27INS-01ENC — modo evidencia: trava de gate fica de fora; exclusão órfã da trava antiga entra"
DT="$TMP/trava"; repo_de_mentira "$DT"
PDT="$DT/.planning/phases/27-x"
mkdir -p "$PDT/.gad/gates" "$PDT/.gad/intent"
echo 'go-and-do: formato 2' > "$PDT/.gad/FORMATO"
echo '{"etapa":"2"}' > "$PDT/.gad/gates/2.json"            # trava que a v2.10.1 commitou
git -C "$DT" add -f "$PDT/.gad/gates/2.json" && git -C "$DT" commit -qm "v2.10.1 commitou a trava"
rm -f "$PDT/.gad/gates/2.json"                              # o pass apagou → «D» órfão
echo '{"etapa":"4.1"}' > "$PDT/.gad/gates/4.1.json"        # trava viva no caminho antigo
echo '$ pytest' > "$PDT/.gad/gates/4.1-evidencia.txt"       # evidência de gate: É evidência
echo v > "$PDT/.gad/intent/vereditos.txt"
saida=$(cd "$DT" && bash "$SCRIPT" "$PDT" 27 evidencia 2>&1); rc=$?
[ "$rc" = 0 ] && ok "modo evidencia: exit 0" || erro "esperado exit 0, veio $rc" "$saida"
vivos=$(git -C "$DT" ls-files)
printf '%s\n' "$vivos" | grep -q 'gates/4.1.json' && erro "a trava viva entrou no commit de evidência" "$vivos" \
  || ok "trava de gate (gates/*.json) fica fora do commit de evidência"
printf '%s\n' "$vivos" | grep -q 'gates/4.1-evidencia.txt' && ok "evidência de gate (gates/*-evidencia.txt) entra" \
  || erro "evidência de gate ficou de fora" "$vivos"
git -C "$DT" status --porcelain | grep -q '^ D.*gates/2.json' \
  && erro "exclusão órfã da trava antiga continua pendurada" "$(git -C "$DT" status --porcelain)" \
  || ok "exclusão da trava antiga entrou no commit (sem «D» órfão)"

echo "== modo desconhecido segue reprovando"
saida=$(cd "$D" && bash "$SCRIPT" "$D/fase" 99 xpto 2>&1); rc=$?
[ "$rc" = 2 ] && printf '%s' "$saida" | grep -q 'uat|runlog|intencao' \
  && ok "modo desconhecido → exit 2 com a lista atualizada" || erro "esperado exit 2" "rc=$rc $saida"

echo
[ "$falhas" -eq 0 ] && echo "test-commita-artefatos: TUDO OK" || echo "test-commita-artefatos: $falhas falha(s)"
[ "$falhas" -eq 0 ]
