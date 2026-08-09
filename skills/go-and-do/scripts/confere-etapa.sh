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
#   --dry-run: avalia e imprime, não grava evento nenhum (PC-12 — validação contra
#   fases arquivadas sem sujar run-log real).
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
# No pass (fora do --dry-run): mede a etapa com mede-tokens.py (janela desde o
# checkpoint aberto pelo pre-despacho) e grava o evento `end` com tokens_reais/custo —
# números só de fonte mecânica (G.1). No fail: grava evento `script` com o resumo.
# Saída: JSON 1 linha + espelho .planning/.gad-last-confere-etapa.json (PC-5).
# Exit: 0 pass · 1 fail · 2 erro de uso/manifest.

set -euo pipefail
shopt -s nullglob
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

ETAPA="${1:-}"; shift || true
[ -n "$ETAPA" ] || { echo "uso: confere-etapa.sh <etapa> [--fase N] [--projeto DIR] [--dry-run]" >&2; exit 2; }
FASE=""; PROJ=""; DRY=0; FIXCYCLE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fase)    FASE="${2:-}"; shift 2 ;;
    --projeto) PROJ="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --fix-cycle) FIXCYCLE=1; shift ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

MANIFEST="$GAD_SCRIPTS_DIR/manifests/etapa-$ETAPA.json"
[ -f "$MANIFEST" ] || { echo "ERRO: manifest inexistente para etapa \"$ETAPA\" ($MANIFEST)" >&2; exit 2; }
jq -e . "$MANIFEST" >/dev/null || { echo "ERRO: manifest inválido: $MANIFEST" >&2; exit 2; }
RUNLOG_ETAPA=$(jq -r '.runlog_etapa' "$MANIFEST")

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
    # 5.C: promoção dos marcadores — escritor único; modelo reporta, ESTE script promove
    if [ "$FALHAS" = 0 ] && [ "$DRY" = 0 ]; then
      grep -q '^pre_uat: generated' "$UAT" && sed -i 's/^pre_uat: generated/pre_uat: executed/' "$UAT"
      if [ "$FIXCYCLE" = 1 ] && ! grep -q '^pre_uat_fix_cycle:' "$UAT"; then
        sed -i '/^pre_uat: executed/a pre_uat_fix_cycle: done' "$UAT"
      fi
      if [ "$n_issue" = 0 ] && [ "$n_pend" = 0 ] && [ "$n_pass" -gt 0 ]; then
        grep -q '^status: testing' "$UAT" && sed -i 's/^status: testing/status: complete/' "$UAT"
      fi
    fi
  fi
fi

# ── veredito + eventos + medição ─────────────────────────────────────────────
if [ "$FALHAS" = 0 ]; then VEREDITO=pass; else VEREDITO=fail; fi
MEDICAO=null
if [ "$DRY" = 0 ]; then
  if [ "$VEREDITO" = pass ]; then
    # janela da etapa: do checkpoint aberto pelo pre-despacho até agora
    sid="${CLAUDE_CODE_SESSION_ID:-}"
    RL="$PHASE_DIR/$NN-RUN-LOG.jsonl"
    desde=""
    if [ -n "$sid" ] && [ -f "$RL" ]; then
      desde=$(grep "\"sessao\":\"${sid:0:8}\"" "$RL" | grep '"evento":"checkpoint"' \
        | grep -F "\"etapa\":\"$RUNLOG_ETAPA\"" | tail -n1 | sed -n 's/.*"ts":"\([^"]*\)".*/\1/p')
    fi
    if [ -n "$sid" ] && [ -n "$desde" ]; then
      MEDICAO=$(python3 "$GAD_SCRIPTS_DIR/mede-tokens.py" --sessao "$sid" \
        --desde "$desde" --ate "$(date -Is)" --sem-espelho 2>/dev/null || echo '{"status":"sem_medicao","reason":"mede-tokens falhou"}')
    else
      MEDICAO='{"status":"sem_medicao","reason":"sem sessão ou sem checkpoint da etapa no run-log"}'
    fi
    if [ "$(jq -r '.status' <<<"$MEDICAO")" = ok ]; then
      gad_runlog "$PHASE_DIR" "$NN" end "$RUNLOG_ETAPA" \
        --tokens-reais "$(jq -r '.total.input_tokens + .total.output_tokens + .total.cache_creation_tokens' <<<"$MEDICAO")" \
        --custo "$(jq -r '.total.custo_usd // 0' <<<"$MEDICAO")" \
        --kv veredito=pass
    else
      gad_runlog "$PHASE_DIR" "$NN" end "$RUNLOG_ETAPA" --kv veredito=pass \
        --kv medicao="$(jq -r '.reason // "indisponivel"' <<<"$MEDICAO")"
    fi
  else
    resumo=$(jq -r '[.[] | select(.resultado=="FALHA") | .id] | join(",")' <<<"$RES")
    gad_runlog "$PHASE_DIR" "$NN" script "$RUNLOG_ETAPA" \
      --kv script=confere-etapa.sh --kv exit=1 --kv resumo="falhas: $resumo"
  fi
fi

gad_json_out confere-etapa "$(jq -cn --arg e "$ETAPA" --arg v "$VEREDITO" \
  --argjson r "$RES" --argjson x "$EXTRAI" --argjson m "$MEDICAO" \
  '{etapa:$e, veredito:$v, asserts:$r, extrai:$x, medicao:$m}')"
[ "$VEREDITO" = pass ]
