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
saida=$(RUN "$PD" 1 --ids "c1-01,c1-02" "${ALVOS[@]}" 2>&1); rc=$?
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
  # F4 RLR (FM-05INT): o placeholder `:<hash>` do intent.md deixou de ser tolerado em
  # silêncio — caminho declarado fora do diff agora é RECUSA (caso próprio abaixo). Aqui
  # a forma canônica só-ids: o ciclo tocou 2 caminhos e nenhum id declarou qual → hash
  # vazio, mas DECLARADO em hash_ausente[].
  ids=$(jq -cr '.correcoes|map(.id)|join(",")' "$apl" 2>/dev/null)
  [ "$ids" = "c1-01,c1-02" ] && ok '.aplicado traz os ids das correcoes' || erro "ids" "$ids"
  vaz=$(jq -cr '[.correcoes[]|select(.hash=="")]|length' "$apl" 2>/dev/null)
  aus=$(jq -cr '.hash_ausente|sort|join(",")' "$apl" 2>/dev/null)
  { [ "$vaz" = 2 ] && [ "$aus" = "c1-01,c1-02" ]; } \
    && ok '>1 caminho sem declaração → hash vazio E id em hash_ausente[]' \
    || erro "hash_ausente" "vazias=$vaz ausentes=$aus"
  # FM-05INT: o assunto do commit sai da LISTA DE ARQUIVOS DO DIFF, não dos ids
  # t59 b2 (FM-F27INS-04INT): o assunto traz os IDS (forma documentada); a lista de arquivos
  # do diff — que continua saindo do diff, não do que o coordenador digitou — vai ao corpo
  msg=$(G log -1 --pretty=%s)
  [ "$msg" = "docs(fase 24.3): correções do ciclo 1 — c1-01, c1-02" ] \
    && ok "assunto do commit = ids da rodada" || erro "mensagem" "$msg"
  body=$(G log -1 --pretty=%b)
  case "$body" in *"caminhos: .planning/phases/24.3-fase/24.3-SPEC.md, .planning/ROADMAP.md"*)
    ok "corpo do commit = arquivos do diff" ;; *) erro "corpo sem os caminhos do diff" "$body" ;; esac
  case "$body" in *"ids: c1-01,c1-02"*) ok "corpo do commit registra os ids" ;;
    *) erro "corpo sem os ids" "$body" ;; esac
  [ "$(jq -c '.commits' "$apl")" = "[\"$(G rev-parse HEAD)\"]" ] && ok "commits = [o commit do ciclo]" \
    || erro "commits" "$(jq -c '.commits' "$apl")"
  [ "$(jq -r '.rodadas|length' "$apl"):$(jq -r '.rodadas[0].rodada' "$apl")" = "1:c1" ] \
    && ok "rodadas = 1 (c1)" || erro "rodadas" "$(jq -c '.rodadas' "$apl")"
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

echo "== C1.1 — um único caminho comitado → hash = blob sha do arquivo no commit"
monta_repo; set_alvos
RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1
echo "so a spec mudou neste ciclo" >> "$PD/24.3-SPEC.md"
RUN "$PD" 1 --ids "c1-01,c1-02" "${ALVOS[@]}" >/dev/null 2>&1; rc=$?
apl="$PD/.intent/.correcoes-c1.aplicado"
if [ "$rc" != 0 ]; then erro "fecho falhou (rc=$rc)"; else
  cam=$(jq -r '.caminhos|length' "$apl")
  [ "$cam" = 1 ] && ok "o ciclo comitou exatamente 1 caminho" || erro "caminhos=$cam"
  esperado=$(G rev-parse "HEAD:.planning/phases/24.3-fase/24.3-SPEC.md")
  h1=$(jq -r '.correcoes[0].hash' "$apl"); h2=$(jq -r '.correcoes[1].hash' "$apl")
  [ -n "$h1" ] && [ "$h1" = "$esperado" ] && [ "$h2" = "$esperado" ] \
    && ok "hash não-vazio e igual ao blob do arquivo no commit" \
    || erro "hash" "h1=$h1 h2=$h2 esperado=$esperado"
  aus=$(jq -cr '.hash_ausente' "$apl")
  [ "$aus" = "[]" ] && ok "hash_ausente presente e vazio (chave sempre gravada)" \
    || erro "hash_ausente deveria ser []" "$aus"
fi
limpa

echo "== C1.2 — forma 2 (id:<caminho>): cada correção pega o blob do caminho que declarou"
monta_repo; set_alvos
RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1
echo "correcao na spec"    >> "$PD/24.3-SPEC.md"
echo "correcao no context" >> "$PD/24.3-CONTEXT.md"
RUN "$PD" 1 --ids "c1-01:.planning/phases/24.3-fase/24.3-SPEC.md,c1-02:.planning/phases/24.3-fase/24.3-CONTEXT.md" \
  "${ALVOS[@]}" >/dev/null 2>&1; rc=$?
