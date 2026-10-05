#!/usr/bin/env python3
"""context-render.py — monta o documento único de intenção (NN-CONTEXT.md) a partir do depósito
da fase (NN-DISCUSS-CHECKPOINT.json) e o promove ao diretório da fase (fork, plano 06-13, D-12).

O render é FUNÇÃO PURA do depósito: o mesmo depósito rende o mesmo documento, byte a byte
(nada de data/hora, nada de ordem de dicionário). Ele grava só num RASCUNHO; quem põe o
documento no lugar é a PROMOÇÃO, e ela só acontece com a aprovação do dono gravada no
depósito (`checkpoint-write.py aprovar --sha256 <sha do rascunho>`).

Uso:
  context-render.py <ckpt> --out <rascunho>
      Grava o rascunho (temporário irmão + os.replace) e imprime UMA linha
      `{"out", "bytes", "sha256", "vazias"}` — `vazias` lista os slugs de seção ainda sem
      texto no depósito (a guarda reprova por eles). O documento nunca vai ao stdout
      (teto de 20 KB dos scripts do fork, P18). Sem --out → exit 2.
  context-render.py --promover <rascunho> <destino> --sha256 <hex> [--ckpt <ckpt>]
      Confere sha256(rascunho) == --sha256 == `aprovado_sha256` do depósito (de --ckpt ou
      do env CKPT); qualquer divergência, depósito ausente ou sem aprovação → exit 2 e o
      destino fica como estava. Senão copia o rascunho para um temporário irmão do destino
      (`.<nome>.promo-*`), faz fsync e troca por os.replace: um kill antes da troca deixa o
      destino ausente (ou o anterior intacto), nunca pela metade. Temporários de uma promoção
      que morreu são apagados na seguinte.

Moldura (a do `<interfaces>` do 06-04, conferida pelo confere-documento.py):
  linha 1 `# Especificação da fase <NN> — <nome>` · linha 2 `<!-- gad:documento-unico: v1 -->`
  15 seções `## …` na ordem do esqueleto; «Decisões do dono» = `<decisions>` com uma linha
  `- **D-NN:** <resposta>` por decisão do dono (ordem numérica do id), a prosa da decisão
  indentada embaixo e neutralizada; sem decisão → frase sem token `D-`. «Pendências» dentro de
  `<deferred>`; «Referências» = `<canonical_refs>` + `<code_context>`; «Bloco da máquina» = os
  três JSON do depósito entre as marcas gsd:reqs/gsd:scope/gsd:acs, verbatim.
  O texto das seções vem do depósito como está; só fechamentos/aberturas das tags que a
  moldura usa são neutralizados (um `</decisions>` solto quebraria o parser).

Regras de neutralização da prosa da decisão (o parser downstream, decisions.cjs, lê qualquer
`- **D-NN:**` dentro de <decisions>):
  linha começando por `#`            → prefixo `\\#`
  linha começando por `- **`/`* **`  → prefixo `·`
  fence ```                          → removido
  `</tag>` de tags conhecidas        → `&lt;/tag>`
Stdlib apenas.
"""
import argparse
import hashlib
import json
import os
import re
import sys
import tempfile

KNOWN_TAGS = ("decisions", "domain", "spec_lock", "canonical_refs", "code_context",
              "specifics", "deferred", "plan", "task", "reversibility", "user_constraints")
CLOSE_RE = re.compile(r"</(" + "|".join(KNOWN_TAGS) + r")\b", re.I)
OPEN_RE = re.compile(r"<(task|plan|decisions|reversibility|deferred|canonical_refs|code_context)\b", re.I)
ID_RE = re.compile(r"^D-(\d+)$")

