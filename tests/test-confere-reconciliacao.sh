#!/usr/bin/env bash
# test-confere-reconciliacao.sh — bancada da reconciliação VEREDITO × APLICADO (A5a) e
# da trava de ordem releitura→correção na saída (A5b).
#
# Réguas:
#   · `confirmado` sem correção promovida é CONFIRMADO-NAO-APLICADO;
#   · `nao_sustentado` COM correção promovida é INVERSAO — o caso mais grave;
#   · id promovido sem linha de veredito é APLICADO-SEM-VEREDITO, salvo quando o id foge
#     do padrão estrito `c<N>-<NN>` (passada "b" e outras origens = fora-do-escopo, não conta);
#   · fase sem nenhum `.vereditos-c*.txt` é `n/a` e exit 0 — não se inventa falha;
#   · com --ordem, correção promovida DEPOIS da releitura do último ciclo é ORDEM-VIOLADA.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/confere-reconciliacao.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-a5-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

# fase <nome> → cria <TMP>/<nome>/.intent e ecoa o phase_dir
fase() { local d="$TMP/$1"; mkdir -p "$d/.intent"; echo "$d"; }

# vereditos <phase_dir> <C> <linha...>   (cada linha no formato "id|classe|veredito|cat")
vereditos() {
  local pd="$1" c="$2"; shift 2
  : > "$pd/.intent/.vereditos-c$c.txt"
  local l
  for l in "$@"; do
    printf '%s\n' "$l" | awk -F'|' '{printf "%s | %s | %s | %s\n",$1,$2,$3,$4}' \
      >> "$pd/.intent/.vereditos-c$c.txt"
  done
}

# aplicado <phase_dir> <C> <id,id,...>
aplicado() {
  local pd="$1" c="$2" ids="$3" json="" i
  for i in $(printf '%s' "$ids" | tr ',' ' '); do json="$json,\"$i\""; done
  json="${json#,}"
  printf '{"v":1,"ciclo":"%s","ids":[%s],"commit":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","caminhos":[]}\n' \
    "$c" "$json" > "$pd/.intent/.correcoes-c$c.aplicado"
}

echo "== as cinco classificações, uma a uma"

D=$(fase ok-confirmado); vereditos "$D" 1 "c1-01|novo|confirmado|A-produto"; aplicado "$D" 1 c1-01
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "reconciliacao: ok" && [ "$rc" = 0 ] \
  && ok "confirmado + aplicado → ok (exit 0)" || erro "confirmado aplicado não passou" "$saida"

D=$(fase ok-jacoberto); vereditos "$D" 1 "c1-01|novo|ja_coberto|D-documental"; aplicado "$D" 1 c1-01
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "reconciliacao: ok" && [ "$rc" = 0 ] \
  && ok "ja_coberto + aplicado → ok (a correção reforçou; é legítimo)" || erro "ja_coberto acusado" "$saida"

D=$(fase inversao); vereditos "$D" 4 "c4-01|novo|confirmado|A-produto" "c4-05|novo|nao_sustentado|D-documental"
aplicado "$D" 4 c4-01,c4-05
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "INVERSAO c4 c4-05" && [ "$rc" = 1 ] \
  && ok "nao_sustentado + aplicado → INVERSAO na saída + exit 1" || erro "inversão não acusada" "$saida"

D=$(fase cna); vereditos "$D" 1 "c1-04|novo|confirmado|C-instrumentacao"; aplicado "$D" 1 c1-01
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "CONFIRMADO-NAO-APLICADO c1 c1-04" && [ "$rc" = 1 ] \
  && ok "confirmado ausente do .aplicado → CONFIRMADO-NAO-APLICADO + exit 1" || erro "CNA não acusado" "$saida"

D=$(fase asv); vereditos "$D" 1 "c1-01|novo|confirmado|A-produto"; aplicado "$D" 1 c1-01,c1-07
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "APLICADO-SEM-VEREDITO c1 c1-07" && [ "$rc" = 1 ] \
  && ok "id promovido sem linha de veredito → APLICADO-SEM-VEREDITO + exit 1" || erro "ASV não acusado" "$saida"

