#!/usr/bin/env bash
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gsd-shim.sh" 2>/dev/null && trap 'gad_autoregistro "confere-cardinalidade.sh" "$?"' EXIT || true
# confere-cardinalidade.sh — os mesmos números têm de bater entre os artefatos da etapa 1.
#
# Achado FM-F4RLR-09INT: na F4 RLR o cabeçalho do 04-INTENT-REVIEW.md dizia 12 confirmados
# e a tabela do MESMO arquivo tinha 24 (vereditos no disco: 30); dispensados eram 3 no
# cabeçalho e 5 nos arquivos de veredito; dívidas eram 5 na seção, só 2 no deferred-items.md.
# Quem lê só um dos artefatos leva o número errado — inclusive o planner.
#
# SÓ ACUSA (o plano diz «acusa»; reescrever cabeçalho por script fica para depois de uma
# fase real, mesma decisão da MGTm-01INT). Exit 0 = tudo bate · exit 1 = divergência.
# Uso: confere-cardinalidade.sh <phase_dir> <NN> [--json]
set -uo pipefail

PD="${1:-}"; NN="${2:-}"; MODO="${3:-}"
[ -n "$PD" ] && [ -n "$NN" ] || { echo "uso: confere-cardinalidade.sh <phase_dir> <NN> [--json]"; exit 0; }

GAD_LIB="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib" python3 - "$PD" "$NN" "$MODO" <<'PYCARD'
import glob
import json
import os
import re
import sys

pd, nn, modo = sys.argv[1], sys.argv[2], sys.argv[3]
sys.dont_write_bytecode = True
sys.path.insert(0, os.environ["GAD_LIB"])
import gad_caminhos  # v2.10.1: caminhos da fase (formato novo × antigo)
avisos = []
medido = {}

ir = os.path.join(pd, f"{nn}-INTENT-REVIEW.md")
txt = ""
if os.path.exists(ir):
    txt = open(ir, encoding="utf-8", errors="replace").read()

# ── (1) cabeçalho declarado ────────────────────────────────────────────────
def cab(nome):
    m = re.search(r"^%s:\s*(\d+)\s*$" % nome, txt, re.M)
    return int(m.group(1)) if m else None


declarado = {k: cab(f"achados_{k}") for k in ("confirmados", "descartados", "dispensados")}

# ── (2) tabela de achados — a coluna `veredito` ────────────────────────────
# Um id por linha; a linha `c2-04..c2-07` declara 4 achados numa linha só e é contada
# como 4 (a faixa é explícita). Linha de cabeçalho e separador ficam de fora.
RE_FAIXA = re.compile(r"^([a-z]\d+)-(\d+)\.\.(?:[a-z]\d+-)?(\d+)$")
tab = {"confirmados": 0, "descartados": 0, "dispensados": 0, "outros": 0}
ids_tabela = []
# Recorte: SÓ a «## Tabela de achados». Sem ele entram as linhas da reconciliação
# mecânica e das dívidas, que têm outra coluna 4 — medido na F4 RLR: 24 «confirmados»
# em vez de 16, e 6 vereditos «não reconhecidos» que eram só outra tabela.
m_tab = re.search(r"^#+ *Tabela de achados[^\n]*$(.*?)(?=^#+ |\Z)", txt, re.M | re.S)
corpo_tabela = m_tab.group(1) if m_tab else txt
for linha in corpo_tabela.splitlines():
    linha = linha.strip()
    if not linha.startswith("|") or re.match(r"^\|[\s:|-]+\|$", linha):
        continue
    cels = [c.strip() for c in linha.strip("|").split("|")]
    if len(cels) < 4:
        continue
    ident = re.sub(r"[*`]", "", cels[0]).strip()
    if not re.match(r"^[a-z]\d+-\d+", ident):
        continue
    peso = 1
    m = RE_FAIXA.match(ident)
    if m:
        peso = max(1, int(m.group(3)) - int(m.group(2)) + 1)
    ver = cels[3].lower()
    ids_tabela.append(ident)
    if "confirmado_irrelevante" in ver or "dispensad" in ver:
        tab["dispensados"] += peso
    elif "confirmado" in ver:
        tab["confirmados"] += peso
    elif "nao_sustentado" in ver or "não_sustentado" in ver or "descartad" in ver:
        tab["descartados"] += peso
    else:
        tab["outros"] += peso

