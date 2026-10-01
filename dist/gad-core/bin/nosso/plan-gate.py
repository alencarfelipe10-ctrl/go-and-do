#!/usr/bin/env python3
"""plan-gate.py — portão §13a-bis do plan-phase (fork gen5-patches, P13, 01/09/2026).

Confere a FORMA dos planos de uma fase depois que o checker aprovou: sobreposição de
arquivos dentro da onda, files_modified vazio, dependência que não resolve, wave: que
mente, cadeia quase-serial, reversibilidade sem checkpoint, arquivo-hub (aviso) e largura
máxima 1 (aviso). Tudo mecânico, lendo o mesmo índice que a execução consome
(`gad-tools phase-plan-index <fase> --raw`) e os `*-PLAN.md` da fase.

Uso:
  plan-gate.py <phase_dir> <plan-index.json> [--min-planos 4] [--razao 0.6]
               [--no-reversibility-gates] [--irreversiveis ARQ] [--out ARQ | --no-out]
  plan-gate.py <phase_dir> <plan-index.json> --probe-lastro

`--min-planos N`: as cláusulas de cadeia e de largura valem a partir de N planos (plano 4 /
B5, 05/09/2026: antes o default 3 era lido como "mais de 3"; agora N é o primeiro tamanho
em que a cláusula vale). `--razao 0.6`: ondas/planos a partir daí é cadeia quase-serial.

Lastro (B2/B4/B5): uma dependência tem lastro quando o plano dependente cita algo NOMEADO que
o pré-requisito cria — um caminho do `files_modified`/`files_deleted` dele (caminho inteiro,
nome do arquivo, ou o módulo quando o nome tem 10+ caracteres), o SUMMARY dele
(`<id>-SUMMARY`), ou o id do plano na mesma linha de um identificador de código. A
justificativa `depends_on_rationale:` só desarma a cláusula de cadeia quando ela própria
traz esse lastro; prosa solta não desarma mais. `--probe-lastro` imprime
{arestas:[{de, para, lastro, evidencia}], razao, largura_max, hubs} e sai 0 — é a terceira
sonda determinística do checker (plan-phase/blocks/checker.md).

Saída (stdout): JSON {passed, falhas:[{codigo, planos, detalhe}], avisos:[...], resumo}.
Exit: 0 passou · 1 reprovou · 2 erro de uso/entrada.
Também grava a mesma saída em <.planning>/.gad/last-plan-gate.json quando encontra o
`.planning` acima de <phase_dir> (a go-and-do lê esse arquivo no fecho da etapa 2).
"""
import argparse
import json
import os
import re
import sys
from itertools import combinations

CODIGOS = (
    "SOBREPOSICAO-NA-ONDA",
    "FILES-MODIFIED-VAZIO",
    "DEPENDENCIA-NAO-RESOLVE",
    "WAVE-DECLARADA-DIVERGE",
    "CADEIA-QUASE-SERIAL",
    "ONE-WAY-SEM-CHECKPOINT",
    "TAREFA-SEM-RATING",
    "ARQUIVO-HUB",
    "LARGURA-MAXIMA-1",
)
TIPOS_SEM_ARQUIVO = {"checkpoint", "research"}
RE_NAO_RESOLVE = re.compile(r"does not resolve to any plan")
RE_WAVE_DIVERGE = re.compile(r"declared wave: (\d+) but depends_on DAG places it in wave (\d+)")
RE_PLAN_WARN = re.compile(r"^Plan ([^:]+):")
RE_TASK = re.compile(r"<task\b([^>]*)>(.*?)</task>", re.S)
RE_ATTR = re.compile(r'(\w+)="([^"]*)"')
RE_REV = re.compile(r'<reversibility\b[^>]*rating="([^"]*)"')
RE_ACTION = re.compile(r"<action>(.*?)</action>", re.S)
RE_NAME = re.compile(r"<name>(.*?)</name>", re.S)
RE_RATIONALE_COMMENT = re.compile(r"<!--\s*depende de\s+\S+\s+porque(.*?)-->", re.I | re.S)
RE_IDENT = re.compile(r"`[^`\n]{3,}`|\b[A-Za-z_][A-Za-z0-9_]*(?:_[A-Za-z0-9_]+)+\b|\b[\w./-]+\.(?:py|js|ts|cjs|md|json|yaml|yml|sh|sql|toml)\b")


