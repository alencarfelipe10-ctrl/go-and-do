#!/usr/bin/env bash
# confere-pre-spec.sh — conferência mecânica do contrato PRE-SPEC ↔ SPEC (R2 · R7 · S4 · §0.5).
#
# Uso:
#   confere-pre-spec.sh [--exige-origem] [--reqs REQUIREMENTS.md] <NN-SPEC.md> <NN-PRE-SPEC.md>
#   confere-pre-spec.sh --so-bloco <NN-PRE-SPEC.md>
#   confere-pre-spec.sh --sem-pre-spec [--exige-origem] [--reqs REQUIREMENTS.md] <NN-SPEC.md>
#
# Modo sem pré-spec (D7c): fase sem NN-PRE-SPEC.md (SPEC do dono, ou gerado sem insumo). O
# SPEC passa pelas conferências de forma que só existiam com PRE-SPEC — AC-POR-PONTEIRO,
# AC-SEM-ORIGEM, AC-ORIGEM-INEXISTENTE (R-n/SC-n/REQ-ID contra o `--reqs`) e os sinos de
# classe. Origem ou marca `PS-nn` vira AC-ORIGEM-INEXISTENTE / ID-INEXISTENTE com a mensagem
# «a fase não tem PRE-SPEC» (mesma família de código: o confere-etapa.sh grepa a família).
# RESSALVA-SEM-LIMITACAO e EXTENSAO-SUSPEITA não se aplicam. O resumo traz `modo=sem-pre-spec`.
#
# O bloco de decisões vive no PRE-SPEC entre os marcadores
#   <!-- gad:decisoes:begin v1 -->  …JSON…  <!-- gad:decisoes:end -->
# e o conteúdo é um ARRAY JSON canônico (parser `json` da stdlib com `object_pairs_hook`,
# porque `json.loads` aceita chave duplicada em silêncio e fica com a última).
# Campos por entrada: id (PS-nn) · kind (decisao_dono|fato_medido) · area ·
# req_anchor (R-n | SC-n | ID do REQUIREMENTS | none) · decisao · opcoes_descartadas[] · evidencia ·
# reversibilidade (reversible|costly|one-way) · reversibilidade_justificativa
# (obrigatória em costly/one-way) · ressalva (opcional) · span.
#
# Códigos emitidos (uma linha `CODIGO arquivo:linha mensagem` cada):
#   FALHA   MARCA-SEM-ID          `[pre-spec]` sem id no SPEC
#   FALHA   ID-INEXISTENTE        marca cita PS-nn que não existe no bloco
#   FALHA   FATO-SEM-EVIDENCIA    kind=fato_medido sem evidência reproduzível
#   FALHA   RESSALVA-SEM-LIMITACAO  PS com `ressalva` sem linha correspondente na seção
#                                 "Limitações declaradas" do SPEC (citando PS-nn ou
#                                 `descartada: porquê`)
#   FALHA   AC-POR-PONTEIRO       AC/MUST NOT cujo corpo é só um ponteiro (S4): `→ NN-PRE-SPEC.md §x`,
#                                 `ver §x`, `→ §x`, `conforme PRE-SPEC §x`. AC que apenas
#                                 TERMINA com a citação tem corpo próprio e passa.
#   FALHA   AC-SEM-ORIGEM         linha de AC (`- [ ] AC-nn — …`) sem `[origem: <ids>]` no fim.
#                                 Um AC sem origem é um AC que ninguém pediu (caso AC-12 da F24.4).
#                                 É FALHA quando o SPEC traz `<!-- spec-origem: v1 -->` (molde
#                                 novo) ou com `--exige-origem`; senão é AVISO (specs antigas).
#   FALHA   AC-ORIGEM-INEXISTENTE id citado na origem que não existe: PS-nn fora do bloco,
#                                 AC-nn fora da própria SPEC (ou o próprio AC), id fora do
#                                 padrão; R-n/SC-n/REQ-ID fora do `--reqs` quando passado.
#   AVISO   ORIGEM-NAO-CONFERIDA  sem `--reqs`, os ids R-n/SC-n/REQ-ID foram aceitos pelo
#                                 padrão, sem conferir no REQUIREMENTS.md (uma linha por rodada).
#   Origens aceitas: PS-nn · AA-n (item n da seção `## Anexo A` do PRE-SPEC) · Goal (literal;
#   o SPEC precisa de `## Goal` com texto) · AC-nn desta SPEC · R-n/SC-n/REQ-ID (`CANC-v3x-01`).
#   Classe do critério (D2·D4·D9·D10) — FALHA com `<!-- spec-classe: v1 -->` no SPEC ou
#   `--exige-classe`; sem os dois, AVISO, e só quando o SPEC tem tag de classe ou bloco
#   `gsd:acs` (SPEC anterior ao molde sai como hoje):
#   FALHA   AC-SEM-CLASSE         linha de AC sem `[exigido: …]` nem `[desejável]`, ou com os dois,
#                                 ou classe da prosa ≠ classe do bloco `gsd:acs`, ou AC fora do
#                                 bloco / entrada do bloco sem AC, ou bloco ausente/inválido.
#   FALHA   EXIGIDO-SEM-MOTIVO    `[exigido]` sem `: <motivo>`, ou `motivo` vazio no bloco.
#   FALHA   EXIGIDO-SEM-REGUA     `[exigido]` cujas origens são TODAS `AC-nn` (derivado não é
#                                 régua de resultado — cite AA-n, PS-nn, Goal ou REQ-ID).
#   FALHA   EXIGIDO-DIVERGE-SEM-MOTIVO  `[diverge: …]` sem `AA-n — <porquê>`, ou `diverge` no
#                                 bloco sem `porque`.
#   FALHA   GOAL-SEM-COBERTURA    sem `## Cobertura do Goal`, ou sem a linha `**Efeitos sem
#                                 cobertura:**`, ou com ela em branco, ou com efeito descoberto.
#   AVISO   AC-ORIGEM-REPETIDA    dois ou mais ACs com o MESMO conjunto de origens (bandeira
#                                 da pergunta de unicidade — nunca reprova; ignora AC sem origem).
#   AVISO   EXTENSAO-SUSPEITA     números, identificadores snake_case/CamelCase e literais
#                                 (None, default, …) presentes na linha marcada
#                                 `[pre-spec:PS-nn…]` e ausentes no span/decisao do PS-nn.
#                                 Token-level, sem regex sobre prosa livre. NÃO falha:
#                                 o revisor recebe a lista; o coordenador decide (R2 (c)).
#   (bloco) ID-DUPLICADO, JSON inválido, chave duplicada, campo faltando/enum errado
#           → bloco INVÁLIDO → exit 2.
#
# Exit: 0 = ok (avisos não reprovam) · 1 = falha (ou bloco ausente) · 2 = bloco inválido.
# `--so-bloco` valida só o bloco e imprime `pre_spec_bloco: ausente|invalido|ok`
# (é o que o setup-intencao.sh emite na onda 1) — exit 1 = ausente, 2 = invalido, 0 = ok.
# Nesse modo FATO-SEM-EVIDENCIA entra em `invalido` (o tri-estado não tem casa para
# "bloco bem-formado com fato sem evidência", e ele não pode passar como `ok`).
#
# Régua da skill: verificação vira script; julgamento fica no modelo.

