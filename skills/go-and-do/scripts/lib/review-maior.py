#!/usr/bin/env python3
"""review-maior.py — LEITOR ÚNICO do code review da fase (FM-04GAT · FJ-01ENC).

Fatorado do `confere-etapa.sh` (bloco REVMAX) em 21/09/2026 para que o fiscal do 4.1 e
o `numeros-da-fase.sh` (radiografia dos gates) leiam o MESMO arquivo pela MESMA regra.
Dois parsers do mesmo artefato foi exatamente como o fiscal do 4.1 acabou dando veredito
da iteração errada na F4 RLR — não escreva um segundo.

Ordem de escolha: `NN-REVIEW-FIX*` (mais recente) > `NN-REVIEW.iterN` (N mais alto) >
`NN-REVIEW.md`.

Uso: review-maior.py <phase_dir> <NN>   → JSON numa linha

Saída:
  arquivo, iteracao, status, critical/warning/info/total/skipped/fixed (quando existem),
  formato_nao_reconhecido (quando não há `status:`),
  abertos: [ids] — IDs de achado (`WR-09`, `CR-02`, `IN-16`…) declarados ABERTOS no
  arquivo de maior iteração. Heurística DECLARADA: IDs citados em seções/linhas cujo
  texto diz «aberto/abertos/open/não corrigido/skipped/deixados». É insumo do resumo
  executivo (FJ-01ENC), não veredito: a lista vem com `abertos_fonte` dizendo de onde saiu.
"""
import glob
import json
import os
import re
import sys

RE_ID = re.compile(r"\b([A-Z]{2,3}-\d{1,3})\b")
RE_ABERTO = re.compile(
    r"abert[oa]s?|open\b|n[ãa]o[ -]corrigid|n[ãa]o[ -]fechad|skipped|deixad[oa]s|pendente",
    re.I,
)
RE_FECHADO = re.compile(r"fechad[oa]s?\b|closed\b|corrigid[oa]s?\b", re.I)


def iter_de(nome):
    m = re.search(r"\.iter(\d+)\.md$", nome)
    return int(m.group(1)) if m else 1


def escolhe(pd, nn):
    cands = []
    for pat, peso in (
        (f"{nn}-REVIEW-FIX*.md", 2),
        (f"{nn}-REVIEW.md", 1),
        (f"{nn}-REVIEW.iter*.md", 1),
    ):
        for f in glob.glob(os.path.join(pd, pat)):
            cands.append((peso, iter_de(f), f))
    if not cands:
        return None, None
    cands.sort()
    _, it, alvo = cands[-1]
    return it, alvo


def abertos_de(txt):
    """IDs declarados abertos + a fonte (cabeçalho da seção ou trecho da linha)."""
    ids, fontes = [], []
    secao = None
    for linha in txt.splitlines():
        if linha.lstrip().startswith("#"):
            secao = linha.strip("# ").strip()
            continue
        contexto = f"{secao or ''} {linha}"
        if not RE_ABERTO.search(contexto):
            continue
        # uma seção «Fechados» com a palavra «aberto» dentro de uma frase não conta:
        # o sinal de abertura tem de estar no cabeçalho OU na própria linha.
        if secao and RE_FECHADO.search(secao) and not RE_ABERTO.search(linha):
            continue
        for i in RE_ID.findall(linha):
            if i not in ids:
                ids.append(i)
                fontes.append((secao or "corpo")[:80])
    return ids, fontes


def main():
    if len(sys.argv) < 3:
        print(json.dumps({"arquivo": None, "erro": "uso: review-maior.py <phase_dir> <NN>"}))
        return 0
    pd, nn = sys.argv[1], sys.argv[2]
    it, alvo = escolhe(pd, nn)
    if not alvo:
        print(json.dumps({"arquivo": None, "abertos": []}))
        return 0
    txt = open(alvo, encoding="utf-8", errors="replace").read()

    def campo(nome):
        m = re.search(r"^\s*%s:\s*(\S+)" % nome, txt, re.M)
        return m.group(1) if m else None

    status = campo("status")
    nums = {}
    for k in ("critical", "warning", "info", "total", "skipped", "fixed"):
        v = campo(k)
        if v is not None:
            try:
                nums[k] = int(v)
            except ValueError:
                nums[k] = v
    ids, fontes = abertos_de(txt)
    saida = {
        "arquivo": os.path.basename(alvo),
        "iteracao": it,
        "status": status,
        **nums,
        "abertos": ids,
        "abertos_fonte": sorted(set(fontes)),
    }
    if status is None:
        saida["formato_nao_reconhecido"] = True
    print(json.dumps(saida, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
