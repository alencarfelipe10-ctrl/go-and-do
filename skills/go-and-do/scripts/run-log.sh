#!/usr/bin/env bash
# run-log.sh — telemetria da go-and-do (endurecida em 27/07/2026 — plano da auditoria F20).
# Uso: run-log.sh <phase_dir> <NN> <evento> "<etapa>" [tokens] [pct] [subagent_tokens] [limit] [tokens_camada2] [motivo]
#      run-log.sh <phase_dir> <NN> audit   → audita a GRADE (janelas abertas por sessão; não muta)
#      run-log.sh <phase_dir> <NN> close --sessao <id> ["motivo"]
#                                          → fecho ADMINISTRATIVO de janela órfã de sessão MORTA
#                                            (end sintético "fechado_admin"; a sessão atual não
#                                            consegue fechar janela alheia pelo caminho normal —
#                                            2 ocorrências: F19-inspired e F2-rlr 29/07)
#      run-log.sh --selftest               → auto-teste em sandbox (única rota que pode sair != 0)
#
#   evento ∈ {run, checkpoint, end, stop, skip, compact, audit}
#
# ── PAPEL DOS NÚMEROS (leia antes de somar qualquer coisa) ─────────────────────────────
#   `tokens`/`pct` (checkpoint) = FOTOGRAFIA do contexto da camada 0 naquele instante.
#   `subagent_tokens` (end)     = usage CUMULATIVO que o harness reportou a um despacho
#   (input + cache_creation + cache_read + output de TODOS os turnos — o cache_read
#   recontabiliza a janela inteira a cada turno). É CONFERÊNCIA, nunca métrica de custo:
#   somar isso como "custo da fase" superconta ~3-4x (caso real F20: 8,34M alegados vs
#   2,30M de output medidos). A métrica é o ledger da /audit-gad (mede dos transcripts).
#   O que este log tem de INSUBSTITUÍVEL é a GRADE: seq + timestamps + etapas canônicas,
#   que permitem atribuir o consumo medido a etapas nomeadas.
#
# ── ENDURECIMENTOS MECÂNICOS (nenhum depende de disciplina do modelo) ──────────────────
#   seq            — contador monotônico por arquivo; ordenação canônica (7 pares end/checkpoint
#                    no mesmo segundo na F20 tornavam a ordem por timestamp ambígua).
#   auto-fechamento— checkpoint novo com a janela anterior da MESMA sessão ainda aberta →
#                    grava antes um `end` sintético `"auto_fechado":true` e avisa no stdout
#                    (caso real F20: a 3.4 verificação rodou, produziu artefato e ficou sem
#                    janela — o custo dela caiu no balde do code review).
#   vocabulário    — a etapa DEVE começar com o ID canônico (`3.3 execucao`, `0-B intencao`,
#                    `lateral pesquisa X`); fora do vocabulário → aviso no stdout (não falha).
#   compact        — detector mecânico (desde 07/07/2026): queda > 100k na mesma sessão →
#                    evento `compact` gravado pelo próprio script (na AOS-10 o modelo detectou
#                    verbalmente e esqueceu de logar).
#   skill_version  — `git describe` no clone, no evento `run` (na F19 uma release saiu com a
#                    fase em voo e a auditoria reconstruiu a versão por timestamps).
#   camada2        — 9º arg: número = tokens_camada2 (soma reportada aos despachos do host);
#                    literal `sem_report` = chave `"camada2":"sem_report"` (ausência passa a
#                    ser distinguível de contagem completa). NUNCA estimado.
#   motivo         — 10º arg: texto livre do stop/skip vai em campo próprio, não na etapa.
#   parent_etapa   — end órfão de camada 2 (etapa contendo "(camada 2 retomada") ganha
#                    automaticamente `"parent_etapa":"<ID>"` — atribuição determinística ao pai.
#
# Appenda 1 linha JSON em <phase_dir>/<NN>-RUN-LOG.jsonl.
# Telemetria é instrumento, não gate: fora do --selftest, NUNCA falha o pipeline (exit 0).

