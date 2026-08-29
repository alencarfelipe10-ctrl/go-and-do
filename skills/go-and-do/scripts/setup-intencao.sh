#!/usr/bin/env bash
# setup-intencao.sh — primeiro ato do coordenador de intenção (decisão 1.2).
#
# Irmão gêmeo, em granularidade fina, do if/else que o abre-rodada.sh mecanizou na
# camada 0: (a) higiene idempotente da flag de chain do discuss; (b) decisão de entrada
# pelo DISCO. O coordenador roda isto no primeiro turno e obedece o campo `entrada` —
# morre a classe "coordenador releu errado o estado e re-rodou o que estava pronto".
#
# Uso: setup-intencao.sh <phase_dir> <NN> [--com-resposta]
#      setup-intencao.sh <phase_dir> <NN> --pre-spec-route legacy|structured
#                        --resposta "<texto do dono>"   (grava a rota e devolve o setup)
#      setup-intencao.sh --r6 <phase_dir> <NN>          (só o bloco R6, SEM efeito colateral)
#
# Higiene: se NN-CONTEXT.md existe e a revisão não está done/skipped, roda
# `config-set workflow._auto_chain_active false` (zerar de novo é inócuo por design —
# um crash entre o discuss e o zeramento original deixaria a flag armada, e com ela o
# plan-phase encadearia direto pro execute, atropelando a revisão).
#
# `entrada` (ordem de precedência, tudo por existência/frontmatter — PC-2: um CONTEXT
# escrito à mão conta como pronto; o teste é existência, não autoria):
#   incorporar_resposta  — despacho veio com --com-resposta (continuação de pausa)
#   ja_pronto            — intent_review: done|skipped (idempotência: releia números e devolva)
#   reapresentar_pergunta— intent_review: needs_decision SEM resposta no despacho
#   revisao              — intent_review: blocked (re-tenta) OU spec+context prontos
#   spec                 — sem NN-SPEC.md
#   discuss              — sem NN-CONTEXT.md
#
# Também detecta NN-PRE-SPEC.md (campo `pre_spec`: insumo pré-travado pelo usuário —
# não muda a `entrada`, roteia o insumo aos filhos spec/discuss) e garante a pasta de
# trabalho .intent/ (decisão 1.5).
#
# ── ACRÉSCIMOS DA v2.2.0 (plano dos 27 ajustes da intenção) ────────────────────
# §0.5 ROTA DO PRE-SPEC (fail-closed). Com PRE-SPEC no disco, roda
#   `confere-pre-spec.sh --so-bloco` e emite `pre_spec_bloco: ok|ausente|invalido`.
#   `ausente|invalido` sem rota autorizada → `needs_decision` COM o texto do plano
#   (migrar via pre-spec-migra.py OU autorizar a rota antiga). Nunca "zero decisões em
#   silêncio". A resposta do dono vira estado durável em `.intent/pre-spec-route.json`
#   `{path, sha256, mode, resposta_dono, ts}`, relido nas chegadas seguintes; sha256
#   diferente do PRE-SPEC atual → a rota é invalidada e a pergunta volta.
#   `pre_spec_mode` (structured|legacy|null) vai explícito no resultado — o coordenador
#   repassa aos DOIS filhos; `legacy` acende `sino_pre_spec_sem_bloco` (obrigatório).
# R2. Com SPEC **e** PRE-SPEC no disco, roda `confere-pre-spec.sh <SPEC> <PRE-SPEC>` e
#   devolve `r2: {status, falhas[], avisos[]}` — as falhas (MARCA-SEM-ID, ID-INEXISTENTE,
#   …) reprovam no `confere-etapa.sh 1`; `EXTENSAO-SUSPEITA` é aviso que o coordenador
#   põe no briefing do revisor.
# R6. `goal_roadmap` (Goal da entrada da fase no ROADMAP) + `issues` estruturadas:
#   `{tipo: missing_requirement, id}` (id citado na linha **Requirements** da entrada e
#   ausente do REQUIREMENTS.md) e `{tipo: phase_without_req_id}` (entrada sem linha
#   Requirements, ou com uma que não cita id nenhum — "TBD (derivar na spec)").
#   Só a linha **Requirements** é lida: id citado em prosa (fora de escopo, débito,
#   AC-nn) NÃO é citação de requisito e não pode acender um gate.
# T3. Salvaguarda do blob-base: em `entrada: revisao`, sem `.intent/.base-<artefato>.txt`
#   e COM prova durável de que nenhuma revisão começou (sem `.intent/runs/`, sem
#   `.correcoes-c*`, sem `.done-c*`, e `git hash-object` do artefato == o marcador
#   `.gerado-<artefato>.txt` que o filho gravou na geração), grava a base com
#   `git hash-object -w`. Fora disso NÃO reconstrói: base tardia promoveria artefato já
#   corrigido a "original" e inflaria a métrica. `t3: [{artefato, status: gravado|
#   ja_existe|nao_medido|nao_aplicavel, blob, motivo}]`. `<artefato>` = SPEC | CONTEXT.
#
# Saída: JSON 1 linha + espelho PC-5. Exit 0 sempre que decidir; 2 = uso inválido.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