apl="$PD/.intent/.correcoes-c1.aplicado"
if [ "$rc" != 0 ]; then erro "fecho falhou (rc=$rc)"; else
  bs=$(G rev-parse "HEAD:.planning/phases/24.3-fase/24.3-SPEC.md")
  bc=$(G rev-parse "HEAD:.planning/phases/24.3-fase/24.3-CONTEXT.md")
  h1=$(jq -r '.correcoes[]|select(.id=="c1-01")|.hash' "$apl")
  h2=$(jq -r '.correcoes[]|select(.id=="c1-02")|.hash' "$apl")
  { [ "$h1" = "$bs" ] && [ "$h2" = "$bc" ]; } \
    && ok "caminho declarado resolve o hash mesmo com 2 caminhos no commit" \
    || erro "hashes por caminho declarado" "c1-01=$h1 (esp $bs) c1-02=$h2 (esp $bc)"
  [ "$(jq -cr '.hash_ausente' "$apl")" = "[]" ] && ok "nenhuma ausência" || erro "hash_ausente não vazio"
  [ "$(jq -cr '.ids|join(",")' "$apl")" = "c1-01,c1-02" ] \
    && ok "ids[] continua só com os ids (sem o caminho)" || erro "ids[] contaminado"
fi
limpa

echo "== C6.1 — CONTEXT comitado no ciclo → DECISIONS-INDEX.md regravado no MESMO commit"
# O gerador é o do fork (GAD_DECISIONS_INDEX aponta para ele — nada instalado). O índice já
# existe no projeto (gerado antes do ciclo); a emenda muda uma D-NN do CONTEXT.
GEN="$AQUI/../../gsd-optimize/gen5-patches/nossos/.claude/gsd-core/bin/nosso/decisions-index.py"
if [ -f "$GEN" ]; then
  monta_repo; set_alvos
  printf '# Phase 24.3: Fase - Context\n\n<decisions>\n## Implementation Decisions\n\n### A\n- **D-01 [auto, R1]:** decisão original\n\n### Claude'"'"'s Discretion\n- nada\n\n</decisions>\n' > "$PD/24.3-CONTEXT.md"
  python3 "$GEN" "$REPO/.planning" >/dev/null 2>&1
  G add -A >/dev/null; G commit -qm "contexto + índice" >/dev/null
  grep -q 'decisão original' "$REPO/.planning/DECISIONS-INDEX.md" && ok "fixture: índice existe e reflete o CONTEXT" || erro "fixture do índice"
  GAD_DECISIONS_INDEX="$GEN" RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1 || erro "--inicio com índice falhou"
  jq -e '.alvos[] | select(.path==".planning/DECISIONS-INDEX.md")' "$PD/.intent/.correcoes-c1.base.json" >/dev/null \
    && ok "--inicio: o índice entrou nos alvos (senão o fecho o recusaria como alvo novo)" || erro "índice fora do --inicio"
  sed -i 's/decisão original/decisão EMENDADA no ciclo/' "$PD/24.3-CONTEXT.md"
  saida=$(GAD_DECISIONS_INDEX="$GEN" RUN "$PD" 1 --ids "c1-01" "${ALVOS[@]}" 2>&1); rc=$?
  [ "$rc" = 0 ] && ok "fecho aceito" || erro "fecho falhou (rc=$rc)" "$saida"
  G show HEAD:.planning/DECISIONS-INDEX.md | grep -q 'decisão EMENDADA no ciclo' \
    && ok "índice regravado e comitado junto (sem stale)" || erro "índice no HEAD ainda é o velho"
  jq -r '.caminhos[]' "$PD/.intent/.correcoes-c1.aplicado" | grep -qx '.planning/DECISIONS-INDEX.md' \
    && ok ".aplicado lista o índice entre os caminhos" || erro "índice fora de caminhos[]"
  G diff --quiet -- .planning/DECISIONS-INDEX.md && ok "worktree do índice limpo após o commit" || erro "índice sujo"
  limpa

  echo "== C6.2 — ciclo que NÃO toca o CONTEXT não mexe no índice; gerador ausente → silêncio"
  monta_repo; set_alvos
  printf '# Phase 24.3: Fase - Context\n\n<decisions>\n## Implementation Decisions\n\n### A\n- **D-01 [auto, R1]:** decisão\n\n### Claude'"'"'s Discretion\n- nada\n\n</decisions>\n' > "$PD/24.3-CONTEXT.md"
  python3 "$GEN" "$REPO/.planning" >/dev/null 2>&1
  G add -A >/dev/null; G commit -qm "contexto + índice" >/dev/null
  IDX_BLOB=$(G rev-parse HEAD:.planning/DECISIONS-INDEX.md)
  GAD_DECISIONS_INDEX="$GEN" RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1
  echo "spec corrigida" >> "$PD/24.3-SPEC.md"
  GAD_DECISIONS_INDEX="$GEN" RUN "$PD" 1 --ids "c1-01" "${ALVOS[@]}" >/dev/null 2>&1 || erro "fecho só-SPEC falhou"
  [ "$(G rev-parse HEAD:.planning/DECISIONS-INDEX.md)" = "$IDX_BLOB" ] && ok "só o SPEC mudou → índice intocado" || erro "índice mudou sem CONTEXT mudar"
  jq -r '.caminhos[]' "$PD/.intent/.correcoes-c1.aplicado" | grep -qx '.planning/DECISIONS-INDEX.md' \
    && erro "índice comitado sem mudança" || ok "índice não entra em caminhos[] quando não muda"
  # gerador ausente: o ciclo 2 toca o CONTEXT e nada acontece com o índice
  GAD_DECISIONS_INDEX="/nao/existe.py" RUN "$PD" 2 --inicio "${ALVOS[@]}" >/dev/null 2>&1
  jq -e '.alvos[] | select(.path==".planning/DECISIONS-INDEX.md")' "$PD/.intent/.correcoes-c2.base.json" >/dev/null 2>&1 \
    && erro "gerador ausente e o índice entrou nos alvos" || ok "gerador ausente → índice fora dos alvos (silêncio)"
  echo "emenda" >> "$PD/24.3-CONTEXT.md"
  saida=$(GAD_DECISIONS_INDEX="/nao/existe.py" RUN "$PD" 2 --ids "c2-01" "${ALVOS[@]}" 2>&1); rc=$?
  [ "$rc" = 0 ] && ok "gerador ausente → o ciclo comita normalmente (exit 0)" || erro "gerador ausente quebrou o ciclo" "$saida"
  [ "$(G rev-parse HEAD:.planning/DECISIONS-INDEX.md)" = "$IDX_BLOB" ] && ok "gerador ausente → índice segue igual" || erro "índice mudou sem gerador"
  limpa
