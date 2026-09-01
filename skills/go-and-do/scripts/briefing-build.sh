#!/usr/bin/env bash
# briefing-build.sh — monta o briefing dos revisores adversariais (decisões 1.6/1.7/1.8/1.9).
#
# O briefing deixa de ser redigido pelo coordenador: das peças, só a varredura reversa
# (e, no ciclo 2+, o "o que mudou") é julgamento — o resto é montagem. A missão tem
# texto CANÔNICO num lugar só (impossível nascer uma whitelist improvisada como a que
# ancorou o revisor na F21) e a taxonomia vem de prompts/categorias-achados.md (mesma
# régua do verificador).
#
# v2.2.0 (ajustes da intenção — E2c, R1, R3, R8):
#   E2c/R1 GATE (exit 4, ANTES de qualquer escrita, inclusive do nonce):
#     C = 1  → exige `.intent/.ciclo0.json` (schema v:1, arrays explícitos) coerente
#              com `.correcoes-c0.aplicado` + `.releitura-c0.done`.
#     C >= 2 → exige `.correcoes-c<C-1>.aplicado` (ou `.correcoes-c<C-1>.vazio`) e
#              `.releitura-c<C-1>.json` válido, amarrado ao commit e aos blobs.
#     C1  → `hash` de correção tem de ser NÃO-VAZIO. Válvula: um `.aplicado` que traz
#           o campo `hash_ausente` pode listar ali os ids sem hash (ausência declarada,
#           passa); um `.aplicado` SEM esse campo é anterior ao conserto C1 (legado) e
#           passa com aviso — senão toda fase antiga travaria.
#   R3   → seção "Revalidação dirigida (ciclo 0)" no c1: cada correção do ciclo 0 volta
#          ao revisor como pedido de confirmação. Nenhum sino sai do briefing.
#   R8   → (1) seção "Perguntas dirigidas" com resposta estruturada obrigatória em
#          `## Respostas dirigidas` + manifesto `.intent/.perguntas-c<C>.json`;
#          (2) ROADMAP = SÓ a entrada da fase (antes: fase + vizinhas);
#          (3) lições saem do briefing (viraram checklist do intent-spec/intent-discuss);
#              as respostas do checklist chegam nos `.sinos-*.txt` como linhas
#              `licao <n>: aplicada|nao_se_aplica — porquê` e são DESVIADAS para
#              `.intent/.licoes-c<C>.txt` — nunca voltam ao briefing;
#          (4) ciclo >= 2: "o que mudou" logo após a Missão.
#
# Uso: briefing-build.sh <phase_dir> <NN> <ciclo> [--varredura ARQ] [--mudancas ARQ]
#   --varredura  arquivo com a seção "Asserções existentes que esta fase falsifica"
#                (escrita pelo coordenador — único insumo de modelo do ciclo 1)
#   --mudancas   ciclo 2+: o que mudou desde o ciclo anterior + achados já resolvidos
#
# Saída: JSON 1 linha + espelho PC-5. Exit 0 ok · 2 uso inválido · 4 gate reprovado.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/gsd-shim.sh"

PD="${1:-}"; NN="${2:-}"; C="${3:-}"
[ -n "$PD" ] && [ -n "$NN" ] && [ -n "$C" ] || { echo "uso: briefing-build.sh <phase_dir> <NN> <ciclo> [--varredura ARQ] [--mudancas ARQ]" >&2; exit 2; }
shift 3
VARREDURA=""; MUDANCAS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --varredura) VARREDURA="${2:-}"; shift 2 ;;
    --mudancas)  MUDANCAS="${2:-}"; shift 2 ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done
[ -d "$PD" ] || { echo "ERRO: phase_dir inexistente: $PD" >&2; exit 2; }
ROOT="$(gad_project_root "$PD")"
mkdir -p "$PD/.intent"
OUT="$PD/.intent/briefing-c$C.md"
AVISOS=()

