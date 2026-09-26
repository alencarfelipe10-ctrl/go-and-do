#!/usr/bin/env bash
# run-log.sh — telemetria da go-and-do (esquema major de 2026-08 — retrato fiel da linha
# do tempo, decisões G.1/G.2 do gad-major-update).
#
# Uso (escrita):
#   run-log.sh <phase_dir> <NN> <evento> "<etapa>" [tokens] [pct] [subagent_tokens] [limit] \
#              [_morto] [motivo] [FLAGS]
#   FLAGS:  --camada <0|1|2|externa>   camada onde a ação ocorreu
#           --modelo <id>              modelo em uso (opus-5, sonnet-5, gpt-5.x, …)
#           --effort <nível>           effort do modelo
#           --tokens-reais <int>       tokens MEDIDOS do transcript (mede-tokens.py; nunca
#                                      autodeclarados)
#           --custo <usd>              custo da etapa calculado por mede-tokens.py (precos.json)
#           --kv <chave=valor>         campo extra (repetível; número/true/false viram JSON cru)
#   evento ∈ {run, checkpoint, end, stop, skip, compact, despacho, retorno, script,
#             incidente}
#     run        — abertura da rodada (escrito pelo abre-rodada.sh)
#     checkpoint — fotografia do contexto da camada 0 (abre janela de etapa)
#     end        — fecha a janela de etapa (escrito pelo confere-etapa.sh no fecho)
#     stop/skip  — pausa/pulo declarado
#     compact    — auto-detectado (queda >100k na mesma sessão)
#     despacho   — início de despacho de subagente (escrito pelo pre-despacho.sh e pelo
#                  hook gad-lifecycle.sh; NUNCA pelo modelo)
#     retorno    — fim de despacho (escrito pelo hook; par do despacho — não fecha janela
#                  de etapa, que é do par checkpoint/end)
#     script     — auto-registro de um script da skill (nome+exit+resumo via --kv)
#     incidente  — desvio disclosed no meio da rodada (origem+detalhe via --kv). É a
#                  fonte mecânica da régua 27(a) da auditoria; na F24 os 10 incidentes
#                  foram parar em DECISOES.md por falta deste evento documentado.
#
# ── FM-F4RLR-04UAT: veredito `handback` + elo da retomada ──────────────────────────────
#   `handback` é o veredito da etapa 6 que PAROU sem ship (rota 6.4-HB do workflow — hoje
#   isso já é gravado por um `stop`/etapa "handback"; um `end` id 6 com `--kv
#   veredito=handback`, quando o workflow vier a emiti-lo, também conta). Não é `pass`: a
#   fase não terminou, só devolveu o controle.
#   O 1º `checkpoint` de etapa "5 …" que aparece DEPOIS de um hand-back (sem nenhum outro
#   checkpoint de etapa 5 no meio) ganha, sozinho e automaticamente, `retomada_de_seq` e
#   `retomada_de_sessao` apontando para a linha do hand-back — mecânico, sem depender do
#   workflow chamar nada de novo. Quem soma tempo/tokens por etapa (dashboard, recortes)
#   trata as duas janelas de etapa 5 (a que parou + a que retomou) como uma coisa só.
#
# Modos:  run-log.sh <phase_dir> <NN> audit                    → audita a GRADE (não muta)
#         run-log.sh <phase_dir> <NN> close --sessao <id> [m]  → fecho ADMINISTRATIVO de
#                    janela órfã de sessão MORTA (2 ocorrências: F19-inspired e F2-rlr)
#         run-log.sh <phase_dir> <NN> abertas [--sessao <id>]  → janelas abertas da sessão
#                    (default: a atual), uma por linha "linha<TAB>etapa<TAB>ts" (não muta)
#         run-log.sh --selftest                                → sandbox (única rota exit != 0)
#
# ── PAPEL DOS NÚMEROS (leia antes de somar qualquer coisa) ─────────────────────────────
#   `tokens`/`pct` (checkpoint)  = FOTOGRAFIA do contexto da camada 0 (context-check.sh).
#   `subagent_tokens` (end)      = usage CUMULATIVO que o harness reportou a um despacho.
#     É CONFERÊNCIA, nunca métrica de custo: somar isso superconta ~3-4x (F20: 8,34M
#     alegados vs 2,30M medidos).
#   `tokens_reais`/`custo_usd`   = medição do transcript por mede-tokens.py (4 campos de
#     usage, dedup por requestId) — a MÉTRICA. Só entram por flag, só de fonte mecânica.
#   O campo autodeclarado `tokens_camada2` MORREU nesta versão (supercontagem sistêmica;
#   subagente não reporta token nenhum) — o 9º argumento posicional é aceito e DESCARTADO
#   com aviso, para compatibilidade de chamada.
#
# ── ENDURECIMENTOS MECÂNICOS (nenhum depende de disciplina do modelo) ──────────────────
#   flock          — toda escrita (inclusive o cálculo do seq) roda sob lock exclusivo no
#                    próprio JSONL: paralelismo real de 6 lanes já foi medido; append
#                    concorrente tem garantia formal, não estatística.
#   seq            — contador monotônico por arquivo; ordenação canônica (7 pares end/
#                    checkpoint no mesmo segundo na F20 tornavam timestamp ambíguo).
#   auto-fechamento— checkpoint novo com a janela anterior da MESMA sessão ainda aberta →
#                    grava antes um `end` sintético `"auto_fechado":true` e avisa no stderr.
#                    Checkpoint com `--kv paralelo=true` (t59, 4.1b × 4.5) abre janela SEM
#                    fechar as outras — modelo completo em janelas_abertas().
#   vocabulário    — validado NA ESCRITA (PC-2: eventos antigos no mesmo arquivo são
#                    tolerados na leitura). A etapa DEVE começar com o ID canônico da
#                    numeração nova: `0` abertura · `1` intencao · `1.5` contratos ·
#                    `2` planejamento · `2.5` convergencia · `3` construcao · `4.x` gates ·
#                    `5` uat · `6` encerramento · ou preparacao|probe|lateral|resumo|
#                    verificacao. Fora disso → aviso no stdout (não falha).
#   compact        — detector mecânico: queda > 100k na mesma sessão → evento `compact`.
#   skill_version  — `git describe` no clone, no evento `run`.
#   motivo         — 10º arg: texto livre do stop/skip em campo próprio, não na etapa.
#   parent_etapa   — end órfão de camada 2 (etapa contendo "(camada 2 retomada") ganha
#                    `"parent_etapa":"<ID>"` — atribuição determinística ao pai.
#
# Appenda 1 linha JSON em <phase_dir>/<NN>-RUN-LOG.jsonl.
# Telemetria é instrumento, não gate: fora do --selftest, NUNCA falha o pipeline (exit 0).

