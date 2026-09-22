#!/usr/bin/env bash
# confere-etapa.sh — cancela de CHEGADA de toda etapa (decisões 2.C + T.1).
#
# Quando o subagente volta com "done", a camada 0 NÃO acredita: roda isto. O script
# checa o DISCO contra o manifest da etapa (scripts/manifests/etapa-<etapa>.json —
# espelho 1:1 do contrato de saída que o prompt da etapa declara) e devolve o veredito.
# `fail` → exit 1 e a camada 0 devolve a lista do que falta AO MESMO subagente, não
# importa o que ele alegou (precedentes: marcadores fabricados F21-ox, Instruction
# Poisoning F2-rlr). Fiscalizar por cancela, não por releitura.
#
# Uso: confere-etapa.sh <etapa> [--fase N] [--projeto DIR] [--dry-run]
#   <etapa> = nome do manifest (string opaca, PC-9): 0 · 1 · 1.5 · 2 · 2.5 · 3 ·
#   4-code-review · 4-ui-review · 4-eval-review · 4-secure · 4-validate · 5 · 6.
#   <etapa> = "pausa" (sem manifest): fecho de INTERRUPÇÃO (Sub-rotina D) — mede a
#   janela aberta desta sessão com mede-tokens.py e grava o `end` com o rótulo
#   CANÔNICO do checkpoint + "interrompida":true (fix da falha 2 da auditoria F24:
#   o caminho de pausa não media e fragmentava o rótulo da etapa em 3 variantes).
#   --dry-run: avalia e imprime, não grava evento nenhum (PC-12 — validação contra
#   fases arquivadas sem sujar run-log real).
#   --sem-telemetria: avalia e grava o `.fence-<etapa>.ok` no pass (removendo-o no fail), e NÃO
#   grava evento nenhum no run-log, NÃO mede tokens e NÃO TOCA NO LOCK `.gate-fail-<etapa>.json`
#   (nem o cria no fail, nem o remove no pass). É o modo do subagente de camada 1, que confere o
#   próprio trabalho antes de devolver `done` (46 j / 46 r). Duas razões, as duas medidas:
#   (1) telemetria é da camada 0, que re-roda esta cancela na chegada — dois `end` para a mesma
#   etapa falseiam o ledger (a limpeza do 45(b) teve de apagar linhas do run-log da 24.5 por
#   contaminação parecida); (2) o lock é o insumo do `POS_FAIL` logo abaixo: se esta rodada o
#   removesse, a rodada com telemetria veria `POS_FAIL=0` e o evento `pass pós-fail (lock
#   removido)` da v2.1.9 nunca seria gravado — a fase ficaria com o `fail` no run-log e sem o
#   `pass` que o destravou (F24.3 4.4).
#   Resumo:            fence | lock | run-log | mede
#     normal            sim  | sim  |  sim    | sim
#     --sem-telemetria  sim  | NÃO  |  não    | não
#     --dry-run         não  | não  |  não    | não
#   <etapa> = "pausa" --pos-pausa (P17, v2.4.0): cancela DEPOIS do `reconcilia-docs.sh
#   --pausa` — não mede nada, só confere que o STATE.md diz `status: paused` e que o
#   `state_head` é HEAD ou HEAD~1 (o WIP logo antes do commit próprio do reconciliador).
#   Na F24.4 o STATE.md ficou 16 commits atrás do HEAD depois da pausa e ninguém viu.
#
# Manifest (DSL dos asserts):
#   nivel "falha" reprova a etapa; "informativo" só reporta (PC-4: asserts que dependem
#   de evento de hook são informativos quando o hook não está instalado).
#   condicao {flag, sinal}: aplica só se a flag da rodada (ponteiro) estiver ligada;
#   sem ponteiro, aplica se o glob `sinal` existir no disco (retomada/dry-run).
#   tipos: glob (padrao+min/max de arquivos) · grep (arquivo/glob + regex + min/max de
#   ocorrências) · sdk (gsd_run query + jq + espera) · ou (passa se qualquer sub-assert
#   passar). Placeholders: {fase}=phase_dir · {nn}=NN · {n}=fase · {root}=raiz.
#
# Blocos MECÂNICOS fora do manifest (a DSL só sabe glob/grep/sdk/json): etapa 1 = R2
# (`confere-pre-spec.sh --exige-origem [--reqs REQUIREMENTS.md] <SPEC> <PRE-SPEC>`: falhas
# reprovam — inclusive AC-SEM-ORIGEM e AC-ORIGEM-INEXISTENTE, P12 —; EXTENSAO-SUSPEITA e
# ORIGEM-NAO-CONFERIDA viram aviso em `extrai.r2_avisos`) + R6 (`setup-intencao.sh --r6`: cada issue estruturada exige id
# no REQUIREMENTS.md OU sino `req_ausente: <id>` / `fase_sem_req` — nos `.sinos-*.txt` ou
# no NN-INTENT-REVIEW.md, que é onde o conteúdo sobrevive à limpeza 1.5); etapa 5 = UAT;
# etapa 6 = self-check.
#
# No pass (fora do --dry-run): mede a etapa com mede-tokens.py (janela desde o
# checkpoint aberto pelo pre-despacho) e grava o evento `end` com tokens_reais/custo —
# números só de fonte mecânica (G.1). No fail: grava evento `script` com o resumo.
# Saída: JSON 1 linha + espelho .planning/.gad/last-confere-etapa.json (PC-5).
# Exit: 0 pass · 1 fail · 2 erro de uso/manifest.

set -euo pipefail
shopt -s nullglob
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

ETAPA="${1:-}"; shift || true
[ -n "$ETAPA" ] || { echo "uso: confere-etapa.sh <etapa> [--fase N] [--projeto DIR] [--dry-run] [--fix-cycle] [--reuat]" >&2; exit 2; }
FASE=""; PROJ=""; DRY=0; SEMTEL=0; FIXCYCLE=0; POSPAUSA=0; REUAT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fase)    FASE="${2:-}"; shift 2 ;;
    --projeto) PROJ="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; export GAD_DRY_RUN=1; shift ;;
    --sem-telemetria) SEMTEL=1; shift ;;
    --fix-cycle) FIXCYCLE=1; shift ;;
    --reuat) REUAT=1; shift ;;
    --pos-pausa) POSPAUSA=1; shift ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

# ── B1 (F4 RLR, FM-08INT+FM-07EXE+FM-05UAT): o fiscal grava o PRÓPRIO evento `script`
# a cada execução, com o exit REAL — inclusive quando falha/repassa. Antes, só os dois
# sites de escrita manual abaixo (pos-fail e fail) geravam o evento; um pass comum não
# gravava nada. Um único `trap EXIT` cobre os três casos (pass comum, pos-fail, fail) e
# qualquer saída antecipada (uso, manifest ausente). `rc` é capturado ANTES de qualquer
# outro comando no trap — "$?" sozinho no corpo do trap pegaria o exit do PRÓPRIO teste
# `[ ... ]`, não o do script (mesma lição do `trap` do spot-check-ponteiros.sh, B1 R2).
# --sem-telemetria (46 j/r): contrato documentado "NÃO grava evento nenhum no run-log" —
# a guarda abaixo respeita isso; --dry-run já sai de graça via GAD_DRY_RUN (gad_autoregistro
# e o `gad_runlog` direto abaixo escrevem em $PHASE_DIR/$NN, que só existe fora do dry-run
# porque DRY guarda toda a lógica de escrita mais abaixo — não há caminho de escrita real
# sob --dry-run mesmo sem essa guarda; a guarda por GAD_DRY_RUN é só para o `gad_autoregistro`
# de fallback nos exits antecipados).
_gad_ce_resumo() { # linha "etapa modo veredito baldes" — sempre resolvível, mesmo cedo
  local etapa="${RUNLOG_ETAPA:-$ETAPA}" modo="" n extra=""
  [ "$ETAPA" = pausa ] && modo="pausa"
  [ "${POSPAUSA:-0}" = 1 ] && modo="${modo:+$modo,}pos-pausa"
  [ "${FIXCYCLE:-0}" = 1 ] && modo="${modo:+$modo,}fixcycle"
  [ "${REUAT:-0}" = 1 ] && modo="${modo:+$modo,}reuat"
  [ -n "$modo" ] || modo="normal"
  n=$(jq 'length' <<<"${RES:-[]}" 2>/dev/null) || n=0
  if [ "${VEREDITO:-}" = fail ] && [ -n "${resumo:-}" ]; then extra=" falhas: $resumo"; fi
  if [ "${POS_FAIL:-0}" = 1 ]; then extra="$extra pass pós-fail (lock removido)"; fi
  printf 'etapa=%s modo=%s veredito=%s baldes=%s%s' "$etapa" "$modo" "${VEREDITO:-${ver:-erro}}" "$n" "$extra"
}
_gad_ce_grava_script() { # <rc> <resumo>
  # --dry-run: nenhuma escrita, nem por este caminho direto — gad_runlog não olha
  # GAD_DRY_RUN sozinho (só gad_autoregistro/gad_json_out olham); a guarda é daqui.
  [ "${GAD_DRY_RUN:-0}" = 1 ] && return 0
  if [ -n "${PHASE_DIR:-}" ] && [ -n "${NN:-}" ] && [ -n "${RUNLOG_ETAPA:-}" ]; then
    # sites com fase/etapa já resolvidos (via --fase/--projeto OU ponteiro): grava direto,
    # sem depender do ponteiro `.gad-rodada-ativa.json` (o gad_autoregistro exige `.nn` +
    # `.phase_dir` NELE — bancadas que passam --fase sem ponteiro completo, como
    # test-confere-etapa.sh, ficariam mudas se dependessem só dele).
    gad_runlog "$PHASE_DIR" "$NN" script "$RUNLOG_ETAPA" \
      --kv script=confere-etapa.sh --kv exit="$1" --kv resumo="$2"
  else
    # exit antecipado (uso, manifest ausente, fase não resolvida): sem PHASE_DIR/NN não
    # há onde escrever direto — só resta o ponteiro de rodada ativa, via gad_autoregistro.
    gad_autoregistro "confere-etapa.sh" "$1" "$2"
  fi
}
trap 'rc=$?; [ "${SEMTEL:-0}" = 1 ] || _gad_ce_grava_script "$rc" "$(_gad_ce_resumo)"' EXIT

if [ "$ETAPA" != "pausa" ]; then
  MANIFEST="$GAD_SCRIPTS_DIR/manifests/etapa-$ETAPA.json"
  [ -f "$MANIFEST" ] || { echo "ERRO: manifest inexistente para etapa \"$ETAPA\" ($MANIFEST)" >&2; exit 2; }
  jq -e . "$MANIFEST" >/dev/null || { echo "ERRO: manifest inválido: $MANIFEST" >&2; exit 2; }
  RUNLOG_ETAPA=$(jq -r '.runlog_etapa' "$MANIFEST")
fi

ROOT="$(gad_project_root "${PROJ:-$PWD}")"
PONTEIRO="$ROOT/.planning/.gad-rodada-ativa.json"
NN=""; PHASE_DIR=""
if [ -z "$FASE" ] && [ -f "$PONTEIRO" ]; then
  FASE=$(jq -r '.fase // empty' "$PONTEIRO")
  NN=$(jq -r '.nn // empty' "$PONTEIRO")
  PHASE_DIR=$(jq -r '.phase_dir // empty' "$PONTEIRO")
fi
[ -n "$FASE" ] || { echo "ERRO: fase desconhecida — sem ponteiro de rodada e sem --fase" >&2; exit 2; }
[ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ] || PHASE_DIR=$(gad_phase_dir "$ROOT" "$FASE") \
  || { echo "ERRO: fase $FASE não encontrada em $ROOT/.planning/phases/" >&2; exit 2; }
[ -n "$NN" ] || NN=$(basename "$PHASE_DIR" | grep -o '[0-9][0-9.]*' | head -1)

# ── modo pausa --pos-pausa: o STATE.md aponta o commit real da parada? ───────
if [ "$ETAPA" = "pausa" ] && [ "$POSPAUSA" = 1 ]; then
  STATE="$ROOT/.planning/STATE.md"; MOTIVOS="[]"
  motivo() { MOTIVOS=$(jq -c --arg m "$1" '. + [$m]' <<<"$MOTIVOS"); }
  st=""; sh=""
  if [ -f "$STATE" ]; then
    st=$(grep -m1 -E '^status: ' "$STATE" | sed -e 's/^status:[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/\r$//' || true)
    sh=$(grep -m1 -E '^state_head: ' "$STATE" | sed -e 's/^state_head:[[:space:]]*//' -e 's/[[:space:]]*$//' || true)
  else
    motivo "STATE.md ausente"
  fi
  head0=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)
  head1=$(git -C "$ROOT" rev-parse HEAD~1 2>/dev/null || true)
  [ -n "$head0" ] || motivo "HEAD ilegível em $ROOT"
  [ "$st" = paused ] || motivo "status: '$(printf '%s' "$st" | cut -c1-60)' (esperado paused — rode reconcilia-docs.sh --pausa)"
  if [ -z "$sh" ]; then motivo "state_head ausente no STATE.md"
  elif [ "$sh" != "$head0" ] && [ "$sh" != "$head1" ]; then
    atras=$(git -C "$ROOT" rev-list --count "$sh..HEAD" 2>/dev/null || echo "?")
    motivo "state_head ${sh:0:12} não é HEAD nem HEAD~1 ($atras commit(s) atrás de ${head0:0:12})"
  fi
  n=$(jq 'length' <<<"$MOTIVOS"); ver=pass; [ "$n" = 0 ] || ver=fail
  gad_json_out confere-etapa "$(jq -cn --arg v "$ver" --arg st "$st" --arg sh "$sh" --arg h "$head0" --argjson m "$MOTIVOS" \
    '{etapa:"pausa", pos_pausa:true, veredito:$v, status:$st, state_head:$sh, head:$h, motivos:$m}')"
  [ "$ver" = pass ] && exit 0 || exit 1
fi

# ── modo pausa: fecho medido da etapa interrompida (Sub-rotina D) ────────────
if [ "$ETAPA" = "pausa" ]; then
  sid="${CLAUDE_CODE_SESSION_ID:-}"
  RL="$PHASE_DIR/$NN-RUN-LOG.jsonl"
  [ -n "$sid" ] && [ -f "$RL" ] || { echo "pausa: sem sessão ou sem run-log — nada a fechar" >&2; exit 0; }
  lnum=$(grep -n "\"sessao\":\"${sid:0:8}\"" "$RL" | grep '"evento":"checkpoint"' | tail -n1 | cut -d: -f1 || true)
  [ -n "$lnum" ] || { echo "pausa: nenhuma janela desta sessão no run-log — nada a fechar"; exit 0; }
  fechada=$(tail -n +"$((lnum+1))" "$RL" | grep "\"sessao\":\"${sid:0:8}\"" | { grep -c '"evento":"\(end\|skip\|stop\)"' || true; })
  if [ "${fechada:-0}" -gt 0 ]; then echo "pausa: janela já fechada — nada a fazer"; exit 0; fi
  et=$(sed -n "${lnum}p" "$RL" | sed -n 's/.*"etapa":"\([^"]*\)".*/\1/p' || true)
  desde=$(sed -n "${lnum}p" "$RL" | sed -n 's/.*"ts":"\([^"]*\)".*/\1/p' || true)
  MEDICAO='{"status":"sem_medicao","reason":"janela sem ts"}'
  if [ -n "$desde" ]; then
    MEDICAO=$(python3 "$GAD_SCRIPTS_DIR/mede-tokens.py" --sessao "$sid" \
      --desde "$desde" --ate "$(date -Is)" --sem-espelho 2>/dev/null || echo '{"status":"sem_medicao","reason":"mede-tokens falhou"}')
  fi
  if [ "$(jq -r '.status' <<<"$MEDICAO")" = ok ]; then
    gad_runlog "$PHASE_DIR" "$NN" end "$et" \
      --tokens-reais "$(jq -r '.total.input_tokens + .total.output_tokens + .total.cache_creation_tokens + (.total.cache_creation_1h_tokens // 0)' <<<"$MEDICAO")" \
      --custo "$(jq -r '.total.custo_usd // 0' <<<"$MEDICAO")" \
      --kv interrompida=true
  else
    gad_runlog "$PHASE_DIR" "$NN" end "$et" --kv interrompida=true \
      --kv medicao="$(jq -r '.reason // "indisponivel"' <<<"$MEDICAO")"
  fi
  gad_json_out confere-etapa "$(jq -cn --arg e "$et" --argjson m "$MEDICAO" \
    '{etapa:"pausa", janela:$e, interrompida:true, medicao:$m}')"
  exit 0