# ── modo --r6: só a extração do ROADMAP, sem tocar disco (o confere-etapa.sh 1 usa) ──
SO_R6=0
if [ "${1:-}" = "--r6" ]; then SO_R6=1; shift; fi

PD="${1:-}"; NN="${2:-}"; COM_RESPOSTA=0; ROTA_NOVA=""; RESPOSTA=""
[ -n "$PD" ] && [ -n "$NN" ] || { echo "uso: setup-intencao.sh [--r6] <phase_dir> <NN> [--com-resposta] [--pre-spec-route legacy|structured --resposta \"<texto>\"]" >&2; exit 2; }
shift 2
while [ $# -gt 0 ]; do case "$1" in
  --com-resposta)    COM_RESPOSTA=1; shift ;;
  --pre-spec-route)  ROTA_NOVA="${2:-}"; shift 2 ;;
  --resposta)        RESPOSTA="${2:-}"; shift 2 ;;
  *) echo "flag desconhecida: $1" >&2; exit 2 ;;
esac; done
[ -d "$PD" ] || { echo "ERRO: phase_dir inexistente: $PD" >&2; exit 2; }
case "$ROTA_NOVA" in ""|legacy|structured) ;; *)
  echo "ERRO: --pre-spec-route aceita 'legacy' ou 'structured' (veio: $ROTA_NOVA)" >&2; exit 2 ;;
esac
[ -z "$ROTA_NOVA" ] || [ -n "$RESPOSTA" ] || {
  echo "ERRO: --pre-spec-route exige --resposta \"<texto do dono>\" (a rota é decisão dele, não do coordenador)" >&2; exit 2; }

SPEC_F="$PD/$NN-SPEC.md"
CTX_F="$PD/$NN-CONTEXT.md"
PRE_SPEC=""
[ -f "$PD/$NN-PRE-SPEC.md" ] && PRE_SPEC="$PD/$NN-PRE-SPEC.md"

# ── raiz do projeto pela ÁRVORE (.planning/ROADMAP.md acima do phase_dir): a fase pode
# morar fora de repo git (bancada, fixture) e o gad_project_root cairia no próprio dir.
raiz_planning() {
  local d; d="$(CDPATH= cd -- "$1" && pwd -P)"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/.planning/ROADMAP.md" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname -- "$d")"
  done
  return 1
}

