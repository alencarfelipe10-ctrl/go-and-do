#!/usr/bin/env python3
"""riscos-aceitos.py — LEITOR ÚNICO dos riscos aceitos do NN-SECURITY.md (FM-01ENC).

Fatorado do pre-despacho.sh em 21/09/2026: o numeros-da-fase.sh (radiografia dos gates,
FJ-01ENC) lê a MESMA tabela «Accepted Risks Log» pela MESMA regra. Uso: <arquivo> → JSON.
"""
import json, re, sys
try:
    txt = open(sys.argv[1], encoding="utf-8", errors="replace").read()
except OSError:
    print("[]"); raise SystemExit(0)
achados = []
# (1) cabeçalho legado `riscos_aceitos:` — se existir, continua valendo
m = re.search(r"^riscos_aceitos:\s*$((?:\n[ \t]+-[ \t]+.+)+)", txt, re.M)
if m:
    achados += [l.strip(" -\t") for l in m.group(1).strip().splitlines()]
# (2) tabela «Accepted Risks Log» — o formato real
m = re.search(r"^#+ *Accepted Risks Log[^\n]*$(.*?)(?=^#+ |\Z)", txt, re.M | re.S)
if m:
    for linha in m.group(1).splitlines():
        linha = linha.strip()
        if not linha.startswith("|") or re.match(r"^\|[\s:|-]+\|$", linha):
            continue
        cels = [c.strip() for c in linha.strip("|").split("|")]
        if not cels or not cels[0] or re.match(r"^(risk|risco|id|\*\*)", cels[0], re.I):
            continue
        achados.append(" — ".join(c for c in cels[:3] if c))
# (3) linhas com disposição `accept` fora da tabela
for linha in txt.splitlines():
    if re.search(r"\b(disposition|disposicao|disposição)\s*[:|]?\s*\|?\s*accept\b", linha, re.I):
        achados.append(linha.strip().strip("|").strip())
vistos, saida = set(), []
for a in achados:
    if a and a not in vistos:
        vistos.add(a); saida.append(a[:200])
print(json.dumps(saida[:8], ensure_ascii=False))