# ───────────────────────────── selftest ─────────────────────────────
if [ "$1" = "--selftest" ]; then
  SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/$(basename -- "$0")"
  TMP=$(mktemp -d) || exit 1
  export CLAUDE_CODE_SESSION_ID="selftest0-0000-0000"
  D="$TMP/.planning/phases/99-teste"; F="$D/99-RUN-LOG.jsonl"
  fail=0
  ok()  { echo "PASS: $1"; }
  bad() { echo "FAIL: $1"; fail=1; }

  bash "$SELF" "$D" 99 run "preparacao" >/dev/null
  grep -q '"evento":"run"' "$F" && grep -q '"seq":1' "$F" && ok "run + seq inicial" || bad "run + seq inicial"
  grep -q '"skill_version"' "$F" && ok "skill_version no run" || bad "skill_version no run (git describe falhou?)"

  bash "$SELF" "$D" 99 checkpoint "0-B intencao" 300000 75 "" 400000 >/dev/null
  grep -q '"tokens":300000,"pct":75,"limit":400000' "$F" && ok "checkpoint com medição" || bad "checkpoint com medição"

  out=$(bash "$SELF" "$D" 99 checkpoint "2.3 planejamento" 310000 77 "" 400000)
  echo "$out" | grep -q "janela-fechada-automaticamente" && grep -q '"auto_fechado":true' "$F" \
    && ok "auto-fechamento de janela aberta" || bad "auto-fechamento de janela aberta"

  bash "$SELF" "$D" 99 end "2.3 planejamento" "" "" 123456 "" 9999 >/dev/null
  grep -q '"subagent_tokens":123456,"tokens_camada2":9999' "$F" && ok "end com tokens_camada2" || bad "end com tokens_camada2"

  bash "$SELF" "$D" 99 end "3.2 convergencia" "" "" 111 "" sem_report >/dev/null
  grep -q '"camada2":"sem_report"' "$F" && ok "marcador sem_report" || bad "marcador sem_report"

  out=$(bash "$SELF" "$D" 99 checkpoint "3.3 execucao" 100000 25 "" 400000)
  echo "$out" | grep -q "compact-detectado" && grep -q '"evento":"compact"' "$F" \
    && ok "detector de compact" || bad "detector de compact"

  bash "$SELF" "$D" 99 end '3.3 execucao (camada 2 retomada — plano 03)' "" "" 5555 >/dev/null
  grep -q '"parent_etapa":"3.3"' "$F" && ok "parent_etapa no end órfão" || bad "parent_etapa no end órfão"

  out=$(bash "$SELF" "$D" 99 end "etapa-inventada qualquer" "" "" 1 2>/dev/null)
  echo "$out" | grep -q "fora do vocabulário" && ok "aviso de vocabulário" || bad "aviso de vocabulário"

  bash "$SELF" "$D" 99 end "3.3 execucao" "" "" 42 >/dev/null
  bash "$SELF" "$D" 99 stop "pausa" 320000 80 "" 400000 "" 'ship bloqueado — repo sem remote ("LGPD")' >/dev/null
  grep -q '"evento":"stop".*"motivo":"ship bloqueado' "$F" && ok "stop com medição + motivo (escapado)" || bad "stop com medição + motivo"

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
  case "${CLAUDE_CODE_SESSION_ID:-}" in selftest*) return 0 ;; esac
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
  ) >/dev/null 2>&1 &
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
    echo "audit: linhas=$(wc -l < "$f" | tr -d ' ') run=$(grep -c '"evento":"run"' "$f") checkpoint=$(grep -c '"evento":"checkpoint"' "$f") end=$(grep -c '"evento":"end"' "$f") skip=$(grep -c '"evento":"skip"' "$f") stop=$(grep -c '"evento":"stop"' "$f") compact=$(grep -c '"evento":"compact"' "$f") janelas_abertas=$abertas"
    echo "audit: lembrete — todo passo que TERIA rodado e não rodou precisa de um evento skip (UI/AI/eval/secure com gate off etc.); o script não adivinha o que devia rodar, só cobra o que ficou aberto"
  } 2>/dev/null
  exit 0
fi

# ───────────────────────────── escrita normal ─────────────────────────────
{
  dir="$1"; nn="$2"; evento="$3"; etapa="$4"; tokens="${5:-}"; pct="${6:-}"; subt="${7:-}"; lim="${8:-}"; c2="${9:-}"; motivo="${10:-}"
  [ -n "$dir" ] && [ -n "$nn" ] && [ -n "$evento" ] || exit 0
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

  # seq monotônico por arquivo (ordenação canônica; timestamps têm resolução de 1s e
  # colidem — 7 pares end/checkpoint no mesmo segundo na F20)
  last_seq=$(sed -n 's/.*"seq":\([0-9]*\).*/\1/p' "$f" 2>/dev/null | tail -n1)
  case "$last_seq" in (''|*[!0-9]*) last_seq=0 ;; esac
  seq=$((last_seq+1))

  # etapa e motivo são texto livre — escapa aspas e barras pro JSON não quebrar
  etapa=$(printf '%s' "$etapa" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r\t')
  motivo=$(printf '%s' "$motivo" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r\t')

  # Vocabulário canônico: a etapa começa com o ID do passo (aviso, nunca falha — texto
  # livre sem ID inviabiliza agregação entre fases; caso real F20: 4 grafias distintas)
  case "$evento" in
    checkpoint|end|skip)
      _id="${etapa%% *}"
      case "$_id" in
        preparacao|probe|lateral|resumo|verificacao|0-A|0-B|1|1.[0-9]*|2.[0-9]*|3.[0-9]*|4.[0-9]*|5.[0-9]*|6.[0-9]*) : ;;
        *) echo "aviso: etapa \"$_id\" fora do vocabulário canônico — prefixe com o ID do passo (ex.: \"3.3 execucao\", \"0-B intencao\", \"lateral pesquisa X\")" ;;
      esac ;;
  esac

  # Checkpoint sem medição não passa em silêncio (caso real, F16-ox 25/07: o checkpoint da
  # 5.4 nasceu sem tokens/pct e ninguém notou até a auditoria). O aviso vai pro stdout — é o
  # canal que o orquestrador lê; a regra de reação (re-rodar o context-check 1x) é da Sub-G.
  if [ "$evento" = "checkpoint" ]; then
    case "$tokens" in
      (''|*[!0-9]*|0) echo "aviso: checkpoint sem tokens/pct — context-check falhou? re-rode o bloco da Sub-rotina A (1x) antes de seguir" ;;
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
  case "$tokens" in (*[!0-9]*|'') ;; (*) linha="$linha,\"tokens\":$tokens";; esac
  case "$pct" in (*[!0-9]*|'') ;; (*) linha="$linha,\"pct\":$pct";; esac
  case "$lim" in (*[!0-9]*|'') ;; (*) linha="$linha,\"limit\":$lim";; esac
  case "$subt" in (*[!0-9]*|'') ;; (*) linha="$linha,\"subagent_tokens\":$subt";; esac
  # camada 2: número = soma reportada; `sem_report` = marcador verificável de ausência
  case "$c2" in
    (sem_report) linha="$linha,\"camada2\":\"sem_report\"" ;;
    (*[!0-9]*|'') ;;
    (*) linha="$linha,\"tokens_camada2\":$c2" ;;
  esac
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
