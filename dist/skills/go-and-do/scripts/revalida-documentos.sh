#!/usr/bin/env bash
# revalida-documentos.sh — deriva documental da etapa de intenção, conferida por script
# (MGTm-01INT, auditoria F4 RLR de 21/09/2026).
#
# POR QUE ESTE SCRIPT EXISTE
# As três passadas «b» da F4 RLR (≈ 17,5 min e 271.744 tokens de verificador) não
# acharam contradição nenhuma: consertaram SÓ deriva documental — ponteiro de decisão
# apontando para critério renumerado, a palavra «três» onde já havia quatro itens, e a
# frase «revalidada no ciclo N» faltando em 4 decisões. Isso é trabalho de script.
# A releitura do verificador continua existindo para contradição de CONTEÚDO, que é o
# que só ela enxerga.
#
# USO
#   revalida-documentos.sh <phase_dir> <C> [--carimbar]
#     <phase_dir>  pasta da fase (contém NN-CONTEXT.md; NN-SPEC.md só em fase antiga)
#     <C>          número do ciclo (usado no carimbo «revalidada no ciclo N»)
#     --carimbar   além de acusar, grava o carimbo do ciclo nas decisões emendadas
#                  neste ciclo. SEM esta flag o script NÃO escreve nada.
#
# DOIS MODOS, decididos pela presença do NN-SPEC.md (plano 06-16, AC-40):
#   · fase antiga (SPEC + CONTEXT) — a régua de sempre, byte a byte: decisão é o bullet
#     `**D-NN**` do CONTEXT e o critério é declarado no SPEC.
#   · documento único (só o NN-CONTEXT.md) — tudo dentro do mesmo arquivo: decisão é
#     `**D-NN**`, `**D-NN:**` ou `**D-NN [tags]:**`; critério declarado é a referência que
#     aparece FORA dos bullets de decisão; e entra a família DERIVA.
#
# O QUE CONFERE (quatro famílias, todas SÓ ACUSAM por padrão)
#   PONTEIRO  — toda referência `SC-<n>` / `R<n>` / `AC-<n>` citada dentro de um bullet de
#               decisão do CONTEXT existe como critério declarado (no SPEC; no documento
#               único, no próprio CONTEXT fora das decisões).
#   CONTAGEM  — número escrito por extenso («três decisões», «quatro critérios») × a
#               quantidade real de itens da lista que vem logo abaixo.
#   CARIMBO   — decisão cujo texto mudou neste ciclo (comparado ao blob pré-ciclo gravado
#               em `.intent/.correcoes-c<C>.base.json`) tem de trazer
#               «revalidada no ciclo <C>». Sem `.base.json` a família é pulada e dito.
#   DERIVA    — só no documento único: critério `AC-<n>` cuja linha mudou neste ciclo
#               (mesmo blob pré-ciclo) e decisão que o cita e NÃO foi revista no mesmo
#               ciclo (linha idêntica à de antes) → acusa. A emenda no critério sem
#               rever a decisão que o cita é a deriva que a releitura pegava à mão.
#
# A REESCRITA AUTOMÁTICA FICA PARA DEPOIS: este script acusa (exit 1 com a lista) e o
# `--carimbar` é a única escrita, deliberadamente a mais burra das três. A decisão de
# reescrever ponteiro e contagem sozinho espera uma fase real sem ruído.
#
# Exit 0 = nada a acusar · 1 = acusações (lista no stdout) · 2 = uso inválido.

set -uo pipefail

PD="${1:-}"; C="${2:-}"; CARIMBAR=0
[ -n "$PD" ] && [ -n "$C" ] || {
  echo "uso: revalida-documentos.sh <phase_dir> <C> [--carimbar]" >&2; exit 2; }
shift 2
while [ $# -gt 0 ]; do
  case "$1" in
    --carimbar) CARIMBAR=1; shift ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done
[ -d "$PD" ] || { echo "ERRO: phase_dir inexistente: $PD" >&2; exit 2; }

