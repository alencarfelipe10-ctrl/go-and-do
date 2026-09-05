#!/usr/bin/env bash
# test-briefing-build.sh — bancada do gate E2c/R1 e das mudanças R3/R8 do briefing.
#
# Régua: o briefing do ciclo C não nasce sem o laço do ciclo anterior fechado
# (correção → commit → releitura, conferido por blob). E nenhum sino do ciclo 0 some.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/briefing-build.sh"
COMMIT="$AQUI/../skills/go-and-do/scripts/correcoes-commit.sh"
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

REPO=""; PD=""
G() { git -C "$REPO" -c user.name=t -c user.email=t@t.io -c commit.gpgsign=false "$@"; }
RUN()  { ( cd "$REPO" && bash "$SCRIPT" "$@" ); }
RUNC() { ( cd "$REPO" && bash "$COMMIT" "$@" ); }

monta_repo() {
  REPO=$(mktemp -d "${TMPDIR:-/tmp}/gad-brief-XXXXXX")
  PD="$REPO/.planning/phases/24.3-fase"
  mkdir -p "$PD/.intent" "$REPO/.planning"
  git -c init.defaultBranch=main init -q "$REPO"
  cat > "$REPO/.planning/ROADMAP.md" <<'EOF'
# Roadmap

### Phase 24.2: fase anterior

Texto da fase anterior que NÃO deve entrar no briefing.
Mais uma linha da anterior.

### Phase 24.3: atribuicao de receita

Entrada desta fase — esta é a que entra.

### Phase 24.4: fase seguinte

Texto da fase seguinte que NÃO deve entrar no briefing.
EOF
  cat > "$REPO/.planning/LICOES-DE-INTENCAO.md" <<'EOF'
# Lições
- Lição 1: não confiar em contagem autorreportada.
- Lição 2: gate cego reportando verde é pior que gate ausente.
EOF
  echo "req base" > "$REPO/.planning/REQUIREMENTS.md"
  printf '# Spec\n\n## Goal\n\nO Δ Receita da Botafogo vai de −79.349,83 → 0,00 (efeito medido).\n\n## Background\n\nspec base\ndecisao X [auto]\n' > "$PD/24.3-SPEC.md"
  echo "context base"                        > "$PD/24.3-CONTEXT.md"
  echo "review base"                         > "$PD/24.3-INTENT-REVIEW.md"
  G add -A >/dev/null; G commit -qm base >/dev/null
}
limpa() { [ -n "$REPO" ] && rm -rf "$REPO"; }
trap limpa EXIT

# ciclo0 com N correções reais: usa o correcoes-commit.sh para produzir o `.aplicado`
fecha_ciclo0() { # <ids>
  RUNC "$PD" 0 --inicio --artefatos "$PD/24.3-SPEC.md" "$PD/24.3-CONTEXT.md" \
       "$PD/24.3-INTENT-REVIEW.md" >/dev/null 2>&1
  echo "correcao do ciclo 0" >> "$PD/24.3-SPEC.md"
  echo "correcao do ciclo 0" >> "$PD/24.3-CONTEXT.md"
  RUNC "$PD" 0 --ids "$1" --artefatos "$PD/24.3-SPEC.md" "$PD/24.3-CONTEXT.md" \
       "$PD/24.3-INTENT-REVIEW.md" >/dev/null 2>&1
}
releitura_json_de() { # <ciclo> — deriva do .aplicado (é o que o gad-verificador grava, v: 2)
  local c="$1" apl="$PD/.intent/.correcoes-c$1.aplicado"
  local commit; commit=$(jq -r .commit "$apl")
  { printf '{"v":2,"ciclo":%s,"commit":"%s","artefatos":[' "$c" "$commit"
    local first=1 p b
    while IFS= read -r p; do
      b=$(G rev-parse "$commit:$p")
      [ $first = 1 ] || printf ','; first=0
      printf '{"path":"%s","blob":"%s"}' "$p" "$b"
    done < <(jq -r '.caminhos[]' "$apl")
    printf '],"contradiz":[],"prescreve_mecanismo":[],"omissoes_novas":[],"cardinalidade":[],"unicidade":[],"consistencia":"ok","ok":true}\n'; }
}

echo "== E2c.1 — c1 sem .ciclo0.json → exit 4"
monta_repo
RUN "$PD" 24.3 1 >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] && ok "exit 4 sem .ciclo0.json" || erro "esperado 4, veio $rc"
[ -f "$PD/.intent/.prova-leitura-c1.txt" ] && erro "gate reprovado queimou o nonce" \
  || ok "gate roda ANTES do nonce (nenhuma prova-leitura escrita)"

