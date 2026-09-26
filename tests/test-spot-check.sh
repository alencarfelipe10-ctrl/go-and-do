#!/usr/bin/env bash
# test-spot-check.sh — suíte do R9 (normalização de links markdown no spot-check-ponteiros.sh).
# Régua: [texto](alvo) vale pelo ALVO; o texto nunca vira uma segunda referência.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/spot-check-ponteiros.sh"
FIX="$AQUI/fixtures/spot-check"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-spot-check-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0

ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

# Materializa as fixtures com o caminho absoluto real da árvore de teste.
cp "$FIX/x.py" "$TMP/x.py"
for f in tres-formas.md intervalo.md deslocamento.md; do
  sed "s|@@ABS@@|$TMP|g" "$FIX/$f" > "$TMP/$f"
done
cp "$FIX/sem-links.md" "$TMP/sem-links.md"
for f in desloc-ship.py desloc-conftest.py no-desloc.py bat-paraphrase.py; do
  cp "$FIX/$f" "$TMP/$f"
done

# --- 1. Três formas do mesmo alvo -------------------------------------------
saida=$("$SCRIPT" "$TMP/tres-formas.md" "$TMP")
esperado="referencias_vistas=3 · alvos_unicos=1 · OK 1/1"
if [ "$saida" = "$esperado" ]; then
  ok "3 formas do mesmo alvo → $esperado (0 MISSING-FILE)"
else
  erro "3 formas do mesmo alvo" "esperado: $esperado
obtido:   $saida"
fi

# --- 2. Sem links markdown: comportamento idêntico ao de antes do R9 ---------
saida=$("$SCRIPT" "$TMP/sem-links.md" "$TMP")
quebrados=$(echo "$saida" | grep -E '^MISSING-' | sort)
esperado_q="MISSING-FILE naoexiste.py:3
MISSING-LINE x.py:999 (arquivo tem 20 linhas)"
if [ "$quebrados" = "$esperado_q" ]; then
  ok "sem links: as linhas de ponteiro quebrado são as de sempre"
else
  erro "sem links: linhas quebradas" "esperado:
$esperado_q
obtido:
$quebrados"
fi
sumario=$(echo "$saida" | tail -1)
if [ "$sumario" = "referencias_vistas=4 · alvos_unicos=3 · OK 1/3" ]; then
  ok "sem links: alvos_unicos/OK reproduzem o total e o OK antigos (3 e 1/3)"
else
  erro "sem links: sumário" "obtido: $sumario"
fi

# --- 3. Âncora de intervalo e alvo sem linha --------------------------------
saida=$("$SCRIPT" "$TMP/intervalo.md" "$TMP")
if ! echo "$saida" | grep -q '^MISSING-'; then
  ok "#L5-L9 → :5 e alvo sem linha herda a linha do texto (0 quebrados)"
else
  erro "intervalo/alvo sem linha" "$saida"
fi
if echo "$saida" | tail -1 | grep -q 'referencias_vistas=2 · alvos_unicos=2'; then
  ok "intervalo: 2 referências, 2 alvos"
else
  erro "intervalo: contagem" "$(echo "$saida" | tail -1)"
fi

