#!/usr/bin/env python3
# confere-documento.py — conferidor determinístico do documento único de intenção
# (`NN-CONTEXT.md` no formato `<!-- gad:documento-unico: v1 -->`, ADR 0001, plano 06-04).
# Um conferidor só para o comando `/gad-discuss-phase` (antes do «ok») e para a Go & Do
# (fim de cada ciclo da consultoria, modo --coerencia), que chama o do runtime.
#
# Uso:
#   confere-documento.py <doc> [--reqs REQUIREMENTS.md] [--coerencia] [--json]
#
# Saída: uma linha `CODIGO arquivo:linha mensagem` por falha, depois `AVISO CODIGO
# arquivo:linha mensagem` por aviso, e o resumo `resumo: falhas=N · avisos=M`. Linha 0 =
# achado do arquivo inteiro (seção ausente, aviso da rodada). Ordem estável: linha, código,
# mensagem. O resumo traz a contagem por código (`· CODIGO=n`). Teto do fork (P18): o modo
# texto mostra no máximo 50 achados (mensagem cortada em 160 caracteres) e diz quantos
# omitiu. `--json` troca tudo por `{"falhas": [...], "avisos": [...]}` (cada item: codigo,
# arquivo, linha, mensagem), sem teto — quem pede o JSON o grava em arquivo.
#
# Códigos (FALHA salvo indicação):
#   DOC-SEM-TITULO        linha 1 não é `# Especificação da fase NN — <nome>`
#   DOC-SEM-MARCA         linha 2 não é `<!-- gad:documento-unico: v1 -->`
#   SECAO-FALTANDO        heading do esqueleto ausente (as 15 seções, AC-09)
#   SECAO-FORA-DE-ORDEM   heading do esqueleto fora da ordem, repetido, ou `## ` que não
#                         faz parte do esqueleto
#   SECAO-DESCARTADA      seção que o ADR descartou: Critérios exigidos, Cobertura do Goal,
#                         Consistência interna, Interview Log, Implementation Notes, qualquer
#                         heading com «Ambiguity» (AC-21), e as tags `<spec_lock>`, `<domain>`,
#                         `<specifics>`
#   DECISAO-AUTOMATICA    linha com a etiqueta de decisão automática (`[auto]`, AC-11)
#   DECISOES-SEM-BLOCO    «Decisões do dono» sem o par `<decisions>` … `</decisions>`
#   DECISOES-ILEGIVEIS    dentro do bloco: bullet em negrito com id que não é D-NN
#                         (`- **AC-…`, `- **R-…`), D-NN fora da gramática `- **D-NN:** texto`,
#                         D-NN com tag `informational`/`folded`/`deferred` (sai do gate), ou —
#                         sem nenhuma D-NN — bloco vazio ou frase com token `D-` seguido de
#                         letra/número (o decisions.cjs leria `could-not-parse`; Armadilha 3)
#   AC-SEM-CLASSE         linha `- [ ] AC-nn` sem `[exigido: <motivo>]` nem `[desejável]`, ou
#                         com os dois
#   EXIGIDO-SEM-MOTIVO    `[exigido]` sem motivo na prosa, ou `motivo` vazio no gsd:acs
#   AC-SEM-ORIGEM         linha de AC sem `[origem: <ids>]` (ou com a lista vazia)
#   AC-ORIGEM-INVALIDA    origem que a cancela não aceita: `PS-nn`/`AA-n` (vocabulário do
#                         PRE-SPEC, que saiu), D-NN fora do `<decisions>`, R-n fora do
#                         gsd:reqs, AC-nn inexistente ou o próprio AC, id fora do padrão, id
#                         de requisito fora do `--reqs`. Aceitos: D-NN existente · `Goal` ·
#                         R-n existente · AC-nn existente (critério derivado) · id de requisito
#                         do milestone · `não-regressão`
#   AVISO ORIGEM-NAO-CONFERIDA  sem `--reqs`, ids de requisito do milestone aceitos pelo
#                         padrão `[A-Z]+-\d+` sem conferir no REQUIREMENTS.md (uma linha)
#   ID-DUPLICADO          D-NN repetido no `<decisions>`, R-n repetido no gsd:reqs ou na
#                         prosa, AC-nn repetido na prosa ou no gsd:acs (AC-15)
#   NUMERO-SEM-FONTE      item de «Situação de hoje» com número (fora de datas ISO, versões
#                         x.y.z e ids D/R/AC) sem `arquivo:linha`, sem comando entre crases e
#                         sem `[herdado]` (AC-13)
#   QUEDA-SEM-TABELA      requisito com `stateful` em `shapes` ou texto que casa uma regex de
#                         `plan-gate-irreversiveis.txt` (mesmo diretório) e sem a tabela
#                         `| Estado de queda | … |` em «Limites e restrições» (AC-20)
#   QUEDA-SEM-GATILHO     tabela de estados de queda sem requisito que a peça
#   QUEDA-AC-NAO-EXIGIDO  AC citado na tabela inexistente ou não exigido, ou linha sem AC
#   ARTEFATOS-SEM-COLUNAS tabela de «Artefatos novos» sem as colunas
#                         `Caminho | Público? | Dado pessoal? | Quem grava`, ou seção vazia
#   BORDAS-VAZIA          «Edge Coverage (Bordas)» sem linha de tabela e sem frase de motivo
#                         (a linha `**Coverage:**` não conta como motivo; AC-19)
#   BLOCO-INVALIDO        marcas do gsd:reqs/gsd:scope/gsd:acs ausentes ou repetidas, JSON
#                         inválido, chave duplicada (object_pairs_hook), item sem `id`,
#                         item de gsd:reqs sem `text_en`, classe/origem inválida no gsd:acs
#   PROSA-BLOCO-DIVERGE   AC na prosa e não no gsd:acs (ou o contrário), classe ou origem
#                         diferentes entre os dois, requisitos da prosa ≠ itens do gsd:reqs
#
# --coerencia roda só BLOCO-INVALIDO, ID-DUPLICADO e PROSA-BLOCO-DIVERGE (fim de cada ciclo
# da consultoria, AC-40). Sem a flag, roda tudo.
# Exit: 0 = ok (avisos não reprovam) · 1 = falha · 2 = uso ou erro de leitura.
# Régua: só python3 da stdlib; leitura linear, regex ancoradas por linha. O conferidor não
# roda o decisions.cjs (seria dependência do motor): replica as regras de gramática dele.
import json
import os
import re
import sys
import unicodedata