echo "== E2c.2 — .ciclo0.json = {} → exit 4 (existência não basta)"
echo '{}' > "$PD/.intent/.ciclo0.json"
RUN "$PD" 24.3 1 >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] && ok "exit 4 com {} (chaves faltando)" || erro "esperado 4, veio $rc"

echo "== E2c.3 — ciclo 0 sem correção: arrays vazios EXPLÍCITOS passam"
echo '{"v":1,"sinos":[],"correcoes":[],"releitura":{"commit":"","artefatos":[]}}' \
  > "$PD/.intent/.ciclo0.json"
RUN "$PD" 24.3 1 >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] && ok "ainda exit 4 sem .releitura-c0.done" || erro "esperado 4, veio $rc"
: > "$PD/.intent/.releitura-c0.done"
saida=$(RUN "$PD" 24.3 1 2>&1); rc=$?
[ "$rc" = 0 ] && ok "passa com arrays vazios + .releitura-c0.done" || erro "esperado 0, veio $rc" "$saida"
printf '%s' "$saida" | jq -e '.avisos[]? | select(test("0 correções"))' >/dev/null \
  && ok "declaração de ciclo 0 vazio aparece nos avisos (auditável)" || erro "vazio silencioso"
printf '%s' "$saida" | jq -e '.gate.avisos[]? | select(test("releitura c0 em formato legado"))' >/dev/null \
  && ok "R9: releitura sem \`v\` é aceita como legado, com aviso nomeado" || erro "legado da releitura silencioso" "$saida"

echo "== R1 (plano 3) — Goal do SPEC no briefing, verbatim; SPEC sem Goal avisa e não falha"
BRF="$PD/.intent/briefing-c1.md"
grep -q '^## Goal desta fase' "$BRF" && ok "seção 'Goal desta fase' presente" || erro "Goal ausente do briefing"
sed -n '/^## Goal desta fase/,/^## Artefatos/p' "$BRF" | grep -q '−79.349,83' \
  && ok "o texto do Goal chega verbatim (o efeito medido está lá)" || erro "Goal não veio verbatim"
grep -q 'vinculo_goal' "$BRF" && ok "a Missão pede a linha \`vinculo_goal:\` por achado" || erro "vinculo_goal ausente"
grep -q 'vinculo_goal: nenhum' "$BRF" && ok "…e diz o que acontece com o achado sem vínculo (dívida, não ciclo)" || erro "destino do sem-vínculo ausente"
grep -q 'nenhum achado, de nenhuma categoria, é um resultado' "$BRF" && ok "licença de zero cobre o parecer inteiro" || erro "licença de zero antiga"
grep -q '### Achado 0 — nenhum achado novo' "$BRF" && ok "literal grepado \`### Achado 0\` intacto" || erro "literal Achado 0 sumiu"
cp "$PD/24.3-SPEC.md" "$PD/24.3-SPEC.md.bak"; sed -i '/^## Goal/,/^## Background/{/^## Background/!d}' "$PD/24.3-SPEC.md"
saida=$(RUN "$PD" 24.3 1 2>&1); rc=$?
[ "$rc" = 0 ] && ok "SPEC sem \`## Goal\` não falha" || erro "SPEC sem Goal derrubou o build (rc=$rc)" "$saida"
printf '%s' "$saida" | jq -e '.avisos[]? | select(test("sem seção"))' >/dev/null && ok "…e avisa" || erro "SPEC sem Goal em silêncio" "$saida"
grep -q '^## Goal desta fase' "$BRF" && erro "seção Goal impressa vazia" || ok "sem Goal, a seção não é impressa"
mv -f "$PD/24.3-SPEC.md.bak" "$PD/24.3-SPEC.md"; RUN "$PD" 24.3 1 >/dev/null 2>&1

