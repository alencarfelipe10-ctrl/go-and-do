#!/usr/bin/env python3
"""scout.py — consulta o grafo do code-review-graph (ou cai em grep) e imprime o resumo ≤ 8 KB.

Chamado por scout.sh; não invoque à mão. Entrada: objetivo (arquivo), SPEC (opcional), raiz,
caminho do graph.db, origem (texto do cabeçalho). Saída: markdown em stdout.
Fork gen5-patches (P11, 01/09/2026).
"""
import json
import os
import re
import sqlite3
import subprocess
import sys

TETO = 8192
MAX_SIMBOLOS = 80
MAX_TERMOS = 30
EXT_CODIGO = ("py", "ts", "tsx", "js", "jsx", "sh", "cjs", "mjs", "go", "rs", "java", "rb")
STOP = set("""
a o os as um uma uns umas de do da dos das em no na nos nas por para com sem sob sobre entre que qual
quais quando onde como mais menos muito pouco todo toda todos todas este esta esse essa isto isso aquele
aquela ser está estão foi são ter tem têm sua seu suas seus não nem mas ou também já ainda apenas mesmo
mesma pela pelo pelas pelos ao aos à às cada outra outro outras outros fase fases objetivo goal phase
the and for with from that this these those into onto over under than then when where which while who
whom what will would shall should must can could may might have has had been being are was were does
did done into about after before between during without within each every some such only also very
just like make made makes uses used using
""".split())


