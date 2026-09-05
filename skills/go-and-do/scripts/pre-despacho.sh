#!/usr/bin/env bash
# pre-despacho.sh — cancela de SAÍDA de toda etapa que despacha subagente (decisão 2.C).
#
# Num bloco atômico: gate de contexto (Sub-rotina A absorvida — teto absoluto 400k,
# parar > compactar) + extras da etapa (lidos do manifest) + evento no run-log. A camada 0
# roda isto ANTES de despachar e obedece o campo `despacho` do JSON — não decide.
#
# Uso: pre-despacho.sh <etapa> [--fase N] [--projeto DIR] [--dry-run]
#   <etapa> casa com scripts/manifests/etapa-<etapa>.json (string opaca — "1.5" e "2.5"
#   nunca viram int, PC-9). Sem --fase/--projeto, lê o ponteiro da rodada ativa
#   (.planning/.gad-rodada-ativa.json, escrito pelo abre-rodada.sh).
#
# Campo `despacho` do JSON (política 100% em script, aprovada 08/08):
#   ok                   — despache com prompts/<etapa>.md.
#   stop                 — contexto >= teto: o evento `stop` já foi gravado, a linha de
#                          handoff está no campo `handoff`; repasse-a ao dono e PARE.
#                          (fail-closed por LÓGICA; exit 3)
#   bloqueio_sem_revisor — só etapa 2.5: NENHUM revisor externo instalado. A fase NÃO
#                          continua sem consultoria especializada (decisão do Felipe 09/08,
#                          PC-6) — pergunte ao dono como proceder. (exit 4)
#   bloqueio_paralelismo — só etapa 3 (manifest `pre.paralelismo`): a rodada vai
#                          serializar uma onda de >=2 planos, ou os args trazem
#                          `--interactive`. O campo `motivo` diz a chave e o valor; suba
#                          AskUserQuestion com a `message` real do base-check. (exit 4)
#   Contexto `unknown` — falha ABERTA declarada: `despacho: ok` com `contexto.reason`
#   preenchido; anuncie "gate não mediu, confiando na retomabilidade" e siga (freio que
#   falha fechado por defeito de MEDIÇÃO pararia rodadas saudáveis).
#
# Campos informativos: `janela_silencio` (23h–07h local — hard gate vira pausa graciosa,
# S.I) · `revisores` (2.5: presença individual; UM ausente = segue com o outro, disclosed)
# · `git_remote` (6: gatilho da rota B de ship, 6.E — julgamento fica na camada 0).
#
# Escritor único (T.2): este script grava o CHECKPOINT da etapa (fotografia do contexto +
# abertura da janela; kv despacho=autorizado). O ciclo de vida fino de cada Agent() é do
# hook gad-lifecycle.sh (eventos despacho/retorno) — nunca daqui.
# Saída: JSON 1 linha + espelho .planning/.gad/last-pre-despacho.json (PC-5). Exit 0=ok.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

ETAPA="${1:-}"; shift || true
[ -n "$ETAPA" ] || { echo "uso: pre-despacho.sh <etapa> [--fase N] [--projeto DIR] [--dry-run]" >&2; exit 2; }
FASE=""; PROJ=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fase)    FASE="${2:-}"; shift 2 ;;
    --projeto) PROJ="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

MANIFEST="$GAD_SCRIPTS_DIR/manifests/etapa-$ETAPA.json"
[ -f "$MANIFEST" ] || { echo "ERRO: manifest inexistente para etapa \"$ETAPA\" ($MANIFEST)" >&2; exit 2; }
RUNLOG_ETAPA=$(jq -r '.runlog_etapa' "$MANIFEST")

ROOT="$(gad_project_root "${PROJ:-$PWD}")"
PONTEIRO="$ROOT/.planning/.gad-rodada-ativa.json"

# fase/NN/fase_dir: ponteiro da rodada > flags > descoberta no disco
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

