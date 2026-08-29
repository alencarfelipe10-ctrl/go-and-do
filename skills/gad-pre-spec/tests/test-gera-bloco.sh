#!/usr/bin/env bash
# test-gera-bloco.sh — gera-bloco.py: respostas sintéticas da entrevista → bloco válido.
#
# O que se prova:
#   1. respostas em português viram bloco canônico que PASSA no confere-pre-spec.sh
#   2. ids PS-01… sequenciais; campos opcionais vazios são OMITIDOS (o contrato v1 tem
#      allowlist fechada e rejeita campo vazio)
#   3. costly/one-way sem justificativa → recusa, nada é escrito
#   4. fato_medido sem evidência reproduzível → recusa citando a regra do `[herdado]`
#   5. reprovação do confere → o arquivo é RESTAURADO ao conteúdo anterior
#   6. arquivo sem as marcas → recusa
set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib-bancada.sh"

G="$SKILL/scripts/gera-bloco.py"
RAIZ=$(bancada gera-bloco)
ALVO="$RAIZ/99-PRE-SPEC.md"
molde "$ALVO" 99 "Fase sintética da bancada"

echo "-- caminho feliz"
saida=$(python3 "$G" --entrada "$FIX/respostas-ok.json" --arquivo "$ALVO" --confere "$CONFERE" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "exit 0" || erro "exit 0" "exit=$rc
$saida"
echo "$saida" | grep -q 'pre_spec_bloco: ok' && ok "confere-pre-spec.sh aprovou o bloco gerado" \
  || erro "confere-pre-spec.sh aprovou" "$saida"
echo "$saida" | grep -q 'entradas=3' && ok "3 entradas no bloco" || erro "entradas=3" "$saida"

BLOCO=$(sed -n '/gad:decisoes:begin/,/gad:decisoes:end/p' "$ALVO" | sed '1d;$d')
python3 - "$BLOCO" <<'PY' && ok "estrutura do bloco (ids, kinds, omissão de opcionais)" || erro "estrutura do bloco"
import json, sys
d = json.loads(sys.argv[1])
assert [e["id"] for e in d] == ["PS-01", "PS-02", "PS-03"], d
assert d[0]["kind"] == "decisao_dono" and d[1]["kind"] == "fato_medido"
assert d[0]["reversibilidade"] == "costly"
assert d[0]["reversibilidade_justificativa"]
assert d[0]["req_anchor"] == "R2" and d[2]["req_anchor"] == "none"
assert d[0]["opcoes_descartadas"] == ["Opção B — uma linha por contrato", "Opção C — híbrida"]
# opcionais vazios têm de estar AUSENTES, não vazios
assert "ressalva" not in d[1] and "ressalva" not in d[2], d
assert "opcoes_descartadas" not in d[1], d
assert "reversibilidade_justificativa" not in d[1], d
PY

echo "-- idempotência: rodar de novo dá o mesmo bloco"
antes=$(md5sum < "$ALVO")
python3 "$G" --entrada "$FIX/respostas-ok.json" --arquivo "$ALVO" --confere "$CONFERE" >/dev/null 2>&1
[ "$(md5sum < "$ALVO")" = "$antes" ] && ok "segunda passada não muda o arquivo" || erro "idempotência"

echo "-- costly sem justificativa"
antes=$(md5sum < "$ALVO")
saida=$(python3 "$G" --entrada "$FIX/respostas-costly-sem-justificativa.json" --arquivo "$ALVO" \
        --confere "$CONFERE" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "exit 2 (entrada inválida)" || erro "exit 2" "exit=$rc
$saida"
echo "$saida" | grep -q 'exige .justificativa' && ok "mensagem nomeia a justificativa" || erro "mensagem" "$saida"
[ "$(md5sum < "$ALVO")" = "$antes" ] && ok "arquivo intocado" || erro "arquivo intocado"

echo "-- fato sem evidência reproduzível (regra do [herdado])"
saida=$(python3 "$G" --entrada "$FIX/respostas-fato-herdado.json" --arquivo "$ALVO" \
        --confere "$CONFERE" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "exit 2" || erro "exit 2" "exit=$rc
$saida"
echo "$saida" | grep -q '\[herdado\]' && ok "a recusa manda marcar \`[herdado]\`" || erro "menção a [herdado]" "$saida"
[ "$(md5sum < "$ALVO")" = "$antes" ] && ok "arquivo intocado" || erro "arquivo intocado"

echo "-- reprovação do confere restaura o arquivo"
# id fora do padrão só é pego pelo confere (o gera-bloco numera sozinho), então
# simulamos um confere que sempre reprova: o contrato é 'reprovou → restaura'.
FALSO="$RAIZ/confere-falso.sh"
printf '#!/usr/bin/env bash\necho "BLOCO-INVALIDO simulado"\nexit 2\n' > "$FALSO"
antes=$(md5sum < "$ALVO")
saida=$(python3 "$G" --entrada "$FIX/respostas-ok.json" --arquivo "$ALVO" --confere "$FALSO" 2>&1); rc=$?
[ "$rc" = 3 ] && ok "exit 3 quando o confere reprova" || erro "exit 3" "exit=$rc
$saida"
[ "$(md5sum < "$ALVO")" = "$antes" ] && ok "arquivo restaurado ao conteúdo anterior" || erro "restauração"
echo "$saida" | grep -q 'restaurado' && ok "a mensagem diz que restaurou" || erro "mensagem de restauração" "$saida"

echo "-- arquivo sem as marcas"
SEMMARCA="$RAIZ/sem-marcas.md"
printf '# só um título\n' > "$SEMMARCA"
saida=$(python3 "$G" --entrada "$FIX/respostas-ok.json" --arquivo "$SEMMARCA" --confere "$CONFERE" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "exit 2 sem as marcas" || erro "exit 2 sem as marcas" "exit=$rc
$saida"
echo "$saida" | grep -q 'templates/PRE-SPEC.md' && ok "a recusa aponta o molde" || erro "recusa aponta o molde" "$saida"

echo "-- auto-descoberta do confere (rota de produção: o passo 5 não passa --confere)"
molde "$ALVO" 99 "Fase sintética da bancada"
saida=$(python3 "$G" --entrada "$FIX/respostas-ok.json" --arquivo "$ALVO" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "sem --confere: achou o confere-pre-spec.sh sozinho" \
  || erro "auto-descoberta do confere-pre-spec.sh (skills/go-and-do/scripts/)" "exit=$rc
$saida"
echo "$saida" | grep -q 'pre_spec_bloco: ok' && ok "conferência rodou de verdade" || erro "conferência rodou" "$saida"

echo "-- --stdout não escreve nada"
saida=$(python3 "$G" --entrada "$FIX/respostas-ok.json" --stdout 2>&1); rc=$?
[ "$rc" = 0 ] && ok "--stdout exit 0" || erro "--stdout exit 0" "$saida"
printf '%s' "$saida" | python3 -c 'import json,sys; assert len(json.load(sys.stdin))==3' \
  && ok "--stdout imprime o array com 3 entradas" || erro "--stdout imprime o array"

fim
