#!/usr/bin/env bash
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gsd-shim.sh" 2>/dev/null && trap 'gad_autoregistro "gera-intent-review.sh" "$?"' EXIT || true
# gera-intent-review.sh — monta a tabela do NN-INTENT-REVIEW.md a partir dos arquivos do
# verificador, já no formato que o fiscal lê (FJ-F27INS-06INT, tarefa 59 b6).
#
# Por quê: na F27 INS o coordenador redigiu a tabela à mão e o fiscal rodou 3 vezes — ponteiro
# sem diretório (`ship.py:60`), veredito fora do vocabulário («confirmado (B, alta)»), coluna
# `fontes` ausente (o `confere-cardinalidade.sh` lê o veredito na 4ª coluna e contou 0),
# proposições sem as linhas e o cabeçalho com 3 confirmados em vez de 4 (c1-07 fora).
#
# O QUE GERA (stdout, markdown para colar; o coordenador escreve só «ação tomada» e o
# dono/destino das dívidas):
#   · as 3 contagens do frontmatter, contadas nas MESMAS linhas da tabela e com a mesma regra
#     do fiscal — cabeçalho × tabela batem por construção;
#   · «Novos confirmados por ciclo»;
#   · «## Tabela de achados» com `| id | alegação | fontes | veredito | destino | ação tomada |
#     proposição |` — uma linha por id da UNIÃO de `c*/vereditos.txt` (todos os ciclos) com os
#     `achados-verificados.json`; alegação e evidência verbatim do verificador (caminho
#     completo); veredito = a palavra seca do `vereditos.txt` (o arquivo selado que o fiscal
#     conta); `proposição` (T3) derivada de `correcoes.aplicado` + `correcoes.py` (lido por
#     AST, nunca executado) + a versão do artefato de antes do ciclo;
#   · linhas da «## Dívidas registradas» para os `confirmado_irrelevante` e os `confirmado`
#     com `vinculo_goal: nenhum`.
#
# O QUE NÃO FAZ (FM-F27INS-07INT — o gerador não maquia divergência):
#   · não escolhe em silêncio entre dois arquivos do verificador que discordam: o veredito do
#     `vereditos.txt` vai à célula, a divergência vai à «ação tomada» da linha, à seção
#     «## Divergências dos arquivos do verificador», ao `--json` e ao exit 1;
#   · não omite id que só um dos arquivos tem (c1-07 da F27 só existe no vereditos.txt);
#   · proposição que não se deriva sai `PENDENTE — <motivo>`, SEM nenhuma das cinco chaves
#     (um PENDENTE com as chaves passaria no R7 do fiscal) — e exit 1;
#   · não escreve o INTENT-REVIEW, nem o deferred-items.md, nem nada em `.gad/` — só imprime.
#     Dívida decidida pelo coordenador (sino do c0) não vem daqui; o fiscal da b4
#     (`confere-cardinalidade.sh`) é quem barra dívida fora do deferred-items.
#
# Uso: gera-intent-review.sh <phase_dir> <NN> [--json]
# Exit: 0 = tabela limpa · 1 = gerada com divergência/pendência (resolva antes de colar) ·
#       2 = uso inválido ou nenhum vereditos.txt no disco.
set -uo pipefail

PD="${1:-}"; NN="${2:-}"; MODO="${3:-}"
if [ -z "$PD" ] || [ -z "$NN" ]; then
  echo "uso: gera-intent-review.sh <phase_dir> <NN> [--json]" >&2; exit 2
fi
[ -d "$PD" ] || { echo "gera-intent-review: phase_dir inexistente: $PD" >&2; exit 2; }

GAD_LIB="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib" python3 - "$PD" "$NN" "$MODO" <<'PYGERA'
import ast
import glob
import json
import os
import re
import subprocess
import sys

pd, nn, modo = sys.argv[1].rstrip("/"), sys.argv[2], sys.argv[3]
sys.dont_write_bytecode = True
sys.path.insert(0, os.environ["GAD_LIB"])
import gad_caminhos  # mesma tabela de caminhos do fiscal (formato novo × antigo)

divergencias = []   # arquivos do verificador que discordam — nunca resolvidas aqui
pendentes = []      # o que o gerador não conseguiu derivar
fontes_lidas = []
RE_ID = re.compile(r"^c\d+[a-z]?-\d+$")


def rel(p):
    return os.path.relpath(p, pd)