# ───────────────────────────── selftest ─────────────────────────────
if [ "$1" = "--selftest" ]; then
  SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/$(basename -- "$0")"
  TMP=$(mktemp -d) || exit 1
  export RUNLOG_SEM_ESPELHO=1
  export CLAUDE_CODE_SESSION_ID="selftest0-0000-0000"
  D="$TMP/.planning/phases/99-teste"; F="$D/99-RUN-LOG.jsonl"
  fail=0
  ok()  { echo "PASS: $1"; }
  bad() { echo "FAIL: $1"; fail=1; }

  bash "$SELF" "$D" 99 run "0 abertura" --modelo fable-5 --effort high --kv hook_instalado=true >/dev/null
  grep -q '"evento":"run"' "$F" && grep -q '"seq":1' "$F" && ok "run + seq inicial" || bad "run + seq inicial"
  grep -q '"skill_version"' "$F" && ok "skill_version no run" || bad "skill_version no run (git describe falhou?)"
  grep -q '"modelo":"fable-5","effort":"high"' "$F" && grep -q '"hook_instalado":true' "$F" \
    && ok "run com modelo/effort/kv" || bad "run com modelo/effort/kv"

  bash "$SELF" "$D" 99 checkpoint "1 intencao" 300000 75 "" 400000 >/dev/null
  grep -q '"tokens":300000,"pct":75,"limit":400000' "$F" && ok "checkpoint com medição" || bad "checkpoint com medição"

  ERRF=$(mktemp)
  out=$(bash "$SELF" "$D" 99 checkpoint "2 planejamento" 310000 77 "" 400000 2>"$ERRF")
  # FM-03ENC: o aviso é PROSA — stdout é do JSON de quem chama (o pre-despacho.sh morreu
  # com erro de JSON em 20/09 por causa desta linha).
  echo "$out" | grep -q "janela-fechada" && bad "FM-03ENC: aviso vazou para o stdout" \
    || ok "FM-03ENC: aviso de janela fechada sai só no stderr"
  grep -q '"auto_fechado":true' "$F" \
    && ok "auto-fechamento de janela aberta" || bad "auto-fechamento de janela aberta"
  rm -f "$ERRF"

  out=$(bash "$SELF" "$D" 99 end "2 planejamento" "" "" 123456 "" 9999 2>/dev/null)
  echo "$out" | grep -q "tokens_camada2 morreu" && grep -q '"subagent_tokens":123456' "$F" \
    && ! grep -q '"tokens_camada2"' "$F" \
    && ok "9º arg descartado com aviso (campo autodeclarado morto)" || bad "9º arg descartado com aviso"

  bash "$SELF" "$D" 99 end "2.5 convergencia" "" "" "" "" "" "" --tokens-reais 88123 --custo 1.37 --camada 1 >/dev/null
  grep -q '"tokens_reais":88123,"custo_usd":1.37' "$F" && grep -q '"camada":1' "$F" \
    && ok "end com medição mecânica (tokens_reais/custo/camada)" || bad "end com medição mecânica"

  bash "$SELF" "$D" 99 despacho "1 intencao" --camada 0 --modelo opus-5 --effort medium --kv agente=gad-intent >/dev/null
  grep -q '"evento":"despacho".*"agente":"gad-intent"' "$F" && ok "evento despacho com agente" || bad "evento despacho"
  bash "$SELF" "$D" 99 retorno "1 intencao" --camada 0 --kv agente=gad-intent >/dev/null
  grep -q '"evento":"retorno"' "$F" && ok "evento retorno" || bad "evento retorno"

  bash "$SELF" "$D" 99 script "1 intencao" --kv script=confere-rotas.sh --kv exit=0 --kv resumo="rotas ok" >/dev/null
  grep -q '"evento":"script".*"script":"confere-rotas.sh","exit":0,"resumo":"rotas ok"' "$F" \
    && ok "auto-registro de script" || bad "auto-registro de script"

  bash "$SELF" "$D" 99 incidente "1 intencao" --kv origem=confere-rotas.sh --kv detalhe="teto estourado c1:5" >/dev/null
  grep -q '"evento":"incidente".*"origem":"confere-rotas.sh","detalhe":"teto estourado c1:5"' "$F" \
    && ok "evento incidente" || bad "evento incidente"

  # dente do gate: lock de fail do confere-etapa recusa o end (vira incidente);
  # pausa (interrompida=true) passa; lock removido (só o confere-etapa faz) libera
  printf '{"etapa":"5","ts":"x","resumo":"falhas: pre_uat_executado"}\n' > "$D/.gate-fail-5.json"
  out=$(bash "$SELF" "$D" 99 end "5 uat" 2>/dev/null)
  echo "$out" | grep -q "GATE-EM-FAIL" && grep -q '"origem":"gate-dente"' "$F" \
    && ! grep -q '"evento":"end","etapa":"5 uat"' "$F" \
    && ok "gate-dente: end recusado com lock vivo" || bad "gate-dente: end recusado com lock vivo"
  bash "$SELF" "$D" 99 end "5 uat" --kv interrompida=true >/dev/null
  grep -q '"evento":"end","etapa":"5 uat".*"interrompida":true' "$F" \
    && ok "gate-dente: pausa fecha janela mesmo com lock" || bad "gate-dente: pausa fecha janela mesmo com lock"
  rm -f "$D/.gate-fail-5.json"
  bash "$SELF" "$D" 99 end "5 uat" --kv veredito=pass >/dev/null
  grep -q '"etapa":"5 uat".*"veredito":"pass"' "$F" \
    && ok "gate-dente: lock removido libera o end" || bad "gate-dente: lock removido libera o end"

  # v2.1.9: UAT pendente recusa end pass; 2º end da mesma etapa declara `substitui`
  printf 'scenarios:\n  - id: 1\n    result: pass\n  - id: 3\n    result: [pending]\n' > "$D/99-UAT.md"
  out=$(bash "$SELF" "$D" 99 end "5 uat" --kv veredito=pass 2>/dev/null)
  echo "$out" | grep -q "UAT-PENDENTE" && ok "uat: end pass recusado com cenário pendente" || bad "uat: end pass recusado com cenário pendente"
  sed -i 's/\[pending\]/pass/' "$D/99-UAT.md"
  bash "$SELF" "$D" 99 end "5 uat" --kv veredito=pass >/dev/null
  tail -n1 "$F" | grep -q '"substitui":[0-9]' && ok "2º end da mesma etapa declara substitui" || bad "2º end da mesma etapa declara substitui"
  rm -f "$D/99-UAT.md"

  # v2.1.9: um end com `tokens` posicional (número do harness) NÃO alimenta o detector
  bash "$SELF" "$D" 99 end "3 construcao" 251511 >/dev/null
  out=$(bash "$SELF" "$D" 99 checkpoint "3 construcao" 100000 25 "" 400000)
  echo "$out" | grep -q "compact-detectado" && grep -q '"evento":"compact"' "$F" \
    && ok "detector de compact" || bad "detector de compact"
  grep -q 'queda 251511' "$F" && bad "detector de compact ignora tokens de end" || ok "detector de compact ignora tokens de end"

  bash "$SELF" "$D" 99 end '3 construcao (camada 2 retomada — plano 03)' "" "" 5555 >/dev/null
  grep -q '"parent_etapa":"3"' "$F" && ok "parent_etapa no end órfão" || bad "parent_etapa no end órfão"

  out=$(bash "$SELF" "$D" 99 end "0-B intencao" "" "" 1 2>/dev/null)
  echo "$out" | grep -q "fora do vocabulário" && ok "vocabulário novo rejeita ID antigo (0-B)" || bad "vocabulário novo rejeita ID antigo"
  out=$( { bash "$SELF" "$D" 99 end "1.5 contratos"; bash "$SELF" "$D" 99 checkpoint "4.2 code-review" 100 0 "" 400000; } 2>/dev/null )
  echo "$out" | grep -q "fora do vocabulário" && bad "IDs novos 1.5/4.2 aceitos" || ok "IDs novos 1.5/4.2 aceitos"

  bash "$SELF" "$D" 99 end "4.2 code-review" "" "" 42 >/dev/null
  bash "$SELF" "$D" 99 stop "pausa" 320000 80 "" 400000 "" 'ship bloqueado — repo sem remote ("LGPD")' >/dev/null
  grep -q '"evento":"stop".*"motivo":"ship bloqueado' "$F" && ok "stop com medição + motivo (escapado)" || bad "stop com medição + motivo"

  # flock: 6 appends concorrentes → 6 linhas, seq único e monotônico no arquivo inteiro
  before=$(wc -l < "$F")
  for i in 1 2 3 4 5 6; do bash "$SELF" "$D" 99 script "5 uat" --kv script=lane$i --kv exit=0 & done
  wait
  after=$(wc -l < "$F")
  [ $((after-before)) -eq 6 ] && ok "flock: 6 appends concorrentes, 6 linhas" || bad "flock: appends concorrentes ($before -> $after)"

  out=$(bash "$SELF" "$D" 99 audit)
  echo "$out" | grep -q "janelas_abertas=0" && ok "audit: grade fechada" || bad "audit: grade fechada ($out)"
  bash "$SELF" "$D" 99 checkpoint "6.3 resumo" 330000 82 "" 400000 >/dev/null
  out=$(bash "$SELF" "$D" 99 audit)
  echo "$out" | grep -q 'JANELA ABERTA.*6.3 resumo' && ok "audit: detecta janela aberta" || bad "audit: detecta janela aberta"

  # close administrativo: sessão "morta" deixa janela aberta; outra sessão a fecha de fora
  export CLAUDE_CODE_SESSION_ID="morta0000-0000"
  bash "$SELF" "$D" 99 checkpoint "3.4 verificacao" 200000 50 "" 400000 >/dev/null
  export CLAUDE_CODE_SESSION_ID="selftest0-0000-0000"
  out=$(bash "$SELF" "$D" 99 audit)
  echo "$out" | grep -q "close --sessao morta000" && ok "audit aponta o close p/ sessão morta" || bad "audit aponta o close p/ sessão morta"
  out=$(bash "$SELF" "$D" 99 close --sessao morta0000 "API 500 matou a sessão")
  echo "$out" | grep -q "fechada administrativamente" && grep -q '"fechado_admin":true' "$F" \
    && grep -q '"fechado_por":"selftest"' "$F" && ok "close fecha janela de sessão morta" || bad "close fecha janela de sessão morta"
  out=$(bash "$SELF" "$D" 99 close --sessao morta0000)
  echo "$out" | grep -q "já está fechada" && ok "close é no-op na 2ª vez" || bad "close é no-op na 2ª vez"
  out=$(bash "$SELF" "$D" 99 close --sessao selftest0)
  echo "$out" | grep -q "SESSÃO ATUAL" && ok "close recusa a sessão atual" || bad "close recusa a sessão atual"

  # FM-F4RLR-04UAT: elo da retomada (arquivo próprio — não interfere no seq do $F acima)
  D2="$TMP/.planning/phases/98-teste"; F2="$D2/98-RUN-LOG.jsonl"
  export CLAUDE_CODE_SESSION_ID="sessA0000-0000"
  bash "$SELF" "$D2" 98 checkpoint "5 uat" 100000 25 "" 400000 >/dev/null
  bash "$SELF" "$D2" 98 stop "handback" 110000 27 "" 400000 "" "balde 3 pendente" >/dev/null
  export CLAUDE_CODE_SESSION_ID="sessB0000-0000"
  bash "$SELF" "$D2" 98 checkpoint "5 uat" 5000 1 "" 400000 >/dev/null
  grep -q '"retomada_de_seq":2' "$F2" && grep -q '"retomada_de_sessao":"sessA000"' "$F2" \
    && ok "retomada: 1º checkpoint de etapa 5 após handback ganha o elo" \
    || bad "retomada: elo ausente no 1º checkpoint" "$(tail -n1 "$F2")"
  bash "$SELF" "$D2" 98 checkpoint "5 uat" 6000 2 "" 400000 >/dev/null
  tail -n1 "$F2" | grep -q 'retomada_de_seq' \
    && bad "retomada: 2º checkpoint de etapa 5 ganhou elo de novo (só o 1º deveria)" \
    || ok "retomada: 2º checkpoint de etapa 5 não repete o elo"
  export CLAUDE_CODE_SESSION_ID="selftest0-0000-0000"
  D3="$TMP/.planning/phases/97-teste"; F3="$D3/97-RUN-LOG.jsonl"
  bash "$SELF" "$D3" 97 checkpoint "5 uat" 1000 1 "" 400000 >/dev/null
  grep -q 'retomada_de' "$F3" \
    && bad "retomada: checkpoint de etapa 5 sem handback prévio ganhou elo indevido" \
    || ok "retomada: sem handback prévio, sem elo"

  # a janela retomada pode abrir com um rótulo de sub-etapa ("5.1 retomada"), não só "5 uat"
  D4="$TMP/.planning/phases/96-teste"; F4="$D4/96-RUN-LOG.jsonl"
  export CLAUDE_CODE_SESSION_ID="sessC0000-0000"
  bash "$SELF" "$D4" 96 checkpoint "5 uat" 90000 22 "" 400000 >/dev/null
  bash "$SELF" "$D4" 96 stop "handback" 95000 24 "" 400000 "" "balde 3 pendente" >/dev/null
  export CLAUDE_CODE_SESSION_ID="sessD0000-0000"
  bash "$SELF" "$D4" 96 checkpoint "5.1 retomada" 3000 1 "" 400000 >/dev/null
  grep -q 'retomada_de_seq' "$F4" \
    && ok "retomada: 1º checkpoint pós-handback com rótulo 5.x (não só \"5 uat\") ganha o elo" \
    || bad "retomada: rótulo 5.x não reconhecido" "$(tail -n1 "$F4")"

  # FM-F4RLR-02GAT (confirmação): "4.1b re-review" é rótulo válido no vocabulário canônico
  out=$(bash "$SELF" "$D" 99 checkpoint "4.1b re-review" 100 0 "" 400000 2>/dev/null)
  echo "$out" | grep -q "fora do vocabulário" \
    && bad "FM-02GAT: checkpoint 4.1b re-review rejeitado pelo vocabulário" \
    || ok "FM-02GAT: checkpoint 4.1b re-review aceito no vocabulário canônico"

  # t59 (FM-F27INS-01GAT): janelas paralelas — o caso real da F27 INS (seq 355–360): o 4.4 aberto,
  # o 4.1b abre, o 4.5 abre em paralelo; antes, cada checkpoint fechava o anterior (4.1b vazio).
  D5="$TMP/.planning/phases/95-teste"; F5="$D5/95-RUN-LOG.jsonl"
  aud5() { bash "$SELF" "$D5" 95 audit | sed -n 's/.*janelas_abertas=\([0-9]*\).*/\1/p'; }
  bash "$SELF" "$D5" 95 checkpoint "4.4 secure" 100000 25 "" 400000 >/dev/null 2>&1
  bash "$SELF" "$D5" 95 checkpoint "4.1b re-review" 101000 25 "" 400000 --kv paralelo=true >/dev/null 2>&1
  bash "$SELF" "$D5" 95 checkpoint "4.5 validate" 102000 25 "" 400000 --kv paralelo=true >/dev/null 2>&1
  grep -q '"auto_fechado":true' "$F5" \
    && bad "paralelo: abrir 4.1b/4.5 fechou janela" "$(grep auto_fechado "$F5")" \
    || ok "paralelo: abrir 4.1b e 4.5 em paralelo não fecha o 4.4 nem o 4.1b"
  grep -q '"etapa":"4.5 validate".*"paralelo":true' "$F5" \
    && ok "paralelo: o checkpoint grava \"paralelo\":true" || bad "paralelo: campo ausente no checkpoint"
  [ "$(aud5)" = 3 ] && ok "paralelo: audit vê 3 janelas abertas" || bad "paralelo: audit ($(aud5) abertas, esperado 3)"
  bash "$SELF" "$D5" 95 end "4.2 ui-review" >/dev/null 2>&1
  [ "$(aud5)" = 3 ] && ok "paralelo: end de outra etapa com 2+ janelas abertas não fecha nenhuma" \
    || bad "paralelo: end sem casamento fechou janela ($(aud5) abertas)"
  bash "$SELF" "$D5" 95 end "4.5 validate" --kv veredito=pass >/dev/null 2>&1
  bash "$SELF" "$D5" 95 end "4.1b re-review" --kv veredito=pass >/dev/null 2>&1
  out=$(bash "$SELF" "$D5" 95 audit)
  echo "$out" | grep -q 'janelas_abertas=1' && echo "$out" | grep -q 'JANELA ABERTA.*4.4 secure' \
    && ok "paralelo: cada end fecha a janela do próprio ID (sobra o 4.4)" || bad "paralelo: end fechou a janela errada" "$out"
  bash "$SELF" "$D5" 95 end "4.4 secure" --kv veredito=pass >/dev/null 2>&1
  [ "$(aud5)" = 0 ] && ! grep -q '"substitui"' "$F5" \
    && ok "paralelo: 3 ends, grade fechada, nenhum substitui" || bad "paralelo: grade ($(aud5) abertas) ou substitui indevido"
  # reabrir o MESMO ID em paralelo aposenta a janela antiga dele (só ela)
  bash "$SELF" "$D5" 95 checkpoint "4.1b re-review" 103000 25 "" 400000 --kv paralelo=true >/dev/null 2>&1
  bash "$SELF" "$D5" 95 checkpoint "4.5 validate" 104000 26 "" 400000 --kv paralelo=true >/dev/null 2>&1
  bash "$SELF" "$D5" 95 checkpoint "4.1b re-review" 105000 26 "" 400000 --kv paralelo=true >/dev/null 2>&1
  [ "$(grep -c '"auto_fechado":true' "$F5")" = 1 ] && grep -q '"etapa":"4.1b re-review","auto_fechado":true' "$F5" \
    && [ "$(aud5)" = 2 ] && ok "paralelo: reabrir o 4.1b fecha só o 4.1b antigo" || bad "paralelo: reabertura do mesmo ID" "$(grep auto_fechado "$F5")"
  # checkpoint COMUM fecha todas as abertas, uma a uma
  bash "$SELF" "$D5" 95 checkpoint "5 uat" 106000 26 "" 400000 >/dev/null 2>&1
  [ "$(grep -c '"auto_fechado":true' "$F5")" = 3 ] && [ "$(aud5)" = 1 ] \
    && ok "paralelo: checkpoint comum fecha as 2 janelas abertas (2 ends sintéticos)" \
    || bad "paralelo: checkpoint comum ($(grep -c auto_fechado "$F5") auto_fechado, $(aud5) abertas)"
  bash "$SELF" "$D5" 95 stop "pausa" 107000 27 "" 400000 "" "fim do teste" >/dev/null 2>&1
  [ "$(aud5)" = 0 ] && ok "paralelo: stop fecha todas" || bad "paralelo: stop deixou janela aberta"
  bash "$SELF" "$D5" 95 checkpoint "4.1b re-review" 100 0 "" 400000 --kv paralelo=true >/dev/null 2>&1
  bash "$SELF" "$D5" 95 checkpoint "4.5 validate" 100 0 "" 400000 --kv paralelo=true >/dev/null 2>&1
  out=$(bash "$SELF" "$D5" 95 abertas | cut -f2 | tr '\n' '|')
  [ "$out" = "4.1b re-review|4.5 validate|" ] && ok "abertas: lista as janelas abertas da sessão atual, em ordem" \
    || bad "abertas: saída [$out]"
  [ -z "$(bash "$SELF" "$D5" 95 abertas --sessao outra000)" ] && ok "abertas: sessão sem janela → vazio" \
    || bad "abertas: sessão alheia devolveu janela"
  bash "$SELF" "$D5" 95 stop "pausa" 100 0 "" 400000 "" "fim" >/dev/null 2>&1
  # close administrativo fecha TODAS as janelas da sessão morta (paralelas incluídas)
  export CLAUDE_CODE_SESSION_ID="morta2000-0000"
  bash "$SELF" "$D5" 95 checkpoint "4.1b re-review" 100 0 "" 400000 --kv paralelo=true >/dev/null 2>&1
  bash "$SELF" "$D5" 95 checkpoint "4.5 validate" 100 0 "" 400000 --kv paralelo=true >/dev/null 2>&1
  export CLAUDE_CODE_SESSION_ID="selftest0-0000-0000"
  bash "$SELF" "$D5" 95 close --sessao morta2000 "teste" >/dev/null
  [ "$(grep -c '"fechado_admin":true' "$F5")" = 2 ] && [ "$(aud5)" = 0 ] \
    && ok "close: fecha as 2 janelas paralelas da sessão morta" || bad "close: janelas paralelas ($(grep -c fechado_admin "$F5") fechadas)"
  python3 -c 'import json,sys; [json.loads(l) for l in open(sys.argv[1]) if l.strip()]' "$F5" 2>/dev/null \
    && ok "paralelo: linhas do run-log com escrita múltipla são JSON válido" || bad "paralelo: linha JSON inválida em $F5"
  sed -n 's/.*"seq":\([0-9]*\).*/\1/p' "$F5" | awk 'NR>1 && $1!=p+1{exit 1} {p=$1}' \
    && ok "paralelo: seq monotônico com ends sintéticos/admin em lote" || bad "paralelo: seq quebrado em $F5"

  seqs=$(sed -n 's/.*"seq":\([0-9]*\).*/\1/p' "$F" | tr '\n' ' ')
  python3 - "$F" <<'EOF' >/dev/null 2>&1 && ok "todas as linhas são JSON válido" || bad "linha JSON inválida"