def ler(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def termos_do_objetivo(texto):
    """Identificadores em crase e snake_case primeiro, depois REQ-IDs, depois palavras ≥ 4 letras."""
    crase = re.findall(r"`([^`\n]{2,60})`", texto)
    ident = []
    for c in crase:
        c = c.strip()
        if (re.fullmatch(r"[\w.\- ]+", c) and not re.search(r"\.(md|txt|json)$", c)
                and not re.fullmatch(r"[0-9a-f]{7,40}", c) and len(c.split()) <= 3
                and c not in ("None", "True", "False")):
            ident.append(c)
    reqs = re.findall(r"\b(?:[A-Z]{2,}-v?\w*-\d+|R\d+|SC\d+|PS-\d+)\b", texto)
    palavras = [w.lower() for w in re.findall(r"[A-Za-zÀ-ÿ_][A-Za-zÀ-ÿ_0-9]{3,}", texto)]
    freq = {}
    for w in palavras:
        if w in STOP or w.isdigit():
            continue
        freq[w] = freq.get(w, 0) + 1
    snake = [w for w in freq if "_" in w]
    comuns = sorted((w for w in freq if "_" not in w), key=lambda w: (-freq[w], w))
    vistos, saida = set(), []
    for t in ident + snake + reqs + comuns:
        k = t.lower()
        if k in vistos or len(k) < 3:
            continue
        vistos.add(k)
        saida.append(t)
    return saida[:MAX_TERMOS]


def arquivos_da_spec(texto):
    achados = re.findall(r"(?<![\w/])((?:[\w.\-]+/)+[\w.\-]+\.(?:py|ts|tsx|js|jsx|sh|cjs|mjs|md))\b", texto)
    vistos, saida = set(), []
    for a in achados:
        if a.startswith(".planning/") or a in vistos:
            continue
        vistos.add(a)
        saida.append(a)
    return saida


def fts_query(term):
    toks = [t for t in re.split(r"[^\w]+", term) if t]
    if not toks:
        return None
    return '"' + " ".join(toks) + '"*'


class Grafo:
    """Leitura do graph.db. Confere as colunas que usa; qualquer falta → ValueError (reserva em grep)."""

    def __init__(self, db, root):
        self.c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        self.root = os.path.realpath(root)
        cols = lambda t: {r[1] for r in self.c.execute(f"pragma table_info({t})")}
        precisa = {"nodes": {"id", "kind", "name", "qualified_name", "file_path", "line_start", "line_end", "is_test"},
                   "edges": {"kind", "source_qualified", "target_qualified"}}
        for t, cs in precisa.items():
            falta = cs - cols(t)
            if falta:
                raise ValueError(f"tabela {t} sem colunas {sorted(falta)}")
        if not self.c.execute("select 1 from sqlite_master where name='nodes_fts'").fetchone():
            raise ValueError("sem nodes_fts")
        self.n = self.c.execute("select count(*) from nodes").fetchone()[0]
        if self.n == 0:
            raise ValueError("grafo vazio")
        self.strip = self._prefixo()

    def _prefixo(self):
        """Quantos componentes iniciais do file_path absoluto tirar para cair na raiz atual."""
        r = self.c.execute("select file_path from nodes where kind='File' limit 1").fetchone()
        if not r:
            return 0
        p = r[0]
        if p.startswith(self.root + "/"):
            return len(self.root.split("/"))
        partes = p.split("/")
        for i in range(1, len(partes)):
            if os.path.exists(os.path.join(self.root, "/".join(partes[i:]))):
                return i
        return 0

    def rel(self, p):
        partes = p.split("/")
        return "/".join(partes[self.strip:]) if self.strip and len(partes) > self.strip else p

    def commit(self):
        try:
            r = self.c.execute("select value from metadata where key='git_head_sha'").fetchone()
            return r[0] if r else None
        except sqlite3.Error:
            return None

    def simbolos_por_termo(self, termos):
        acertos = {}  # qualified_name -> conjunto de termos
        for t in termos:
            q = fts_query(t)
            if not q:
                continue
            try:
                rows = self.c.execute(
                    "select n.qualified_name from nodes_fts f join nodes n on n.id=f.rowid "
                    "where nodes_fts match ? limit 80", (q,)).fetchall()
            except sqlite3.Error:
                continue
            for (qn,) in rows:
                acertos.setdefault(qn, set()).add(t)
        return acertos

    def no(self, qn):
        return self.c.execute("select kind,name,file_path,line_start,line_end,is_test from nodes where qualified_name=?", (qn,)).fetchone()

    def vizinhos(self, qn):
        chama = [r[0] for r in self.c.execute(
            "select target_qualified from edges where source_qualified=? and kind='CALLS' limit 8", (qn,))]
        chamado = [r[0] for r in self.c.execute(
            "select source_qualified from edges where target_qualified=? and kind='CALLS' limit 8", (qn,))]
        testes = [r[0] for r in self.c.execute(
            "select target_qualified from edges where source_qualified=? and kind='TESTED_BY' limit 6", (qn,))]
        liga = lambda xs: [x for x in xs if "/" in x]
        return liga(chama), liga(chamado), testes

    def testes_do_arquivo(self, rel, nomes):
        """Arquivos de teste ligados a `rel`: importam seu módulo (IMPORTS_FROM, nome de módulo, não
        resolvido a caminho pelo indexador) ou chamam um símbolo de topo dele pelo nome (CALLS)."""
        base = re.sub(r"\.\w+$", "", rel).split("/")
        mods = {".".join(base), ".".join(base[1:])} if len(base) > 1 else {".".join(base)}
        mods.discard("")
        saida = {}
        qm = ",".join("?" * len(mods))
        for (fp,) in self.c.execute(f"select distinct file_path from edges where kind='IMPORTS_FROM' and target_qualified in ({qm})", tuple(mods)):
            r = self.rel(fp)
            if eh_teste(r) and r != rel:
                saida.setdefault(r, set()).add("import")
        if nomes:
            qn = ",".join("?" * len(nomes))
            for fp, nm in self.c.execute(f"select file_path, target_qualified from edges where kind='CALLS' and target_qualified in ({qn})", tuple(nomes)):
                r = self.rel(fp)
                if eh_teste(r) and r != rel:
                    saida.setdefault(r, set()).add(nm)
        return saida

    def topo_do_arquivo(self, rel):
        rows = self.c.execute(
            "select qualified_name,kind,name,line_start,line_end,file_path from nodes where kind in ('Class','Function') "
            "and (parent_name is null or parent_name='') and file_path like ? order by line_start", ("%/" + rel,)).fetchall()
        return [r[:5] for r in rows if self.rel(r[5]) == rel]

    def entradas_por_arquivo(self, arquivos):
        saida = {}
        for a in arquivos:
            n = self.c.execute(
                "select count(*) from edges e join nodes t on t.qualified_name=e.target_qualified "
                "join nodes s on s.qualified_name=e.source_qualified where e.kind in ('CALLS','IMPORTS_FROM') "
                "and t.file_path like ? and s.file_path not like ?", ("%" + a, "%" + a)).fetchone()[0]
            saida[a] = n
        return saida


def eh_teste(rel):
    b = os.path.basename(rel)
    return bool(re.search(r"(^|/)tests?/", rel) or re.match(r"test_|.*_test\.|.*\.test\.|.*\.spec\.", b))


def nome(qn):
    return qn.split("::", 1)[1] if "::" in qn else os.path.basename(qn)


def consulta_grafo(g, termos, spec_files):
    arquivos = {}  # rel -> {"hits": n, "simbolos": {nome: (kind, l1, l2, chama, chamado)}, "spec": bool}
    testes = {}  # rel do teste -> set(nomes cobertos)

    def bump(rel, spec=False):
        d = arquivos.setdefault(rel, {"hits": 0, "simbolos": {}, "spec": False})
        d["spec"] = d["spec"] or spec
        return d

    acertos = g.simbolos_por_termo(termos)
    for f in spec_files:
        if not os.path.exists(os.path.join(g.root, f)):
            continue
        d = bump(f, spec=True)
        d["hits"] += 3
        topo = g.topo_do_arquivo(f)
        topo.sort(key=lambda r: (-len(acertos.get(r[0], ())), r[3] or 0))
        for qn, kind, nm, l1, l2 in topo[:8]:
            chama, chamado, _ = g.vizinhos(qn)
            d["simbolos"].setdefault(nm, (kind, l1, l2, [nome(x) for x in chama[:3]], [nome(x) for x in chamado[:3]]))
        nomes = [r[2] for r in topo if r[1] == "Function"][:60]
        for t, cobre in sorted(g.testes_do_arquivo(f, nomes).items(), key=lambda kv: -len(kv[1]))[:20]:
            testes.setdefault(t, set()).update(cobre)

    ordenados = sorted(acertos.items(), key=lambda kv: (-len(kv[1]), kv[0]))[:MAX_SIMBOLOS]
    for qn, ts in ordenados:
        n = g.no(qn)
        if not n:
            continue
        kind, nm, fp, l1, l2, is_test = n
        rel = g.rel(fp)
        if kind == "File":  # o caminho do arquivo casou com o termo (ex.: test_roteamento_cancel_date.py)
            if eh_teste(rel):
                testes.setdefault(rel, set()).add("nome-do-arquivo")
            else:
                bump(rel)["hits"] += len(ts)
            continue
        if is_test or kind == "Test" or eh_teste(rel):
            testes.setdefault(rel, set()).add(nm)
            continue
        d = bump(rel)
        d["hits"] += len(ts)
        chama, chamado, tst = g.vizinhos(qn)
        d["simbolos"].setdefault(nm, (kind, l1, l2, [nome(x) for x in chama[:3]], [nome(x) for x in chamado[:3]]))
        for t in tst:
            tn = g.no(t)
            if tn:
                testes.setdefault(g.rel(tn[2]), set()).add(nm)
        for v in chamado[:4]:
            vn = g.no(v)
            if vn and not vn[5]:
                bump(g.rel(vn[2]))["hits"] += 0.5
    entradas = g.entradas_por_arquivo(list(arquivos)[:30])
    return arquivos, testes, entradas


def consulta_grep(root, termos, spec_files):
    dirs = [d for d in ("src", "tests", "app", "lib", "packages") if os.path.isdir(os.path.join(root, d))]
    cb = os.path.join(root, ".planning", "codebase", "STRUCTURE.md")
    if os.path.exists(cb):
        for d in re.findall(r"`([\w\-]+)/`", ler(cb)):
            if os.path.isdir(os.path.join(root, d)) and d not in dirs:
                dirs.append(d)
    if not dirs:
        dirs = ["."]
    padrao = "|".join(re.escape(t) for t in termos[:20] if len(t) >= 4)
    if not padrao:
        return {}, {}, {}
    # um grep por diretório, com cota de linhas por diretório: senão src/ consome as 200 e tests/ nunca aparece
    linhas, cota = [], max(20, 200 // len(dirs))
    for d in dirs:
        cmd = ["grep", "-rn", "-i", "-I", "-E", padrao, d] + ["--include=*." + e for e in EXT_CODIGO]
        try:
            out = subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=60).stdout
        except (subprocess.TimeoutExpired, OSError):
            out = ""
        linhas += out.splitlines()[:cota]
    arquivos, testes = {}, {}
    for l in linhas:
        m = re.match(r"([^:]+):(\d+):(.*)", l)
        if not m:
            continue
        f, ln, tx = m.group(1), int(m.group(2)), m.group(3).strip()
        alvo = testes if ("/test" in f or f.startswith("test")) else arquivos
        d = alvo.setdefault(f, {"hits": 0, "simbolos": {}, "spec": False, "linhas": []})
        d["hits"] += 1
        if len(d["linhas"]) < 3:
            d["linhas"].append(f"{ln}: {tx[:70]}")
        sm = re.match(r"\s*(?:def|class|function|const|export (?:default )?(?:function|class|const))\s+([\w]+)", tx)
        if sm:
            d["simbolos"].setdefault(sm.group(1), ("grep", ln, ln, [], []))
    for f in spec_files:
        if os.path.exists(os.path.join(root, f)):
            d = arquivos.setdefault(f, {"hits": 0, "simbolos": {}, "spec": False, "linhas": []})
            d["spec"], d["hits"] = True, d["hits"] + 3
    return arquivos, {k: set(v["simbolos"]) or {"(match)"} for k, v in testes.items()}, {}


def montar(origem, termos, arquivos, testes, entradas, aviso):
    L = [f"# scout · origem: {origem}", ""]
    if aviso:
        L += [f"> aviso: {aviso}", ""]
    L += ["termos: " + ", ".join(termos[:20]), ""]
    ordem = sorted(arquivos.items(), key=lambda kv: (not kv[1]["spec"], -kv[1]["hits"], kv[0]))[:30]
    L.append("## Arquivos relevantes")
    for rel, d in ordem:
        tag = " (SPEC)" if d["spec"] else ""
        syms = []
        so_citado = d["spec"] and d["hits"] <= 3
        for nm, (kind, l1, l2, chama, chamado) in list(d["simbolos"].items())[:1 if so_citado else 4]:
            viz = "" if so_citado else (" ← " + chamado[0] if chamado else "") + (" → " + chama[0] if chama else "")
            syms.append(f"`{nm}`" + (f":{l1}" if l1 else "") + viz)
        L.append(f"- {rel}{tag} · {d['hits']:g}" + (" · " + "; ".join(syms) if syms else ""))
        for ln in d.get("linhas", [])[:2]:
            L.append(f"  - {ln}")
    L.append("")
    L.append("## Testes existentes")
    peso = lambda c: len(c - {"import"}) + (3 if "nome-do-arquivo" in c else 0)
    for rel, cobre in sorted(testes.items(), key=lambda kv: (-peso(kv[1]), kv[0]))[:30]:
        L.append(f"- {rel} · " + ", ".join(sorted(cobre - {"nome-do-arquivo"})[:2] or ["nome"]))
    if not testes:
        L.append("- nenhum teste ligado aos termos")
    L.append("")
    reut = [nm for _, d in ordem[:6] for nm, (k, *_r) in d["simbolos"].items() if k in ("Function", "Class")][:3]
    L += ["## reusable"] + ([f"- `{n}`" for n in reut] or ["- nada detectado; confira à mão"]) + [""]
    pads = []
    dirs_teste = sorted({os.path.dirname(t) for t in testes})
    if dirs_teste:
        pads.append("testes em " + ", ".join(f"`{d}/*`" for d in dirs_teste[:3]))
    if any("golden" in t for t in testes):
        pads.append("padrão de golden/baseline em `tests/golden/*`")
    if any(t.endswith(".py") for t in arquivos):
        pads.append("python: símbolos privados `_nome` com testes unitários por função")
    L += ["## patterns"] + ([f"- {p}" for p in pads[:3]] or ["- nada detectado"]) + [""]
    integ = sorted(entradas.items(), key=lambda kv: -kv[1])[:3]
    # só conexões (onde o código novo se liga ao existente); risco e restrição vão à Regression
    # Surface do SPEC — na 24.4, 4 dos 5 "pontos de integração" eram riscos (achado P2, plano 2)
    L += ["## integration", "<!-- só conexões; risco e restrição vão à Regression Surface do SPEC -->"] + ([f"- {a} · {n} arestas de entrada" for a, n in integ] or
                                [f"- {a}" for a, _ in ordem[:3]] or ["- nada detectado"])
    texto = "\n".join(L) + "\n"
    if len(texto.encode("utf-8")) > TETO:
        # corta a cauda da lista de arquivos até caber, preservando as seções finais
        i = L.index("## Testes existentes")
        cauda = L[i:]
        cabeca = L[:i]
        marca = "- … (cortado: saída acima de 8 KB)"
        while cabeca and len(("\n".join(cabeca + [marca, ""] + cauda) + "\n").encode("utf-8")) > TETO:
            cabeca.pop()
        texto = "\n".join(cabeca + [marca, ""] + cauda) + "\n"
        if len(texto.encode("utf-8")) > TETO:
            texto = texto.encode("utf-8")[:TETO - 40].decode("utf-8", "ignore") + "\n- … (cortado a 8 KB)\n"
    return texto


def main():
    a = dict(zip(sys.argv[1::2], sys.argv[2::2]))
    root = a.get("--root", ".")
    objetivo = ler(a["--goal-file"]) if a.get("--goal-file") else ""
    spec = ler(a["--spec"]) if a.get("--spec") else ""
    db = a.get("--graph", "")
    origem_extra = a.get("--origem", "")
    termos = termos_do_objetivo(objetivo + "\n" + spec[:12000])
    spec_files = arquivos_da_spec(spec)
    aviso = origem_extra
    g = None
    if db and os.path.exists(db):
        try:
            g = Grafo(db, root)
        except (ValueError, sqlite3.Error) as e:
            aviso = (aviso + "; " if aviso else "") + f"grafo inutilizável ({e}) — reserva em grep"
    if g:
        origem = f"grafo {(g.commit() or '?')[:12]} ({g.n} nós)"
        arquivos, testes, entradas = consulta_grafo(g, termos, spec_files)
    else:
        origem = "grep"
        if not db:
            aviso = (aviso + "; " if aviso else "") + "sem .code-review-graph/graph.db — reserva em grep"
        arquivos, testes, entradas = consulta_grep(root, termos, spec_files)
    sys.stdout.write(montar(origem, termos, arquivos, testes, entradas, aviso))


if __name__ == "__main__":
    main()