# ── GATE E2c/R1 — antes de escrever qualquer coisa (nonce inclusive) ──────────
# Régua: o briefing do ciclo C só nasce se o ciclo anterior fechou o laço
# correção → commit → releitura, com os blobs conferidos contra o commit E contra o
# worktree atual (edição depois da releitura invalida a releitura).
GATE_JSON=$(GAD_PD="$PD" GAD_C="$C" GAD_ROOT="$ROOT" python3 - <<'PY'
import json, os, re, subprocess, sys

PD   = os.environ["GAD_PD"]
C    = os.environ["GAD_C"]
ROOT = os.environ["GAD_ROOT"]
IN   = os.path.join(PD, ".intent")

def die(msg):
    print(json.dumps({"ok": False, "erro": msg}, ensure_ascii=False))
    sys.exit(0)

def git(*a):
    r = subprocess.run(["git", "-C", ROOT, *a], capture_output=True, text=True)
    return r.returncode, r.stdout.strip(), r.stderr.strip()

def carrega(p, rotulo):
    if not os.path.exists(p):
        die("%s ausente: %s" % (rotulo, p))
    try:
        with open(p, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as e:
        die("%s ilegível (%s): %s" % (rotulo, p, e))

def exige_chaves(d, chaves, rotulo):
    if not isinstance(d, dict):
        die("%s não é um objeto JSON" % rotulo)
    faltando = [k for k in chaves if k not in d]
    if faltando:
        die("%s: chave(s) obrigatória(s) faltando: %s (array/objeto vazio tem de ser "
            "EXPLÍCITO — `{}` não basta)" % (rotulo, ", ".join(faltando)))

def valida_hashes(aplicado, sem_hash, rotulo, avisos):
    """C1 — `hash` vazio só passa quando a ausência foi DECLARADA.

    `sem_hash` = ids cujo `hash` é string vazia. A régua tem uma válvula, e a válvula
    é a PRESENÇA DA CHAVE `hash_ausente` no `.aplicado`:

    · chave ausente  → `.aplicado` gravado por um `correcoes-commit.sh` anterior ao
      conserto C1, que nunca teve como preencher o hash (o `--ids` mandava o
      placeholder `:<hash>`). É legado, não corrupção: aceita com aviso. Sem isso toda
      fase antiga — a F24.4 inteira, 58/58 entradas — passaria a travar.
    · chave presente (mesmo `[]`) → artefato do script novo, que preenche o hash
      sozinho. Aí um `hash` vazio fora de `hash_ausente[]` é corrupção → reprova.
    """
    if not sem_hash:
        return
    if aplicado is None or "hash_ausente" not in aplicado:
        avisos.append(
            "%s: %d correção(ões) com `hash` vazio num `.aplicado` sem campo "
            "`hash_ausente` — artefato anterior ao conserto C1, aceito como legado "
            "(%s)" % (rotulo, len(sem_hash), ", ".join(sorted(sem_hash))))
        return
    declarados = aplicado.get("hash_ausente") or []
    if not isinstance(declarados, list):
        die("`.aplicado`.hash_ausente não é lista")
    faltando = sorted(set(sem_hash) - set(declarados))
    if faltando:
        die("%s: correção(ões) com `hash` VAZIO e não declaradas em "
            "`.aplicado`.hash_ausente: %s — hash vazio declarado é ausência auditável; "
            "hash vazio silencioso é corrupção (C1)" % (rotulo, ", ".join(faltando)))
    avisos.append(
        "%s: %d correção(ões) sem hash, declaradas em `hash_ausente` (o ciclo tocou "
        "mais de um caminho e o id não disse qual)" % (rotulo, len(sem_hash)))


def valida_releitura(rel, aplicado, vazio, rotulo):  # noqa: C901
    """rel = {commit, artefatos:[{path, blob}]}; amarra a commit + blobs."""
    exige_chaves(rel, ["commit", "artefatos"], rotulo)
    arts = rel["artefatos"]
    if not isinstance(arts, list):
        die("%s.artefatos não é lista" % rotulo)
    paths = []
    for a in arts:
        if not isinstance(a, dict) or "path" not in a or "blob" not in a:
            die("%s.artefatos: item sem path/blob" % rotulo)
        paths.append(a["path"])
    if len(paths) != len(set(paths)):
        die("%s.artefatos: caminho duplicado" % rotulo)

    if vazio:
        if arts:
            die("%s: ciclo declarado vazio mas a releitura lista artefatos" % rotulo)
        return []
    if aplicado is None:
        if arts:
            die("%s: sem `.aplicado` correspondente, artefatos têm de ser []" % rotulo)
        return []

    exige_chaves(aplicado, ["commit", "caminhos"], "`.correcoes` aplicado")
    # dois hashes por caminho (E2 x R1): a releitura relê o COMMIT; o worktree pode
    # divergir dele por desenho quando o doc já estava sujo antes do ciclo.
    hashes = {b["path"]: b for b in (aplicado.get("blobs") or []) if isinstance(b, dict)}
    if rel["commit"] != aplicado["commit"]:
        die("%s.commit (%s) != commit do `.aplicado` (%s)"
            % (rotulo, rel["commit"], aplicado["commit"]))
    if set(paths) != set(aplicado["caminhos"]):
        die("%s: conjunto de caminhos != do `.aplicado` (releitura=%s · aplicado=%s)"
            % (rotulo, sorted(paths), sorted(aplicado["caminhos"])))

    commit = rel["commit"]
    for a in arts:
        p, b = a["path"], a["blob"]
        rc, out, _ = git("rev-parse", "%s:%s" % (commit, p))
        if rc != 0:
            die("%s: %s não existe no commit %s" % (rotulo, p, commit))
        if out != b:
            die("%s: blob de %s (%s) != o do commit %s (%s)" % (rotulo, p, b, commit, out))
        h = hashes.get(p)
        if h and h.get("blob_commit") and h["blob_commit"] != b:
            die("%s: blob relido de %s (%s) != blob_commit do `.aplicado` (%s)"
                % (rotulo, p, b, h["blob_commit"]))
        abs_p = p if os.path.isabs(p) else os.path.join(ROOT, p)
        if not os.path.exists(abs_p):
            die("%s: %s não existe no worktree" % (rotulo, p))
        rc, out, _ = git("hash-object", "--", abs_p)
        if rc != 0:
            die("%s: git hash-object falhou em %s" % (rotulo, p))
        esperado = h["blob_worktree"] if (h and h.get("blob_worktree")) else b
        if out != esperado:
            die("%s: %s foi EDITADO depois da releitura (worktree=%s != esperado=%s) — "
                "a releitura vale só para o estado relido" % (rotulo, p, out, esperado))
        if h and h.get("blob_worktree") and h["blob_worktree"] != h.get("blob_commit"):
            info["avisos"].append(
                "%s continua com a edição pré-ciclo do usuário no worktree (por desenho: "
                "o commit do ciclo levou só o delta do ciclo)" % p)
    return paths

info = {"ok": True, "gate": "c%s" % C, "avisos": [], "sinos": []}

if str(C) == "1":
    z = carrega(os.path.join(IN, ".ciclo0.json"), "`.intent/.ciclo0.json` (E2c)")
    exige_chaves(z, ["v", "sinos", "correcoes", "releitura"], "`.ciclo0.json`")
    if z["v"] != 1:
        die("`.ciclo0.json`: schema v=%s desconhecido (esperado v=1)" % z["v"])
    sinos, cors = z["sinos"], z["correcoes"]
    if not isinstance(sinos, list) or not isinstance(cors, list):
        die("`.ciclo0.json`: sinos e correcoes têm de ser listas")

    ids_cor = {}
    sem_hash = []          # ids com `hash` presente mas VAZIO (C1)
    for c in cors:
        if not isinstance(c, dict) or "id" not in c or "hash" not in c:
            die("`.ciclo0.json`.correcoes: item sem id/hash")
        if c["id"] in ids_cor:
            die("`.ciclo0.json`.correcoes: id duplicado %s" % c["id"])
        ids_cor[c["id"]] = c["hash"]
        if not str(c["hash"]).strip():
            sem_hash.append(c["id"])

    referenciados = set()
    for s in sinos:
        if not isinstance(s, dict):
            die("`.ciclo0.json`.sinos: item não é objeto")
        for k in ("id", "origem", "disposicao"):
            if k not in s:
                die("`.ciclo0.json`.sinos: item sem `%s`" % k)
        if s["origem"] not in ("spec", "discuss"):
            die("sino %s: origem `%s` inválida (spec|discuss)" % (s["id"], s["origem"]))
        if s["disposicao"] not in ("corrigido", "descartado", "aberto"):
            die("sino %s: disposicao `%s` inválida" % (s["id"], s["disposicao"]))
        if s["disposicao"] == "corrigido":
            cid = s.get("correcao_id")
            if not cid:
                die("sino %s: `corrigido` exige exatamente um `correcao_id`" % s["id"])
            if cid not in ids_cor:
                die("sino %s: correcao_id `%s` não existe em correcoes[]" % (s["id"], cid))
            referenciados.add(cid)
        elif "correcao_id" in s:
            die("sino %s: `%s` proíbe o campo `correcao_id`" % (s["id"], s["disposicao"]))
    orfas = sorted(set(ids_cor) - referenciados)
    if orfas:
        die("`.ciclo0.json`.correcoes sem sino que as referencie: %s" % ", ".join(orfas))

    # Guarda anti-cegueira: `sinos: []` com sinos reais no disco esconderia R3.
    if not sinos:
        for nome in (".sinos-spec.txt", ".sinos-discuss.txt"):
            p = os.path.join(IN, nome)
            if not os.path.exists(p):
                continue
            # as respostas do checklist de lições (R8(3)) moram no mesmo arquivo e NÃO
            # são sinos — um arquivo só com elas não contradiz `sinos: []`.
            with open(p, encoding="utf-8", errors="replace") as fh:
                reais = [l for l in fh
                         if l.strip() and not re.match(r"^\s*licao \d+:", l)]
            if reais:
                die("`.ciclo0.json`.sinos=[] mas %s tem sino real — sino sumindo (R3)" % nome)

    aplicado = None
    if cors:
        aplicado = carrega(os.path.join(IN, ".correcoes-c0.aplicado"),
                           "`.intent/.correcoes-c0.aplicado` (E2c)")
        exige_chaves(aplicado, ["commit", "caminhos", "correcoes"], "`.correcoes-c0.aplicado`")
        par_z = sorted((c["id"], c["hash"]) for c in cors)
        par_a = sorted((c.get("id"), c.get("hash")) for c in aplicado["correcoes"])
        if par_z != par_a:
            die("`.ciclo0.json`.correcoes %s != `.aplicado`.correcoes %s" % (par_z, par_a))
    # C1: o veredito da válvula vem AQUI — logo depois de carregar o `.aplicado` e
    # ANTES da releitura. Assim "hash vazio" nunca se disfarça de erro de releitura.
    valida_hashes(aplicado, sem_hash, "`.ciclo0.json`.correcoes", info["avisos"])
    valida_releitura(z["releitura"], aplicado, False, "`.ciclo0.json`.releitura")

    if not os.path.exists(os.path.join(IN, ".releitura-c0.done")):
        die("`.intent/.releitura-c0.done` ausente (R1: a releitura do ciclo 0 não fechou)")

    info["ciclo0_vazio"] = not cors
    info["sinos"] = [
        {"id": s["id"], "origem": s["origem"], "disposicao": s["disposicao"],
         "correcao_id": s.get("correcao_id", "")}
        for s in sinos
    ]
    info["correcoes"] = [{"id": k, "hash": v} for k, v in ids_cor.items()]
    if not cors:
        info["avisos"].append("ciclo 0 declarou 0 correções (arrays vazios explícitos)")

else:
    try:
        prev = int(str(C)) - 1
    except ValueError:
        die("ciclo `%s` não é numérico — o gate C>=2 não sabe qual é o anterior" % C)
    ap_p  = os.path.join(IN, ".correcoes-c%d.aplicado" % prev)
    vaz_p = os.path.join(IN, ".correcoes-c%d.vazio" % prev)
    tem_ap, tem_vaz = os.path.exists(ap_p), os.path.exists(vaz_p)
    if not tem_ap and not tem_vaz:
        die("nem `.correcoes-c%d.aplicado` nem `.correcoes-c%d.vazio` — o ciclo %d não "
            "fechou o commit de correções (E2c)" % (prev, prev, prev))
    if tem_ap and tem_vaz:
        die("`.correcoes-c%d.aplicado` E `.correcoes-c%d.vazio` coexistem — estado ambíguo"
            % (prev, prev))
    aplicado = carrega(ap_p, "`.correcoes-c%d.aplicado`" % prev) if tem_ap else None
    if aplicado is not None:
        # mesma régua do ciclo 0, mesma válvula — aqui a fonte dos ids é o próprio
        # `.aplicado` (não há `.ciclo0.json` para os ciclos >= 2)
        sem_hash_ap = [c.get("id") for c in (aplicado.get("correcoes") or [])
                       if isinstance(c, dict) and not str(c.get("hash", "")).strip()]
        valida_hashes(aplicado, sem_hash_ap,
                      "`.correcoes-c%d.aplicado`.correcoes" % prev, info["avisos"])
    rel = carrega(os.path.join(IN, ".releitura-c%d.json" % prev),
                  "`.intent/.releitura-c%d.json` (R1)" % prev)
    paths = valida_releitura(rel, aplicado, tem_vaz, "`.releitura-c%d.json`" % prev)
    info["ciclo_anterior"] = prev
    info["correcoes_vazio"] = tem_vaz
    info["artefatos_relidos"] = paths
    if tem_vaz:
        info["avisos"].append("ciclo %d declarado SEM correções (`.vazio`)" % prev)

print(json.dumps(info, ensure_ascii=False))
PY
)
if [ "$(printf '%s' "$GATE_JSON" | jq -r '.ok')" != "true" ]; then
  echo "GATE-INTENCAO c$C reprovado: $(printf '%s' "$GATE_JSON" | jq -r '.erro')" >&2
  exit 4
fi
mapfile -t GATE_AV < <(printf '%s' "$GATE_JSON" | jq -r '.avisos[]?')
AVISOS+=(${GATE_AV[@]+"${GATE_AV[@]}"})

# ── canário de leitura: nonce nasce aqui, só no arquivo ──────────────────────
PROVA="$PD/.intent/.prova-leitura-c$C.txt"
NONCE="PROVA-$(od -An -N3 -tx1 /dev/urandom | tr -d ' ')"
echo "Token de prova de leitura do ciclo $C: $NONCE" > "$PROVA"

# ── perguntas dirigidas (R8): Q1–Q3 são canônicas e SEMPRE existem — manifesto
# estável é o que dá sentido a "Q ausente vira bruto incerto". A revalidação do
# ciclo 0 (R3) entra a partir de Q4.
QIDS=(); QTIPO=(); QREF=()
add_q() { QIDS+=("Q$(( ${#QIDS[@]} + 1 ))"); QTIPO+=("$1"); QREF+=("${2:-}"); }
add_q varredura
add_q enumeracao_reversa
add_q raio_de_explosao
# R8(3): as respostas do checklist de lições que os filhos gravam nos `.sinos-*.txt`
# (linha ASCII `licao <n>: aplicada|nao_se_aplica — porquê`) NÃO voltam ao briefing —
# elas saíram dele de propósito. Vão para cá, como evidência de auditoria.
LICOES="$PD/.intent/.licoes-c$C.txt"
: > "$LICOES"

REVAL=()   # linhas "qid|sino|origem|correcao_id"
if [ "$C" = 1 ]; then
  while IFS='|' read -r sid sorig sdisp scid; do
    [ -n "$sid" ] || continue
    case "$sid" in licao\ [0-9]*|licao[0-9]*) continue ;; esac
    [ "$sdisp" = corrigido ] || continue
    add_q revalidacao_c0 "$sid"
    REVAL+=("${QIDS[${#QIDS[@]}-1]}|$sid|$sorig|$scid")
  done < <(printf '%s' "$GATE_JSON" | jq -r '.sinos[]? | [.id,.origem,.disposicao,.correcao_id] | join("|")')