# ---------- leitura ----------

def ler_frontmatter(texto):
    """Leitor mínimo de YAML de frontmatter: escalares, listas inline e listas em bloco
    de 1º nível. Só para os campos que o gate usa (type, autonomous, files_deleted,
    files_modified, depends_on_rationale)."""
    if not texto.startswith("---"):
        return {}, texto
    fim = texto.find("\n---", 3)
    if fim < 0:
        return {}, texto
    bloco = texto[3:fim]
    corpo = texto[fim + 4:]
    fm = {}
    chave = None
    for linha in bloco.splitlines():
        if not linha.strip() or linha.lstrip().startswith("#"):
            continue
        if not linha.startswith((" ", "\t")):
            m = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", linha)
            if not m:
                chave = None
                continue
            chave, val = m.group(1), m.group(2).strip()
            if val.startswith("["):
                itens = val.strip("[]").split(",")
                fm[chave] = [i.strip().strip("'\"") for i in itens if i.strip()]
            elif val == "":
                fm[chave] = []
            else:
                fm[chave] = val.strip("'\"")
        elif chave is not None and isinstance(fm.get(chave), list):
            s = linha.strip()
            if s.startswith("- "):
                fm[chave].append(s[2:].strip().strip("'\""))
    return fm, corpo


def carregar_planos(phase_dir, indice):
    """Casa cada plano do índice com o arquivo PLAN.md; devolve dict id -> info."""
    arquivos = sorted(f for f in os.listdir(phase_dir) if f.endswith("-PLAN.md"))
    por_id = {}
    for f in arquivos:
        caminho = os.path.join(phase_dir, f)
        with open(caminho, encoding="utf-8") as fh:
            texto = fh.read()
        fm, corpo = ler_frontmatter(texto)
        por_id[f[: -len("-PLAN.md")]] = {"arquivo": f, "fm": fm, "corpo": corpo, "texto": texto}
    planos = {}
    for p in indice.get("plans", []):
        pid = p["id"]
        disco = por_id.get(pid) or next((v for k, v in por_id.items() if k.startswith(pid)), None)
        planos[pid] = {"idx": p, "disco": disco}
    return planos


def tarefas(corpo):
    """Lista de tarefas na ordem do arquivo: {type, name, action, rating}."""
    out = []
    for m in RE_TASK.finditer(corpo):
        attrs = dict(RE_ATTR.findall(m.group(1)))
        miolo = m.group(2)
        rev = RE_REV.search(miolo)
        act = RE_ACTION.search(miolo)
        nome = RE_NAME.search(miolo)
        out.append({
            "type": attrs.get("type", "auto"),
            "name": (nome.group(1).strip() if nome else "?")[:80],
            "action": act.group(1) if act else "",
            "rating": rev.group(1) if rev else None,
        })
    return out


def carregar_irreversiveis(caminho):
    regs = []
    if not caminho or not os.path.isfile(caminho):
        return regs
    with open(caminho, encoding="utf-8") as fh:
        for n, linha in enumerate(fh, 1):
            s = linha.strip()
            if not s or s.startswith("#"):
                continue
            try:
                regs.append((s, re.compile(s, re.I)))
            except re.error as e:
                print(f"aviso: regex inválida em {caminho}:{n}: {e}", file=sys.stderr)
    return regs


# ---------- cláusulas ----------

def c1_sobreposicao(planos, indice, falhas):
    for onda, ids in indice.get("waves", {}).items():
        arqs = {}
        for pid in ids:
            info = planos.get(pid)
            if not info:
                continue
            p = info["idx"]
            deleted = p.get("files_deleted")
            if deleted is None and info["disco"]:
                deleted = info["disco"]["fm"].get("files_deleted") or []
            arqs[pid] = set(p.get("files_modified") or []) | set(deleted or [])
        for a, b in combinations(ids, 2):
            comum = sorted(arqs.get(a, set()) & arqs.get(b, set()))
            if comum:
                falhas.append({"codigo": "SOBREPOSICAO-NA-ONDA", "planos": [a, b],
                               "detalhe": f"onda {onda}: {a} e {b} tocam {', '.join(comum)}"})


