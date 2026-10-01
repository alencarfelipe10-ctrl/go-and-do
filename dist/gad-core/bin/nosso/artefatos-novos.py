#!/usr/bin/env python3
"""artefatos-novos.py — extrai a seção "Artefatos novos commitados" do SPEC (R5).

Ponto ÚNICO de parse dessa seção. Dois consumidores a chamam e por isso não podem
divergir (se divergissem, a guarda bloquearia por artefato que o init nunca mostrou):

  - `discuss-init.sh` (R5b) — emite uma gray area obrigatória por artefato;
  - `context-guard.sh` (R5c) — `GUARD_EXIT=2` se a seção é não-vazia e falta um D-NN
    cobrindo cada artefato no CONTEXT.

Uso:
  artefatos-novos.py <SPEC.md>            → um caminho por linha (stdout), exit 0
  artefatos-novos.py <SPEC.md> --json     → {"secao": bool, "artefatos": [...]}
  (exit 0 sempre que o SPEC existe; seção ausente/vazia = zero linhas)

Heading exato: `## Artefatos novos commitados` (o `templates/spec.md` o cria — outra
frente da onda 2). Formato aceito, um artefato por linha: tabela markdown
(`| caminho | conteúdo |`) OU lista (`- \\`caminho\\` — conteúdo`).

Regra de vazio (deliberadamente por FORMA, não por texto): vale como artefato só a
linha de onde sai um token que PARECE caminho — com `/` ou com extensão. Assim
"nenhum", "n/a", a linha de cabeçalho da tabela, o separador `|---|` e o placeholder
do molde caem fora sem que este script precise conhecer a redação do molde (que está
sendo escrita em paralelo). Placeholder também é barrado por marcador (`<…>`, `[…]`,
`{…}`) e por `…`/`...`.
"""
import json
import re
import sys

HEADING = re.compile(r"^##\s+Artefatos\s+novos\s+commitados\s*$", re.I)
PROXIMA = re.compile(r"^##\s+\S")
CRASE = re.compile(r"`([^`]+)`")
# caminho: tem barra, ou tem extensão de 1-6 caracteres alfanuméricos
CAMINHO = re.compile(r"^(?=.*[/.])[\w./@-]+$")
PLACEHOLDER = re.compile(r"[<>\[\]{}]|\.\.\.|…")


def parece_caminho(tok):
    tok = tok.strip().strip("`").strip()
    if not tok or PLACEHOLDER.search(tok):
        return None
    if not CAMINHO.match(tok):
        return None
    if "/" in tok:
        return tok
    if re.search(r"\.[A-Za-z0-9]{1,6}$", tok):
        return tok
    return None


def celulas(linha):
    """Candidatos a caminho na linha, na ordem: primeiro o que está entre crases."""
    dentro = CRASE.findall(linha)
    if dentro:
        return dentro
    corpo = linha.strip()
    if corpo.startswith("|"):
        return [c for c in corpo.strip("|").split("|")]
    corpo = re.sub(r"^\s*[-*+]\s+", "", corpo)
    return re.split(r"\s+", corpo)


def extrai(texto):
    linhas = texto.split("\n")
    ini = None
    for n, l in enumerate(linhas):
        if HEADING.match(l):
            ini = n + 1
            break
    if ini is None:
        return False, []
    corpo = []
    for l in linhas[ini:]:
        if PROXIMA.match(l):
            break
        corpo.append(l)
    achados = []
    for l in corpo:
        s = l.strip()
        if not s or set(s) <= set("|-: "):      # separador de tabela / linha vazia
            continue
        for tok in celulas(l):
            p = parece_caminho(tok)
            if p:
                if p not in achados:
                    achados.append(p)
                break                            # um artefato por linha
    return True, achados


def main():
    args = [a for a in sys.argv[1:] if a != "--json"]
    como_json = "--json" in sys.argv[1:]
    if not args:
        sys.stderr.write("uso: artefatos-novos.py <SPEC.md> [--json]\n")
        sys.exit(2)
    try:
        with open(args[0], encoding="utf-8", errors="replace") as f:
            texto = f.read()
    except OSError:
        # SPEC ausente = seção ausente = seção vazia. Nunca aborta o chamador.
        print(json.dumps({"secao": False, "artefatos": []}) if como_json else "", end="")
        return
    secao, achados = extrai(texto)
    if como_json:
        print(json.dumps({"secao": secao, "artefatos": achados}, ensure_ascii=False))
    else:
        for a in achados:
            print(a)


if __name__ == "__main__":
    main()
