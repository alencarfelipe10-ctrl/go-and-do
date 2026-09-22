#!/usr/bin/env bash
# test-confere-ponteiros-plano.sh — bancada do confere-ponteiros-plano.sh (FJ-F4RLR-02PLAN).
# SÓ AVISA: exit é sempre 0 (ferramenta de relato, no molde do test-confere-plano.sh).
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
S="$AQUI/../skills/go-and-do/scripts/confere-ponteiros-plano.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-ptrplano-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else erro "$1" "esperado [$3], obtido [$2]"; fi; }

echo "== (1) PONTEIRO-ONDA-ANTERIOR — read_first cita arquivo:linha que onda anterior reescreve"
PD="$TMP/fase-a"; mkdir -p "$PD"
cat > "$PD/7-01-PLAN.md" <<'EOF'
---
phase: "7"
plan: 01
wave: 1
files_modified:
  - src/a.py
---
<tasks><task type="auto"><read_first>
- alguma coisa sem ponteiro
</read_first></task></tasks>
EOF
cat > "$PD/7-02-PLAN.md" <<'EOF'
---
phase: "7"
plan: 02
wave: 2
files_modified:
  - src/b.py
---
<tasks><task type="auto"><read_first>
- src/a.py:42 (onde o teste espera)
</read_first></task></tasks>
EOF
OUT=$(bash "$S" "$PD"); RC=$?
eq "exit 0 (só avisa)" "$RC" 0
eq "1 aviso" "$(jq -r .total <<<"$OUT")" 1
eq "código certo" "$(jq -r '.avisos[0].codigo' <<<"$OUT")" "PONTEIRO-ONDA-ANTERIOR"
eq "aponta pro plano certo" "$(jq -r '.avisos[0].plano' <<<"$OUT")" "7-02-PLAN.md"

echo "== (1b) arquivo reescrito por onda POSTERIOR (ainda não rodou) não é PONTEIRO-ONDA-ANTERIOR"
PD2="$TMP/fase-b"; mkdir -p "$PD2"
cat > "$PD2/7-01-PLAN.md" <<'EOF'
---
phase: "7"
plan: 01
wave: 1
files_modified:
  - src/a.py
---
<tasks><task type="auto"><read_first>
- src/a.py:10
</read_first></task></tasks>
EOF
cat > "$PD2/7-02-PLAN.md" <<'EOF'
---
phase: "7"
plan: 02
wave: 2
files_modified:
  - src/a.py
---
<tasks><task type="auto"><read_first>
- nada aqui
</read_first></task></tasks>
EOF
OUT=$(bash "$S" "$PD2")
eq "onda 1 lê src/a.py antes da onda 2 reescrever → sem aviso (a onda 2 é POSTERIOR)" "$(jq -r .total <<<"$OUT")" 0

echo "== (2) SECAO-FORA-DA-POSICAO — §N citado em linhas erradas"
PD3="$TMP/fase-c"; mkdir -p "$PD3"
{ printf 'linha1\nlinha2\n## 3. Terceira Secao\nlinha4\n'
  for i in $(seq 5 60); do echo "linha$i"; done
} > "$PD3/7-SPEC.md"
cat > "$PD3/7-01-PLAN.md" <<'EOF'
---
phase: "7"
plan: 01
wave: 1
files_modified:
  - src/a.py
---
<tasks><task type="auto"><read_first>
- 7-SPEC.md §3. Terceira Secao, linhas 40-45
</read_first></task></tasks>
EOF
OUT=$(bash "$S" "$PD3")
eq "1 aviso de posição errada" "$(jq -r .total <<<"$OUT")" 1
eq "código certo" "$(jq -r '.avisos[0].codigo' <<<"$OUT")" "SECAO-FORA-DA-POSICAO"
eq "diz a linha real" "$(jq -r '.avisos[0].detalhe' <<<"$OUT" | grep -c 'linha 3')" 1

echo "== (2b) §N citado na posição certa → sem aviso"
cat > "$PD3/7-01-PLAN.md" <<'EOF'
---
phase: "7"
plan: 01
wave: 1
files_modified:
  - src/a.py
---
<tasks><task type="auto"><read_first>
- 7-SPEC.md §3. Terceira Secao, linhas 3-5
</read_first></task></tasks>
EOF
OUT=$(bash "$S" "$PD3")
eq "posição bate → sem aviso" "$(jq -r .total <<<"$OUT")" 0

echo "== plano sem read_first, sem files_modified → não quebra, 0 avisos"
PD4="$TMP/fase-d"; mkdir -p "$PD4"
printf -- '---\nphase: "7"\nplan: 01\nwave: 1\n---\n<tasks></tasks>\n' > "$PD4/7-01-PLAN.md"
OUT=$(bash "$S" "$PD4"); RC=$?
eq "exit 0" "$RC" 0
eq "0 avisos" "$(jq -r .total <<<"$OUT")" 0

echo "== uso inválido → exit 2"
bash "$S" >/dev/null 2>&1; eq "sem argumentos" "$?" 2
bash "$S" "$TMP/nao-existe" >/dev/null 2>&1; eq "phase_dir inexistente" "$?" 2

echo "--------------------------------------------------"
echo "$falhas falha(s)"
[ "$falhas" -eq 0 ]