MARCA = "<!-- gad:documento-unico: v1 -->"
# (heading, slug no depósito). None = seção montada pela moldura.
SECOES = [
    ("Goal", "goal"),
    ("Situação de hoje", "situacao"),
    ("Decisões do dono", None),
    ("Requisitos", "requisitos"),
    ("Critérios de aceite", "criterios"),
    ("Limites e restrições", "limites"),
    ("Prohibitions (Proibições)", "proibicoes"),
    ("Edge Coverage (Bordas)", "bordas"),
    ("Regression Surface", "regression"),
    ("Artefatos novos", "artefatos"),
    ("Limitações declaradas", "limitacoes"),
    ("A critério do planner (Claude's Discretion)", "discricao"),
    ("Pendências e ideias adiadas", "pendencias"),
    ("Referências e mapa do código", None),
    ("Bloco da máquina", None),
]
SLUGS = ("goal", "situacao", "requisitos", "criterios", "limites", "proibicoes", "bordas",
         "regression", "artefatos", "limitacoes", "discricao", "pendencias", "referencias",
         "codigo", "reqs_json", "scope_json", "acs_json")
SEM_DECISAO = "Nenhuma decisão do dono registrada nesta fase."


def die(msg, code=2):
    sys.stderr.write(f"[context-render] ERROR: {msg}\n")
    sys.exit(code)


def neutralize(text):
    out = []
    for ln in (text or "").splitlines():
        s = ln.rstrip()
        if s.strip().startswith("```"):
            continue
        if s.lstrip().startswith("#"):
            s = s.replace("#", "\\#", 1)
        if re.match(r"^\s*[-*]\s+\*\*", s):
            s = "· " + s.lstrip()[2:]
        s = CLOSE_RE.sub(lambda m: "&lt;/" + m.group(1), s)
        s = OPEN_RE.sub(lambda m: "&lt;" + m.group(1), s)
        out.append(s)
    return out


def inline(text):
    """Texto de 1 linha (resposta, nome): sem quebras, sem tags da moldura."""
    s = " ".join((text or "").split())
    s = CLOSE_RE.sub(lambda m: "&lt;/" + m.group(1), s)
    s = OPEN_RE.sub(lambda m: "&lt;" + m.group(1), s)
    return s


def tags_only(text):
    """Texto de seção: verbatim, só as tags da moldura neutralizadas."""
    s = (text or "").strip("\n")
    s = CLOSE_RE.sub(lambda m: "&lt;/" + m.group(1), s)
    return OPEN_RE.sub(lambda m: "&lt;" + m.group(1), s)


def decisoes(data):
    """Decisões do dono em ordem numérica do id (estável: não depende de ordem de dicionário)."""
    todas = []
    areas = [a.get("name") for a in (data.get("areas") or []) if isinstance(a, dict)]
    decs = data.get("decisions") or {}
    for k, area in enumerate(areas + sorted(a for a in decs if a not in areas)):
        for j, d in enumerate(decs.get(area) or []):
            if d.get("origin", "owner") != "owner":
                continue          # o depósito só aceita o dono; um depósito antigo não vaza decisão automática
            m = ID_RE.match(str(d.get("id") or ""))
            todas.append(((int(m.group(1)) if m else 10 ** 9), k, j, d))
    return [d for *_, d in sorted(todas, key=lambda x: x[:3])]


def bloco_decisoes(data):
    linhas = []
    for d in decisoes(data):
        linhas.append(f"- **{d['id']}:** {inline(d.get('answer'))}")
        for pl in neutralize(d.get("prose")):
            linhas.append(("  " + pl) if pl.strip() else "")
    return "<decisions>\n" + "\n".join(linhas or [SEM_DECISAO]) + "\n</decisions>"


def tag(nome, texto):
    corpo = tags_only(texto)
    return f"<{nome}>\n" + (corpo + "\n" if corpo else "") + f"</{nome}>"


def render(data):
    sec = data.get("secoes") or {}
    phase = str(data.get("phase", "")).strip()
    nome = inline(data.get("phase_name") or "")
    partes = [f"# Especificação da fase {phase} — {nome}\n{MARCA}"]
    for heading, slug in SECOES:
        if heading == "Decisões do dono":
            corpo = bloco_decisoes(data)
        elif heading == "Pendências e ideias adiadas":
            corpo = tag("deferred", sec.get("pendencias"))
        elif heading == "Referências e mapa do código":
            corpo = tag("canonical_refs", sec.get("referencias")) + "\n\n" + tag("code_context", sec.get("codigo"))
        elif heading == "Bloco da máquina":
            blocos = []
            for k in ("reqs", "scope", "acs"):
                js = (sec.get(k + "_json") or "").strip("\n")
                blocos.append(f"<!-- gad:{k}:begin -->\n" + (js + "\n" if js else "") + f"<!-- gad:{k}:end -->")
            corpo = "\n\n".join(blocos)
        else:
            corpo = tags_only(sec.get(slug))
        partes.append(f"## {heading}" + (f"\n\n{corpo}" if corpo else ""))
    return "\n\n".join(partes) + "\n"