set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gsd-shim.sh" 2>/dev/null && trap 'gad_autoregistro "confere-pre-spec.sh" "$?"' EXIT || true

MODO="completo"
EXIGE_ORIGEM=0; EXIGE_CLASSE=0; REQS=""
while :; do
  case "${1:-}" in
    --exige-origem) EXIGE_ORIGEM=1; shift ;;
    --exige-classe) EXIGE_CLASSE=1; shift ;;
    --sem-pre-spec) MODO="sem-pre"; shift ;;
    --reqs) REQS="${2:?uso: --reqs <REQUIREMENTS.md>}"; shift 2
            [ -f "$REQS" ] || { echo "ERRO: --reqs não encontrado: $REQS" >&2; exit 2; } ;;
    *) break ;;
  esac
done
if [ "$MODO" = "sem-pre" ]; then
  SPEC="${1:?uso: confere-pre-spec.sh --sem-pre-spec [--reqs REQUIREMENTS.md] <NN-SPEC.md>}"
  PRE=""
  [ -f "$SPEC" ] || { echo "ERRO: SPEC não encontrado: $SPEC" >&2; exit 2; }
elif [ "${1:-}" = "--so-bloco" ]; then
  MODO="so-bloco"; shift
  PRE="${1:?uso: confere-pre-spec.sh --so-bloco <NN-PRE-SPEC.md>}"
  SPEC=""
else
  SPEC="${1:?uso: confere-pre-spec.sh <NN-SPEC.md> <NN-PRE-SPEC.md>}"
  PRE="${2:?uso: confere-pre-spec.sh <NN-SPEC.md> <NN-PRE-SPEC.md>}"
  [ -f "$SPEC" ] || { echo "ERRO: SPEC não encontrado: $SPEC" >&2; exit 2; }
fi
[ "$MODO" = "sem-pre" ] || [ -f "$PRE" ] || { echo "ERRO: PRE-SPEC não encontrado: $PRE" >&2; exit 2; }

python3 - "$MODO" "$PRE" "$SPEC" "$EXIGE_ORIGEM" "$REQS" "$EXIGE_CLASSE" <<'PY'
import json, re, sys

MODO, PRE, SPEC = sys.argv[1], sys.argv[2], sys.argv[3]
EXIGE_ORIGEM, REQS = sys.argv[4] == "1", sys.argv[5]
EXIGE_CLASSE = sys.argv[6] == "1"
SEM_PRE = MODO == "sem-pre"
SEM_PRE_MSG = "a fase não tem PRE-SPEC"