import json,sys
[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
EOF
  echo "seqs: $seqs"
  echo "$seqs" | awk '{for(i=2;i<=NF;i++) if($i!=$(i-1)+1) exit 1}' && ok "seq monotônico" || bad "seq monotônico"

  rm -rf "$TMP"
  [ "$fail" -eq 0 ] && echo "SELFTEST: OK" || echo "SELFTEST: FALHOU"
  exit "$fail"
fi

# ───────────────────────────── espelho na nuvem (gad-harness) ─────────────────────────────
# Replica cada linha appendada na tabela gad_eventos do Supabase, para o painel ao vivo.
# Fire-and-forget: subshell em background, timeout curto, saída descartada — o espelho
# JAMAIS atrasa ou falha a fase. Sem config → sem espelho, em silêncio. O JSONL local
# segue sendo a fonte canônica; a nuvem admite lacunas por definição.
# Config: ~/.config/go-and-do/config com SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
# (mesmo padrão do ~/.config/audit-gad/config do P9; chmod 600).
# Uso: espelha <dir> <NN> <linha-json>
espelha() {
  [ -f "$HOME/.config/go-and-do/config" ] || return 0
  # dois guardas: a env dedicada cobre o selftest inteiro (que troca o session id
  # no teste do close — caso 02/08: sessão "morta0000" vazou 99-teste pra nuvem)
  [ -n "${RUNLOG_SEM_ESPELHO:-}" ] && return 0
  case "${CLAUDE_CODE_SESSION_ID:-}" in selftest*) return 0 ;; esac
  # 9>&-: o subshell não pode herdar o fd do flock — a trava soltaria só depois do curl
  (
    _dir="$1"; _nn="$2"; _raw="$3"
    . "$HOME/.config/go-and-do/config" 2>/dev/null
    [ -n "${SUPABASE_URL:-}" ] && [ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ] || exit 0
    # projeto = nome do diretório-raiz do repo alvo (chave canônica do P10)
    _proj=$(basename "$(git -C "$_dir" rev-parse --show-toplevel 2>/dev/null || echo "$_dir")")
    # fase como número JSON válido (NN pode vir com zero à esquerda: "02" não é JSON)
    _fase=$(printf '%s' "$_nn" | sed 's/[^0-9]//g; s/^0*//'); : "${_fase:=0}"
    curl -sS --max-time 3 -o /dev/null \
      -X POST "$SUPABASE_URL/rest/v1/gad_eventos" \
      -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"projeto\":\"$_proj\",\"fase\":$_fase,\"raw\":$_raw}"
    # cadastro do projeto (gad_projetos): caminho + fase atual + total de fases do
    # ROADMAP. Upsert que NÃO toca o apelido (editado pelo Felipe no painel).
    _top=$(git -C "$_dir" rev-parse --show-toplevel 2>/dev/null || echo "$_dir")
    _caminho="~${_top#"$HOME"}"
    # total = MAIOR número de fase do ROADMAP (numeração contínua entre milestones;
    # 999 = laterais/backlog, fora da conta). Contar linhas subestimaria o total.
    _total=$(grep -o '^### Phase [0-9]*' "$_top/.planning/ROADMAP.md" 2>/dev/null \
      | grep -o '[0-9]*$' | grep -v '^999$' | sort -n | tail -1)
    : "${_total:=0}"
    [ "$_total" -gt 0 ] && _total_json=$_total || _total_json=null
    curl -sS --max-time 3 -o /dev/null \
      -X POST "$SUPABASE_URL/rest/v1/gad_projetos?on_conflict=projeto" \
      -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Content-Type: application/json" \
      -H "Prefer: resolution=merge-duplicates" \
      -d "{\"projeto\":\"$_proj\",\"caminho\":\"$_caminho\",\"fase_atual\":$_fase,\"total_fases\":$_total_json,\"atualizado_em\":\"$(date -u +%FT%TZ)\"}"
  ) >/dev/null 2>&1 9>&- &
}

# trava exclusiva no próprio JSONL (fd 9): o seq só é confiável se leitura+escrita forem
# atômicas. flock ausente na plataforma → segue sem trava (degradação rara e declarada aqui).
trava() {
  exec 9>>"$1" 2>/dev/null || return 0
  command -v flock >/dev/null 2>&1 && flock -x 9 2>/dev/null
  return 0
}

# ───────────────────────────── janelas abertas (modelo de janelas) ─────────────────────────────
# t59 (FM-F27INS-01GAT): uma sessão pode ter MAIS DE UMA janela aberta — o workflow manda o 4.1b
# rodar em paralelo com o 4.5 (MGTm-01GAT), e na F27 INS abrir o 4.5 fechou o 4.1b vazio no mesmo
# segundo. O checkpoint que abre uma janela paralela leva `"paralelo":true` (--kv paralelo=true).
# Leitura, evento a evento da sessão, em ordem:
#   checkpoint sem paralelo → aposenta toda janela anterior (é o legado «só o último checkpoint
#                             conta»: run-log antigo lê igual) e abre a sua;
#   checkpoint paralelo     → abre a sua sem fechar as outras (só aposenta a do MESMO ID: reabrir);
#   end/skip                → fecha a janela aberta do MESMO ID (`etapa` até o 1º espaço); sem
#                             casamento, fecha a única janela aberta (legado); com 2+ abertas e
#                             nenhuma do mesmo ID, não fecha nada;
#   stop                    → fecha todas.
# Uso: janelas_abertas <arquivo> <sessao8> → "linha<TAB>etapa<TAB>ts" por janela aberta, em ordem.
janelas_abertas() {
  [ -f "$1" ] || return 0
  awk -v s="\"sessao\":\"$2\"" '
    function campo(k,   r) {
      if (match($0, "\"" k "\":\"[^\"]*\"")) {
        r = substr($0, RSTART, RLENGTH); sub("^\"" k "\":\"", "", r); sub("\"$", "", r); return r
      }
      return ""
    }
    function tira(k,   i) { for (i = k; i < n; i++) { L[i]=L[i+1]; E[i]=E[i+1]; T[i]=T[i+1]; I[i]=I[i+1] } n-- }
    index($0, s) == 0 { next }
    { ev = campo("evento"); et = campo("etapa"); id = et; sub(/ .*/, "", id) }
    ev == "checkpoint" {
      if (index($0, "\"paralelo\":true") == 0) n = 0
      else { for (i = n; i >= 1; i--) if (I[i] == id) tira(i) }
      n++; L[n] = NR; E[n] = et; T[n] = campo("ts"); I[n] = id; next
    }
    ev == "stop" { n = 0; next }
    ev == "end" || ev == "skip" {
      k = 0; for (i = n; i >= 1; i--) if (I[i] == id) { k = i; break }
      if (k == 0 && n == 1) k = 1
      if (k > 0) tira(k)
      next
    }
    END { for (i = 1; i <= n; i++) printf "%d\t%s\t%s\n", L[i], E[i], T[i] }' "$1"
}

# ───────────────────────────── modo close (administrativo) ─────────────────────────────
# Fecha de fora a janela aberta de uma sessão que morreu (API 500, kill etc.): grava um
# `end` sintético com "fechado_admin":true NA SESSÃO MORTA. Só age se a janela existe e
# está aberta — rodar contra sessão sã ou já fechada é no-op com aviso. Nunca falha.
if [ "$3" = "close" ]; then
  {
    dir="$1"; nn="$2"; shift 3
    alvo=""; motivo=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --sessao) alvo="$2"; shift 2 ;;
        *) motivo="$1"; shift ;;
      esac
    done
    [ -n "$alvo" ] || { echo "close: uso — close --sessao <id> [\"motivo\"]"; exit 0; }
    alvo="${alvo:0:8}"
    case "$dir" in
      /*) ;;
      *) _root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$_root" ] && dir="$_root/$dir" ;;
    esac
    f="$dir/$nn-RUN-LOG.jsonl"
    [ -f "$f" ] || { echo "close: run-log inexistente ($f)"; exit 0; }
    cur="${CLAUDE_CODE_SESSION_ID:-desconhecida}"
    if [ "$alvo" = "${cur:0:8}" ]; then
      echo "close: $alvo é a SESSÃO ATUAL — feche a janela pelo caminho normal (end/skip/stop)"; exit 0
    fi
    trava "$f"
    grep "\"sessao\":\"$alvo\"" "$f" | grep -q '"evento":"checkpoint"' \
      || { echo "close: nenhuma janela da sessão $alvo neste run-log"; exit 0; }
    # t59 (FM-F27INS-01GAT): TODAS as janelas abertas da sessão morta (paralelas incluídas)
    _abertas=$(janelas_abertas "$f" "$alvo")
    [ -n "$_abertas" ] || { echo "close: a janela da sessão $alvo já está fechada — nada a fazer"; exit 0; }
    motivo=$(printf '%s' "$motivo" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r\t')
    while IFS=$'\t' read -r _ln et _ts; do
      [ -n "$_ln" ] || continue
      ts=$(date -Is 2>/dev/null || date +%s)
      last_seq=$(sed -n 's/.*"seq":\([0-9]*\).*/\1/p' "$f" 2>/dev/null | tail -n1)
      case "$last_seq" in (''|*[!0-9]*) last_seq=0 ;; esac
      seq=$((last_seq+1))
      linha="{\"ts\":\"$ts\",\"seq\":$seq,\"sessao\":\"$alvo\",\"evento\":\"end\",\"etapa\":\"$et\",\"fechado_admin\":true,\"fechado_por\":\"${cur:0:8}\""
      [ -n "$motivo" ] && linha="$linha,\"motivo\":\"$motivo\""
      linha="$linha}"
      printf '%s\n' "$linha" >> "$f"
      espelha "$dir" "$nn" "$linha"
      echo "close: janela da sessão $alvo (etapa \"$et\") fechada administrativamente — o custo de subagentes dela NÃO foi registrado (anote se souber)"
    done <<<"$_abertas"
  } 2>/dev/null
  exit 0
