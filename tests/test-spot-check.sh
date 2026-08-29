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
for f in tres-formas.md intervalo.md; do
  sed "s|@@ABS@@|$TMP|g" "$FIX/$f" > "$TMP/$f"
done
cp "$FIX/sem-links.md" "$TMP/sem-links.md"

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

echo "test-spot-check.sh: $falhas falha(s)"
[ "$falhas" -eq 0 ]