BEGIN = "<!-- gad:decisoes:begin v1 -->"
END   = "<!-- gad:decisoes:end -->"

KINDS  = {"decisao_dono", "fato_medido"}
REVERS = {"reversible", "costly", "one-way"}
OBRIG  = ["id", "kind", "area", "req_anchor", "decisao", "evidencia", "reversibilidade", "span"]
CONHEC = set(OBRIG) | {"opcoes_descartadas", "reversibilidade_justificativa", "ressalva"}

RE_ID     = re.compile(r'^PS-\d\d$')
RE_ANCHOR = re.compile(r'^(?:[A-Z]{1,8}-?\d+|none)$')  # R-n, SC-n ou ID do REQUIREMENTS do projeto (RESID-01, DESC-01…) — alargado 29/08
RE_PONTO  = re.compile(r'\S+\.[A-Za-z0-9_]+:\d+(?:-\d+)?')   # arquivo:linha

falhas, avisos = [], []
def falha(cod, arq, lin, msg): falhas.append((cod, arq, lin, msg))
def aviso(cod, arq, lin, msg): avisos.append((cod, arq, lin, msg))

def morre_invalido(msg, linha=0):
    print(f"BLOCO-INVALIDO {PRE}:{linha} {msg}")
    print("resumo: bloco inválido — nada mais foi conferido")
    if MODO == "so-bloco":
        print("pre_spec_bloco: invalido")
    sys.exit(2)

# ---------------------------------------------------------------- bloco
# Modo sem pré-spec: não há bloco a ler; `ps` fica vazio e tudo que cita PS-nn reprova
# com a mensagem própria. O resto das conferências do SPEC roda igual.
linhas_pre = [] if SEM_PRE else open(PRE, encoding="utf-8", errors="replace").read().split("\n")
ini = fim = None
for n, l in enumerate(linhas_pre, 1):
    if BEGIN in l and ini is None: ini = n
    elif END in l and ini is not None and fim is None: fim = n
if SEM_PRE:
    ini = fim = 0
elif ini is None or fim is None:
    print(f"BLOCO-AUSENTE {PRE}:0 não achei {BEGIN} … {END}")
    if MODO == "so-bloco":
        print("pre_spec_bloco: ausente")
    else:
        print("resumo: bloco ausente — nada foi conferido")
    sys.exit(1)

bruto = "[]" if SEM_PRE else "\n".join(linhas_pre[ini:fim-1])

def sem_duplicata(pares):
    vistas = set()
    for k, _ in pares:
        if k in vistas:
            morre_invalido(f"chave duplicada no JSON do bloco: {k!r}", ini)
        vistas.add(k)
    return dict(pares)

try:
    dados = json.loads(bruto, object_pairs_hook=sem_duplicata)
except json.JSONDecodeError as e:
    morre_invalido(f"JSON inválido: {e.msg} (linha {e.lineno} do bloco)", ini + e.lineno)

if not isinstance(dados, list):
    morre_invalido("o conteúdo do bloco tem de ser um array JSON de objetos", ini)

def linha_do_id(psid):
    for n in range(ini, fim):
        if psid in linhas_pre[n-1]:
            return n
    return ini

ps = {}
for i, e in enumerate(dados):
    if not isinstance(e, dict):
        morre_invalido(f"entrada #{i+1} não é um objeto", ini)
    psid = e.get("id")
    if not isinstance(psid, str) or not RE_ID.match(psid):
        morre_invalido(f"entrada #{i+1}: `id` ausente ou fora do padrão PS-nn ({psid!r})", ini)
    ln = linha_do_id(psid)
    if psid in ps:
        morre_invalido(f"ID-DUPLICADO {psid} aparece duas vezes no bloco", ln)
    for c in OBRIG:
        if c not in e or e[c] is None or (isinstance(e[c], str) and not e[c].strip()):
            morre_invalido(f"{psid}: campo obrigatório ausente ou vazio: `{c}`", ln)
    desconhecidos = set(e) - CONHEC
    if desconhecidos:
        morre_invalido(f"{psid}: campo(s) fora do contrato v1: {sorted(desconhecidos)}", ln)
    if e["kind"] not in KINDS:
        morre_invalido(f"{psid}: `kind` inválido ({e['kind']!r}); use {sorted(KINDS)}", ln)
    if not RE_ANCHOR.match(str(e["req_anchor"])):
        morre_invalido(f"{psid}: `req_anchor` inválido ({e['req_anchor']!r}); use R-n, SC-n, um ID do REQUIREMENTS (ex. DESC-01) ou none", ln)
    if e["reversibilidade"] not in REVERS:
        morre_invalido(f"{psid}: `reversibilidade` inválida ({e['reversibilidade']!r})", ln)
    if e["reversibilidade"] in ("costly", "one-way") and not str(e.get("reversibilidade_justificativa", "")).strip():
        morre_invalido(f"{psid}: `reversibilidade_justificativa` é obrigatória em {e['reversibilidade']}", ln)
    if "opcoes_descartadas" in e and not isinstance(e["opcoes_descartadas"], list):
        morre_invalido(f"{psid}: `opcoes_descartadas` tem de ser lista", ln)
    e["_linha"] = ln
    ps[psid] = e