fi

# ───────────────────────────── modo abertas (consulta) ─────────────────────────────
# t59 (FM-F27INS-01GAT): as janelas abertas de UMA sessão (default: a atual), pelo mesmo modelo
# do auto-fechamento/audit/close — fonte única para o pre-despacho.sh (paralelo automático com o
# 4.1b aberto) e o confere-etapa.sh (rótulo do 4.1b). Não muta. Saída: "linha<TAB>etapa<TAB>ts".
if [ "$3" = "abertas" ]; then
  {
    dir="$1"; nn="$2"; shift 3
    alvo="${CLAUDE_CODE_SESSION_ID:-}"
    [ "${1:-}" = "--sessao" ] && alvo="${2:-}"
    case "$dir" in
      /*) ;;
      *) _root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$_root" ] && dir="$_root/$dir" ;;
    esac
    [ -n "$alvo" ] && janelas_abertas "$dir/$nn-RUN-LOG.jsonl" "${alvo:0:8}"
  } 2>/dev/null
  exit 0
fi

# ───────────────────────────── modo audit ─────────────────────────────
if [ "$3" = "audit" ]; then
  {
    dir="$1"; nn="$2"
    case "$dir" in
      /*) ;;
      *) _root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$_root" ] && dir="$_root/$dir" ;;
    esac
    f="$dir/$nn-RUN-LOG.jsonl"
    if [ ! -f "$f" ]; then echo "audit: run-log inexistente ($f)"; exit 0; fi
    abertas=0
    for s in $(sed -n 's/.*"sessao":"\([^"]*\)".*/\1/p' "$f" | sort -u); do
      # t59 (FM-F27INS-01GAT): uma linha por janela aberta — a sessão pode ter janelas paralelas
      while IFS=$'\t' read -r ln et _ts; do
        [ -n "$ln" ] || continue
        if [ "$s" = "${CLAUDE_CODE_SESSION_ID:0:8}" ]; then
          echo "audit: JANELA ABERTA na sessão $s — etapa \"$et\" sem end/skip/stop (feche-a antes do stop)"
        else
          echo "audit: JANELA ABERTA na sessão $s — etapa \"$et\" sem end/skip/stop; sessão NÃO é a atual (morreu?) → feche com: run-log.sh <dir> <NN> close --sessao $s \"motivo\""
        fi
        abertas=$((abertas+1))
      done < <(janelas_abertas "$f" "$s")
    done
    echo "audit: linhas=$(wc -l < "$f" | tr -d ' ') run=$(grep -c '"evento":"run"' "$f") checkpoint=$(grep -c '"evento":"checkpoint"' "$f") end=$(grep -c '"evento":"end"' "$f") despacho=$(grep -c '"evento":"despacho"' "$f") retorno=$(grep -c '"evento":"retorno"' "$f") script=$(grep -c '"evento":"script"' "$f") skip=$(grep -c '"evento":"skip"' "$f") stop=$(grep -c '"evento":"stop"' "$f") compact=$(grep -c '"evento":"compact"' "$f") janelas_abertas=$abertas"
    echo "audit: lembrete — todo passo que TERIA rodado e não rodou precisa de um evento skip (UI/AI/eval/secure com gate off etc.); o script não adivinha o que devia rodar, só cobra o que ficou aberto"
  } 2>/dev/null
  exit 0
