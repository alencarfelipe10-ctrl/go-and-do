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
# Blocos MECÂNICOS fora do manifest (a DSL só sabe glob/grep/sdk): etapa 1 = R2
# (`confere-pre-spec.sh <SPEC> <PRE-SPEC>`: falhas reprovam, EXTENSAO-SUSPEITA vira aviso
# em `extrai.r2_avisos`) + R6 (`setup-intencao.sh --r6`: cada issue estruturada exige id
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
      --tokens-reais "$(jq -r '.total.input_tokens + .total.output_tokens + .total.cache_creation_tokens' <<<"$MEDICAO")" \
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
  ST="$ROOT/.planning/STATE.md"
  if [ -f "$ST" ] && grep -qE '^status: *executing' "$ST" \
     && grep -qE "^current_phase: *${FASE}\$" "$ST"; then
    RES=$(jq -c --arg d "STATE.md ainda diz status: executing para a fase $FASE — rode reconcilia-docs.sh" \
      '. + [{id:"state_reconciliado", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
  fi
  # varredura anti-órfã da TaskList (S.C): sinal p/ camada 0 reconciliar
  EXTRAI=$(jq -c --argjson p "$n_plans" --argjson s "$n_sums" \
    '. + {plans:$p, summaries:$s}' <<<"$EXTRAI")
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
  # demais) REPROVAM; EXTENSAO-SUSPEITA (c) é AVISO — vai para `extrai.r2_avisos`, que o
  # coordenador põe no briefing do revisor. Sem PRE-SPEC não há o que conferir.
  R2_ST=nao_aplicavel; R2_AVISOS="[]"
  if [ -f "$PRE_F" ] && [ -f "$SPEC_F" ] && [ -f "$CPS" ]; then
    r2rc=0; r2out=$(bash "$CPS" "$SPEC_F" "$PRE_F" 2>&1) || r2rc=$?
    R2_AVISOS=$(printf '%s\n' "$r2out" | { grep -E '^EXTENSAO-SUSPEITA ' || true; } | jq -R . | jq -cs .)
    r2fal=$(printf '%s\n' "$r2out" | { grep -E '^(MARCA-SEM-ID|ID-INEXISTENTE|FATO-SEM-EVIDENCIA|RESSALVA-SEM-LIMITACAO|AC-POR-PONTEIRO|BLOCO-AUSENTE|BLOCO-INVALIDO) ' || true; })
    ROTA_MODO=""; [ -f "$ROTA_F" ] && ROTA_MODO=$(jq -r '.mode // empty' "$ROTA_F" 2>/dev/null || true)
    if [ -z "$r2fal" ]; then
      R2_ST=ok
      RES=$(jq -c --arg d "confere-pre-spec.sh sem falhas ($(printf '%s' "$R2_AVISOS" | jq 'length') aviso(s) EXTENSAO-SUSPEITA)" \
        '. + [{id:"r2_pre_spec", resultado:"ok", detalhe:$d}]' <<<"$RES")
    elif [ "$ROTA_MODO" = legacy ] && printf '%s' "$r2fal" | grep -q '^BLOCO-AUSENTE'; then
      # rota antiga autorizada pelo dono (§0.5): o bloco não existe por decisão dele —
      # a conferência não se aplica, e o sino `pre_spec_sem_bloco` é que carrega o custo.
      R2_ST=pulado_legacy
      RES=$(jq -c '. + [{id:"r2_pre_spec", resultado:"aviso", detalhe:"PRE-SPEC sem bloco com rota `legacy` autorizada pelo dono — R2 não se aplica (sino pre_spec_sem_bloco)"}]' <<<"$RES")
    else
      R2_ST=falha
      RES=$(jq -c --arg d "confere-pre-spec.sh reprovou: $(printf '%s' "$r2fal" | head -3 | tr '\n' ' ' | cut -c1-300)" \
        '. + [{id:"r2_pre_spec", resultado:"FALHA", detalhe:$d}]' <<<"$RES"); FALHAS=$((FALHAS+1))
    fi
  fi

  # ── R6: cada issue estruturada emitida pelo setup tem de estar RESOLVIDA no disco —
  # o id existe no REQUIREMENTS.md (o `--r6` já re-deriva contra ele) OU há sino
  # ESTRUTURADO. Menção em prosa não conta. O sino é procurado nos `.intent/.sinos-*.txt`
  # E no NN-INTENT-REVIEW.md: a limpeza 1.5 apaga os sinos no fecho (assert
  # `limpeza_intent`, min/max 0) e a política diz que o conteúdo sobrevive no
  # INTENT-REVIEW — sem esta 2ª fonte a escapatória seria insatisfazível nesta cancela.
  R6=$( { bash "$SETUP_I" --r6 "$PHASE_DIR" "$NN" 2>/dev/null || echo '{}'; } | tail -1 )
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

  EXTRAI=$(jq -c --argjson r6 "$R6" --arg st "$R2_ST" --argjson av "$R2_AVISOS" \
    '. + {goal_roadmap: ($r6.goal_roadmap // null),
          issues: ($r6.issues // []),
          req_ids: ($r6.req_ids // []),
          r2_status: $st, r2_avisos: $av}' <<<"$EXTRAI")
fi

# ── veredito + eventos + medição ─────────────────────────────────────────────
if [ "$FALHAS" = 0 ]; then VEREDITO=pass; else VEREDITO=fail; fi
# dente do gate (auditorias F21-ox/F24-pausa/F24-fecho — 3ª ocorrência de "guarda cega
# reporta verde"): o fail deixa um lock que o run-log.sh HONRA — nenhum `end` desta
# etapa é gravável enquanto o lock existir. Só ESTE script, ao dar pass, remove o lock.
LOCK="$PHASE_DIR/.gate-fail-${RUNLOG_ETAPA%% *}.json"
MEDICAO=null
if [ "$DRY" = 0 ]; then
  if [ "$VEREDITO" = pass ]; then
    POS_FAIL=0
    if [ -f "$LOCK" ]; then
      POS_FAIL=1; rm -f "$LOCK"
      # v2.1.9: o pass que destrava um fail também fica no run-log como evento `script`
      # (F24.3 4.4: só a reprovação aparecia; a re-cancela verde só existia no transcript)
      gad_runlog "$PHASE_DIR" "$NN" script "$RUNLOG_ETAPA" \
        --kv script=confere-etapa.sh --kv exit=0 --kv resumo="pass pós-fail (lock removido)"
    fi
    # janela da etapa: do checkpoint aberto pelo pre-despacho até agora
    sid="${CLAUDE_CODE_SESSION_ID:-}"
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
    if [ -n "$sid" ] && [ -n "$desde" ]; then
      MEDICAO=$(python3 "$GAD_SCRIPTS_DIR/mede-tokens.py" --sessao "$sid" \
        --desde "$desde" --ate "$(date -Is)" --sem-espelho 2>/dev/null || echo '{"status":"sem_medicao","reason":"mede-tokens falhou"}')
    else
      MEDICAO='{"status":"sem_medicao","reason":"sem sessão ou sem checkpoint da etapa no run-log"}'
    fi
    POSFLAG=(); [ "$POS_FAIL" = 1 ] && POSFLAG=(--kv pos_gate_fail=true)
    if [ "$(jq -r '.status' <<<"$MEDICAO")" = ok ]; then
      gad_runlog "$PHASE_DIR" "$NN" end "$RUNLOG_ETAPA" \
        --tokens-reais "$(jq -r '.total.input_tokens + .total.output_tokens + .total.cache_creation_tokens' <<<"$MEDICAO")" \
        --custo "$(jq -r '.total.custo_usd // 0' <<<"$MEDICAO")" \
        --kv veredito=pass ${POSFLAG[@]+"${POSFLAG[@]}"}
    else
      gad_runlog "$PHASE_DIR" "$NN" end "$RUNLOG_ETAPA" --kv veredito=pass \
        --kv medicao="$(jq -r '.reason // "indisponivel"' <<<"$MEDICAO")" \
        ${POSFLAG[@]+"${POSFLAG[@]}"}
    fi
  else
    resumo=$(jq -r '[.[] | select(.resultado=="FALHA") | .id] | join(",")' <<<"$RES")
    printf '{"etapa":"%s","ts":"%s","resumo":"falhas: %s"}\n' \
      "${RUNLOG_ETAPA%% *}" "$(date -Is)" "$resumo" > "$LOCK"
    gad_runlog "$PHASE_DIR" "$NN" script "$RUNLOG_ETAPA" \
      --kv script=confere-etapa.sh --kv exit=1 --kv resumo="falhas: $resumo"
  fi
fi

gad_json_out confere-etapa "$(jq -cn --arg e "$ETAPA" --arg v "$VEREDITO" \
  --argjson r "$RES" --argjson x "$EXTRAI" --argjson m "$MEDICAO" \
  '{etapa:$e, veredito:$v, asserts:$r, extrai:$x, medicao:$m}')"
[ "$VEREDITO" = pass ]