MARCA = "<!-- gad:documento-unico: v1 -->"
RE_TITULO = re.compile(r"^# Especificação da fase (\d+(?:\.\d+)*[A-Za-z]?) — \S.*$")

ESQUELETO = [
    "Goal",
    "Situação de hoje",
    "Decisões do dono",
    "Requisitos",
    "Critérios de aceite",
    "Limites e restrições",
    "Prohibitions (Proibições)",
    "Edge Coverage (Bordas)",
    "Regression Surface",
    "Artefatos novos",
    "Limitações declaradas",
    "A critério do planner (Claude's Discretion)",
    "Pendências e ideias adiadas",
    "Referências e mapa do código",
    "Bloco da máquina",
]
DESCARTADAS = ("Critérios exigidos", "Cobertura do Goal", "Consistência interna",
               "Interview Log", "Implementation Notes")
TAGS_DESCARTADAS = ("<spec_lock>", "<domain>", "<specifics>")
COLUNAS_ARTEFATOS = ["Caminho", "Público?", "Dado pessoal?", "Quem grava"]
NAO_RASTREAVEIS = {"informational", "folded", "deferred"}
BLOCOS = ("reqs", "scope", "acs")

RE_HEADING = re.compile(r"^(#{1,6})[ \t]+(.+?)[ \t]*$")
RE_FENCE = re.compile(r"^\s*(?:```|~~~)")
RE_AUTO = re.compile(r"\[auto\]", re.I)
# decisions.cjs: DECISION_ID_SOURCE, boldLeadInBulletRe, ID_ATTEMPT_SOURCE, decisionTokenRe
RE_BULLET_ID = re.compile(r"^\s*-\s+\*\*([A-Z]+[0-9]*-[A-Za-z0-9][A-Za-z0-9_-]*)")
RE_BULLET_TENTATIVA = re.compile(r"^\s*-\s+\*\*D(?:[0-9][A-Za-z0-9]*)?-")
RE_BULLET_D = re.compile(r"^\s*-\s+\*\*(D-\d+)(?:\s*\[([^\]]+)\])?:\*\*\s*\S")
RE_TOKEN_D = re.compile(r"\bD[0-9]*-[A-Za-z0-9]", re.ASCII)
RE_AC_LINHA = re.compile(r"^\s*-\s+\[[ xX]\]\s+(AC-\d+)\b")
RE_EXIGIDO = re.compile(r"\[exigido(?::([^\]]*))?\]")
RE_DESEJAVEL = re.compile(r"\[desej[aá]vel\]")
RE_ORIGEM = re.compile(r"\[origem:([^\]]*)\]")
RE_REQ_PROSA = re.compile(r"^(?:(\d+)\.\s+\*\*(?:R-?(\d+)\b)?|###\s+R-?(\d+)\b)")
RE_REQ_ID = re.compile(r"^[A-Z][A-Z0-9]*(?:-[A-Za-z0-9]+)*-\d+$")
RE_REQ_ID_TEXTO = re.compile(r"\b[A-Z][A-Z0-9]*(?:-[A-Za-z0-9]+)*-\d+\b")
RE_FONTE_ARQ = re.compile(r"[\w./~-]*[./][\w-]+:\d+")
RE_NUM_ISENTO = re.compile(r"\b\d{4}-\d{2}-\d{2}\b|\bv?\d+(?:\.\d+){2,}\b|\b(?:AC|D|R)-?\d+\b")
RE_TABELA_SEP = re.compile(r"^\|[ \t]*:?-{2,}")