fi

# ───────────────────────────── escrita normal ─────────────────────────────
{
  dir="$1"; nn="$2"; evento="$3"; etapa="$4"
  [ -n "$dir" ] && [ -n "$nn" ] && [ -n "$evento" ] || exit 0
  shift 4 2>/dev/null || true
  # posicionais legados (até 6, param no primeiro --flag)
  _p=(); while [ $# -gt 0 ]; do case "$1" in --*) break ;; *) _p+=("$1"); shift ;; esac; done
  tokens="${_p[0]:-}"; pct="${_p[1]:-}"; subt="${_p[2]:-}"; lim="${_p[3]:-}"; c2="${_p[4]:-}"; motivo="${_p[5]:-}"
  # flags do esquema novo (G.1)
  camada=""; modelo=""; effort=""; treais=""; custo=""; kvs=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --camada)       camada="${2:-}"; shift 2 ;;
      --modelo)       modelo="${2:-}"; shift 2 ;;
      --effort)       effort="${2:-}"; shift 2 ;;
      --tokens-reais) treais="${2:-}"; shift 2 ;;
      --custo)        custo="${2:-}";  shift 2 ;;
      --kv)           kvs+=("${2:-}"); shift 2 ;;
      *) shift ;;
    esac
  done

  # Caminho relativo é resolvido contra a raiz do repo, não contra o cwd — um subagente
  # parado na pasta errada criava uma árvore .planning/ DUPLICADA (caso real, F16.1).
  case "$dir" in
    /*) ;;
    *) _root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$_root" ] && dir="$_root/$dir" ;;
  esac
  mkdir -p "$dir" 2>/dev/null || exit 0
  f="$dir/$nn-RUN-LOG.jsonl"

  ts=$(date -Is 2>/dev/null || date +%s)
  sess="${CLAUDE_CODE_SESSION_ID:-desconhecida}"
  sess="${sess:0:8}"

  # daqui em diante a escrita é atômica: seq lido e linha gravada sob a mesma trava
  trava "$f"

  # seq monotônico por arquivo (ordenação canônica; timestamps têm resolução de 1s e
  # colidem — 7 pares end/checkpoint no mesmo segundo na F20)
  last_seq=$(sed -n 's/.*"seq":\([0-9]*\).*/\1/p' "$f" 2>/dev/null | tail -n1)
  case "$last_seq" in (''|*[!0-9]*) last_seq=0 ;; esac
  seq=$((last_seq+1))

  # etapa e motivo são texto livre — escapa aspas e barras pro JSON não quebrar
  etapa=$(printf '%s' "$etapa" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r\t')
  motivo=$(printf '%s' "$motivo" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r\t')

  # Vocabulário canônico da numeração NOVA, validado na escrita (aviso, nunca falha —
  # texto livre sem ID inviabiliza agregação entre fases; caso real F20: 4 grafias)
  case "$evento" in
    checkpoint|end|skip|despacho|retorno|script|incidente)
      _id="${etapa%% *}"
      case "$_id" in
        preparacao|probe|lateral|resumo|verificacao|0|1|1.5|2|2.5|3|3.[0-9]*|4|4.[0-9]*|5|5.[0-9]*|6|6.[0-9]*) : ;;
        *) echo "aviso: etapa \"$_id\" fora do vocabulário canônico — prefixe com o ID da numeração nova (ex.: \"1 intencao\", \"2.5 convergencia\", \"4.2 code-review\", \"lateral pesquisa X\")" ;;
      esac ;;
  esac

  # Dente do gate (fix da 3ª ocorrência de "guarda cega reporta verde", F24-fecho:
  # confere-etapa exit 1 → end pass 18s depois). O confere-etapa.sh em fail grava
  # o lock da etapa e SÓ ele, ao dar pass, remove. Um `end` com o
  # lock vivo é recusado: vira evento `incidente` + instrução no stdout. Exceções que
  # fecham janela sem passar pelo gate: interrompida=true (pausa) e stop/skip.
  if [ "$evento" = "end" ]; then
    _id="${etapa%% *}"
    # t59 (FM-F27INS-01ENC): o lock mora no estado ignorado da rodada
    # (`.planning/.gad/gates/<fase>/<id>.json`); por 1 release o caminho antigo da pasta da
    # fase (`.gad/gates/<id>.json` ou `.gate-fail-<id>.json`) também trava — tabela única no
    # lib/gad-caminhos.sh (gad_trava_caminhos).
    . "$(dirname -- "${BASH_SOURCE[0]}")/lib/gad-caminhos.sh"
    _lock=""
    while IFS= read -r _l; do
      [ -n "$_l" ] && [ -f "$_l" ] && { _lock="$_l"; break; }
    done < <(gad_trava_caminhos "$dir" "$_id")
    _interr=0
    for _kv in ${kvs[@]+"${kvs[@]}"}; do [ "$_kv" = "interrompida=true" ] && _interr=1; done
    if [ -n "$_lock" ] && [ "$_interr" = 0 ]; then
      _res=$(sed -n 's/.*"resumo":"\([^"]*\)".*/\1/p' "$_lock" | head -1)
      trava "$f"
      last_seq=$(sed -n 's/.*"seq":\([0-9]*\).*/\1/p' "$f" 2>/dev/null | tail -n1)
      case "$last_seq" in (''|*[!0-9]*) last_seq=0 ;; esac
      _linha_inc="{\"ts\":\"$ts\",\"seq\":$((last_seq+1)),\"sessao\":\"$sess\",\"evento\":\"incidente\",\"etapa\":\"$etapa\",\"origem\":\"gate-dente\",\"detalhe\":\"end recusado: confere-etapa.sh em fail ($_res)\"}"
      printf '%s\n' "$_linha_inc" >> "$f"
      espelha "$dir" "$nn" "$_linha_inc"
      echo "GATE-EM-FAIL: end da etapa \"$_id\" RECUSADO — o último confere-etapa.sh falhou ($_res). Corrija e re-rode confere-etapa.sh $_id até pass (só ele remove o lock); se a falha pedir julgamento do dono, abra needs_decision. Incidente gravado."
      exit 0
    fi
  fi

  # UAT (v2.1.9, F24.3 falha 6): `end` da etapa 5 com veredito=pass enquanto o NN-UAT.md
  # ainda tem cenário [pending]/blocked é RECUSADO (pendência bloqueia o ship — o 1º end da
  # F24.3 saiu pass com o cenário 3 pendente e a etapa foi somada em dobro). E um 2º `end`
  # da MESMA etapa na MESMA sessão declara `substitui:<seq>` — quem soma (audit-gad,
  # dashboard) conta só o último; o 1º vira histórico, não custo.
  if [ "$evento" = "end" ]; then
    _id="${etapa%% *}"
    _pass=0; for _kv in ${kvs[@]+"${kvs[@]}"}; do [ "$_kv" = "veredito=pass" ] && _pass=1; done
    if [ "$_id" = "5" ] && [ "$_pass" = 1 ] && [ -f "$dir/$nn-UAT.md" ] \
       && grep -qE 'result: *(\[pending\]|blocked|pending)' "$dir/$nn-UAT.md"; then
      echo "UAT-PENDENTE: end da etapa 5 com veredito=pass RECUSADO — o $nn-UAT.md ainda tem cenário [pending]/blocked. Resolva o cenário (ou grave o end sem veredito=pass) e re-rode."
      exit 0
    fi
    _prev_end=$(grep "\"sessao\":\"$sess\"" "$f" 2>/dev/null | grep '"evento":"end"' \
                | grep -F "\"etapa\":\"$etapa\"" | grep -v '"auto_fechado":true' | tail -n1 \
                | sed -n 's/.*"seq":\([0-9]*\).*/\1/p')
    case "$_prev_end" in (''|*[!0-9]*) ;; (*) kvs+=("substitui=$_prev_end") ;; esac
  fi

  # O campo autodeclarado morreu (G.1-d): o 9º posicional é aceito e descartado.
  if [ -n "$c2" ]; then
    echo "aviso: tokens_camada2 morreu no esquema major — valor descartado; tokens reais agora vêm do mede-tokens.py (--tokens-reais/--custo no end da etapa)"
    c2=""
  fi

  # Checkpoint sem medição não passa em silêncio (caso real, F16-ox 25/07: o checkpoint da
  # 5.4 nasceu sem tokens/pct e ninguém notou até a auditoria). O aviso vai pro stdout — é o
  # canal que o orquestrador lê; a regra de reação (re-rodar o context-check 1x) é da Sub-G.
  if [ "$evento" = "checkpoint" ]; then
    case "$tokens" in
      (''|*[!0-9]*|0) echo "aviso: checkpoint sem tokens/pct — context-check falhou? re-rode o gate (1x) antes de seguir" ;;
    esac
  fi

  # FM-04UAT: elo da retomada. Um hand-back fecha a etapa 6 numa sessão (`stop`/etapa
  # "handback", rota 6.4-HB) ou — quando o workflow vier a gravar o veredito próprio da
  # FM-F4RLR-04UAT — um `end` da etapa 6 com `veredito=handback`; os dois disparadores são
  # aceitos. A retomada abre em OUTRA sessão (não há `sessao` em comum para casar), então o
  # 1º checkpoint da etapa 5 que aparece depois do hand-back — e só ele, sem outro checkpoint
  # de etapa 5 no meio — ganha o elo mecânico de volta: `retomada_de_seq`/`retomada_de_sessao`
  # apontam para a linha do hand-back. Quem lê o run-log (dashboard, recortes) passa a somar
  # as duas janelas de etapa 5 sem adivinhar por timestamp.
  RETOMADA_SEQ=""; RETOMADA_SESS=""
  _et5=0
  case "${etapa%% *}" in (5|5.*) _et5=1 ;; esac
  if [ "$evento" = "checkpoint" ] && [ "$_et5" = 1 ] && [ -f "$f" ]; then
    _hb_ln1=$(grep -n '"evento":"stop".*"etapa":"handback' "$f" 2>/dev/null | tail -n1 | cut -d: -f1)
    _hb_ln2=$(grep -n '"evento":"end".*"etapa":"6[^"]*".*"veredito":"handback"' "$f" 2>/dev/null | tail -n1 | cut -d: -f1)
    _hb_ln=""
    case "$_hb_ln1$_hb_ln2" in
      '') ;;
      *)
        if [ -n "$_hb_ln1" ] && [ -n "$_hb_ln2" ]; then
          [ "$_hb_ln1" -ge "$_hb_ln2" ] 2>/dev/null && _hb_ln="$_hb_ln1" || _hb_ln="$_hb_ln2"
        else
          _hb_ln="${_hb_ln1:-$_hb_ln2}"
        fi ;;
    esac
    if [ -n "$_hb_ln" ]; then
      _ja=$(tail -n +"$((_hb_ln+1))" "$f" 2>/dev/null | grep -cE '"evento":"checkpoint","etapa":"5([. ]|")')
      if [ "${_ja:-0}" -eq 0 ] 2>/dev/null; then
        _hb_row=$(sed -n "${_hb_ln}p" "$f")
        RETOMADA_SEQ=$(printf '%s' "$_hb_row" | sed -n 's/.*"seq":\([0-9]*\).*/\1/p')
        RETOMADA_SESS=$(printf '%s' "$_hb_row" | sed -n 's/.*"sessao":"\([^"]*\)".*/\1/p')
        [ -n "$RETOMADA_SEQ" ] && kvs+=("retomada_de_seq=$RETOMADA_SEQ")
        [ -n "$RETOMADA_SESS" ] && kvs+=("retomada_de_sessao=$RETOMADA_SESS")
      fi
    fi
  fi

  # Auto-fechamento de janela: checkpoint novo com o checkpoint anterior da MESMA sessão
  # ainda sem end/skip/stop → end sintético auto_fechado (fechamento não pode depender de
  # disciplina — caso real F20: a 3.4 rodou e ficou sem janela; o custo caiu na etapa vizinha)
  # t59 (FM-F27INS-01GAT): checkpoint com `--kv paralelo=true` abre janela SEM fechar as outras
  # (4.1b × 4.5, MGTm-01GAT) — só reabre a do MESMO ID; checkpoint comum fecha TODAS as abertas
  # da sessão, uma a uma, cada uma medida desde o próprio checkpoint (modelo em janelas_abertas).
  _paralelo=0
  for _kv in ${kvs[@]+"${kvs[@]}"}; do [ "$_kv" = "paralelo=true" ] && _paralelo=1; done
  if [ "$evento" = "checkpoint" ] && [ -f "$f" ] && [ "$sess" != "desconhe" ]; then
    while IFS=$'\t' read -r ln prev_etapa prev_ts; do
      [ -n "$ln" ] || continue
      if [ "$_paralelo" = 1 ] && [ "${prev_etapa%% *}" != "${etapa%% *}" ]; then continue; fi
      {
        # v2.1.9 (F24.3 falha 2): a janela órfã é MEDIDA pelo mede-tokens.py (do checkpoint
        # até agora) em vez de nascer sem tokens — a construção da S2 (7,05M tokens_reais)
        # saiu do run-log sem custo e o "end corretivo" à mão gravou o contexto da camada 0
        # (251.511) como se fosse custo. Falhou a medição → campo `medicao` com o motivo.
        _med='{"status":"sem_medicao","reason":"sem ts do checkpoint"}'
        _mt="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/mede-tokens.py"
        if [ -n "$prev_ts" ] && [ -f "$_mt" ] && [ -z "${RUNLOG_SEM_MEDICAO:-}" ]; then
          _med=$(python3 "$_mt" --sessao "${CLAUDE_CODE_SESSION_ID}" --desde "$prev_ts" \
                 --ate "$ts" --sem-espelho 2>/dev/null </dev/null || echo '{"status":"sem_medicao","reason":"mede-tokens falhou"}')
        fi
        _linha_auto="{\"ts\":\"$ts\",\"seq\":$seq,\"sessao\":\"$sess\",\"evento\":\"end\",\"etapa\":\"$prev_etapa\",\"auto_fechado\":true"
        if [ "$(printf '%s' "$_med" | sed -n 's/.*"status": *"\([a-z_]*\)".*/\1/p' | head -1)" = ok ]; then
          _tr=$(printf '%s' "$_med" | python3 -c 'import json,sys; t=json.load(sys.stdin)["total"]; print(t["input_tokens"]+t["output_tokens"]+t["cache_creation_tokens"]+t.get("cache_creation_1h_tokens",0)); ' 2>/dev/null)
          _cu=$(printf '%s' "$_med" | python3 -c 'import json,sys; print(json.load(sys.stdin)["total"].get("custo_usd",0))' 2>/dev/null)
          case "$_tr" in (''|*[!0-9]*) ;; (*) _linha_auto="$_linha_auto,\"tokens_reais\":$_tr,\"custo_usd\":${_cu:-0},\"medicao\":\"auto (mede-tokens.py, janela do checkpoint)\"" ;; esac
        else
          _rz=$(printf '%s' "$_med" | sed -n 's/.*"reason": *"\([^"]*\)".*/\1/p' | head -1 | tr -d '\\"')
          _linha_auto="$_linha_auto,\"medicao\":\"indisponivel: ${_rz:-desconhecido}\""
        fi
        _linha_auto="$_linha_auto}"
        printf '%s\n' "$_linha_auto" >> "$f"
        espelha "$dir" "$nn" "$_linha_auto"
        # FM-03ENC: STDERR. Este aviso saía no STDOUT e ia parar no meio do JSON do
        # pre-despacho.sh — medido em 20/09: o leitor da camada 0 morreu com erro de
        # JSON, chamou de novo e o efeito colateral ficou no run-log (um `end` sintético
        # da etapa 6 sete segundos depois do checkpoint). Prosa é stderr; o fato vira
        # campo `janela_fechada_automaticamente` no JSON de quem chama.
        echo >&2 "janela-fechada-automaticamente: etapa \"$prev_etapa\" estava sem end/skip — end sintético gravado COM medição do mede-tokens.py quando disponível; NÃO grave um 'end corretivo' com número do harness (contexto ≠ custo)"
        seq=$((seq+1))
      }
    done < <(janelas_abertas "$f" "$sess")
  fi

  # Detector mecânico de auto-compact (ver cabeçalho): só em checkpoint com tokens > 0
  # (0 = medição falhou, não compact) e com session id real (sem id, duas rodadas viram a
  # mesma "sessão" e uma retomada pareceria queda). prev = último valor > 0 da mesma sessão
  # (pular zeros evita que uma medição falha mascare um compact real logo depois).
  if [ "$evento" = "checkpoint" ] && [ "$sess" != "desconhe" ]; then
    case "$tokens" in
      (''|*[!0-9]*|0) ;;
      (*)
        # só CHECKPOINTS entram na comparação (v2.1.9): um `end`/`stop` com `tokens`
        # posicional (F24.3: end corretivo com 251.511 = contexto, não custo) gerava
        # compact falso — fotografia compara com fotografia
        prev=$(grep "\"sessao\":\"$sess\"" "$f" 2>/dev/null | grep '"evento":"checkpoint"' \
               | sed -n 's/.*"tokens":\([0-9]*\).*/\1/p' | awk '$0+0 > 0' | tail -n1)
        if [ -n "$prev" ] && [ "$prev" -gt 0 ] 2>/dev/null && [ $(( prev - tokens )) -gt 100000 ]; then
          _linha_cpt="{\"ts\":\"$ts\",\"seq\":$seq,\"sessao\":\"$sess\",\"evento\":\"compact\",\"etapa\":\"auto-detectado: queda ${prev} -> ${tokens} tokens\"}"
          printf '%s\n' "$_linha_cpt" >> "$f"
          espelha "$dir" "$nn" "$_linha_cpt"
          # Sinal no stdout — é assim que o orquestrador fica sabendo (o append é silencioso).
          echo "compact-detectado: queda ${prev} -> ${tokens} tokens"
          seq=$((seq+1))
        fi
        ;;
    esac
  fi

  # Versão da skill no evento `run` (mecânico — sem depender de disciplina do modelo):
  # `git describe` no clone (o script vive dentro dele; pwd -P resolve o symlink).
  # Motivo: na F19 uma release saiu com a fase em voo e a auditoria teve que reconstruir
  # por timestamps de commit qual versão regia cada etapa. Falhou o git → campo omitido.
  ver=""
  if [ "$evento" = "run" ]; then
    _sd=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P)
    [ -n "$_sd" ] && ver=$(git -C "$_sd" describe --tags --always 2>/dev/null | tr -cd 'A-Za-z0-9._-' | head -c 40)
  fi

  linha="{\"ts\":\"$ts\",\"seq\":$seq,\"sessao\":\"$sess\",\"evento\":\"$evento\",\"etapa\":\"$etapa\""
  [ -n "$ver" ] && linha="$linha,\"skill_version\":\"$ver\""
  # camada: 0/1/2 viram número; "externa" (codex/agy) vira string
  case "$camada" in ('') ;; (*[!0-9]*) camada=$(printf '%s' "$camada" | tr -cd 'a-z'); [ -n "$camada" ] && linha="$linha,\"camada\":\"$camada\"" ;; (*) linha="$linha,\"camada\":$camada" ;; esac
  [ -n "$modelo" ] && linha="$linha,\"modelo\":\"$(printf '%s' "$modelo" | tr -cd 'A-Za-z0-9._-')\""
  [ -n "$effort" ] && linha="$linha,\"effort\":\"$(printf '%s' "$effort" | tr -cd 'a-z')\""
  case "$tokens" in (*[!0-9]*|'') ;; (*) linha="$linha,\"tokens\":$tokens";; esac
  case "$pct" in (*[!0-9]*|'') ;; (*) linha="$linha,\"pct\":$pct";; esac
  case "$lim" in (*[!0-9]*|'') ;; (*) linha="$linha,\"limit\":$lim";; esac
  case "$subt" in (*[!0-9]*|'') ;; (*) linha="$linha,\"subagent_tokens\":$subt";; esac
  # medição mecânica (mede-tokens.py) — só entra por flag, nunca por autodeclaração
  case "$treais" in (*[!0-9]*|'') ;; (*) linha="$linha,\"tokens_reais\":$treais";; esac
  case "$custo" in
    ('') ;;
    (*[!0-9.]*) ;;
    (*) linha="$linha,\"custo_usd\":$custo" ;;
  esac
  # campos extras --kv chave=valor (número/true/false = JSON cru; resto = string escapada)
  for _kv in ${kvs[@]+"${kvs[@]}"}; do
    _k="${_kv%%=*}"; _v="${_kv#*=}"
    _k=$(printf '%s' "$_k" | tr -cd 'A-Za-z0-9_'); [ -n "$_k" ] || continue
    case "$_v" in
      (true|false) linha="$linha,\"$_k\":$_v" ;;
      (''|*[!0-9]*) _v=$(printf '%s' "$_v" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r\t')
                    linha="$linha,\"$_k\":\"$_v\"" ;;
      (*) linha="$linha,\"$_k\":$_v" ;;
    esac
  done
  [ -n "$motivo" ] && linha="$linha,\"motivo\":\"$motivo\""
  # end órfão de camada 2 → atribuição determinística ao pai pelo ID canônico
  case "$etapa" in
    (*"(camada 2 retomada"*) linha="$linha,\"parent_etapa\":\"${etapa%% *}\"" ;;
  esac
  linha="$linha}"

  printf '%s\n' "$linha" >> "$f"
  espelha "$dir" "$nn" "$linha"
} 2>/dev/null
exit 0