else
  ok "gerador do fork não encontrado ao lado — casos C6 pulados"
fi

echo "== M4 (46 j) — --inicio tolera alvo ainda inexistente (o INTENT-REVIEW nasce no ciclo)"
monta_repo
rm -f "$PD/24.3-INTENT-REVIEW.md"
saida=$(RUN "$PD" 0 --inicio --artefatos "$PD/24.3-SPEC.md" "$PD/24.3-CONTEXT.md" \
        "$PD/24.3-INTENT-REVIEW.md" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "--inicio com alvo ausente: exit 0 (era exit 3)" \
  || erro "esperado 0, veio $rc" "$saida"
n=$(jq '[.alvos[] | select(.ausente_no_inicio == true)] | length' "$PD/.intent/.correcoes-c0.base.json" 2>/dev/null)
[ "$n" = 1 ] && ok "o alvo ausente entra no .base.json com ausente_no_inicio:true" \
  || erro "esperado 1 alvo ausente, veio [$n]"
b=$(jq -r '.alvos[] | select(.ausente_no_inicio == true) | .blob_pre' "$PD/.intent/.correcoes-c0.base.json")
[ -z "$b" ] && ok "blob_pre vazio (delta inteiro é do ciclo)" || erro "blob_pre deveria ser vazio: [$b]"

echo "== M4 — ponta a ponta: o INTENT-REVIEW nasce DENTRO do ciclo e entra no commit"
monta_repo
rm -f "$PD/24.3-INTENT-REVIEW.md"
RUN "$PD" 0 --inicio --artefatos "$PD/24.3-SPEC.md" "$PD/24.3-CONTEXT.md" \
    "$PD/24.3-INTENT-REVIEW.md" >/dev/null 2>&1 || erro "--inicio falhou no ponta a ponta"
printf 'review criado no ciclo\n' > "$PD/24.3-INTENT-REVIEW.md"
echo "correcao do ciclo" >> "$PD/24.3-SPEC.md"
saida=$(RUN "$PD" 0 --ids "c0-01" --artefatos "$PD/24.3-SPEC.md" "$PD/24.3-CONTEXT.md" \
        "$PD/24.3-INTENT-REVIEW.md" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "--ids fecha o ciclo com o alvo que nasceu dentro dele (exit 0)" \
  || erro "esperado 0, veio $rc" "$saida"
jq -e '[.caminhos[] | select(endswith("24.3-INTENT-REVIEW.md"))] | length == 1' \
  "$PD/.intent/.correcoes-c0.aplicado" >/dev/null 2>&1 \
  && ok "o arquivo novo entrou nos caminhos comitados" \
  || erro "INTENT-REVIEW ficou de fora do commit" "$(jq -c '.caminhos' "$PD/.intent/.correcoes-c0.aplicado" 2>&1)"

echo "== M4 — nos modos --ids/--vazio a ausência segue sendo erro"
monta_repo
rm -f "$PD/24.3-INTENT-REVIEW.md"
saida=$(RUN "$PD" 0 --ids "c0-01" --artefatos "$PD/24.3-SPEC.md" \
        "$PD/24.3-INTENT-REVIEW.md" 2>&1); rc=$?
[ "$rc" = 3 ] && printf '%s' "$saida" | grep -q 'alvo inexistente' \
  && ok "--ids com alvo ausente: exit 3, como antes" || erro "esperado 3, veio $rc" "$saida"

echo "== M5 (46 j) — o índice de decisões não conta como 2.º caminho na regra do hash"
monta_repo
mkdir -p "$REPO/.planning"
printf '# indice\n' > "$REPO/.planning/DECISIONS-INDEX.md"
cat > "$REPO/gerador.py" <<'PYGEN'
import sys, pathlib
planning = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".planning")
(planning / "DECISIONS-INDEX.md").write_text("# indice regenerado\n")
PYGEN
G add -A >/dev/null; G commit -qm indice >/dev/null
saida=$(GAD_DECISIONS_INDEX="$REPO/gerador.py" RUN "$PD" 1 --inicio \
        --artefatos "$PD/24.3-CONTEXT.md" 2>&1); rc=$?
[ "$rc" = 0 ] || erro "--inicio com índice falhou (rc=$rc)" "$saida"
echo "correcao do ciclo" >> "$PD/24.3-CONTEXT.md"
saida=$(GAD_DECISIONS_INDEX="$REPO/gerador.py" RUN "$PD" 1 --ids "c1-01,c1-02" \
        --artefatos "$PD/24.3-CONTEXT.md" 2>&1); rc=$?
if [ "$rc" = 0 ]; then
  apl="$PD/.intent/.correcoes-c1.aplicado"
  ncam=$(jq '.caminhos | length' "$apl")
  nsem=$(jq '.hash_ausente | length' "$apl")
  [ "$ncam" -ge 2 ] && ok "o ciclo comitou $ncam caminhos (CONTEXT + índice derivado)" \
    || erro "esperava 2+ caminhos, veio $ncam"
  [ "$nsem" = 0 ] && ok "0 correções sem hash (era 8 na F24.5)" \
    || erro "ainda há $nsem correção(ões) em hash_ausente[]" "$(jq -c '{caminhos,hash_ausente}' "$apl")"
else
  erro "commit do ciclo com índice falhou (rc=$rc)" "$saida"
fi

# ════════════════════════════════════════════════════════════════════════════
# F4 RLR — travas de id (FM-04INT + FJ-05INT), selo por caminho declarado
# (FM-05INT), base preservada no re-selo e aborto que NÃO grava .vazio (FJ-04INT).
# ════════════════════════════════════════════════════════════════════════════

vereditos() { # escreve .intent/.vereditos-c<C>.txt com as linhas dadas
  local c="$1"; shift
  mkdir -p "$PD/.intent"
  printf '%s\n' "$@" > "$PD/.intent/.vereditos-c$c.txt"
}
prepara_ciclo() { # monta repo + --inicio + uma emenda real na SPEC
  monta_repo; set_alvos
  RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1 || erro "--inicio falhou"
  echo "spec corrigida pelo ciclo" >> "$PD/24.3-SPEC.md"
}

echo "== F4RLR.1 — id inventado é recusado ANTES de tocar o repositório"
prepara_ciclo
vereditos 1 "c1-01 | bug | confirmado | codigo"
H0=$(G rev-parse HEAD)
saida=$(RUN "$PD" 1 --ids "c1-01,c1-99" "${ALVOS[@]}" 2>&1); rc=$?
[ "$rc" = 3 ] && ok "id inventado → exit 3" || erro "esperava exit 3, veio $rc" "$saida"
case "$saida" in *"c1-99"*) ok "a recusa nomeia o id inventado" ;; *) erro "recusa sem o id" "$saida" ;; esac
case "$saida" in *"ids válidos"*c1-01*) ok "a recusa lista os ids válidos" ;; *) erro "sem lista de válidos" "$saida" ;; esac
[ "$(G rev-parse HEAD)" = "$H0" ] && ok "HEAD inalterado" || erro "HEAD avançou"
[ -f "$PD/.intent/.correcoes-c1.vazio" ] && erro "aborto por erro gravou .vazio (FJ-04INT)" \
  || ok "aborto por erro NÃO grava .vazio (FJ-04INT)"
