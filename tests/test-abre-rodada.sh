#!/usr/bin/env bash
# test-abre-rodada.sh — bancada do estágio 3 (retrato) do abre-rodada.sh:
#   resolução do diretório da fase = phase_dir → expected_phase_dir → ERRO.
#
# O bug corrigido em 29/08/2026 (plano /gad-pre-spec, §4): quando o `init.phase-op`
# devolvia `phase_dir` vazio (fase no ROADMAP, pasta ainda não criada), o script caía
# num nome INVENTADO — `.planning/phases/<NN>-nova` — que nenhum workflow do GSD
# encontra; o `NN-PRE-SPEC.md` do dono ficava invisível. O GSD já diz onde a pasta deve
# nascer, em `expected_phase_dir` (com o prefixo do projeto: `RLR-03-deploy-operacao`).
#
# Bancada ISOLADA (mktemp): nenhum projeto real é lido ou escrito. O `gsd-tools` é
# mockado por um .cjs em $RUNTIME_DIR/gsd-core/bin/ (1ª posição do resolvedor do
# lib/gsd-shim.sh), que ecoa a fixture de `init.phase-op` pedida por env.
# Tudo roda com --dry-run: nada de evento `run`, ponteiro ou mkdir.
#   bash tests/test-abre-rodada.sh      · exit 0 = verde
set -u

RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
S="$RAIZ/skills/go-and-do/scripts/abre-rodada.sh"

OK=0; FALHAS=0
ok()    { OK=$((OK+1)); printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }
casa()  { if printf '%s' "$2" | grep -qE "$3"; then ok "$1"; else falha "$1" "não casou /$3/ em: $(printf '%s' "$2" | head -c 300)"; fi; }
nao_casa() { if printf '%s' "$2" | grep -qE "$3"; then falha "$1" "casou /$3/ e não devia"; else ok "$1"; fi; }

BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT

# ── projeto de mentira ───────────────────────────────────────────────────────
ROOT="$BASE/proj"
mkdir -p "$ROOT/.planning/phases/RLR-02-identidade"
git init -q "$ROOT" >/dev/null 2>&1
printf '# ROADMAP\n' > "$ROOT/.planning/ROADMAP.md"

# ── mock do gsd-tools ────────────────────────────────────────────────────────
# O shim resolve na ordem: $RUNTIME_DIR/gsd-core/bin/gsd-tools.cjs (via `node`) → …
export RUNTIME_DIR="$BASE/runtime"
mkdir -p "$RUNTIME_DIR/gsd-core/bin"
cat > "$RUNTIME_DIR/gsd-core/bin/gsd-tools.cjs" <<'CJS'
// mock: só responde `query init.phase-op <N>` com a fixture apontada por GAD_FIXTURE.
const fs = require('fs');
const a = process.argv.slice(2);
if (a[0] === 'query' && a[1] === 'init.phase-op') {
  process.stdout.write(fs.readFileSync(process.env.GAD_FIXTURE, 'utf8'));
  process.exit(0);
}
process.exit(0);
CJS

fixture() { # fixture <nome> <json> → exporta GAD_FIXTURE
  printf '%s' "$2" > "$BASE/$1.json"; export GAD_FIXTURE="$BASE/$1.json"
}
EXIT=0
J=""
roda() { # roda <N> → grava $EXIT e $J (stdout+stderr). Sem command substitution:
         # `$(roda …)` roda em subshell e o exit code se perderia.
  ( cd "$ROOT" && CLAUDE_CODE_SESSION_ID= bash "$S" "$1" --projeto "$ROOT" --dry-run ) \
    > "$BASE/saida.txt" 2>&1
  EXIT=$?
  J="$(cat "$BASE/saida.txt")"
}
campo() { printf '%s' "$1" | grep -o '^{.*}$' | tail -1 | jq -r "$2" 2>/dev/null || printf '<json-invalido>'; }

# ═════════════════════════════════════ caso 1: pasta existe → phase_dir manda
echo "── caso 1: phase_dir preenchido (pasta no disco) ──"
fixture c1 "{\"phase_found\":true,\"phase_number\":\"RLR-02\",\"phase_name\":\"identidade\",
  \"phase_dir\":\"$ROOT/.planning/phases/RLR-02-identidade\",\"expected_phase_dir\":null,
  \"padded_phase\":\"02\",\"planning_exists\":true,\"has_context\":true,\"has_plans\":false,
  \"has_research\":false,\"has_reviews\":false,\"has_verification\":false,\"plan_count\":0}"