echo "== R5 (plano 3) — obrigação do ciclo 1 e as três perguntas do montante"
grep -q '^## Obrigação do ciclo 1' "$BRF" && ok "seção 'Obrigação do ciclo 1' presente no c1" || erro "obrigação ausente"
grep -q 'SPEC × REQUIREMENTS' "$BRF" && ok "sem PRE-SPEC, o item 1 é a forma REQUIREMENTS" || erro "forma REQUIREMENTS ausente"
grep -q 'SPEC × régua do PRE-SPEC' "$BRF" && erro "forma PRE-SPEC apareceu sem PRE-SPEC" || ok "forma PRE-SPEC não aparece sem o arquivo"
printf 'pre-spec\n' > "$PD/24.3-PRE-SPEC.md"; RUN "$PD" 24.3 1 >/dev/null 2>&1
grep -q 'SPEC × régua do PRE-SPEC' "$BRF" && ok "com PRE-SPEC, o item 1 cita o PRE-SPEC como objeto" || erro "forma PRE-SPEC ausente"
grep -q 'não a ataque como' "$BRF" && ok "o bloco [pre-spec] (decisão tem dono) continua" || erro "bloco [pre-spec] sumiu"
rm -f "$PD/24.3-PRE-SPEC.md"; RUN "$PD" 24.3 1 >/dev/null 2>&1
qids=$(jq -cr '.qids|join(",")' "$PD/.intent/.perguntas-c1.json")
[ "$qids" = "Q1,Q2,Q3,Q4,Q5,Q6" ] && ok "c1 sem correção: Q1–Q3 canônicas + Q4–Q6 do montante" || erro "manifesto" "$qids"
[ "$(jq -r '.detalhe[3].tipo,.detalhe[4].tipo,.detalhe[5].tipo' "$PD/.intent/.perguntas-c1.json" | paste -sd,)" = "montante_prespec,montante_context,montante_conjunto" ] \
  && ok "tipos das três Q do montante no manifesto" || erro "tipos do montante"
grep -q '^- \*\*Q4\*\* (SPEC × régua a montante)' "$BRF" && ok "o texto das Q interpola o qid atribuído (Q4), não número à mão" || erro "Q4 do montante não interpolada" "$(grep -n 'régua a montante' "$BRF")"

echo "== E2c.4 — sinos:[] com .sinos-spec.txt cheio → exit 4 (R3: nenhum sino some)"
echo "sino do spec" > "$PD/.intent/.sinos-spec.txt"
RUN "$PD" 24.3 1 >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] && ok "exit 4 (sinos declarados vazios com sino no disco)" || erro "esperado 4, veio $rc"
rm -f "$PD/.intent/.sinos-spec.txt"
# plano 2 (C5) × anti-cegueira: `leitura_propria:` é evidência de auditoria, não sino
printf 'leitura_propria: src/a.py — a função lê o campo x\nlicao 1: aplicada — ok\n' > "$PD/.intent/.sinos-discuss.txt"
RUN "$PD" 24.3 1 >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok "sinos:[] com .sinos-discuss.txt só de leitura_propria:/licao → passa (não é sino)" || erro "leitura_propria travou o c1 (rc=$rc)"
rm -f "$PD/.intent/.sinos-discuss.txt"

echo "== C4 (plano 2, 05/09/2026) — criterio_nao_fecha: do discuss chega ao briefing do revisor"
# As duas medições que na F24.4 viraram D-13 e D-15, escritas como sino com o prefixo exato.
cat > "$PD/.intent/.sinos-discuss.txt" <<'SINOS'
criterio_nao_fecha: AC-11 — motor reconhece zero linhas para o aluno 616385 (esperado ≥ 1) — uv run python -m src.dre --aluno 616385 --mes 2026-03
criterio_nao_fecha: AC-42 — dois contratos ativos no mês onde o critério só admite um — uv run pytest tests/golden/test_contratos_ativos.py -k 616385
licao 1: aplicada — resposta do checklist, não é sino
SINOS
# o ciclo 0 declara os dois sinos (senão o anti-cegueira do R3 barra o briefing, e com razão)
cp "$PD/.intent/.ciclo0.json" "$PD/.intent/.ciclo0.json.bak"
echo '{"v":1,"sinos":[{"id":"criterio_nao_fecha AC-11","origem":"discuss","disposicao":"aberto"},{"id":"criterio_nao_fecha AC-42","origem":"discuss","disposicao":"aberto"}],"correcoes":[],"releitura":{"commit":"","artefatos":[]}}' \
  > "$PD/.intent/.ciclo0.json"
saida=$(RUN "$PD" 24.3 1 2>&1); rc=$?
[ "$rc" = 0 ] && ok "gate segue passando com o arquivo de sinos do discuss" || erro "esperado 0, veio $rc" "$saida"
BRF4="$PD/.intent/briefing-c1.md"
[ "$(grep -c '^criterio_nao_fecha: AC-' "$BRF4")" = 2 ] && ok "as duas linhas criterio_nao_fecha: aparecem no briefing (seção Sinos de discuss)" || erro "criterio_nao_fecha ausente do briefing" "$(grep -n 'criterio_nao_fecha\|Sinos de' "$BRF4")"
grep -q '^## Sinos de discuss' "$BRF4" && ok "sob o heading '## Sinos de discuss'" || erro "heading dos sinos do discuss"
grep -q 'licao 1: aplicada' "$BRF4" && erro "resposta de lição vazou para o briefing" || ok "a resposta de lição do mesmo arquivo continua fora (R8)"
rm -f "$PD/.intent/.sinos-discuss.txt"; mv -f "$PD/.intent/.ciclo0.json.bak" "$PD/.intent/.ciclo0.json"
RUN "$PD" 24.3 1 >/dev/null 2>&1   # regera o briefing-c1 no estado anterior para os casos R8