[ -f "$PD/.intent/.correcoes-c1.aplicado" ] && erro "gravou .aplicado numa recusa" || ok "nenhum .aplicado"
limpa

echo "== F4RLR.2 — id DISPENSADO (confirmado_irrelevante) é recusado"
prepara_ciclo
vereditos 1 "c1-01 | bug | confirmado | codigo" "c1-02 | nit | confirmado_irrelevante | doc"
saida=$(RUN "$PD" 1 --ids "c1-01,c1-02" "${ALVOS[@]}" 2>&1); rc=$?
[ "$rc" = 3 ] && ok "dispensado promovido → exit 3" || erro "esperava exit 3, veio $rc" "$saida"
case "$saida" in *DISPENSADO*) ok "a recusa diz DISPENSADO" ;; *) erro "mensagem" "$saida" ;; esac
case "$saida" in *dívida*) ok "a recusa aponta a dívida como destino" ;; *) erro "sem destino" "$saida" ;; esac
limpa

echo "== F4RLR.3 — achado CONFIRMADO sem destino é recusado; --adiados dá destino"
prepara_ciclo
vereditos 1 "c1-01 | bug | confirmado | codigo" "c1-02 | bug | confirmado | codigo"
saida=$(RUN "$PD" 1 --ids "c1-01" "${ALVOS[@]}" 2>&1); rc=$?
[ "$rc" = 3 ] && ok "confirmado sem destino → exit 3" || erro "esperava exit 3, veio $rc" "$saida"
case "$saida" in *c1-02*) ok "a recusa nomeia o confirmado órfão" ;; *) erro "sem o id" "$saida" ;; esac
saida=$(RUN "$PD" 1 --ids "c1-01" --adiados "c1-02" "${ALVOS[@]}" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "--adiados dá destino ao confirmado → exit 0" || erro "esperava exit 0, veio $rc" "$saida"
case "$(G log -1 --pretty=%b)" in *"adiados: c1-02"*) ok "o corpo do commit registra os adiados" ;;
  *) erro "corpo sem adiados" "$(G log -1 --pretty=%b)" ;; esac