USO = "uso: confere-documento.py <doc> [--reqs REQUIREMENTS.md] [--coerencia] [--json]"
# Teto do stdout do fork (P18, 20 KB): no modo texto, no máximo TETO_LINHAS achados de até
# TETO_MENSAGEM caracteres; o resto vira uma linha de contagem e o --json traz a lista inteira.
TETO_LINHAS = 50
TETO_MENSAGEM = 160


def normaliza(s):
    s = unicodedata.normalize("NFD", s)
    return "".join(c for c in s if unicodedata.category(c) != "Mn").casefold().strip()


def norm_r(rid):
    m = re.fullmatch(r"R-?(\d+)", rid.strip())
    return f"R{int(m.group(1))}" if m else rid.strip()


def norm_origem(o):
    o = o.strip()
    if normaliza(o) == "nao-regressao":
        return "não-regressão"
    if re.fullmatch(r"R-?\d+", o):
        return norm_r(o)
    return o


def descartada(texto):
    if "ambiguity" in texto.lower():
        return True
    return any(texto.startswith(d) for d in DESCARTADAS)


def celulas(linha):
    return [c.strip() for c in linha.strip().strip("|").split("|")]


class ChaveDuplicada(ValueError):
    pass


def sem_duplicata(pares):
    d = {}
    for k, v in pares:
        if k in d:
            raise ChaveDuplicada(f"chave duplicada no JSON do bloco: {k!r}")
        d[k] = v
    return d