fi

subst() {
  local s="$1"
  s="${s//\{fase\}/$PHASE_DIR}"; s="${s//\{nn\}/$NN}"
  s="${s//\{n\}/$FASE}";         s="${s//\{root\}/$ROOT}"
  printf '%s' "$s"
}

# ── avaliação de um assert (JSON compacto em $1) → seta AV_OK / AV_DET ───────
avalia() {
  local a="$1" tipo padrao regex query esp jqf min max n det arq arquivos
  tipo=$(jq -r '.tipo' <<<"$a")
  min=$(jq -r '.min // 1' <<<"$a"); max=$(jq -r '.max // "null"' <<<"$a")
  case "$tipo" in
    glob)
      padrao=$(subst "$(jq -r '.padrao' <<<"$a")")
      # nullglob não filtra caminho LITERAL (sem metacaractere) — conte só o que existe
      n=0; for arq in $padrao; do [ -e "$arq" ] && n=$((n+1)); done
      det="$n arquivo(s) para $(basename "$padrao")" ;;
    grep)
      padrao=$(subst "$(jq -r '.arquivo' <<<"$a")")
      regex=$(jq -r '.regex' <<<"$a")
      arquivos=(); for arq in $padrao; do [ -f "$arq" ] && arquivos+=("$arq"); done
      n=0
      if [ ${#arquivos[@]} -gt 0 ]; then
        n=$(grep -hEc "$regex" "${arquivos[@]}" 2>/dev/null | awk '{s+=$1} END{print s+0}')
      fi
      det="$n ocorrência(s) de /$regex/ em $(basename "$padrao") (${#arquivos[@]} arquivo(s))" ;;
    sdk)
      query=$(subst "$(jq -r '.query' <<<"$a")")
      jqf=$(jq -r '.jq // "."' <<<"$a"); esp=$(jq -r '.espera' <<<"$a")
      local out val
      out=$(cd "$ROOT" && gsd_run query $query 2>/dev/null) || out=""
      val=$(jq -r "$jqf" <<<"$out" 2>/dev/null || printf '%s' "$out")
      val=$(printf '%s' "$val" | tr -d ' \n\r')
      if [ "$val" = "$esp" ] || printf '%s' "$val" | grep -q "$esp"; then n=1; else n=0; fi
      min=1; max="null"
      det="query \`$query\` → \"$val\" (esperado: $esp)" ;;
    ou)
      local sub subok=0 dets=""
      while IFS= read -r sub; do
        avalia "$sub" && subok=1 && dets="$AV_DET" && break
        dets="$dets${dets:+ | }$AV_DET"
      done < <(jq -c '.de[]' <<<"$a")
      AV_DET="ou: $dets"
      [ "$subok" = 1 ] && return 0 || return 1 ;;
    *)
      AV_DET="tipo de assert desconhecido: $tipo"; return 1 ;;
  esac
  AV_DET="$det"
  [ "$n" -ge "$min" ] || return 1
  [ "$max" = "null" ] || [ "$n" -le "$max" ] || return 1
  return 0
}

# condicao {flag, sinal}: 0=aplica · 1=pula
aplica_condicao() {
  local a="$1" flag sinal
  flag=$(jq -r '.condicao.flag // empty' <<<"$a")
  [ -n "$flag" ] || return 0
  if [ -f "$PONTEIRO" ] && jq -e ".args.$flag" "$PONTEIRO" >/dev/null 2>&1; then
    [ "$(jq -r ".args.$flag" "$PONTEIRO")" = "true" ] && return 0 || return 1
  fi
  sinal=$(subst "$(jq -r '.condicao.sinal // empty' <<<"$a")")
  [ -n "$sinal" ] || return 1
  local sf; for sf in $sinal; do [ -e "$sf" ] && return 0; done
  return 1
}

RES="[]"; FALHAS=0
while IFS= read -r a; do
  id=$(jq -r '.id' <<<"$a"); nivel=$(jq -r '.nivel // "falha"' <<<"$a")
  if ! aplica_condicao "$a"; then
    RES=$(jq -c --arg id "$id" '. + [{id:$id, resultado:"pulado", detalhe:"condição da flag não se aplica"}]' <<<"$RES")
    continue
  fi
  if avalia "$a"; then
    RES=$(jq -c --arg id "$id" --arg d "$AV_DET" '. + [{id:$id, resultado:"ok", detalhe:$d}]' <<<"$RES")
  else
    RES=$(jq -c --arg id "$id" --arg d "$AV_DET" --arg nv "$nivel" \
      '. + [{id:$id, resultado:(if $nv=="falha" then "FALHA" else "aviso" end), detalhe:$d}]' <<<"$RES")
    [ "$nivel" = "falha" ] && FALHAS=$((FALHAS+1))
  fi
done < <(jq -c '.asserts[]?' "$MANIFEST")

# ── extrações específicas da etapa (insumo de julgamento da camada 0) ────────
EXTRAI="{}"
while IFS= read -r x; do
  xid=$(jq -r '.id' <<<"$x"); xtipo=$(jq -r '.tipo' <<<"$x")
  case "$xtipo" in
    grep-arquivos)
      padrao=$(subst "$(jq -r '.padrao' <<<"$x")")
      regex=$(jq -r '.regex' <<<"$x")
      lista="[]"
      for f in $padrao; do
        grep -qE "$regex" "$f" 2>/dev/null \
          && lista=$(jq -c --arg f "$(basename "$f")" '. + [$f]' <<<"$lista")
      done
      EXTRAI=$(jq -c --arg id "$xid" --argjson l "$lista" '. + {($id): $l}' <<<"$EXTRAI") ;;
    grep-valor)
      # primeiro match inteiro do regex — dado de roteamento (a camada 0 nunca relê o
      # relatório do gate; vereditos são strings/números canônicos, 4.A)
      padrao=$(subst "$(jq -r '.arquivo' <<<"$x")")
      regex=$(jq -r '.regex' <<<"$x")
      val=""
      for f in $padrao; do
        [ -f "$f" ] || continue
        val=$(grep -hoE "$regex" "$f" 2>/dev/null | head -1) && [ -n "$val" ] && break
      done
      EXTRAI=$(jq -c --arg id "$xid" --arg v "$val" '. + {($id): (if $v=="" then null else $v end)}' <<<"$EXTRAI") ;;
    json)
      # P13/P19: espelho JSON gravado por outro script (ex.: `.planning/.gad/last-plan-gate.json`
      # do plan shape gate §13a-bis), filtrado por `jq`. Ausente → null; com `"ausente":
      # "incidente"` grava também um `incidente` no run-log (fora do --dry-run): o gate do
      # fork sempre grava o espelho, então arquivo ausente = o gate não rodou.
      arq=$(subst "$(jq -r '.arquivo' <<<"$x")"); jqf=$(jq -r '.jq // "."' <<<"$x")
      val=null
      if [ -f "$arq" ]; then
        val=$(jq -c "$jqf" "$arq" 2>/dev/null) || val=null; [ -n "$val" ] || val=null
      elif [ "$(jq -r '.ausente // ""' <<<"$x")" = incidente ] && [ "$DRY" = 0 ]; then
        gad_runlog "$PHASE_DIR" "$NN" incidente "$RUNLOG_ETAPA" --kv origem=confere-etapa.sh \
          --kv detalhe="$xid: $(basename "$arq") ausente — o script que o grava não rodou"
      fi
      EXTRAI=$(jq -c --arg id "$xid" --argjson v "$val" '. + {($id): $v}' <<<"$EXTRAI") ;;
  esac
done < <(jq -c '.extrai[]?' "$MANIFEST")