def ler_json(p):
    try:
        with open(p, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return None


# ── (1) vereditos no disco — o MESMO glob do confere-cardinalidade.sh ─────────────
vereditos = {}      # id → {ciclo, classe, veredito, categoria}
ordem = []
arqs_ver = gad_caminhos.glob_fase(pd, "intent/c*/vereditos.txt")
for f in arqs_ver:
    ciclo = gad_caminhos.curinga(pd, "intent/c*/vereditos.txt", f)
    fontes_lidas.append(rel(f))
    for linha in open(f, encoding="utf-8", errors="replace"):
        cels = [c.strip() for c in linha.split("|")]
        if len(cels) < 3 or not cels[0] or cels[0].startswith("#"):
            continue
        ident = cels[0]
        reg = {"ciclo": ciclo, "classe": cels[1], "veredito": cels[2],
               "categoria": cels[3] if len(cels) > 3 else ""}
        if ident in vereditos:
            if vereditos[ident]["veredito"] != reg["veredito"]:
                divergencias.append({"id": ident, "tipo": "VEREDITO-DUPLICADO",
                                     "detalhe": f"{ident} aparece 2× nos vereditos.txt: "
                                                f"«{vereditos[ident]['veredito']}» (c{vereditos[ident]['ciclo']}) × "
                                                f"«{reg['veredito']}» (c{ciclo})"})
            continue
        vereditos[ident] = reg
        ordem.append(ident)

if not arqs_ver:
    print(f"gera-intent-review: nenhum vereditos.txt em {pd} — nada a gerar "
          "(rode depois do verificador de cada ciclo)", file=sys.stderr)
    raise SystemExit(2)

ciclos = sorted({v["ciclo"] for v in vereditos.values()} |
                {gad_caminhos.curinga(pd, "intent/c*/vereditos.txt", f) for f in arqs_ver},
                key=lambda c: (len(c), c))

# ── (2) achados-verificados.json de cada ciclo (run-atual; senão o último run) ────
achados = {}        # id → dict do verificador
for c in ciclos:
    cand = []
    ra = gad_caminhos.caminho(pd, f"intent/c{c}/run-atual")
    if os.path.isfile(ra):
        run = open(ra, encoding="utf-8").read().strip()
        if run:
            cand.append(gad_caminhos.caminho(pd, f"intent/c{c}/runs/{run}/achados-verificados.json"))
    cand += sorted(gad_caminhos.glob_fase(pd, f"intent/c{c}/runs/*/achados-verificados.json"),
                   reverse=True)
    for p in cand:
        if os.path.isfile(p):
            dados = ler_json(p)
            if dados is None:
                pendentes.append({"id": f"c{c}", "tipo": "ACHADOS-ILEGIVEL", "detalhe": rel(p)})
                break
            fontes_lidas.append(rel(p))
            for a in (dados if isinstance(dados, list) else dados.get("achados", [])):
                if isinstance(a, dict) and a.get("id"):
                    achados.setdefault(a["id"], a)
            break

# ── (3) releitura: alegação dos ids de classe `releitura` (não passam pelo verificador) ─
def alegacao_releitura(ident, reg):
    """c1-07 (F27): `c1-07 | releitura | confirmado | omissoes_novas` → a lista
    `omissoes_novas` do c1/releitura.json. Mapeia por ORDEM só quando o número de ids da
    categoria bate com o tamanho da lista; senão, pendente — nunca palpite."""
    cat = reg["categoria"]
    p = gad_caminhos.caminho(pd, f"intent/c{reg['ciclo']}/releitura.json")
    dados = ler_json(p) if os.path.isfile(p) else None
    if not isinstance(dados, dict) or not isinstance(dados.get(cat), list):
        return None, f"sem lista «{cat}» em {os.path.basename(p)} do c{reg['ciclo']}"
    irmaos = [i for i in ordem if vereditos[i]["classe"] == "releitura"
              and vereditos[i]["ciclo"] == reg["ciclo"] and vereditos[i]["categoria"] == cat]
    lista = dados[cat]
    if len(irmaos) != len(lista):
        return None, (f"{len(irmaos)} id(s) «releitura/{cat}» × {len(lista)} item(ns) em "
                      f"c{reg['ciclo']}/releitura.json — sem casamento seguro")
    item = lista[irmaos.index(ident)]
    fontes_lidas.append(rel(p))
    if isinstance(item, dict):
        txt = item.get("o_que") or item.get("alegacao") or json.dumps(item, ensure_ascii=False)
        onde = item.get("path", "")
        return (f"(releitura c{reg['ciclo']}) {txt}", onde), None
    return (f"(releitura c{reg['ciclo']}) {item}", ""), None


# ── (4) proposição (T3): correcoes.aplicado + correcoes.py (AST) + artefato pré-ciclo ─
def raiz_projeto():
    i = pd.find("/.planning/")
    base = pd[:i] if i >= 0 else os.path.dirname(os.path.dirname(pd))
    try:
        top = subprocess.run(["git", "-C", base, "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        top = ""
    return base, (top == os.path.realpath(base) or top == base)


RAIZ, RAIZ_GIT = raiz_projeto()

aplicado = {}       # id → {"path": rel ao repo, "commit": sha, "ciclo": c}
head_pre = {}       # ciclo → sha
for f in gad_caminhos.glob_fase(pd, "intent/c*/correcoes.aplicado"):
    c = gad_caminhos.curinga(pd, "intent/c*/correcoes.aplicado", f)
    d = ler_json(f)
    if not isinstance(d, dict):
        continue
    fontes_lidas.append(rel(f))
    m = re.search(r"ids:\s*([^\n]+)", d.get("mensagem", ""))
    if m:
        for par in m.group(1).split(","):
            if ":" in par:
                i, p = par.split(":", 1)
                aplicado[i.strip()] = {"path": p.strip(), "commit": d.get("commit", ""), "ciclo": c}
    for i in d.get("ids", []):
        aplicado.setdefault(i, {"path": "", "commit": d.get("commit", ""), "ciclo": c})
for f in gad_caminhos.glob_fase(pd, "intent/c*/correcoes.base.json"):
    c = gad_caminhos.curinga(pd, "intent/c*/correcoes.base.json", f)
    d = ler_json(f)
    if isinstance(d, dict) and d.get("head_pre"):
        head_pre[c] = d["head_pre"]


def olds_do_script(p):
    """id → [strings `old`] de um correcoes.py, por AST (nunca executa). Formas medidas:
    `rep(old, new, "c1-01")` (id em argumento) e `edit("27-SPEC.md", [(old, new), …])` com o
    id no comentário `# c1-07: …` mais recente acima da chamada."""
    src = open(p, encoding="utf-8", errors="replace").read()
    arvore = ast.parse(src)
    comentarios = []
    for n, linha in enumerate(src.splitlines(), 1):
        m = re.match(r"\s*#\s*(c\d+[a-z]?-\d+)\b", linha)
        if m:
            comentarios.append((n, m.group(1)))
    saida = {}

    def strs(no):
        return [x.value for x in ast.walk(no) if isinstance(x, ast.Constant) and isinstance(x.value, str)]

    for st in arvore.body:
        if not (isinstance(st, ast.Expr) and isinstance(st.value, ast.Call)):
            continue
        call = st.value
        ident = next((s for s in strs(call) if RE_ID.match(s)), None)
        if ident is None:
            acima = [i for (n, i) in comentarios if n < st.lineno]
            ident = acima[-1] if acima else None
        if ident is None:
            continue
        olds = []
        for a in call.args:
            if isinstance(a, (ast.List, ast.Tuple)):
                pares = a.elts if isinstance(a, ast.List) else [a]
                for par in pares:
                    if (isinstance(par, ast.Tuple) and len(par.elts) >= 2 and isinstance(par.elts[0], ast.Constant)
                            and isinstance(par.elts[0].value, str)):
                        olds.append(par.elts[0].value)
        if not olds:
            pos = [a.value for a in call.args if isinstance(a, ast.Constant) and isinstance(a.value, str)]
            if len(pos) >= 2 and not RE_ID.match(pos[0]):
                olds.append(pos[0])
        if olds:
            saida.setdefault(ident, []).extend(olds)
    return saida


olds = {}
for f in gad_caminhos.glob_fase(pd, "intent/c*/correcoes.py"):
    try:
        for i, lst in olds_do_script(f).items():
            olds.setdefault(i, []).extend(lst)
        fontes_lidas.append(rel(f))
    except Exception as e:  # sintaxe que o AST não lê → as proposições dali ficam pendentes
        pendentes.append({"id": rel(f), "tipo": "CORRECOES-ILEGIVEL", "detalhe": str(e)[:120]})


def versoes(caminho_rel, ciclo, commit):
    """Texto do artefato na ordem: head_pre do ciclo → revisões do arquivo ANTERIORES ao commit
    da correção, da mais nova para a mais velha (até 40) → todas as revisões → disco. Medido
    na F27: o `correcoes.base.json` do c1 foi regravado no `--inicio` do c1b e o head_pre dele
    JÁ traz as correções do c1 — o `old` só existe na revisão anterior; por isso a caminhada
    pelo histórico, e não só o head_pre. Partir do pai do commit da correção evita pegar a
    linha deslocada da versão corrigida (c1-07: 223 antes, 224 depois)."""
    revs = [(head_pre.get(ciclo), "head_pre")]
    if RAIZ_GIT:
        pontos = ([f"{commit}^"] if commit else []) + ["HEAD"]
        for ponto in pontos:
            r = subprocess.run(["git", "-C", RAIZ, "log", "-n", "40", "--format=%H", ponto, "--", caminho_rel],
                               capture_output=True, text=True)
            if r.returncode == 0:
                revs += [(h, "rev") for h in r.stdout.split()]
    vistos = set()
    for sha, nome in revs:
        if sha and RAIZ_GIT and sha not in vistos:
            vistos.add(sha)
            r = subprocess.run(["git", "-C", RAIZ, "show", f"{sha}:{caminho_rel}"],
                               capture_output=True, text=True)
            if r.returncode == 0:
                yield r.stdout, f"{nome} {sha[:8]}"
    disco = os.path.join(RAIZ, caminho_rel)
    if os.path.isfile(disco):
        yield open(disco, encoding="utf-8", errors="replace").read(), "disco"


RE_ACD = re.compile(r"^\s*(?:[-*]\s*)?(?:\[[ xX]\]\s*)?\*{0,2}((?:AC|D)-\d+)\b")
RE_R = re.compile(r"^\s*(?:\d+\.\s*)?\*{0,2}(R-?\d+)\s*(?:—|–|-|:)")
RE_HEAD = re.compile(r"^#{1,6}\s+\S")


def proposicao(ident):
    """Devolve (célula, None) ou (None, motivo). O vocabulário da âncora é o do
    `etiqueta-achados.py` da /audit-gad: AC-n/D-nn/R-n no início da linha, senão o heading
    mais próximo ACIMA escrito com os `#` (sem eles a âncora sai `não_medido`)."""
    ap = aplicado.get(ident)
    if not ap or not ap["path"]:
        return None, "id sem artefato no correcoes.aplicado"
    if ident not in olds:
        return None, "sem trecho `old` atribuível a este id nos correcoes.py"
    nome = os.path.basename(ap["path"])
    m = re.search(r"-(SPEC|CONTEXT)\.md$", nome)
    artefato = m.group(1) if m else nome
    ciclo_num = re.match(r"\d+", ap["ciclo"] or "")
    ciclo_base = ciclo_num.group(0) if ciclo_num else ap["ciclo"]
    for conteudo, origem in versoes(ap["path"], ciclo_base, ap["commit"]):
        for old in olds[ident]:
            if conteudo.count(old) != 1:
                continue
            ini = conteudo[: conteudo.index(old)].count("\n") + 1
            fim = ini + old.count("\n")
            linhas = conteudo.splitlines()
            ancora = None
            mm = RE_ACD.match(linhas[ini - 1]) or RE_R.match(linhas[ini - 1])
            if mm:
                ancora = mm.group(1)
            else:
                for k in range(ini - 1, -1, -1):
                    if RE_HEAD.match(linhas[k]):
                        ancora = '"' + linhas[k].strip() + '"'
                        break
            if not ancora:
                continue
            texto = " ".join(old.split("\n")).replace("\\", "\\\\").replace('"', '\\"')
            cel = (f'{{artefato: {artefato}, ancora: {ancora}, span_linhas: [{ini}, {fim}], '
                   f'texto: "{texto}", origem_texto: de_artefato_pos_ciclo}}')
            return (cel, origem), None
    return None, f"trecho `old` não localizado uma única vez em {nome} (head_pre/histórico git/disco)"


# ── (5) as linhas ──────────────────────────────────────────────────────────────
def celula(s):
    # `|` dentro de alegação/evidência deslocaria a coluna do veredito que o fiscal lê
    # (cels[3]); a proposição é a ÚLTIMA coluna e fica verbatim.
    return " ".join(str(s).split()).replace("|", "∣")


def classe_fiscal(v):
    """A MESMA classificação do confere-cardinalidade.sh (tabela)."""
    v = v.lower()
    if "confirmado_irrelevante" in v or "dispensad" in v:
        return "dispensados"
    if "confirmado" in v:
        return "confirmados"
    if "nao_sustentado" in v or "não_sustentado" in v or "descartad" in v:
        return "descartados"
    return "outros"


ids = list(ordem) + [i for i in sorted(achados) if i not in vereditos]
linhas = []
for ident in ids:
    reg = vereditos.get(ident)
    ach = achados.get(ident)
    obs = []
    if reg is None:
        veredito = "sem_veredito_no_disco"
        divergencias.append({"id": ident, "tipo": "SEM-VEREDITO-NO-DISCO",
                             "detalhe": f"{ident} está no achados-verificados.json "
                                        f"(veredito «{ach.get('veredito', '?')}») e em nenhum vereditos.txt"})
        obs.append(f"⚠ DIVERGÊNCIA: sem linha no vereditos.txt; achados-verificados.json diz `{ach.get('veredito', '?')}`")
    else:
        veredito = reg["veredito"]
        if ach is not None and ach.get("veredito") and ach["veredito"] != veredito:
            divergencias.append({"id": ident, "tipo": "VEREDITO-DIVERGENTE",
                                 "detalhe": f"{ident}: vereditos.txt diz «{veredito}», "
                                            f"achados-verificados.json diz «{ach['veredito']}»"})
            obs.append(f"⚠ DIVERGÊNCIA: achados-verificados.json diz `{ach['veredito']}`, vereditos.txt diz `{veredito}`")
    # alegação + evidência
    alegacao, evidencia, fontes = None, "", []
    if ach is not None:
        alegacao = ach.get("alegacao", "")
        evidencia = ach.get("evidencia", "")
        fontes = list(ach.get("fontes") or [])
    elif reg and reg["classe"] == "releitura":
        r, motivo = alegacao_releitura(ident, reg)
        if r:
            alegacao, onde = r
            evidencia = onde
            fontes = ["releitura"]
        else:
            pendentes.append({"id": ident, "tipo": "ALEGACAO-PENDENTE", "detalhe": motivo})
    else:
        pendentes.append({"id": ident, "tipo": "ALEGACAO-PENDENTE",
                          "detalhe": "id sem achado no achados-verificados.json do ciclo"})
    if alegacao is None:
        alegacao_cel = "PENDENTE — alegação não encontrada nos arquivos do verificador"
    else:
        alegacao_cel = celula(alegacao) + (f" — evidência: {celula(evidencia)}" if evidencia else "")
    categoria = (reg or {}).get("categoria") or (ach or {}).get("categoria", "")
    fontes_cel = celula(" · ".join([", ".join(fontes) or "—"] + ([categoria] if categoria else [])))
    cls = classe_fiscal(veredito)
    # destino
    if cls == "confirmados":
        destino = f"correção ({aplicado[ident]['commit'][:8]})" if ident in aplicado and aplicado[ident]["commit"] else "«preencher»"
    elif cls == "dispensados":
        destino = "dívida"
    elif cls == "descartados":
        destino = "registrado"
    else:
        destino = "«preencher»"
    # proposição (só confirmado — é o que o R7 do fiscal cobra)
    prop_cel, prop_origem = "—", None
    if cls == "confirmados" and veredito.strip().lower() == "confirmado":
        r, motivo = proposicao(ident)
        if r:
            prop_cel, prop_origem = r
        else:
            prop_cel = f"PENDENTE — {motivo}"
            pendentes.append({"id": ident, "tipo": "PROPOSICAO-PENDENTE", "detalhe": motivo})
    acao = " · ".join(["«preencher»"] + obs)
    linhas.append({"id": ident, "ciclo": (reg or {}).get("ciclo", ""), "classe": (reg or {}).get("classe", ""),
                   "veredito": veredito, "classe_fiscal": cls, "categoria": categoria,
                   "fontes": fontes, "destino": destino, "proposicao": prop_cel,
                   "proposicao_linhas_de": prop_origem,
                   "vinculo_goal": (ach or {}).get("vinculo_goal", ""),
                   "md": f"| {ident} | {alegacao_cel} | {fontes_cel} | {veredito} | {destino} | {acao} | {prop_cel} |",
                   "alegacao": alegacao_cel, "evidencia": celula(evidencia)})

contagem = {k: sum(1 for l in linhas if l["classe_fiscal"] == k)
            for k in ("confirmados", "descartados", "dispensados", "outros")}

# dívidas: confirmado_irrelevante, ou confirmado com vinculo_goal «nenhum»
dividas = [l for l in linhas if l["classe_fiscal"] == "dispensados"
           or (l["classe_fiscal"] == "confirmados" and re.match(r"\s*nenhum", l["vinculo_goal"] or "", re.I))]

# por ciclo
por_ciclo = []
for c in ciclos:
    ls = [l for l in linhas if l["ciclo"] == c]
    conf = [l for l in ls if l["classe_fiscal"] == "confirmados"]
    disp = [l for l in ls if l["classe_fiscal"] == "dispensados"]

    def agrupa(lst):
        g = {}
        for l in lst:
            g.setdefault(l["categoria"] or "sem categoria", []).append(l["id"])
        return "; ".join(f"{k}: {', '.join(v)}" for k, v in g.items())
    por_ciclo.append(f"- Ciclo {c}: {len(conf)} confirmado(s)" + (f" ({agrupa(conf)})" if conf else "")
                     + f" · {len(disp)} dispensado(s)" + (f" ({agrupa(disp)})" if disp else ""))

rc = 1 if (divergencias or pendentes) else 0

if modo == "--json":
    print(json.dumps({"contagem": contagem, "linhas": [{k: v for k, v in l.items() if k != "md"} for l in linhas],
                      "dividas": [l["id"] for l in dividas], "divergencias": divergencias,
                      "pendentes": pendentes, "fontes_lidas": sorted(set(fontes_lidas))},
                     ensure_ascii=False))
    raise SystemExit(rc)

out = []
out.append(f"<!-- gera-intent-review.sh: gerado de {', '.join(sorted(set(fontes_lidas)))}. "
           "O coordenador escreve só «ação tomada» e dono/destino das dívidas; "
           "não edite veredito nem contagem à mão. -->")
out.append("")
out.append("## Contagens do frontmatter")
out.append("")
out.append("```yaml")
out.append(f"achados_confirmados: {contagem['confirmados']}")
out.append(f"achados_descartados: {contagem['descartados']}")
out.append(f"achados_dispensados: {contagem['dispensados']}")
out.append("```")
if contagem["outros"]:
    out.append(f"\n{contagem['outros']} linha(s) com veredito fora do vocabulário do fiscal — ficam na tabela e fora das contagens.")
out.append("")
out.append("## Novos confirmados por ciclo")
out.append("")
out += por_ciclo
out.append("")
out.append("## Tabela de achados")
out.append("")
out.append("| id | alegação | fontes | veredito | destino | ação tomada | proposição |")
out.append("|----|----------|--------|----------|---------|-------------|------------|")
out += [l["md"] for l in linhas]
out.append("")
out.append("## Dívidas registradas")
out.append("")
if dividas:
    out.append("| id | alegação | evidência | dono | destino |")
    out.append("|----|----------|-----------|------|---------|")
    for l in dividas:
        ev = l["evidencia"] or "—"
        vg = celula(l["vinculo_goal"]) if l["vinculo_goal"] else ""
        out.append(f"| {l['id']} | {l['alegacao'].split(' — evidência: ')[0]} | {ev}{(' · vinculo_goal: ' + vg) if vg else ''} | «preencher» | «preencher» |")
else:
    out.append("nenhuma (dos arquivos do verificador; dívida decidida pelo coordenador entra à mão)")
if divergencias or pendentes:
    out.append("")
    out.append("## Divergências dos arquivos do verificador")
    out.append("")
    out.append("Não resolvidas pelo gerador (FM-F27INS-07INT): decida e registre antes de colar a tabela.")
    out.append("")
    for d in divergencias:
        out.append(f"- {d['tipo']} {d['detalhe']}")
    for p in pendentes:
        out.append(f"- {p['tipo']} {p['id']}: {p['detalhe']}")
print("\n".join(out))
for d in divergencias:
    print(f"gera-intent-review: {d['tipo']} {d['detalhe']}", file=sys.stderr)
for p in pendentes:
    print(f"gera-intent-review: {p['tipo']} {p['id']}: {p['detalhe']}", file=sys.stderr)
raise SystemExit(rc)
PYGERA