echo "== id fora do padrão c<N>-<NN> não conta (passada \"b\" é documentada)"
D=$(fase fora); vereditos "$D" 1 "c1-01|novo|confirmado|A-produto"; aplicado "$D" 1 c1-01,c1b-01,c1b-02
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "fora-do-escopo=2" && [ "$rc" = 0 ] \
  && ok "c1b-01/c1b-02 → fora-do-escopo, exit 0" || erro "passada b contada como violação" "$saida"
# o padrão exige o espaço: a linha de resumo também traz a palavra ("APLICADO-SEM-VEREDITO=0")
printf '%s' "$saida" | grep -q "APLICADO-SEM-VEREDITO c" \
  && erro "id da passada b virou APLICADO-SEM-VEREDITO" "$saida" || ok "nenhuma linha de violação para c1b-*"

echo "== ciclo sem correção promovida"
D=$(fase sem-aplicado-limpo); vereditos "$D" 2 "c2-01|novo|nao_sustentado|D-documental"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
[ "$rc" = 0 ] && printf '%s' "$saida" | grep -q "reconciliacao: ok" \
  && ok "vereditos sem confirmado e sem .aplicado → legítimo (exit 0)" || erro "acusou ciclo legitimamente vazio" "$saida"

D=$(fase sem-aplicado-sujo); vereditos "$D" 2 "c2-01|novo|confirmado|A-produto" "c2-02|novo|confirmado|A-produto"
: > "$D/.intent/.correcoes-c2.vazio"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "ciclo marcado vazio" \
  && ok "marcador .vazio é nomeado na saída (não manda o leitor caçar o .aplicado)" || erro "marcador .vazio ignorado" "$saida"
[ "$(printf '%s' "$saida" | grep -c 'CONFIRMADO-NAO-APLICADO c')" = 2 ] && [ "$rc" = 1 ] \
  && ok "os dois confirmados viram CONFIRMADO-NAO-APLICADO + exit 1" || erro "confirmados sem correção passaram" "$saida"

echo "== terceiro campo ilegível: fail-closed dos DOIS lados"
D=$(fase ilegivel-aplicado); vereditos "$D" 1 "c1-01|novo|talvez|A-produto"; aplicado "$D" 1 c1-01
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "VEREDITO-ILEGIVEL c1 c1-01" && [ "$rc" = 1 ] \
  && ok "veredito ilegível + aplicado → VEREDITO-ILEGIVEL + exit 1" || erro "ilegível aplicado passou" "$saida"

D=$(fase ilegivel-nao-aplicado); vereditos "$D" 1 "c1-01|novo||A-produto"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "VEREDITO-ILEGIVEL c1 c1-01" && [ "$rc" = 1 ] \
  && ok "veredito vazio e NÃO aplicado também acusa (não é absorvido no contador ok)" \
  || erro "linha ilegível inflou o ok em silêncio" "$saida"

echo "== R2 (plano 3, 05/09/2026) — confirmado_irrelevante: quarto valor do veredito, não quinto campo"
D=$(fase disp-ausente); vereditos "$D" 3 "c3-01|novo|confirmado|A-produto" "c3-05|novo|confirmado_irrelevante|B-viabilidade"; aplicado "$D" 3 c3-01
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "VEREDITO-ILEGIVEL c" && erro "confirmado_irrelevante lido como ilegível" "$saida" || ok "confirmado_irrelevante não é VEREDITO-ILEGIVEL"
printf '%s' "$saida" | grep -q "CONFIRMADO-NAO-APLICADO c3 c3-05" && erro "dispensado ausente do .aplicado cobrado como CNA" "$saida" \
  || ok "dispensado ausente do .aplicado → ok (a dispensa tira o ciclo, não obriga correção)"
printf '%s' "$saida" | grep -q "dispensados=1 dispensados_aplicados=0" && [ "$rc" = 0 ] \
  && ok "resumo traz dispensados=1 dispensados_aplicados=0 e exit 0" || erro "resumo/exit" "$saida"

