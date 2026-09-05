#!/usr/bin/env bash
# briefing-build.sh — monta o briefing dos consultores especializados de intenção (decisões 1.6/1.7/1.8/1.9).
#
# O briefing deixa de ser redigido pelo coordenador: das peças, só a varredura reversa
# (e, no ciclo 2+, o "o que mudou") é julgamento — o resto é montagem. A missão tem
# texto CANÔNICO num lugar só (impossível nascer uma whitelist improvisada como a que
# ancorou o consultor na F21) e a taxonomia vem de prompts/categorias-achados.md (mesma
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
#          ao consultor como pedido de confirmação (desde a v2.5.0, numa pergunta única —
#          ver R8 abaixo). Nenhum sino sai do briefing.
#   R8   → (1) seção "Perguntas dirigidas" com resposta estruturada obrigatória em
#          `## Respostas dirigidas` + manifesto `.intent/.perguntas-c<C>.json`;
#          (2) ROADMAP = SÓ a entrada da fase (antes: fase + vizinhas);
#          (3) lições saem do briefing (viraram checklist do intent-spec/intent-discuss);
#              as respostas do checklist chegam nos `.sinos-*.txt` como linhas
#              `licao <n>: aplicada|nao_se_aplica — porquê` e são DESVIADAS para
#              `.intent/.licoes-c<C>.txt` — nunca voltam ao briefing;
#          (4) ciclo >= 2: "o que mudou" logo após a Missão.
#
# v2.5.0 (consultoria especializada — plano 3 da F24.4, R1/R5/R7/R8/R9):
#   R1   → seção "Goal desta fase" (verbatim do `## Goal` do SPEC) e a Missão pede uma
#          linha de campo `vinculo_goal:` por achado (sem marcador de lista — o fallback do
#          `extrai_achados` do confere-ciclo.sh contaria um bullet com id `cN-NN`).
#   R5   → ciclo 1 ganha "Obrigação do ciclo 1" (SPEC × régua a montante, CONTEXT como
#          alvo, conjunto nomeado enumerado) e três perguntas dirigidas do montante.
#   R7   → `--mudancas` validado por FORMA: só `## O que corrigi` e `## Achados resolvidos`
#          entram; o resto é omitido com aviso `MUDANCAS-SECAO-FORA-DO-CONTRATO: <heading>`.
#   R8   → revalidação do ciclo 0 vira UMA pergunta (bloco único); a lista de sinos
#          corrigidos continua inteira; a frase "evidência = o diff do commit" saiu.
#   R9   → `valida_releitura` exige o veredito em disco quando `v: 2` (chaves `ciclo`,
#          `contradiz`, `prescreve_mecanismo`, `omissoes_novas`, `cardinalidade`,
#          `consistencia`, `ok`; `unicidade` no c0) e reprova `ok: false`; sem `v` = legado
#          com aviso nomeado (retrocompatibilidade da F24.4).
#
# Uso: briefing-build.sh <phase_dir> <NN> <ciclo> [--varredura ARQ] [--mudancas ARQ]
#   --varredura  arquivo com a seção "Asserções existentes que esta fase falsifica"
#                (escrita pelo coordenador — único insumo de modelo do ciclo 1)
#   --mudancas   ciclo 2+: DUAS seções e nada mais — `## O que corrigi` e
#                `## Achados resolvidos`; heading fora disso é omitido com aviso
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


def valida_veredito_releitura(rel, rotulo, ciclo):
    """R9 (plano 3) — o arquivo em disco é o objeto de retorno, não um recibo.

    `v: 2` → exige as chaves de veredito, com tipo, e `ok: false` reprova (a correção
    `c<C>b` não fechou). `v` ausente → legado: vale só `commit`/`artefatos`, com aviso
    nomeado — os `.releitura-c1/c2.json` de 235 B da F24.4 são o prompt antigo
    obedecido, não corrupção, e reprová-los travaria toda fase anterior.
    """
    v = rel.get("v")
    if v is None:
        info["avisos"].append(
            "releitura %s em formato legado (v ausente) — veredito não conferível" % ciclo)
        return
    if v != 2:
        die("%s: schema v=%s desconhecido (esperado v=2 ou ausente=legado)" % (rotulo, v))
    listas = ["contradiz", "prescreve_mecanismo", "omissoes_novas", "cardinalidade"]
    if str(ciclo) == "c0":
        listas.append("unicidade")
    faltando = [k for k in ["ciclo", *listas, "consistencia", "ok"] if k not in rel]
    if faltando:
        die("%s: chave obrigatória faltando: %s — a releitura v2 responde às perguntas "
            "em disco, não só no retorno" % (rotulo, ", ".join(faltando)))
    for k in listas:
        if not isinstance(rel[k], list):
            die("%s.%s não é lista" % (rotulo, k))
    if not isinstance(rel["ok"], bool):
        die("%s.ok não é booleano" % rotulo)
    if rel["ok"] is False:
        die("%s: a releitura do ciclo anterior reprovou (ok: false) e a correção do tipo "
            "`c<C>b` não fechou — corrija e despache uma releitura nova" % rotulo)


