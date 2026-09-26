#!/usr/bin/env bash
# test-fase-formato.sh — tarefa 57 (v2.10.1): uma pasta `.gad/` por fase.
#
# Cobre o C6 do plano: tabela única (bash × Python iguais); fase nova ganha `.gad/FORMATO`
# (commitado na abertura) e fase antiga NÃO ganha; fence e trava de gate nos dois formatos;
# fiscal verde nos dois; `commita-artefatos … evidencia` nos dois; lane com arquivo ignorado
# nos dois; DURA × RESTO do fiscal no formato novo; o ciclo de lanes (roda-lanes com dublê →
# registra-ciclo → decide-ciclo → confere-rotas) inteiro no formato novo.
set -u

RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SC="$RAIZ/skills/go-and-do/scripts"
export RUNLOG_SEM_ESPELHO=1

OK=0; FALHAS=0
ok()    { OK=$((OK+1)); printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }
sim()   { if eval "$2"; then ok "$1"; else falha "$1" "falhou: $2"; fi; }

BASE="${KEEP_BASE:-$(mktemp -d)}"; [ -n "${KEEP_BASE:-}" ] || trap 'rm -rf "$BASE"' EXIT
export RUNTIME_DIR="$BASE/runtime"; mkdir -p "$RUNTIME_DIR/gsd-core/bin"
cat > "$RUNTIME_DIR/gsd-core/bin/gsd-tools.cjs" <<'CJS'
const fs = require('fs'); const a = process.argv.slice(2);
if (a[0] === 'query' && a[1] === 'init.phase-op') { process.stdout.write(fs.readFileSync(process.env.GAD_FIXTURE, 'utf8')); process.exit(0); }
if (a[0] === 'query' && a[1] === 'roadmap.get-phase') { process.stdout.write('{"found":false}'); process.exit(0); }
if (a[0] === 'query' && a[1] === 'config-get') { process.stdout.write('false'); process.exit(0); }
process.exit(0);
CJS

projeto() { # <nome> [antigo] → root (fase 99-bancada; `antigo` = já tem evidência .intent/)
  local r="$BASE/$1" pd
  pd="$r/.planning/phases/99-bancada"; mkdir -p "$pd"
  git init -q "$r"; git -C "$r" config user.name t; git -C "$r" config user.email t@t
  printf '# ROADMAP\n\n### Phase 99: bancada\n**Goal:** provar o layout .gad/ da fase\n**Requirements:** BAN-01\n' > "$r/.planning/ROADMAP.md"
  printf '# Requirements\n- [ ] **BAN-01**: layout\n' > "$r/.planning/REQUIREMENTS.md"; printf '{}\n' > "$r/.planning/config.json"
  # mesma regra de ignore que o RLR tem na raiz (inventário A3)
  printf '.planning/phases/*/pareceres/.codex-*\n.planning/phases/*/pareceres/*.launch.log\n' > "$r/.gitignore"
  printf '# spec\n' > "$pd/99-SPEC.md"
  if [ "${2:-}" = antigo ]; then mkdir -p "$pd/.intent"; printf 'x\n' > "$pd/.intent/.sinos-spec.txt"; fi
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q -m base
  printf '{"phase_found":true,"phase_number":"99","phase_name":"bancada","phase_dir":"%s","expected_phase_dir":null,"padded_phase":"99","planning_exists":true,"has_context":false,"has_plans":false,"has_research":false,"has_reviews":false,"has_verification":false,"plan_count":0}' "$pd" > "$r/fix.json"
  printf '%s' "$r"
}
abre() { ( cd "$1" && GAD_FIXTURE="$1/fix.json" CLAUDE_CODE_SESSION_ID= bash "$SC/abre-rodada.sh" 99 --projeto "$1" 2>/dev/null | head -1 ); }