# ── gate de contexto (Sub-rotina A absorvida) ────────────────────────────────
linha=$("$GAD_SCRIPTS_DIR/context-check.sh" 2>/dev/null || echo "tokens=0 limit=0 pct=0 status=unknown reason=context-check-falhou")
tokens=$(printf '%s' "$linha" | sed -n 's/.*tokens=\([0-9]*\).*/\1/p')
limite=$(printf '%s' "$linha" | sed -n 's/.*limit=\([0-9]*\).*/\1/p')
pct=$(printf '%s' "$linha"    | sed -n 's/.*pct=\([0-9]*\).*/\1/p')
status=$(printf '%s' "$linha" | sed -n 's/.*status=\([a-z]*\).*/\1/p')
reason=$(printf '%s' "$linha" | sed -n 's/.*reason=\(.*\)$/\1/p')

# ── janela de silêncio (S.I): 23h–07h local — fonte única em janela-silencio.sh ──
# Um só cálculo da regra. Enquanto eram dois independentes, um deles podia divergir em
# silêncio — o padrão que deixou a pergunta pendurada 5h52 na F24.4.
# Forma `if`, não `$(...; [ $? -eq 1 ])`: com `set -e` o comando falhando aborta a
# substituição antes do teste e devolveria string vazia. Exit 2 (uso inválido) cai no
# `else` como `null` (JSON válido, lido como "não medido" — não como `false`): este campo
# é informativo, e quem atua é o gate da Sub-rotina I, que chama o script direto.
silencio=null
JS="$GAD_SCRIPTS_DIR/janela-silencio.sh"
if [ -x "$JS" ]; then
  js_rc=0; "$JS" >/dev/null 2>&1 || js_rc=$?
  case "$js_rc" in 0) silencio=false ;; 1) silencio=true ;; esac
fi

# ── extras da etapa (declarados no manifest, executados aqui) ────────────────
extras="{}"
# gate condicionado a flag (4.A): sem a flag da rodada E sem o artefato-sinal → pular;
# sinal presente SEM a flag → sino de esquecimento (4.F: AI-SPEC órfã de --ai)
FLAG_NOME=$(jq -r '.pre.flag.nome // empty' "$MANIFEST")
if [ -n "$FLAG_NOME" ]; then
  FL=false
  [ -f "$PONTEIRO" ] && FL=$(jq -r ".args.$FLAG_NOME // false" "$PONTEIRO")
  SINAL=$(jq -r '.pre.flag.sinal // empty' "$MANIFEST" | sed "s|{fase}|$PHASE_DIR|; s|{nn}|$NN|")
  SINAL_EXISTE=false; [ -n "$SINAL" ] && [ -e "$SINAL" ] && SINAL_EXISTE=true
  if [ "$FL" != true ]; then
    if [ "$SINAL_EXISTE" = true ]; then
      extras=$(jq -cn --argjson prev "$extras" --arg f "$FLAG_NOME" --arg s "$SINAL" \
        '$prev + {sino_esquecimento: ("fase tem " + ($s|split("/")|last) + " mas a rodada veio sem --" + $f + " — o gate não vai rodar. Esquecimento?")}')
    else
      [ "$DRY" = 1 ] || gad_runlog "$PHASE_DIR" "$NN" skip "$RUNLOG_ETAPA (sem --$FLAG_NOME)"
      gad_json_out pre-despacho "$(jq -cn --arg e "$ETAPA" --arg f "$FLAG_NOME" \
        '{etapa:$e, despacho:"pular_flag", motivo:("gate condicionado a --" + $f + " — flag ausente e sem artefato-sinal")}')"
      exit 0
    fi
  fi