class Conferencia:
    def __init__(self, caminho, linhas, ids_reqs):
        self.arq = caminho
        self.L = linhas
        self.ids_reqs = ids_reqs          # None = sem --reqs
        self.falhas = []
        self.avisos = []
        self.cerca = self._marca_cercas()
        self.h2 = [(i + 1, m.group(2)) for i, l in enumerate(linhas)
                   if not self.cerca[i] and (m := RE_HEADING.match(l)) and len(m.group(1)) == 2]
        self.decisoes = self._le_decisoes()
        self.acs_prosa = self._le_acs_prosa()
        self.reqs_prosa = self._le_reqs_prosa()
        self.bloco = {b: self._le_bloco(b) for b in BLOCOS}

    def falha(self, codigo, linha, msg):
        self.falhas.append((linha, codigo, msg))

    def aviso(self, codigo, linha, msg):
        self.avisos.append((linha, codigo, msg))

    def _marca_cercas(self):
        dentro, marcas = False, []
        for l in self.L:
            if RE_FENCE.match(l):
                marcas.append(True)
                dentro = not dentro
            else:
                marcas.append(dentro)
        return marcas

    # --- leitura -------------------------------------------------------------
    def secao(self, nome):
        """(linha do heading, [índices 0-based do corpo]) da primeira `## nome`, ou None."""
        for k, (n, texto) in enumerate(self.h2):
            if texto == nome:
                fim = self.h2[k + 1][0] - 1 if k + 1 < len(self.h2) else len(self.L)
                return n, list(range(n, fim))
        return None

    def _le_decisoes(self):
        """(linha de <decisions>, linha de </decisions>) — 1-based — ou None."""
        ini = fim = None
        for i, l in enumerate(self.L):
            s = l.strip()
            if ini is None and s == "<decisions>":
                ini = i + 1
            elif ini is not None and s == "</decisions>":
                fim = i + 1
                break
        return (ini, fim) if ini is not None and fim is not None else None

    def _le_acs_prosa(self):
        acs = []
        for i, l in enumerate(self.L):
            if self.cerca[i]:
                continue
            m = RE_AC_LINHA.match(l)
            if not m:
                continue
            ex, de = RE_EXIGIDO.search(l), RE_DESEJAVEL.search(l)
            origens = RE_ORIGEM.findall(l)
            acs.append({
                "id": m.group(1), "linha": i + 1, "texto": l,
                "exigido": ex, "desejavel": de,
                "classe": None if (ex and de) or not (ex or de) else ("exigido" if ex else "desejavel"),
                "origem": None if not origens else [o.strip() for o in origens[-1].split(",") if o.strip()],
            })
        return acs

    def _le_reqs_prosa(self):
        sec = self.secao("Requisitos")
        if sec is None:
            return None
        reqs = []
        for i in sec[1]:
            if self.cerca[i]:
                continue
            m = RE_REQ_PROSA.match(self.L[i])
            if m:
                num = m.group(2) or m.group(3) or m.group(1)
                reqs.append((f"R{int(num)}", i + 1))
        return reqs

    def _le_bloco(self, nome):
        """{'ini', 'fim', 'dados' | 'erro'} ou {'erro', 'ini': linha} — linhas 1-based."""
        ab, fe = f"<!-- gad:{nome}:begin -->", f"<!-- gad:{nome}:end -->"
        ini = [i + 1 for i, l in enumerate(self.L) if l.strip() == ab]
        fim = [i + 1 for i, l in enumerate(self.L) if l.strip() == fe]
        if not ini or not fim:
            return {"ini": 0, "fim": 0, "erro": f"marcas `{ab}` … `{fe}` ausentes"}
        if len(ini) > 1 or len(fim) > 1:
            return {"ini": ini[1] if len(ini) > 1 else fim[1], "fim": 0,
                    "erro": f"marcas do gad:{nome} repetidas"}
        a, b = ini[0], fim[0]
        if b < a:
            return {"ini": a, "fim": b, "erro": f"`{fe}` vem antes de `{ab}`"}
        bruto = "\n".join(self.L[a:b - 1])
        try:
            dados = json.loads(bruto, object_pairs_hook=sem_duplicata)
        except ChaveDuplicada as e:
            return {"ini": a, "fim": b, "erro": str(e)}
        except json.JSONDecodeError as e:
            return {"ini": a, "fim": b, "erro": f"JSON inválido ({e.msg}, linha {a + e.lineno})"}
        return {"ini": a, "fim": b, "dados": dados}

    def linha_do_id(self, nome, ident):
        b = self.bloco[nome]
        alvo = re.compile(r'"id"\s*:\s*"' + re.escape(ident) + '"')
        for i in range(b.get("ini", 0), max(b.get("fim", 0) - 1, 0)):
            if alvo.search(self.L[i]):
                return i + 1
        return b.get("ini", 0)

    def ids_decisoes(self):
        if self.decisoes is None:
            return []
        a, b = self.decisoes
        out = []
        for i in range(a, b - 1):
            m = RE_BULLET_D.match(self.L[i]) or RE_BULLET_ID.match(self.L[i])
            if m and re.fullmatch(r"D-\d+", m.group(1)):
                out.append((m.group(1), i + 1))
        return out

    def reqs_bloco(self):
        d = self.bloco["reqs"].get("dados")
        if not isinstance(d, list):
            return None
        return [e for e in d if isinstance(e, dict) and isinstance(e.get("id"), str)]

    def acs_bloco(self):
        d = self.bloco["acs"].get("dados")
        if not isinstance(d, list):
            return None
        return [e for e in d if isinstance(e, dict) and isinstance(e.get("id"), str)]

    # --- forma ---------------------------------------------------------------
    def titulo_e_marca(self):
        if not self.L or not RE_TITULO.match(self.L[0]):
            self.falha("DOC-SEM-TITULO", 1,
                       "a linha 1 tem de ser `# Especificação da fase NN — <nome>`")
        if len(self.L) < 2 or self.L[1].strip() != MARCA:
            self.falha("DOC-SEM-MARCA", 2, f"a linha 2 tem de ser `{MARCA}`")

    def esqueleto(self):
        vistos, maior = {}, -1
        for n, texto in self.h2:
            if descartada(texto):
                continue
            if texto not in ESQUELETO:
                self.falha("SECAO-FORA-DE-ORDEM", n, f"«## {texto}» não faz parte do esqueleto de 15 seções")
                continue
            idx = ESQUELETO.index(texto)
            if texto in vistos:
                self.falha("SECAO-FORA-DE-ORDEM", n, f"«## {texto}» repetida (primeira na linha {vistos[texto]})")
                continue
            vistos[texto] = n
            if idx < maior:
                self.falha("SECAO-FORA-DE-ORDEM", n,
                           f"«## {texto}» (seção {idx + 1}) aparece depois de «## {ESQUELETO[maior]}» (seção {maior + 1})")
            maior = max(maior, idx)
        for idx, texto in enumerate(ESQUELETO):
            if texto not in vistos:
                self.falha("SECAO-FALTANDO", 0, f"falta o heading «## {texto}» (seção {idx + 1} do esqueleto)")

    def descartadas(self):
        for i, l in enumerate(self.L):
            if self.cerca[i]:
                continue
            m = RE_HEADING.match(l)
            if m and len(m.group(1)) >= 2 and descartada(m.group(2)):
                self.falha("SECAO-DESCARTADA", i + 1, f"«{l.strip()}» é seção descartada pelo ADR 0001")
                continue
            s = l.strip()
            for tag in TAGS_DESCARTADAS:
                if s.startswith(tag):
                    self.falha("SECAO-DESCARTADA", i + 1, f"`{tag}` é bloco descartado pelo ADR 0001")

    def decisao_automatica(self):
        for i, l in enumerate(self.L):
            if RE_AUTO.search(l):
                self.falha("DECISAO-AUTOMATICA", i + 1,
                           "etiqueta de decisão automática: o documento só traz decisões do dono")

    # --- conteúdo ------------------------------------------------------------
    def decisoes_do_dono(self):
        sec = self.secao("Decisões do dono")
        if sec is None:
            return
        n, corpo = sec
        if self.decisoes is None or not (corpo and corpo[0] < self.decisoes[0] <= corpo[-1] + 1):
            self.falha("DECISOES-SEM-BLOCO", n,
                       "«Decisões do dono» sem o par `<decisions>` … `</decisions>` (o parser lê só o bloco)")
            return
        a, b = self.decisoes
        dentro = list(range(a, b - 1))          # índices 0-based das linhas entre as tags
        tem_d = False
        for i in dentro:
            l = self.L[i]
            mid = RE_BULLET_ID.match(l)
            if mid and not re.fullmatch(r"D-\d+", mid.group(1)):
                self.falha("DECISOES-ILEGIVEIS", i + 1,
                           f"bullet `- **{mid.group(1)}…` dentro de <decisions>: o bloco só aceita `- **D-NN:**` (o parser leria could-not-parse)")
                continue
            if mid or RE_BULLET_TENTATIVA.match(l):
                md = RE_BULLET_D.match(l)
                if not md:
                    self.falha("DECISOES-ILEGIVEIS", i + 1,
                               "decisão fora da gramática `- **D-NN:** texto` (o parser leria could-not-parse)")
                    continue
                tem_d = True
                tags = {t.strip().lower() for t in (md.group(2) or "").split(",") if t.strip()}
                fora = sorted(tags & NAO_RASTREAVEIS)
                if fora:
                    self.falha("DECISOES-ILEGIVEIS", i + 1,
                               f"{md.group(1)} com tag {', '.join(fora)}: tira a decisão do dono do gate de cobertura")
        if not tem_d:
            texto = [self.L[i] for i in dentro if self.L[i].strip()]
            if not texto:
                self.falha("DECISOES-ILEGIVEIS", a,
                           "<decisions> vazio: sem decisão do dono, escreva uma frase dizendo que não há decisão")
            else:
                for i in dentro:
                    if RE_TOKEN_D.search(self.L[i]):
                        self.falha("DECISOES-ILEGIVEIS", i + 1,
                                   "frase de «sem decisão» com token `D-` seguido de letra/número (o parser leria could-not-parse)")

    def criterios(self):
        ids_ac = {ac["id"] for ac in self.acs_prosa}
        ids_d = {d for d, _ in self.ids_decisoes()}
        reqs = self.reqs_bloco()
        ids_r = None if reqs is None else {norm_r(e["id"]) for e in reqs}
        acs_b = {e["id"]: e for e in (self.acs_bloco() or [])}
        nao_conferidos = []
        for ac in self.acs_prosa:
            acid, n, l = ac["id"], ac["linha"], ac["texto"]
            if ac["exigido"] and ac["desejavel"]:
                self.falha("AC-SEM-CLASSE", n, f"{acid} traz `[exigido…]` e `[desejável]` ao mesmo tempo")
            elif not (ac["exigido"] or ac["desejavel"]):
                self.falha("AC-SEM-CLASSE", n, f"{acid} sem `[exigido: <motivo>]` nem `[desejável]`")
            if ac["classe"] == "exigido":
                motivo = (ac["exigido"].group(1) or "").strip()
                ent = acs_b.get(acid)
                if not motivo:
                    self.falha("EXIGIDO-SEM-MOTIVO", n, f"{acid} é `[exigido]` sem motivo: escreva `[exigido: <motivo>]`")
                elif ent is not None and str(ent.get("classe", "")).lower() == "exigido" \
                        and not str(ent.get("motivo") or "").strip():
                    self.falha("EXIGIDO-SEM-MOTIVO", n, f"{acid} é exigido e o `motivo` do gsd:acs está vazio")
            if not ac["origem"]:
                self.falha("AC-SEM-ORIGEM", n, f"{acid} sem `[origem: <ids>]`: critério sem origem é critério que ninguém pediu")
                continue
            for o in ac["origem"]:
                motivo = self._origem_invalida(o, acid, ids_ac, ids_d, ids_r, nao_conferidos)
                if motivo:
                    self.falha("AC-ORIGEM-INVALIDA", n, f"{acid} cita {o}: {motivo}")
        if nao_conferidos:
            vistos = []
            for o in nao_conferidos:
                if o not in vistos:
                    vistos.append(o)
            self.aviso("ORIGEM-NAO-CONFERIDA", 0,
                       f"sem --reqs, aceitos pelo padrão sem conferir no REQUIREMENTS.md: {', '.join(vistos)}")

    def _origem_invalida(self, o, acid, ids_ac, ids_d, ids_r, nao_conferidos):
        if re.fullmatch(r"(?:PS|AA)-\d+", o):
            return "vocabulário do PRE-SPEC, que saiu (aceitos: D-NN, Goal, R-n, id de requisito, não-regressão)"
        if o == "Goal" or normaliza(o) == "nao-regressao":
            return None
        if re.fullmatch(r"D-\d+", o):
            return None if o in ids_d else "decisão inexistente no bloco <decisions>"
        if re.fullmatch(r"R-?\d+", o):
            if ids_r is None:
                return None                     # gsd:reqs inválido: o BLOCO-INVALIDO já reprova
            return None if norm_r(o) in ids_r else "requisito inexistente no gsd:reqs"
        if re.fullmatch(r"AC-\d+", o):
            if o == acid:
                return "o critério cita a si mesmo"
            return None if o in ids_ac else "critério inexistente neste documento"
        if RE_REQ_ID.fullmatch(o):
            if self.ids_reqs is None:
                nao_conferidos.append(o)
                return None
            return None if o in self.ids_reqs else "id fora do REQUIREMENTS.md do --reqs"
        return "id fora do padrão (aceitos: D-NN, Goal, R-n, AC-nn, id de requisito, não-regressão)"

    def numeros_com_fonte(self):
        sec = self.secao("Situação de hoje")
        if sec is None:
            return
        itens, atual = [], None
        for i in sec[1]:
            l = self.L[i]
            s = l.strip()
            if not s or self.cerca[i] or s.startswith("<!--") or s.startswith("|"):
                atual = None
                if s.startswith("|"):
                    itens.append([i + 1, l])
                continue
            if atual is None or re.match(r"^\s*(?:[-*]|\d+\.)\s", l):
                atual = [i + 1, l]
                itens.append(atual)
            else:
                atual[1] += " " + s
        for n, texto in itens:
            if "[herdado]" in texto or "`" in texto or RE_FONTE_ARQ.search(texto):
                continue
            if re.search(r"\d", RE_NUM_ISENTO.sub(" ", texto)):
                self.falha("NUMERO-SEM-FONTE", n,
                           "medição sem fonte executada: cite `arquivo:linha` ou o comando entre crases, ou marque `[herdado]`")

    def estados_de_queda(self, regexes):
        reqs = self.reqs_bloco() or []
        gatilhos = []
        for e in reqs:
            shapes = e.get("shapes") if isinstance(e.get("shapes"), list) else []
            texto = " ".join(str(e.get(k) or "") for k in ("text", "text_en"))
            if "stateful" in shapes:
                gatilhos.append((e["id"], "shape stateful"))
                continue
            for rx in regexes:
                if rx.search(texto):
                    gatilhos.append((e["id"], f"casa `{rx.pattern}` de plan-gate-irreversiveis.txt"))
                    break
        sec = self.secao("Limites e restrições")
        cab, linhas_dados = None, []
        if sec is not None:
            corpo = sec[1]
            for k, i in enumerate(corpo):
                l = self.L[i]
                if l.strip().startswith("|") and normaliza(celulas(l)[0]) == "estado de queda":
                    cab = i + 1
                    j = k + 1
                    if j < len(corpo) and RE_TABELA_SEP.match(self.L[corpo[j]]):
                        j += 1
                    while j < len(corpo) and self.L[corpo[j]].strip().startswith("|"):
                        linhas_dados.append(corpo[j] + 1)
                        j += 1
                    break
        if gatilhos and (cab is None or not linhas_dados):
            for rid, porque in gatilhos:
                self.falha("QUEDA-SEM-TABELA", self.linha_do_id("reqs", rid),
                           f"{rid} ({porque}) exige a tabela «Estado de queda | Comportamento exigido | Mensagem / comando de recuperação | AC» em «Limites e restrições»")
        if cab is not None and not gatilhos:
            self.falha("QUEDA-SEM-GATILHO", cab,
                       "tabela de estados de queda sem requisito stateful nem comando irreversível: tire a tabela ou o gatilho falta no gsd:reqs")
        classe = {ac["id"]: ac["classe"] for ac in self.acs_prosa}
        for n in linhas_dados:
            ids = re.findall(r"AC-\d+", celulas(self.L[n - 1])[-1])
            if not ids:
                self.falha("QUEDA-AC-NAO-EXIGIDO", n, "linha da tabela de estados de queda sem AC")
            for acid in ids:
                if acid not in classe:
                    self.falha("QUEDA-AC-NAO-EXIGIDO", n, f"{acid} citado na tabela de estados de queda não existe")
                elif classe[acid] != "exigido":
                    self.falha("QUEDA-AC-NAO-EXIGIDO", n, f"{acid} citado na tabela de estados de queda não é exigido")

    def _tabelas_e_prosa(self, corpo):
        """(cabeçalhos [(linha, células)], nº de linhas de dados, linhas de prosa) do corpo."""
        cabs, dados, prosa = [], 0, []
        depois_sep = False
        for k, i in enumerate(corpo):
            l, s = self.L[i], self.L[i].strip()
            if self.cerca[i]:
                continue
            if s.startswith("|"):
                if RE_TABELA_SEP.match(s):
                    depois_sep = True
                elif depois_sep:
                    dados += 1
                elif k + 1 < len(corpo) and RE_TABELA_SEP.match(self.L[corpo[k + 1]].strip()):
                    cabs.append((i + 1, celulas(l)))
                continue
            depois_sep = False
            if s and not s.startswith("<!--") and not RE_HEADING.match(l):
                prosa.append((i + 1, s))
        return cabs, dados, prosa

    def artefatos(self):
        sec = self.secao("Artefatos novos")
        if sec is None:
            return
        cabs, _, prosa = self._tabelas_e_prosa(sec[1])
        if not cabs and not prosa:
            self.falha("ARTEFATOS-SEM-COLUNAS", sec[0],
                       "«Artefatos novos» vazia: tabela `| Caminho | Público? | Dado pessoal? | Quem grava |` ou uma frase dizendo que não há")
        for n, cols in cabs:
            if cols != COLUNAS_ARTEFATOS:
                self.falha("ARTEFATOS-SEM-COLUNAS", n,
                           f"colunas {cols} ≠ {COLUNAS_ARTEFATOS}")

    def bordas(self):
        sec = self.secao("Edge Coverage (Bordas)")
        if sec is None:
            return
        _, dados, prosa = self._tabelas_e_prosa(sec[1])
        motivo = [s for _, s in prosa if not s.startswith("**Coverage:**")]
        if dados == 0 and not motivo:
            self.falha("BORDAS-VAZIA", sec[0],
                       "Bordas sem linha de tabela e sem frase de motivo: diga por que nenhuma borda se aplica")

    # --- bloco da máquina, ids e coerência --------------------------------------
    def bloco_valido(self):
        for nome in BLOCOS:
            b = self.bloco[nome]
            if "erro" in b:
                self.falha("BLOCO-INVALIDO", b["ini"], f"gad:{nome}: {b['erro']}")
                continue
            d = b["dados"]
            if nome == "scope":
                if not isinstance(d, dict):
                    self.falha("BLOCO-INVALIDO", b["ini"], "gsd:scope: tem de ser um objeto JSON")
                continue
            if not isinstance(d, list):
                self.falha("BLOCO-INVALIDO", b["ini"], f"gad:{nome}: tem de ser um array JSON")
                continue
            for k, e in enumerate(d):
                if not isinstance(e, dict) or not isinstance(e.get("id"), str) or not e["id"].strip():
                    self.falha("BLOCO-INVALIDO", b["ini"], f"gad:{nome}: item {k + 1} sem `id`")
                    continue
                n = self.linha_do_id(nome, e["id"])
                if nome == "reqs":
                    if not isinstance(e.get("text_en"), str) or not e["text_en"].strip():
                        self.falha("BLOCO-INVALIDO", n, f"gsd:reqs: {e['id']} sem `text_en` (o edge-probe classifica por ele)")
                else:
                    if str(e.get("classe", "")).lower() not in ("exigido", "desejavel"):
                        self.falha("BLOCO-INVALIDO", n, f"gsd:acs: {e['id']} com classe {e.get('classe')!r} (exigido|desejavel)")
                    if not isinstance(e.get("origem"), list) or not all(isinstance(o, str) for o in e["origem"]):
                        self.falha("BLOCO-INVALIDO", n, f"gsd:acs: {e['id']} sem `origem` em lista de ids")

    def ids_duplicados(self):
        def repetidos(pares, onde):
            vistos = {}
            for ident, n in pares:
                if ident in vistos:
                    self.falha("ID-DUPLICADO", n, f"{ident} repetido {onde} (primeiro na linha {vistos[ident]})")
                else:
                    vistos[ident] = n
        repetidos(self.ids_decisoes(), "no <decisions>")
        repetidos(self.reqs_prosa or [], "na prosa de «Requisitos»")
        repetidos([(ac["id"], ac["linha"]) for ac in self.acs_prosa], "nos critérios de aceite")
        for nome, normal in (("reqs", norm_r), ("acs", lambda x: x)):
            itens = (self.reqs_bloco if nome == "reqs" else self.acs_bloco)()
            if itens is not None:
                repetidos([(normal(e["id"]), self.linha_do_id(nome, e["id"])) for e in itens], f"no gad:{nome}")

    def coerencia(self, estrita):
        acs = self.acs_bloco()
        if acs is not None:
            bloco = {}
            for e in acs:
                bloco.setdefault(e["id"], e)
            prosa = {}
            for ac in self.acs_prosa:
                prosa.setdefault(ac["id"], ac)
            for acid, ac in prosa.items():
                e = bloco.get(acid)
                if e is None:
                    self.falha("PROSA-BLOCO-DIVERGE", ac["linha"], f"{acid} está na prosa e não no gsd:acs")
                    continue
                cb = str(e.get("classe", "")).lower()
                if (ac["classe"] is not None or estrita) and ac["classe"] != cb:
                    self.falha("PROSA-BLOCO-DIVERGE", ac["linha"],
                               f"{acid}: prosa diz {ac['classe'] or 'sem classe'} e o gsd:acs diz {cb or 'sem classe'}")
                ob = e.get("origem") if isinstance(e.get("origem"), list) else []
                op = ac["origem"] or []
                if (ac["origem"] is not None or estrita) and \
                        sorted({norm_origem(o) for o in op}) != sorted({norm_origem(str(o)) for o in ob}):
                    self.falha("PROSA-BLOCO-DIVERGE", ac["linha"],
                               f"{acid}: origem da prosa [{', '.join(op)}] ≠ do gsd:acs [{', '.join(map(str, ob))}]")
            for acid in bloco:
                if acid not in prosa:
                    self.falha("PROSA-BLOCO-DIVERGE", self.linha_do_id("acs", acid),
                               f"{acid} está no gsd:acs e não na prosa dos critérios de aceite")
        reqs = self.reqs_bloco()
        if reqs is not None and self.reqs_prosa is not None:
            bloco = {norm_r(e["id"]): e["id"] for e in reqs}
            prosa = {rid: n for rid, n in self.reqs_prosa}
            for rid, n in prosa.items():
                if rid not in bloco:
                    self.falha("PROSA-BLOCO-DIVERGE", n, f"{rid} está na prosa de «Requisitos» e não no gsd:reqs")
            for rid, orig in bloco.items():
                if rid not in prosa:
                    self.falha("PROSA-BLOCO-DIVERGE", self.linha_do_id("reqs", orig),
                               f"{orig} está no gsd:reqs e não na prosa de «Requisitos» ({len(prosa)} na prosa, {len(bloco)} no bloco)")