# ── R6: Goal + issues estruturadas da entrada da fase no ROADMAP ─────────────
r6_json() {
  local root rm rq
  root="$(raiz_planning "$PD" || true)"
  if [ -z "$root" ]; then
    printf '%s' '{"goal_roadmap":null,"issues":[],"requirements_line":null,"req_ids":[],"roadmap_entrada":false,"motivo":"ROADMAP.md não encontrado acima do phase_dir"}'
    return 0
  fi
  rm="$root/.planning/ROADMAP.md"; rq="$root/.planning/REQUIREMENTS.md"
  [ -f "$rq" ] || rq=""
  python3 - "$rm" "$rq" "$NN" <<'PY'
import json, re, sys
roadmap, reqs, nn = sys.argv[1], sys.argv[2], sys.argv[3]

linhas = open(roadmap, encoding="utf-8", errors="replace").read().split("\n")
# Entrada de detalhe da fase: heading em INGLÊS `### Phase <NN>` (o parser do GSD e o
# nosso leem o mesmo heading; "Fase" em pt-BR quebra os dois). O lookahead impede que
# a fase 24 case com a entrada da 24.3.
rx_ini = re.compile(r'^#{2,4}\s+Phase\s+' + re.escape(nn) + r'(?![\w.])', re.I)
rx_head = re.compile(r'^#{1,4}\s')
ini = None
for i, l in enumerate(linhas):
    if rx_ini.match(l):
        ini = i
        break
saida = {"goal_roadmap": None, "issues": [], "requirements_line": None, "req_ids": [],
         "roadmap_entrada": ini is not None}
if ini is None:
    saida["motivo"] = "nenhuma entrada `### Phase %s` no ROADMAP" % nn
    print(json.dumps(saida, ensure_ascii=False)); raise SystemExit(0)

fim = len(linhas)
for j in range(ini + 1, len(linhas)):
    if rx_head.match(linhas[j]):
        fim = j
        break
entrada = linhas[ini + 1:fim]

RX_GOAL = re.compile(r'^\*\*Goal[^:]*:\*{0,2}\s*(.*)$')
RX_REQ  = re.compile(r'^\*\*Requirements?[^:]*:\*{0,2}\s*(.*)$', re.I)
# Id de requisito: PREFIXO-sufixo com prefixo de 2+ maiúsculas (RESP-v3x-01, CANC-v3x-02,
# BOL-01, RESID-02, NF-01, CR-01, TF-03, DATA-15SEMBASE). Duas travas contra falso
# positivo — o `missing_requirement` é GATE, e gate que grita à toa é gate desligado:
#   · piso de 2 maiúsculas no prefixo → mata a família `D-nn`/`D-q90-05` (decisões/débitos);
#   · último segmento tem de conter dígito → mata `PRE-SPEC`, `MUST-NOT` e afins.
RX_ID   = re.compile(r'\b[A-Z]{2,}[A-Z0-9]*(?:-[A-Za-z0-9]+)+\b')

goal_aberto = False
for l in entrada:
    if saida["goal_roadmap"] is None or goal_aberto:
        m = RX_GOAL.match(l)
        if m and m.group(1).strip():
            saida["goal_roadmap"] = m.group(1).strip(); goal_aberto = True
        elif goal_aberto:
            # Goal quebrado em várias linhas: continua até linha em branco ou próximo
            # campo (`**Depends on:**`, `**Requirements**:` …). Sem isto, promessa do
            # Goal na 2ª linha sumiria em silêncio do "dentro ou fora" do spec.
            if not l.strip() or l.lstrip().startswith("**") or l.lstrip().startswith(("-", "|", ">")):
                goal_aberto = False
            else:
                saida["goal_roadmap"] += " " + l.strip()
    if saida["requirements_line"] is None:
        m = RX_REQ.match(l)
        if m:
            saida["requirements_line"] = m.group(1).strip()

ids = []
if saida["requirements_line"]:
    for m in RX_ID.finditer(saida["requirements_line"]):
        if not re.search(r'\d', m.group(0).rsplit("-", 1)[-1]):
            continue
        if m.group(0) not in ids:
            ids.append(m.group(0))
saida["req_ids"] = ids

if not ids:
    saida["issues"].append({"tipo": "phase_without_req_id"})
elif reqs:
    txt = open(reqs, encoding="utf-8", errors="replace").read()
    for i in ids:
        if not re.search(r'(?<![A-Za-z0-9-])' + re.escape(i) + r'(?![A-Za-z0-9-])', txt):
            saida["issues"].append({"tipo": "missing_requirement", "id": i})
else:
    for i in ids:
        saida["issues"].append({"tipo": "missing_requirement", "id": i})
    saida["motivo"] = "REQUIREMENTS.md ausente — todo id citado conta como ausente"

print(json.dumps(saida, ensure_ascii=False))
PY
}