fi

{
  echo "# Briefing da revisão adversarial de intenção — fase $NN, ciclo $C"
  echo
  echo "## Missão"
  echo
  echo "Leia os artefatos E o código real e tente derrubar as decisões desta fase."
  echo "Seu tempo de leitura é finito — gaste-o na ordem: (1º) o que faria o software"
  echo "errar em produção, trair um requisito ou abrir/deixar aberta uma brecha de"
  echo "segurança [Produto]; (2º) o que faria a execução da fase falhar ou exigir"
  echo "retrabalho [Viabilidade]; (3º) o resto. Reporte todo achado que encontrar,"
  echo "inclusive incertos — mas classifique cada um: \`A-produto\`, \`B-viabilidade\`,"
  echo "\`C-instrumentacao\`, \`D-documental\`, \`E-decisao-do-dono\` (marque a categoria"
  echo "no título do achado, ex.: \`### Achado 3 [A-produto] — ...\`). Achados C e D da"
  echo "mesma classe de erro: reporte como UM item de classe com a lista de ocorrências."
  echo "Não há número certo de achados — zero achados A é um resultado válido se a"
  echo "intenção estiver sólida. Cada achado com: alegação, evidência (arquivo:linha"
  echo "quando houver) e confiança (alta/média/baixa)."
  echo
  # Ciclo 2+: "o que mudou" logo após a Missão (R8.4) — o revisor precisa do delta
  # ANTES de decidir onde gastar leitura, não num rodapé.
  if [ -n "$MUDANCAS" ] && [ -f "$MUDANCAS" ]; then
    echo "## Ciclo $C — o que mudou desde o ciclo anterior (não repita o já resolvido)"
    echo
    cat "$MUDANCAS"
    echo
  elif [ "$C" != 1 ]; then
    AVISOS+=("ciclo $C sem --mudancas: o briefing não diz o que mudou")
  fi
  cat "$GAD_SCRIPTS_DIR/../prompts/categorias-achados.md" 2>/dev/null \
    || AVISOS+=("categorias-achados.md ausente")
  echo
  echo "## Prova de leitura (obrigatória)"
  echo
  echo "Abra \`$PROVA\` e transcreva o token dele na primeira linha do parecer, no"
  echo "formato \`prova_leitura: <token>\`."
  echo
  echo "## Artefatos (leia dos caminhos — qualquer arquivo do repositório é elegível)"
  echo
  echo "- \`$PD/$NN-SPEC.md\`"
  echo "- \`$PD/$NN-CONTEXT.md\`"
  if [ -f "$PD/$NN-PRE-SPEC.md" ]; then
    echo "- \`$PD/$NN-PRE-SPEC.md\` — decisões PRÉ-TRAVADAS pelo usuário numa sessão"
    echo "  interativa anterior. Decisão marcada \`[pre-spec]\` nos artefatos tem dono:"
    echo "  não a ataque como \"decisão não justificada\" — ataque, se for o caso, a"
    echo "  consequência técnica dela."
  fi
  [ -f "$ROOT/.planning/REQUIREMENTS.md" ] && echo "- \`$ROOT/.planning/REQUIREMENTS.md\`"
  echo "- Repositório sob revisão: \`$ROOT\`"
  echo
  # ROADMAP: SÓ a entrada da fase (R8.2 — antes vinham as vizinhas junto)
  RM="$ROOT/.planning/ROADMAP.md"
  if [ -f "$RM" ]; then
    mapfile -t H < <(grep -n '^### Phase ' "$RM" | cut -d: -f1)
    ALVO=$(grep -n "^### Phase ${NN#0}[:.]" "$RM" | head -1 | cut -d: -f1 || true)
    [ -z "$ALVO" ] && ALVO=$(grep -n "^### Phase $NN[:.]" "$RM" | head -1 | cut -d: -f1 || true)
    if [ -n "$ALVO" ]; then
      echo "## Trecho do ROADMAP (entrada desta fase)"
      echo
      ini=$ALVO; fim=$(wc -l < "$RM")
      for i in "${!H[@]}"; do
        if [ "${H[$i]}" = "$ALVO" ]; then
          [ $((i+1)) -lt ${#H[@]} ] && fim=$(( ${H[$((i+1))]} - 1 ))
          break
        fi
      done
      sed -n "${ini},${fim}p" "$RM"
      echo
    else
      AVISOS+=("fase $NN não achada no ROADMAP — trecho omitido")
    fi
  fi
  # Livro-razão mecânico: enumeração 1:1 das decisões [auto] e [pre-spec]
  echo "## Livro-razão de decisões automáticas e pré-travadas (enumeração mecânica 1:1)"
  echo
  n_auto=0
  for f in "$PD/$NN-SPEC.md" "$PD/$NN-CONTEXT.md"; do
    [ -f "$f" ] || continue
    while IFS= read -r l; do
      echo "- \`$(basename "$f"):${l%%:*}\` — ${l#*:}"
      n_auto=$((n_auto+1))
    done < <(grep -n '\[auto\]\|\[pre-spec\]' "$f" || true)
  done
  [ "$n_auto" = 0 ] && echo "*(nenhuma linha \`[auto]\`/\`[pre-spec]\` nos artefatos)*"
  echo
  # Varredura reversa (insumo de modelo)
  if [ -n "$VARREDURA" ] && [ -f "$VARREDURA" ]; then
    echo "## Asserções existentes que esta fase falsifica (varredura reversa)"
    echo
    cat "$VARREDURA"
    echo
  else
    AVISOS+=("varredura reversa ausente do briefing")
  fi
  # Sinos dos filhos (lidos do disco — 1.5). R8(3): o checklist de lições que o filho
  # responde vive no MESMO arquivo de sinos (`licao <n>: aplicada|nao_se_aplica — …`).
  # Isso é evidência de auditoria, não insumo do revisor: despejá-lo aqui devolveria ao
  # briefing exatamente o que o R8(3) tirou dele. Nenhum SINO é filtrado.
  for s in "$PD/.intent/".sinos-*.txt; do
    [ -f "$s" ] || continue
    FONTE=$(basename "$s" | sed 's/^\.sinos-//; s/\.txt$//')
    grep -aE '^[[:space:]]*licao [0-9]+:' "$s" \
      | sed -E "s|^[[:space:]]*|$FONTE \| |" >> "$LICOES" || true
    RESTO=$(grep -avE '^[[:space:]]*licao [0-9]+:' "$s" || true)
    [ -n "$(printf '%s' "$RESTO" | tr -d '[:space:]')" ] || continue
    echo "## Sinos de $FONTE"
    echo
    printf '%s\n' "$RESTO"
    echo
  done
  # R3 — ciclo 1: sino do ciclo 0 que NÃO virou correção continua visível.
  if [ "$C" = 1 ]; then
    NCOR=$(printf '%s' "$GATE_JSON" | jq -r '[.sinos[]? | select(.disposicao!="corrigido")
      | select(.id | test("^licao ?[0-9]") | not)] | length')
    if [ "${NCOR:-0}" -gt 0 ]; then
      echo "## Sinos do ciclo 0 não corrigidos (contexto — seguem sendo alvo)"
      echo
      printf '%s' "$GATE_JSON" | jq -r '.sinos[]? | select(.disposicao!="corrigido")
        | select(.id | test("^licao ?[0-9]") | not)
        | "- `" + .id + "` (" + .origem + ") — " + .disposicao'
      echo
    fi
  fi
  # ── Perguntas dirigidas (R8.1) ──────────────────────────────────────────────
  echo "## Perguntas dirigidas"
  echo
  echo "Responda a TODAS as perguntas abaixo numa seção \`## Respostas dirigidas\` do"
  echo "parecer, uma linha por pergunta, EXATAMENTE neste formato:"
  echo
  echo '```'
  echo "- Q<n>: sim|não|incerto — evidência"
  echo '```'
  echo
  echo "\`sim\` e \`incerto\` contam como achado bruto do ciclo (é assim que a pergunta"
  echo "vira sinal, não conversa). \`não\` só sai da contagem com evidência que sustente"
  echo "a exclusão — \"não\", \"N/A\" ou reticências viram \`incerto\`. Responder no corpo"
  echo "do parecer NÃO substitui a linha: sem a linha, a pergunta conta como \`incerto\`."
  echo "Isto não limita seu parecer — ache o que mais houver, dirigido ou não."
  echo
  echo "- **Q1** (varredura): a varredura reversa acima está incompleta ou errada —"
  echo "  existe asserção que esta fase falsifica e que ela não lista?"
  echo "- **Q2** (enumeração reversa): existe asserção no repositório que as mudanças"
  echo "  prescritas tornam falsa ou insatisfazível, inclusive em arquivos que os"
  echo "  artefatos não citam? Qualquer lista de arquivos neste briefing é ponto de"
  echo "  partida, não fronteira."
  echo "- **Q3** (raio de explosão): a intenção subestima o raio de explosão real — o"
  echo "  que ela toca de compartilhado, que contrato cria ou muda, o que não tem"
  echo "  análogo no código, quem depende dela nas fases seguintes?"
  if [ ${#REVAL[@]} -gt 0 ]; then
    echo
    echo "### Revalidação dirigida (ciclo 0)"
    echo
    echo "O coordenador já corrigiu, antes deste ciclo, os sinos abaixo. Para cada um:"
    echo "**confirme ou derrube** — \`sim\` = a correção está errada, incompleta ou criou"
    echo "problema novo."
    echo
    for r in "${REVAL[@]}"; do
      IFS='|' read -r q sid sorig scid <<< "$r"
      echo "- **$q** (revalidação c0): sino \`$sid\` (origem: $sorig) → correção \`$scid\`"
      echo "  aplicada nos artefatos; evidência = o diff do commit do ciclo 0 registrado"
      echo "  em \`$PD/.intent/.correcoes-c0.aplicado\`. A correção resolveu o sino?"
    done
  fi
} > "$OUT"

# Manifesto de completude das perguntas (R8.3) — insumo do confere-ciclo.sh --perguntas
MAN="$PD/.intent/.perguntas-c$C.json"
{
  printf '{"v":1,"ciclo":"%s","qids":[' "$C"
  for i in "${!QIDS[@]}"; do [ "$i" = 0 ] || printf ','; printf '"%s"' "${QIDS[$i]}"; done
  printf '],"detalhe":['
  for i in "${!QIDS[@]}"; do
    [ "$i" = 0 ] || printf ','
    printf '{"qid":"%s","tipo":"%s","ref":"%s"}' "${QIDS[$i]}" "${QTIPO[$i]}" "${QREF[$i]}"
  done
  printf ']}\n'
} | jq -c . > "$MAN.tmp" && mv -f "$MAN.tmp" "$MAN"

NLIC=$(wc -l < "$LICOES" | tr -d ' ')
[ "$NLIC" = 0 ] && rm -f "$LICOES" && LICOES=""

AV_JSON=$(printf '%s\n' ${AVISOS[@]+"${AVISOS[@]}"} | jq -R . | jq -cs 'map(select(length>0))')
gad_json_out briefing-build "$(jq -cn --arg b "$OUT" --arg p "$PROVA" --arg m "$MAN" \
  --arg lic "$LICOES" --argjson nlic "$NLIC" \
  --argjson na "$n_auto" --argjson lin "$(wc -l < "$OUT")" --argjson av "$AV_JSON" \
  --argjson nq "${#QIDS[@]}" --argjson g "$GATE_JSON" \
  '{briefing:$b, prova_leitura:$p, perguntas:$m, perguntas_total:$nq,
    licoes: (if $lic == "" then null else $lic end), licoes_respostas:$nlic,
    decisoes_auto:$na, linhas:$lin, avisos:$av, gate:$g}')"