echo "== R8 — briefing sem lições, ROADMAP só da fase, Q1–Q3 e manifesto"
BRF="$PD/.intent/briefing-c1.md"
grep -q "LICOES\|Lição 1" "$BRF" && erro "lições continuam no briefing" || ok "lições saíram do briefing"
grep -q "Phase 24.4" "$BRF" && erro "ROADMAP trouxe a fase seguinte" || ok "ROADMAP não traz a fase seguinte"
grep -q "Phase 24.2" "$BRF" && erro "ROADMAP trouxe a fase anterior" || ok "ROADMAP não traz a fase anterior"
grep -q "Entrada desta fase" "$BRF" && ok "ROADMAP traz a entrada da fase" || erro "entrada da fase sumiu"
grep -q "^## Perguntas dirigidas" "$BRF" && ok "seção Perguntas dirigidas presente" || erro "seção ausente"
grep -q "## Respostas dirigidas" "$BRF" && ok "briefing exige a seção de resposta estruturada" || erro "formato de resposta não pedido"
grep -q '### Achado 0 — nenhum achado novo' "$BRF" && ok "briefing documenta o gabarito de zero achados (P15)" || erro "gabarito Achado 0 ausente do briefing"
qids=$(jq -cr '.qids|join(",")' "$PD/.intent/.perguntas-c1.json" 2>/dev/null)
[ "$qids" = "Q1,Q2,Q3,Q4,Q5,Q6" ] && ok "manifesto estável com Q1–Q3 (+ Q4–Q6 do montante no c1)" || erro "manifesto" "$qids"

echo "== R3 — c1 com correção do ciclo 0: revalidação dirigida + sino não corrigido visível"
limpa; monta_repo
fecha_ciclo0 "c0-01"
APL="$PD/.intent/.correcoes-c0.aplicado"
[ -f "$APL" ] || erro "o correcoes-commit.sh não produziu o .aplicado do ciclo 0"
releitura_json_de 0 > "$PD/.intent/.releitura-c0.json"
: > "$PD/.intent/.releitura-c0.done"
COMMIT0=$(jq -r .commit "$APL")
# C1: quem preenche o hash é o correcoes-commit.sh — o `.ciclo0.json` tem de repetir
# o que ele gravou (aqui o ciclo tocou 2 caminhos, então o hash sai vazio e declarado)
H0=$(jq -r '.correcoes[0].hash' "$APL")
jq -n --arg c "$COMMIT0" --arg h "$H0" --slurpfile r "$PD/.intent/.releitura-c0.json" '{
  v:1,
  sinos:[{id:"s-01",origem:"spec",disposicao:"corrigido",correcao_id:"c0-01"},
         {id:"s-02",origem:"discuss",disposicao:"aberto"}],
  correcoes:[{id:"c0-01",hash:$h}],
  releitura:$r[0]}' > "$PD/.intent/.ciclo0.json"
saida=$(RUN "$PD" 24.3 1 2>&1); rc=$?
[ "$rc" = 0 ] && ok "gate passa com o laço completo do ciclo 0" || erro "esperado 0, veio $rc" "$saida"
BRF="$PD/.intent/briefing-c1.md"
grep -q "Revalidação dirigida (ciclo 0)" "$BRF" && ok "seção de revalidação dirigida presente" || erro "R3 ausente"
grep -q "sino \`s-01\`" "$BRF" && ok "sino corrigido volta como pedido de revalidação" || erro "s-01 sumiu"
grep -q "\`s-02\`" "$BRF" && ok "sino aberto continua no briefing (nenhum sino some)" || erro "s-02 sumiu"
qids=$(jq -cr '.qids|join(",")' "$PD/.intent/.perguntas-c1.json")
[ "$qids" = "Q1,Q2,Q3,Q4,Q5,Q6,Q7" ] && ok "revalidação c0 entra como UMA pergunta (Q7) no manifesto — R8 do plano 3" || erro "manifesto" "$qids"
[ "$(jq -r '.detalhe[6].ref' "$PD/.intent/.perguntas-c1.json")" = "s-01" ] && ok "ref da Q de revalidação = ids dos sinos corrigidos" || erro "ref" "$(jq -c '.detalhe[6]' "$PD/.intent/.perguntas-c1.json")"
grep -q '^- \*\*Q7\*\* (revalidação do ciclo 0)' "$BRF" && ok "a Q de revalidação interpola o qid (Q7)" || erro "Q7 não interpolada"
grep -q 'evidência = o diff do commit' "$BRF" && erro "a frase que entregava a evidência do «sim» continua" || ok "a frase «evidência = o diff do commit» saiu (J7)"