echo "── tabela única: bash × Python ──"
DIFS=0
for r in intent/c1/vereditos.txt 'intent/c*/vereditos.txt' 'intent/c*/status-*.json' intent/c1/done-codex \
         intent/c1/briefing.md intent/c1/briefing-reformat-agy.md intent/c1/runs/R/x intent/c0/ciclo.json \
         intent/c0b/releitura.json 'intent/c0*/releitura.done' intent/c2/correcoes.pre-3.patch \
         intent/sinos-spec.txt intent/pre-spec-route.json intent/base-SPEC.txt convergencia/c1/done-agy \
         convergencia/c2/briefing.md lanes/roda-planrev-codex-c1.json lanes/tabela-c1.txt fences/4.1b.ok \
         gates/5.json gates/5-evidencia.txt plan-checker/iter-2.yaml pos-ship/vereditos.json uat/humano-4.1.md; do
  b="$(bash -c ". '$SC/lib/gad-caminhos.sh'; gad_fase_legado_rel '$r'")"
  p="$(python3 -B -c "import sys; sys.path.insert(0,'$SC/lib'); import gad_caminhos as g; print(g.legado_rel('$r'))")"
  [ "$b" = "$p" ] || { DIFS=$((DIFS+1)); echo "     $r: bash=$b py=$p"; }
done
eq "24 nomes (inclusive globs) traduzem igual nos dois helpers" "$DIFS" "0"

echo "── 57(b): quem abre a fase decide o formato ──"
RN=$(projeto novo); PDN="$RN/.planning/phases/99-bancada"
J=$(abre "$RN")
sim "fase sem evidência ganha .gad/FORMATO"                   "[ -f '$PDN/.gad/FORMATO' ]"
sim "…e .gad/lanes/.gitignore com codex-* e *.launch.log"     "grep -qx 'codex-\\*' '$PDN/.gad/lanes/.gitignore' && grep -qx '\\*.launch.log' '$PDN/.gad/lanes/.gitignore'"
eq  "FORMATO commitado na abertura (antes de qualquer worktree)" "$(git -C "$RN" ls-files "$PDN/.gad/FORMATO" | wc -l | tr -d ' ')" "1"
eq  "abre-rodada relata formato_fase=novo, formato_commit=ok"  "$(jq -r '.rodada.formato_fase+","+.rodada.formato_commit' <<<"$J")" "novo,ok"
J2=$(abre "$RN")
eq  "reabrir não recommita (ja_commitado)"                     "$(jq -r .rodada.formato_commit <<<"$J2")" "ja_commitado"
RA=$(projeto antigo antigo); PDA="$RA/.planning/phases/99-bancada"
J=$(abre "$RA")
sim "fase com .intent/ NÃO ganha FORMATO"                      "[ ! -e '$PDA/.gad' ]"
eq  "…formato_fase=antigo"                                     "$(jq -r .rodada.formato_fase <<<"$J")" "antigo"
RB=$(projeto oxlegado); PDB="$RB/.planning/phases/99-bancada"
mkdir -p "$PDB/pareceres/conv"; : > "$PDB/pareceres/conv/.done-conv-c1-codex"
abre "$RB" >/dev/null
sim "layout ainda mais velho (pareceres/conv/.done-*) também fica antigo" "[ ! -e '$PDB/.gad' ]"

echo "── fence, trava de gate e fiscal nos dois formatos ──"
for par in "novo|$RN|$PDN|.gad/fences/0.ok" "antigo|$RA|$PDA|.fence-0.ok"; do
  IFS='|' read -r fmt R PD FEN <<<"$par"
  ( cd "$R" && bash "$SC/confere-etapa.sh" 0 --projeto "$R" --fase 99 >/dev/null 2>&1 ); rc=$?
  eq  "[$fmt] fiscal da etapa 0 verde (exit 0)"                "$rc" "0"
  sim "[$fmt] recibo em $FEN"                                  "[ -s '$PD/$FEN' ]"