def c2_files_vazio(planos, falhas):
    for pid, info in planos.items():
        if info["idx"].get("files_modified"):
            continue
        tipo = (info["disco"]["fm"].get("type") if info["disco"] else None) or "execute"
        if tipo in TIPOS_SEM_ARQUIVO:
            continue
        no_arquivo = len(info["disco"]["fm"].get("files_modified") or []) if info["disco"] else 0
        det = f"{pid}: files_modified vazio no índice (o executor não vê arquivo nenhum e a guarda de sobreposição fica desarmada)"
        if no_arquivo:
            det += f"; o arquivo declara {no_arquivo} entrada(s), mas o parser do GAD não leu o frontmatter — YAML inválido, corrija o frontmatter"
        falhas.append({"codigo": "FILES-MODIFIED-VAZIO", "planos": [pid], "detalhe": det})


def c3_c4_warnings(indice, falhas):
    for w in indice.get("warnings", []) or []:
        m = RE_PLAN_WARN.match(w)
        pid = m.group(1) if m else "?"
        if RE_NAO_RESOLVE.search(w):
            falhas.append({"codigo": "DEPENDENCIA-NAO-RESOLVE", "planos": [pid], "detalhe": w})
        elif RE_WAVE_DIVERGE.search(w):
            falhas.append({"codigo": "WAVE-DECLARADA-DIVERGE", "planos": [pid],
                           "detalhe": w + " — wave: é calculado das dependências; escreva o valor do cálculo ou omita"})


def cadeias(planos, indice):
    """Cadeias = sequências de ondas de largura 1 encadeadas por depends_on."""
    ondas = sorted(((int(k), v) for k, v in indice.get("waves", {}).items()), key=lambda x: x[0])
    resultado, atual = [], []
    for _, ids in ondas:
        if len(ids) == 1:
            pid = ids[0]
            deps = set(planos[pid]["idx"].get("depends_on") or []) if pid in planos else set()
            if atual and atual[-1] in deps:
                atual.append(pid)
            else:
                if len(atual) > 1:
                    resultado.append(atual)
                atual = [pid]
        else:
            if len(atual) > 1:
                resultado.append(atual)
            atual = []
    if len(atual) > 1:
        resultado.append(atual)
    return resultado


def arquivos_de(info):
    """files_modified ∪ files_deleted de um plano (índice, com o frontmatter como reserva)."""
    if not info:
        return []
    p = info["idx"]
    arqs = list(p.get("files_modified") or [])
    deleted = p.get("files_deleted")
    if deleted is None and info["disco"]:
        deleted = info["disco"]["fm"].get("files_deleted") or []
    return arqs + list(deleted or [])


def _num(pid):
    return pid.rsplit("-", 1)[-1]


def lastro(texto, prereq_id, prereq_info):
    """(bool, evidência): o texto cita algo nomeado que o pré-requisito cria?"""
    if not texto:
        return False, ""
    for arq in arquivos_de(prereq_info):
        base = os.path.basename(arq)
        stem = os.path.splitext(base)[0]
        if arq in texto:
            return True, f"cita {arq}"
        # borda: `base.py` não pode casar `database.py` nem `tests/base.py`; nomes genéricos
        # (`__init__.py`, `conftest.py`) ainda casam por nome — limitação conhecida
        if base and re.search(r"(?<![\w/.-])" + re.escape(base) + r"(?![\w])", texto):
            return True, f"cita {base}"
        if len(stem) >= 10 and re.search(r"(?<![\w.])" + re.escape(stem) + r"(?![\w])", texto):
            return True, f"cita o módulo {stem}"
    if f"{prereq_id}-SUMMARY" in texto:
        return True, f"lê {prereq_id}-SUMMARY"
    num = _num(prereq_id)
    padrao = re.compile(r"(?<![\w.])" + re.escape(prereq_id) + r"(?![\w.])|\b[Pp]lan(?:o|e)?\s+" + re.escape(num) + r"\b")
    for linha in texto.splitlines():
        if padrao.search(linha):
            m = RE_IDENT.search(padrao.sub(" ", linha))
            if m:
                return True, f"cita {prereq_id} junto de {m.group(0)[:40]}"
    return False, ""


def texto_rationale(info):
    """Só a justificativa declarada: `depends_on_rationale:` e/ou o comentário `<!-- depende de … -->`."""
    if not info or not info["disco"]:
        return ""
    fm, texto = info["disco"]["fm"], info["disco"]["texto"]
    partes = []
    r = fm.get("depends_on_rationale")
    if r:
        partes.append(r if isinstance(r, str) else " ".join(r))
    partes += [m.group(0) for m in RE_RATIONALE_COMMENT.finditer(texto)]
    return "\n".join(partes)


