#!/usr/bin/env bash
# spot-check-ponteiros.sh — verificação determinística de citações `arquivo:linha`.
#
# Uso: spot-check-ponteiros.sh <arquivo.md> [root ...]
#   Extrai todo padrão `caminho:linha` do arquivo, resolve o caminho e confere:
#   (a) o arquivo existe; (b) a linha existe.
#   Multi-root (auditoria 04/08 da F22: falsos-positivos MISSING-FILE em massa quando
#   o documento cita mais de uma árvore — repo + transcrições fora dele): pode passar
#   VÁRIAS raízes; um caminho relativo é tentado em cada uma, na ordem, e só é
#   MISSING-FILE se não existir em NENHUMA. Sem root → default: cwd.
#
#   [R9, 28/08] Links markdown são NORMALIZADOS antes do grep: em `[texto](alvo)` vale
#   o ALVO, nunca o texto — o texto é suprimido para não virar uma segunda referência
#   (era daí que vinham os MISSING-FILE falsos: `[capability-registry.cjs:2485](file:///…#L2485)`
#   produzia um ponteiro relativo inexistente além do absoluto bom). `file://` é
#   removido, `#L<n>` e `#L<n>-L<m>` viram `:<n>` (a primeira linha do intervalo). Se o
#   alvo não trouxer linha mas o texto trouxer (`[x.py:12](/abs/x.py)`), a linha do texto
#   é colada no alvo. Dedup DEPOIS da normalização.
#
#   Saída: uma linha por ponteiro QUEBRADO (`MISSING-FILE caminho:linha` ou
#   `MISSING-LINE caminho:linha (arquivo tem N linhas)`), e um sumário final
#   `referencias_vistas=N · alvos_unicos=M · OK M'/M` (N conta cada citação do
#   documento; M conta alvos distintos após a normalização). Exit 0 sempre — é
#   ferramenta de relato; o julgamento do que fazer com um ponteiro quebrado é do modelo.
#
#   [t59/L13, 26/09, FM-F27INS-03PLAN] Checagem de LIMITE (existe o arquivo? existe a
#   linha?) não vê DESLOCAMENTO — a linha citada existe, só o conteúdo mudou (3 casos
#   reais da F27-INS: `ship.py:502→503`, `conftest.py:57→59`,
#   `test_bat_commands.py:23-25→25-26`, achados só pelo escrivão da convergência em
#   `27-REVIEWS.md`, nunca por este script). Quando a MESMA CÉLULA DE TABELA (linha
#   que começa com `|`, formato real do "source-grounding pass" da convergência) traz
#   a citação `caminho:linha` **e** um trecho literal entre crases ou aspas duplas
#   (≥4 caracteres, que não seja ele mesmo outra citação) descrevendo o conteúdo
#   esperado, o script confere se esse literal aparece no trecho citado do arquivo
#   real. Fora de tabela (prosa, parágrafo) o script NÃO tenta — testado contra o
#   corpus real: "mesma linha" em prosa longa com vários links pega literal de OUTRA
#   citação da mesma frase e vira falso positivo; melhor silêncio do que aviso ruim.
#   Se não aparece ALI mas aparece numa janela de
#   ±`SPOT_CHECK_JANELA` linhas (padrão 10, busca da mais próxima para a mais longe),
#   emite `DESLOCADO caminho:N -> linha real M ("literal")` e o sumário ganha
#   `· deslocados=K` (só quando K>0; sem deslocamento, o sumário não muda). Se nenhum
#   literal casa nem na janela, o script fica em silêncio: não inventa categoria para
#   o que não pode confirmar (é o caso da citação parafraseada — não literal — do
#   `test_bat_commands.py`, que por isso continua sem aviso; ver
#   `t59-plano/relatorio-L13.md`). Citação com dois-pontos soltos no mesmo trecho
#   (`arquivo:57 e :88`) reaproveita o caminho da citação anterior na MESMA célula —
#   é o formato real do `27-REVIEWS.md`.
#
# Régua da skill: verificação vira script; julgamento fica no modelo.

