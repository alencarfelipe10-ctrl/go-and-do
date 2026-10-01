#!/usr/bin/env bash
# confere-pii.sh — gate de PII do PRE-SPEC: nenhuma pessoa aparece por nome.
#
# Uso:
#   confere-pii.sh <arquivo.md> [<arquivo.md>…]
#                  [--nomes <lista.txt>]       lista de nomes VISTOS nos insumos (bloqueio duro)
#                  [--permitidos <lista.txt>]  termos extra a ignorar (soma-se ao default)
#                  [--brando]                  heurística vira aviso; só a lista dura reprova
#
# DUAS CAMADAS
#   1. Lista dura (`--nomes`): qualquer ocorrência, em qualquer contexto, reprova
#      (`PII-NOME-CONHECIDO`). É a lista dos nomes que apareceram na transcrição/laudo
#      que abriu a conversa — o caso do 24, corrigido a posteriori com `sed`.
#   2. Heurística "Nome Sobrenome": dois tokens capitalizados seguidos (com `da/de/dos`
#      opcional no meio), fora de heading, bloco de código, código inline, caminho de
#      arquivo e URL, e com nenhum dos dois tokens na lista de permitidos
#      (`scripts/nomes-permitidos.txt` + `--permitidos`) → `PII-NOME-SUSPEITO`.
#
# FALSOS POSITIVOS ESPERADOS (a heurística não entende semântica — a lista de permitidos é o remédio)
#   * produto/empresa de duas palavras que não esteja na lista ("Google Workspace",
#     "Banco Central", "Receita Federal");
#   * título de documento citado em prosa ("Manual Operacional", "Nota Fiscal");
#   * início de frase seguido de substantivo próprio isolado nunca é acusado (exige DOIS
#     tokens), mas "Segundo Marcelo…" — preposição capitalizada + nome — é acusado, e bem;
#   * termo estrangeiro capitalizado em prosa ("Machine Learning", "Pull Request");
#   * nome de fase escrito em caixa de título ("Fase Nova Cobrança") — `Fase` já é permitido,
#     mas "Nova Cobrança" não.
#   Nenhum desses é motivo para relaxar a regra: acrescente o termo à lista de permitidos,
#   com um comentário dizendo por que não é pessoa.
#
# Saída: uma linha `CODIGO arquivo:linha trecho` por achado + resumo.
# Exit: 0 = limpo · 1 = achado que reprova · 2 = erro de uso.
set -u

AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
PERMITIDOS_PADRAO="$AQUI/nomes-permitidos.txt"

ARQUIVOS=(); NOMES=""; PERMITIDOS_EXTRA=""; BRANDO=0
while [ $# -gt 0 ]; do
  case "$1" in
    --nomes)      NOMES="${2:?--nomes exige um arquivo}"; shift 2 ;;
    --permitidos) PERMITIDOS_EXTRA="${2:?--permitidos exige um arquivo}"; shift 2 ;;
    --brando)     BRANDO=1; shift ;;
    -h|--help)    sed -n '2,32p' "$0"; exit 0 ;;
    -*)           echo "ERRO: opção desconhecida: $1" >&2; exit 2 ;;
    *)            ARQUIVOS+=("$1"); shift ;;
  esac