echo "== E2c.5 — negativas do schema do ciclo 0"
neg() { # <rotulo> <json do .ciclo0>
  printf '%s' "$2" > "$PD/.intent/.ciclo0.json"
  RUN "$PD" 24.3 1 >/dev/null 2>&1
  [ $? = 4 ] && ok "$1 → exit 4" || erro "$1 deveria dar exit 4"
}
REL=$(cat "$PD/.intent/.releitura-c0.json")
neg "sino corrigido sem correcao_id" \
  "{\"v\":1,\"sinos\":[{\"id\":\"s-01\",\"origem\":\"spec\",\"disposicao\":\"corrigido\"}],\"correcoes\":[{\"id\":\"c0-01\",\"hash\":\"$H0\"}],\"releitura\":$REL}"
neg "sino aberto COM correcao_id" \
  "{\"v\":1,\"sinos\":[{\"id\":\"s-01\",\"origem\":\"spec\",\"disposicao\":\"aberto\",\"correcao_id\":\"c0-01\"},{\"id\":\"s-9\",\"origem\":\"spec\",\"disposicao\":\"corrigido\",\"correcao_id\":\"c0-01\"}],\"correcoes\":[{\"id\":\"c0-01\",\"hash\":\"$H0\"}],\"releitura\":$REL}"
neg "correção órfã (sem sino que a referencie)" \
  "{\"v\":1,\"sinos\":[{\"id\":\"s-01\",\"origem\":\"spec\",\"disposicao\":\"aberto\"}],\"correcoes\":[{\"id\":\"c0-01\",\"hash\":\"$H0\"}],\"releitura\":$REL}"
neg "hash da correção divergente do .aplicado" \
  "{\"v\":1,\"sinos\":[{\"id\":\"s-01\",\"origem\":\"spec\",\"disposicao\":\"corrigido\",\"correcao_id\":\"c0-01\"}],\"correcoes\":[{\"id\":\"c0-01\",\"hash\":\"OUTRO\"}],\"releitura\":$REL}"
SUB=$(printf '%s' "$REL" | jq -c '.artefatos |= [.[0]]')
neg "releitura com subconjunto dos caminhos do .aplicado" \
  "{\"v\":1,\"sinos\":[{\"id\":\"s-01\",\"origem\":\"spec\",\"disposicao\":\"corrigido\",\"correcao_id\":\"c0-01\"}],\"correcoes\":[{\"id\":\"c0-01\",\"hash\":\"$H0\"}],\"releitura\":$SUB}"

echo "== C1 — hash vazio: sem declaração reprova, declarado passa, legado passa com aviso"
CIC0_OK="{\"v\":1,\"sinos\":[{\"id\":\"s-01\",\"origem\":\"spec\",\"disposicao\":\"corrigido\",\"correcao_id\":\"c0-01\"}],\"correcoes\":[{\"id\":\"c0-01\",\"hash\":\"\"}],\"releitura\":$REL}"
printf '%s' "$CIC0_OK" > "$PD/.intent/.ciclo0.json"
# (a) `.aplicado` do script NOVO (tem a chave hash_ausente) com o id FORA dela → corrupção
jq '.correcoes=[{"id":"c0-01","hash":""}] | .hash_ausente=[]' "$APL" > "$APL.t" && mv "$APL.t" "$APL"
saida=$(RUN "$PD" 24.3 1 2>&1); rc=$?
[ "$rc" = 4 ] && ok "hash vazio com hash_ausente=[] → exit 4 (corrupção)" || erro "esperado 4, veio $rc" "$saida"
# (b) mesma coisa, mas a ausência DECLARADA em hash_ausente → passa
jq '.hash_ausente=["c0-01"]' "$APL" > "$APL.t" && mv "$APL.t" "$APL"
saida=$(RUN "$PD" 24.3 1 2>&1); rc=$?
[ "$rc" = 0 ] && ok "hash vazio declarado em hash_ausente → exit 0" || erro "esperado 0, veio $rc" "$saida"
printf '%s' "$saida" | jq -e '.gate.avisos[]? | select(test("hash_ausente"))' >/dev/null \
  && ok "a ausência declarada aparece nos avisos (auditável)" || erro "ausência silenciosa"
# (c) VÁLVULA DO LEGADO: `.aplicado` SEM a chave hash_ausente (fase anterior ao C1,
#     como as 5 da F24.4) → passa com aviso, senão toda fase antiga travaria
jq 'del(.hash_ausente)' "$APL" > "$APL.t" && mv "$APL.t" "$APL"
saida=$(RUN "$PD" 24.3 1 2>&1); rc=$?
[ "$rc" = 0 ] && ok "legado (sem a chave hash_ausente) → exit 0" || erro "esperado 0, veio $rc" "$saida"
printf '%s' "$saida" | jq -e '.gate.avisos[]? | select(test("legado"))' >/dev/null \
  && ok "o legado é declarado como legado, não escondido" || erro "aviso de legado ausente"