if [ "$SO_R6" = 1 ]; then
  r6_json
  exit 0
fi

mkdir -p "$PD/.intent"

IR="$PD/$NN-INTENT-REVIEW.md"
ESTADO=""
[ -f "$IR" ] && ESTADO=$(grep -m1 '^intent_review:' "$IR" | sed 's/^intent_review: *//' | tr -d ' \r' || true)

# ── higiene idempotente da flag de chain ─────────────────────────────────────
CHAIN=nao_aplicavel
if [ -f "$CTX_F" ] && [ "$ESTADO" != "done" ] && [ "$ESTADO" != "skipped" ]; then
  ROOT="$(gad_project_root "$PD")"
  if (cd "$ROOT" && gsd_run query config-set workflow._auto_chain_active false >/dev/null 2>&1); then
    CHAIN=zerada
  else
    CHAIN=falhou   # declarado; a cancela do confere-etapa 1 barra na saída se armada
  fi
fi

# ── entrada fina pelo disco ──────────────────────────────────────────────────
if [ "$COM_RESPOSTA" = 1 ]; then          ENTRADA=incorporar_resposta
elif [ "$ESTADO" = done ] || [ "$ESTADO" = skipped ]; then ENTRADA=ja_pronto
elif [ "$ESTADO" = needs_decision ]; then ENTRADA=reapresentar_pergunta
elif [ "$ESTADO" = blocked ]; then        ENTRADA=revisao
elif [ ! -f "$SPEC_F" ]; then             ENTRADA=spec
elif [ ! -f "$CTX_F" ]; then              ENTRADA=discuss
else                                      ENTRADA=revisao
fi

CPS="$GAD_SCRIPTS_DIR/confere-pre-spec.sh"
ROTA_F="$PD/.intent/pre-spec-route.json"

# ══ §0.5 — rota do PRE-SPEC (fail-closed) ════════════════════════════════════
TEXTO_DECISAO='O PRE-SPEC não tem o bloco de decisões legível por máquina. Escolha: migrar o PRE-SPEC para o bloco (o `pre-spec-migra.py` gera um rascunho a partir da prosa para você revisar) OU autorizar a rota antiga (filho lê o arquivo inteiro, com sino `pre_spec_sem_bloco`).'

