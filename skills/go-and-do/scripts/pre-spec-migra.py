#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pre-spec-migra.py — rascunho do bloco `gad:decisoes` a partir da prosa de um PRE-SPEC.

Uso: pre-spec-migra.py <NN-PRE-SPEC.md> [--max N]

SÓ AJUDA, NUNCA DECIDE. Extrai *candidatos* a decisão/fato do PRE-SPEC legado e devolve,
no stdout, um bloco `<!-- gad:decisoes:begin v1 --> … <!-- gad:decisoes:end -->` com uma
entrada por candidato. Todo campo que o script não consegue inferir sai como "REVISAR" —
o dono (§0.5 do plano: onda 0.5) revisa entrada por entrada antes de o bloco valer.
O rascunho NÃO passa no `confere-pre-spec.sh` de propósito: `REVISAR` não é um enum
válido de `kind`/`reversibilidade`, então um rascunho não revisado nunca é aceito como
bloco de verdade.

De onde vêm os candidatos:
  (a) seções cujo título casa `Recomendação` / `DECISÃO DO DONO`;
  (b) linhas de tabela de decisão (`## 7 Perguntas`, `### 6.1 Travas`, e qualquer tabela
      cuja linha traga DECIDIDA / DECISÃO / MEDIDA);
  (c) seções de medição (título com "medid"/"MEDIDA"/"o que foi medido");
  (d) uma frase por seção contendo "decidido/decisão/opção".

`kind` sugerido: `decisao_dono` quando há "DECISÃO DO DONO"/"decidida pelo dono"/opção
escolhida; `fato_medido` quando há número medido + "medido/medida/zero/N/N".