jq '.hash_ausente=["c0-01"]' "$APL" > "$APL.t" && mv "$APL.t" "$APL"

echo "== R1 — artefato editado DEPOIS da releitura → exit 4"
jq -n --slurpfile r "$PD/.intent/.releitura-c0.json" '{
  v:1, sinos:[{id:"s-01",origem:"spec",disposicao:"corrigido",correcao_id:"c0-01"}],
  correcoes:[{id:"c0-01",hash:""}], releitura:$r[0]}' > "$PD/.intent/.ciclo0.json"
echo "edicao depois da releitura" >> "$PD/24.3-SPEC.md"
RUN "$PD" 24.3 1 >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] && ok "exit 4 (hash-object atual != blob relido)" || erro "esperado 4, veio $rc"
G checkout -- "$PD/24.3-SPEC.md" 2>/dev/null

echo "== E2c.6 — ciclo 2"
RUN "$PD" 24.3 2 >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] && ok "c2 sem .correcoes-c1.aplicado/.vazio → exit 4" || erro "esperado 4, veio $rc"
: > "$PD/.intent/.correcoes-c1.vazio"
echo '{"commit":"","artefatos":[]}' > "$PD/.intent/.releitura-c1.json"
printf '## O que corrigi\n- c1-01: mudou isto (alegação a testar: a contagem é 7)\n\n## Achados resolvidos\n- c1-01\n' > "$PD/.intent/.mudancas-c2.md"
saida=$(RUN "$PD" 24.3 2 --mudancas "$PD/.intent/.mudancas-c2.md" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "c2 passa com .vazio + releitura vazia (legado)" || erro "esperado 0, veio $rc" "$saida"
lin=$(grep -n "o que mudou desde o ciclo anterior" "$PD/.intent/briefing-c2.md" | cut -d: -f1)
mis=$(grep -n "^## Missão" "$PD/.intent/briefing-c2.md" | cut -d: -f1)
art=$(grep -n "^## Artefatos" "$PD/.intent/briefing-c2.md" | cut -d: -f1)
if [ -n "$lin" ] && [ "$lin" -gt "$mis" ] && [ "$lin" -lt "$art" ]; then
  ok "\"o que mudou\" logo após a Missão (R8.4)"
else
  erro "posição do bloco 'o que mudou'" "missao=$mis mudou=$lin artefatos=$art"
fi
grep -q 'mudou isto' "$PD/.intent/briefing-c2.md" && ok "as duas seções canônicas entram inteiras (R7)" || erro "seção canônica omitida"
grep -q '^## Obrigação do ciclo 1' "$PD/.intent/briefing-c2.md" && erro "obrigação do ciclo 1 vazou para o c2" || ok "obrigação do ciclo 1 não aparece no c2 (R5)"
qids=$(jq -cr '.qids|join(",")' "$PD/.intent/.perguntas-c2.json")
[ "$qids" = "Q1,Q2,Q3" ] && ok "c2: só as três canônicas no manifesto" || erro "manifesto c2" "$qids"

echo "== R7 (plano 3) — --mudancas validado por forma: seção fora do contrato é omitida com aviso"
printf 'Texto solto antes de qualquer heading.\n\n## O que corrigi\n- c1-01: mudou isto\n\n## Onde vale gastar o ciclo 2\nO que ainda não foi atacado por ninguém: (a) a Regression Surface.\n' > "$PD/.intent/.mudancas-c2.md"
saida=$(RUN "$PD" 24.3 2 --mudancas "$PD/.intent/.mudancas-c2.md" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "heading fora do contrato não reprova o build (omite, não trava)" || erro "esperado 0, veio $rc" "$saida"
grep -q 'não foi atacado' "$PD/.intent/briefing-c2.md" && erro "a seção fora do contrato chegou ao briefing" || ok "«não foi atacado por ninguém» não chega ao consultor"
grep -q 'Texto solto antes' "$PD/.intent/briefing-c2.md" && erro "texto antes do primeiro heading vazou" || ok "texto antes do primeiro heading é omitido"
grep -q 'mudou isto' "$PD/.intent/briefing-c2.md" && ok "a seção canônica do mesmo arquivo entra" || erro "seção canônica perdida junto"
printf '%s' "$saida" | jq -e '.avisos[]? | select(. == "MUDANCAS-SECAO-FORA-DO-CONTRATO: ## Onde vale gastar o ciclo 2")' >/dev/null \
  && ok "aviso MUDANCAS-SECAO-FORA-DO-CONTRATO com o heading" || erro "aviso do heading ausente" "$(printf '%s' "$saida" | jq -c .avisos)"
printf '%s' "$saida" | jq -e '.avisos[]? | select(test("antes do primeiro heading"))' >/dev/null \
  && ok "aviso do texto antes do primeiro heading" || erro "aviso do texto solto ausente"
printf '# Nada canônico\n\n## Estado do dossiê\ntudo bem\n' > "$PD/.intent/.mudancas-c2.md"
saida=$(RUN "$PD" 24.3 2 --mudancas "$PD/.intent/.mudancas-c2.md" 2>&1); rc=$?
grep -q 'o que mudou desde o ciclo anterior' "$PD/.intent/briefing-c2.md" && erro "seção 'o que mudou' impressa vazia" || ok "arquivo inteiro fora do contrato → briefing sem a seção"
printf '%s' "$saida" | jq -e '.avisos[]? | select(test("arquivo inteiro fora do contrato"))' >/dev/null && ok "…com o aviso «sem --mudancas» acrescido do motivo" || erro "motivo ausente" "$(printf '%s' "$saida" | jq -c .avisos)"

echo "== R9 (plano 3) — releitura v:2: chaves obrigatórias, ok:false reprova, legado avisa"
echo '{"v":2,"commit":"","artefatos":[]}' > "$PD/.intent/.releitura-c1.json"
saida=$(RUN "$PD" 24.3 2 2>&1); rc=$?
[ "$rc" = 4 ] && ok "v:2 sem as chaves de veredito → exit 4 (stub declarado v2 não passa)" || erro "esperado 4, veio $rc" "$saida"
printf '%s' "$saida" | grep -q 'contradiz, prescreve_mecanismo, omissoes_novas, cardinalidade' && ok "a mensagem nomeia as chaves que faltam" || erro "mensagem sem as chaves" "$saida"
echo '{"v":2,"ciclo":1,"commit":"","artefatos":[],"contradiz":[],"prescreve_mecanismo":[],"omissoes_novas":[],"cardinalidade":[],"consistencia":"não_disponível","ok":false}' > "$PD/.intent/.releitura-c1.json"
saida=$(RUN "$PD" 24.3 2 2>&1); rc=$?
[ "$rc" = 4 ] && printf '%s' "$saida" | grep -q 'ok: false' && ok "ok:false em disco → exit 4 (a correção c<C>b não fechou)" || erro "ok:false passou (rc=$rc)" "$saida"
echo '{"v":2,"ciclo":1,"commit":"","artefatos":[],"contradiz":[],"prescreve_mecanismo":[],"omissoes_novas":[],"cardinalidade":[],"consistencia":"não_disponível","ok":true}' > "$PD/.intent/.releitura-c1.json"
saida=$(RUN "$PD" 24.3 2 2>&1); rc=$?
[ "$rc" = 0 ] && ok "v:2 completo com listas vazias e ok:true → passa (contradiz: [] honesto não é cota)" || erro "esperado 0, veio $rc" "$saida"
printf '%s' "$saida" | jq -e '.gate.avisos[]? | select(test("formato legado"))' >/dev/null && erro "v:2 marcado como legado" || ok "v:2 não recebe o aviso de legado (unicidade só é exigida no c0)"
echo '{"v":3,"commit":"","artefatos":[]}' > "$PD/.intent/.releitura-c1.json"
RUN "$PD" 24.3 2 >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] && ok "v desconhecido → exit 4" || erro "esperado 4, veio $rc"
echo '{"commit":"","artefatos":[{"path":"x","blob":"y"}]}' > "$PD/.intent/.releitura-c1.json"
RUN "$PD" 24.3 2 >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] && ok "ciclo .vazio com releitura não-vazia → exit 4" || erro "esperado 4, veio $rc"
limpa