# FATO-SEM-EVIDENCIA: fato_medido exige evidência reproduzível (arquivo:linha ou comando→saída)
for psid, e in ps.items():
    if e["kind"] != "fato_medido":
        continue
    ev = str(e["evidencia"]).strip()
    reproduzivel = ev.lower() != "none" and (RE_PONTO.search(ev) or "→" in ev or "->" in ev)
    if not reproduzivel:
        falha("FATO-SEM-EVIDENCIA", PRE, e["_linha"],
              f"{psid} é fato_medido e `evidencia` não é reproduzível ({ev!r}); "
              "use arquivo:linha ou comando → saída")

if MODO == "so-bloco":
    # Tri-estado do setup-intencao.sh: ausente (exit 1) | invalido (exit 2) | ok (exit 0).
    # Falha de conteúdo do próprio bloco (FATO-SEM-EVIDENCIA) conta como `invalido` —
    # o coordenador não pode receber um bloco que afirma fato sem evidência como `ok`.
    for cod, arq, lin, msg in falhas:
        print(f"{cod} {arq}:{lin} {msg}")
    print(f"resumo: falhas={len(falhas)} · avisos=0 · entradas={len(ps)}")
    print("pre_spec_bloco: invalido" if falhas else "pre_spec_bloco: ok")
    sys.exit(2 if falhas else 0)

# ---------------------------------------------------------------- SPEC
linhas_spec = open(SPEC, encoding="utf-8", errors="replace").read().split("\n")

RE_MARCA_ID  = re.compile(r'\[(pre-spec|medido):\s*(PS-\d\d)((?:\s*,\s*[^\]]+)?)\]')
RE_MARCA_NUA = re.compile(r'\[pre-spec\](?!:)')

usados = set()
for n, l in enumerate(linhas_spec, 1):
    for m in RE_MARCA_NUA.finditer(l):
        falha("MARCA-SEM-ID", SPEC, n, "marca `[pre-spec]` sem id; use `[pre-spec:PS-nn, R-n]`")
    for m in RE_MARCA_ID.finditer(l):
        psid = m.group(2)
        if psid not in ps:
            falha("ID-INEXISTENTE", SPEC, n,
                  f"marca cita {psid} e {SEM_PRE_MSG}" if SEM_PRE
                  else f"marca cita {psid}, que não existe no bloco de {PRE}")
        else:
            usados.add(psid)

# --- RESSALVA-SEM-LIMITACAO ------------------------------------------------
RE_SECAO_LIM = re.compile(r'^\s{0,3}#{1,6}\s.*limita(?:ç|c)(?:ões|oes)\s+declaradas', re.I)
RE_HEADING   = re.compile(r'^\s{0,3}#{1,6}\s')
lim_ini = None
for n, l in enumerate(linhas_spec, 1):
    if RE_SECAO_LIM.match(l):
        lim_ini = n
        break
corpo_lim = []
if lim_ini is not None:
    for l in linhas_spec[lim_ini:]:
        if RE_HEADING.match(l):
            break
        corpo_lim.append(l)

for psid, e in sorted(ps.items()):
    if not str(e.get("ressalva", "")).strip():
        continue
    # A cobertura é POR LINHA e tem de identificar o PS: uma linha `descartada: <porquê>`
    # solta não cobre ressalva nenhuma (senão um único descarte absolveria o SPEC inteiro).
    coberta = any(psid in l for l in corpo_lim)
    if lim_ini is None:
        falha("RESSALVA-SEM-LIMITACAO", SPEC, 0,
              f"{psid} tem `ressalva` e o SPEC não tem seção \"Limitações declaradas\"")
    elif not coberta:
        falha("RESSALVA-SEM-LIMITACAO", SPEC, lim_ini,
              f"{psid} tem `ressalva` sem linha correspondente em \"Limitações declaradas\" "
              "(cite PS-nn ou escreva `descartada: <porquê>`)")

# --- AC-POR-PONTEIRO (S4) --------------------------------------------------
RE_AC       = re.compile(r'(?:\bAC-\d+\b|MUST\s+NOT)', re.I)
_VERBO = r'(?:ver|veja|vide|cf\.?|conforme|consulte)'
# Corpo que é SÓ um ponteiro, em qualquer das formas do S4 (`→` ou `ver §`):
#   `→ 99-PRE-SPEC.md §5` · `ver §3.2` · `ver 99-PRE-SPEC.md §3.2` · `→ §3.2` ·
#   `conforme PRE-SPEC §2`. Ancorado nas duas pontas: um AC que apenas TERMINA
#   com uma citação ("… e o Δ fecha em zero, ver 99-PRE-SPEC.md §5.") tem corpo
#   próprio e NÃO é acusado.
RE_SO_PONTA = re.compile(
    r'^(?:' + _VERBO + r'\s*)?'                                   # verbo antes da seta
    r'(?:(?:→|->|=>)\s*)?'                                        # seta
    r'(?:' + _VERBO + r'\s+)?'                                    # ou verbo depois da seta
    r'(?:'
    r'\S*PRE-SPEC(?:\.md)?\s*(?:(?:§|#)\s*[\w.\-]+)?'             # arquivo PRE-SPEC [+ §x]
    r'|'
    r'(?:\S*\.md\s*)?(?:§|#)\s*[\w.\-]+'                          # [arquivo.md] §x
    r')'
    r'[\s.,;]*$', re.I)