BLOCO=nao_aplicavel; MODO=null; NEEDS=null; SINO_LEGACY=false; ROTA_ESTADO=nao_aplicavel
SHA=""
if [ -n "$PRE_SPEC" ]; then
  SHA=$(sha256sum "$PRE_SPEC" | cut -d' ' -f1)
  BLOCO=erro
  if [ -f "$CPS" ]; then
    SAIDA_BLOCO=$(bash "$CPS" --so-bloco "$PRE_SPEC" 2>&1) || true
    B=$(printf '%s\n' "$SAIDA_BLOCO" | sed -n 's/^pre_spec_bloco: *//p' | tail -1)
    case "$B" in ok|ausente|invalido) BLOCO="$B" ;; *) BLOCO=erro ;; esac
  fi

  # rota gravada anteriormente ainda vale? (o hash do PRE-SPEC tem de bater)
  ROTA_MODO=""; ROTA_SHA=""
  if [ -f "$ROTA_F" ]; then
    ROTA_MODO=$(jq -r '.mode // empty' "$ROTA_F" 2>/dev/null || true)
    ROTA_SHA=$(jq -r '.sha256 // empty' "$ROTA_F" 2>/dev/null || true)
    if [ "$ROTA_SHA" = "$SHA" ]; then ROTA_ESTADO=valida; else ROTA_ESTADO=invalidada_por_hash; ROTA_MODO=""; fi
  else
    ROTA_ESTADO=ausente
  fi

  # gravação da resposta do dono (o coordenador chama com --pre-spec-route … --resposta …)
  if [ -n "$ROTA_NOVA" ]; then
    jq -n --arg p "$PRE_SPEC" --arg s "$SHA" --arg m "$ROTA_NOVA" --arg r "$RESPOSTA" \
      --arg t "$(date -Is)" \
      '{path:$p, sha256:$s, mode:$m, resposta_dono:$r, ts:$t}' > "$ROTA_F"
    ROTA_MODO="$ROTA_NOVA"; ROTA_ESTADO=gravada
  fi

  if [ "$BLOCO" = ok ]; then
    MODO='"structured"'
    # rota estruturada por conferência mecânica (o bloco está lá e é válido)
    if [ "$ROTA_MODO" != structured ]; then
      jq -n --arg p "$PRE_SPEC" --arg s "$SHA" \
        --arg r "${RESPOSTA:-bloco presente e válido — rota estruturada por conferência mecânica}" \
        --arg t "$(date -Is)" \
        '{path:$p, sha256:$s, mode:"structured", resposta_dono:$r, ts:$t}' > "$ROTA_F"
      ROTA_ESTADO=gravada
    fi
  elif [ "$ROTA_ESTADO" = valida ] || [ "$ROTA_ESTADO" = gravada ]; then
    case "$ROTA_MODO" in
      legacy)     MODO='"legacy"'; SINO_LEGACY=true ;;
      structured) # o dono mandou a estruturada e o bloco não está válido: fail-closed de novo
                  MODO=null
                  NEEDS=$(jq -cn --arg t "$TEXTO_DECISAO" --arg b "$BLOCO" \
                    '{motivo:("pre_spec_bloco: " + $b + " — a rota gravada diz `structured` e o bloco não está válido no disco"), texto:$t}') ;;
      *)          MODO=null
                  NEEDS=$(jq -cn --arg t "$TEXTO_DECISAO" --arg b "$BLOCO" \
                    '{motivo:("pre_spec_bloco: " + $b), texto:$t}') ;;
    esac
  else
    MODO=null
    NEEDS=$(jq -cn --arg t "$TEXTO_DECISAO" --arg b "$BLOCO" --arg r "$ROTA_ESTADO" \
      '{motivo:("pre_spec_bloco: " + $b + " · rota: " + $r), texto:$t}')
  fi
fi

# ══ R2 — SPEC × PRE-SPEC (mecânico) ══════════════════════════════════════════
R2='{"status":"nao_aplicavel","motivo":"exige NN-SPEC.md e NN-PRE-SPEC.md no disco","falhas":[],"avisos":[]}'
if [ -n "$PRE_SPEC" ] && [ -f "$SPEC_F" ] && [ -f "$CPS" ]; then
  RC=0; OUT2=$(bash "$CPS" "$SPEC_F" "$PRE_SPEC" 2>&1) || RC=$?
  FAL=$(printf '%s\n' "$OUT2" | { grep -E '^(MARCA-SEM-ID|ID-INEXISTENTE|FATO-SEM-EVIDENCIA|RESSALVA-SEM-LIMITACAO|AC-POR-PONTEIRO|BLOCO-AUSENTE|BLOCO-INVALIDO) ' || true; } | jq -R . | jq -cs .)
  AVI=$(printf '%s\n' "$OUT2" | { grep -E '^EXTENSAO-SUSPEITA ' || true; } | jq -R . | jq -cs .)
  case "$RC" in 0) ST=ok ;; 2) ST=bloco_invalido ;; *) ST=falha ;; esac
  R2=$(jq -cn --arg s "$ST" --argjson f "$FAL" --argjson a "$AVI" --argjson rc "$RC" \
    '{status:$s, exit:$rc, falhas:$f, avisos:$a}')
fi