echo "== E2xR1 — ROADMAP pré-sujo: releitura vale contra o COMMIT, worktree contra o pós-commit"
limpa; monta_repo
sed -i 's/^Entrada desta fase.*/Entrada desta fase — EDITADA PELO USUARIO antes do ciclo./' \
  "$REPO/.planning/ROADMAP.md"
DOCS=(--docs "$REPO/.planning/ROADMAP.md" "$REPO/.planning/REQUIREMENTS.md")
RUNC "$PD" 0 --inicio --artefatos "$PD/24.3-SPEC.md" "$PD/24.3-CONTEXT.md" \
     "$PD/24.3-INTENT-REVIEW.md" "${DOCS[@]}" >/dev/null 2>&1
echo "correcao do ciclo 0" >> "$PD/24.3-SPEC.md"
sed -i '1a linha inserida pelo ciclo 0' "$REPO/.planning/ROADMAP.md"
RUNC "$PD" 0 --ids "c0-01" --artefatos "$PD/24.3-SPEC.md" "$PD/24.3-CONTEXT.md" \
     "$PD/24.3-INTENT-REVIEW.md" "${DOCS[@]}" >/dev/null 2>&1
APL="$PD/.intent/.correcoes-c0.aplicado"
bc=$(jq -r '.blobs[] | select(.path==".planning/ROADMAP.md") | .blob_commit' "$APL")
bw=$(jq -r '.blobs[] | select(.path==".planning/ROADMAP.md") | .blob_worktree' "$APL")
[ -n "$bc" ] && [ "$bc" != "$bw" ] \
  && ok ".aplicado grava blob_commit != blob_worktree para o doc pré-sujo" \
  || erro "dois hashes do ROADMAP" "commit=$bc worktree=$bw"