done
[ ${#ARQUIVOS[@]} -gt 0 ] || { echo "uso: confere-pii.sh <arquivo.md>… [--nomes lista] [--permitidos lista] [--brando]" >&2; exit 2; }
for f in "${ARQUIVOS[@]}"; do [ -f "$f" ] || { echo "ERRO: arquivo não encontrado: $f" >&2; exit 2; }; done
[ -z "$NOMES" ] || [ -f "$NOMES" ] || { echo "ERRO: lista de nomes não encontrada: $NOMES" >&2; exit 2; }
[ -z "$PERMITIDOS_EXTRA" ] || [ -f "$PERMITIDOS_EXTRA" ] || { echo "ERRO: lista de permitidos não encontrada: $PERMITIDOS_EXTRA" >&2; exit 2; }

python3 - "$BRANDO" "$PERMITIDOS_PADRAO" "$PERMITIDOS_EXTRA" "$NOMES" "${ARQUIVOS[@]}" <<'PY'
import re, sys, unicodedata

BRANDO = sys.argv[1] == "1"
PADRAO, EXTRA, NOMES = sys.argv[2], sys.argv[3], sys.argv[4]
ARQUIVOS = sys.argv[5:]

def normaliza(s):
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return s.casefold().strip()

def carrega(caminho):
    if not caminho:
        return []
    itens = []
    with open(caminho, encoding="utf-8") as fh:
        for l in fh:
            l = l.split("#", 1)[0].strip()
            if l:
                itens.append(l)
    return itens

permitidos = set()
for termo in carrega(PADRAO) + carrega(EXTRA):
    permitidos.add(normaliza(termo))
    for parte in termo.split():          # "Claude Code" também libera "Claude" e "Code"
        permitidos.add(normaliza(parte))

duros = carrega(NOMES)

MAI = "A-ZÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ"
MIN = "a-zà-öø-ÿ"
TOKEN = rf"[{MAI}][{MIN}]{{2,}}"
LIGA = r"(?:\s+(?:d[aeo]s?|e|del|van|von))?"
RE_PAR = re.compile(rf"\b({TOKEN}){LIGA}\s+({TOKEN})\b")

RE_HEADING = re.compile(r"^\s{0,3}#{1,6}\s")
RE_FENCE = re.compile(r"^\s*(?:```|~~~)")
RE_INLINE = re.compile(r"`[^`]*`")
RE_HTML = re.compile(r"<!--.*?-->", re.S)
RE_URL = re.compile(r"\b(?:https?|file)://\S+")
RE_CAMINHO = re.compile(r"\S*[/\\]\S+|\S+\.[A-Za-z0-9_]{1,5}\b")
RE_LINK = re.compile(r"\]\([^)]*\)")

falhas, avisos = [], []

for arq in ARQUIVOS:
    bruto = open(arq, encoding="utf-8", errors="replace").read()
    bruto = RE_HTML.sub(lambda m: "\n" * m.group(0).count("\n"), bruto)
    dentro_de_codigo = False
    for n, linha in enumerate(bruto.split("\n"), 1):
        if RE_FENCE.match(linha):
            dentro_de_codigo = not dentro_de_codigo
            continue

        # camada 1 — lista dura: vale em QUALQUER contexto, inclusive heading e código
        alvo_duro = normaliza(linha)
        for nome in duros:
            if normaliza(nome) and normaliza(nome) in alvo_duro:
                falhas.append(("PII-NOME-CONHECIDO", arq, n,
                               f"{nome!r} (da lista de nomes dos insumos)"))

        if dentro_de_codigo or RE_HEADING.match(linha):
            continue

        # camada 2 — heurística, sobre a linha limpa de código inline, links e caminhos
        limpa = RE_INLINE.sub(" ", linha)
        limpa = RE_LINK.sub(" ", limpa)
        limpa = RE_URL.sub(" ", limpa)
        limpa = RE_CAMINHO.sub(" ", limpa)
        for m in RE_PAR.finditer(limpa):
            a, b = m.group(1), m.group(2)
            if normaliza(a) in permitidos or normaliza(b) in permitidos:
                continue
            if normaliza(m.group(0)) in permitidos:
                continue
            achado = ("PII-NOME-SUSPEITO", arq, n, m.group(0))
            (avisos if BRANDO else falhas).append(achado)

for cod, arq, lin, msg in falhas:
    print(f"{cod} {arq}:{lin} {msg}")
for cod, arq, lin, msg in avisos:
    print(f"AVISO {cod} {arq}:{lin} {msg}")

print(f"resumo: falhas={len(falhas)} · avisos={len(avisos)} · arquivos={len(ARQUIVOS)}")
sys.exit(1 if falhas else 0)
PY
