#!/usr/bin/env bash
# test-pii.sh — confere-pii.sh: nome próprio no corpo bloqueia a gravação.
#
# O que se prova:
#   1. nome da lista dura (`--nomes`, extraída dos insumos) → PII-NOME-CONHECIDO, exit 1
#   2. "Nome Sobrenome" capitalizado no corpo, sem lista dura → PII-NOME-SUSPEITO, exit 1
#   3. contextos isentos: heading, bloco de código, código inline, caminho de arquivo
#   4. termos da lista de permitidos (modelos, ferramentas, rótulos) não acusam —
#      é o que mantém o próprio molde limpo
#   5. --brando rebaixa a heurística a aviso, mas a lista dura continua reprovando
#   6. --permitidos acrescenta termos e cala um falso positivo conhecido
set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib-bancada.sh"

P="$SKILL/scripts/confere-pii.sh"
RAIZ=$(bancada pii)

echo "-- nome da lista dura"
saida=$(bash "$P" "$FIX/com-nome-PRE-SPEC.md" --nomes "$FIX/nomes.txt" 2>&1); rc=$?
[ "$rc" = 1 ] && ok "exit 1" || erro "exit 1" "exit=$rc
$saida"
echo "$saida" | grep -q 'PII-NOME-CONHECIDO' && ok "código PII-NOME-CONHECIDO" || erro "código" "$saida"
echo "$saida" | grep -q 'com-nome-PRE-SPEC.md:7' && ok "aponta a linha do achado" || erro "linha do achado" "$saida"

echo "-- heurística sem lista dura"
saida=$(bash "$P" "$FIX/com-nome-PRE-SPEC.md" 2>&1); rc=$?
[ "$rc" = 1 ] && ok "exit 1 só pela heurística" || erro "exit 1" "exit=$rc
$saida"
echo "$saida" | grep -q 'PII-NOME-SUSPEITO.*Joana Peixoto' && ok "pegou 'Joana Peixoto'" || erro "PII-NOME-SUSPEITO" "$saida"

echo "-- contextos isentos"
echo "$saida" | grep -q 'Motor Fiscal' && erro "caminho de arquivo não pode ser acusado" "$saida" \
  || ok "caminho src/Motor Fiscal/x.py isento"
echo "$saida" | grep -q 'Nome Sobrenome' && erro "código inline não pode ser acusado" "$saida" \
  || ok "código inline \`Nome Sobrenome\` isento"
echo "$saida" | grep -q 'Fixture com PII' && erro "heading não pode ser acusado pela heurística" "$saida" \
  || ok "heading isento da heurística"

LIMPO="$RAIZ/limpo.md"
cat > "$LIMPO" <<'EOF'
# Fase 99 — Fixture limpa

## 7. Regras de negócio ditadas pelo cliente

> "o desconto não pode zerar a mensalidade" (o cliente, 2026-08-01)

O responsável 1 confirmou a regra; o aluno 7 é o caso-âncora.

```
Joana Peixoto aparece aqui dentro de um bloco de código
```

Ferramentas citadas: Claude Code, AskUserQuestion, RL Conecta.
EOF
echo "-- documento limpo"
saida=$(bash "$P" "$LIMPO" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "exit 0 num documento sem nomes" || erro "exit 0" "exit=$rc
$saida"
echo "$saida" | grep -q 'falhas=0' && ok "resumo falhas=0" || erro "falhas=0" "$saida"
echo "$saida" | grep -q 'Claude Code' && erro "termo permitido não pode ser acusado" "$saida" \
  || ok "termos permitidos (Claude Code, AskUserQuestion, RL Conecta) isentos"
echo "$saida" | grep -q 'bloco de código' && erro "bloco de código não pode ser acusado pela heurística" "$saida" \
  || ok "bloco de código isento da heurística"

echo "-- lista dura vale mesmo dentro do bloco de código"
saida=$(bash "$P" "$LIMPO" --nomes "$FIX/nomes.txt" 2>&1); rc=$?
[ "$rc" = 1 ] && ok "exit 1: a lista dura não tem contexto isento" || erro "exit 1 com lista dura" "$saida"

echo "-- --brando"
saida=$(bash "$P" "$FIX/com-nome-PRE-SPEC.md" --brando 2>&1); rc=$?
[ "$rc" = 0 ] && ok "--brando: heurística sozinha vira aviso (exit 0)" || erro "--brando exit 0" "exit=$rc
$saida"
echo "$saida" | grep -q 'AVISO PII-NOME-SUSPEITO' && ok "achado sai como AVISO" || erro "AVISO" "$saida"
saida=$(bash "$P" "$FIX/com-nome-PRE-SPEC.md" --brando --nomes "$FIX/nomes.txt" 2>&1); rc=$?
[ "$rc" = 1 ] && ok "--brando NÃO afrouxa a lista dura" || erro "--brando + lista dura = exit 1" "exit=$rc
$saida"

echo "-- --permitidos cala falso positivo conhecido"
FP="$RAIZ/falso-positivo.md"
printf 'O relatório é entregue ao Banco Central todo mês.\n' > "$FP"
bash "$P" "$FP" >/dev/null 2>&1 && erro "'Banco Central' deveria ser acusado sem a lista" \
  || ok "falso positivo esperado: 'Banco Central' é acusado sem a lista"
printf 'Banco Central\n' > "$RAIZ/permitidos.txt"
bash "$P" "$FP" --permitidos "$RAIZ/permitidos.txt" >/dev/null 2>&1 \
  && ok "--permitidos silencia o falso positivo" || erro "--permitidos"

echo "-- o molde recém-gerado passa limpo (guarda da lista de permitidos)"
MOLDE="$RAIZ/99-PRE-SPEC.md"
molde "$MOLDE" 99 "Fase sintética da bancada"
bash "$P" "$MOLDE" >/dev/null 2>&1 && ok "templates/PRE-SPEC.md materializado passa no gate" \
  || erro "molde acusado pelo gate de PII" "$(bash "$P" "$MOLDE" 2>&1)"

echo "-- uso incorreto"
bash "$P" >/dev/null 2>&1; [ "$?" = 2 ] && ok "sem argumento → exit 2" || erro "sem argumento → exit 2"
bash "$P" "$RAIZ/nao-existe.md" >/dev/null 2>&1; [ "$?" = 2 ] && ok "arquivo ausente → exit 2" || erro "arquivo ausente → exit 2"

fim