limpa

echo "== F4RLR.4 — id de releitura do mesmo ciclo (c1b-NN) é aceito"
prepara_ciclo
vereditos 1 "c1-01 | bug | confirmado | codigo"
saida=$(RUN "$PD" 1 --ids "c1-01,c1b-01" "${ALVOS[@]}" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "c1b-01 aceito sem estar nos vereditos" || erro "esperava exit 0, veio $rc" "$saida"
limpa

echo "== F4RLR.5 — caminho declarado ausente do diff é RECUSA (era silêncio)"
prepara_ciclo
vereditos 1 "c1-01 | bug | confirmado | codigo"
H0=$(G rev-parse HEAD)
saida=$(RUN "$PD" 1 --ids "c1-01:$PD/24.3-CONTEXT.md" "${ALVOS[@]}" 2>&1); rc=$?
[ "$rc" = 3 ] && ok "caminho declarado fora do diff → exit 3" || erro "esperava exit 3, veio $rc" "$saida"
[ "$(G rev-parse HEAD)" = "$H0" ] && ok "HEAD inalterado na recusa" || erro "HEAD avançou"
limpa

echo "== F4RLR.6 — re-selo: --inicio no mesmo HEAD não sobrescreve a base pré-ciclo"
monta_repo; set_alvos
RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1
B0=$(cat "$PD/.intent/.correcoes-c1.base.json")
echo "spec corrigida pelo ciclo" >> "$PD/24.3-SPEC.md"
RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1 || erro "2º --inicio falhou"
[ "$(cat "$PD/.intent/.correcoes-c1.base.json")" = "$B0" ] \
  && ok "base pré-ciclo preservada no 2º --inicio" || erro "base foi sobrescrita (blob_pre viria emendado)"
vereditos 1 "c1-01 | bug | confirmado | codigo"
RUN "$PD" 1 --ids "c1-01" "${ALVOS[@]}" >/dev/null 2>&1 \
  && ok "o fecho ainda enxerga o delta do ciclo" || erro "fecho falhou após re-selo"
limpa

echo "== F4RLR.7 — revalida-documentos.sh: contagem por extenso × lista"
REV="$AQUI/../skills/go-and-do/scripts/revalida-documentos.sh"
monta_repo
cat > "$PD/24.3-CONTEXT.md" <<'MD'
## Decisões
Foram tomadas três decisões nesta fase.

- **D-01** — uma coisa (revalidada no ciclo 1)
- **D-02** — outra coisa
- **D-03** — mais uma
- **D-04** — a quarta, que a contagem esqueceu
MD
saida=$(bash "$REV" "$PD" 1 2>&1); rc=$?
[ "$rc" != 0 ] && ok "contagem divergente → exit != 0" || erro "não acusou a contagem" "$saida"
case "$saida" in *CONTAGEM*) ok "acusa CONTAGEM" ;; *) erro "sem CONTAGEM" "$saida" ;; esac
sed -i 's/três decisões/quatro decisões/' "$PD/24.3-CONTEXT.md"
saida=$(bash "$REV" "$PD" 1 2>&1); rc=$?
[ "$rc" = 0 ] && ok "contagem certa → exit 0" || erro "acusou com a contagem certa" "$saida"
limpa

echo "== F4RLR.8 — revalida-documentos.sh: ponteiro de decisão para critério inexistente"
monta_repo
cat > "$PD/24.3-CONTEXT.md" <<'MD'
## Decisões
- **D-01** — fecha o critério SC-2
- **D-02** — fecha o critério SC-9
MD
cat > "$PD/24.3-SPEC.md" <<'MD'
## Critérios
- **SC-1** — um
- **SC-2** — dois
MD
saida=$(bash "$REV" "$PD" 1 2>&1); rc=$?
[ "$rc" != 0 ] && ok "ponteiro órfão → exit != 0" || erro "não acusou o ponteiro" "$saida"
case "$saida" in *PONTEIRO*SC-9*) ok "acusa PONTEIRO SC-9" ;; *) erro "sem o ponteiro" "$saida" ;; esac
limpa

echo "== F4RLR.9 — FIAÇÃO: o correcoes-commit.sh chama o revalida-documentos.sh"
monta_repo; set_alvos
cat > "$PD/24.3-CONTEXT.md" <<'MD'
## Decisões
Foram tomadas três decisões nesta fase.

