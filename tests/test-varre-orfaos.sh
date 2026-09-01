#!/usr/bin/env bash
# test-varre-orfaos.sh — bancada do B3 (varredura de órfãos da rotina de parada).
#
# Régua: (1) sem `--matar` o script só RELATA — é o padrão; (2) o critério é o vínculo
# com o phase_dir, nunca o nome do processo; (3) as salvaguardas (teto de 10 candidatos,
# GRUPO-MISTO, alvo largo demais, diretório inexistente) precisam recusar a morte, não
# apenas avisar. Um caminho errado relatando `orfaos: 0` seria a pior falha possível
# numa rotina de parada — por isso diretório inexistente é exit 2.
#
# O único processo real desta bancada é UM `sleep` lançado aqui dentro do sandbox e
# morto aqui mesmo. Todas as salvaguardas que exigiriam dezenas de processos são
# exercitadas com `GAD_PS_FALSA` (instantâneo de `ps` pré-cozido), pelo mesmo motivo
# que o B1 usa `GAD_HORA_FALSA`. Nenhum teste desta bancada envia sinal a processo que
# não tenha sido lançado por ela.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/varre-orfaos.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-orfaos-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

echo "== uso inválido → exit 2 (nunca 'orfaos: 0')"
saida=$("$SCRIPT" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "sem argumento → exit 2" || erro "esperado 2, veio $rc" "$saida"

saida=$("$SCRIPT" "$TMP/nao-existe" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "diretório inexistente → exit 2" || erro "esperado 2, veio $rc" "$saida"
printf '%s' "$saida" | grep -q "orfaos: 0" && erro "caminho errado relatou 'orfaos: 0'" "$saida" \
  || ok "caminho errado não relata zero órfãos"

saida=$("$SCRIPT" "$HOME" 2>&1); rc=$?
[ "$rc" = 2 ] && printf '%s' "$saida" | grep -q "RECUSA" \
  && ok "phase_dir = \$HOME → RECUSA (alvo largo demais), exit 2" || erro "alvo largo aceito" "$saida"

echo "== fase limpa → orfaos: 0, exit 0"
D="$TMP/fase-limpa"; mkdir -p "$D"
saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^orfaos: 0$" && [ "$rc" = 0 ] \
  && ok "nenhum processo vinculado → orfaos: 0 (exit 0)" || erro "fase limpa acusou órfão" "$saida"

echo "== processo real lançado nesta bancada (só relato, sem --matar)"
D="$TMP/INS-99.9-fase-de-mentira"; mkdir -p "$D"
cat > "$D/waiter.sh" <<'EOF'
#!/usr/bin/env bash
sleep 45
EOF
chmod +x "$D/waiter.sh"
# O caminho do phase_dir está na linha de comando por construção — é exatamente o rastro
# de um waiter de disco lançado dentro da fase. A saída vai para /dev/null porque um
# processo de fundo segurando o pipe da suíte travaria o runner.
"$D/waiter.sh" >/dev/null 2>&1 </dev/null & ALVO=$!
sleep 0.3

saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^orfaos: 1$" && [ "$rc" = 1 ] \
  && ok "waiter encontrado pela linha de comando → orfaos: 1 (exit 1)" || erro "não achou o waiter" "$saida"
printf '%s' "$saida" | grep -q "pid=$ALVO " \
  && ok "relata o pid certo" || erro "pid $ALVO ausente do relato" "$saida"
printf '%s' "$saida" | grep -qE "vida=[0-9]+s reparentado=(sim|nao)" \
  && ok "relata tempo de vida e a anotação de reparentado" || erro "colunas faltando" "$saida"
kill -0 "$ALVO" 2>/dev/null \
  && ok "sem --matar o processo continua vivo (o padrão é só relatar)" || erro "o relato matou o processo"

# O waiter herdou o grupo/sessão desta bancada. Mesmo com --matar o script tem de
# recusar tocar nesse grupo — se não recusasse, mataria o próprio teste. Note que ele
# é RELATADO assim mesmo: só a morte é recusada, não a visibilidade.
saida=$("$SCRIPT" "$D" --matar 2>&1); rc=$?
printf '%s' "$saida" | grep -qE "GRUPO-PROPRIO|GRUPO-MISTO" \
  && ok "grupo compartilhado com o shell da bancada → marcado como não-matável" \
  || erro "não protegeu o grupo do chamador" "$saida"
printf '%s' "$saida" | grep -q "morte recusada" \
  && ok "--matar recusou explicitamente o grupo" || erro "não recusou a morte" "$saida"
printf '%s' "$saida" | grep -q "TERM enviado" && erro "enviou TERM ao grupo do chamador" "$saida" \
  || ok "nenhum TERM enviado ao grupo do chamador"
kill -0 "$ALVO" 2>/dev/null \
  && ok "o processo (e a bancada) sobreviveram ao --matar" \
  || erro "a salvaguarda de grupo próprio não protegeu"

# A bancada mata a ÁRVORE, não só o wrapper: o `sleep` filho não carrega o phase_dir na
# linha de comando, então sobreviveria invisível ao relato — vazando um processo por
# rodada da suíte.
FILHOS=$(pgrep -P "$ALVO" 2>/dev/null || true)
kill "$ALVO" 2>/dev/null; wait "$ALVO" 2>/dev/null
for f in $FILHOS; do kill "$f" 2>/dev/null || true; done
sleep 0.3
restou=0
for f in $FILHOS; do kill -0 "$f" 2>/dev/null && restou=$((restou+1)); done
[ "$restou" -eq 0 ] && ok "a bancada não vaza processo (árvore do waiter inteira morta)" \
  || erro "$restou descendente(s) do waiter sobreviveram à limpeza da bancada"

saida=$("$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^orfaos: 0$" && [ "$rc" = 0 ] \
  && ok "morto pela bancada → orfaos: 0 (exit 0)" || erro "órfão persistiu no relato" "$saida"

echo "== salvaguardas com instantâneo de ps pré-cozido (nenhum processo real)"
D="$TMP/INS-88.8-sintetica"; mkdir -p "$D"

# (a) teto: 11 candidatos em grupos limpos → RECUSA antes de qualquer sinal
SNAP="$TMP/ps-11.txt"; : > "$SNAP"
i=1
while [ "$i" -le 11 ]; do
  printf '%6d %6d %6d %6d bash -c waiter %s/marcador-%d\n' \
    $((970000+i)) 1 $((980000+i)) 300 "$D" "$i" >> "$SNAP"
  i=$((i+1))
done
saida=$(GAD_PS_FALSA="$SNAP" "$SCRIPT" "$D" --matar 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^RECUSA: 11 candidatos — acima do teto; inspecione à mão$" \
  && ok "11 candidatos → RECUSA literal do plano" || erro "teto não recusou" "$saida"
[ "$rc" = 1 ] && ok "RECUSA sai com exit 1 (há órfãos, nada foi feito)" || erro "esperado 1, veio $rc"
printf '%s' "$saida" | grep -q "TERM enviado" && erro "enviou TERM apesar da RECUSA" "$saida" \
  || ok "nenhum TERM enviado sob RECUSA"

# (b) exatamente 10 candidatos: abaixo do teto, o teto não morde
head -n 10 "$SNAP" > "$TMP/ps-10.txt"
saida=$(GAD_PS_FALSA="$TMP/ps-10.txt" "$SCRIPT" "$D" 2>&1)
printf '%s' "$saida" | grep -q "^orfaos: 10$" \
  && ok "10 candidatos ainda são relatados (borda do teto)" || erro "borda do teto errada" "$saida"

# (c) grupo misto sintético: 2 casam, 1 estranho no mesmo pgid → morte recusada
SNAP2="$TMP/ps-misto.txt"
{ printf '%6d %6d %6d %6d bash -c waiter %s/marcador-1\n' 970101 1      960001 300 "$D"
  printf '%6d %6d %6d %6d bash -c waiter %s/marcador-2\n' 970102 970101 960001 290 "$D"
  printf '%6d %6d %6d %6d /usr/bin/algum-daemon-alheio\n' 970103 1      960001 999
  printf '%6d %6d %6d %6d bash -c waiter %s/marcador-3\n' 970104 1      960002 280 "$D"
} > "$SNAP2"
saida=$(GAD_PS_FALSA="$SNAP2" "$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "grupo pgid=960001  \[GRUPO-MISTO" \
  && ok "pgid com processo alheio marcado GRUPO-MISTO" || erro "grupo misto não marcado" "$saida"
printf '%s' "$saida" | grep -q "grupo pgid=960002$" \
  && ok "pgid limpo relatado sem a marca de misto" || erro "grupo limpo marcado errado" "$saida"
printf '%s' "$saida" | grep -q "^orfaos: 3$" \
  && ok "conta 3 candidatos (o daemon alheio não entra)" || erro "contagem errada" "$saida"
printf '%s' "$saida" | grep -q "reparentado=sim" \
  && ok "PPID 1 vira anotação reparentado=sim" || erro "anotação de reparentado ausente" "$saida"
[ "$rc" = 1 ] && ok "exit 1 com órfãos" || erro "esperado 1, veio $rc"

# (d) o daemon alheio, sozinho, não é candidato — o nome nunca é critério
SNAP3="$TMP/ps-alheio.txt"
printf '%6d %6d %6d %6d /usr/bin/codex --serve\n' 970201 1 960009 999 > "$SNAP3"
saida=$(GAD_PS_FALSA="$SNAP3" "$SCRIPT" "$D" 2>&1); rc=$?
printf '%s' "$saida" | grep -q "^orfaos: 0$" && [ "$rc" = 0 ] \
  && ok "processo 'codex' sem vínculo com a fase NÃO é órfão (nome não é critério)" \
  || erro "varreu por nome" "$saida"

echo
[ "$falhas" -eq 0 ] && echo "test-varre-orfaos: TUDO OK" || echo "test-varre-orfaos: $falhas falha(s)"
[ "$falhas" -eq 0 ]
