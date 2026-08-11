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
# Modos:  run-log.sh <phase_dir> <NN> audit                    → audita a GRADE (não muta)
#         run-log.sh <phase_dir> <NN> close --sessao <id> [m]  → fecho ADMINISTRATIVO de
#                    janela órfã de sessão MORTA (2 ocorrências: F19-inspired e F2-rlr)
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
#                    grava antes um `end` sintético `"auto_fechado":true` e avisa no stdout.
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

  out=$(bash "$SELF" "$D" 99 checkpoint "2 planejamento" 310000 77 "" 400000)
  echo "$out" | grep -q "janela-fechada-automaticamente" && grep -q '"auto_fechado":true' "$F" \
    && ok "auto-fechamento de janela aberta" || bad "auto-fechamento de janela aberta"

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

  out=$(bash "$SELF" "$D" 99 checkpoint "3 construcao" 100000 25 "" 400000)
  echo "$out" | grep -q "compact-detectado" && grep -q '"evento":"compact"' "$F" \
    && ok "detector de compact" || bad "detector de compact"

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
    ln=$(grep -n "\"sessao\":\"$alvo\"" "$f" | grep '"evento":"checkpoint"' | tail -n1 | cut -d: -f1)
    [ -n "$ln" ] || { echo "close: nenhuma janela da sessão $alvo neste run-log"; exit 0; }
    closed=$(tail -n +"$((ln+1))" "$f" | grep "\"sessao\":\"$alvo\"" | grep -c '"evento":"\(end\|skip\|stop\)"')
    if [ "$closed" -gt 0 ] 2>/dev/null; then
      echo "close: a janela da sessão $alvo já está fechada — nada a fazer"; exit 0
    fi
    et=$(sed -n "${ln}p" "$f" | sed -n 's/.*"etapa":"\([^"]*\)".*/\1/p')
    ts=$(date -Is 2>/dev/null || date +%s)
    last_seq=$(sed -n 's/.*"seq":\([0-9]*\).*/\1/p' "$f" 2>/dev/null | tail -n1)
    case "$last_seq" in (''|*[!0-9]*) last_seq=0 ;; esac
    seq=$((last_seq+1))
    motivo=$(printf '%s' "$motivo" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r\t')
    linha="{\"ts\":\"$ts\",\"seq\":$seq,\"sessao\":\"$alvo\",\"evento\":\"end\",\"etapa\":\"$et\",\"fechado_admin\":true,\"fechado_por\":\"${cur:0:8}\""
    [ -n "$motivo" ] && linha="$linha,\"motivo\":\"$motivo\""
    linha="$linha}"
    printf '%s\n' "$linha" >> "$f"
    espelha "$dir" "$nn" "$linha"
    echo "close: janela da sessão $alvo (etapa \"$et\") fechada administrativamente — o custo de subagentes dela NÃO foi registrado (anote se souber)"
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
      ln=$(grep -n "\"sessao\":\"$s\"" "$f" | grep '"evento":"checkpoint"' | tail -n1 | cut -d: -f1)
      [ -n "$ln" ] || continue
      closed=$(tail -n +"$((ln+1))" "$f" | grep "\"sessao\":\"$s\"" | grep -c '"evento":"\(end\|skip\|stop\)"')
      if [ "$closed" -eq 0 ] 2>/dev/null; then
        et=$(sed -n "${ln}p" "$f" | sed -n 's/.*"etapa":"\([^"]*\)".*/\1/p')
        if [ "$s" = "${CLAUDE_CODE_SESSION_ID:0:8}" ]; then
          echo "audit: JANELA ABERTA na sessão $s — etapa \"$et\" sem end/skip/stop (feche-a antes do stop)"
        else
          echo "audit: JANELA ABERTA na sessão $s — etapa \"$et\" sem end/skip/stop; sessão NÃO é a atual (morreu?) → feche com: run-log.sh <dir> <NN> close --sessao $s \"motivo\""
        fi
        abertas=$((abertas+1))
      fi
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
  # .gate-fail-<id>.json na phase_dir e SÓ ele, ao dar pass, remove. Um `end` com o
  # lock vivo é recusado: vira evento `incidente` + instrução no stdout. Exceções que
  # fecham janela sem passar pelo gate: interrompida=true (pausa) e stop/skip.
  if [ "$evento" = "end" ]; then
    _id="${etapa%% *}"
    _lock="$dir/.gate-fail-$_id.json"
    _interr=0
    for _kv in ${kvs[@]+"${kvs[@]}"}; do [ "$_kv" = "interrompida=true" ] && _interr=1; done
    if [ -f "$_lock" ] && [ "$_interr" = 0 ]; then
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

  # Auto-fechamento de janela: checkpoint novo com o checkpoint anterior da MESMA sessão
  # ainda sem end/skip/stop → end sintético auto_fechado (fechamento não pode depender de
  # disciplina — caso real F20: a 3.4 rodou e ficou sem janela; o custo caiu na etapa vizinha)
  if [ "$evento" = "checkpoint" ] && [ -f "$f" ] && [ "$sess" != "desconhe" ]; then
    ln=$(grep -n "\"sessao\":\"$sess\"" "$f" | grep '"evento":"checkpoint"' | tail -n1 | cut -d: -f1)
    if [ -n "$ln" ]; then
      closed=$(tail -n +"$((ln+1))" "$f" | grep "\"sessao\":\"$sess\"" | grep -c '"evento":"\(end\|skip\|stop\)"')
      if [ "$closed" -eq 0 ] 2>/dev/null; then
        prev_etapa=$(sed -n "${ln}p" "$f" | sed -n 's/.*"etapa":"\([^"]*\)".*/\1/p')
        _linha_auto="{\"ts\":\"$ts\",\"seq\":$seq,\"sessao\":\"$sess\",\"evento\":\"end\",\"etapa\":\"$prev_etapa\",\"auto_fechado\":true}"
        printf '%s\n' "$_linha_auto" >> "$f"
        espelha "$dir" "$nn" "$_linha_auto"
        echo "janela-fechada-automaticamente: etapa \"$prev_etapa\" estava sem end/skip — end sintético gravado; se houve subagente, o custo dele NÃO foi registrado (anote se souber)"
        seq=$((seq+1))
      fi
    fi
  fi

  # Detector mecânico de auto-compact (ver cabeçalho): só em checkpoint com tokens > 0
  # (0 = medição falhou, não compact) e com session id real (sem id, duas rodadas viram a
  # mesma "sessão" e uma retomada pareceria queda). prev = último valor > 0 da mesma sessão
  # (pular zeros evita que uma medição falha mascare um compact real logo depois).
  if [ "$evento" = "checkpoint" ] && [ "$sess" != "desconhe" ]; then
    case "$tokens" in
      (''|*[!0-9]*|0) ;;
      (*)
        prev=$(grep "\"sessao\":\"$sess\"" "$f" 2>/dev/null \
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