done
sim "[novo] nenhum .fence-*.ok solto na pasta da fase"         "! ls '$PDN'/.fence-* >/dev/null 2>&1"
( cd "$RN" && bash "$SC/confere-etapa.sh" 1 --projeto "$RN" --fase 99 >/dev/null 2>&1 )
# t59 (FM-F27INS-01ENC): a trava é estado da rodada — sai da pasta da fase nos dois formatos
sim "[novo] fail grava a trava em .planning/.gad/gates/<fase>/1.json" "[ -s '$RN/.planning/.gad/gates/99-bancada/1.json' ]"
sim "[novo] …e nenhuma trava na pasta da fase (evidência)"     "[ ! -e '$PDN/.gad/gates/1.json' ] && ! ls '$PDN'/.gate-fail-* >/dev/null 2>&1"
OUT=$(bash "$SC/run-log.sh" "$PDN" 99 end "1 intencao" --kv veredito=pass 2>&1)
case "$OUT" in *GATE-EM-FAIL*) ok "[novo] run-log recusa o end com a trava viva (dente do gate)" ;;
  *) falha "[novo] run-log recusa o end com a trava viva" "$OUT" ;; esac
( cd "$RA" && bash "$SC/confere-etapa.sh" 1 --projeto "$RA" --fase 99 >/dev/null 2>&1 )
sim "[antigo] fail grava a trava em .planning/.gad/gates/<fase>/1.json" "[ -s '$RA/.planning/.gad/gates/99-bancada/1.json' ] && [ ! -e '$PDA/.gate-fail-1.json' ]"
OUT=$(bash "$SC/run-log.sh" "$PDA" 99 end "1 intencao" --kv veredito=pass 2>&1)
case "$OUT" in *GATE-EM-FAIL*) ok "[antigo] run-log recusa o end com a trava viva" ;;
  *) falha "[antigo] run-log recusa o end com a trava viva" "$OUT" ;; esac

# leitura dupla por 1 release: trava deixada no caminho ANTIGO por uma rodada da v2.10.1
mkdir -p "$PDN/.gad/gates"; printf '{"etapa":"2","ts":"x","resumo":"falhas: legado"}\n' > "$PDN/.gad/gates/2.json"
OUT=$(bash "$SC/run-log.sh" "$PDN" 99 end "2 planejamento" --kv veredito=pass 2>&1)
case "$OUT" in *GATE-EM-FAIL*) ok "[novo] run-log recusa o end com a trava ANTIGA viva (leitura dupla)" ;;
  *) falha "[novo] run-log recusa o end com a trava antiga viva" "$OUT" ;; esac