- **D-01** — uma
- **D-02** — outra
- **D-03** — mais uma
- **D-04** — a quarta, que a contagem esqueceu
MD
G add -A >/dev/null; G commit -qm "context com deriva" >/dev/null
RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1
echo "spec corrigida pelo ciclo" >> "$PD/24.3-SPEC.md"
vereditos 1 "c1-01 | bug | confirmado | codigo"
saida=$(RUN "$PD" 1 --ids "c1-01" "${ALVOS[@]}" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "o ciclo fecha (a deriva SÓ avisa, não bloqueia)" || erro "fechou com rc=$rc" "$saida"
case "$saida" in *"AVISO revalida-documentos"*) ok "o aviso do revalida-documentos chegou ao stderr" ;;
  *) erro "o revalida-documentos não foi chamado (fiação morta)" "$saida" ;; esac
case "$saida" in *CONTAGEM*) ok "o aviso nomeia a CONTAGEM divergente" ;; *) erro "aviso sem CONTAGEM" "$saida" ;; esac
esp="$(git -C "$REPO" rev-parse --path-format=absolute --git-path gad-cache)/last-correcoes-commit.json"   # v2.10.1: cópia no cache
n=$(jq -r '.revalida_avisos // "ausente"' "$esp" 2>/dev/null)
{ [ -n "$n" ] && [ "$n" != ausente ] && [ "$n" -gt 0 ]; } \
  && ok "revalida_avisos=$n no JSON de saída" || erro "revalida_avisos" "$n"
limpa

# ════════════════════════════════════════════════════════════════════════════
# t59 b2+b3 (FM-F27INS-04INT + FJ-F27INS-03INT) — rodadas do mesmo ciclo: o .aplicado
# acumula os commits, e a rodada «b» aceita só os ids novos, herdando o resto do
# .aplicado anterior CONFERIDO contra o git.
# ════════════════════════════════════════════════════════════════════════════
APL1() { printf '%s' "$PD/.intent/.correcoes-c1.aplicado"; }
rodada_a() { # ciclo 1, rodada a: c1-01 e c1-02 confirmados, corrigidos na SPEC
  monta_repo; set_alvos
  vereditos 1 "c1-01 | bug | confirmado | codigo" "c1-02 | bug | confirmado | codigo"
  RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1 || erro "--inicio (a) falhou"
  echo "spec corrigida na rodada a" >> "$PD/24.3-SPEC.md"
  RUN "$PD" 1 --ids "c1-01,c1-02" "${ALVOS[@]}" >/dev/null 2>&1 || erro "fecho da rodada a falhou"
  CA=$(G rev-parse HEAD)
  HASH_A=$(jq -r '.correcoes[]|select(.id=="c1-01")|.hash' "$(APL1)")
}
rodada_b_inicio() { # c1-07 confirmado tarde (caso F27), --inicio da rodada b, emenda no CONTEXT
  vereditos 1 "c1-01 | bug | confirmado | codigo" "c1-02 | bug | confirmado | codigo" \
              "c1-07 | bug | confirmado | codigo"
  RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1 || erro "--inicio (b) falhou"
  echo "context corrigido na rodada b" >> "$PD/24.3-CONTEXT.md"
}

echo "== t59 b3 — rodada b só com o id novo é ACEITA (antes: recusa «confirmado sem destino»)"
rodada_a; rodada_b_inicio
saida=$(RUN "$PD" 1 --ids "c1-07" "${ALVOS[@]}" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "rodada b com --ids c1-07 → exit 0" || erro "esperava exit 0, veio $rc" "$saida"
case "$saida" in *"herdados do .aplicado (conferido contra o git): ids c1-01,c1-02"*) ok "a herança é declarada no stderr" ;;
  *) erro "herança não declarada" "$saida" ;; esac
CB=$(G rev-parse HEAD); A="$(APL1)"
echo "== t59 b2 — o .aplicado registra TODOS os commits do ciclo"
[ "$(jq -c '.commits' "$A")" = "[\"$CA\",\"$CB\"]" ] && ok "commits = [rodada a, rodada b]" || erro "commits" "$(jq -c '.commits' "$A")"
[ "$(jq -r '.commit' "$A")" = "$CB" ] && ok "commit = o da rodada vigente (a releitura se amarra a ele)" || erro "commit"
[ "$(jq -r '.ids|join(",")' "$A")" = "c1-01,c1-02,c1-07" ] && ok "ids = união do ciclo" || erro "ids" "$(jq -c .ids "$A")"
[ "$(jq -r '.correcoes|map(.id)|join(",")' "$A")" = "c1-01,c1-02,c1-07" ] && ok "correcoes = união" || erro "correcoes" "$(jq -c .correcoes "$A")"
[ "$(jq -r '.correcoes[]|select(.id=="c1-01")|.hash' "$A")" = "$HASH_A" ] \
  && ok "c1-01 fica com o hash da rodada que o gravou (não é re-selado)" || erro "hash herdado mudou"
