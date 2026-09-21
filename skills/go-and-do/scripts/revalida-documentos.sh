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
#     <phase_dir>  pasta da fase (contém NN-SPEC.md, NN-CONTEXT.md, …)
#     <C>          número do ciclo (usado no carimbo «revalidada no ciclo N»)
#     --carimbar   além de acusar, grava o carimbo do ciclo nas decisões emendadas
#                  neste ciclo. SEM esta flag o script NÃO escreve nada.
#
# O QUE CONFERE (três famílias, todas SÓ ACUSAM por padrão)
#   PONTEIRO  — toda referência `SC-<n>` / `R<n>` / `AC-<n>` citada dentro de um bullet de
#               decisão (`**D-NN**`) do CONTEXT existe como critério declarado no SPEC.
#   CONTAGEM  — número escrito por extenso («três decisões», «quatro critérios») × a
#               quantidade real de itens da lista que vem logo abaixo.
#   CARIMBO   — decisão cujo texto mudou neste ciclo (comparado ao blob pré-ciclo gravado
#               em `.intent/.correcoes-c<C>.base.json`) tem de trazer
#               «revalidada no ciclo <C>». Sem `.base.json` a família é pulada e dito.
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
BASE="$PD/.intent/.correcoes-c$C.base.json"

ACUSACOES=0
acusa() { echo "$*"; ACUSACOES=$((ACUSACOES+1)); }

# ── PONTEIRO: decisão do CONTEXT → critério do SPEC ──────────────────────────
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
        velho=$(grep -F "**$d**" "$ANTES" | head -1)
        novo=$(grep -F "**$d**" "$CTX" | head -1)
        [ -n "$velho" ] || continue          # decisão nova: não há o que revalidar
        [ "$velho" = "$novo" ] && continue   # intocada neste ciclo
        case "$novo" in *"revalidada no ciclo $C"*) continue ;; esac
        if [ "$CARIMBAR" = 1 ]; then
          python3 - "$CTX" "$d" "$C" <<'PY'
import sys
arq, d, c = sys.argv[1], sys.argv[2], sys.argv[3]
linhas = open(arq, encoding="utf-8").read().splitlines(keepends=True)
alvo = "**%s**" % d
for i, l in enumerate(linhas):
    if alvo in l:
        linhas[i] = l.rstrip("\n") + " (revalidada no ciclo %s)\n" % c
        break
open(arq, "w", encoding="utf-8").write("".join(linhas))
PY
          echo "CARIMBO $d — carimbada «revalidada no ciclo $C»"
        else
          acusa "CARIMBO $d mudou no ciclo $C e não traz «revalidada no ciclo $C»"
        fi
      done < <(grep -oE '\*\*D-[0-9]+\*\*' "$CTX" | tr -d '*' | sort -u)
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