def justificado(info, planos):
    """A justificativa desarma a cadeia só quando cita arquivo ou símbolo de um pré-requisito."""
    if not info or not info["disco"]:
        return False
    just = texto_rationale(info)
    if not just:
        return False
    for dep in info["idx"].get("depends_on") or []:
        if lastro(just, dep, planos.get(dep))[0]:
            return True
    return False


def arestas_com_lastro(planos):
    out = []
    for pid, info in planos.items():
        # só o corpo: o frontmatter do próprio plano (depends_on:, files_modified:) não é citação
        texto = info["disco"]["corpo"] if info["disco"] else ""
        for dep in info["idx"].get("depends_on") or []:
            ok, ev = lastro(texto, dep, planos.get(dep))
            out.append({"de": pid, "para": dep, "lastro": ok, "evidencia": ev})
    return out


def hubs(planos, minimo=3):
    por_arquivo = {}
    for pid, info in planos.items():
        for arq in set(arquivos_de(info)):
            por_arquivo.setdefault(arq, []).append(pid)
    return [{"arquivo": a, "planos": sorted(ps)} for a, ps in sorted(por_arquivo.items()) if len(ps) >= minimo]


def c5_cadeia(planos, indice, min_planos, razao, falhas, avisos):
    n_planos = len(indice.get("plans", []))
    n_ondas = len(indice.get("waves", {}))
    if n_planos < min_planos or n_planos == 0:
        return n_planos, n_ondas
    r = n_ondas / n_planos
    if r < razao:
        return n_planos, n_ondas
    cs = cadeias(planos, indice)
    desc = ["→".join(c) for c in cs] or ["(sem cadeia contígua; as ondas estreitas estão espalhadas)"]
    dependentes = [pid for c in cs for pid in c[1:]]
    todos_justificados = bool(dependentes) and all(justificado(planos.get(pid), planos) for pid in dependentes)
    det = (f"{n_ondas} ondas para {n_planos} planos (razão {r:.2f} ≥ {razao}); cadeias: {'; '.join(desc)}. "
           "Justifique cada dependência com `depends_on_rationale:` no frontmatter ou uma linha "
           "`<!-- depende de NN porque … -->` citando um arquivo ou símbolo do pré-requisito, ou refatie para ondas mais largas")
    item = {"codigo": "CADEIA-QUASE-SERIAL", "planos": sorted({p for c in cs for p in c}) or [p["id"] for p in indice["plans"]],
            "detalhe": det}
    (avisos if todos_justificados else falhas).append(item)
    return n_planos, n_ondas


def c6_reversibilidade(planos, irreversiveis, destino):
    for pid, info in planos.items():
        if not info["disco"]:
            continue
        fm = info["disco"]["fm"]
        ts = tarefas(info["disco"]["corpo"])
        autonomo = str(fm.get("autonomous", "true")).lower() == "true"
        tem_checkpoint = any(t["type"].startswith("checkpoint:") for t in ts)
        houve_decision = False
        for i, t in enumerate(ts, 1):
            if t["type"] == "checkpoint:decision":
                houve_decision = True
            if t["rating"] == "one-way" and not houve_decision:
                destino.append({"codigo": "ONE-WAY-SEM-CHECKPOINT", "planos": [pid],
                                "detalhe": f"{pid} tarefa {i} ({t['name']}): rating one-way sem checkpoint:decision antes dela"})
            if t["rating"] is None and t["action"] and not t["type"].startswith("checkpoint:"):
                hits = [src for src, rx in irreversiveis if rx.search(t["action"])]
                if hits:
                    destino.append({"codigo": "TAREFA-SEM-RATING", "planos": [pid],
                                    "detalhe": f"{pid} tarefa {i} ({t['name']}): a ação casa com `{hits[0]}` e não tem <reversibility>; classifique-a (reversible|costly|one-way)"})
        if tem_checkpoint and autonomo:
            destino.append({"codigo": "ONE-WAY-SEM-CHECKPOINT", "planos": [pid],
                            "detalhe": f"{pid}: tem tarefa checkpoint:* e autonomous: true; todo plano com checkpoint é autonomous: false"})