# ── etapa 5 (UAT): pacote de mecanização 5.E — reconciliação, evidência, gaps,
# predicado nativo, segredos; marcadores promovidos SÓ por este script (5.C) ──
if [ "$ETAPA" = "5" ]; then
  UAT="$PHASE_DIR/$NN-UAT.md"
  if [ -f "$UAT" ]; then
    conta() { { grep -cE "$1" "$UAT" || true; } | head -1; }
    n_pass=$(conta 'result: *pass'); n_issue=$(conta 'result: *issue')
    n_pend=$(conta 'result: *(\[pending\]|blocked|pending)'); n_assumed=$(conta 'result: *assumed')
    n_probes=$(conta '🔍')
    n_evid=0; for ev in "$PHASE_DIR"/uat-evidencia/*; do [ -f "$ev" ] && n_evid=$((n_evid+1)); done
    EXTRAI=$(jq -c --argjson p "$n_pass" --argjson i "$n_issue" --argjson pe "$n_pend" \
      --argjson a "$n_assumed" --argjson pr "$n_probes" --argjson ev "$n_evid" \
      '. + {reconciliacao:{pass:$p, issue:$i, pending:$pe, assumed:$a, probes:$pr, evidencias:$ev}}' <<<"$EXTRAI")
    # 2.7.0: observação pós-ship mora em NN-POS-SHIP.md (o predicado nativo só aceita
    # pass) — contada à parte, NUNCA somada a pending; candidato que o pos-ship.py
    # recusou segue no UAT.md como balde 3
    PS=$(python3 "$GAD_SCRIPTS_DIR/pos-ship.py" lista "$PHASE_DIR" "$NN" 2>/dev/null || echo '{"total":0,"bloqueiam_proxima":0}')
    EXTRAI=$(jq -c --argjson ps "$PS" '. + {pos_ship:{total:$ps.total, bloqueiam_proxima:$ps.bloqueiam_proxima}}' <<<"$EXTRAI")
    # 5.E-b: evidência dura — arquivos >= cenários GUI de balde 1+2 (F19-ox: pasta
    # VAZIA; F21-ins: path inexistente). Fase sem browser (só cli/logic/judgment/api)
    # não gera prova visual — esperado 0.
    n_nao_gui=$(conta 'tipo: *(cli|logic|judgment|api)')
    esperado=$((n_pass + n_issue - n_nao_gui)); [ "$esperado" -lt 0 ] && esperado=0
    grep -qE 'localhost|gsd-browser|browser_' "$UAT" || esperado=0
    if [ "$esperado" -gt 0 ] && [ "$n_evid" -lt "$esperado" ]; then
      RES=$(jq -c --arg d "evidências ($n_evid) < cenários pass+issue ($esperado) — 5.E-b" \
        '. + [{id:"evidencia_por_cenario", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    fi
    # 5.E-c: lint do gap-YAML — todo issue precisa de entrada em ## Gaps (alimenta o --gaps)
    n_gaps=$(conta '^ *- truth:')
    if [ "$n_issue" -gt 0 ] && [ "$n_gaps" -lt "$n_issue" ]; then
      RES=$(jq -c --arg d "issues=$n_issue mas só $n_gaps gap-YAML em ## Gaps" \
        '. + [{id:"gap_yaml", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    fi
    # 5.E-d: predicado nativo (o freio que desmentiu a camada 0 na F21-ins)
    UP=$( (cd "$ROOT" && gsd_run phase uat-passed "$FASE" 2>/dev/null) | tr -d ' \n\r' || true )
    EXTRAI=$(jq -c --arg u "${UP:-indisponivel}" '. + {uat_passed_nativo:$u}' <<<"$EXTRAI")
    # 5.E-g: varredura de SEGREDOS (restrita, padrão-gitleaks — NUNCA PII genérica)
    VAZOU=$( { grep -rhIoE 'AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36,}|sk-[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY|SUPABASE_SERVICE_ROLE_KEY *[=:] *[A-Za-z0-9._-]{20,}|eyJ[A-Za-z0-9_-]{20,}\.eyJ' \
        "$UAT" "$PHASE_DIR/uat-evidencia" 2>/dev/null || true; } | head -3 )
    if [ -n "$VAZOU" ]; then
      RES=$(jq -c --arg d "padrão de segredo no artefato/evidência: $(head -c 60 <<<"$VAZOU")…" \
        '. + [{id:"segredo_no_artefato", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    fi
    # ── F4 RLR · FM-01UAT · FJ-01UAT · FJ-02UAT: o que o `pass` conduzido tem de ter ──
    # Um leitor só do NN-UAT.md (uat-fiscal.py) — dois parsers do mesmo arquivo é como o
    # fiscal do 4.1 acabou dando veredito da iteração errada (FM-04GAT).
    UATF=$(python3 "$GAD_SCRIPTS_DIR/uat-fiscal.py" "$UAT" "$PHASE_DIR" 2>/dev/null || echo '{}')
    jq -e . >/dev/null 2>&1 <<<"$UATF" || UATF='{}'
    n_sev=$(jq '(.pass_sem_evidencia//[])|length' <<<"$UATF")
    n_slc=$(jq '(.logic_sem_comando//[])|length' <<<"$UATF")
    n_ssd=$(jq '(.pass_sem_sondagem//[])|length' <<<"$UATF")
    if [ "${n_sev:-0}" -gt 0 ]; then
      RES=$(jq -c --arg d "AVISO: $n_sev cenário(s) conduzido(s) em pass sem arquivo de evidência (exceção declarável na nota: «ação sem saída»): $(jq -r '.pass_sem_evidencia|join(" · ")' <<<"$UATF" | cut -c1-300)" \
        '. + [{id:"uat_pass_sem_evidencia", resultado:"AVISO", detalhe:$d}]' <<<"$RES")
    fi
    if [ "${n_slc:-0}" -gt 0 ]; then
      RES=$(jq -c --arg d "AVISO: $n_slc cenário(s) type: logic em pass cuja evidência não tem nenhuma linha '\$ ' — pass por leitura de código: $(jq -r '.logic_sem_comando|join(" · ")' <<<"$UATF" | cut -c1-300)" \
        '. + [{id:"uat_logic_sem_comando", resultado:"AVISO", detalhe:$d}]' <<<"$RES")
    fi
    if [ "${n_ssd:-0}" -gt 0 ]; then
      # AVISO NESTA RELEASE (decisão do dono, 21/09 — mesmo tratamento do `incidente_tardio`):
      # volta a FALHA dura depois de UMA fase real rodar com o `uat-playbook.md` novo (C5),
      # que é quem ensina a escotilha. A saída de escape é declarada no próprio cenário —
      # «🔍 não se aplica: <motivo>» —, não é o fiscal que dispensa.
      RES=$(jq -c --arg d "AVISO: $n_ssd cenário(s) conduzido(s) em pass sem linha 🔍 (sondagem adversarial) — devolva ao condutor; aceita «🔍 não se aplica: <motivo>»: $(jq -r '.pass_sem_sondagem|join(" · ")' <<<"$UATF" | cut -c1-300)" \
        '. + [{id:"uat_pass_sem_sondagem", resultado:"AVISO", detalhe:$d}]' <<<"$RES")
    fi
    EXTRAI=$(jq -c --argjson u "$UATF" '. + {uat_fiscal: ($u|del(.summary_novo))}' <<<"$EXTRAI")

    # 5.C: promoção dos marcadores — escritor único; modelo reporta, ESTE script promove
    if [ "$FALHAS" = 0 ] && [ "$DRY" = 0 ]; then
      grep -q '^pre_uat: generated' "$UAT" && sed -i 's/^pre_uat: generated/pre_uat: executed/' "$UAT"
      if [ "$FIXCYCLE" = 1 ] && ! grep -q '^pre_uat_fix_cycle:' "$UAT"; then
        sed -i '/^pre_uat: executed/a pre_uat_fix_cycle: done' "$UAT"
      fi
      # re-UAT do balde 3 (5.6): 1× por fase, mesmo desenho do fix cycle
      if [ "$REUAT" = 1 ] && ! grep -q '^pre_uat_reuat:' "$UAT"; then
        sed -i '/^pre_uat: executed/a pre_uat_reuat: done' "$UAT"
      fi
      # FM-02UAT: o bloco `## Summary` é RECALCULADO e escrito por este script, o
      # `status` é promovido e o bloco `## Current Test` (rascunho do condutor) some —
      # TUDO ANTES do commit e do recibo. Medido na F4 RLR: no commit que o recibo do
      # fiscal aponta o cabeçalho ainda dizia `testing` e o resumo dizia 33/20/13 com 29
      # `pass` no corpo; o resumo só foi corrigido 6,5 min depois, já no encerramento.
      # O próprio uat-fiscal.py promove o status (mesma condição de antes, mais
      # `blocked`), é idempotente e não toca o arquivo se o conteúdo não muda.
      ESCRITO=$(python3 "$GAD_SCRIPTS_DIR/uat-fiscal.py" "$UAT" "$PHASE_DIR" --escrever 2>/dev/null || echo '{}')
      EXTRAI=$(jq -c --argjson e "$(jq -c '{escrito:(.escrito//[]), summary:(.summary_novo//"")}' <<<"${ESCRITO:-\{\}}" 2>/dev/null || echo '{}')" \
        '. + {uat_reconciliado: $e}' <<<"$EXTRAI")
    fi
  fi
fi

# ── etapa 6: self-check mecânico (6.A/6.5) ───────────────────────────────────
if [ "$ETAPA" = "6" ]; then
  n_plans=0; n_sums=0
  for f in "$PHASE_DIR"/*-PLAN.md;    do [ -f "$f" ] && n_plans=$((n_plans+1)); done
  for f in "$PHASE_DIR"/*-SUMMARY.md; do [ -f "$f" ] && n_sums=$((n_sums+1)); done
  if [ "$n_plans" -gt "$n_sums" ]; then
    RES=$(jq -c --arg d "sobrou plano sem SUMMARY ($n_plans planos × $n_sums summaries) — ação humana travou onda?" \
      '. + [{id:"plan_x_summary", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
  fi
  # anti-placeholder de timestamp (fabricação em série: F20/F22)
  PLACE=$( { grep -rlE '<ts>|YYYY-MM|0000-00-00|\[timestamp\]' \
      "$PHASE_DIR/$NN-RESUMO-EXECUTIVO.md" "$PHASE_DIR/$NN-UAT.md" \
      "$PHASE_DIR/$NN-LEARNINGS.md" 2>/dev/null || true; } | head -2 )
  if [ -n "$PLACE" ]; then
    RES=$(jq -c --arg d "placeholder de timestamp em: $(basename $PLACE | tr '\n' ' ')" \
      '. + [{id:"ts_placeholder", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
  fi
  # v2.1.9 (F24.3 falha 5): AC marcado PARCIAL/bloqueador em algum SUMMARY não pode estar
  # `passed` no VERIFICATION — a declaração precedeu a prova em 47 min na F24.3
  VER="$PHASE_DIR/$NN-VERIFICATION.md"
  if [ -f "$VER" ] && grep -qE '^status: *passed' "$VER"; then
    # linha de aceite/critério com a marca PARCIAL/bloqueador (F24.3-07-SUMMARY:225 —
    # "item 4 (suíte completa) PARCIAL … bloqueador"); reporta a linha, não um id inferido
    PARC=$( { grep -hE '(\b(AC|REQ|SC)-[0-9]+|[Cc]rit[ée]rio|[Aa]ceite|su[íi]te completa).*(PARCIAL|bloqueador)' \
              "$PHASE_DIR"/*-SUMMARY.md 2>/dev/null || true; } | head -1 | tr -d '"' | cut -c1-100)
    if [ -n "$PARC" ]; then
      RES=$(jq -c --arg d "VERIFICATION passed mas um SUMMARY marca PARCIAL/bloqueador: «$PARC» — meça o AC antes de promover" \
        '. + [{id:"ac_parcial_x_verification", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    fi
  fi
  # v2.1.9 (F24.3 falha 3 / 32e — 3ª reincidência): espelhos de estado reconciliados?
  # reconcilia-docs.sh roda antes desta cancela; aqui só se confere que ele agiu.
  # B2 (31/08): esta cancela usava o MESMO grep literal do reconcilia-docs.sh — e por isso
  # herdava o mesmo ponto cego. Quando o `status` é uma frase em vez do token (formato real
  # no alencarOS: `status: "Fase 13 … PAUSADA…"`), `^status: *executing` não bate: o
  # reconciliador não escreve e a cancela dá verde. Agora os campos são lidos como VALOR e
  # o formato ilegível reprova por si (assert `state_formato`).
  # Caminho escolhido: checagem PRÓPRIA, e não chamada ao reconcilia-docs.sh em modo
  # verificação — o `--dry-run` dele NÃO é livre de efeito colateral (o `gad_json_out` da
  # linha final grava `.planning/.gad/last-reconcilia-docs.json` fora da guarda do DRY, e
  # medimos isso no grupo-inspired). Uma cancela não pode mutar estado para julgar.
  ST="$ROOT/.planning/STATE.md"
  if [ -f "$ST" ]; then
    st_val=$(grep -m1 -E '^status: ' "$ST" | sed -e 's/^status:[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/\r$//')
    cp_val=$(grep -m1 -E '^current_phase: ' "$ST" | sed -e 's/^current_phase:[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/\r$//')
    if [ "$cp_val" = "$FASE" ]; then
      if [ "$st_val" = executing ]; then
        RES=$(jq -c --arg d "STATE.md ainda diz status: executing para a fase $FASE — rode reconcilia-docs.sh" \
          '. + [{id:"state_reconciliado", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
      elif ! printf '%s' "$st_val" | grep -qE '^[A-Za-z_][A-Za-z0-9_-]*$'; then
        RES=$(jq -c --arg d "FORMATO-INESPERADO: o status do STATE.md da fase $FASE não é um token reconhecível ('$(printf '%s' "$st_val" | cut -c1-80)') — nem esta cancela nem o reconcilia-docs.sh conseguem julgá-lo; conserte à mão" \
          '. + [{id:"state_formato", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
      fi
    fi
  fi
  # varredura anti-órfã da TaskList (S.C): sinal p/ camada 0 reconciliar
  EXTRAI=$(jq -c --argjson p "$n_plans" --argjson s "$n_sums" \
    '. + {plans:$p, summaries:$s}' <<<"$EXTRAI")
fi

# ── etapa 3 (construção): paralelismo observado × planejado ──────────────────
# O mandato de paralelismo do prompts/execute.md só era imponível por confissão da camada
# 1. Aqui a cancela mede pelo run-log: para cada onda planejada com >=2 planos, quantos
# executores daquela onda estiveram abertos ao mesmo tempo (despacho sem retorno entre
# eles). Só extrai — a régua da /audit-gad julga depois. O que reprova é uma coisa só:
# `workflow.use_worktrees` ter virado false entre o pré-despacho e o fecho (a "chave de
# emergência" que serializa a fase inteira sem ninguém decidir).
if [ "$ETAPA" = "3" ]; then
  RL3="$PHASE_DIR/$NN-RUN-LOG.jsonl"
  IDX3=$(cd "$ROOT" && gsd_run phase-plan-index "$FASE" --raw 2>/dev/null || echo '{}')
  jq -e . >/dev/null 2>&1 <<<"$IDX3" || IDX3='{}'
  # Regras que o arquivo real da F24.4 impôs ao leitor: a `descricao` do despacho veio em
  # três grafias ("Execute plan 01 of phase 24.4", "… of phase INS-24.4", "Execute plan
  # 24.4-08") — a chave comum é o sufixo numérico do id; um `retorno` fecha TODOS os
  # despachos abertos daquele plano, porque os despachos negados pelo sentinel ficam sem
  # retorno e contariam como abertos para sempre; `serializacao_observada` só quando >=2
  # planos da onda foram despachados e nunca dois estiveram abertos juntos.
  PAR_OBS=$(IDX_JSON="$IDX3" python3 - "$RL3" 2>/dev/null <<'PYOBS' || echo '{"paralelismo_observado":{},"serializacao_observada":[],"largura":{"janela_executores_min":0,"minutos_em_largura_1":0,"pct_largura_1":null}}'
import json
import os
import re
import sys
from datetime import datetime


def main() -> int:
    idx = json.loads(os.environ.get("IDX_JSON") or "{}")
    waves = {w: list(ids) for w, ids in (idx.get("waves") or {}).items() if len(ids) >= 2}
    plan_of = {}
    for ids in waves.values():
        for pid in ids:
            plan_of[pid] = pid
            plan_of[pid.rsplit("-", 1)[-1]] = pid
    wave_of = {pid: w for w, ids in waves.items() for pid in ids}

    evs = []
    try:
        with open(sys.argv[1], encoding="utf-8") as fh:
            for ln in fh:
                try:
                    e = json.loads(ln)
                except Exception:
                    continue
                if e.get("evento") not in ("despacho", "retorno") or e.get("agente") != "gsd-executor":
                    continue
                m = re.search(r"plan\s+([0-9][0-9.]*-)?([0-9]+)", e.get("descricao") or "", re.I)
                if not m:
                    continue
                num = m.group(2)
                pid = (plan_of.get((m.group(1) or "") + num) or plan_of.get(num.zfill(2))
                       or plan_of.get(num))
                if not pid:
                    continue
                try:
                    ts = datetime.fromisoformat(e.get("ts", "")).timestamp()
                except Exception:
                    ts = 0.0
                # v2.5.4 (45e): só `retorno` com fim_real:true fecha um despacho — o retorno do
                # PostToolUse é o da CHAMADA (Agent assíncrono) e chega 2–5 s após o despacho.
                if e["evento"] == "retorno" and e.get("fim_real") is not True:
                    evs.append((ts, e.get("seq", 0), "retorno_chamada", pid))
                    continue
                evs.append((ts, e.get("seq", 0), e["evento"], pid))
    except (FileNotFoundError, IndexError):
        pass
    evs.sort()

    aberto = {}
    res = {w: {"planejados": len(ids), "despachados": 0, "simultaneos_max": 0,
               "janela_despachos_s": None, "duracao_onda_s": None, "plano_mais_lento_s": None}
           for w, ids in waves.items()}
    primeiro, ultimo, ultimo_retorno, inicio_plano = {}, {}, {}, {}
    vistos = {w: set() for w in waves}
    sem_fim = {w: 0 for w in waves}
    for ts, _seq, ev, pid in evs:
        w = wave_of[pid]
        if ev == "retorno_chamada":
            sem_fim[w] += 1
            continue
        if ev == "despacho":
            aberto[pid] = aberto.get(pid, 0) + 1
            vistos[w].add(pid)
            primeiro.setdefault(w, ts)
            ultimo[w] = ts
            inicio_plano[pid] = ts   # o último despacho do plano é o que o retorno fecha
            sim = sum(1 for p in waves[w] if aberto.get(p, 0) > 0)
            res[w]["simultaneos_max"] = max(res[w]["simultaneos_max"], sim)
        else:
            aberto[pid] = 0
            if ts and inicio_plano.get(pid):
                ultimo_retorno[w] = max(ultimo_retorno.get(w, 0), ts)
                dur = int(ts - inicio_plano[pid])
                res[w]["plano_mais_lento_s"] = max(res[w]["plano_mais_lento_s"] or 0, dur)
    for w in waves:
        res[w]["despachados"] = len(vistos[w])
        # despacho ainda aberto no fecho = sem retorno real (hook SubagentStop ausente, ou
        # retorno só da chamada): a onda não é medível — não se conclui serialização dela
        abertos = [p for p in waves[w] if aberto.get(p, 0) > 0]
        if abertos or (vistos[w] and sem_fim[w] and not ultimo_retorno.get(w)):
            res[w]["nao_medido"] = (f"{len(abertos) or sem_fim[w]} despacho(s) sem retorno real "
                                    "(fim_real) — hook SubagentStop não registrado ou executor aberto")
            res[w]["simultaneos_max"] = None
        if w in primeiro and primeiro[w] and ultimo.get(w):
            res[w]["janela_despachos_s"] = int(ultimo[w] - primeiro[w])
        # C3 (plano 4): tempo da onda (1º despacho → último retorno) × plano mais lento — próximo
        # de 1 na onda larga é o sinal de paralelismo real
        if w in primeiro and primeiro[w] and ultimo_retorno.get(w):
            res[w]["duracao_onda_s"] = int(ultimo_retorno[w] - primeiro[w])
    ser = [w for w, r in res.items()
           if r["despachados"] >= 2 and r["simultaneos_max"] is not None and r["simultaneos_max"] <= 1]

    # (47f, régua C3 da tarefa 43) minutos em largura 1 na fase INTEIRA, pelos pares
    # despacho/retorno-real. Passe próprio, sem o filtro de ondas com 2+ planos do bloco acima:
    # uma onda de um plano só é justamente largura 1, e é o que se quer medir.
    # Advisory: nunca reprova — é régua, não cota.
    jan = []
    abertos_ts = {}
    try:
        with open(sys.argv[1], encoding="utf-8") as fh:
            for ln in fh:
                try:
                    e = json.loads(ln)
                except Exception:
                    continue
                if e.get("agente") != "gsd-executor":
                    continue
                d = e.get("descricao") or ""
                try:
                    ts = datetime.fromisoformat(e.get("ts", "")).timestamp()
                except Exception:
                    continue
                if e.get("evento") == "despacho":
                    abertos_ts.setdefault(d, ts)
                elif e.get("evento") == "retorno" and e.get("fim_real") is True and abertos_ts.get(d):
                    jan.append((abertos_ts.pop(d), ts))
    except (FileNotFoundError, IndexError):
        pass
    marcos = sorted({t for p in jan for t in p})
    l1 = tot = 0.0
    for a, b in zip(marcos, marcos[1:]):
        n = sum(1 for t0, t1 in jan if t0 <= a < t1)
        tot += b - a
        if n == 1:
            l1 += b - a
    largura = {"janela_executores_min": int(tot / 60), "minutos_em_largura_1": int(l1 / 60),
               "pct_largura_1": int(100 * l1 / tot) if tot else None}

    print(json.dumps({"paralelismo_observado": res, "serializacao_observada": ser,
                      "largura": largura}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYOBS
  )
  jq -e . >/dev/null 2>&1 <<<"$PAR_OBS" || PAR_OBS='{"paralelismo_observado":{},"serializacao_observada":[],"largura":{"janela_executores_min":0,"minutos_em_largura_1":0,"pct_largura_1":null}}'
  # C2 (plano 4, 05/09): onda planejada com 2+ planos que rodou em série é incidente no run-log,
  # um por onda, com a janela entre os despachos. Continua não reprovando — serializar não é
  # erro do executor, é fato a registrar; na F24.4 as ondas 1 e 6 serializaram (11 h entre os
  # despachos da 6) sem que nenhum retorno ou evento dissesse isso.
  if [ "$DRY" = 0 ]; then
    while IFS= read -r w; do
      [ -n "$w" ] || continue
      jan=$(jq -r --arg w "$w" '.paralelismo_observado[$w].janela_despachos_s // "?"' <<<"$PAR_OBS")
      gad_runlog "$PHASE_DIR" "$NN" incidente "$RUNLOG_ETAPA" --kv origem=confere-etapa.sh \
        --kv detalhe="onda $w serializada: $(jq -r --arg w "$w" '.paralelismo_observado[$w].despachados' <<<"$PAR_OBS") planos despachados, nunca 2 abertos juntos (janela entre despachos ${jan}s)"
    done < <(jq -r '.serializacao_observada[]' <<<"$PAR_OBS")
  fi
  # use_worktrees do início (espelho do pre-despacho.sh 3) × do fecho
  PRE3="$ROOT/.planning/.gad/last-pre-despacho-3.json"
  uw0=null; uw1=null
  [ -f "$PRE3" ] && uw0=$(jq -c '.use_worktrees // null' "$PRE3" 2>/dev/null || echo null)
  uw1=$(cd "$ROOT" && gsd_run query config-get workflow.use_worktrees --raw 2>/dev/null | tr -d ' \n\r' || true)
  case "$uw1" in true|false) ;; *) uw1=null ;; esac
  if [ "$uw0" = true ] && [ "$uw1" = false ]; then
    RES=$(jq -c '. + [{id:"use_worktrees_alterado", resultado:"FALHA", detalhe:"workflow.use_worktrees era true no pré-despacho da etapa 3 e está false no fecho — a fase foi serializada por mudança de config durante a rodada, sem decisão do dono"}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    [ "$DRY" = 1 ] || gad_runlog "$PHASE_DIR" "$NN" incidente "$RUNLOG_ETAPA" \
      --kv origem=confere-etapa.sh --kv detalhe="use_worktrees true→false durante a etapa 3"
  fi
  # C3 (plano 4): lançamentos de suíte pelo roda-suite.sh nesta fase — lidos do estado em
  # `<git-common-dir>/gad-suite/<tag>/` (comum aos worktrees): quantos lançamentos, quantos
  # relançamentos recusados pelo lock (rc 3) e o tempo total (iniciado → mtime do rc).
  COMMON3=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  SUITE=$(GAD_SUITE_DIR="${COMMON3:+$COMMON3/gad-suite}" GAD_RL="$RL3" python3 - 2>/dev/null <<'PYSUITE' || echo '{"lancamentos":0,"recusados":0,"tempo_total_s":0,"tags":[],"fora_da_fase":[]}'
import glob, json, os
from datetime import datetime
d = os.environ.get("GAD_SUITE_DIR") or ""


def ts(s):
    try:
        return datetime.fromisoformat(s.strip()).timestamp()
    except Exception:
        return None


# t0 = 1º despacho de executor no run-log desta etapa (mesmo critério do bloco da suíte final,
# 45f/F24.5: sem ele o contador somava o `gate-onda-7` simulado de 05/09, de outra fase — o
# diretório gad-suite/ é comum aos worktrees e não é apagado entre fases).
t0 = 0.0
t0chk = None
try:
    for ln in open(os.environ.get("GAD_RL") or "", encoding="utf-8", errors="replace"):
        try:
            e = json.loads(ln)
        except Exception:
            continue
        if e.get("evento") == "checkpoint" and str(e.get("etapa", "")).startswith("3") and t0chk is None:
            t0chk = ts(e.get("ts", "")) or None
        if e.get("evento") == "despacho" and e.get("agente") == "gsd-executor":
            t0 = ts(e.get("ts", "")) or 0.0
            break
except OSError:
    pass
if not t0 and t0chk:
    t0 = t0chk

lanc = rec = tempo = 0
tags = []
fora_da_fase = []
for st in sorted(glob.glob(os.path.join(d, "*"))) if d and os.path.isdir(d) else []:
    if not os.path.isfile(os.path.join(st, "cmd")):
        continue
    try:
        ini = ts(open(os.path.join(st, "iniciado")).read())
    except OSError:
        ini = None
    if t0 and (ini is None or ini < t0):
        fora_da_fase.append(os.path.basename(st))
        continue
    lanc += 1
    tags.append(os.path.basename(st))
    try:
        rec += sum(1 for l in open(os.path.join(st, "recusados")) if l.strip())
    except OSError:
        pass
    try:
        fim = os.path.getmtime(os.path.join(st, "rc"))
        tempo += max(0, int(fim - (ini or 0)))
    except (OSError, ValueError):
        pass
print(json.dumps({"lancamentos": lanc, "recusados": rec, "tempo_total_s": tempo,
                  "tags": tags, "fora_da_fase": fora_da_fase}))
PYSUITE
  )
  jq -e . >/dev/null 2>&1 <<<"$SUITE" || SUITE='{"lancamentos":0,"recusados":0,"tempo_total_s":0,"tags":[],"fora_da_fase":[]}'
  EXTRAI=$(jq -c --argjson po "$PAR_OBS" --argjson a "$uw0" --argjson b "$uw1" --argjson su "$SUITE" \
    '. + $po + {use_worktrees:{inicio:$a, fecho:$b}, suite:$su}' <<<"$EXTRAI")

  # ── suíte final (45n, v2.5.4 — F24.5): a última suíte COMPLETA da etapa precisa estar verde
  # e sem commit de código depois dela; a última onda precisa de gate próprio quando o projeto
  # usa `roda-suite.sh --gate-onda`. Só se aplica a projeto instrumentado (há lançamento do
  # roda-suite.sh nesta etapa ou o test_command cita roda-suite.sh). O dono pode aceitar suíte
  # vermelha por `suite-ressalva.sh` (frontmatter do VERIFICATION) — vira incidente, não falha.
  TESTCMD=$(jq -r '.workflow.test_command // ""' "$ROOT/.planning/config.json" 2>/dev/null || true)
  SF=$(GAD_SUITE_DIR="${COMMON3:+$COMMON3/gad-suite}" GAD_ROOT="$ROOT" GAD_RL="$RL3" IDX_JSON="$IDX3" \
       GAD_VER="$PHASE_DIR/$NN-VERIFICATION.md" GAD_TESTCMD="$TESTCMD" python3 - 2>/dev/null <<'PYSF' || echo '{"aplica":false}'
import glob, json, os, re, subprocess
from datetime import datetime
d = os.environ.get("GAD_SUITE_DIR") or ""; root = os.environ["GAD_ROOT"]
testcmd = os.environ.get("GAD_TESTCMD") or ""; ver = os.environ.get("GAD_VER") or ""
idx = json.loads(os.environ.get("IDX_JSON") or "{}")

def ts(s):
    try: return datetime.fromisoformat(s.strip()).timestamp()
    except Exception: return None

# t0 = 1º despacho de executor no run-log da etapa (fallback: 1º checkpoint "3 construcao"; senão 0)
t0 = 0.0; t0chk = None
try:
    for ln in open(os.environ.get("GAD_RL") or "", encoding="utf-8", errors="replace"):
        try: e = json.loads(ln)
        except Exception: continue
        if e.get("evento") == "checkpoint" and str(e.get("etapa", "")).startswith("3") and t0chk is None:
            t0chk = ts(e.get("ts", "")) or None
        if e.get("evento") == "despacho" and e.get("agente") == "gsd-executor":
            t0 = ts(e.get("ts", "")) or 0.0; break
except OSError:
    pass
if not t0 and t0chk: t0 = t0chk

tags = []
for st in sorted(glob.glob(os.path.join(d, "*"))) if d and os.path.isdir(d) else []:
    if not os.path.isfile(os.path.join(st, "cmd")): continue
    try: ini = ts(open(os.path.join(st, "iniciado")).read())
    except OSError: ini = None
    rc = None
    try:
        s = open(os.path.join(st, "rc")).read().strip(); rc = int(s) if s else None
    except (OSError, ValueError): rc = None
    tags.append({"tag": os.path.basename(st), "iniciado": ini, "rc": rc})
na_etapa = [t for t in tags if t["iniciado"] is not None and t["iniciado"] >= t0]
aplica = bool(na_etapa) or ("roda-suite.sh" in testcmd)
out = {"aplica": aplica, "t0": t0, "codigos": [], "ultima_completa": None, "commits_pos_suite": []}
if not aplica:
    print(json.dumps(out)); raise SystemExit
completas = [t for t in na_etapa if not t["tag"].startswith("gate-onda-")]
ressalva = False
try:
    fm = open(ver, encoding="utf-8").read().split("\n---", 2)[0]
    ressalva = bool(re.search(r"^suite_final:\s*vermelha", fm, re.M)) and bool(re.search(r"^suite_ressalva:\s*\S", fm, re.M))
except OSError:
    pass
out["ressalva"] = ressalva
if not completas:
    out["codigos"].append("SUITE-COMPLETA-AUSENTE")
else:
    u = max(completas, key=lambda t: t["iniciado"]); out["ultima_completa"] = u
    if u["rc"] is None:
        out["codigos"].append("SUITE-EM-CURSO")
    elif u["rc"] != 0:
        out["codigos"].append("SUITE-FINAL-VERMELHA-COM-RESSALVA" if ressalva else "SUITE-FINAL-VERMELHA")
    else:
        since = datetime.fromtimestamp(u["iniciado"]).isoformat()
        try:
            r = subprocess.run(["git", "-C", root, "log", f"--since={since}", "--name-only", "--format=%h %s"],
                               capture_output=True, text=True, timeout=10)
            # DESVIO (bug literal do plano): `--name-only` põe a linha em branco logo
            # APÓS o cabeçalho (antes da lista de arquivos), não depois dela — tratar
            # "" como gatilho de flush (igual a um novo cabeçalho) zera `cur` antes de
            # qualquer arquivo ser visto e SUITE-NAO-RELANCADA nunca dispara. Linha em
            # branco agora é no-op; o flush final roda depois do laço.
            shas = []; cur = None; toca = False
            for ln in r.stdout.splitlines():
                if re.match(r"^[0-9a-f]{7,} ", ln):
                    if cur and toca: shas.append(cur)
                    cur = ln[:60]; toca = False
                elif ln.strip() and not ln.startswith(".planning/"):
                    toca = True
            if cur and toca: shas.append(cur)
            out["commits_pos_suite"] = shas
            if shas: out["codigos"].append("SUITE-NAO-RELANCADA")
        except Exception:
            pass
# última onda com gate próprio (só quando o test_command é o --gate-onda)
if "--gate-onda" in testcmd:
    waves = [int(w) for w in (idx.get("waves") or {}).keys() if str(w).isdigit()]
    if waves:
        W = max(waves)
        if not any(t["tag"] == f"gate-onda-{W}" for t in na_etapa):
            out["codigos"].append("ULTIMA-ONDA-SEM-GATE"); out["ultima_onda"] = W
print(json.dumps(out))
PYSF
  )
  jq -e . >/dev/null 2>&1 <<<"$SF" || SF='{"aplica":false}'
  EXTRAI=$(jq -c --argjson sf "$SF" '. + {suite_final:$sf}' <<<"$EXTRAI")
  if [ "$(jq -r '.aplica' <<<"$SF")" = true ]; then
    while IFS= read -r cod; do
      [ -n "$cod" ] || continue
      det=$(jq -r --arg c "$cod" '
        (.ultima_completa // {}) as $u |
        if $c=="SUITE-FINAL-VERMELHA" then "última suíte completa (\($u.tag)) terminou rc=\($u.rc): conserte e RELANCE (roda-suite.sh --lancar --tag suite-final-2 --cmd …) até rc=0, ou o dono aceita por suite-ressalva.sh"
        elif $c=="SUITE-NAO-RELANCADA" then "commit de código depois da última suíte verde (\($u.tag)): \(.commits_pos_suite|join("; ")) — relance a suíte completa"
        elif $c=="SUITE-EM-CURSO" then "suíte \($u.tag) ainda sem rc: espere (roda-suite.sh --esperar --tag \($u.tag)) antes do fecho"
        elif $c=="SUITE-COMPLETA-AUSENTE" then "nenhuma suíte completa lançada nesta etapa (só gates de onda): rode a suíte inteira uma vez depois da última onda"
        elif $c=="ULTIMA-ONDA-SEM-GATE" then "a última onda (\(.ultima_onda)) não teve gate-onda-\(.ultima_onda): a suíte completa não substitui o gate da onda (F24.5)"
        elif $c=="SUITE-FINAL-VERMELHA-COM-RESSALVA" then "última suíte completa (\($u.tag)) rc=\($u.rc), aceita pelo dono via suite-ressalva.sh"
        else $c end' <<<"$SF")
      if [ "$cod" = "SUITE-FINAL-VERMELHA-COM-RESSALVA" ]; then
        RES=$(jq -c --arg d "$det" '. + [{id:"suite_final", resultado:"INFORMATIVO", detalhe:$d}]' <<<"$RES")
        [ "$DRY" = 1 ] || gad_runlog "$PHASE_DIR" "$NN" incidente "$RUNLOG_ETAPA" --kv origem=confere-etapa.sh --kv detalhe="$det"
      else
        RES=$(jq -c --arg i "$(printf '%s' "$cod" | tr 'A-Z-' 'a-z_')" --arg d "$det" \
          '. + [{id:$i, resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
      fi
    done < <(jq -r '.codigos[]' <<<"$SF")
  fi

  # ── escopo por plano (P06, consertos F24.4): confere-plano.sh em cada plano com SUMMARY.
  # `FORA-DA-LISTA`, `LISTA-VAZIA`, `COMMITS-A-MENOS` e `SEM-COMMIT` reprovam. Arquivo fora do
  # `files_modified` é colisão que o cálculo de ondas não enxerga; commit único para três
  # tarefas esconde qual tarefa quebrou e impede reverter só ela (A1, 04/09/2026). Cada plano
  # reprovado pelo script vira um `incidente` no run-log; um plano que falha não impede a
  # conferência dos outros, e plano sem SUMMARY é pulado.
  CPL="$GAD_SCRIPTS_DIR/confere-plano.sh"
  PC_OK=0; PC_FALHA="[]"; PC_CODIGOS="{}"; PC_REPROVA=""; PC_INFO="{}"; PC_NDECL="{}"
  if [ -f "$CPL" ]; then
    for sf in "$PHASE_DIR"/*-SUMMARY.md; do
      [ -f "$sf" ] || continue
      pid=$(basename "$sf" -SUMMARY.md)
      [ -f "$PHASE_DIR/$pid-PLAN.md" ] || continue
      pcrc=0; pcout=$(bash "$CPL" "$PHASE_DIR" "$pid" 2>/dev/null | tail -1) || pcrc=$?
      jq -e . >/dev/null 2>&1 <<<"$pcout" || pcout=$(jq -cn --arg p "$pid" --arg rc "$pcrc" \
        '{plan:$p, veredito:"falha", codigos:["ILEGIVEL (rc=\($rc))"], fora_da_lista:[]}')
      # C7 (plano 2): informativos (DECISAO-SEM-SUMMARY) colhidos antes do `continue` — um plano
      # `ok` pode ter faltantes.
      PC_INFO=$(jq -c --arg p "$pid" --argjson i "$(jq -c '.informativos // []' <<<"$pcout")" 'if ($i|length)>0 then . + {($p): $i} else . end' <<<"$PC_INFO")
      # 46t: desvios de escopo que o executor DECLAROU no SUMMARY, por plano.
      PC_NDECL=$(jq -c --arg p "$pid" --argjson n "$(jq -c '.arquivo_nao_declarado // []' <<<"$pcout")" \
        'if ($n|length)>0 then . + {($p): $n} else . end' <<<"$PC_NDECL")
      if [ "$(jq -r '.veredito' <<<"$pcout")" = ok ]; then
        PC_OK=$((PC_OK+1)); continue
      fi
      PC_FALHA=$(jq -c --arg p "$pid" '. + [$p]' <<<"$PC_FALHA")
      PC_CODIGOS=$(jq -c --arg p "$pid" --argjson c "$(jq -c '.codigos' <<<"$pcout")" '. + {($p): $c}' <<<"$PC_CODIGOS")
      if jq -e '.codigos[] | select(test("^(FORA-DA-LISTA|LISTA-VAZIA|COMMITS-A-MENOS|SEM-COMMIT)"))' >/dev/null <<<"$pcout"; then
        PC_REPROVA="$PC_REPROVA${PC_REPROVA:+ · }$pid: $(jq -r '[.codigos[]|select(test("^(FORA-DA-LISTA|LISTA-VAZIA|COMMITS-A-MENOS|SEM-COMMIT)"))] + .fora_da_lista | join(" ")' <<<"$pcout")"
      fi
      [ "$DRY" = 1 ] || gad_runlog "$PHASE_DIR" "$NN" incidente "$RUNLOG_ETAPA" \
        --kv origem=confere-plano.sh --kv plano="$pid" \
        --kv detalhe="$(jq -r '.codigos | join(", ")' <<<"$pcout")"
    done
    if [ -n "$PC_REPROVA" ]; then
      RES=$(jq -c --arg d "plano fora do escopo declarado: $PC_REPROVA — arquivo fora do files_modified é colisão invisível para as ondas; menos commits que tarefas esconde qual tarefa quebrou" \
        '. + [{id:"escopo_planos", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    fi
    # recolisão entre ondas com as listas REAIS (46t): dois planos de ONDAS diferentes que
    # tocaram o mesmo arquivo não são colisão (as ondas são sequenciais); dois planos da MESMA
    # onda, sim — e é exatamente o que o cálculo de ondas não viu, porque rodou com a lista
    # declarada antes da execução. Assert novo: vale da v2.6.0 em diante.
    COLISAO=$(IDX_JSON="$IDX3" ROOT="$ROOT" python3 - <<'PYCOL' || echo '[]'
import json, os, re, subprocess
idx = json.loads(os.environ.get("IDX_JSON") or "{}")
waves = {w: list(ids) for w, ids in (idx.get("waves") or {}).items()}
if not waves:  # fallback: plans[].wave (mesma informação; medido 11/09 na 24.5)
    for p in (idx.get("plans") or []):
        if p.get("wave") is not None and p.get("id"):
            waves.setdefault(str(p["wave"]), []).append(p["id"])
root = os.environ["ROOT"]
tocados = {}
for w, ids in waves.items():
    for pid in ids:
        tag = re.escape(pid)
        r = subprocess.run(["git", "-C", root, "log", "--format=%H", "-E",
                            "--grep=^[a-z]+\\(" + tag + "(-[^)]*)?\\)(!)?:"],
                           capture_output=True, text=True, timeout=20)
        arqs = set()
        for sha in r.stdout.split():
            s = subprocess.run(["git", "-C", root, "show", "--name-only", "--format=", sha],
                               capture_output=True, text=True, timeout=20)
            for f in s.stdout.splitlines():
                f = f.strip()
                # FM-11EXE: a isenção era larga demais («todo .planning/, todo
                # *-SUMMARY.md») e escondia colisão real entre dois planos da mesma onda
                # em artefato de planejamento. Agora ignora SÓ o que o modo worktree do
                # GSD manda todo plano tocar — o REQUIREMENTS.md — e o SUMMARY do
                # PRÓPRIO plano. O SUMMARY de OUTRO plano volta a contar.
                if not f:
                    continue
                if f.endswith("REQUIREMENTS.md") or f.endswith("/STATE.md") or f.endswith("state.json"):
                    continue
                base = f.rsplit("/", 1)[-1]
                if base.endswith("-SUMMARY.md") and base.startswith(pid):
                    continue
                arqs.add(f)
        tocados[pid] = arqs
out = []
for w, ids in waves.items():
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            comuns = sorted(tocados.get(ids[i], set()) & tocados.get(ids[j], set()))
            if comuns:
                out.append({"onda": w, "planos": [ids[i], ids[j]], "arquivos": comuns[:10]})
print(json.dumps(out, ensure_ascii=False))
PYCOL
    )
    jq -e . >/dev/null 2>&1 <<<"$COLISAO" || COLISAO='[]'
    if [ "$(jq 'length' <<<"$COLISAO")" -gt 0 ]; then
      RES=$(jq -c --arg d "COLISAO-REAL-NA-ONDA: $(jq -r '[.[]|"onda \(.onda): \(.planos|join(" × ")) em \(.arquivos|join(", "))"]|join(" · ")' <<<"$COLISAO" | cut -c1-400) — dois planos da MESMA onda commitaram o mesmo arquivo; o cálculo de ondas rodou com a lista declarada antes da execução" \
        '. + [{id:"colisao_real_onda", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
      [ "$DRY" = 1 ] || gad_runlog "$PHASE_DIR" "$NN" incidente "$RUNLOG_ETAPA" --kv origem=confere-etapa.sh \
        --kv detalhe="COLISAO-REAL-NA-ONDA: $(jq -r '[.[]|"onda \(.onda) \(.planos|join("×"))"]|join("; ")' <<<"$COLISAO")"
    fi
  fi
  EXTRAI=$(jq -c --argjson ok "$PC_OK" --argjson f "$PC_FALHA" --argjson c "$PC_CODIGOS" --argjson i "$PC_INFO" \
    --argjson col "${COLISAO:-[]}" --argjson nd "$PC_NDECL" \
    '. + {planos_conferidos:{ok:$ok, falha:$f, codigos:$c, informativos:$i},
          colisao_real_onda:$col, arquivo_nao_declarado:$nd}' <<<"$EXTRAI")

  # ── prova por reexecução (A4, plano 4 / 05/09/2026): "17 de 18 verdes" sem comando e saída
  # colados na mesma seção não é verificação. Na F24.4 o 24.4-05-SUMMARY.md:71 e :223
  # declararam a contagem sem ter rodado nada; o :237 do mesmo arquivo traz a prova por
  # arquivo tocado e não pode ser acusado. Afirmação = `N (de|dos|of) M … verde(s)|passed|
  # passing` (ASCII); prova na mesma seção `##` (o bloco antes do 1º `##`, frontmatter
  # incluído, é uma seção) = linha `$ …`, fence com pytest|uv run|npm|make|cargo, ou linha de
  # sumário `passed|failed … (in|em) <tempo>`. Reprova só quando o SUMMARY traz o marcador
  # `<!-- gad_prova: v1 -->` do template do fork; sem ele vira aviso em `extrai.prova_avisos`
  # (fase antiga não reprova por regra nova, molde do P12).
  PROVA=$(python3 - "$PHASE_DIR" 2>/dev/null <<'PYPROVA' || echo '{"falhas":[],"avisos":[]}'
import glob
import json
import os
import re
import sys

RE_AFIRMA = re.compile(r"\b([0-9]+) (de|dos|of) ([0-9]+)[^.\n]{0,80}\b(verde|verdes|passed|passing)\b", re.I)
RE_CMD = re.compile(r"^\s*\$ \S")
RE_FENCE_CMD = re.compile(r"\b(pytest|uv run|npm|make|cargo)\b")
RE_SUMARIO = re.compile(r"\b(passed|failed)\b.*\b(in|em) [0-9]+([.,][0-9]+)?(s|min|m)\b")


def secoes(linhas):
    """[(inicio, fim)] por `##`; o bloco antes do primeiro `##` é uma seção."""
    marcas = [i for i, l in enumerate(linhas) if l.startswith("## ")]
    limites = [0] + marcas + [len(linhas)]
    return [(limites[i], limites[i + 1]) for i in range(len(limites) - 1) if limites[i] < limites[i + 1]]


def tem_prova(bloco):
    fence = False
    for l in bloco:
        if l.startswith("```"):
            fence = not fence
            continue
        if fence and RE_FENCE_CMD.search(l):
            return True
        if RE_CMD.match(l) or RE_SUMARIO.search(l):
            return True
    return False


falhas, avisos = [], []
for arq in sorted(glob.glob(os.path.join(sys.argv[1], "*-SUMMARY.md"))):
    with open(arq, encoding="utf-8", errors="replace") as fh:
        linhas = fh.read().splitlines()
    marcado = any("<!-- gad_prova: v1 -->" in l for l in linhas)
    for ini, fim in secoes(linhas):
        bloco = linhas[ini:fim]
        if tem_prova(bloco):
            continue
        for k, l in enumerate(bloco, ini + 1):
            m = RE_AFIRMA.search(l)
            if m:
                item = {"arquivo": os.path.basename(arq), "linha": k, "trecho": m.group(0)[:100]}
                (falhas if marcado else avisos).append(item)
print(json.dumps({"falhas": falhas, "avisos": avisos}, ensure_ascii=False))
PYPROVA
  )
  jq -e . >/dev/null 2>&1 <<<"$PROVA" || PROVA='{"falhas":[],"avisos":[]}'
  if [ "$(jq '.falhas|length' <<<"$PROVA")" -gt 0 ]; then
    RES=$(jq -c --arg d "PROVA-SEM-REEXECUCAO: $(jq -r '[.falhas[]|"\(.arquivo):\(.linha) «\(.trecho)»"]|join(" · ")' <<<"$PROVA" | cut -c1-400) — cole o comando rodado e a saída na mesma seção" \
      '. + [{id:"prova_por_reexecucao", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    [ "$DRY" = 1 ] || gad_runlog "$PHASE_DIR" "$NN" incidente "$RUNLOG_ETAPA" --kv origem=confere-etapa.sh \
      --kv detalhe="PROVA-SEM-REEXECUCAO em $(jq -r '[.falhas[]|"\(.arquivo):\(.linha)"]|join(", ")' <<<"$PROVA")"
  elif [ "$(jq '.avisos|length' <<<"$PROVA")" -gt 0 ]; then
    RES=$(jq -c --arg d "$(jq '.avisos|length' <<<"$PROVA") afirmação(ões) de contagem sem comando e saída na mesma seção (SUMMARY sem \`gad_prova: v1\` — aviso): $(jq -r '[.avisos[]|"\(.arquivo):\(.linha)"]|join(", ")' <<<"$PROVA" | cut -c1-300)" \
      '. + [{id:"prova_por_reexecucao", resultado:"aviso", detalhe:$d}]' <<<"$RES")
  fi
  EXTRAI=$(jq -c --argjson p "$PROVA" '. + {prova_avisos: $p.avisos, prova_falhas: $p.falhas}' <<<"$EXTRAI")
fi

# ── etapa 1 (intenção): R2 (SPEC × PRE-SPEC) + R6 (ROADMAP × REQUIREMENTS) ───
# Os dois asserts são MECÂNICOS e vivem aqui (não no manifest) porque dependem de rodar
# outro script e de casar id a id — a DSL do manifest só sabe glob/grep/sdk.
if [ "$ETAPA" = "1" ]; then
  SETUP_I="$GAD_SCRIPTS_DIR/setup-intencao.sh"
  CPS="$GAD_SCRIPTS_DIR/confere-pre-spec.sh"
  SPEC_F="$PHASE_DIR/$NN-SPEC.md"; PRE_F="$PHASE_DIR/$NN-PRE-SPEC.md"
  ROTA_F="$PHASE_DIR/.intent/pre-spec-route.json"

  # ── R2: as falhas do confere-pre-spec.sh ((a) MARCA-SEM-ID, (b) ID-INEXISTENTE e as
  # demais, inclusive AC-SEM-ORIGEM / AC-ORIGEM-INEXISTENTE — P12) REPROVAM;
  # EXTENSAO-SUSPEITA (c) e ORIGEM-NAO-CONFERIDA são AVISO — vão para `extrai.r2_avisos`,
  # que o coordenador põe no briefing do revisor. Sem PRE-SPEC, o SPEC é conferido contra
  # o REQUIREMENTS (modo sem pré-spec, id `r2_spec_sem_pre_spec`): o SPEC do dono e o SPEC
  # gerado sem insumo passam pelas mesmas conferências de forma (D7c).
  # `--exige-origem` sempre (a go-and-do exige origem nos ACs a partir da v2.4.0) e
  # `--reqs` quando o REQUIREMENTS.md existe — sem ele `CANC-v3x-03` e afins entrariam
  # sem conferência. Flag de classe não é passada: a classe liga só pelo marcador
  # `<!-- spec-classe: v1 -->` do SPEC (com a flag aqui, todo SPEC anterior ao molde
  # reprovaria no dia da instalação). Sinos de classe na família das falhas: AC-SEM-CLASSE,
  # EXIGIDO-SEM-MOTIVO, EXIGIDO-SEM-REGUA, EXIGIDO-DIVERGE-SEM-MOTIVO, GOAL-SEM-COBERTURA;
  # AC-ORIGEM-REPETIDA é bandeira (aviso) e vai ao briefing do revisor.
  R2_ST=nao_aplicavel; R2_AVISOS="[]"
  if [ -f "$SPEC_F" ] && [ -f "$CPS" ]; then
    REQS_F="$ROOT/.planning/REQUIREMENTS.md"
    R2_ARGS=(--exige-origem); [ -f "$REQS_F" ] && R2_ARGS+=(--reqs "$REQS_F")
    if [ -f "$PRE_F" ]; then
      R2_ID=r2_pre_spec
      r2rc=0; r2out=$(bash "$CPS" "${R2_ARGS[@]}" "$SPEC_F" "$PRE_F" 2>&1) || r2rc=$?
    else
      R2_ID=r2_spec_sem_pre_spec
      r2rc=0; r2out=$(bash "$CPS" --sem-pre-spec "${R2_ARGS[@]}" "$SPEC_F" 2>&1) || r2rc=$?
    fi
    # O script emite falha e aviso no mesmo formato; um código de classe sem o marcador sai
    # como aviso com o sufixo literal abaixo. Separar pelo sufixo, não pelo nome: senão o gate
    # promoveria o aviso a falha e a classe viraria incondicional aqui (resposta 2 do dono).
    AVISO_CLASSE='(aviso: SPEC sem `<!-- spec-classe: v1 -->`'
    AVISO_CLASSE_RX='\(aviso: SPEC sem `<!-- spec-classe: v1 -->`'
    R2_AVISOS=$(printf '%s\n' "$r2out" | { grep -E "^(EXTENSAO-SUSPEITA|ORIGEM-NAO-CONFERIDA|AC-ORIGEM-REPETIDA) |$AVISO_CLASSE_RX" || true; } | jq -R . | jq -cs .)
    r2fal=$(printf '%s\n' "$r2out" | { grep -v -F "$AVISO_CLASSE" || true; } | { grep -E '^(MARCA-SEM-ID|ID-INEXISTENTE|FATO-SEM-EVIDENCIA|RESSALVA-SEM-LIMITACAO|AC-POR-PONTEIRO|AC-SEM-ORIGEM|AC-ORIGEM-INEXISTENTE|AC-SEM-CLASSE|EXIGIDO-SEM-MOTIVO|EXIGIDO-SEM-REGUA|EXIGIDO-DIVERGE-SEM-MOTIVO|GOAL-SEM-COBERTURA|BLOCO-AUSENTE|BLOCO-INVALIDO) ' || true; })
    ROTA_MODO=""; [ -f "$ROTA_F" ] && ROTA_MODO=$(jq -r '.mode // empty' "$ROTA_F" 2>/dev/null || true)
    if [ -z "$r2fal" ]; then
      R2_ST=ok
      RES=$(jq -c --arg id "$R2_ID" --arg d "confere-pre-spec.sh sem falhas ($(printf '%s' "$R2_AVISOS" | jq 'length') aviso(s) EXTENSAO-SUSPEITA/ORIGEM-NAO-CONFERIDA/AC-ORIGEM-REPETIDA)" \
        '. + [{id:$id, resultado:"ok", detalhe:$d}]' <<<"$RES")
    elif [ "$ROTA_MODO" = legacy ] && printf '%s' "$r2fal" | grep -q '^BLOCO-AUSENTE'; then
      # rota antiga autorizada pelo dono (§0.5): o bloco não existe por decisão dele —
      # a conferência não se aplica, e o sino `pre_spec_sem_bloco` é que carrega o custo.
      R2_ST=pulado_legacy
      RES=$(jq -c '. + [{id:"r2_pre_spec", resultado:"aviso", detalhe:"PRE-SPEC sem bloco com rota `legacy` autorizada pelo dono — R2 não se aplica (sino pre_spec_sem_bloco)"}]' <<<"$RES")
    else
      R2_ST=falha
      RES=$(jq -c --arg id "$R2_ID" --arg d "confere-pre-spec.sh reprovou: $(printf '%s' "$r2fal" | head -3 | tr '\n' ' ' | cut -c1-300)" \
        '. + [{id:$id, resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    fi
  fi

  # ── R5 (A5, consertos F24.4): reconciliação VEREDITO × APLICADO + trava de ordem.
  # A tabela de reconciliação do NN-INTENT-REVIEW.md é prosa do coordenador e nunca foi
  # conferida por máquina: na F24.4 passaram 1 INVERSAO (c4-05 `nao_sustentado` aplicado),
  # 2 CONFIRMADO-NAO-APLICADO, 3 APLICADO-SEM-VEREDITO e 1 ORDEM-VIOLADA (correção c4b
  # promovida 5 min depois da releitura c4). Fase sem ciclos sai `n/a` com exit 0.
  CREC="$GAD_SCRIPTS_DIR/confere-reconciliacao.sh"
  if [ -f "$CREC" ]; then
    recrc=0; recout=$(bash "$CREC" "$PHASE_DIR" --ordem 2>&1) || recrc=$?
    if [ "$recrc" = 0 ]; then
      RES=$(jq -c --arg d "$(printf '%s\n' "$recout" | { grep -E '^(resumo|reconciliacao|ordem):' || true; } | tr '\n' ' ' | cut -c1-300)" \
        '. + [{id:"r5_reconciliacao", resultado:"ok", detalhe:$d}]' <<<"$RES")
    elif [ "$recrc" = 1 ]; then
      RES=$(jq -c --arg d "confere-reconciliacao.sh reprovou: $(printf '%s\n' "$recout" | { grep -E '^(INVERSAO|CONFIRMADO-NAO-APLICADO|APLICADO-SEM-VEREDITO|ORDEM-VIOLADA)' || true; } | head -4 | tr '\n' ' ' | cut -c1-400)" \
        '. + [{id:"r5_reconciliacao", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    else
      # exit 2 (uso inválido/insumo ilegível): ausência de garantia, não prova de que está
      # reconciliado — reprova, no mesmo critério do R2/R6 acima.
      RES=$(jq -c --arg d "confere-reconciliacao.sh não pôde conferir (rc=$recrc): $(printf '%s\n' "$recout" | tr '\n' ' ' | cut -c1-300)" \
        '. + [{id:"r5_reconciliacao", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    fi
  fi

  # ── FM-09INT: os mesmos números entre cabeçalho, tabela, vereditos e dívidas ──
  # Medido na F4 RLR (04-INTENT-REVIEW.md, --dry-run, somente-leitura): cabeçalho diz 12
  # confirmados × tabela tem 24 × vereditos no disco têm 30; 3 dispensados no cabeçalho ×
  # 5 nos arquivos de veredito; 5 dívidas na seção × só 2 no deferred-items.md
  # (c1-10/I-01/I-02 ficam de fora). AVISO, não falha: o
  # plano diz «acusa» e um parser de cardinalidade que travasse a etapa cobraria caro por
  # um artefato que o coordenador ainda pode emendar. Vai ao briefing pelo `extrai`.
  CCARD="$GAD_SCRIPTS_DIR/confere-cardinalidade.sh"
  if [ -f "$CCARD" ]; then
    cardrc=0; cardout=$(bash "$CCARD" "$PHASE_DIR" "$NN" --json 2>/dev/null) || cardrc=$?
    jq -e . >/dev/null 2>&1 <<<"$cardout" || cardout='{"avisos":[],"medido":{}}'
    n_card=$(jq '(.avisos//[])|length' <<<"$cardout")
    if [ "${n_card:-0}" -gt 0 ]; then
      RES=$(jq -c --arg d "AVISO: $n_card divergência(s) de cardinalidade na etapa 1 — $(jq -r '(.avisos//[])|join(" · ")' <<<"$cardout" | cut -c1-400)" \
        '. + [{id:"cardinalidade_etapa_1", resultado:"AVISO", detalhe:$d}]' <<<"$RES")
    fi
    EXTRAI=$(jq -c --argjson c "$cardout" '. + {cardinalidade: $c}' <<<"$EXTRAI")
  fi

  # ── FJ-02INT (metade script): «aprovado_com_ressalva» exige dívida nomeada ──
  # Regra 5 do plano: «aprovado com ressalva» só vale na etapa 1 — aqui é onde intent_review
  # é lido, então é aqui que o veto mora. O manifesto (etapa-1.json) já aceita o rótulo no
  # `intent_review_fechada`; este bloco cobra a contrapartida: sem dívida nomeada na «##
  # Dívidas registradas» E registrada no deferred-items.md, a ressalva é bilhete em branco.
  # Reaproveita o `medido.dividas` que o confere-cardinalidade.sh (FM-09INT, acima) já
  # extraiu — não é um 2º parser do mesmo INTENT-REVIEW.md.
  IR_ARQ="$PHASE_DIR/$NN-INTENT-REVIEW.md"
  if [ -f "$IR_ARQ" ] && grep -qE '^intent_review: aprovado_com_ressalva' "$IR_ARQ"; then
    na_secao_n=$(jq '(.medido.dividas.na_secao//[])|length' <<<"${cardout:-{\}}" 2>/dev/null || echo 0)
    faltam=$(jq -r '(.medido.dividas.na_secao//[]) - (.medido.dividas.no_deferred//[]) | join(" ")' <<<"${cardout:-{\}}" 2>/dev/null)
    if [ "${na_secao_n:-0}" -eq 0 ]; then
      RES=$(jq -c '. + [{id:"intent_ressalva_sem_divida", resultado:"FALHA", detalhe:"intent_review: aprovado_com_ressalva sem NENHUMA dívida na «## Dívidas registradas» do INTENT-REVIEW — a ressalva não pode ficar sem nome"}]' <<<"$RES")
      FALHAS=$((FALHAS+1))
    elif [ -n "$faltam" ]; then
      RES=$(jq -c --arg d "intent_review: aprovado_com_ressalva mas a(s) dívida(s) $faltam da «## Dívidas registradas» não está(ão) no deferred-items.md — a ressalva tem de ser rastreável até o fim da fase" \
        '. + [{id:"intent_ressalva_sem_divida", resultado:"FALHA", detalhe:$d}]' <<<"$RES")
      FALHAS=$((FALHAS+1))
    else
      RES=$(jq -c '. + [{id:"intent_ressalva_sem_divida", resultado:"ok", detalhe:"ressalva com dívida nomeada e registrada no deferred-items.md"}]' <<<"$RES")
    fi
  fi

  # ── FM-05INT (metade fiscal): diff em SPEC/CONTEXT sem selo ──
  # Achado F4 RLR: 4 linhas entraram no 04-SPEC.md por fora do correcoes-commit.sh (dentro de
  # um commit de artefatos, sem id nem selo). O `.correcoes-c<C>.aplicado` de cada ciclo grava
  # `blobs[].blob_commit` — o blob do arquivo COMO FICOU depois daquele selo. Pega, por path
  # (só NN-SPEC.md/NN-CONTEXT.md), o `blob_commit` do ciclo MAIS ALTO que menciona aquele path
  # e compara com o blob do arquivo agora no worktree (`git hash-object`, não `git log`: um
  # squash-merge da PR reescreve o histórico e apaga os commits que a evidência original citava
  # — medido no rl-representation real, onde o commit 53dbda6 da auditoria não existe mais).
  # Diferente = alguém escreveu no arquivo depois do último selo. AVISO (não falha: o plano diz
  # «acusar», e o mesmo veto da FM-09INT vale aqui — travar a etapa por um artefato que o
  # coordenador ainda pode emendar custaria caro).
  # LIMITE MEDIDO: só cobre a janela DEPOIS do último selo. Rodado hoje contra a F4 RLR real
  # (que tem a evidência do 53dbda6), este assert dá `[]` — não há regressão a mostrar porque
  # não foi medida a ordem exata do 53dbda6 frente aos selos c2/c3/c4, só o fato de que uma
  # escrita anterior a um selo posterior fica com o mesmo blob_commit do estado atual e por
  # isso é invisível a este mecanismo, que só compara "selo mais recente" × "worktree agora".
  # Cobrir
  # a janela INTER-ciclo pediria encadear `c<N>.aplicado.blobs[].blob_commit` contra
  # `c<N+1>.base.json.alvos[].blob_pre` — e no rl-representation real o `.correcoes-c1.base.json`
  # em disco tem `head_pre` de DEPOIS do ciclo 4 (o próprio re-selo que a FM-05INT/A1 endereça),
  # então essa cadeia não fecha nos dados existentes hoje. Fica como próximo passo declarado,
  # não como bug: ver relatório.
  # (A 2ª metade do achado — "re-emissão de veredito sem escritor registrado" — já é o que o
  # J5/`confere-ciclo.sh --origem-vereditos` mede pelo sha256 do `.vereditos-c<C>.origem.json`
  # contra o `escritores[]`: um bloco abaixo, sem duplicar aqui.)
  declare -A SELO_BLOB=()
  for ap in "$PHASE_DIR/.intent/".correcoes-c*.aplicado; do
    [ -f "$ap" ] || continue
    c_ap=$(basename "$ap" | sed -n 's/^\.correcoes-c\([0-9][0-9]*\)b\?\.aplicado$/\1/p')
    [ -n "$c_ap" ] || c_ap=0
    while IFS=$'\t' read -r bp bc; do
      [ -n "$bp" ] || continue
      case "$bp" in
        */"$NN"-SPEC.md|*/"$NN"-CONTEXT.md) ;;
        *) continue ;;
      esac
      prev="${SELO_BLOB[$bp]:-}"
      c_prev="${prev%%:*}"
      if [ -z "$prev" ] || [ "${c_ap:-0}" -ge "${c_prev:-0}" ] 2>/dev/null; then
        SELO_BLOB["$bp"]="$c_ap:$bc"
      fi
    done < <(jq -r '(.blobs//[])[] | "\(.path)\t\(.blob_commit)"' "$ap" 2>/dev/null)
  done
  SEM_SELO=()
  for bp in "${!SELO_BLOB[@]}"; do
    bc="${SELO_BLOB[$bp]#*:}"
    fp="$ROOT/$bp"
    [ -f "$fp" ] || continue
    atual=$(git -C "$ROOT" hash-object -- "$bp" 2>/dev/null) || continue
    [ "$atual" = "$bc" ] || SEM_SELO+=("$(basename "$bp"): selado $bc, agora $atual")
  done
  if [ "${#SEM_SELO[@]}" -gt 0 ]; then
    d="SPEC/CONTEXT.md mudou depois do último selo do correcoes-commit.sh — ${SEM_SELO[*]}"
    RES=$(jq -c --arg d "${d:0:400}" '. + [{id:"spec_context_sem_selo", resultado:"AVISO", detalhe:$d}]' <<<"$RES")
  fi

  # ── J5 (45k, F24.5): proveniência do veredito. O R5 acima já pega correção promovida SEM
  # linha de veredito; o que ele não vê é a linha de veredito escrita pelo próprio coordenador
  # depois que o verificador saiu (24.5: 3 linhas às 12:12, verificador fechado às 11:15).
  # Em `--dry-run` (o modo com que se valida fase arquivada, PC-12) o recibo ausente sai como
  # aviso: as fases 24.3-24.5 em disco não o têm, e o gate morde a rodada corrente, não a
  # auditoria retroativa.
  CCICLO="$GAD_SCRIPTS_DIR/confere-ciclo.sh"
  if [ -f "$CCICLO" ]; then
    J5_NIVEL=FALHA; [ "$DRY" = 1 ] && J5_NIVEL=aviso
    for vf in "$PHASE_DIR/.intent/".vereditos-c*.txt; do
      [ -f "$vf" ] || continue
      c=$(basename "$vf" | sed -n 's/^\.vereditos-c\([0-9][0-9]*\)\.txt$/\1/p')
      [ -n "$c" ] || continue
      jrc=0; jout=$(bash "$CCICLO" --origem-vereditos "$PHASE_DIR" "$c" 2>&1) || jrc=$?
      if [ "$jrc" = 0 ]; then
        RES=$(jq -c --arg id "j5_origem_c$c" --arg d "$(printf '%s' "$jout" | cut -c1-200)" \
          '. + [{id:$id, resultado:"ok", detalhe:$d}]' <<<"$RES")
      else
        RES=$(jq -c --arg id "j5_origem_c$c" --arg n "$J5_NIVEL" --arg d "$(printf '%s' "$jout" | tr '\n' ' ' | cut -c1-300)" \
          '. + [{id:$id, resultado:$n, detalhe:$d}]' <<<"$RES")
        if [ "$J5_NIVEL" = FALHA ]; then FALHAS=$((FALHAS+1)); fi
      fi
    done
  fi

  # ── C3 (plano 2, 05/09/2026): D-NN que citam critério mudado desde a base selada e não foram
  # emendadas nem marcadas superada-c<N>. Informativo até a métrica M9 medir uma fase real.
  if [ -f "$CREC" ]; then
    recfin=$(bash "$CREC" "$PHASE_DIR" --final 2>/dev/null || true)
    ndes=$(printf '%s\n' "$recfin" | { grep -c '^D-NN-DESATUALIZADA final ' || true; })
    ids=$(printf '%s\n' "$recfin" | { grep '^D-NN-DESATUALIZADA final ' || true; } | awk '{print $3}' | tr '\n' ' ')
    if [ "${ndes:-0}" -gt 0 ]; then
      RES=$(jq -c --arg d "D-NN-DESATUALIZADA: $ndes decisão(ões) citam critério do SPEC mudado desde a base selada e não foram emendadas: $ids— emende ou marque superada-c<N>" \
        '. + [{id:"decisoes_desatualizadas", resultado:"aviso", detalhe:$d}]' <<<"$RES")
    else
      RES=$(jq -c '. + [{id:"decisoes_desatualizadas", resultado:"ok", detalhe:"nenhuma D-NN cita critério mudado sem emenda"}]' <<<"$RES")
    fi
    EXTRAI=$(jq -c --argjson n "${ndes:-0}" --arg ids "$ids" '. + {decisoes_desatualizadas:{n:$n, ids:$ids}}' <<<"$EXTRAI")
  fi

  # ── R6: cada issue estruturada emitida pelo setup tem de estar RESOLVIDA no disco —
  # o id existe no REQUIREMENTS.md (o `--r6` já re-deriva contra ele) OU há sino
  # ESTRUTURADO. Menção em prosa não conta. O sino é procurado nos `.intent/.sinos-*.txt`
  # E no NN-INTENT-REVIEW.md: a limpeza 1.5 apaga os sinos no fecho (assert
  # `limpeza_intent`, min/max 0) e a política diz que o conteúdo sobrevive no
  # INTENT-REVIEW — sem esta 2ª fonte a escapatória seria insatisfazível nesta cancela.
  # FM-03INT (F4 RLR): o `--r6` passou a sair != 0 quando a entrada do ROADMAP nao tem
  # **Goal:** — mas o JSON ja foi impresso. Um `|| echo '{}'` aqui APAGARIA a extracao
  # inteira e o fiscal perderia o R6 no exato caso em que ele mais importa.
  R6=$( bash "$SETUP_I" --r6 "$PHASE_DIR" "$NN" 2>/dev/null | tail -1 )
  [ -n "$R6" ] || R6='{}'
  jq -e . >/dev/null 2>&1 <<<"$R6" || R6='{}'
  SINO_FONTES=("$PHASE_DIR/$NN-INTENT-REVIEW.md")
  for sf in "$PHASE_DIR/.intent/".sinos-*.txt; do [ -f "$sf" ] && SINO_FONTES+=("$sf"); done
  tem_sino() { # <regex>
    local f; for f in "${SINO_FONTES[@]}"; do
      [ -f "$f" ] || continue
      grep -qE "$1" "$f" && return 0
    done
    return 1
  }
  while IFS= read -r iss; do
    [ -n "$iss" ] || continue
    itipo=$(jq -r '.tipo' <<<"$iss"); iid=$(jq -r '.id // ""' <<<"$iss")
    case "$itipo" in
      missing_requirement)
        if tem_sino "(^|[^A-Za-z0-9_])req_ausente: *${iid}([^A-Za-z0-9_-]|$)"; then
          RES=$(jq -c --arg d "REQ-ID $iid segue ausente do REQUIREMENTS.md, mas há sino estruturado \`req_ausente: $iid\`" \
            '. + [{id:"r6_missing_requirement", resultado:"aviso", detalhe:$d}]' <<<"$RES")
        else
          RES=$(jq -c --arg d "o ROADMAP cita $iid e o REQUIREMENTS.md não o define; nem há sino estruturado \`req_ausente: $iid\` (menção em prosa não conta)" \
            '. + [{id:"r6_missing_requirement", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
        fi ;;
      phase_without_req_id)
        if tem_sino "(^|[^A-Za-z0-9_])fase_sem_req([^A-Za-z0-9_-]|$)"; then
          RES=$(jq -c '. + [{id:"r6_phase_without_req_id", resultado:"aviso", detalhe:"entrada do ROADMAP segue sem REQ-ID, com sino estruturado `fase_sem_req`"}]' <<<"$RES")
        else
          RES=$(jq -c --arg d "a entrada da fase no ROADMAP não cita REQ-ID na linha **Requirements** (\"$(jq -r '.requirements_line // "linha ausente"' <<<"$R6" | cut -c1-80)\") e não há sino \`fase_sem_req\`" \
            '. + [{id:"r6_phase_without_req_id", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
        fi ;;
    esac
  done < <(jq -c '.issues[]?' <<<"$R6")

  # ── R7 (proveniência T3) — B4, 31/08 ──────────────────────────────────────────────
  # O `prompts/intent.md` (336-343 e 386-394) manda cada achado `confirmado` da tabela do
  # NN-INTENT-REVIEW.md trazer a `proposicao` com CINCO campos — {artefato, ancora,
  # span_linhas, texto, origem_texto} —, que é o que localiza a frase defeituosa no
  # artefato. Era prosa sem comando associado: nada conferia a presença, e a régua T3 da
  # /audit-gad ficou cega por duas fases. Aqui a etapa 1 passa a reprovar quando falta.
  #
  # Parsing, com as armadilhas do arquivo real (24.4-INTENT-REVIEW.md) já contornadas:
  #  · a coluna se chama `proposição` (com cedilha e til) e a célula NÃO repete a chave
  #    `proposicao:` — procurar o token literal `proposicao` dá zero e mataria a regra;
  #  · o arquivo tem outras tabelas (contagem por ciclo, sinos do c0) que não têm a coluna
  #    — por isso a tabela é delimitada pelo cabeçalho que traz `veredito` E `proposi…`;
  #  · o `texto:` verbatim pode conter `|` (caso real c3-06), o que quebra split
  #    posicional — daí o veredito ser casado como célula inteira (`| confirmado |`) e os
  #    campos serem procurados na linha toda, com borda de palavra para que `origem_texto:`
  #    não seja contado como `texto:`.
  # É checagem de PRESENÇA dos cinco nomes, não de validade do valor: a linha legítima
  # `artefato: —` (achado c1-04, destino transparência) tem de continuar passando.
  IR_F="$PHASE_DIR/$NN-INTENT-REVIEW.md"
  if [ -f "$IR_F" ]; then
    R7_OUT=$(awk '
      function tem(l, campo) { return (l ~ ("(^|[^A-Za-z0-9_])" campo ":")) }
      substr($0,1,1) != "|" { dentro=0; next }
      !dentro { if (index($0,"veredito")>0 && index($0,"proposi")>0) dentro=1; next }
      /^\|[-: |]*\|[-: |]*$/ { next }                       # linha separadora
      $0 !~ /\| *confirmado *\|/ { next }                    # só achados confirmados
      {
        total++
        n = tem($0,"artefato") + tem($0,"ancora") + tem($0,"span_linhas") \
          + tem($0,"texto") + tem($0,"origem_texto")
        split($0, c, "|"); id = c[2]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
        if (id == "") id = "(sem id)"
        if (n == 5) completos++
        else {
          if (n == 0) zerados++; else parciais++
          if (ruins != "") ruins = ruins ","
          ruins = ruins id "(" n "/5)"      # o id entra na lista com ou sem campo algum
        }
      }
      END { printf "%d %d %d %d %s\n", total+0, completos+0, parciais+0, zerados+0, ruins }
    ' "$IR_F")
    read -r r7_tot r7_com r7_par r7_zer r7_ids <<<"$R7_OUT"
    if [ "${r7_tot:-0}" = 0 ]; then
      : # nenhum achado confirmado na tabela (ou tabela ausente) — outra regra cuida disso
    elif [ "$r7_zer" = "$r7_tot" ]; then
      # ESCOTILHA DE COMPATIBILIDADE (obrigatória): nenhum achado tem proposição alguma →
      # é fase anterior à régua. Avisa e NÃO falha; sem isso toda fase antiga reprovaria.
      # A regra só morde na adoção PARCIAL, que é o estado que corrompe a medição da T3.
      RES=$(jq -c --arg d "nenhum dos $r7_tot achados confirmados traz \`proposicao\` — fase anterior à régua T3; a /audit-gad medirá tudo como \`não_medido\`" \
        '. + [{id:"r7_proposicao_t3", resultado:"aviso", detalhe:$d}]' <<<"$RES")
    elif [ "$((r7_par + r7_zer))" -gt 0 ]; then
      RES=$(jq -c --arg d "adoção parcial da \`proposicao\` (T3): $r7_com de $r7_tot achados confirmados completos; sem os cinco campos: ${r7_ids:-—}$( [ "$r7_zer" -gt 0 ] && printf ' · %s sem nenhum campo' "$r7_zer" )" \
        '. + [{id:"r7_proposicao_t3", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    else
      RES=$(jq -c --arg d "os $r7_tot achados confirmados trazem \`proposicao\` com os cinco campos" \
        '. + [{id:"r7_proposicao_t3", resultado:"ok", detalhe:$d}]' <<<"$RES")
    fi
    EXTRAI=$(jq -c --argjson t "${r7_tot:-0}" --argjson k "${r7_com:-0}" \
      '. + {r7_confirmados: $t, r7_com_proposicao: $k}' <<<"$EXTRAI")
  fi

  # ── C3 (consertos F24.4): nenhum sino do ciclo 0 fica `aberto` no fecho da etapa.
  # Na F24.4 o sino c0-14 chegou ao fim `aberto` e a etapa fechou assim mesmo.
  CSIN="$GAD_SCRIPTS_DIR/confere-sinos.sh"
  if [ -x "$CSIN" ]; then
    csrc=0; csout=$(bash "$CSIN" "$PHASE_DIR" 2>&1) || csrc=$?
    if [ "$csrc" = 0 ]; then
      RES=$(jq -c --arg d "$(printf '%s' "$csout" | head -1)" \
        '. + [{id:"c3_sinos_abertos", resultado:"ok", detalhe:$d}]' <<<"$RES")
    elif [ "$csrc" = 1 ]; then
      RES=$(jq -c --arg d "$(printf '%s' "$csout" | tr '\n' ' ' | cut -c1-400)" \
        '. + [{id:"c3_sinos_abertos", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    else
      # exit 2 (.ciclo0.json ilegível): mesmo critério do R5 — ausência de garantia reprova.
      RES=$(jq -c --arg d "confere-sinos.sh não pôde conferir (rc=$csrc): $(printf '%s' "$csout" | tr '\n' ' ' | cut -c1-300)" \
        '. + [{id:"c3_sinos_abertos", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    fi
  fi

  EXTRAI=$(jq -c --argjson r6 "$R6" --arg st "$R2_ST" --argjson av "$R2_AVISOS" \
    '. + {goal_roadmap: ($r6.goal_roadmap // null),
          issues: ($r6.issues // []),
          req_ids: ($r6.req_ids // []),
          r2_status: $st, r2_avisos: $av}' <<<"$EXTRAI")
fi

# ════════════════════════════════════════════════════════════════════════════
# REGRAS GERAIS DA AUDITORIA F4 RLR — valem para TODA etapa
# ════════════════════════════════════════════════════════════════════════════

# ── FM-07INT · FM-04PLAN · FM-07GAT: incidente tardio ────────────────────────
# «Incidente na hora» virou frase em todos os prompts de etapa; aqui está a cancela
# que a torna imponível. Dois sintomas, os dois medidos na F4 RLR:
#   (1) incidente rotulado com a etapa Y e horário POSTERIOR ao `end` de Y — foi
#       escrito depois, de memória, no fecho;
#   (2) >= 3 incidentes no MESMO segundo — rajada digitada de uma vez.
# Só olha os `end` que JÁ existem: o `end` da etapa corrente é gravado logo abaixo,
# por este mesmo script, e ainda não está no arquivo.
RLI="$PHASE_DIR/$NN-RUN-LOG.jsonl"
if [ -f "$RLI" ]; then
  TARDIOS=$(python3 - "$RLI" "$RUNLOG_ETAPA" 2>/dev/null <<'PYTARDIO'
import json, sys, collections
from datetime import datetime

def ts(v):
    if v is None: return None
    if isinstance(v, (int, float)): return float(v)
    t = str(v).replace("Z", "+00:00")
    try: return datetime.fromisoformat(t).timestamp()
    except Exception: return None

# O fiscal de uma etapa julga SÓ os incidentes DELA (medido em 21/09: sem este recorte a
# regra reprovava as 8 etapas das 3 fases reais por incidentes de outras etapas — «nenhuma
# regra nova pode reprovar etapa antiga sem motivo real»).
alvo = (sys.argv[2] if len(sys.argv) > 2 else "").strip()
def da_etapa(et):
    if not alvo:
        return True
    a = alvo.split()[0] if alvo.split() else alvo
    b = (et or "").split()[0] if (et or "").split() else (et or "")
    return a == b

ends, eventos = {}, []
for linha in open(sys.argv[1], encoding="utf-8", errors="replace"):
    linha = linha.strip()
    if not linha: continue
    try: e = json.loads(linha)
    except Exception: continue
    t = ts(e.get("ts") or e.get("timestamp") or e.get("hora"))
    et = str(e.get("etapa") or "")
    if e.get("evento") == "end" and t is not None and et:
        # `substitui`: um `end` re-emitido aposenta o anterior — fica o mais recente
        ends[et] = max(ends.get(et, 0.0), t)
    if e.get("evento") == "incidente" and da_etapa(et):
        eventos.append((t, et, (e.get("detalhe") or e.get("kv", {}).get("detalhe") or "")[:70]))

tardios, rajadas = [], []
for t, et, det in eventos:
    fim = ends.get(et)
    if t is not None and fim is not None and t > fim + 1:
        tardios.append("%s (+%ds do end)" % (det or et, int(t - fim)))

por_segundo = collections.Counter(int(t) for t, _, _ in eventos if t is not None)
for seg, n in por_segundo.items():
    if n >= 3:
        rajadas.append("%d incidentes no mesmo segundo (%d)" % (n, seg))

print(json.dumps({"tardios": tardios, "rajadas": rajadas}, ensure_ascii=False))
PYTARDIO
) || TARDIOS=""
  jq -e . >/dev/null 2>&1 <<<"$TARDIOS" || TARDIOS='{"tardios":[],"rajadas":[]}'
  n_tard=$(jq '.tardios|length' <<<"$TARDIOS"); n_raj=$(jq '.rajadas|length' <<<"$TARDIOS")
  if [ "${n_tard:-0}" -gt 0 ] || [ "${n_raj:-0}" -gt 0 ]; then
    # AVISO nesta release, por DECISÃO DO DONO (21/09): medido em modo seco, o assert
    # reprova quase toda etapa das 3 fases reais (RLR F3/F4, inspired F24.5) — não por
    # artefato da regra, mas porque a prática de escrever incidente no fecho é real e
    # ainda não passou por uma fase com os prompts novos («incidente na hora», C1–C4).
    # Fica DURA na release seguinte, depois de uma fase real com esses prompts.
    # As duas metades (posterior ao `end` e rajada no mesmo segundo) foram rebaixadas
    # juntas: o assert é um só e o dono nomeou o assert.
    RES=$(jq -c --arg d "AVISO: incidente escrito fora da hora do fato: $(jq -r '(.tardios + .rajadas)|join(" · ")' <<<"$TARDIOS" | cut -c1-400)" \
      '. + [{id:"incidente_tardio", resultado:"AVISO", detalhe:$d}]' <<<"$RES")
  fi
  EXTRAI=$(jq -c --argjson t "$TARDIOS" '. + {incidente_tardio: $t}' <<<"$EXTRAI")
fi

# ── FM-06INT: a pasta da fase não pode terminar a etapa com git status sujo ───
# 160 arquivos do `.intent/` da F4 ficaram fora de qualquer commit: eles são a
# evidência da consultoria e sumiriam numa limpeza. A lista de temporários aceitos foi
# medida contra as pastas reais (RLR F3/F4, inspired F24.5), não chutada.
# A etapa 0 é a ABERTURA da rodada: a pasta da fase está justamente nascendo, e cobrar
# árvore limpa ali seria cobrar o fim no começo. A regra vale das etapas 1 em diante.
if [ "$ETAPA" != "0" ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  SUJOS=$( { git -C "$ROOT" status --porcelain --untracked-files=all -- "$PHASE_DIR" 2>/dev/null \
    | sed 's/^...//' \
    | grep -vE '(^|/)\.(gad|gad-[a-z-]*|correcoes-c[0-9a-z]*\.(tmp|pre-[0-9]+\.patch))' \
    | grep -vE '\.(tmp|swp|err|log|pyc)$|(^|/)__pycache__/|(^|/)\.DS_Store$' \
    | head -40; } || true )
  if [ -n "$SUJOS" ]; then
    n_sujos=$( { printf '%s\n' "$SUJOS" | grep -c . || true; } )
    # ── DECISÃO DO DONO (21/09), sobre a contradição medida pelo executor 1 ───────
    # O `workflow.md` roda o fiscal ANTES do `commita-artefatos.sh`, então cobrar árvore
    # limpa de TUDO deixaria a etapa em impasse (o `NN-UAT.md` que o próprio fiscal
    # escreve sujaria a etapa 5; o run-log é reescrito por toda etapa antes de qualquer
    # fiscal). O dono decidiu, sem inverter a ordem do workflow:
    #   • FALHA DURA só para a EVIDÊNCIA DURA — `.intent/`, `pareceres/` e os atestados
    #     (`.fence-*.ok`) —, que é o alvo real da FM-06INT (160 arquivos fora do git na
    #     F4, incluindo os selos dos ciclos 2/3/4 e os vereditos);
    #   • ISENTO o que a PRÓPRIA etapa produz: a etapa 1 é quem produz `.intent/` e
    #     `pareceres/` (e ainda não os commitou quando o fiscal dela roda), e a etapa N é
    #     quem produz o seu `.fence-N.ok` (gravado adiante, neste mesmo script);
    #   • AVISO para todo o resto (`NN-UAT.md`, SUMMARY, run-log, …).
    # Quem commita a evidência dura é `commita-artefatos.sh … evidencia` — uma fonte só.
    DURA=""; RESTO=""
    while IFS= read -r arq; do
      [ -n "$arq" ] || continue
      case "$arq" in
        *"/.intent/"*|*"/pareceres/"*)
          # produzidos pela etapa 1 → isentos NELA, duros das etapas 2 em diante
          if [ "${ETAPA%% *}" = "1" ]; then RESTO="$RESTO $arq"; else DURA="$DURA $arq"; fi ;;
        *"/.fence-"*".ok")
          # o atestado da PRÓPRIA etapa é escrito adiante; os das etapas anteriores não
          if [ "$arq" = "${arq%/.fence-${ETAPA%% *}.ok}" ]; then DURA="$DURA $arq"
          else RESTO="$RESTO $arq"; fi ;;
        *) RESTO="$RESTO $arq" ;;
      esac
    done <<<"$SUJOS"
    if [ -n "$DURA" ]; then
      n_dura=$( { printf '%s\n' $DURA | grep -c . || true; } )
      RES=$(jq -c --arg d "evidência da fase fora de commit na etapa $ETAPA — $n_dura arquivo(s) de .intent/, pareceres/ ou atestado (rode: commita-artefatos.sh <fase> <NN> evidencia): $(printf '%s ' $DURA | cut -c1-350)" \
        '. + [{id:"evidencia_fora_do_git", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    fi
    if [ -n "$RESTO" ]; then
      n_resto=$( { printf '%s\n' $RESTO | grep -c . || true; } )
      RES=$(jq -c --arg d "AVISO: pasta da fase com $n_resto arquivo(s) fora de commit na etapa $ETAPA (rode commita-artefatos.sh antes de fechar): $(printf '%s ' $RESTO | cut -c1-350)" \
        '. + [{id:"pasta_da_fase_suja", resultado:"AVISO", detalhe:$d}]' <<<"$RES")
    fi
    EXTRAI=$(jq -c --argjson n "${n_sujos:-0}" --arg du "$(printf '%s ' $DURA)" \
      '. + {pasta_suja: {total:$n, evidencia_dura:($du|ltrimstr(" ")|rtrimstr(" "))}}' <<<"$EXTRAI")
  fi
fi

# ── FM-01GAT: recibo do 4.1 vencido por commit de código posterior ───────────
# Um recibo fiscal existe para dizer «o que foi aprovado é ISTO». Medido na F4 RLR: o
# `.fence-4.1.ok` apontava para o commit das 20:40 e, das 21:19 às 21:22, o fixer
# commitou WR-14, IN-11 e IN-10 em `fluxo.py`, `posse.py` e `tasks.py` — sem novo `end`,
# sem novo recibo e sem revisor. O gate reabre: novo fiscal → novo `end` → novo recibo
# (e, para warning/critical, re-review estreitado pelo mesmo mecanismo do 4.1b).
# Vale das etapas POSTERIORES ao 4.1 (4.1b/4.4/4.5, 5 e 6) — a própria 4.1 escreve o
# recibo adiante, neste mesmo script.
# O rótulo do run-log é a chave (o argumento `4-code-review` vira `4.1 code-review`).
case "${RUNLOG_ETAPA%% *}" in
  0|1|1.5|2|2.5|3|4.1|4.1b) ;;
  *)
    # FM-02GAT: `.fence-4.1b.ok` (re-review, workflow.md §4.1) não herda o recibo do
    # 4.1 — é o mais recente dos dois que vale (o 4.1b substitui o 4.1 quando existe).
    F41="$PHASE_DIR/.fence-4.1.ok"
    F41B="$PHASE_DIR/.fence-4.1b.ok"
    if [ -f "$F41B" ] && { [ ! -f "$F41" ] || [ "$F41B" -nt "$F41" ]; }; then
      F41="$F41B"
    fi
    if [ -f "$F41" ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
      H41=$(jq -r '.head // ""' "$F41" 2>/dev/null || echo "")
      if [ -n "$H41" ] && git -C "$ROOT" cat-file -e "$H41^{commit}" 2>/dev/null; then
        # `:!.planning` tira os artefatos da rodada: recibo vencido é CÓDIGO que mudou.
        DEPOIS=$( { git -C "$ROOT" log --format='%h %s' "$H41..HEAD" -- . ':!.planning' 2>/dev/null \
                    | head -5; } || true )
        if [ -n "$DEPOIS" ]; then
          n_dep=$( { printf '%s\n' "$DEPOIS" | grep -c . || true; } )
          RES=$(jq -c --arg d "recibo do 4.1 vencido: $n_dep commit(s) de código depois do head aprovado ($H41) — o gate reabre (novo fiscal 4.1 → novo end → novo recibo; warning/critical pedem re-review estreitado, mecanismo do 4.1b): $(printf '%s · ' $DEPOIS | cut -c1-300)" \
            '. + [{id:"recibo_4_1_vencido", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
          EXTRAI=$(jq -c --arg h "$H41" --argjson n "$n_dep" \
            '. + {recibo_4_1: {head:$h, commits_depois:$n}}' <<<"$EXTRAI")
        fi
      fi
    fi ;;
esac

# ── FM-02ENC (fiscal): o local não pode terminar a fase à frente do remoto ────
# AVISO, não falha: há projeto que proíbe push direto e fecha por PR. O que não pode
# é o fecho passar em silêncio com commits que ninguém mais tem.
if [ "$ETAPA" = "6" ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  BR=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  case "$BR" in
    master|main)
      UP=$(git -C "$ROOT" rev-parse --abbrev-ref "$BR@{upstream}" 2>/dev/null || echo "")
      if [ -n "$UP" ]; then
        AF=$(git -C "$ROOT" rev-list --count "$UP..$BR" 2>/dev/null || echo 0)
        if [ "${AF:-0}" -gt 0 ]; then
          RES=$(jq -c --arg d "AVISO: $BR está $AF commit(s) à frente de $UP — o fecho da fase não foi empurrado (6.5: push explícito, ou banner com a pendência se o projeto proíbe push direto)" \
            '. + [{id:"local_a_frente_do_remoto", resultado:"AVISO", detalhe:$d}]' <<<"$RES")
          EXTRAI=$(jq -c --argjson n "$AF" --arg b "$BR" --arg u "$UP" \
            '. + {local_a_frente: {ramo:$b, upstream:$u, commits:$n}}' <<<"$EXTRAI")
        fi
      fi ;;
  esac
fi

# ── FJ-01ENC (fiscal): todo ID aberto da radiografia aparece no resumo ───────
# Os DOIS resumos da F4 RLR narraram as rodadas em prosa e disseram que elas «fecharam os
# avisos restantes»; o code review fechou com WR-09 aberto e 16 Info. A régua do resumo
# manda citar o ID de cada achado ABERTO — aqui ela vira medição. A lista sai do MESMO
# leitor do fiscal do 4.1 (lib/review-maior.py): não há segundo parser.
if [ "$ETAPA" = "6" ]; then
  RSM="$PHASE_DIR/$NN-RESUMO-EXECUTIVO.md"
  if [ -f "$RSM" ]; then
    RVE=$(python3 "$GAD_SCRIPTS_DIR/lib/review-maior.py" "$PHASE_DIR" "$NN" 2>/dev/null) || RVE=""
    jq -e . >/dev/null 2>&1 <<<"$RVE" || RVE='{}'
    ABERTOS=$( { jq -r '(.abertos//[])[]' <<<"$RVE" 2>/dev/null || true; } )
    # FJ-02INT (metade etapa 6): a fase fechada com `intent_review: aprovado_com_ressalva`
    # tem a(s) dívida(s) que a sustentam como aceite pendente — a régua é a MESMA do WR-09
    # acima («todo ID aberto aparece no resumo»), só que a lista vem do
    # confere-cardinalidade.sh (medido.dividas.na_secao) em vez do review-maior.py. Um
    # `FALTAM` só, um assert só — não duplica o resumo_sem_id_aberto.
    IR_ARQ6="$PHASE_DIR/$NN-INTENT-REVIEW.md"
    CCARD6="$GAD_SCRIPTS_DIR/confere-cardinalidade.sh"
    if [ -f "$IR_ARQ6" ] && grep -qE '^intent_review: aprovado_com_ressalva' "$IR_ARQ6" && [ -f "$CCARD6" ]; then
      card6rc=0; cardout6=$(bash "$CCARD6" "$PHASE_DIR" "$NN" --json 2>/dev/null) || card6rc=$?
      jq -e . >/dev/null 2>&1 <<<"$cardout6" || cardout6='{"medido":{}}'
      RESSALVA_IDS=$( { jq -r '(.medido.dividas.na_secao//[])[]' <<<"$cardout6" 2>/dev/null || true; } )
      ABERTOS="$ABERTOS $RESSALVA_IDS"
    fi
    FALTAM=""
    for id in $ABERTOS; do
      [ -n "$id" ] || continue
      grep -qF "$id" "$RSM" || FALTAM="$FALTAM $id"
    done
    if [ -n "$FALTAM" ]; then
      n_falta=$( { printf '%s\n' $FALTAM | grep -c . || true; } )
      RES=$(jq -c --arg d "$n_falta ID(s) aberto(s) do $(jq -r '.arquivo // "code review"' <<<"$RVE") ausente(s) do resumo executivo:$FALTAM — a régua manda citar cada achado ABERTO (número ruim é o que este documento existe para mostrar); o bloco do numeros-da-fase.sh já traz a lista pronta" \
        '. + [{id:"resumo_sem_id_aberto", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
      EXTRAI=$(jq -c --arg f "${FALTAM# }" '. + {resumo_ids_abertos_ausentes: $f}' <<<"$EXTRAI")
    fi
  fi
fi

# ── FM-04GAT: o 4.1 lê as contagens do arquivo de MAIOR iteração ─────────────
# A F4 RLR tinha 04-REVIEW.md, .iter2, .iter3, .iter4, 04-REVIEW-FIX.md e
# 04-REVIEW-FIX.iter4.md — o fiscal lia o `04-REVIEW.md` (a 1ª iteração) e dava o
# veredito da rodada errada. Ordem: REVIEW-FIX mais recente > REVIEW.iterN mais alto >
# REVIEW.md. E `status: all_fixed` com `skipped > 0` reprova: nada fica de fora sem ser
# nomeado. Formato não reconhecido FALHA ALTO — leitor cego é pior que leitor ausente.
if [ "$ETAPA" = "4-code-review" ]; then
  # Leitor fatorado para `lib/review-maior.py` (21/09) — o `numeros-da-fase.sh` (FJ-01ENC)
  # lê o MESMO arquivo pela MESMA regra. Não escreva um segundo parser.
  REVMAX=$(python3 "$GAD_SCRIPTS_DIR/lib/review-maior.py" "$PHASE_DIR" "$NN" 2>/dev/null) || REVMAX=""
  jq -e . >/dev/null 2>&1 <<<"$REVMAX" || REVMAX='{"arquivo":null,"formato_nao_reconhecido":true}'
  rv_arq=$(jq -r '.arquivo // ""' <<<"$REVMAX")
  if [ -n "$rv_arq" ]; then
    if [ "$(jq -r '.formato_nao_reconhecido // false' <<<"$REVMAX")" = true ]; then
      RES=$(jq -c --arg d "$rv_arq: formato não reconhecido (nenhum \`status:\` no cabeçalho) — o leitor de contagens falha alto em vez de devolver zeros" \
        '. + [{id:"review_formato", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    fi
    rv_st=$(jq -r '.status // ""' <<<"$REVMAX"); rv_sk=$(jq -r '.skipped // 0' <<<"$REVMAX")
    if [ "$rv_st" = all_fixed ] && [ "${rv_sk:-0}" != 0 ] && [ "${rv_sk:-0}" != null ]; then
      RES=$(jq -c --arg d "$rv_arq declara \`status: all_fixed\` com skipped: $rv_sk — achado pulado não é achado consertado; nomeie cada um" \
        '. + [{id:"all_fixed_com_skipped", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    fi
  fi
  EXTRAI=$(jq -c --argjson r "$REVMAX" '. + {review_maior_iteracao: $r}' <<<"$EXTRAI")
  # O manifest extrai `status`/`critical`/`warning`/`total` do `NN-REVIEW.md` — a PRIMEIRA
  # iteracao. Era esse o numero que a camada 0 lia para rotear (medido na F4 RLR: o
  # manifest dizia `issues_found · critical: 2` enquanto o iter4 ja dizia `all_fixed`).
  # Sobrescrevemos com o arquivo de maior iteracao, MANTENDO o formato de string do
  # manifest (`"status: all_fixed"`, com o rotulo) — quem parseia nao muda.
  if [ -n "$rv_arq" ]; then
    for campo in status critical warning total skipped; do
      v=$(jq -r --arg k "$campo" '.[$k] // empty' <<<"$REVMAX")
      if [ -z "$v" ]; then
        # ausente no arquivo de maior iteração → null DECLARADO. Deixar o valor do
        # NN-REVIEW.md aqui daria provenância MISTA (status do iter4, critical da 1ª
        # rodada) — pior que errado, porque parece coerente.
        EXTRAI=$(jq -c --arg k "$campo" '. + {($k): null}' <<<"$EXTRAI"); continue
      fi
      case "$campo" in
        status) fmt="status: $v" ;;
        *)      fmt="  $campo: $v" ;;
      esac
      EXTRAI=$(jq -c --arg k "$campo" --arg v "$fmt" '. + {($k): $v}' <<<"$EXTRAI")
    done
    EXTRAI=$(jq -c --arg a "$rv_arq" '. + {review_fonte: $a}' <<<"$EXTRAI")
  fi
fi

# ── veredito + eventos + medição ─────────────────────────────────────────────
if [ "$FALHAS" = 0 ]; then VEREDITO=pass; else VEREDITO=fail; fi
# dente do gate (auditorias F21-ox/F24-pausa/F24-fecho — 3ª ocorrência de "guarda cega
# reporta verde"): o fail deixa um lock que o run-log.sh HONRA — nenhum `end` desta
# etapa é gravável enquanto o lock existir. Só ESTE script, ao dar pass, remove o lock.
LOCK="$PHASE_DIR/.gate-fail-${RUNLOG_ETAPA%% *}.json"
# 46(j)/46(r): recibo do fiscal. O lock acima é o dente do fail; este é o do pass. O
# coordenador da etapa só pode devolver `done` com este arquivo válido — «válido» = existe E
# `head` é o HEAD atual. Na F24.5 a etapa 1 e a etapa 3 devolveram «pronto» sem o fiscal ter
# rodado. Formato definido no PLANO-1; a etapa 3 usa o mesmo (fiacao-P1-fence.md).
FENCE="$PHASE_DIR/.fence-${RUNLOG_ETAPA%% *}.ok"
MEDICAO=null
if [ "$DRY" = 0 ]; then
  if [ "$VEREDITO" = pass ]; then
    POS_FAIL=0
    if [ "$SEMTEL" = 0 ] && [ -f "$LOCK" ]; then
      # v2.1.9: o pass que destrava um fail também fica no run-log como evento `script`
      # (F24.3 4.4: só a reprovação aparecia; a re-cancela verde só existia no transcript).
      # B1 (F4 RLR): a escrita saiu daqui — o `trap EXIT` no topo do arquivo grava o
      # evento `script` uma vez, no fim, com o exit real; `POS_FAIL=1` só alimenta o
      # resumo dele (_gad_ce_resumo) e o `--kv pos_gate_fail=true` do `end` abaixo.
      POS_FAIL=1; rm -f "$LOCK"
    fi
    HEAD_NOW=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo "")
    jq -cn --arg e "${RUNLOG_ETAPA%% *}" --arg f "$NN" --arg h "$HEAD_NOW" \
      --arg t "$(date -Is)" --arg s "${CLAUDE_CODE_SESSION_ID:0:8}" \
      --argjson n "$(jq 'length' <<<"$RES")" \
      '{v:1, etapa:$e, fase:$f, head:$h, ts:$t, sessao:$s, asserts:$n}' > "$FENCE"
    # janela da etapa: do checkpoint aberto pelo pre-despacho até agora
    sid="${CLAUDE_CODE_SESSION_ID:-}"
    if [ "$SEMTEL" = 1 ]; then sid=""; fi
    RL="$PHASE_DIR/$NN-RUN-LOG.jsonl"
    desde=""
    if [ -n "$sid" ] && [ -f "$RL" ]; then
      # || true: sob set -euo pipefail, grep sem match derrubava o script inteiro
      # (caso real F24: a etapa 0 não tem checkpoint → exit 1 sem saída + espelho stale)
      desde=$(grep "\"sessao\":\"${sid:0:8}\"" "$RL" | grep '"evento":"checkpoint"' \
        | grep -F "\"etapa\":\"$RUNLOG_ETAPA\"" | tail -n1 | sed -n 's/.*"ts":"\([^"]*\)".*/\1/p' || true)
      # etapa 0 não tem pre-despacho/checkpoint: a janela abre no evento `run`
      if [ -z "$desde" ] && [ "$ETAPA" = "0" ]; then
        desde=$(grep '"evento":"run"' "$RL" | tail -n1 | sed -n 's/.*"ts":"\([^"]*\)".*/\1/p' || true)
      fi
    fi
    if [ "$SEMTEL" = 1 ]; then
      MEDICAO='{"status":"sem_medicao","reason":"--sem-telemetria"}'
    elif [ -n "$sid" ] && [ -n "$desde" ]; then
      MEDICAO=$(python3 "$GAD_SCRIPTS_DIR/mede-tokens.py" --sessao "$sid" \
        --desde "$desde" --ate "$(date -Is)" --sem-espelho 2>/dev/null || echo '{"status":"sem_medicao","reason":"mede-tokens falhou"}')
    else
      MEDICAO='{"status":"sem_medicao","reason":"sem sessão ou sem checkpoint da etapa no run-log"}'
    fi
    POSFLAG=(); [ "$POS_FAIL" = 1 ] && POSFLAG=(--kv pos_gate_fail=true)
    # FM-04UAT (lado script, pendência do relatório B §6): a etapa 6 que PAROU sem ship
    # (rota 6.4-HB) grava veredito=handback, não pass, no PRÓPRIO `end` id 6 — não só no
    # `stop`/etapa "handback" que já existia. A rota (pausa/handback/ship) foi decidida no
    # DESPACHO da etapa 6 por `pre-despacho.sh 6` (6.1) e sobrevive no espelho
    # last-pre-despacho.json (mesmo etapa 6, ninguém mais rodou pre-despacho.sh no meio) —
    # lido aqui em vez de recalculado, para não ter 2º lugar que decide a rota.
    VEREDITO_END=pass
    if [ "${RUNLOG_ETAPA%% *}" = "6" ]; then
      PD6="$ROOT/.planning/.gad/last-pre-despacho.json"
      if [ -f "$PD6" ] && [ "$(jq -r '.etapa // ""' "$PD6" 2>/dev/null)" = "6" ] \
         && [ "$(jq -r '.paralelismo.rota // .rota // ""' "$PD6" 2>/dev/null)" = "handback" ]; then
        VEREDITO_END=handback
      fi
    fi
    if [ "$SEMTEL" = 1 ]; then
      :
    elif [ "$(jq -r '.status' <<<"$MEDICAO")" = ok ]; then
      gad_runlog "$PHASE_DIR" "$NN" end "$RUNLOG_ETAPA" \
        --tokens-reais "$(jq -r '.total.input_tokens + .total.output_tokens + .total.cache_creation_tokens + (.total.cache_creation_1h_tokens // 0)' <<<"$MEDICAO")" \
        --custo "$(jq -r '.total.custo_usd // 0' <<<"$MEDICAO")" \
        --kv veredito="$VEREDITO_END" ${POSFLAG[@]+"${POSFLAG[@]}"}
    else
      gad_runlog "$PHASE_DIR" "$NN" end "$RUNLOG_ETAPA" --kv veredito="$VEREDITO_END" \
        --kv medicao="$(jq -r '.reason // "indisponivel"' <<<"$MEDICAO")" \
        ${POSFLAG[@]+"${POSFLAG[@]}"}
    fi
  else
    rm -f "$FENCE"
    resumo=$(jq -r '[.[] | select(.resultado=="FALHA") | .id] | join(",")' <<<"$RES")
    if [ "$SEMTEL" = 0 ]; then
      printf '{"etapa":"%s","ts":"%s","resumo":"falhas: %s"}\n' \
        "${RUNLOG_ETAPA%% *}" "$(date -Is)" "$resumo" > "$LOCK"
      # B1 (F4 RLR): idem — o `trap EXIT` grava o evento `script` (exit=1, resumo com
      # "falhas: $resumo" via _gad_ce_resumo, que lê a variável `resumo` acima).
    fi
  fi
fi

gad_json_out confere-etapa "$(jq -cn --arg e "$ETAPA" --arg v "$VEREDITO" \
  --argjson r "$RES" --argjson x "$EXTRAI" --argjson m "$MEDICAO" \
  '{etapa:$e, veredito:$v, asserts:$r, extrai:$x, medicao:$m}')"
[ "$VEREDITO" = pass ]