[ "$(jq -r '.correcoes[]|select(.id=="c1-07")|.hash' "$A")" = "$(G rev-parse "HEAD:.planning/phases/24.3-fase/24.3-CONTEXT.md")" ] \
  && ok "c1-07 selado contra o arquivo da rodada b" || erro "hash de c1-07" "$(jq -c .correcoes "$A")"
[ "$(jq -r '.caminhos|join(",")' "$A")" = ".planning/phases/24.3-fase/24.3-CONTEXT.md" ] \
  && ok "caminhos = só os da rodada vigente" || erro "caminhos" "$(jq -c .caminhos "$A")"
[ "$(jq -r '.blobs|map(.path)|sort|join(",")' "$A")" = ".planning/phases/24.3-fase/24.3-CONTEXT.md,.planning/phases/24.3-fase/24.3-SPEC.md" ] \
  && ok "blobs = selo de todo caminho do ciclo (por caminho)" || erro "blobs" "$(jq -c .blobs "$A")"
[ "$(jq -r '[.rodadas[]|.rodada+":"+(.ids|join("+"))]|join(",")' "$A")" = "c1:c1-01+c1-02,c1b:c1-07" ] \
  && ok "rodadas = c1 (c1-01, c1-02) e c1b (c1-07)" || erro "rodadas" "$(jq -c .rodadas "$A")"
[ "$(G log -1 --pretty=%s)" = "docs(fase 24.3): correções do ciclo 1 — c1-07" ] \
  && ok "assunto da rodada b = só o id novo (prefixo que o confere-reconciliacao procura)" || erro "assunto" "$(G log -1 --pretty=%s)"
case "$(G log -1 --pretty=%b)" in *"rodada: c1b (herdados das anteriores: c1-01,c1-02)"*) ok "corpo declara a rodada e os herdados" ;;
  *) erro "corpo" "$(G log -1 --pretty=%b)" ;; esac

echo "== t59 b3 — rodada c herda as duas anteriores"
vereditos 1 "c1-01 | bug | confirmado | codigo" "c1-02 | bug | confirmado | codigo" "c1-07 | bug | confirmado | codigo"
RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1
echo "review emendado na rodada c" >> "$PD/24.3-INTENT-REVIEW.md"
saida=$(RUN "$PD" 1 --ids "c1b-01" "${ALVOS[@]}" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "rodada c → exit 0" || erro "rodada c falhou ($rc)" "$saida"
[ "$(jq -r '.commits|length' "$A"):$(jq -r '.rodadas[2].rodada' "$A"):$(jq -r '.ids|join(",")' "$A")" = "3:c1c:c1-01,c1-02,c1-07,c1b-01" ] \
  && ok "3 commits, rodada c1c, ids da união" || erro "rodada c" "$(jq -c '{commits,ids,r:[.rodadas[].rodada]}' "$A")"
limpa

echo "== t59 b3 — id de rodada anterior repetido (o prompt antigo mandava) fica com a entrada herdada"
rodada_a; rodada_b_inicio
saida=$(RUN "$PD" 1 --ids "c1-01:$PD/24.3-SPEC.md,c1-02,c1-07" "${ALVOS[@]}" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "repetir c1-01 com caminho da rodada a NÃO é recusa (FM-05INT só olha ids novos)" || erro "rc=$rc" "$saida"
A="$(APL1)"
[ "$(jq -r '.correcoes[]|select(.id=="c1-01")|.hash' "$A")" = "$HASH_A" ] && ok "c1-01 manteve o hash herdado" || erro "c1-01 re-selado"
[ "$(jq -r '.correcoes|length' "$A")" = 3 ] && ok "sem entrada duplicada" || erro "duplicou" "$(jq -c .correcoes "$A")"
[ "$(G log -1 --pretty=%s)" = "docs(fase 24.3): correções do ciclo 1 — c1-07" ] && ok "assunto só com o id novo" || erro "assunto" "$(G log -1 --pretty=%s)"
limpa

echo "== t59 b3 — .aplicado anterior que NÃO confere com o git não é herdado"
rodada_a; rodada_b_inicio
A="$(APL1)"
jq '.blobs[0].blob_commit="0000000000000000000000000000000000000000"' "$A" > "$A.t" && mv "$A.t" "$A"
H0=$(G rev-parse HEAD)
saida=$(RUN "$PD" 1 --ids "c1-07" "${ALVOS[@]}" 2>&1); rc=$?
[ "$rc" = 3 ] && ok "blob adulterado → nada herdado → a trava recusa (exit 3)" || erro "esperava exit 3, veio $rc" "$saida"
case "$saida" in *"NÃO confere com o git"*) ok "o aviso diz que não confere e por quê" ;; *) erro "sem aviso" "$saida" ;; esac
case "$saida" in *"sem destino"*c1-0[12]*) ok "…e a recusa é a de sempre (confirmados sem destino)" ;; *) erro "recusa" "$saida" ;; esac
[ "$(G rev-parse HEAD)" = "$H0" ] && ok "HEAD inalterado" || erro "HEAD avançou"
limpa
rodada_a; rodada_b_inicio
A="$(APL1)"
Z=0000000000000000000000000000000000000000
jq --arg z "$Z" '.blobs[0].blob_commit=$z | .rodadas[0].blobs[0].blob_commit=$z' "$A" > "$A.t" && mv "$A.t" "$A"
saida=$(RUN "$PD" 1 --ids "c1-07" "${ALVOS[@]}" 2>&1); rc=$?
{ [ "$rc" = 3 ] && case "$saida" in *"!= blob_commit gravado"*) true ;; *) false ;; esac; } \
  && ok "blob adulterado dos dois lados (coerente) → o git desmente, não herda" || erro "adulteração coerente" "rc=$rc $saida"