RE_ORIGEM = re.compile(r'\[origem:\s*([^\]]*)\]', re.I)
# Classe do critério (D4): `[exigido: motivo]` · `[desejável]` · `[diverge: AA-n — porquê]`.
# São campos, não corpo — saem do corpo antes de julgar AC-POR-PONTEIRO, como a origem.
RE_EXIG   = re.compile(r'\[exigido(?::\s*([^\]]*))?\]', re.I)
RE_DESEJ  = re.compile(r'\[desej[aá]vel\]', re.I)
RE_DIV    = re.compile(r'\[diverge:\s*([^\]]*)\]', re.I)

def corpo_do_ac(l):
    c = RE_MARCA_ID.sub("", RE_MARCA_NUA.sub("", l))
    c = RE_ORIGEM.sub("", c)   # a origem é campo, não corpo (P12)
    c = RE_DIV.sub("", RE_DESEJ.sub("", RE_EXIG.sub("", c)))   # a classe é campo, não corpo (D4)
    c = re.sub(r'^\s*(?:[-*+]|\d+\.)\s*', "", c)          # marcador de lista
    c = re.sub(r'^\s*\[[^\]]\]\s*', "", c)                 # checkbox `[ ]`/`[x]`/`[m]` (P12)
    c = c.replace("**", "").replace("`", "")
    # tira, em qualquer ordem, rótulo do AC / "MUST NOT" / pontuação de abertura
    for _ in range(4):
        antes = c
        c = re.sub(r'^\s*(?:AC-\d+|MUST\s+NOT)\b', "", c, flags=re.I)
        c = re.sub(r'^\s*[:—–-]\s*', "", c)
        if c == antes:
            break
    return c.strip()

for n, l in enumerate(linhas_spec, 1):
    if not RE_AC.search(l):
        continue
    corpo = corpo_do_ac(l)
    if corpo and RE_SO_PONTA.match(corpo):
        falha("AC-POR-PONTEIRO", SPEC, n,
              "AC/MUST NOT cujo corpo é só um ponteiro para o PRE-SPEC; "
              "requisito, AC, MUST NOT e decisão não saem por referência (S4)")
    elif not corpo and RE_ORIGEM.search(l):
        falha("AC-POR-PONTEIRO", SPEC, n,
              "AC cujo corpo é só a origem `[origem: …]`; a origem é campo, o critério é o corpo (S4/P12)")

# --- AC-SEM-ORIGEM / AC-ORIGEM-INEXISTENTE (P12) ------------------------------
# Linha de DEFINIÇÃO de AC: item de lista, checkbox opcional, `AC-nn` no começo
# (mesma âncora do etiqueta-achados.py). Menções no meio da linha (tabelas) não contam.
RE_AC_DEF   = re.compile(r'^\s*(?:[-*+]|\d+\.)\s*(?:\[[^\]]\]\s*)?\*{0,2}(AC-\d+)\b')
# R2, SC-1, DESC-01 e os ids com segmento de versão do REQUIREMENTS real (CANC-v3x-01 — o
# molde promete aceitá-los; o padrão antigo os rejeitava). Com `--reqs` o id é conferido
# no arquivo de qualquer jeito; o padrão só decide o que é "fora do padrão".
RE_ID_REQ   = re.compile(r'^[A-Z]{1,8}(?:-[A-Za-z0-9]+)*-?\d+$')
MARCADOR    = "<!-- spec-origem: v1 -->"
exige = EXIGE_ORIGEM or any(MARCADOR in l for l in linhas_spec)
acs_def = {}
for n, l in enumerate(linhas_spec, 1):
    m = RE_AC_DEF.match(l)
    if m:
        acs_def.setdefault(m.group(1).upper(), n)
reqs_txt = open(REQS, encoding="utf-8", errors="replace").read() if REQS else None
nao_conferidos = []
sem_origem = falha if exige else aviso