SPEC=$(ls "$PD"/*-SPEC.md 2>/dev/null | head -1)
CTX=$(ls "$PD"/*-CONTEXT.md 2>/dev/null | head -1)
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gad-caminhos.sh"   # v2.10.1
BASE="$(gad_fase_caminho "$PD" "intent/c$C/correcoes.base.json")"

ACUSACOES=0
acusa() { echo "$*"; ACUSACOES=$((ACUSACOES+1)); }

# Bullet de decisão por modo (ver cabeçalho). Fase antiga: só `**D-NN**`, como sempre.
if [ -n "$SPEC" ]; then
  DREG='\*\*D-[0-9]+\*\*'
else
  DREG='\*\*D-[0-9]+( \[[^]]*\])?:?\*\*'
fi
# linha_decisao <arquivo> <D-NN> → a 1ª linha do bullet daquela decisão
linha_decisao() {
  if [ -n "$SPEC" ]; then grep -F "**$2**" "$1" | head -1
  else grep -E "\*\*$2( \[[^]]*\])?:?\*\*" "$1" | head -1; fi
}

# ── PONTEIRO (documento único): decisão → critério declarado no próprio CONTEXT ──
if [ -n "$CTX" ] && [ -z "$SPEC" ]; then
  REF='(^|[^A-Za-z0-9-])(SC|AC|R)-?[0-9]+'
  DECLARADOS=$(grep -vE "$DREG" "$CTX" 2>/dev/null | grep -oE "$REF" \
    | grep -oE '(SC|AC|R)-?[0-9]+' | sort -u)
  CITADOS=$(grep -E "$DREG" "$CTX" 2>/dev/null | grep -oE "$REF" \
    | grep -oE '(SC|AC|R)-?[0-9]+' | sort -u)
  for ref in $CITADOS; do
    printf '%s\n' "$DECLARADOS" | grep -qxF "$ref" && continue
    linha=$(grep -nE "$DREG" "$CTX" | grep -E "(^|[^A-Za-z0-9-])$ref([^0-9]|$)" | head -1)
    acusa "PONTEIRO $ref citado em decisão do $(basename "$CTX") não existe como critério no mesmo documento — ${linha:-<linha não localizada>}"
  done
fi

# ── PONTEIRO (fase antiga): decisão do CONTEXT → critério do SPEC ─────────────
if [ -n "$CTX" ] && [ -n "$SPEC" ]; then
  # critérios declarados: linha que DEFINE o critério (`- **SC-2** —`, `### SC-2`, `| SC-2 |`)
  DECLARADOS=$(grep -oE '(^|[^A-Za-z0-9-])(SC|AC|R)-?[0-9]+' "$SPEC" 2>/dev/null \
    | grep -oE '(SC|AC|R)-?[0-9]+' | sort -u)
  # citações dentro de bullets de decisão
  CITADOS=$(grep -E '\*\*D-[0-9]+\*\*' "$CTX" 2>/dev/null \
    | grep -oE '(SC|AC|R)-?[0-9]+' | sort -u)
  for ref in $CITADOS; do
    printf '%s\n' "$DECLARADOS" | grep -qxF "$ref" && continue
    linha=$(grep -nE '\*\*D-[0-9]+\*\*' "$CTX" | grep -E "(^|[^A-Za-z0-9-])$ref([^0-9]|$)" | head -1)
    acusa "PONTEIRO $ref citado em decisão do CONTEXT não existe como critério no $(basename "$SPEC") — ${linha:-<linha não localizada>}"
  done
fi

# ── CONTAGEM: número por extenso × lista logo abaixo ─────────────────────────
for arq in ${CTX:+"$CTX"} ${SPEC:+"$SPEC"}; do
  [ -f "$arq" ] || continue
  python3 - "$arq" <<'PY' || ACUSACOES=$((ACUSACOES+1))
import re, sys
EXT = {"um":1,"uma":1,"dois":2,"duas":2,"três":3,"tres":3,"quatro":4,"cinco":5,
       "seis":6,"sete":7,"oito":8,"nove":9,"dez":10,"onze":11,"doze":12}
arq = sys.argv[1]
linhas = open(arq, encoding="utf-8", errors="replace").read().splitlines()
pat = re.compile(r"\b(" + "|".join(EXT) + r")\s+(decis\w+|crit\w+|requisit\w+|itens|item)\b", re.I)
ruim = 0
for i, l in enumerate(linhas):
    m = pat.search(l)
    if not m:
        continue
    # conta os itens da lista que começa logo abaixo (pula linhas em branco)
    j = i + 1
    while j < len(linhas) and not linhas[j].strip():
        j += 1
    n = 0
    while j < len(linhas) and re.match(r"\s*([-*+]|\d+\.)\s+\S", linhas[j] or ""):
        n += 1
        j += 1
        while j < len(linhas) and linhas[j].startswith(("  ", "\t")) and not re.match(r"\s*([-*+]|\d+\.)\s", linhas[j]):
            j += 1
    if n == 0:
        continue
    esp = EXT[m.group(1).lower()]
    if esp != n:
        print(f"CONTAGEM {arq}:{i+1} — «{m.group(0)}» mas a lista abaixo tem {n} item(ns)")
        ruim += 1
sys.exit(1 if ruim else 0)
PY
done

# ── CARIMBO: decisão emendada neste ciclo traz «revalidada no ciclo C» ───────
if [ -n "$CTX" ] && [ -f "$BASE" ] && command -v jq >/dev/null 2>&1; then
  rel=$(python3 -c 'import os,sys; print(os.path.basename(sys.argv[1]))' "$CTX")
  blob=$(jq -r --arg n "$rel" '.alvos[] | select(.path | endswith($n)) | .blob_pre' "$BASE" 2>/dev/null | head -1)
  if [ -n "$blob" ] && [ "$blob" != null ]; then
    ROOT=$(git -C "$PD" rev-parse --show-toplevel 2>/dev/null || echo "")
    if [ -n "$ROOT" ] && git -C "$ROOT" cat-file -e "$blob" 2>/dev/null; then
      ANTES=$(mktemp); git -C "$ROOT" cat-file blob "$blob" > "$ANTES" 2>/dev/null
      while IFS= read -r d; do
        velho=$(linha_decisao "$ANTES" "$d")
        novo=$(linha_decisao "$CTX" "$d")
        [ -n "$velho" ] || continue          # decisão nova: não há o que revalidar
        [ "$velho" = "$novo" ] && continue   # intocada neste ciclo
        case "$novo" in *"revalidada no ciclo $C"*) continue ;; esac
        if [ "$CARIMBAR" = 1 ]; then
          python3 - "$CTX" "$d" "$C" "${SPEC:+antiga}" <<'PY'
import re, sys
arq, d, c, modo = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
linhas = open(arq, encoding="utf-8").read().splitlines(keepends=True)
if modo == "antiga":
    casa = lambda l: ("**%s**" % d) in l
else:  # documento único: **D-NN**, **D-NN:** ou **D-NN [tags]:**
    pat = re.compile(r"\*\*%s(?: \[[^\]]*\])?:?\*\*" % re.escape(d))
    casa = lambda l: bool(pat.search(l))
for i, l in enumerate(linhas):
    if casa(l):
        linhas[i] = l.rstrip("\n") + " (revalidada no ciclo %s)\n" % c
        break
open(arq, "w", encoding="utf-8").write("".join(linhas))
PY
          echo "CARIMBO $d — carimbada «revalidada no ciclo $C»"
        else
          acusa "CARIMBO $d mudou no ciclo $C e não traz «revalidada no ciclo $C»"
        fi
      done < <(grep -oE "$DREG" "$CTX" | grep -oE 'D-[0-9]+' | sort -u)
      # ── DERIVA (documento único): AC emendado × decisão que o cita, não revista ──
      if [ -z "$SPEC" ]; then
        while IFS= read -r l; do
          [ -n "$l" ] && acusa "$l"
        done < <(python3 - "$ANTES" "$CTX" "$C" <<'PY'
import re, sys
antes_p, ctx_p, c = sys.argv[1], sys.argv[2], sys.argv[3]
RE_AC = re.compile(r"^\s*(?:#{1,6}\s*|[-*]\s*)?(?:\[[ xX]\]\s*)?\*{0,2}(AC-\d+)\b")
RE_D = re.compile(r"\*\*(D-\d+)(?: \[[^\]]*\])?:?\*\*")


def mapa(linhas, rx):
    m = {}
    for l in linhas:
        a = rx.search(l) if rx is RE_D else rx.match(l)
        if a and a.group(1) not in m:
            m[a.group(1)] = l
    return m


antes = open(antes_p, encoding="utf-8", errors="replace").read().splitlines()
novo = open(ctx_p, encoding="utf-8", errors="replace").read().splitlines()
ac_antes, ac_novo = mapa(antes, RE_AC), mapa(novo, RE_AC)
d_antes, d_novo = mapa(antes, RE_D), mapa(novo, RE_D)
for ac, linha_velha in ac_antes.items():
    if ac_novo.get(ac) == linha_velha:
        continue                                   # critério intocado neste ciclo
    cita = re.compile(r"(?<![A-Za-z0-9-])%s(?!\d)" % re.escape(ac))
    for d, linha_d in d_novo.items():
        if not cita.search(linha_d) or d not in d_antes:
            continue                               # não cita, ou decisão nova
        if d_antes[d] == linha_d:
            print(f"DERIVA {ac} mudou no ciclo {c} e a {d} que o cita não foi revista — {linha_d.strip()}")
PY
)
      fi
      rm -f "$ANTES"
    fi
  fi
else
  [ -n "$CTX" ] && [ ! -f "$BASE" ] && \
    echo "nota: sem $BASE — família CARIMBO pulada (não há estado pré-ciclo para comparar)" >&2
fi

if [ "$ACUSACOES" -gt 0 ]; then
  echo "revalida-documentos: $ACUSACOES acusação(ões) no ciclo $C — a deriva documental fecha ANTES do commit" >&2
  exit 1
fi
echo "revalida-documentos: ciclo $C sem deriva documental" >&2
exit 0