roda 2
eq  "exit 0"                      "$EXIT" "0"
eq  "usa o phase_dir do SDK"      "$(campo "$J" .rodada.phase_dir)" "$ROOT/.planning/phases/RLR-02-identidade"
nao_casa "nada de -nova na saída" "$J" '\-nova'

# ═══════════════════════ caso 2: fase no ROADMAP sem pasta → expected_phase_dir
echo "── caso 2: phase_dir vazio + expected_phase_dir (o bug do \$NN-nova) ──"
fixture c2 "{\"phase_found\":true,\"phase_number\":\"3\",\"phase_name\":\"Deploy\",
  \"phase_dir\":null,\"expected_phase_dir\":\"$ROOT/.planning/phases/RLR-03-deploy-operacao\",
  \"padded_phase\":\"03\",\"planning_exists\":true,\"has_context\":false,\"has_plans\":false,
  \"has_research\":false,\"has_reviews\":false,\"has_verification\":false,\"plan_count\":0}"
roda 3
eq  "exit 0"                                "$EXIT" "0"
eq  "cai no expected_phase_dir do SDK"      "$(campo "$J" .rodada.phase_dir)" "$ROOT/.planning/phases/RLR-03-deploy-operacao"
nao_casa "NUNCA mais o nome inventado"      "$J" '03-nova'
eq  "--dry-run não criou a pasta"           "$([ -d "$ROOT/.planning/phases/RLR-03-deploy-operacao" ] && echo sim || echo nao)" "nao"

# ══════════════════════════ caso 3: os dois vazios → erro claro, exit 5
echo "── caso 3: phase_dir e expected_phase_dir vazios → exit 5 ──"
fixture c3 '{"phase_found":true,"phase_number":"7","phase_name":"Orfa",
  "phase_dir":null,"expected_phase_dir":null,
  "padded_phase":"07","planning_exists":true,"has_context":false,"has_plans":false,
  "has_research":false,"has_reviews":false,"has_verification":false,"plan_count":0}'
roda 7
eq   "exit 5 (documentado no cabeçalho)" "$EXIT" "5"
casa "erro diz que a fase ESTÁ no ROADMAP" "$J" 'está no ROADMAP mas o diretório não pôde ser resolvido'
casa "erro aponta a saída /gad-pre-spec"   "$J" '/gad-pre-spec 7'
nao_casa "sem nome inventado"              "$J" '07-nova'

# ══════════════════════════ caso 4: fase fora do ROADMAP → exit 4 (inalterado)
echo "── caso 4: phase_found=false → exit 4 (comportamento antigo, intacto) ──"
fixture c4 '{"phase_found":false,"phase_number":null,"phase_name":null,
  "phase_dir":null,"expected_phase_dir":null,"padded_phase":null,"planning_exists":true,
  "has_context":false,"has_plans":false,"has_research":false,"has_reviews":false,
  "has_verification":false,"plan_count":0}'
roda 99
eq   "exit 4"                        "$EXIT" "4"
casa "erro de fase fora do ROADMAP"  "$J" 'fase 99 não está no ROADMAP'

# ══════════════════════════ caso 5: o PRE-SPEC é achado no dir resolvido
echo "── caso 5: NN-PRE-SPEC.md no expected_phase_dir é detectado ──"
mkdir -p "$ROOT/.planning/phases/RLR-03-deploy-operacao"
printf '# PRE-SPEC\n' > "$ROOT/.planning/phases/RLR-03-deploy-operacao/03-PRE-SPEC.md"
export GAD_FIXTURE="$BASE/c2.json"
roda 3
eq "pre_spec apontado no dir certo" "$(campo "$J" .pre_spec) " \
   "$ROOT/.planning/phases/RLR-03-deploy-operacao/03-PRE-SPEC.md "

# ══════════════════════════ caso 6: inventário da fase (D7) coerente com o disco
echo "── caso 6: inventario spec/context/pre_spec relata o disco, sem decidir ──"
eq "só o PRE-SPEC no disco" "$(campo "$J" .inventario)" "spec=nao context=nao pre_spec=sim"
printf '# SPEC\n' > "$ROOT/.planning/phases/RLR-03-deploy-operacao/03-SPEC.md"
printf '# CONTEXT\n' > "$ROOT/.planning/phases/RLR-03-deploy-operacao/03-CONTEXT.md"
roda 3
eq "SPEC e CONTEXT escritos → inventário muda"  "$(campo "$J" .inventario)" "spec=sim context=sim pre_spec=sim"
eq "etapa_1 continua sendo relato do disco (despachar)" "$(campo "$J" .etapa_1)" "despachar"

echo
echo "abre-rodada: $OK ok · $FALHAS falhas"
[ "$FALHAS" -eq 0 ]