fi
# retomada por marcador (2.5-C: grep de frontmatter — artefato presente = etapa já feita)
RET_ARQ=$(jq -r '.pre.retomada.arquivo // empty' "$MANIFEST")
if [ -n "$RET_ARQ" ]; then
  RET_ARQ=$(printf '%s' "$RET_ARQ" | sed "s|{fase}|$PHASE_DIR|; s|{nn}|$NN|")
  RET_RE=$(jq -r '.pre.retomada.regex' "$MANIFEST")
  if [ -f "$RET_ARQ" ] && grep -qE "$RET_RE" "$RET_ARQ"; then
    gad_json_out pre-despacho "$(jq -cn --arg e "$ETAPA" \
      '{etapa:$e, despacho:"pular", motivo:"marcador de retomada presente — etapa já concluída em rodada anterior"}')"
    exit 0
  fi
fi
# gate de config (2.5-C: config off → skip declarado na origem, evento no run-log)
CFG_KEY=$(jq -r '.pre.config_gate // empty' "$MANIFEST")
if [ -n "$CFG_KEY" ]; then
  CFG_VAL=$(cd "$ROOT" && gsd_run query config-get "$CFG_KEY" 2>/dev/null | tr -d ' \n\r' || true)
  if [ "$CFG_VAL" = "false" ]; then
    [ "$DRY" = 1 ] || gad_runlog "$PHASE_DIR" "$NN" skip "$RUNLOG_ETAPA (config $CFG_KEY off)"
    gad_json_out pre-despacho "$(jq -cn --arg e "$ETAPA" --arg k "$CFG_KEY" \
      '{etapa:$e, despacho:"skip_config", motivo:("config " + $k + " = false — degradação declarada, siga sem despachar")}')"
    exit 0
  fi
fi
if [ "$(jq -r '.pre.revisores // false' "$MANIFEST")" = "true" ]; then
  cx=false; ag=false
  command -v codex >/dev/null 2>&1 && cx=true
  command -v agy   >/dev/null 2>&1 && ag=true
  extras=$(jq -cn --argjson cx "$cx" --argjson ag "$ag" \
    --argjson prev "$extras" '$prev + {revisores: {codex: $cx, agy: $ag}}')
  if [ "$cx" = false ] && [ "$ag" = false ]; then
    # PC-6: sem NENHUM revisor externo a fase não continua — fail-closed com pergunta
    resumo="bloqueio_sem_revisor: nenhum revisor externo instalado (codex, agy)"
    [ "$DRY" = 1 ] || gad_runlog "$PHASE_DIR" "$NN" script "$RUNLOG_ETAPA" \
      --kv script=pre-despacho.sh --kv exit=4 --kv resumo="$resumo"
    gad_json_out pre-despacho "$(jq -cn --arg e "$ETAPA" --argjson x "$extras" \
      '{etapa:$e, despacho:"bloqueio_sem_revisor",
        pergunta_ao_dono:"A consultoria especializada de intenção exige >=1 consultor externo (codex ou agy) e nenhum está instalado. Instalar um deles e continuar, ou abortar a fase?"} + $x')"
    exit 4
  fi
fi
if [ "$(jq -r '.pre.git_remote // false' "$MANIFEST")" = "true" ]; then
  gr=false
  [ -n "$(git -C "$ROOT" remote 2>/dev/null)" ] && gr=true
  extras=$(jq -cn --argjson gr "$gr" --argjson prev "$extras" '$prev + {git_remote: $gr}')
fi

