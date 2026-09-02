#!/usr/bin/env bash
# test-varre-worktrees.sh — bancada do varre-worktrees.sh (P16 da rodada F24.4).
#
# Régua: (1) sem flag o script só RELATA; (2) classificação nas 4 classes (limpa,
# com-trabalho, suja, fantasma) num repositório sintético; (3) --arquivar produz patches
# que reaplicam com `git am` num clone novo e o diff da suja aplica; (4) --remover só
# apaga branch com trabalho quando há arquivo conferido, respeita --max e nunca toca a
# raiz; (5) uso inválido é exit 2 — inclusive chamar com uma worktree como --projeto.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/varre-worktrees.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-wt-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }
G() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
classe_de() { printf '%s' "$1" | jq -r --arg b "$2" '.worktrees[] | select(.branch==$b) | .classe'; }
campo_de()  { printf '%s' "$1" | jq -r --arg b "$2" --arg c "$3" '.worktrees[] | select(.branch==$b) | .[$c]'; }

# ── repositório sintético: raiz master + 4 cópias ─────────────────────────────
R="$TMP/repo"; mkdir -p "$R"; G -C "$R" init -q -b master
echo a > "$R/a.txt"; mkdir -p "$R/.planning"; G -C "$R" add -A; G -C "$R" commit -qm "base"
W="$R/.claude/worktrees"
G -C "$R" worktree add -q -b wt-limpa "$W/limpa" master
G -C "$R" worktree add -q -b wt-trabalho "$W/trabalho" master
echo b > "$W/trabalho/b.txt"; G -C "$W/trabalho" add b.txt; G -C "$W/trabalho" commit -qm "feat(x): b"
echo c > "$W/trabalho/c.txt"; G -C "$W/trabalho" add c.txt; G -C "$W/trabalho" commit -qm "feat(x): c"
G -C "$R" worktree add -q -b wt-suja "$W/suja" master
echo sujo >> "$W/suja/a.txt"; echo lixo > "$W/suja/ignorado.tmp"
G -C "$R" worktree add -q -b wt-fantasma "$W/fantasma" master
rm -rf "$W/fantasma"
# a base anda depois das cópias: o merge-base fica atrás do master (caso real da 24.2)
echo a2 > "$R/a2.txt"; G -C "$R" add a2.txt; G -C "$R" commit -qm "master anda"