D=$(fase disp-aplicado); vereditos "$D" 3 "c3-05|novo|confirmado_irrelevante|B-viabilidade"; aplicado "$D" 3 c3-05
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^DISPENSADO-APLICADO c3 c3-05 veredito=confirmado_irrelevante" && [ "$rc" = 0 ] \
  && ok "dispensado presente no .aplicado → DISPENSADO-APLICADO, exit 0 (não bloqueante: nada se descarta)" || erro "DISPENSADO-APLICADO" "$saida"
printf '%s' "$saida" | grep -q "reconciliacao: ok" && ok "…e a reconciliação segue ok" || erro "classe informativa virou falha" "$saida"
printf '%s' "$saida" | grep -q "dispensados=1 dispensados_aplicados=1" && ok "resumo: dispensados=1 dispensados_aplicados=1" || erro "resumo" "$saida"

echo "== R9 (plano 3) — RELEITURA-ABERTA no último ciclo (--ordem); legado avisa"
D=$(fase rel-aberta); vereditos "$D" 4 "c4-01|novo|confirmado|A-produto"; aplicado "$D" 4 c4-01
touch -d '2026-08-30 09:00:00' "$D/.intent/.correcoes-c4.aplicado"
echo '{"v":2,"ciclo":4,"commit":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","artefatos":[],"contradiz":[{"ac_a":"AC-1","ac_b":"AC-2","porque":"x"}],"prescreve_mecanismo":[],"omissoes_novas":[],"cardinalidade":[],"consistencia":"não_disponível","ok":false}' > "$D/.intent/.releitura-c4.json"
touch -d '2026-08-30 09:05:00' "$D/.intent/.releitura-c4.json"
saida=$("$SCRIPT" "$D" --ordem 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^RELEITURA-ABERTA c4" && [ "$rc" = 1 ] \
  && ok "releitura v:2 com ok:false no último ciclo → RELEITURA-ABERTA + exit 1" || erro "releitura aberta passou" "$saida"
printf '%s' "$saida" | grep -q "^ordem: ok" && ok "…e a ordem em si continua ok (o exit 1 veio da releitura aberta)" || erro "ordem acusada indevidamente" "$saida"
sed -i 's/"ok":false/"ok":true/' "$D/.intent/.releitura-c4.json"; touch -d '2026-08-30 09:05:00' "$D/.intent/.releitura-c4.json"
saida=$("$SCRIPT" "$D" --ordem 2>&1); rc=$?
printf '%s' "$saida" | grep -q "RELEITURA-ABERTA" && erro "ok:true acusado" "$saida" || { [ "$rc" = 0 ] && ok "mesmo arquivo com ok:true → exit 0" || erro "rc=$rc" "$saida"; }
echo '{"commit":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","artefatos":[]}' > "$D/.intent/.releitura-c4.json"; touch -d '2026-08-30 09:05:00' "$D/.intent/.releitura-c4.json"
saida=$("$SCRIPT" "$D" --ordem 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^aviso: releitura c4 em formato legado" && [ "$rc" = 0 ] \
  && ok "releitura sem \`v\` (os stubs da F24.4) → aviso legado, exit 0" || erro "legado" "$saida"

echo "== fase sem ciclos e usos inválidos"
D=$(fase vazia)
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "reconciliacao: n/a" && [ "$rc" = 0 ] \
  && ok "nenhum .vereditos-c*.txt → n/a + exit 0 (não se inventa falha)" || erro "inventou falha em fase sem ciclos" "$saida"

saida=$("$SCRIPT" "$TMP/nao-existe" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "phase_dir inexistente → exit 2 (uso inválido)" || erro "esperado exit 2, veio $rc" "$saida"
saida=$("$SCRIPT" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "sem argumento → exit 2" || erro "esperado exit 2, veio $rc" "$saida"
saida=$("$SCRIPT" "$D" --nao-existe 2>&1); rc=$?
[ "$rc" = 2 ] && ok "flag desconhecida → exit 2" || erro "esperado exit 2, veio $rc" "$saida"

echo "== recorte por ciclo"
D=$(fase recorte)
vereditos "$D" 1 "c1-01|novo|confirmado|A-produto"; aplicado "$D" 1 c1-01
vereditos "$D" 2 "c2-01|novo|nao_sustentado|D-documental"; aplicado "$D" 2 c2-01
saida=$("$SCRIPT" "$D" 1 2>&1); rc=$?
[ "$rc" = 0 ] && ok "ciclo 1 isolado → exit 0 (a inversão do c2 fica fora do recorte)" || erro "recorte não respeitado" "$saida"
saida=$("$SCRIPT" "$D" 2 2>&1); rc=$?
printf '%s' "$saida" | grep -q "INVERSAO c2" && [ "$rc" = 1 ] \
  && ok "ciclo 2 isolado → INVERSAO + exit 1" || erro "recorte do c2 falhou" "$saida"

echo "== A5b — a trava de ordem na saída"
# Fixtures com reconciliação LIMPA de propósito: assim o único motivo possível de exit 1
# é a ordem, e não a reconciliação vazando por baixo.
D=$(fase ordem-ok); vereditos "$D" 3 "c3-01|novo|confirmado|A-produto"; aplicado "$D" 3 c3-01
echo '{"ciclo":3,"commit":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","ok":true}' > "$D/.intent/.releitura-c3.json"
touch -d '2026-08-30 08:51:00' "$D/.intent/.correcoes-c3.aplicado"
touch -d '2026-08-30 08:52:30' "$D/.intent/.releitura-c3.json"
saida=$("$SCRIPT" "$D" --ordem 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^ordem: ok" && [ "$rc" = 0 ] \
  && ok "releitura depois da correção → ordem: ok (exit 0)" || erro "ordem correta acusada" "$saida"

D=$(fase ordem-violada); vereditos "$D" 4 "c4-01|novo|confirmado|A-produto"; aplicado "$D" 4 c4-01
echo '{"ciclo":4,"commit":"aaaabbbbccccddddeeeeffff0000111122223333","ok":true}' > "$D/.intent/.releitura-c4.json"
touch -d '2026-08-30 09:07:46' "$D/.intent/.releitura-c4.json"
touch -d '2026-08-30 09:12:44' "$D/.intent/.correcoes-c4.aplicado"
saida=$("$SCRIPT" "$D" --ordem 2>&1); rc=$?
printf '%s' "$saida" | grep -q "ORDEM-VIOLADA" && [ "$rc" = 1 ] \
  && ok "correção depois da releitura → ORDEM-VIOLADA + exit 1" || erro "ordem violada passou" "$saida"
printf '%s' "$saida" | grep -q "reconciliacao: ok" \
  && ok "e a reconciliação segue ok — o exit 1 veio só da ordem" || erro "reconciliação vazou na fixture de ordem" "$saida"
printf '%s' "$saida" | grep -q "corroboração:" \
  && ok "acusa também a divergência de commit entre releitura e .aplicado" || erro "corroboração de hash não saiu" "$saida"

# Fail-open que existia e foi fechado: fase COM ciclo 0 e SEM nenhum .vereditos-c*.txt
# (revisão adversarial pulada). Antes, o `reconciliacao: n/a` saía 0 sem sequer olhar a
# ordem — verde no caso que o gate existe para pegar.
D=$(fase ordem-sem-vereditos); aplicado "$D" 0 c0-01
echo '{"ciclo":0,"commit":"aaaabbbbccccddddeeeeffff0000111122223333","ok":true}' > "$D/.intent/.releitura-c0.json"
touch -d '2026-08-30 08:04:00' "$D/.intent/.releitura-c0.json"
touch -d '2026-08-30 08:09:00' "$D/.intent/.correcoes-c0.aplicado"
saida=$("$SCRIPT" "$D" --ordem 2>&1); rc=$?
printf '%s' "$saida" | grep -q "reconciliacao: n/a" && printf '%s' "$saida" | grep -q "ORDEM-VIOLADA" && [ "$rc" = 1 ] \
  && ok "sem vereditos, --ordem ainda avalia o ciclo 0 → ORDEM-VIOLADA + exit 1" \
  || erro "fase sem vereditos escapou da trava de ordem (fail-open)" "$saida"

D=$(fase ordem-na); vereditos "$D" 1 "c1-01|novo|confirmado|A-produto"; aplicado "$D" 1 c1-01
saida=$("$SCRIPT" "$D" --ordem 2>&1); rc=$?
printf '%s' "$saida" | grep -q "ordem: n/a" && [ "$rc" = 0 ] \
  && ok "sem .releitura-c1.json → ordem: n/a + exit 0 (é gate de outro)" || erro "ausência de releitura virou falha aqui" "$saida"

echo "== C3 (plano 2, 05/09/2026) — D-NN-DESATUALIZADA: mexeu no SPEC, tem de olhar o CONTEXT"
# Repositório sintético: SPEC com AC-01/AC-02, CONTEXT com D-01 (cita AC-01), D-02 (cita AC-02,
# superada-c1) e D-03 (cita R2). O ciclo 1 emenda o AC-01 e o R2 no SPEC sem tocar o CONTEXT.
repo_c3() { # <nome> → REPO e PD3 globais
  REPO=$(mktemp -d "${TMPDIR:-/tmp}/gad-c3-XXXXXX"); PD3="$REPO/.planning/phases/24.4-fase"
  mkdir -p "$PD3/.intent"; git -c init.defaultBranch=main init -q "$REPO"
  printf '## Requirements\n- R1: contar linhas\n- R2: somar mensalidades\n\n## Acceptance Criteria\n- AC-01: o motor reconhece uma linha para o aluno\n- AC-02: duas mensalidades somam\n' > "$PD3/24.4-SPEC.md"
  printf '<decisions>\n## Implementation Decisions\n\n### A\n- **D-01 [auto, R1]:** decisão que cita AC-01\n- **D-02 [auto, R1, superada-c1, informational]:** decisão que cita AC-02 e ficou velha no c1\n- **D-03 [auto, R2]:** decisão ancorada em R2\n- **D-04 [auto, R1]:** decisão que não cita critério nenhum\n\n### Claude'"'"'s Discretion\n- nada\n\n</decisions>\n' > "$PD3/24.4-CONTEXT.md"
  git -C "$REPO" -c user.name=t -c user.email=t@t add -A; git -C "$REPO" -c user.name=t -c user.email=t@t commit -qm base
  git -C "$REPO" hash-object -w "$PD3/24.4-SPEC.md" > "$PD3/.intent/.base-SPEC.txt"
  git -C "$REPO" hash-object -w "$PD3/24.4-CONTEXT.md" > "$PD3/.intent/.base-CONTEXT.txt"
}
G3() { git -C "$REPO" -c user.name=t -c user.email=t@t "$@"; }
aplicado3() { # <C> <commit> <caminhos separados por vírgula>
  local cam; cam=$(printf '%s' "$3" | tr ',' '\n' | sed 's/.*/"&"/' | paste -sd, -)
  printf '{"v":1,"ciclo":"%s","ids":["c%s-01"],"commit":"%s","caminhos":[%s]}\n' "$1" "$1" "$2" "$cam" > "$PD3/.intent/.correcoes-c$1.aplicado"
}
repo_c3
sed -i 's/AC-01: o motor reconhece uma linha/AC-01: o motor reconhece zero ou mais linhas/; s/R2: somar mensalidades/R2: somar mensalidades ativas/; s/AC-02: duas mensalidades somam/AC-02: duas mensalidades ativas somam/' "$PD3/24.4-SPEC.md"
G3 add -A; G3 commit -qm "docs(fase 24.4): correções do ciclo 1 — c1-01"
C1=$(G3 rev-parse HEAD); aplicado3 1 "$C1" ".planning/phases/24.4-fase/24.4-SPEC.md"
saida=$("$SCRIPT" "$PD3" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^D-NN-DESATUALIZADA c1 D-01 — cita AC-01 (SPEC mudou em ${C1:0:8}); CONTEXT fora dos caminhos do ciclo" \
  && ok "SPEC emendado (AC-01) + CONTEXT parado → D-NN-DESATUALIZADA c1 D-01, id como 3º token" || erro "D-01 não acusada" "$saida"
printf '%s' "$saida" | grep -q "^D-NN-DESATUALIZADA c1 D-03 — cita R2" && ok "eixo R-n: D-03 (cita R2 mudado) também acusa" || erro "eixo R-n mudo" "$saida"
printf '%s' "$saida" | grep -q "D-NN-DESATUALIZADA c1 D-02" && erro "superada-c1 ainda acusada" || ok "tag superada-c1 → D-02 não acusa (mesmo citando AC-02 mudado)"
printf '%s' "$saida" | grep -q "D-NN-DESATUALIZADA c1 D-04" && erro "falso positivo: D-04 não cita critério" || ok "D-04 (sem id citado) nunca aparece"
printf '%s' "$saida" | grep -q "^informativos: D-NN-DESATUALIZADA=2$" && ok "contagem em informativos: D-NN-DESATUALIZADA=2" || erro "linha informativos" "$saida"
printf '%s' "$saida" | grep -q "^nota c1: CONTEXT ausente dos caminhos" && ok "nota declara o CONTEXT fora dos caminhos do ciclo" || erro "nota do CONTEXT ausente"
[ "$rc" = 0 ] && ok "informativo: o exit continua 0 (sem vereditos, sem classe antiga)" || erro "D-NN-DESATUALIZADA mudou o exit (rc=$rc)"
# --final: base selada → worktree; um passe «b» fora do .aplicado emenda o AC-02 (D-02 é superada → não conta) e o CONTEXT toca a D-01
sed -i 's/D-01 \[auto, R1\]:\*\* decisão que cita AC-01/D-01 [auto, R1]:** decisão que cita AC-01 (emendada no c1b)/' "$PD3/24.4-CONTEXT.md"
G3 add -A; G3 commit -qm "docs(fase 24.4): passe b fora do .aplicado"
saida=$("$SCRIPT" "$PD3" --final 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^D-NN-DESATUALIZADA final D-03 — cita R2" && ok "--final: D-03 continua desatualizada contra a base selada" || erro "--final não acusou D-03" "$saida"
printf '%s' "$saida" | grep -q "D-NN-DESATUALIZADA final D-01" && erro "--final acusou D-01, que foi tocada no CONTEXT" || ok "--final: D-01 tocada no CONTEXT (base → worktree) não acusa"
printf '%s' "$saida" | grep -q "^desatualizadas final: 1 " && ok "--final: contagem 1" || erro "contagem do --final" "$saida"
[ "$rc" = 0 ] && ok "--final também é informativo (exit 0)" || erro "--final mudou o exit (rc=$rc)"
# ciclo cujo commit não tocou o SPEC (o passe b acima só mexeu no CONTEXT) → n/a; sem base selada → final n/a
aplicado3 2 "$(G3 rev-parse HEAD)" ".planning/phases/24.4-fase/24.4-CONTEXT.md"
saida=$("$SCRIPT" "$PD3" 2 2>&1)
printf '%s' "$saida" | grep -q "^nota c2: SPEC fora dos caminhos do commit" && ok "ciclo sem SPEC nos caminhos → nota n/a, nada acusado" || erro "n/a do ciclo sem SPEC" "$saida"
printf '%s' "$saida" | grep -q "DESATUALIZADA c2" && erro "acusou sem SPEC no ciclo" || ok "nenhuma D-NN-DESATUALIZADA c2"
rm -f "$PD3/.intent/.base-SPEC.txt"
saida=$("$SCRIPT" "$PD3" --final 2>&1)
printf '%s' "$saida" | grep -q "^final: n/a (sem .base-SPEC.txt" && ok "fase sem base selada → final: n/a (nunca falha)" || erro "final sem base" "$saida"
rm -rf "$REPO"

echo
[ "$falhas" -eq 0 ] && echo "test-confere-reconciliacao: TUDO OK" || echo "test-confere-reconciliacao: $falhas falha(s)"
[ "$falhas" -eq 0 ]
