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
  printf 'spec base\ndecisao X [auto]\n'    > "$PD/24.3-SPEC.md"
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
releitura_json_de() { # <ciclo> — deriva do .aplicado (é o que o gad-verificador grava)
  local c="$1" apl="$PD/.intent/.correcoes-c$1.aplicado"
  local commit; commit=$(jq -r .commit "$apl")
  { printf '{"commit":"%s","artefatos":[' "$commit"
    local first=1 p b
    while IFS= read -r p; do
      b=$(G rev-parse "$commit:$p")
      [ $first = 1 ] || printf ','; first=0
      printf '{"path":"%s","blob":"%s"}' "$p" "$b"
    done < <(jq -r '.caminhos[]' "$apl")
    printf ']}\n'; }
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

echo "== E2c.4 — sinos:[] com .sinos-spec.txt cheio → exit 4 (R3: nenhum sino some)"
echo "sino do spec" > "$PD/.intent/.sinos-spec.txt"
RUN "$PD" 24.3 1 >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] && ok "exit 4 (sinos declarados vazios com sino no disco)" || erro "esperado 4, veio $rc"
rm -f "$PD/.intent/.sinos-spec.txt"

echo "== R8 — briefing sem lições, ROADMAP só da fase, Q1–Q3 e manifesto"
BRF="$PD/.intent/briefing-c1.md"
grep -q "LICOES\|Lição 1" "$BRF" && erro "lições continuam no briefing" || ok "lições saíram do briefing"
grep -q "Phase 24.4" "$BRF" && erro "ROADMAP trouxe a fase seguinte" || ok "ROADMAP não traz a fase seguinte"
grep -q "Phase 24.2" "$BRF" && erro "ROADMAP trouxe a fase anterior" || ok "ROADMAP não traz a fase anterior"
grep -q "Entrada desta fase" "$BRF" && ok "ROADMAP traz a entrada da fase" || erro "entrada da fase sumiu"
grep -q "^## Perguntas dirigidas" "$BRF" && ok "seção Perguntas dirigidas presente" || erro "seção ausente"
grep -q "## Respostas dirigidas" "$BRF" && ok "briefing exige a seção de resposta estruturada" || erro "formato de resposta não pedido"
qids=$(jq -cr '.qids|join(",")' "$PD/.intent/.perguntas-c1.json" 2>/dev/null)
[ "$qids" = "Q1,Q2,Q3" ] && ok "manifesto estável com Q1–Q3" || erro "manifesto" "$qids"

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
[ "$qids" = "Q1,Q2,Q3,Q4" ] && ok "revalidação c0 entra como Q4 no manifesto" || erro "manifesto" "$qids"

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
echo "mudou isto" > "$PD/.intent/.mudancas-c2.md"
saida=$(RUN "$PD" 24.3 2 --mudancas "$PD/.intent/.mudancas-c2.md" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "c2 passa com .vazio + releitura vazia" || erro "esperado 0, veio $rc" "$saida"
lin=$(grep -n "o que mudou desde o ciclo anterior" "$PD/.intent/briefing-c2.md" | cut -d: -f1)
mis=$(grep -n "^## Missão" "$PD/.intent/briefing-c2.md" | cut -d: -f1)
art=$(grep -n "^## Artefatos" "$PD/.intent/briefing-c2.md" | cut -d: -f1)
if [ -n "$lin" ] && [ "$lin" -gt "$mis" ] && [ "$lin" -lt "$art" ]; then
  ok "\"o que mudou\" logo após a Missão (R8.4)"
else
  erro "posição do bloco 'o que mudou'" "missao=$mis mudou=$lin artefatos=$art"
fi
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