limpa
rodada_a; rodada_b_inicio
A="$(APL1)"
jq '.commit="1111111111111111111111111111111111111111" | .rodadas[0].commit=.commit' "$A" > "$A.t" && mv "$A.t" "$A"
saida=$(RUN "$PD" 1 --ids "c1-07" "${ALVOS[@]}" 2>&1); rc=$?
{ [ "$rc" = 3 ] && case "$saida" in *"não existe no repositório"*) true ;; *) false ;; esac; } \
  && ok "commit inexistente → não herda (exit 3)" || erro "commit inexistente" "rc=$rc $saida"
limpa

echo "== t59 b2 — rodada b SEM alteração não apaga o registro das anteriores"
rodada_a
vereditos 1 "c1-01 | bug | confirmado | codigo" "c1-02 | bug | confirmado | codigo" "c1-07 | bug | confirmado | codigo"
RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1
M0=$(md5sum < "$(APL1)")
saida=$(RUN "$PD" 1 --ids "c1-07" "${ALVOS[@]}" 2>&1); rc=$?
[ "$rc" = 3 ] && ok "rodada sem alteração → exit 3" || erro "esperava exit 3, veio $rc" "$saida"
[ "$(md5sum < "$(APL1)")" = "$M0" ] && ok ".aplicado das rodadas anteriores intacto" || erro ".aplicado mudou/sumiu"
[ -f "$PD/.intent/.correcoes-c1.vazio" ] && erro "gravou .vazio num ciclo com commit" || ok "nenhum .vazio"
echo "== t59 b2 — --vazio num ciclo que já tem rodada comitada é recusa"
RUN "$PD" 1 --vazio >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] && ok "--vazio → exit 3" || erro "esperava exit 3, veio $rc"
[ "$(md5sum < "$(APL1)")" = "$M0" ] && ok ".aplicado intacto" || erro ".aplicado apagado pelo --vazio"
echo "== t59 b3 — rodada só com ids repetidos (nenhum novo) é recusa"
echo "context emendado" >> "$PD/24.3-CONTEXT.md"
saida=$(RUN "$PD" 1 --ids "c1-01,c1-02" "${ALVOS[@]}" 2>&1); rc=$?
{ [ "$rc" = 3 ] && case "$saida" in *"nenhum id novo"*) true ;; *) false ;; esac; } \
  && ok "sem id novo → exit 3 com a razão" || erro "rc=$rc" "$saida"
limpa

echo "== t59 b3 — .aplicado ANTERIOR ao conserto (sem rodadas/commits/adiados) é herdado"
monta_repo; set_alvos
vereditos 1 "c1-01 | bug | confirmado | codigo" "c1-02 | bug | confirmado | codigo"
RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1
echo "spec corrigida na rodada a" >> "$PD/24.3-SPEC.md"
RUN "$PD" 1 --ids "c1-01" --adiados "c1-02" "${ALVOS[@]}" >/dev/null 2>&1 || erro "rodada a falhou"
CA=$(G rev-parse HEAD); A="$(APL1)"
jq 'del(.rodadas, .commits, .adiados) | .mensagem = "docs(fase 24.3): correções do ciclo 1 — x\n\nids: c1-01\nadiados: c1-02"' "$A" > "$A.t" && mv "$A.t" "$A"
RUN "$PD" 1 --inicio "${ALVOS[@]}" >/dev/null 2>&1
echo "context na rodada b" >> "$PD/24.3-CONTEXT.md"
saida=$(RUN "$PD" 1 --ids "c1b-01" "${ALVOS[@]}" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "legado herdado: c1-02 adiado (lido da mensagem) não vira «sem destino»" || erro "rc=$rc" "$saida"
[ "$(jq -c '.commits' "$A")" = "[\"$CA\",\"$(G rev-parse HEAD)\"]" ] && ok "a 1ª rodada foi sintetizada do legado" || erro "commits" "$(jq -c .commits "$A")"
[ "$(jq -r '.adiados|join(",")' "$A")" = "c1-02" ] && ok "adiados herdados" || erro "adiados" "$(jq -c .adiados "$A")"
limpa

echo
[ "$falhas" -eq 0 ] && echo "test-correcoes-commit: TUDO OK" || echo "test-correcoes-commit: $falhas falha(s)"
[ "$falhas" -eq 0 ]