set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gsd-shim.sh" 2>/dev/null || true
DOC="${1:?uso: spot-check-ponteiros.sh <arquivo.md> [root ...]}"
shift
ROOTS=("$@")
# FM-F4RLR-12INT: sem root explícito, resolver a partir da RAIZ DO REPO (git
# rev-parse --show-toplevel a partir do próprio documento), não do cwd de quem chamou —
# o cwd de um agente varia (5 agentes perderam turno com MISSING-FILE falso por isso).
# cwd continua no fim da lista como fallback (compat com documento fora de repo git).
if [ ${#ROOTS[@]} -eq 0 ]; then
  GR="$(cd "$(dirname -- "$DOC")" && git rev-parse --show-toplevel 2>/dev/null || true)"
  PWD_ATUAL="$(pwd)"
  if [ -n "$GR" ] && [ "$GR" != "$PWD_ATUAL" ]; then
    ROOTS=("$GR" "$PWD_ATUAL")
  else
    ROOTS=("${GR:-$PWD_ATUAL}")
  fi
fi

[ -f "$DOC" ] || { echo "ERRO: arquivo não encontrado: $DOC" >&2; exit 2; }
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || { echo "ERRO: root não encontrado: $r" >&2; exit 2; }
done

TMP=$(mktemp -d "${TMPDIR:-/tmp}/spot-check-XXXXXX") || exit 2
# B1/§6.1: um único trap EXIT — o segundo `trap` em bash SUBSTITUI o primeiro, então o
# auto-registro (que estava na linha acima) nunca rodava. Captura o rc ANTES do rm, senão
# o auto-registro gravaria o exit do próprio `rm -rf`, não o do script.
trap 'rc=$?; rm -rf "$TMP"; type gad_autoregistro >/dev/null 2>&1 && gad_autoregistro "spot-check-ponteiros.sh" "$rc"; true' EXIT

# Extração + normalização (python3 stdlib): uma referência por linha, na ordem do documento.
python3 - "$DOC" > "$TMP/refs" <<'PY'
import re, sys, urllib.parse

texto = open(sys.argv[1], encoding="utf-8", errors="replace").read()

LINK = re.compile(r'\[([^\]\n]*)\]\(\s*<?([^)\s>]+)>?\s*\)')
PTR  = re.compile(r'[A-Za-z0-9_./-]+\.[A-Za-z0-9_]+:[0-9]+')
BARE = re.compile(r'file://[^\s)\]>`"\']+')
ANCH = re.compile(r'#L(\d+)(?:-L?\d+)?$')

def normaliza(alvo):
    """Alvo do link → `caminho:linha` (ou caminho sem linha). Nunca resolve o texto."""
    alvo = alvo.strip().strip('`')
    if alvo.startswith("file://"):
        alvo = urllib.parse.unquote(alvo[len("file://"):])
    m = ANCH.search(alvo)
    if m:
        alvo = alvo[:m.start()] + ":" + m.group(1)
    return alvo

def eh_ponteiro(s):
    # Nada com esquema sobrevive: `https://…/foo.py#L12` viraria `https://…/foo.py:12`
    # e, por não ser absoluto, seria tentado em cada root e daria MISSING-FILE falso.
    if "://" in s:
        return False
    return bool(re.fullmatch(r'\S+\.[A-Za-z0-9_]+:[0-9]+', s))

def eh_caminho(s):
    return ("/" in s or re.search(r'\.[A-Za-z0-9_]+$', s)) and "://" not in s

refs = []
partes = []   # texto residual, com os links inteiros removidos
pos = 0
for m in LINK.finditer(texto):
    partes.append(texto[pos:m.start()])
    pos = m.end()
    alvo = normaliza(m.group(2))
    if eh_ponteiro(alvo):
        refs.append((m.start(), alvo))
    elif eh_caminho(alvo):
        # alvo sem linha: aproveita a linha citada no texto do link, se houver
        t = PTR.search(m.group(1))
        if t:
            refs.append((m.start(), alvo.rstrip("/") + ":" + t.group(0).rsplit(":", 1)[1]))
partes.append(texto[pos:])
residuo = "".join(partes)

# URLs file:// soltas (fora de link markdown)
pos = 0
partes = []
for m in BARE.finditer(residuo):
    partes.append(residuo[pos:m.start()])
    pos = m.end()
    alvo = normaliza(m.group(0))
    if eh_ponteiro(alvo):
        refs.append((m.start(), alvo))
partes.append(residuo[pos:])
residuo = "".join(partes)

for m in PTR.finditer(residuo):
    refs.append((m.start(), m.group(0)))

for _, r in refs:
    print(r)
PY

vistas=$(wc -l < "$TMP/refs")
sort -u "$TMP/refs" > "$TMP/alvos"
total=$(wc -l < "$TMP/alvos")

while read -r ptr; do
  [ -n "$ptr" ] || continue
  file="${ptr%:*}"; line="${ptr##*:}"
  # Resolve: absoluto como veio; relativo tentado em cada root, na ordem.
  path=""
  case "$file" in
    /*) [ -f "$file" ] && path="$file" ;;
    *)  for r in "${ROOTS[@]}"; do
          if [ -f "$r/$file" ]; then path="$r/$file"; break; fi
        done ;;
  esac
  if [ -z "$path" ]; then
    echo "MISSING-FILE $ptr"
    continue
  fi
  nlines=$(wc -l < "$path")
  if [ "$line" -gt "$nlines" ]; then
    echo "MISSING-LINE $ptr (arquivo tem $nlines linhas)"
  fi
done < "$TMP/alvos" > "$TMP/out"

broken=$(wc -l < "$TMP/out")

# [t59/L13, FM-F27INS-03PLAN] Segundo passe: DESLOCAMENTO de conteúdo (a linha existe,
# o texto mudou). Só olha citação + literal que convivem na mesma célula/linha do
# documento — não inventa literal, não afrouxa casamento (ver comentário no topo).
JANELA="${SPOT_CHECK_JANELA:-10}"
python3 - "$DOC" "$JANELA" "${ROOTS[@]}" > "$TMP/deslocados" <<'PY'
import re, sys, os

doc = sys.argv[1]
janela = int(sys.argv[2])
roots = sys.argv[3:]

linhas_doc = open(doc, encoding="utf-8", errors="replace").read().splitlines()

# path:N ou path:N-M abre um "caminho atual" na célula; "e :M" ou "e :M-P" soltos
# reaproveitam o caminho aberto por ele (formato real: `conftest.py:57 e :88`).
COMBINED = re.compile(
    r'(?P<path>[A-Za-z0-9_./-]+\.[A-Za-z0-9_]+):(?P<n1>[0-9]+)(?:-(?P<m1>[0-9]+))?'
    r'|(?<!\w)e\s+:(?P<n2>[0-9]+)(?:-(?P<m2>[0-9]+))?'
)
BACKTICK = re.compile(r'`([^`]+)`')
QUOTE = re.compile(r'"([^"]{4,})"')
PTR_DENTRO = re.compile(r'\.[A-Za-z0-9_]+:[0-9]+')
SO_CAMINHO = re.compile(r'^[\w./-]+\.[A-Za-z0-9_]+$')

_cache = {}

def resolve(caminho):
    if caminho in _cache:
        return _cache[caminho]
    candidatos = [caminho] if caminho.startswith("/") else [os.path.join(r, caminho) for r in roots]
    achado = None
    for c in candidatos:
        if os.path.isfile(c):
            with open(c, encoding="utf-8", errors="replace") as fh:
                achado = fh.read().splitlines()
            break
    _cache[caminho] = achado
    return achado

def literais_da_celula(cel):
    saida = []
    for rgx in (BACKTICK, QUOTE):
        for m in rgx.finditer(cel):
            s = m.group(1).strip()
            if len(s) < 4 or PTR_DENTRO.search(s) or SO_CAMINHO.match(s):
                continue
            saida.append(s)
    return saida

def pontos_da_celula(cel):
    pontos = []
    caminho_atual = None
    for m in COMBINED.finditer(cel):
        if m.group("path"):
            caminho_atual = m.group("path")
            n = int(m.group("n1"))
            mm = int(m.group("m1")) if m.group("m1") else n
            pontos.append((caminho_atual, n, mm))
        elif caminho_atual is not None and m.group("n2"):
            n = int(m.group("n2"))
            mm = int(m.group("m2")) if m.group("m2") else n
            pontos.append((caminho_atual, n, mm))
    return pontos

def bate(linhas, n, m, literais):
    if n < 1 or m > len(linhas):
        return False
    trecho = "\n".join(linhas[n - 1:m])
    return any(lit in trecho for lit in literais)

def busca_deslocado(linhas, n, m, literais, janela):
    largura = m - n
    for d in range(1, janela + 1):
        for inicio in (n - d, m + d):
            fim = inicio + largura
            if inicio < 1 or fim > len(linhas):
                continue
            trecho = "\n".join(linhas[inicio - 1:fim])
            for lit in literais:
                if lit in trecho:
                    return inicio, fim, lit
    return None

vistos = set()
for linha in linhas_doc:
    # Só linha de TABELA (célula = unidade citação+literal, do formato real do
    # source-grounding pass). Testado contra o corpus real: em prosa/parágrafo — texto
    # longo com vários links markdown na mesma frase — o "mesmo trecho" pega literal de
    # OUTRA citação da frase e gera falso positivo (ex.: `27-02-PLAN.md:174-177` casando
    # com `rtk proxy`, texto de uma citação vizinha, não da citada). Fora de tabela, a
    # granularidade de "mesma linha" é grosseira demais — melhor ficar em silêncio.
    if not linha.strip().startswith("|"):
        continue
    celulas = linha.split("|")
    for cel in celulas:
        literais = literais_da_celula(cel)
        if not literais:
            continue
        for caminho, n, m in pontos_da_celula(cel):
            conteudo = resolve(caminho)
            if conteudo is None or bate(conteudo, n, m, literais):
                continue
            achou = busca_deslocado(conteudo, n, m, literais, janela)
            if not achou:
                continue
            inicio, fim, lit = achou
            alvo = f"{caminho}:{n}" if n == m else f"{caminho}:{n}-{m}"
            real = str(inicio) if inicio == fim else f"{inicio}-{fim}"
            chave = (alvo, real)
            if chave in vistos:
                continue
            vistos.add(chave)
            print(f'DESLOCADO {alvo} -> linha real {real} ("{lit}")')
PY

deslocados=$(wc -l < "$TMP/deslocados")
cat "$TMP/out"
cat "$TMP/deslocados"
if [ "$deslocados" -gt 0 ]; then
  echo "referencias_vistas=$vistas · alvos_unicos=$total · OK $((total - broken))/$total · deslocados=$deslocados"
else
  echo "referencias_vistas=$vistas · alvos_unicos=$total · OK $((total - broken))/$total"
fi
exit 0