# Origens-régua da D2: `AA-n` = item n da seção `## Anexo A` do PRE-SPEC (lista `n.` até o
# próximo heading); `Goal` = literal, aceito quando o SPEC tem `## Goal` não vazio. O Anexo A
# real da 24.4 tem seis itens numerados sem PS-nn — sem token próprio a régua seria
# impossível de escrever. Ordem dos ramos abaixo: PS → AA → Goal → AC → REQ-ID (`AA-1` casa o
# padrão de REQ-ID e `Goal` não casa nada; os dois têm de ser decididos antes).
RE_AA = re.compile(r'^AA-(\d+)$')
def secao(linhas, titulo_rx):
    ini = None
    rx = re.compile(r'^\s{0,3}#{1,6}\s+' + titulo_rx + r'\b', re.I)
    for n, l in enumerate(linhas, 1):
        if rx.match(l):
            ini = n
            break
    if ini is None:
        return None, []
    corpo = []
    for l in linhas[ini:]:
        if RE_HEADING.match(l):
            break
        corpo.append(l)
    return ini, corpo
anexo_ini, anexo_corpo = secao(linhas_pre, r'Anexo A')
anexo_itens = {int(m.group(1)) for l in anexo_corpo for m in [re.match(r'^\s*(\d+)\.', l)] if m}
goal_ini, goal_corpo = secao(linhas_spec, r'Goal')
goal_ok = goal_ini is not None and any(l.strip() for l in goal_corpo)
origens_por_ac = {}

for acid, n in acs_def.items():
    l = linhas_spec[n-1]
    mo = RE_ORIGEM.search(l)
    ids = [x.strip() for x in mo.group(1).split(",") if x.strip()] if mo else []
    origens_por_ac[acid] = ids
    if not ids:
        sem_origem("AC-SEM-ORIGEM", SPEC, n,
                   f"{acid} sem `[origem: <ids>]` — cite PS-nn, R-n/SC-n/REQ-ID ou AC-nn desta SPEC"
                   + ("" if exige else " (aviso: SPEC sem `<!-- spec-origem: v1 -->` e sem --exige-origem)"))
        continue
    for oid in ids:
        u = oid.upper()
        if RE_ID.match(u):
            if u not in ps:
                falha("AC-ORIGEM-INEXISTENTE", SPEC, n,
                      f"{acid} cita {oid} e {SEM_PRE_MSG}" if SEM_PRE
                      else f"{acid} cita {oid}, que não existe no bloco de {PRE}")
        elif RE_AA.match(u):
            k = int(RE_AA.match(u).group(1))
            if SEM_PRE:
                falha("AC-ORIGEM-INEXISTENTE", SPEC, n, f"{acid} cita {oid} e {SEM_PRE_MSG}")
            elif anexo_ini is None:
                falha("AC-ORIGEM-INEXISTENTE", SPEC, n, f"{acid} cita {oid} e {PRE} não tem seção `## Anexo A`")
            elif k not in anexo_itens:
                falha("AC-ORIGEM-INEXISTENTE", SPEC, n,
                      f"{acid} cita {oid}, e o Anexo A de {PRE} não tem o item {k}. (itens: {sorted(anexo_itens)})")
        elif u == "GOAL":
            if not goal_ok:
                falha("AC-ORIGEM-INEXISTENTE", SPEC, n, f"{acid} cita Goal e o SPEC não tem seção `## Goal` com texto")
        elif u.startswith("AC-") and RE_ID_REQ.match(u):
            if u == acid:
                falha("AC-ORIGEM-INEXISTENTE", SPEC, n, f"{acid} cita a si mesmo como origem")
            elif u not in acs_def:
                falha("AC-ORIGEM-INEXISTENTE", SPEC, n, f"{acid} cita {oid}, que não é AC desta SPEC")
        elif RE_ID_REQ.match(oid):
            if reqs_txt is not None:
                if not re.search(r'(?<![\w-])' + re.escape(oid) + r'(?![\w-])', reqs_txt):
                    falha("AC-ORIGEM-INEXISTENTE", SPEC, n, f"{acid} cita {oid}, que não aparece em {REQS}")
            elif oid not in nao_conferidos:
                nao_conferidos.append(oid)
        else:
            falha("AC-ORIGEM-INEXISTENTE", SPEC, n,
                  f"{acid} cita {oid!r}, fora do padrão (PS-nn, AA-n, Goal, AC-nn, R-n, SC-n ou REQ-ID)")
if nao_conferidos:
    aviso("ORIGEM-NAO-CONFERIDA", SPEC, 0,
          f"sem --reqs: aceitos pelo padrão, sem conferir no REQUIREMENTS.md: {', '.join(nao_conferidos)}")

# --- classe do critério (D2 · D4 · D9 · D10) ---------------------------------
# Ligação: `--exige-classe` ou o marcador `<!-- spec-classe: v1 -->` no SPEC → os códigos são
# FALHA. Sem ligação, só avisa — e só quando o SPEC mostra algum sinal do mecanismo (uma tag
# de classe numa linha de AC ou o bloco `gsd:acs`); SPEC anterior ao molde, sem sinal nenhum,
# sai byte a byte como hoje. AC-ORIGEM-REPETIDA é bandeira sempre (convite à pergunta de
# unicidade, nunca o veredito dela) e ignora AC sem origem.
MARC_CLASSE = "<!-- spec-classe: v1 -->"
exige_classe = EXIGE_CLASSE or any(MARC_CLASSE in l for l in linhas_spec)
ACS_BEGIN, ACS_END = "<!-- gsd:acs:begin -->", "<!-- gsd:acs:end -->"
acs_ini = acs_fim = None
for n, l in enumerate(linhas_spec, 1):
    if ACS_BEGIN in l and acs_ini is None: acs_ini = n
    elif ACS_END in l and acs_ini is not None and acs_fim is None: acs_fim = n