echo "== uso inválido → exit 2"
saida=$("$SCRIPT" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "sem --projeto → exit 2" || erro "esperado 2, veio $rc" "$saida"
saida=$("$SCRIPT" --projeto "$TMP/nao-existe" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "diretório inexistente → exit 2" || erro "esperado 2, veio $rc" "$saida"
saida=$("$SCRIPT" --projeto "$W/limpa" 2>&1); rc=$?
[ "$rc" = 2 ] && printf '%s' "$saida" | grep -q "worktree, não a cópia principal" \
  && ok "worktree como --projeto → exit 2 (a principal nunca vira candidata)" || erro "aceitou worktree como raiz" "$saida"
saida=$("$SCRIPT" --projeto "$R" --max x 2>&1); rc=$?
[ "$rc" = 2 ] && ok "--max não numérico → exit 2" || erro "esperado 2, veio $rc" "$saida"

echo "== relato: 4 classes, nada tocado"
saida=$("$SCRIPT" --projeto "$R" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "exit 0" || erro "exit $rc" "$saida"
[ "$(printf '%s' "$saida" | jq -r .acao)" = relato ] && ok "acao=relato" || erro "acao errada" "$saida"
[ "$(printf '%s' "$saida" | jq '.worktrees|length')" = 4 ] && ok "4 cópias fora da raiz (raiz não listada)" || erro "contagem" "$saida"
[ "$(classe_de "$saida" wt-limpa)" = limpa ] && ok "limpa" || erro "limpa" "$saida"
[ "$(classe_de "$saida" wt-trabalho)" = com-trabalho ] && [ "$(campo_de "$saida" wt-trabalho commits)" = 2 ] \
  && ok "com-trabalho, 2 commits (base andou; só os da cópia contam)" || erro "com-trabalho" "$saida"
[ "$(classe_de "$saida" wt-suja)" = suja ] && [ "$(campo_de "$saida" wt-suja sujeira)" = 1 ] \
  && [ "$(campo_de "$saida" wt-suja nao_rastreados)" = 1 ] \
  && ok "suja: 1 rastreado modificado; não rastreado contado à parte" || erro "suja" "$saida"
[ "$(classe_de "$saida" wt-fantasma)" = fantasma ] && [ "$(campo_de "$saida" wt-fantasma existe)" = false ] \
  && ok "fantasma (registrada, diretório ausente)" || erro "fantasma" "$saida"
[ "$(G -C "$R" worktree list | wc -l)" = 5 ] && ok "relato não removeu nada" || erro "relato removeu"
[ -f "$R/.planning/.gad/last-varre-worktrees.json" ] && ok "espelho .planning/.gad/last-varre-worktrees.json" || erro "sem espelho"
[ -d "$R/.planning/.gad/worktrees-arquivo" ] && erro "relato criou pasta de arquivo" || ok "relato não arquivou"

echo "== --remover sem arquivo: só a limpa sai; trabalho/suja ficam com motivo"
saida=$("$SCRIPT" --projeto "$R" --remover 2>&1); rc=$?
[ "$(campo_de "$saida" wt-limpa removida)" = true ] && ! G -C "$R" show-ref -q refs/heads/wt-limpa \
  && ok "limpa removida (worktree + branch)" || erro "limpa não removida" "$saida"
[ "$(campo_de "$saida" wt-trabalho removida)" = false ] && [ "$(campo_de "$saida" wt-trabalho motivo)" = sem-arquivo-conferido ] \
  && G -C "$R" show-ref -q refs/heads/wt-trabalho && ok "com-trabalho preservada: sem-arquivo-conferido" || erro "com-trabalho" "$saida"
[ "$(campo_de "$saida" wt-suja removida)" = false ] && [ -d "$W/suja" ] \
  && ok "suja preservada" || erro "suja" "$saida"
[ "$(campo_de "$saida" wt-fantasma removida)" = true ] && ! G -C "$R" show-ref -q refs/heads/wt-fantasma \
  && ok "fantasma (0 commits) podada + branch apagada" || erro "fantasma" "$saida"
[ -d "$R" ] && G -C "$R" rev-parse -q --verify master >/dev/null && ok "raiz e master intactos" || erro "raiz tocada"

echo "== --arquivar: patches + diff + README"
saida=$("$SCRIPT" --projeto "$R" --arquivar 2>&1); rc=$?
A="$R/.planning/.gad/worktrees-arquivo"
[ "$(ls "$A/wt-trabalho"/*.patch 2>/dev/null | wc -l)" = 2 ] && ok "com-trabalho: 2 patches" || erro "patches" "$(ls -R "$A")"
[ -f "$A/wt-trabalho/README.md" ] && grep -q "git am -3" "$A/wt-trabalho/README.md" && ok "README com comando de reaplicação" || erro "README"
[ -s "$A/wt-suja/nao-commitado.diff" ] && grep -q "^+sujo" "$A/wt-suja/nao-commitado.diff" \
  && ! grep -q "ignorado.tmp" "$A/wt-suja/nao-commitado.diff" && ok "suja: nao-commitado.diff só com o rastreado" || erro "diff da suja"
[ "$(campo_de "$saida" wt-trabalho arquivado_em)" = "$A/wt-trabalho" ] && ok "arquivado_em no JSON" || erro "arquivado_em" "$saida"
[ "$(G -C "$R" worktree list | wc -l)" = 3 ] && ok "--arquivar sozinho não remove" || erro "arquivar removeu"
C="$TMP/clone-novo"; G clone -q "$R" "$C"; base=$(G -C "$R" merge-base master wt-trabalho)
G -C "$C" checkout -q --detach "$base" && G -C "$C" am -q "$A/wt-trabalho"/*.patch 2>/dev/null \
  && [ -f "$C/c.txt" ] && ok "patches reaplicam (git am) num clone novo" || erro "git am falhou"
G -C "$C" checkout -q --detach master 2>/dev/null; G -C "$C" apply --check "$A/wt-suja/nao-commitado.diff" \
  && ok "diff da suja aplica (git apply --check)" || erro "diff não aplica"

echo "== --max: teto de remoções por chamada"
saida=$("$SCRIPT" --projeto "$R" --remover --max 1 2>&1); rc=$?
[ "$(printf '%s' "$saida" | jq .removidas)" = 1 ] && printf '%s' "$saida" | jq -r '.worktrees[].motivo' | grep -q "teto-max-1" \
  && ok "--max 1: 1 removida, a outra fica com teto-max-1" || erro "teto" "$saida"
saida=$("$SCRIPT" --projeto "$R" --remover 2>&1); rc=$?
[ "$(G -C "$R" worktree list | wc -l)" = 1 ] && ! G -C "$R" show-ref -q refs/heads/wt-trabalho && ! G -C "$R" show-ref -q refs/heads/wt-suja \
  && ok "2ª chamada: arquivo já conferido → ambas removidas; só a raiz sobra" || erro "remoção final" "$saida"
[ "$(G -C "$R" rev-parse --abbrev-ref HEAD)" = master ] && [ -f "$R/a2.txt" ] && ok "raiz intacta ao fim" || erro "raiz"

echo
if [ "$falhas" -eq 0 ]; then echo "test-varre-worktrees: OK"; else echo "test-varre-worktrees: $falhas falha(s)"; exit 1; fi