Aviso de PII: o script marca (no stderr) candidatos cujo texto traz e-mail ou padrão de
nome próprio de pessoa — quem grava o rascunho decide o que fazer. Ele não redige sozinho.
"""

import json, re, sys

RE_HEADING = re.compile(r'^(#{1,6})\s+(.*?)\s*$')
RE_TABELA  = re.compile(r'^\s*\|')
RE_SEP     = re.compile(r'^\s*\|[\s:|-]+\|\s*$')
RE_PONTO   = re.compile(r'[A-Za-z0-9_./-]+\.[A-Za-z0-9_]+:~?\d+(?:-\d+)?')
RE_OPCAO   = re.compile(r'Op[çc][ãa]o\s+([A-Z])\b')
RE_EMAIL   = re.compile(r'[\w.+-]+@[\w-]+\.[\w.]+')

RE_DONO = re.compile(
    r'DECIS[ÃA]O DO DONO|DECIDIDA pelo dono|decis[ãa]o do dono|por decis[ãa]o do dono'
    r'|escolhid[ao]|é o menor conserto|fica dentro do escopo', re.I)
RE_MEDIDO = re.compile(r'\bmedid[ao]s?\b|\bMEDIDA\b|\bzero\b|\b\d+/\d+\b', re.I)
RE_NUM    = re.compile(r'\d')
RE_FRASE_DEC = re.compile(r'decidid|decis[ãa]o|op[çc][ãa]o', re.I)
RE_TIT_MEDIDO = re.compile(r'medid|o que foi medido', re.I)
RE_TIT_DONO   = re.compile(r'recomenda|decis[ãa]o do dono', re.I)


def limpa(t):
    t = re.sub(r'`([^`]*)`', r'\1', t)
    t = t.replace('**', '').replace('__', '')
    t = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', t)
    t = re.sub(r'\s+', ' ', t)
    return t.strip(' -–—•')


def corta(t, n=320):
    t = limpa(t)
    return t if len(t) <= n else t[: n - 1].rstrip() + '…'


def secoes(linhas):
    """[(nivel, titulo, linha_ini, corpo[])] — o preâmbulo entra como seção nível 0."""
    out, atual = [], [0, '(preâmbulo)', 1, []]
    for n, l in enumerate(linhas, 1):
        m = RE_HEADING.match(l)
        if m:
            out.append(atual)
            atual = [len(m.group(1)), limpa(m.group(2)), n, []]
        else:
            atual[3].append(l)
    out.append(atual)
    return [s for s in out if s[1] != '(preâmbulo)' or any(x.strip() for x in s[3])]


def kind_de(texto):
    if RE_DONO.search(texto):
        return 'decisao_dono'
    if RE_MEDIDO.search(texto) and RE_NUM.search(texto):
        return 'fato_medido'
    return 'REVISAR'


def frases(corpo):
    txt = ' '.join(l for l in corpo if not RE_TABELA.match(l))
    txt = limpa(txt)
    return [f.strip() for f in re.split(r'(?<=[.!?])\s+(?=[A-ZÁÉÍÓÚÂÊÔÃÕÇ])', txt) if len(f.strip()) > 40]


def candidato(origem, area, texto, corpo_secao, kind=None):
    texto = corta(texto)
    ev = RE_PONTO.search(' '.join(corpo_secao) + ' ' + texto)
    descartadas = sorted({f'Opção {m.group(1)}' for m in RE_OPCAO.finditer(' '.join(corpo_secao))})
    return {
        'id': None,
        'kind': kind or kind_de(texto),
        'area': area or 'REVISAR',
        'req_anchor': 'REVISAR',
        'decisao': texto,
        'opcoes_descartadas': descartadas or ['REVISAR'],
        'evidencia': ev.group(0) if ev else 'REVISAR',
        'reversibilidade': 'REVISAR',
        'reversibilidade_justificativa': 'REVISAR',
        'ressalva': 'REVISAR',
        'span': origem,
    }


def extrai(caminho, maximo):
    linhas = open(caminho, encoding='utf-8', errors='replace').read().split('\n')
    cands, vistos = [], set()

    def junta(c):
        chave = c['decisao'][:120].lower()
        if chave in vistos:
            return
        vistos.add(chave)
        cands.append(c)

    for nivel, titulo, ini, corpo in secoes(linhas):
        origem = f'§{titulo}' if titulo != '(preâmbulo)' else '§(preâmbulo)'
        fs = frases(corpo)

        # (a) seção de recomendação / decisão do dono
        if RE_TIT_DONO.search(titulo):
            alvo = next((f for f in fs if RE_DONO.search(f) or RE_OPCAO.search(f)), fs[0] if fs else '')
            if alvo:
                junta(candidato(origem, titulo, alvo, corpo, kind='decisao_dono'))

        # (b) tabelas de decisão
        for l in corpo:
            if not RE_TABELA.match(l) or RE_SEP.match(l):
                continue
            celulas = [limpa(c) for c in l.strip().strip('|').split('|')]
            texto = ' — '.join(c for c in celulas if c)
            if not re.search(r'DECIDIDA|DECIS[ÃA]O|MEDIDA', texto):
                continue
            junta(candidato(origem, titulo, texto, corpo))

        # (c) seção de medição
        if RE_TIT_MEDIDO.search(titulo):
            alvo = next((f for f in fs if RE_MEDIDO.search(f) and RE_NUM.search(f)), None)
            if alvo:
                junta(candidato(origem, titulo, alvo, corpo, kind='fato_medido'))
            elif RE_NUM.search(titulo):
                junta(candidato(origem, titulo, titulo, corpo, kind='fato_medido'))

        # (d) uma frase de decisão por seção
        alvo = next((f for f in fs if RE_FRASE_DEC.search(f)), None)
        if alvo:
            junta(candidato(origem, titulo, alvo, corpo))

        if len(cands) >= maximo:
            break

    for i, c in enumerate(cands[:maximo], 1):
        c['id'] = f'PS-{i:02d}'
    return cands[:maximo]


def main():
    args = [a for a in sys.argv[1:]]
    maximo = 40
    if '--max' in args:
        i = args.index('--max')
        maximo = int(args[i + 1]); del args[i:i + 2]
    if len(args) != 1:
        print(__doc__.strip().split('\n')[2], file=sys.stderr)
        return 2
    cands = extrai(args[0], maximo)
    if not cands:
        print('nenhum candidato encontrado — migre à mão', file=sys.stderr)

    for c in cands:
        alvo = f"{c['decisao']} {c['area']}"
        if RE_EMAIL.search(alvo):
            print(f"AVISO-PII {c['id']}: e-mail no texto do candidato", file=sys.stderr)

    print('<!-- gad:decisoes:begin v1 -->')
    print(json.dumps(cands, ensure_ascii=False, indent=2))
    print('<!-- gad:decisoes:end -->')
    print(f'{len(cands)} candidato(s): '
          + ' · '.join(f'{k}={sum(1 for c in cands if c["kind"] == k)}'
                       for k in ('decisao_dono', 'fato_medido', 'REVISAR')), file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