tags_na_prosa = any(RE_EXIG.search(linhas_spec[n-1]) or RE_DESEJ.search(linhas_spec[n-1]) for n in acs_def.values())
sinal_classe = exige_classe or acs_ini is not None or tags_na_prosa
if sinal_classe:
    cls = falha if exige_classe else aviso
    sufixo = "" if exige_classe else " (aviso: SPEC sem `<!-- spec-classe: v1 -->` e sem --exige-classe)"
    acs_bloco = None
    if acs_ini is None or acs_fim is None:
        cls("AC-SEM-CLASSE", SPEC, 0, f"bloco `{ACS_BEGIN} … {ACS_END}` ausente do SPEC — a classe é lida dele{sufixo}")
    else:
        try:
            dados_acs = json.loads("\n".join(linhas_spec[acs_ini:acs_fim-1]), object_pairs_hook=lambda p: dict(p))
            if not isinstance(dados_acs, list) or not all(isinstance(e, dict) and isinstance(e.get("id"), str) for e in dados_acs):
                raise ValueError("array de objetos com `id`")
            acs_bloco = {}
            for e in dados_acs:
                if e["id"].upper() in acs_bloco:
                    cls("AC-SEM-CLASSE", SPEC, acs_ini, f"{e['id']} aparece duas vezes no bloco gsd:acs{sufixo}")
                acs_bloco[e["id"].upper()] = e
        except (json.JSONDecodeError, ValueError) as e:
            cls("AC-SEM-CLASSE", SPEC, acs_ini, f"bloco gsd:acs inválido ({e}){sufixo}")
    for acid, n in acs_def.items():
        l = linhas_spec[n-1]
        ex, de, dv = RE_EXIG.search(l), RE_DESEJ.search(l), RE_DIV.search(l)
        if ex and de:
            cls("AC-SEM-CLASSE", SPEC, n, f"{acid} traz `[exigido…]` e `[desejável]` ao mesmo tempo{sufixo}")
            continue
        classe_prosa = "exigido" if ex else ("desejavel" if de else None)
        if classe_prosa is None:
            cls("AC-SEM-CLASSE", SPEC, n, f"{acid} sem `[exigido: <motivo>]` nem `[desejável]`{sufixo}")
        ent = acs_bloco.get(acid) if acs_bloco is not None else None
        if acs_bloco is not None:
            if ent is None:
                cls("AC-SEM-CLASSE", SPEC, n, f"{acid} ausente do bloco gsd:acs{sufixo}")
            elif classe_prosa and str(ent.get("classe", "")).lower() != classe_prosa:
                cls("AC-SEM-CLASSE", SPEC, n,
                    f"{acid}: prosa diz `{classe_prosa}` e o bloco gsd:acs diz {ent.get('classe')!r} — os dois têm de dizer o mesmo{sufixo}")
        if classe_prosa != "exigido":
            continue
        motivo = (ex.group(1) or "").strip()
        if not motivo or (ent is not None and not str(ent.get("motivo") or "").strip()):
            cls("EXIGIDO-SEM-MOTIVO", SPEC, n, f"{acid} é `[exigido]` sem motivo — escreva `[exigido: <régua em uma frase>]` e `motivo` no bloco{sufixo}")
        ids = [x.upper() for x in origens_por_ac.get(acid, [])]
        if ids and all(x.startswith("AC-") for x in ids):
            cls("EXIGIDO-SEM-REGUA", SPEC, n,
                f"{acid} é `[exigido]` e só cita outro AC como origem — critério derivado não é régua de resultado; cite AA-n, PS-nn, Goal ou o REQ-ID{sufixo}")
        if dv is not None:
            m = re.match(r'^\s*(AA-\d+)\s*(?:[—–:-]+\s*(\S.*))?$', dv.group(1).strip())
            if not m or not (m.group(2) or "").strip():
                cls("EXIGIDO-DIVERGE-SEM-MOTIVO", SPEC, n, f"{acid}: `[diverge: …]` sem `AA-n — <porquê>`{sufixo}")
        if ent is not None and ent.get("diverge") is not None:
            d = ent["diverge"]
            if not isinstance(d, dict) or not str(d.get("porque") or "").strip():
                cls("EXIGIDO-DIVERGE-SEM-MOTIVO", SPEC, n,
                    f"{acid}: `diverge` no bloco gsd:acs sem `porque` — divergir do Anexo A é permitido, em silêncio não{sufixo}")
    if acs_bloco is not None:
        for k, e in acs_bloco.items():
            if k not in acs_def:
                cls("AC-SEM-CLASSE", SPEC, acs_ini, f"{e['id']} está no bloco gsd:acs e não é AC desta SPEC{sufixo}")
    # GOAL-SEM-COBERTURA: a seção existe e não pode ficar em branco nem contradizer a si mesma.
    cob_ini, cob_corpo = secao(linhas_spec, r'Cobertura do Goal')
    if cob_ini is None:
        cls("GOAL-SEM-COBERTURA", SPEC, 0, f"SPEC sem seção `## Cobertura do Goal`{sufixo}")
    else:
        linha_ef = next((l for l in cob_corpo if l.strip().startswith("**Efeitos sem cobertura:**")), None)
        if linha_ef is None:
            cls("GOAL-SEM-COBERTURA", SPEC, cob_ini, f"`## Cobertura do Goal` sem a linha `**Efeitos sem cobertura:**`{sufixo}")
        else:
            valor = linha_ef.split("**Efeitos sem cobertura:**", 1)[1].strip()
            if not valor or valor.startswith("["):
                cls("GOAL-SEM-COBERTURA", SPEC, cob_ini, f"`**Efeitos sem cobertura:**` em branco — escreva `nenhum` ou um efeito por linha{sufixo}")
            elif valor.lower().rstrip(".") != "nenhum":
                cls("GOAL-SEM-COBERTURA", SPEC, cob_ini, f"efeito do Goal sem exigido que o cubra: {valor}{sufixo}")