def carrega_irreversiveis():
    caminho = os.path.join(os.path.dirname(os.path.realpath(__file__)), "plan-gate-irreversiveis.txt")
    regexes = []
    with open(caminho, encoding="utf-8") as fh:
        for l in fh:
            l = l.strip()
            if l and not l.startswith("#"):
                regexes.append(re.compile(l, re.I))
    return regexes


def args_ou_sai(argv):
    doc, reqs, coerencia, como_json = None, None, False, False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--reqs":
            if i + 1 >= len(argv):
                return None
            reqs = argv[i + 1]
            i += 2
            continue
        if a == "--coerencia":
            coerencia = True
        elif a == "--json":
            como_json = True
        elif a.startswith("-"):
            return None
        elif doc is None:
            doc = a
        else:
            return None
        i += 1
    if doc is None:
        return None
    return doc, reqs, coerencia, como_json


def le(caminho):
    with open(caminho, encoding="utf-8") as fh:
        return fh.read()


def main(argv):
    a = args_ou_sai(argv)
    if a is None:
        print(USO, file=sys.stderr)
        return 2
    doc, reqs, coerencia, como_json = a
    try:
        texto = le(doc)
    except (OSError, UnicodeDecodeError) as e:
        print(f"ERRO: não consegui ler o documento {doc}: {e}", file=sys.stderr)
        return 2
    ids_reqs = None
    if reqs is not None:
        try:
            ids_reqs = set(RE_REQ_ID_TEXTO.findall(le(reqs)))
        except (OSError, UnicodeDecodeError) as e:
            print(f"ERRO: não consegui ler o --reqs {reqs}: {e}", file=sys.stderr)
            return 2
    regexes = []
    if not coerencia:
        try:
            regexes = carrega_irreversiveis()
        except (OSError, UnicodeDecodeError, re.error) as e:
            print(f"ERRO: não consegui ler plan-gate-irreversiveis.txt ao lado do script: {e}", file=sys.stderr)
            return 2

    c = Conferencia(doc, texto.split("\n"), ids_reqs)
    c.bloco_valido()
    c.ids_duplicados()
    c.coerencia(estrita=coerencia)
    if not coerencia:
        c.titulo_e_marca()
        c.esqueleto()
        c.descartadas()
        c.decisao_automatica()
        c.decisoes_do_dono()
        c.criterios()
        c.numeros_com_fonte()
        c.estados_de_queda(regexes)
        c.artefatos()
        c.bordas()

    falhas, avisos = sorted(set(c.falhas)), sorted(set(c.avisos))
    if como_json:
        item = lambda t: {"codigo": t[1], "arquivo": doc, "linha": t[0], "mensagem": t[2]}
        print(json.dumps({"falhas": [item(t) for t in falhas], "avisos": [item(t) for t in avisos]},
                         ensure_ascii=False, indent=2))
    else:
        linhas = [f"{cod} {doc}:{n} {corta(msg)}" for n, cod, msg in falhas] + \
                 [f"AVISO {cod} {doc}:{n} {corta(msg)}" for n, cod, msg in avisos]
        for l in linhas[:TETO_LINHAS]:
            print(l)
        if len(linhas) > TETO_LINHAS:
            print(f"… mais {len(linhas) - TETO_LINHAS} achado(s) omitido(s) do stdout (teto de 20 KB); a lista inteira sai com --json")
        contagem = {}
        for _, cod, _ in falhas + avisos:
            contagem[cod] = contagem.get(cod, 0) + 1
        por_codigo = "".join(f" · {k}={v}" for k, v in sorted(contagem.items()))
        print(f"resumo: falhas={len(falhas)} · avisos={len(avisos)}{por_codigo}")
    return 1 if falhas else 0


def corta(msg):
    return msg if len(msg) <= TETO_MENSAGEM else msg[:TETO_MENSAGEM - 1] + "…"


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