def c7_hubs(planos, avisos):
    for h in hubs(planos):
        avisos.append({"codigo": "ARQUIVO-HUB", "planos": h["planos"],
                       "detalhe": f"{h['arquivo']} em {len(h['planos'])} planos ({', '.join(h['planos'])}): concentre num plano-fundação da onda 1 ou dê um símbolo por plano em ondas sucessivas"})


def c8_largura(indice, min_planos, avisos):
    n_planos = len(indice.get("plans", []))
    largura = max((len(v) for v in indice.get("waves", {}).values()), default=0)
    if n_planos >= min_planos and largura <= 1:
        avisos.append({"codigo": "LARGURA-MAXIMA-1", "planos": [p["id"] for p in indice.get("plans", [])],
                       "detalhe": f"{n_planos} planos e nenhuma onda com 2 ou mais: a fase inteira roda em série"})


# ---------- main ----------

def achar_planning(phase_dir):
    d = os.path.abspath(phase_dir)
    for _ in range(6):
        if os.path.basename(d) == ".planning":
            return d
        pai = os.path.dirname(d)
        if pai == d:
            break
        d = pai
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("phase_dir")
    ap.add_argument("plan_index")
    ap.add_argument("--min-planos", type=int, default=4, help="as cláusulas de cadeia e largura valem a partir de N planos")
    ap.add_argument("--razao", type=float, default=0.6)
    ap.add_argument("--probe-lastro", action="store_true", help="só a sonda de lastro: JSON {arestas, razao, largura_max, hubs}, exit 0, nada gravado")
    ap.add_argument("--no-reversibility-gates", action="store_true", help="cláusula 6 vira aviso")
    ap.add_argument("--irreversiveis", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "plan-gate-irreversiveis.txt"))
    ap.add_argument("--out", default=None, help="arquivo JSON de saída (default: <.planning>/.gad/last-plan-gate.json)")
    ap.add_argument("--no-out", action="store_true")
    a = ap.parse_args()

    if not os.path.isdir(a.phase_dir):
        print(f"erro: phase_dir não existe: {a.phase_dir}", file=sys.stderr)
        return 2
    try:
        with open(a.plan_index, encoding="utf-8") as fh:
            indice = json.load(fh)
    except (OSError, ValueError) as e:
        print(f"erro: índice ilegível ({e})", file=sys.stderr)
        return 2
    if "plans" not in indice:
        print("erro: índice sem `plans` (saída de phase-plan-index esperada)", file=sys.stderr)
        return 2

    planos = carregar_planos(a.phase_dir, indice)
    if a.probe_lastro:
        n_p = len(indice.get("plans", [])); n_o = len(indice.get("waves", {}))
        print(json.dumps({"arestas": arestas_com_lastro(planos),
                          "razao": round(n_o / n_p, 2) if n_p else None,
                          "largura_max": max((len(v) for v in indice.get("waves", {}).values()), default=0),
                          "hubs": hubs(planos)}, ensure_ascii=False, indent=2))
        return 0
    falhas, avisos = [], []
    c1_sobreposicao(planos, indice, falhas)
    c2_files_vazio(planos, falhas)
    c3_c4_warnings(indice, falhas)
    n_planos, n_ondas = c5_cadeia(planos, indice, a.min_planos, a.razao, falhas, avisos)
    c6_reversibilidade(planos, carregar_irreversiveis(a.irreversiveis), avisos if a.no_reversibility_gates else falhas)
    c7_hubs(planos, avisos)
    c8_largura(indice, a.min_planos, avisos)

    saida = {
        "passed": not falhas,
        "falhas": falhas,
        "avisos": avisos,
        "resumo": {"fase": indice.get("phase"), "planos": n_planos, "ondas": n_ondas,
                   "razao": round(n_ondas / n_planos, 2) if n_planos else None,
                   "largura_max": max((len(v) for v in indice.get("waves", {}).values()), default=0),
                   "reversibility_gates": not a.no_reversibility_gates},
    }
    txt = json.dumps(saida, ensure_ascii=False, indent=2)
    print(txt)
    if not a.no_out:
        dest = a.out
        if not dest:
            planning = achar_planning(a.phase_dir)
            dest = os.path.join(planning, ".gad", "last-plan-gate.json") if planning else None
        if dest:
            try:
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest, "w", encoding="utf-8") as fh:
                    fh.write(txt + "\n")
            except OSError as e:
                print(f"aviso: não gravei {dest}: {e}", file=sys.stderr)
    return 0 if saida["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