# AC-ORIGEM-REPETIDA (bandeira): dois ou mais ACs com o mesmo conjunto de origens.
grupos = {}
for acid, ids in origens_por_ac.items():
    if ids:
        grupos.setdefault(frozenset(x.upper() for x in ids), []).append(acid)
for chave, acs in grupos.items():
    if len(acs) > 1:
        aviso("AC-ORIGEM-REPETIDA", SPEC, acs_def[acs[0]],
              f"{', '.join(acs)} têm o mesmo conjunto de origens ({', '.join(sorted(chave))}) — qual verificação derruba só cada um? (bandeira, não veredito)")

# --- EXTENSAO-SUSPEITA (aviso, token-level) --------------------------------
RE_IDS_DOC   = re.compile(r'\b(?:PS|AC|R|SC|D|REQ|Q)-?\d+\b')
RE_SNAKE     = re.compile(r'\b[a-zA-Z][a-zA-Z0-9]*(?:_[a-zA-Z0-9]+)+\b')
RE_CAMEL     = re.compile(r'\b[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+\b')
RE_NUM       = re.compile(r'(?<![\w.])\d+(?:[.,]\d+)*%?(?![\w])')
LITERAIS     = ["None", "null", "NULL", "default", "True", "False", "nil", "undefined"]
RE_LITERAL   = re.compile(r'\b(?:' + "|".join(LITERAIS) + r')\b')

def tokens(texto):
    t = RE_IDS_DOC.sub(" ", texto)
    achados = []
    for rx in (RE_SNAKE, RE_CAMEL, RE_NUM, RE_LITERAL):
        achados += [m.group(0) for m in rx.finditer(t)]
    return achados

def corpus(e):
    return RE_IDS_DOC.sub(" ", f"{e.get('span','')} {e.get('decisao','')}").lower()

for n, l in enumerate(linhas_spec, 1):
    marcas = list(RE_MARCA_ID.finditer(l))
    if not marcas:
        continue
    linha_limpa = RE_MARCA_ID.sub(" ", l)
    for m in marcas:
        psid = m.group(2)
        if psid not in ps:
            continue
        base = corpus(ps[psid])
        ausentes = []
        for tk in tokens(linha_limpa):
            if tk.lower() not in base and tk not in ausentes:
                ausentes.append(tk)
        if ausentes:
            aviso("EXTENSAO-SUSPEITA", SPEC, n,
                  f"linha marcada {psid}: {', '.join(ausentes)} não aparece(m) no span/decisao do PS "
                  "— extensão do spec? (o que o spec acrescenta vai em frase/AC `[auto]` separado)")

# ---------------------------------------------------------------- saída
for cod, arq, lin, msg in falhas:
    print(f"{cod} {arq}:{lin} {msg}")
for cod, arq, lin, msg in avisos:
    print(f"{cod} {arq}:{lin} {msg}")

conta = {}
for cod, *_ in falhas + avisos:
    conta[cod] = conta.get(cod, 0) + 1
detalhe = " · ".join(f"{k}={v}" for k, v in sorted(conta.items())) or "nenhum achado"
print(f"resumo: falhas={len(falhas)} · avisos={len(avisos)} · entradas={len(ps)} · "
      f"marcas_usadas={len(usados)}/{len(ps)} · {detalhe}"
      + (" · modo=sem-pre-spec" if SEM_PRE else ""))
sys.exit(1 if falhas else 0)
PY