def vazias(data):
    sec = data.get("secoes") or {}
    return [s for s in SLUGS if not str(sec.get(s) or "").strip()]


def troca_atomica(destino, dados):
    """Temporário irmão do destino + fsync + os.replace. Devolve nada; erro de E/S sobe."""
    d = os.path.dirname(os.path.abspath(destino)) or "."
    base = os.path.basename(destino)
    for velho in os.listdir(d):
        if velho.startswith(f".{base}.promo-"):
            try:
                os.remove(os.path.join(d, velho))
            except OSError:
                pass
    fd, tmp = tempfile.mkstemp(prefix=f".{base}.promo-", suffix=".tmp", dir=d)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(dados)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, destino)
    except BaseException:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise


def sha256(dados):
    return hashlib.sha256(dados).hexdigest()


def op_render(a):
    if not a.ckpt:
        die("uso: context-render.py <ckpt> --out <rascunho>")
    if not a.out:
        die("--out <rascunho> é obrigatório: o documento só sai em arquivo (nunca no stdout)")
    try:
        with open(a.ckpt, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        die(f"depósito ilegível: {a.ckpt} ({e})")
    dados = render(data).encode("utf-8")
    os.makedirs(os.path.dirname(os.path.abspath(a.out)) or ".", exist_ok=True)
    troca_atomica(a.out, dados)
    print(json.dumps({"out": a.out, "bytes": len(dados), "sha256": sha256(dados),
                      "vazias": vazias(data)}, ensure_ascii=False))


def op_promover(a):
    rascunho, destino = a.promover
    if not a.sha256 or not re.fullmatch(r"[0-9a-f]{64}", a.sha256):
        die("--promover exige --sha256 <hex de 64> (o sha do rascunho que o dono aprovou)")
    ckpt = a.ckpt or os.environ.get("CKPT", "")
    if not ckpt:
        die("--promover precisa do depósito: --ckpt <arquivo> ou CKPT no ambiente — nada promovido")
    try:
        with open(ckpt, encoding="utf-8") as f:
            aprovado = (json.load(f) or {}).get("aprovado_sha256")
    except (OSError, json.JSONDecodeError) as e:
        die(f"depósito ilegível: {ckpt} ({e}) — nada promovido")
    try:
        with open(rascunho, "rb") as f:
            dados = f.read()
    except OSError as e:
        die(f"rascunho ilegível: {rascunho} ({e}) — nada promovido")
    atual = sha256(dados)
    if atual != a.sha256:
        die(f"o rascunho mudou: sha256 {atual} ≠ --sha256 {a.sha256} — nada promovido")
    if not aprovado:
        die("o depósito não tem aprovação gravada (checkpoint-write.py aprovar) — nada promovido")
    if aprovado != a.sha256:
        die(f"o sha aprovado pelo dono ({aprovado}) ≠ o do rascunho ({a.sha256}) — nada promovido")
    if not os.path.isdir(os.path.dirname(os.path.abspath(destino)) or "."):
        die(f"diretório do destino não existe: {destino} — nada promovido")
    troca_atomica(destino, dados)
    print(json.dumps({"ok": True, "op": "promover", "destino": destino, "sha256": atual,
                      "bytes": len(dados)}, ensure_ascii=False))


def main():
    ap = argparse.ArgumentParser(prog="context-render.py")
    ap.add_argument("ckpt", nargs="?")
    ap.add_argument("--out")
    ap.add_argument("--promover", nargs=2, metavar=("RASCUNHO", "DESTINO"))
    ap.add_argument("--sha256")
    ap.add_argument("--ckpt", dest="ckpt_opt")
    a = ap.parse_args()
    if a.promover:
        a.ckpt = a.ckpt_opt or a.ckpt
        op_promover(a)
    else:
        op_render(a)


if __name__ == "__main__":
    main()
