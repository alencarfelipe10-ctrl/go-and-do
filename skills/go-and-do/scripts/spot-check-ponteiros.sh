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
# Régua da skill: verificação vira script; julgamento fica no modelo.

set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gsd-shim.sh" 2>/dev/null && trap 'gad_autoregistro "spot-check-ponteiros.sh" "$?"' EXIT || true
DOC="${1:?uso: spot-check-ponteiros.sh <arquivo.md> [root ...]}"
shift
ROOTS=("$@")
[ ${#ROOTS[@]} -eq 0 ] && ROOTS=("$(pwd)")

[ -f "$DOC" ] || { echo "ERRO: arquivo não encontrado: $DOC" >&2; exit 2; }
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || { echo "ERRO: root não encontrado: $r" >&2; exit 2; }
done

TMP=$(mktemp -d "${TMPDIR:-/tmp}/spot-check-XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

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
cat "$TMP/out"
echo "referencias_vistas=$vistas · alvos_unicos=$total · OK $((total - broken))/$total"
exit 0