# ── (3) arquivos de veredito do disco ──────────────────────────────────────
ver_disco = {"confirmados": 0, "descartados": 0, "dispensados": 0}
arquivos = gad_caminhos.glob_fase(pd, "intent/c*/vereditos.txt")
for f in arquivos:
    for linha in open(f, encoding="utf-8", errors="replace"):
        cels = [c.strip() for c in linha.split("|")]
        if len(cels) < 3:
            continue
        v = cels[2].lower()
        if v == "confirmado_irrelevante":
            ver_disco["dispensados"] += 1
        elif v.startswith("confirmado"):
            ver_disco["confirmados"] += 1
        elif v in ("nao_sustentado", "descartado", "não_sustentado"):
            ver_disco["descartados"] += 1

medido.update({"cabecalho": declarado, "tabela": tab, "vereditos_no_disco": ver_disco,
               "arquivos_de_veredito": [os.path.basename(f) for f in arquivos]})

for k in ("confirmados", "descartados", "dispensados"):
    d, t, v = declarado[k], tab[k], ver_disco[k]
    if d is None:
        continue
    if d != t:
        avisos.append(f"CARDINALIDADE {k}: cabeçalho diz {d}, a tabela do mesmo arquivo tem {t}")
    if arquivos and d != v:
        avisos.append(f"CARDINALIDADE {k}: cabeçalho diz {d}, os arquivos de veredito têm {v}")
if tab["outros"]:
    avisos.append(f"VEREDITO-NAO-RECONHECIDO: {tab['outros']} linha(s) da tabela com veredito fora do vocabulário (confirmado/confirmado_irrelevante/nao_sustentado)")

# ── (4) dívidas: seção × deferred-items.md ─────────────────────────────────
m = re.search(r"^#+ *D[íi]vidas registradas[^\n]*$(.*?)(?=^#+ |\Z)", txt, re.M | re.S)
ids_secao = []
if m:
    for linha in m.group(1).splitlines():
        linha = linha.strip()
        if not linha.startswith("|") or re.match(r"^\|[\s:|-]+\|$", linha):
            continue
        ident = re.sub(r"[*`]", "", linha.strip("|").split("|")[0]).strip()
        if ident and not re.match(r"^(id|achado)$", ident, re.I):
            ids_secao.append(ident)

defer = []
for cand in (os.path.join(pd, "deferred-items.md"),
             os.path.join(os.path.dirname(os.path.dirname(pd)), "deferred-items.md")):
    if os.path.exists(cand):
        defer.append(cand)
ids_defer = set()
for f in defer:
    conteudo = open(f, encoding="utf-8", errors="replace").read()
    for i in ids_secao:
        if i in conteudo:
            ids_defer.add(i)
medido["dividas"] = {"na_secao": ids_secao, "no_deferred": sorted(ids_defer),
                     "deferred_lidos": [os.path.basename(f) for f in defer]}
if ids_secao and defer:
    faltam = [i for i in ids_secao if i not in ids_defer]
    if faltam:
        avisos.append("DIVIDA-SEM-REGISTRO: " + " ".join(faltam)
                      + f" — na «## Dívidas registradas» ({len(ids_secao)}) e ausente(s) do deferred-items.md")
elif ids_secao and not defer:
    avisos.append(f"DIVIDA-SEM-ARQUIVO: {len(ids_secao)} dívida(s) na seção e NENHUM deferred-items.md na fase nem no .planning/")

if modo == "--json":
    print(json.dumps({"avisos": avisos, "medido": medido}, ensure_ascii=False))
else:
    if not os.path.exists(ir):
        print(f"cardinalidade: sem {nn}-INTENT-REVIEW.md — nada a conferir")
        raise SystemExit(0)
    for a in avisos:
        print("⚠️ " + a)
    if not avisos:
        print("cardinalidade: OK — cabeçalho, tabela, vereditos e dívidas batem")
raise SystemExit(1 if avisos else 0)
PYCARD