# ══ T3 — salvaguarda do blob-base (só em entrada: revisao) ═══════════════════
t3_um() { # <rotulo SPEC|CONTEXT> <arquivo>  → JSON de um artefato
  local rot="$1" arq="$2" base="$PD/.intent/.base-$1.txt" ger="$PD/.intent/.gerado-$1.txt"
  local blob="" motivo="" st=""
  if [ ! -f "$arq" ]; then
    st=nao_aplicavel; motivo="$rot ainda não existe no disco"
  elif [ -f "$base" ]; then
    st=ja_existe; blob=$(tr -d ' \n\r' < "$base" || true)
  elif [ "$ENTRADA" != revisao ]; then
    st=nao_medido; motivo="salvaguarda só age em entrada: revisao (na geração a base é gravada pelo filho)"
  else
    local sujo="" g
    [ -d "$PD/.intent/runs" ] && sujo="já há .intent/runs/ (revisão começou)"
    if [ -z "$sujo" ]; then
      for g in "$PD/.intent/".correcoes-c* "$PD/".correcoes-c* "$PD/.intent/".done-c* "$PD/".done-c*; do
        [ -e "$g" ] && { sujo="marcador de ciclo no disco: $(basename "$g")"; break; }
      done
    fi
    if [ -n "$sujo" ]; then
      st=nao_medido; motivo="$sujo — base tardia promoveria artefato já corrigido a original"
    elif [ ! -f "$ger" ]; then
      st=nao_medido; motivo="sem marcador .gerado-$rot.txt (o filho não gravou na geração)"
    elif ! git -C "$PD" rev-parse --git-dir >/dev/null 2>&1; then
      st=nao_medido; motivo="phase_dir fora de repo git — hash-object -w indisponível"
    else
      local h m; h=$(git -C "$PD" hash-object -- "$arq" 2>/dev/null || true)
      m=$(tr -d ' \n\r' < "$ger" || true)
      if [ -n "$h" ] && [ "$h" = "$m" ]; then
        blob=$(git -C "$PD" hash-object -w -- "$arq" 2>/dev/null || true)
        if [ -n "$blob" ]; then printf '%s\n' "$blob" > "$base"; st=gravado
        else st=nao_medido; motivo="git hash-object -w falhou"; fi
      else
        st=nao_medido; motivo="artefato mudou desde a geração (hash != .gerado-$rot.txt)"
      fi
    fi
  fi
  jq -cn --arg a "$rot" --arg s "$st" --arg b "$blob" --arg m "$motivo" \
    '{artefato:$a, status:$s, blob:(if $b=="" then null else $b end), motivo:(if $m=="" then null else $m end)}'
}
T3=$(t3_um SPEC "$SPEC_F"; t3_um CONTEXT "$CTX_F")
T3=$(printf '%s' "$T3" | jq -cs .)

R6=$(r6_json)

gad_json_out setup-intencao "$(jq -cn --arg ch "$CHAIN" --arg e "$ENTRADA" --arg est "${ESTADO:-ausente}" \
  --arg ps "$PRE_SPEC" --arg bl "$BLOCO" --argjson md "$MODO" --argjson nd "$NEEDS" \
  --argjson sl "$SINO_LEGACY" --arg re "$ROTA_ESTADO" --arg rf "$ROTA_F" \
  --argjson r2 "$R2" --argjson t3 "$T3" --argjson r6 "$R6" \
  '{chain_flag_zerada:$ch, entrada:$e, intent_review:$est,
    pre_spec:(if $ps != "" then $ps else null end),
    pre_spec_bloco:$bl, pre_spec_mode:$md, pre_spec_rota:{estado:$re, arquivo:$rf},
    sino_pre_spec_sem_bloco:$sl, needs_decision:$nd,
    r2:$r2, t3:$t3,
    goal_roadmap:$r6.goal_roadmap, issues:$r6.issues,
    r6:{requirements_line:$r6.requirements_line, req_ids:($r6.req_ids // []),
        roadmap_entrada:$r6.roadmap_entrada, motivo:($r6.motivo // null)}}')"