rm -f "$PDN/.gad/gates/2.json"
PYT=$(python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import gad_caminhos as g; print("|".join(g.trava_caminhos(sys.argv[2], "5")))' "$SC/lib" "$PDN")
eq  "[py] trava_caminhos = novo e antigo, nessa ordem"          "$PYT" "$RN/.planning/.gad/gates/99-bancada/5.json|$PDN/.gad/gates/5.json"
SHT=$(bash -c '. "$1/lib/gad-caminhos.sh"; gad_trava_caminhos "$2" 5 | paste -sd"|"' _ "$SC" "$PDN")
eq  "[sh] gad_trava_caminhos = o mesmo que o gêmeo Python"      "$SHT" "$PYT"
# t59 (L10): a lista inteira da pasta suja mora no estado ignorado da rodada — gêmeos sh×py
PYS=$(python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import gad_caminhos as g; print(g.pasta_suja_caminho(sys.argv[2], "4-code-review"))' "$SC/lib" "$PDN")
eq  "[py] pasta_suja_caminho = .planning/.gad/pasta-suja/<fase>/<etapa>.txt" "$PYS" "$RN/.planning/.gad/pasta-suja/99-bancada/4-code-review.txt"
SHS=$(bash -c '. "$1/lib/gad-caminhos.sh"; gad_pasta_suja_caminho "$2" "4-code-review"' _ "$SC" "$PDN")
eq  "[sh] gad_pasta_suja_caminho = o mesmo que o gêmeo Python"  "$SHS" "$PYS"
SHE=$(bash -c '. "$1/lib/gad-caminhos.sh"; gad_pasta_suja_caminho "$2" "5 uat"' _ "$SC" "$PDN")
PYE=$(python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import gad_caminhos as g; print(g.pasta_suja_caminho(sys.argv[2], "5 uat"))' "$SC/lib" "$PDN")
eq  "[sh×py] etapa com espaço vira _ nos dois"                   "$SHE|$PYE" "$RN/.planning/.gad/pasta-suja/99-bancada/5_uat.txt|$RN/.planning/.gad/pasta-suja/99-bancada/5_uat.txt"

echo "── ciclo de lanes inteiro no formato novo (dublês) ──"
export GAD_LANES_DIR="$RAIZ/tests/fixtures/roda-lanes/stub" GAD_ESPERAR_PASSO=1
IC() { bash -c ". '$SC/lib/gad-caminhos.sh'; gad_fase_caminho '$PDN' 'intent/$1'"; }
mkdir -p "$PDN/.gad/intent/c1"
printf 'Briefing.\nprova_leitura: <token>\n' > "$(IC c1/briefing.md)"
printf 'Token: PROVA-abc123\n' > "$(IC c1/prova-leitura.txt)"
bash "$SC/roda-lanes.sh" "$PDN" 99 1 "$(IC c1/briefing.md)" --prova "$(IC c1/prova-leitura.txt)" --lanes "codex agy" >/dev/null
ESP=$(bash "$SC/roda-lanes.sh" "$PDN" 99 1 --esperar 2>/dev/null | tail -1)
eq  "roda-lanes --esperar acha as duas lanes"                  "$(jq -r .esperado <<<"$ESP")" "true"
sim "ponteiro do ciclo em .gad/intent/c1/run-atual"            "[ -s '$PDN/.gad/intent/c1/run-atual' ]"
sim "run-dir em .gad/intent/c1/runs/<id>/"                     "[ -d '$PDN/.gad/intent/c1/runs/'\$(cat '$PDN/.gad/intent/c1/run-atual') ]"
sim "status e done promovidos em .gad/intent/c1/"              "[ -s '$PDN/.gad/intent/c1/status-codex.json' ] && [ -e '$PDN/.gad/intent/c1/done-agy' ]"
sim "espelho da lane em .gad/lanes/roda-codex-c1.json"         "[ -s '$PDN/.gad/lanes/roda-codex-c1.json' ]"
sim "parecer visível continua em pareceres/"                   "[ -s '$PDN/pareceres/99-parecer-codex-c1.md' ]"
sim "nenhum dotfile novo em pareceres/ nem .intent/"           "[ -z \"\$(find '$PDN/pareceres' -name '.*' 2>/dev/null)\" ] && [ ! -e '$PDN/.intent' ]"
bash "$SC/registra-ciclo.sh" "$PDN" 99 1 intencao >/dev/null 2>&1
sim "registra-ciclo grava a tabela em .gad/lanes/tabela-c1.txt" "[ -s '$PDN/.gad/lanes/tabela-c1.txt' ]"
printf 'c1-01 | novo | confirmado | A-produto\n' > "$(IC c1/vereditos.txt)"
DC=$(cd "$RN" && bash "$SC/decide-ciclo.sh" "$PDN" 1 2>/dev/null | tail -1)
sim "decide-ciclo lê os vereditos do formato novo"             "jq -e '.decisao != \"sem_dados\"' >/dev/null <<<'$DC'"
cp "$PDN/.gad/lanes/tabela-c1.txt" "$(IC c1/tabela.txt)"
: > "$(IC c1/verificador.done)"; printf '{"mode":"child"}\n' > "$(IC c1/rota-verificacao.json)"
CR=$(bash "$SC/confere-rotas.sh" "$PDN/.gad/intent" 2>&1); rc=$?
case "$CR" in *"ok c1"*|*"rota ok c1"*) ok "confere-rotas acha o ciclo 1 em .gad/intent/ (exit $rc)" ;;
  *) falha "confere-rotas acha o ciclo 1 em .gad/intent/" "$CR" ;; esac

echo "── lane com arquivo ignorado nos dois formatos ──"
: > "$PDN/.gad/lanes/codex-c1.err"; : > "$PDN/.gad/lanes/codex-review.done"; : > "$PDN/.gad/lanes/x.launch.log"
mkdir -p "$PDA/pareceres"; : > "$PDA/pareceres/.codex-c1.err"; : > "$PDA/pareceres/.codex-review.done"; : > "$PDA/pareceres/x.launch.log"
eq  "[novo] codex-*/launch.log fora do git status"            "$(git -C "$RN" status --porcelain --untracked-files=all | grep -cE 'codex-c1.err|codex-review.done|launch.log' || true)" "0"
eq  "[antigo] idem (regra do .gitignore do projeto)"           "$(git -C "$RA" status --porcelain --untracked-files=all | grep -cE 'codex-c1.err|codex-review.done|launch.log' || true)" "0"

echo "── DURA × RESTO do fiscal no formato novo ──"
git -C "$RN" add -A >/dev/null 2>&1; git -C "$RN" commit -q -m tudo >/dev/null 2>&1
mkdir -p "$PDN/.gad/plan-checker"; printf 'status: ok\n' > "$PDN/.gad/plan-checker/iter-1.yaml"
F=$(cd "$RN" && bash "$SC/confere-etapa.sh" 2 --projeto "$RN" --fase 99 --dry-run 2>/dev/null | tail -1)
eq  "[novo] plan-checker/ fora de commit na etapa 2 = AVISO (como .plan-checker/ sempre foi)" \
    "$(jq -r '[.asserts[]? | select(.id=="evidencia_fora_do_git")] | length' <<<"$F")" "0"
printf 'nova\n' > "$(IC c1/licoes.txt)"
F=$(cd "$RN" && bash "$SC/confere-etapa.sh" 2 --projeto "$RN" --fase 99 --dry-run 2>/dev/null | tail -1)
eq  "[novo] intent/ fora de commit na etapa 2 = FALHA dura"   "$(jq -r '[.asserts[]? | select(.id=="evidencia_fora_do_git" and .resultado=="FALHA")] | length' <<<"$F")" "1"

echo "── commita-artefatos … evidencia nos dois formatos ──"
( cd "$RN" && bash "$SC/commita-artefatos.sh" "$PDN" 99 evidencia >/dev/null 2>&1 )
LS=$(git -C "$RN" ls-files "$PDN")
for f in .gad/FORMATO .gad/lanes/.gitignore .gad/intent/c1/vereditos.txt .gad/intent/c1/licoes.txt .gad/lanes/roda-codex-c1.json .gad/fences/0.ok .gad/plan-checker/iter-1.yaml; do
  sim "[novo] commitado: $f" "grep -qF '$PDN/$f' <<<'$LS' || grep -qF '.planning/phases/99-bancada/$f' <<<'$LS'"
done
for f in .gad/lanes/codex-c1.err .gad/lanes/codex-review.done .gad/lanes/x.launch.log; do
  sim "[novo] NÃO commitado: $f" "! grep -qF '99-bancada/$f' <<<'$LS'"
done
eq  "[novo] pasta da fase com exatamente UMA entrada oculta"    "$(ls -A "$PDN" | grep -c '^\.' )" "1"
mkdir -p "$PDA/.intent"; printf 'l\n' > "$PDA/.intent/.licoes-c1.txt"
( cd "$RA" && bash "$SC/commita-artefatos.sh" "$PDA" 99 evidencia >/dev/null 2>&1 )
LSA=$(git -C "$RA" ls-files "$PDA")
sim "[antigo] commitado: .intent/.licoes-c1.txt"               "grep -qF '99-bancada/.intent/.licoes-c1.txt' <<<'$LSA'"
sim "[antigo] nada foi escrito no formato novo"                "[ ! -e '$PDA/.gad' ]"

echo
echo "$OK ok / $FALHAS falhas"
[ "$FALHAS" -eq 0 ]
