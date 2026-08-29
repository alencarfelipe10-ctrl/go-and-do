#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gera-bloco.py — monta o bloco `gad:decisoes` v1 do PRE-SPEC a partir das respostas
da entrevista e o insere entre as marcas do arquivo.

Uso:
    gera-bloco.py --entrada respostas.json --arquivo <NN-PRE-SPEC.md>
                  [--confere <caminho do confere-pre-spec.sh>] [--sem-conferir]
                  [--saida <arquivo>] [--stdout]

ENTRADA (JSON) — array de objetos com nomes em português, do jeito que a entrevista
produz. Nenhum campo canônico do contrato precisa ser digitado à mão:

    [
      {
        "tipo": "decisao",              # decisao | medicao   (obrigatório)
        "assunto": "Grão do DRE",       # área/tema           (obrigatório)
        "texto": "A agregação fica…",   # a decisão ou o fato (obrigatório)
        "requisito": "R2",              # R-n | SC-n | ID do REQUIREMENTS (DESC-01) | vazio → "none"
        "descartadas": ["Opção B …"],   # lista, opcional
        "evidencia": "src/x.py:12",     # obrigatória em "medicao"
        "reversibilidade": "cara",      # reversivel | cara | sem-volta
        "justificativa": "…",           # obrigatória em cara/sem-volta
        "ressalva": "…",                # opcional (obriga linha no SPEC — R7)
        "onde": "§5 Recomendação"       # seção do PRE-SPEC   (obrigatório)
      }
    ]

Os nomes canônicos do contrato (kind, area, req_anchor, decisao, evidencia, span…)
também são aceitos como sinônimo, para reprocessar um bloco já existente.

REGRAS QUE ESTE SCRIPT IMPÕE (antes de qualquer conferência mecânica)
  * `medicao` (kind=fato_medido) exige evidência REPRODUZÍVEL: `arquivo:linha` ou
    `comando → saída`. Número copiado de documento antigo não é fato medido: ele fica
    no corpo do PRE-SPEC marcado `[herdado]` e não entra no bloco. Recusa explícita.
  * `cara`/`sem-volta` (costly/one-way) exigem justificativa.
  * ids `PS-01`…`PS-99`, sequenciais, na ordem da entrada. Acima de 99 o contrato
    (`^PS-\\d\\d$`) não tem casa: falha com mensagem clara.
  * campos opcionais VAZIOS são omitidos, nunca emitidos como string vazia — o
    confere-pre-spec.sh rejeita campo obrigatório vazio e campo fora do contrato.

SAÍDA: reescreve o arquivo entre `<!-- gad:decisoes:begin v1 -->` e
`<!-- gad:decisoes:end -->` (as marcas têm de existir) e, em seguida, chama
`confere-pre-spec.sh --so-bloco`. Se a conferência reprovar, o arquivo é RESTAURADO ao
conteúdo anterior e o exit é ≠ 0.