def valida_releitura(rel, aplicado, vazio, rotulo, ciclo):  # noqa: C901
    """rel = {commit, artefatos:[{path, blob}], (v:2 + veredito)}; amarra a commit + blobs."""
    exige_chaves(rel, ["commit", "artefatos"], rotulo)
    valida_veredito_releitura(rel, rotulo, ciclo)
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
            # as respostas do checklist de lições (R8(3)) e as linhas `leitura_propria:`
            # do discuss (evidência de auditoria, plano 2/C5) moram no mesmo arquivo e
            # NÃO são sinos — um arquivo só com elas não contradiz `sinos: []`.
            with open(p, encoding="utf-8", errors="replace") as fh:
                reais = [l for l in fh
                         if l.strip()
                         and not re.match(r"^\s*(licao \d+:|leitura_propria:)", l)]
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
    valida_releitura(z["releitura"], aplicado, False, "`.ciclo0.json`.releitura", "c0")

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
    paths = valida_releitura(rel, aplicado, tem_vaz, "`.releitura-c%d.json`" % prev,
                             "c%d" % prev)
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
# estável é o que dá sentido a "Q ausente vira bruto incerto". No ciclo 1 entram, nesta
# ordem, as três do montante (R5, plano 3) e UMA de revalidação do ciclo 0 (R8 do plano
# 3: bloco único — 13 perguntas de bênção renderam 25 ratificações e 1 achado na F24.4).
# Nenhum número de pergunta é escrito à mão: o `add_q` atribui e o texto interpola.
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