releitura_json_de 0 > "$PD/.intent/.releitura-c0.json"
: > "$PD/.intent/.releitura-c0.done"
H0=$(jq -r '.correcoes[0].hash' "$APL")
jq -n --arg h "$H0" --slurpfile r "$PD/.intent/.releitura-c0.json" '{
  v:1, sinos:[{id:"s-01",origem:"spec",disposicao:"corrigido",correcao_id:"c0-01"}],
  correcoes:[{id:"c0-01",hash:$h}], releitura:$r[0]}' > "$PD/.intent/.ciclo0.json"
saida=$(RUN "$PD" 24.3 1 2>&1); rc=$?
[ "$rc" = 0 ] && ok "gate c1 PASSA com ROADMAP legitimamente sujo" \
  || erro "gate acusou edição inexistente (esperado 0, veio $rc)" "$saida"
printf '%s' "$saida" | jq -e '.gate.avisos[]? | select(test("edição pré-ciclo"))' >/dev/null \
  && ok "a divergência worktree x commit é declarada, não escondida" || erro "divergência silenciosa"
echo "edicao real depois da releitura" >> "$REPO/.planning/ROADMAP.md"
RUN "$PD" 24.3 1 >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] && ok "ROADMAP editado DEPOIS da releitura → exit 4" || erro "esperado 4, veio $rc"
limpa


echo "== R8(3) — respostas do checklist de lições saem do briefing e viram evidência"
limpa; monta_repo
echo '{"v":1,"sinos":[{"id":"s-01","origem":"spec","disposicao":"aberto"}],"correcoes":[],"releitura":{"commit":"","artefatos":[]}}' \
  > "$PD/.intent/.ciclo0.json"
: > "$PD/.intent/.releitura-c0.done"
cat > "$PD/.intent/.sinos-spec.txt" <<'EOS'
licao 1: aplicada — o SPEC declara o oraculo de erro em 24.3-SPEC.md:12
- sino real: o criterio de aceite 3 nao tem oraculo observavel
licao 2: nao_se_aplica — esta fase nao mexe em contagem autorreportada
EOS
saida=$(RUN "$PD" 24.3 1 2>&1); rc=$?
[ "$rc" = 0 ] || erro "briefing falhou (rc=$rc)" "$saida"
BRF="$PD/.intent/briefing-c1.md"
n_lic=$(grep -c '^licao [0-9]' "$BRF" || true)
[ "$n_lic" = 0 ] && ok "0 linhas \`licao\` no briefing" || erro "$n_lic linha(s) licao vazaram para o briefing"
n_sino=$(sed -n '/^## Sinos de spec/,/^## /p' "$BRF" | grep -c '^- sino real' || true)
[ "$n_sino" = 1 ] && ok "o sino real continua no briefing (nenhum sino some)" || erro "sino real sumiu"
LIC="$PD/.intent/.licoes-c1.txt"
[ "$(wc -l < "$LIC" 2>/dev/null | tr -d ' ')" = 2 ] \
  && ok "as 2 respostas de lição foram para .licoes-c1.txt" || erro "arquivo de lições" "$(cat "$LIC" 2>/dev/null)"
grep -q '^spec | licao 1: aplicada' "$LIC" && ok "cada linha carrega a origem (spec/discuss)" || erro "origem ausente"
printf '%s' "$saida" | jq -e '.licoes_respostas == 2' >/dev/null \
  && ok "o JSON declara quantas respostas de lição foram colhidas" || erro "JSON sem licoes_respostas"
limpa

echo
[ "$falhas" -eq 0 ] && echo "test-briefing-build: TUDO OK" || echo "test-briefing-build: $falhas falha(s)"
[ "$falhas" -eq 0 ]