# ── paralelismo (etapa 3, manifest `pre.paralelismo`) — o 18b do workflow vira dente ──
# Antes era prosa dirigida à camada 0, com um antídoto (`baseRef: head`) que o predicado do
# GSD ignorava; a serialização virava fato consumido dentro do gsd-execute-phase sem
# ninguém medir (F20, F24.x). Aqui o script lê as três fontes que decidem o paralelismo
# (config, isolamento + base-check, args) e bloqueia com exit 4 quando alguma delas nega.
PARALELISMO_ATIVO=0
if [ "$(jq -r '.pre.paralelismo // false' "$MANIFEST")" = "true" ]; then
  PARALELISMO_ATIVO=1
  bloqueia_par() { # $1 = motivo curto (chave=valor)  $2 = pergunta ao dono  $3 = JSON paralelismo
    resumo="bloqueio_paralelismo: $1"
    [ "$DRY" = 1 ] || gad_runlog "$PHASE_DIR" "$NN" script "$RUNLOG_ETAPA" \
      --kv script=pre-despacho.sh --kv exit=4 --kv paralelismo=bloqueio --kv resumo="$resumo"
    gad_json_out pre-despacho "$(jq -cn --arg e "$ETAPA" --arg m "$1" --arg q "$2" \
      --argjson par "$3" --argjson x "$extras" \
      '{etapa:$e, despacho:"bloqueio_paralelismo", motivo:$m, pergunta_ao_dono:$q, paralelismo:$par} + $x')"
    exit 4
  }
  # (1) config: workflow.use_worktrees e parallelization (objeto {enabled} ou booleano —
  # a mesma coerção do config-loader.cjs; `--raw` num objeto imprime "[object Object]")
  uw=$(cd "$ROOT" && gsd_run query config-get workflow.use_worktrees --raw 2>/dev/null | tr -d ' \n\r' || true)
  praw=$(cd "$ROOT" && gsd_run query config-get parallelization 2>/dev/null | tr -d ' \n\r' || true)
  # `has("enabled")`, não `.enabled // true`: o `//` do jq trata false como ausente
  pen=$(jq -r 'if type=="object" then (if has("enabled") then .enabled else true end) else . end' <<<"$praw" 2>/dev/null || printf '%s' "$praw")
  # (2) isolamento + base da cópia. `set-baseref` é no-clobber (só escreve se a chave não
  # existir ou já for "head"); registra no NN-DECISOES.md só quando mudou algo.
  ISO=$(cd "$ROOT" && gsd_run inspect-dispatch-isolation 2>/dev/null | tr -d ' \n\r' || true)
  : "${ISO:=desconhecido}"
  BASEREF_APLICADO=false; SD=null; MSG=""
  if [ "$ISO" = harness-worktree ] || [ "$ISO" = orchestrator-worktree ]; then
    if [ "$DRY" = 0 ] && [ "$ISO" = harness-worktree ]; then
      sb=$(cd "$ROOT" && gsd_run worktree set-baseref 2>/dev/null || echo '{}')
      if [ "$(jq -r '.changed // false' <<<"$sb" 2>/dev/null)" = true ]; then
        BASEREF_APLICADO=true
        DEC="$PHASE_DIR/$NN-DECISOES.md"
        grep -q 'baseRef: head aplicado pelo pre-despacho' "$DEC" 2>/dev/null || {
          printf '\n## Decisões automáticas da Etapa 3 (pré-despacho)\n\n- `[auto]` baseRef: head aplicado pelo pre-despacho.sh em `.claude/settings.local.json` (%s) — a cópia de cada executor parte do HEAD, não de origin/HEAD.\n  Desfazer: remover a chave `worktree.baseRef` do arquivo.\n' "$(date -Is)" >> "$DEC"; }
      fi
    fi
    SD=$(cd "$ROOT" && gsd_run worktree base-check --mode "$ISO" --pick shouldDegrade 2>/dev/null | tr -d ' \n\r' || true)
    case "$SD" in true|false) ;; *) SD=null ;; esac
    [ "$SD" = true ] && MSG=$(cd "$ROOT" && gsd_run worktree base-check --mode "$ISO" --pick message 2>/dev/null | tr -d '\r' || true)
  fi
  # ondas largas = ondas com >=2 planos ainda incompletos (é onde a serialização custa)
  IDX=$(cd "$ROOT" && gsd_run phase-plan-index "$FASE" --raw 2>/dev/null || echo '{}')
  jq -e . >/dev/null 2>&1 <<<"$IDX" || IDX='{}'
  ONDAS=$(jq -c '(.incomplete // []) as $inc
    | [ (.waves // {}) | to_entries[] | select(([.value[] | select(. as $p | $inc | index($p))] | length) >= 2) | .key ]' <<<"$IDX")
  # (3) args da rodada: `--interactive` serializa por desenho (execute-phase.md:243-249)
  INTERATIVO=false
  [ -f "$PONTEIRO" ] && jq -e '[.args // {} | .. | strings | select(test("--interactive"))] | length > 0' "$PONTEIRO" >/dev/null 2>&1 && INTERATIVO=true
  PAR=$(jq -cn --arg iso "$ISO" --argjson sd "$SD" --argjson ondas "$ONDAS" --arg uw "${uw:-desconhecido}" \
    --arg pen "${pen:-desconhecido}" --argjson ba "$BASEREF_APLICADO" --arg msg "$MSG" --argjson it "$INTERATIVO" \
    'def b: if .=="true" then true elif .=="false" then false else . end;
     {isolation:$iso, should_degrade:$sd, ondas_largas:$ondas, use_worktrees:($uw|b), parallelization:($pen|b),
      baseref_aplicado:$ba, interactive_nos_args:$it} + (if $msg != "" then {message:$msg} else {} end)')
  # espelho lido pelo confere-etapa.sh 3 (compara use_worktrees do início com o do fecho);
  # --dry-run não grava nada, como o resto do script
  [ "$DRY" = 1 ] || { mkdir -p "$ROOT/.planning/.gad"; jq -cn --arg ts "$(date -Is)" --argjson par "$PAR" \
    '{ts:$ts, use_worktrees:$par.use_worktrees, paralelismo:$par}' > "$ROOT/.planning/.gad/last-pre-despacho-3.json"; }
  if [ "$uw" = false ]; then
    bloqueia_par "workflow.use_worktrees=false" "workflow.use_worktrees está false: toda onda de >=2 planos rodaria em série. Religar (config-set workflow.use_worktrees true) e continuar, ou aceitar a serialização?" "$PAR"
  fi
  if [ "$pen" = false ]; then
    bloqueia_par "parallelization=false" "parallelization está false no config: o gsd-execute-phase serializa tudo. Religar e continuar, ou aceitar a serialização?" "$PAR"
  fi
  if [ "$INTERATIVO" = true ]; then
    bloqueia_par "args contêm --interactive" "Os args da rodada trazem --interactive, que executa os planos em série e ignora as ondas. Remover a bandeira (use --wave N para filtrar onda) ou aceitar a serialização?" "$PAR"
  fi
  if [ "$SD" = true ] && [ "$(jq 'length' <<<"$ONDAS")" -gt 0 ]; then
    bloqueia_par "should_degrade=true em onda(s) $(jq -r 'join(",")' <<<"$ONDAS")" "O base-check do GSD rebaixaria a(s) onda(s) $(jq -r 'join(",")' <<<"$ONDAS") para sequencial. Mensagem real: $MSG — Como proceder?" "$PAR"
  fi
  # (5) C1 (plano 4, 05/09): o portão de forma §13a-bis tem de ter passado NESTA fase. É ele que
  # reprova sobreposição de arquivos dentro da onda — o único estado que faz o execute-phase
  # serializar a onda inteira (`Running these plans sequentially…`). `last-plan-gate.json` é
  # singleton por .planning/.gad/: um `passed: true` da fase anterior liberaria a fase nova sem
  # portão, por isso `resumo.fase` tem de casar com a fase (comparados pelo sufixo numérico —
  # o índice diz "24.4", o ponteiro pode dizer "INS-24.4").
  PG="$ROOT/.planning/.gad/last-plan-gate.json"; PG_OK=false; PG_MOTIVO=""
  if [ ! -f "$PG" ]; then PG_MOTIVO="last-plan-gate.json ausente (o portão não rodou)"
  elif [ "$(jq -r '.passed // false' "$PG" 2>/dev/null)" != true ]; then PG_MOTIVO="last-plan-gate.json com passed=$(jq -r 'if has("passed") then (.passed|tostring) else "ilegível" end' "$PG" 2>/dev/null): $(jq -r '[.falhas[]?.codigo]|unique|join(",")' "$PG" 2>/dev/null)"
  else
    pg_fase=$(jq -r '.resumo.fase // ""' "$PG" 2>/dev/null | grep -oE '[0-9][0-9.]*$' || true)
    fase_num=$(printf '%s' "$FASE" | grep -oE '[0-9][0-9.]*$' || true)
    if [ -n "$pg_fase" ] && [ "$pg_fase" = "$fase_num" ]; then PG_OK=true; else PG_MOTIVO="last-plan-gate.json é da fase '$(jq -r '.resumo.fase // ""' "$PG")', não da $FASE"; fi
  fi
  PAR=$(jq -c --argjson ok "$PG_OK" --arg m "$PG_MOTIVO" '. + {plan_gate_ok:$ok} + (if $m != "" then {plan_gate_motivo:$m} else {} end)' <<<"$PAR")
  if [ "$PG_OK" != true ]; then
    bloqueia_par "plan_gate_ausente_ou_reprovado: $PG_MOTIVO" "O portão de forma dos planos não passou (ou não rodou) nesta fase — $PG_MOTIVO. Replanejar (rodar o plan-phase de novo até o §13a-bis passar), ou aceitar o despacho sabendo que a onda pode serializar?" "$PAR"
  fi
  if [ "$(jq 'length' <<<"$ONDAS")" -gt 0 ]; then :; else
    # C2 (plano 4): nenhuma onda com 2+ planos — a fase inteira roda em série. Não bloqueia (3 planos
    # encadeados por medição são legítimos, caso 08→09→10 da 24.4), mas toca o sino: incidente no
    # run-log e `sem_onda_larga: true` no espelho, para a régua e o dono verem.
    PAR=$(jq -c '. + {nota:"n/a (ondas de 1 plano)", sem_onda_larga:true}' <<<"$PAR")
    [ "$DRY" = 1 ] || gad_runlog "$PHASE_DIR" "$NN" incidente "$RUNLOG_ETAPA" --kv origem=pre-despacho.sh \
      --kv detalhe="nenhuma onda com 2+ planos — a fase inteira roda em série"
  fi
  extras=$(jq -cn --argjson prev "$extras" --argjson par "$PAR" '$prev + {paralelismo: $par}')
fi

# ── etapa 6: roteamento por baldes (6.1) + transparência mecânica (6.2) ──────
if [ "$ETAPA" = "6" ]; then
  UAT="$PHASE_DIR/$NN-UAT.md"
  cnt() { { grep -cE "$1" "$UAT" 2>/dev/null || true; } | head -1; }
  n_issue=$(cnt 'result: *issue'); n_pend=$(cnt 'result: *(\[pending\]|blocked|pending)')
  n_pass=$(cnt 'result: *pass'); n_assumed=$(cnt 'result: *assumed')
  NO_SHIP=false; [ -f "$PONTEIRO" ] && NO_SHIP=$(jq -r '.args.no_ship // false' "$PONTEIRO")
  if [ "${n_issue:-0}" -gt 0 ]; then ROTA=pausa
  elif [ "${n_pend:-0}" -gt 0 ] || [ "$NO_SHIP" = true ]; then ROTA=handback
  else ROTA=ship; fi
  # predicado nativo medido, colado no briefing do ship (a regra escrita furou na F21)
  UPRAW=$( (cd "$ROOT" && gsd_run phase uat-passed "$FASE" --raw 2>/dev/null || \
            gsd_run phase uat-passed "$FASE" 2>/dev/null) | head -c 2000 | tr -d '\n' || true )
  # transparência: 5 fontes extraídas mecanicamente — o modelo só redige
  # cada estágio protegido: sob pipefail, grep/awk sem match ou sem arquivo sai !=0
  # e o set -e mata o script logo após a atribuição
  b4=$({ grep -B2 'result: *assumed' "$UAT" 2>/dev/null || true; } \
       | { grep -vE '^--$|result:' || true; } | head -8 | jq -R . | jq -cs .)
  b3=$({ grep -B2 -E 'result: *(\[pending\]|blocked)' "$UAT" 2>/dev/null || true; } \
       | { grep -vE '^--$|result:' || true; } | head -8 | jq -R . | jq -cs .)
  itr=$({ awk '/^transparencia:/{f=1;next} f&&/^[a-z_]+:/{f=0} f&&/^ *- /{print}' \
        "$PHASE_DIR/$NN-INTENT-REVIEW.md" 2>/dev/null || true; } | head -8 | jq -R . | jq -cs .)
  sk=$({ grep '"evento":"skip"' "$PHASE_DIR/$NN-RUN-LOG.jsonl" 2>/dev/null || true; } \
       | { jq -c '.etapa' 2>/dev/null || true; } | head -8 | jq -cs .)
  ra=$({ awk '/^riscos_aceitos:/{f=1;next} f&&/^[a-z_]+:/{f=0} f&&/^ *- /{print}' \
       "$PHASE_DIR/$NN-SECURITY.md" 2>/dev/null || true; } | head -8 | jq -R . | jq -cs .)
  extras=$(jq -cn --argjson prev "$extras" --arg rota "$ROTA" --arg up "$UPRAW" \
    --argjson p "${n_pass:-0}" --argjson i "${n_issue:-0}" --argjson pe "${n_pend:-0}" --argjson a "${n_assumed:-0}" \
    --argjson b4 "$b4" --argjson b3 "$b3" --argjson itr "$itr" --argjson sk "$sk" --argjson ra "$ra" \
    '$prev + {rota:$rota, baldes:{pass:$p, issue:$i, pending:$pe, assumed:$a},
      uat_passed_raw:$up,
      transparencia:{balde_4:$b4, balde_3:$b3, intent_review:$itr, skips_runlog:$sk, riscos_aceitos:$ra}}')
fi

# ── política de limite (2.C) ─────────────────────────────────────────────────
if [ "$status" = "stop" ]; then
  handoff="Contexto em $((tokens/1000))k (teto $((limite/1000))k) — pausa graciosa. Retome numa sessão nova com: /go-and-do $FASE"
  if [ "$DRY" = 0 ]; then
    gad_runlog "$PHASE_DIR" "$NN" stop "$RUNLOG_ETAPA" \
      "$tokens" "$pct" "" "$limite" "" "contexto em $((tokens/1000))k"
    rm -f "$PONTEIRO"   # PC-3: rodada parada não arma mais o hook
  fi
  gad_json_out pre-despacho "$(jq -cn --arg e "$ETAPA" --arg h "$handoff" \
    --argjson t "${tokens:-0}" --argjson p "${pct:-0}" --argjson l "${limite:-0}" --argjson x "$extras" \
    '{etapa:$e, despacho:"stop", contexto:{tokens:$t,pct:$p,limit:$l,status:"stop"}, handoff:$h} + $x')"
  exit 3
fi

# ok (ou unknown declarado): abre a janela da etapa e autoriza o despacho
PAR_KV=(); [ "$PARALELISMO_ATIVO" = 1 ] && PAR_KV=(--kv paralelismo=ok)
[ "$DRY" = 1 ] || gad_runlog "$PHASE_DIR" "$NN" checkpoint "$RUNLOG_ETAPA" \
  "$tokens" "$pct" "" "$limite" --kv despacho=autorizado ${PAR_KV[@]+"${PAR_KV[@]}"}
gad_json_out pre-despacho "$(jq -cn --arg e "$ETAPA" --arg st "${status:-unknown}" --arg rz "$reason" \
  --arg pr "prompts" --argjson t "${tokens:-0}" --argjson p "${pct:-0}" --argjson l "${limite:-0}" \
  --argjson sil "$silencio" --argjson x "$extras" \
  '{etapa:$e, despacho:"ok",
    contexto:({tokens:$t,pct:$p,limit:$l,status:$st} + (if $rz != "" then {reason:$rz} else {} end)),
    janela_silencio:$sil} + $x')"