Exit: 0 = ok · 2 = entrada inválida (nada foi escrito) · 3 = bloco reprovado na
conferência (arquivo restaurado) · 4 = erro de ambiente/arquivo.
"""

import argparse
import json
import os
import re
import subprocess
import sys

BEGIN = "<!-- gad:decisoes:begin v1 -->"
END = "<!-- gad:decisoes:end -->"

RE_PONTO = re.compile(r"\S+\.[A-Za-z0-9_]+:\d+(?:-\d+)?")
RE_ANCHOR = re.compile(r"^(?:[A-Z]{1,8}-?\d+|none)$")  # R-n, SC-n ou ID do REQUIREMENTS (DESC-01…)

TIPOS = {
    "decisao": "decisao_dono",
    "decisão": "decisao_dono",
    "decisao_dono": "decisao_dono",
    "medicao": "fato_medido",
    "medição": "fato_medido",
    "fato": "fato_medido",
    "fato_medido": "fato_medido",
}

REVERS = {
    "reversivel": "reversible",
    "reversível": "reversible",
    "reversible": "reversible",
    "cara": "costly",
    "custosa": "costly",
    "costly": "costly",
    "sem-volta": "one-way",
    "sem volta": "one-way",
    "one-way": "one-way",
}

# campo canônico → nomes aceitos na entrada (o primeiro que aparecer vence)
SINONIMOS = {
    "kind": ("tipo", "kind"),
    "area": ("assunto", "area", "área"),
    "req_anchor": ("requisito", "req_anchor"),
    "decisao": ("texto", "decisao", "decisão"),
    "opcoes_descartadas": ("descartadas", "opcoes_descartadas", "opções_descartadas"),
    "evidencia": ("evidencia", "evidência"),
    "reversibilidade": ("reversibilidade",),
    "reversibilidade_justificativa": ("justificativa", "reversibilidade_justificativa"),
    "ressalva": ("ressalva",),
    "span": ("onde", "span", "secao", "seção"),
}


class Recusa(Exception):
    pass


def pega(entrada, canonico):
    for nome in SINONIMOS[canonico]:
        if nome in entrada and entrada[nome] is not None:
            return entrada[nome]
    return None


def texto(valor):
    return "" if valor is None else str(valor).strip()


def reproduzivel(ev):
    ev = ev.strip()
    return ev.lower() != "none" and bool(RE_PONTO.search(ev) or "→" in ev or "->" in ev)


def converte(entradas):
    if not isinstance(entradas, list):
        raise Recusa("a entrada tem de ser um array JSON de objetos")
    if len(entradas) > 99:
        raise Recusa(
            f"{len(entradas)} entradas: o contrato v1 usa ids PS-01..PS-99 "
            "(`^PS-\\d\\d$`) e não tem casa para a 100ª"
        )
    saida = []
    for i, e in enumerate(entradas, 1):
        rot = f"entrada #{i}"
        if not isinstance(e, dict):
            raise Recusa(f"{rot}: não é um objeto")
        desconhecidos = set(e) - {n for nomes in SINONIMOS.values() for n in nomes}
        if desconhecidos:
            raise Recusa(
                f"{rot}: campo(s) que não sei traduzir: {sorted(desconhecidos)} — "
                f"use um destes nomes: {sorted(n for ns in SINONIMOS.values() for n in ns)}"
            )

        tipo_bruto = texto(pega(e, "kind")).lower()
        if tipo_bruto not in TIPOS:
            raise Recusa(f"{rot}: `tipo` ausente ou inválido ({tipo_bruto!r}); use 'decisao' ou 'medicao'")
        kind = TIPOS[tipo_bruto]

        area = texto(pega(e, "area"))
        decisao = texto(pega(e, "decisao"))
        span = texto(pega(e, "span"))
        for nome, valor in (("assunto", area), ("texto", decisao), ("onde", span)):
            if not valor:
                raise Recusa(f"{rot}: `{nome}` é obrigatório e veio vazio")

        anchor = texto(pega(e, "req_anchor")) or "none"
        if not RE_ANCHOR.match(anchor):
            raise Recusa(f"{rot}: `requisito` inválido ({anchor!r}); use R-n, SC-n, o ID do REQUIREMENTS (ex. DESC-01) ou deixe vazio")

        rev_bruto = texto(pega(e, "reversibilidade")).lower()
        if rev_bruto not in REVERS:
            raise Recusa(
                f"{rot}: `reversibilidade` ausente ou inválida ({rev_bruto!r}); "
                "use 'reversivel', 'cara' ou 'sem-volta'"
            )
        rev = REVERS[rev_bruto]

        ev = texto(pega(e, "evidencia")) or "none"
        if kind == "fato_medido" and not reproduzivel(ev):
            raise Recusa(
                f"{rot}: é uma medição e a evidência ({ev!r}) não é reproduzível. "
                "Número sem fonte executada nesta sessão NÃO é fato_medido: deixe-o no corpo "
                "do PRE-SPEC marcado `[herdado]`, ou meça de novo e cite `arquivo:linha` "
                "ou `comando → saída`."
            )

        just = texto(pega(e, "reversibilidade_justificativa"))
        if rev in ("costly", "one-way") and not just:
            raise Recusa(f"{rot}: reversibilidade '{rev_bruto}' exige `justificativa`")

        descartadas = pega(e, "opcoes_descartadas") or []
        if not isinstance(descartadas, list):
            raise Recusa(f"{rot}: `descartadas` tem de ser lista")
        descartadas = [texto(d) for d in descartadas if texto(d)]

        ressalva = texto(pega(e, "ressalva"))

        item = {
            "id": f"PS-{i:02d}",
            "kind": kind,
            "area": area,
            "req_anchor": anchor,
            "decisao": decisao,
            "evidencia": ev,
            "reversibilidade": rev,
            "span": span,
        }
        # opcionais: presentes só quando têm conteúdo (o contrato rejeita campo vazio)
        if descartadas:
            item["opcoes_descartadas"] = descartadas
        if just:
            item["reversibilidade_justificativa"] = just
        if ressalva:
            item["ressalva"] = ressalva
        saida.append(item)
    return saida


def substitui_bloco(original, bloco_json):
    linhas = original.split("\n")
    ini = fim = None
    for n, l in enumerate(linhas):
        if BEGIN in l and ini is None:
            ini = n
        elif END in l and ini is not None and fim is None:
            fim = n
    if ini is None or fim is None:
        raise Recusa(
            f"não achei as marcas {BEGIN} … {END} no arquivo — "
            "gere o esqueleto pelo templates/PRE-SPEC.md antes"
        )
    return "\n".join(linhas[: ini + 1] + bloco_json.split("\n") + linhas[fim:])


def acha_confere(explicito):
    if explicito:
        return explicito
    aqui = os.path.dirname(os.path.realpath(__file__))
    candidatos = [
        os.path.join(aqui, "..", "..", "go-and-do", "scripts", "confere-pre-spec.sh"),
        os.path.join(os.path.expanduser("~"), ".claude", "skills", "go-and-do",
                     "scripts", "confere-pre-spec.sh"),
    ]
    for c in candidatos:
        c = os.path.normpath(c)
        if os.path.isfile(c):
            return c
    return None


def main():
    p = argparse.ArgumentParser(add_help=True, description="monta o bloco gad:decisoes do PRE-SPEC")
    p.add_argument("--entrada", required=True, help="JSON com as respostas da entrevista ('-' = stdin)")
    p.add_argument("--arquivo", help="NN-PRE-SPEC.md a atualizar (obrigatório fora do --stdout)")
    p.add_argument("--saida", help="grava noutro caminho em vez de sobrescrever --arquivo")
    p.add_argument("--stdout", action="store_true", help="só imprime o bloco JSON, não escreve nada")
    p.add_argument("--confere", help="caminho do confere-pre-spec.sh")
    p.add_argument("--sem-conferir", action="store_true",
                   help="pula a conferência (só para diagnóstico — a skill NUNCA usa)")
    a = p.parse_args()

    try:
        bruto = sys.stdin.read() if a.entrada == "-" else open(a.entrada, encoding="utf-8").read()
    except OSError as e:
        print(f"ERRO: não consegui ler a entrada: {e}", file=sys.stderr)
        return 4
    try:
        entradas = json.loads(bruto)
    except json.JSONDecodeError as e:
        print(f"ERRO: entrada não é JSON válido: {e}", file=sys.stderr)
        return 2

    try:
        itens = converte(entradas)
    except Recusa as e:
        print(f"RECUSADO: {e}", file=sys.stderr)
        return 2

    bloco = json.dumps(itens, ensure_ascii=False, indent=2)

    if a.stdout:
        print(bloco)
        return 0

    if not a.arquivo:
        print("ERRO: --arquivo é obrigatório (ou use --stdout)", file=sys.stderr)
        return 2
    try:
        original = open(a.arquivo, encoding="utf-8").read()
    except OSError as e:
        print(f"ERRO: não consegui ler {a.arquivo}: {e}", file=sys.stderr)
        return 4

    try:
        novo = substitui_bloco(original, bloco)
    except Recusa as e:
        print(f"RECUSADO: {e}", file=sys.stderr)
        return 2

    alvo = a.saida or a.arquivo
    anterior = original if alvo == a.arquivo else None
    with open(alvo, "w", encoding="utf-8") as fh:
        fh.write(novo)

    if a.sem_conferir:
        print(f"bloco gravado em {alvo}: {len(itens)} entrada(s) — conferência PULADA")
        return 0

    confere = acha_confere(a.confere)
    if not confere:
        if anterior is not None:
            open(alvo, "w", encoding="utf-8").write(anterior)
        print("ERRO: não achei o confere-pre-spec.sh (use --confere <caminho>); "
              "nada foi gravado", file=sys.stderr)
        return 4

    r = subprocess.run(["bash", confere, "--so-bloco", alvo],
                       capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    if r.returncode != 0:
        if anterior is not None:
            open(alvo, "w", encoding="utf-8").write(anterior)
            print(f"REPROVADO pelo confere-pre-spec.sh (exit {r.returncode}) — "
                  f"{alvo} restaurado ao conteúdo anterior", file=sys.stderr)
        else:
            print(f"REPROVADO pelo confere-pre-spec.sh (exit {r.returncode})", file=sys.stderr)
        return 3

    print(f"bloco gravado em {alvo}: {len(itens)} entrada(s) — conferência OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
