#!/usr/bin/env bash
# confere-pre-spec.sh — conferência mecânica do contrato PRE-SPEC ↔ SPEC (R2 · R7 · S4 · §0.5).
#
# Uso:
#   confere-pre-spec.sh <NN-SPEC.md> <NN-PRE-SPEC.md>
#   confere-pre-spec.sh --so-bloco <NN-PRE-SPEC.md>
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
if [ "${1:-}" = "--so-bloco" ]; then
  MODO="so-bloco"; shift
  PRE="${1:?uso: confere-pre-spec.sh --so-bloco <NN-PRE-SPEC.md>}"
  SPEC=""
else
  SPEC="${1:?uso: confere-pre-spec.sh <NN-SPEC.md> <NN-PRE-SPEC.md>}"
  PRE="${2:?uso: confere-pre-spec.sh <NN-SPEC.md> <NN-PRE-SPEC.md>}"
  [ -f "$SPEC" ] || { echo "ERRO: SPEC não encontrado: $SPEC" >&2; exit 2; }
fi
[ -f "$PRE" ] || { echo "ERRO: PRE-SPEC não encontrado: $PRE" >&2; exit 2; }

python3 - "$MODO" "$PRE" "$SPEC" <<'PY'
import json, re, sys

MODO, PRE, SPEC = sys.argv[1], sys.argv[2], sys.argv[3]

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
linhas_pre = open(PRE, encoding="utf-8", errors="replace").read().split("\n")
ini = fim = None
for n, l in enumerate(linhas_pre, 1):
    if BEGIN in l and ini is None: ini = n
    elif END in l and ini is not None and fim is None: fim = n
if ini is None or fim is None:
    print(f"BLOCO-AUSENTE {PRE}:0 não achei {BEGIN} … {END}")
    if MODO == "so-bloco":
        print("pre_spec_bloco: ausente")
    else:
        print("resumo: bloco ausente — nada foi conferido")
    sys.exit(1)

bruto = "\n".join(linhas_pre[ini:fim-1])

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
            falha("ID-INEXISTENTE", SPEC, n, f"marca cita {psid}, que não existe no bloco de {PRE}")
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

def corpo_do_ac(l):
    c = RE_MARCA_ID.sub("", RE_MARCA_NUA.sub("", l))
    c = re.sub(r'^\s*(?:[-*+]|\d+\.)\s*', "", c)          # marcador de lista
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
      f"marcas_usadas={len(usados)}/{len(ps)} · {detalhe}")
sys.exit(1 if falhas else 0)
PY