REVAL=()   # linhas "sino|origem|correcao_id" — a lista continua inteira (nenhum sino some)
QMONT1=""; QMONT2=""; QMONT3=""; QREVAL=""
if [ "$C" = 1 ]; then
  add_q montante_prespec;  QMONT1="${QIDS[${#QIDS[@]}-1]}"
  add_q montante_context;  QMONT2="${QIDS[${#QIDS[@]}-1]}"
  add_q montante_conjunto; QMONT3="${QIDS[${#QIDS[@]}-1]}"
  while IFS='|' read -r sid sorig sdisp scid; do
    [ -n "$sid" ] || continue
    case "$sid" in licao\ [0-9]*|licao[0-9]*) continue ;; esac
    [ "$sdisp" = corrigido ] || continue
    REVAL+=("$sid|$sorig|$scid")
  done < <(printf '%s' "$GATE_JSON" | jq -r '.sinos[]? | [.id,.origem,.disposicao,.correcao_id] | join("|")')
  if [ ${#REVAL[@]} -gt 0 ]; then
    # `ref` = os ids dos sinos unidos por `;` — campo de auditoria, ninguém o parseia
    add_q revalidacao_c0 "$(printf '%s\n' "${REVAL[@]}" | cut -d'|' -f1 | paste -sd';' -)"
    QREVAL="${QIDS[${#QIDS[@]}-1]}"
  fi
fi

# Goal da fase (R1, plano 3): o alvo de todo achado, verbatim da seção `## Goal` do SPEC
GOAL_TXT=""
if [ -f "$PD/$NN-SPEC.md" ]; then
  GOAL_INI=$(grep -n '^## Goal' "$PD/$NN-SPEC.md" | head -1 | cut -d: -f1 || true)
  [ -n "$GOAL_INI" ] && GOAL_TXT=$(awk -v s="$GOAL_INI" 'NR>s { if ($0 ~ /^## /) exit; print }' "$PD/$NN-SPEC.md")
fi
[ -n "$(printf '%s' "$GOAL_TXT" | tr -d '[:space:]')" ] \
  || AVISOS+=("SPEC sem seção \`## Goal\` — o briefing sai sem o alvo dos achados")

{
  echo "# Briefing da consultoria especializada de intenção — fase $NN, ciclo $C"
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
  echo "Não há número certo de achados — nenhum achado, de nenhuma categoria, é um resultado"
  echo "válido se a intenção estiver sólida. Cada achado com: alegação, evidência (arquivo:linha"
  echo "quando houver), confiança (alta/média/baixa) e uma linha de campo \`vinculo_goal:\`,"
  echo "sem marcador de lista, nomeando qual efeito medido do Goal (seção \"Goal desta fase\","
  echo "abaixo) fica em risco se o achado for ignorado — o trecho do Goal ou o \`AC-nn\` que o"
  echo "carrega. Forma: \`vinculo_goal: <efeito medido do Goal> (AC-nn)\`. Achado do tipo"
  echo "\"a fase deveria também fazer X\" é fora de alvo, a menos que X seja condição necessária"
  echo "para o que a fase promete. Não invente achado para preencher. Achado verdadeiro que você"
  echo "não consegue amarrar ao Goal entra assim mesmo, com \`vinculo_goal: nenhum\` — ele vira"
  echo "dívida registrada e segue para o planejamento; o que ele não faz é comprar mais um"
  echo "ciclo. Bug de código que morde em produção é sempre achado, com ou sem vínculo."
  echo "Sem achado novo, escreva literalmente \`### Achado 0 — nenhum achado novo\`: o contador só lê o gabarito, e um parecer só em prosa é devolvido para reformatação."
  echo
  # Ciclo 2+: "o que mudou" logo após a Missão (R8.4) — o consultor precisa do delta
  # ANTES de decidir onde gastar leitura, não num rodapé.
  # R7 (plano 3): o arquivo é validado por FORMA. Só entram as seções `## O que corrigi`
  # e `## Achados resolvidos`; heading fora da lista, ou texto antes do primeiro heading,
  # é omitido com aviso — no c3 da F24.4 o coordenador escreveu ali "o que ainda não foi
  # atacado", e dirigir o olhar do consultor é decidir o achado no lugar dele. Omitir em
  # vez de reprovar: um erro de redação do coordenador não deve travar o ciclo.
  if [ -n "$MUDANCAS" ] && [ -f "$MUDANCAS" ]; then
    MUD_RAW=$(awk '
      /^## / { sec=$0; sub(/[[:space:]]+$/, "", sec)
               keep=(sec=="## O que corrigi" || sec=="## Achados resolvidos")
               if (!keep) print "F\t" sec }
      sec=="" { if ($0 ~ /[^[:space:]]/ && !pre) { print "F\ttexto antes do primeiro heading"; pre=1 }; next }
      keep { print "K\t" $0 }
    ' "$MUDANCAS")
    while IFS= read -r h; do
      [ -n "$h" ] && AVISOS+=("MUDANCAS-SECAO-FORA-DO-CONTRATO: $h")
    done < <(printf '%s\n' "$MUD_RAW" | sed -n 's/^F\t//p')
    MUD_TXT=$(printf '%s\n' "$MUD_RAW" | sed -n 's/^K\t//p')
    if [ -n "$(printf '%s' "$MUD_TXT" | tr -d '[:space:]')" ]; then
      echo "## Ciclo $C — o que mudou desde o ciclo anterior (não repita o já resolvido)"
      echo
      printf '%s\n' "$MUD_TXT"
      echo
    else
      AVISOS+=("ciclo $C sem --mudancas: o briefing não diz o que mudou (arquivo inteiro fora do contrato: só \`## O que corrigi\` e \`## Achados resolvidos\` entram)")
    fi
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
  if [ -n "$(printf '%s' "$GOAL_TXT" | tr -d '[:space:]')" ]; then
    echo "## Goal desta fase (o alvo de todo achado)"
    echo
    printf '%s\n' "$GOAL_TXT"
    echo
    echo "Este é o efeito medido que a fase promete. Todo achado seu diz qual parte dele fica"
    echo "em risco se for ignorado — é isso que separa um achado de uma nota."
    echo
  fi
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
  # R5 (plano 3) — obrigação do ciclo 1: os documentos a montante são objeto, não
  # autoridade. Foi aqui que o AC-12 da F24.4 cairia: o PRE-SPEC proibia medir pelo Δ
  # agregado, o AC media por Δ agregado, e nenhum dos quatro ciclos cruzou os dois.
  if [ "$C" = 1 ]; then
    echo "## Obrigação do ciclo 1 — os documentos a montante são objeto"
    echo
    echo "Antes de procurar defeito novo, faça estas três conferências e responda a elas nas"
    echo "perguntas dirigidas $QMONT1, $QMONT2 e $QMONT3."
    echo
    if [ -f "$PD/$NN-PRE-SPEC.md" ]; then
      echo "1. **SPEC × régua do PRE-SPEC.** Para cada critério de aceite do SPEC, ache a régua"
      echo "   candidata correspondente no \`$PD/$NN-PRE-SPEC.md\` (Anexo A e itens \`PS-nn\`)."
      echo "   Critério que mede de um jeito que a régua candidata proíbe, sem uma linha de motivo"
      echo "   no SPEC, é achado — a régua pode ter sido superada, mas a superação tem de estar"
      echo "   escrita."
    else
      echo "1. **SPEC × REQUIREMENTS.** Para cada critério de aceite, ache o requisito \`REQ-*\` que"
      echo "   ele fecha em \`$ROOT/.planning/REQUIREMENTS.md\`. Critério sem requisito que o"
      echo "   sustente, ou requisito da fase que nenhum critério fecha, é achado."
    fi
    echo "2. **CONTEXT como alvo.** Leia o \`$PD/$NN-CONTEXT.md\` procurando decisão que contradiz"
    echo "   outra, decisão que o SPEC já superou e decisão que prescreve como implementar em vez"
    echo "   de dizer o que tem de ser verdade. O CONTEXT não é prova de nada: é mais um documento"
    echo "   sob revisão."
    echo "3. **Conjunto nomeado é conjunto enumerado.** Critério que fala de \"os 8 alunos\", \"as 4"
    echo "   escolas\" ou \"os 3 mecanismos\" exige, no documento, a lista com os elementos."
    echo "   Cardinalidade sem enumeração é achado: ninguém pode provar o critério."
    echo
    echo "A decisão marcada \`[pre-spec]\` continua tendo dono: não ataque a escolha do usuário;"
    echo "ataque o SPEC que não a honra, ou a consequência técnica dela."
    echo
  fi
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
  # Isso é evidência de auditoria, não insumo do consultor: despejá-lo aqui devolveria ao
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
  if [ "$C" = 1 ]; then
    echo "- **$QMONT1** (SPEC × régua a montante): existe critério de aceite que mede de um"
    echo "  jeito que a régua candidata do documento a montante proíbe, sem motivo registrado"
    echo "  no SPEC?"
    echo "- **$QMONT2** (CONTEXT como alvo): existe decisão do CONTEXT contraditória, superada"
    echo "  pelo SPEC ou que prescreve mecanismo em vez de comportamento?"
    echo "- **$QMONT3** (conjunto nomeado): existe critério que fala de um conjunto cujos"
    echo "  elementos o documento não enumera?"
  fi
  echo "- Resposta \`não\` a qualquer pergunta que só vale porque o ponto não toca o Goal:"
  echo "  escreva na forma \`não — irrelevante para o Goal: <o efeito medido que não é tocado>,"
  echo "  ver <AC-nn | R-n | arquivo:linha>\` — a palavra \`irrelevante\` sozinha é resposta vazia."
  if [ ${#REVAL[@]} -gt 0 ]; then
    echo
    echo "### Revalidação dirigida (ciclo 0)"
    echo
    echo "Antes deste ciclo o coordenador corrigiu os sinos abaixo, nos artefatos (commit"
    echo "registrado em \`$PD/.intent/.correcoes-c0.aplicado\`). Responda à pergunta"
    echo "**$QREVAL**: alguma dessas correções criou problema novo, ficou incompleta ou está"
    echo "errada? \`sim\` exige qual e a evidência; \`não\` exige o que você conferiu para dizer"
    echo "isso."
    echo
    for r in "${REVAL[@]}"; do
      IFS='|' read -r sid sorig scid <<< "$r"
      echo "- sino \`$sid\` (origem: $sorig) → correção \`$scid\`"
    done
    echo
    echo "- **$QREVAL** (revalidação do ciclo 0): alguma correção do ciclo 0 criou problema"
    echo "  novo, ficou incompleta ou está errada? \`sim\` exige qual e a evidência; \`não\`"
    echo "  exige o que você conferiu."
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