# --- 4. Regressão: o TEXTO do link não vira ponteiro relativo ----------------
cat > "$TMP/texto-nao-conta.md" <<MD
Ver [\`capability-registry.cjs:2485-2488\`](file://$TMP/x.py#L5-L9).
MD
saida=$("$SCRIPT" "$TMP/texto-nao-conta.md" "$TMP")
if ! echo "$saida" | grep -q 'capability-registry'; then
  ok "texto do link suprimido (nenhum MISSING-FILE falso de capability-registry.cjs)"
else
  erro "texto do link não foi suprimido" "$saida"
fi

# --- 5. Link http(s) com âncora não vira ponteiro relativo ------------------
cp "$FIX/url-http.md" "$TMP/url-http.md"
saida=$("$SCRIPT" "$TMP/url-http.md" "$TMP")
if ! echo "$saida" | grep -q '^MISSING-'; then
  ok "permalink https://…#L12 ignorado (não vira caminho relativo)"
else
  erro "permalink https ignorado" "$saida"
fi

# --- 6. FM-F4RLR-12INT: sem root explícito, resolve pela RAIZ DO REPO, não pelo cwd ---
REPO="$TMP/repo-fake"; mkdir -p "$REPO/sub/mais-fundo"
git -C "$REPO" init -q
cp "$FIX/x.py" "$REPO/x.py"
printf 'Ver x.py:5 para o detalhe.\n' > "$REPO/sub/doc.md"
saida=$(cd "$REPO/sub/mais-fundo" && "$SCRIPT" "../doc.md")
if ! echo "$saida" | grep -q '^MISSING-FILE'; then
  ok "sem root: resolve x.py pela raiz do repo, mesmo chamado de subpasta funda"
else
  erro "sem root não resolveu pela raiz do repo" "$saida"
fi

# --- 7. FM-F27INS-03PLAN (t59/L13): DESLOCAMENTO de conteúdo, molde do 27-REVIEWS.md ---
saida=$("$SCRIPT" "$TMP/deslocamento.md" "$TMP")

if echo "$saida" | grep -qF "DESLOCADO $TMP/desloc-ship.py:3 -> linha real 4 (\"VIRTUAL_ENV\")"; then
  ok "ship.py: citação na linha errada (3), literal só bate na linha real (4)"
else
  erro "deslocamento ship.py não detectado" "$saida"
fi

if echo "$saida" | grep -qF "DESLOCADO $TMP/desloc-conftest.py:3 -> linha real 5 (\"senha-de-teste\")"; then
  ok "conftest.py: :3 e :8 no mesmo trecho — :3 deslocado para :5"
else
  erro "deslocamento conftest.py (:3) não detectado" "$saida"
fi

if echo "$saida" | grep -qF "$TMP/desloc-conftest.py:8"; then
  erro "conftest.py: :8 confere direto — não deveria aparecer como DESLOCADO" "$saida"
else
  ok "conftest.py: :8 confere direto (admin na própria linha) — sem aviso"
fi

if echo "$saida" | grep -qF "$TMP/no-desloc.py"; then
  erro "no-desloc.py: literal bate na própria linha — não deveria disparar" "$saida"
else
  ok "no-desloc.py: literal na própria linha — nenhum DESLOCADO (controle negativo)"
fi

if echo "$saida" | grep -qF "$TMP/bat-paraphrase.py"; then
  erro "bat-paraphrase.py: literal é paráfrase, não deveria ter casado" "$saida"
else
  ok "bat-paraphrase.py: literal parafraseado (não verbatim) — script fica em silêncio, não inventa aviso"
fi

deslocados=$(echo "$saida" | grep -c '^DESLOCADO ')
if [ "$deslocados" -eq 2 ]; then
  ok "exatamente 2 DESLOCADO (ship + conftest:3); conftest:8/no-desloc/bat-paraphrase não contam"
else
  erro "contagem de DESLOCADO" "esperado 2, obtido $deslocados
$saida"
fi

if echo "$saida" | tail -1 | grep -qF '· deslocados=2'; then
  ok "sumário ganha «· deslocados=2» só quando há deslocamento"
else
  erro "sumário sem «deslocados=2»" "$(echo "$saida" | tail -1)"
fi

# --- 8. Sem deslocamento no documento: sumário NÃO ganha o sufixo (superconjunto) ---
saida=$("$SCRIPT" "$TMP/sem-links.md" "$TMP")
if echo "$saida" | tail -1 | grep -q 'deslocados='; then
  erro "sumário sem deslocamento não deveria citar «deslocados=»" "$(echo "$saida" | tail -1)"
else
  ok "sem deslocamento: sumário idêntico ao de antes (sem sufixo)"
fi

echo "test-spot-check.sh: $falhas falha(s)"
[ "$falhas" -eq 0 ]
