"""lib/gad_caminhos.py — gêmeo em Python do lib/gad-caminhos.sh (v2.10.1, tarefas 56/57).

Mesma tabela, mesmos nomes. Quem importa: mede-tokens.py, pos-ship.py, o Python embutido do
briefing-build.sh e do confere-cardinalidade.sh. A /audit-gad importa este arquivo pelo
caminho instalado (ou por GAD_CAMINHOS_PY) — não copia a regra.

Raiz da .planning (56):
  estado_dir(root)            → <root>/.planning/.gad
  estado_garante(root)        → cria a pasta + .gitignore com `*`
  cache_dir(root)             → `git rev-parse --path-format=absolute --git-path gad-cache`
                                (fallback sem git: $XDG_CACHE_HOME/gad/<nome>-<hash>)
  eh_estado(slug)             → o espelho last-<slug>.json é ESTADO? (lista explícita)
  espelho_caminho(root, slug) → onde mora last-<slug>.json
  rodada_ativa(root)          → ponteiro novo, ou o legado se só ele existir (None se nenhum)
"""
import hashlib
import os
import subprocess

ESTADO_SLUGS = ("pre-despacho", "pre-despacho-3", "pre-gate", "plan-gate")


def estado_dir(root):
    return os.path.join(root, ".planning", ".gad")


def estado_garante(root):
    d = estado_dir(root)
    os.makedirs(d, exist_ok=True)
    gi = os.path.join(d, ".gitignore")
    if not os.path.exists(gi):
        with open(gi, "w", encoding="utf-8") as fh:
            fh.write("# go-and-do v2.10.1 (56(d)): estado efêmero da rodada — nunca vai para o git.\n"
                     "# Evidência da fase mora em .planning/phases/*/.gad/ e É commitada.\n*\n")
    return d


def cache_dir(root):
    try:
        r = subprocess.run(["git", "-C", root, "rev-parse", "--path-format=absolute",
                            "--git-path", "gad-cache"], capture_output=True, text=True, timeout=5)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except Exception:
        pass
    h = hashlib.sha1(root.encode("utf-8")).hexdigest()[:12]
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(base, "gad", f"{os.path.basename(root.rstrip('/'))}-{h}")


def eh_estado(slug):
    return slug in ESTADO_SLUGS


def espelho_caminho(root, slug):
    d = estado_dir(root) if eh_estado(slug) else cache_dir(root)
    return os.path.join(d, f"last-{slug}.json")


def rodada_ativa(root):
    for p in (os.path.join(root, ".planning", ".gad", "rodada-ativa.json"),
              os.path.join(root, ".planning", ".gad-rodada-ativa.json")):
        if os.path.isfile(p):
            return p
    return None


# ═════════════════════════════════════════════════════════════════════════════
# PASTA DA FASE (57) — mesma tabela do lib/gad-caminhos.sh (ver o cabeçalho de lá)
#   fase_formato(pd) → "novo" | "antigo"
#   legado_rel(rel)  → nome antigo relativo à fase (aceita globs)
#   caminho(pd, rel) → caminho real conforme o formato da fase
#   glob_fase(pd, relpadrao) → lista ordenada dos arquivos que casam
#   curinga(pd, relpadrao, arquivo) → trecho casado pelo único `*` do padrão
# ═════════════════════════════════════════════════════════════════════════════
import glob as _glob
import re as _re

_RE_CICLO = _re.compile(r"^c([0-9*?\[][^/]*)(?:/(.*))?$")


def fase_formato(pd):
    return "novo" if os.path.isfile(os.path.join(pd, ".gad", "FORMATO")) else "antigo"


def legado_rel(rel):
    if rel in ("intent", "convergencia"):
        return "." + rel
    if rel.startswith("intent/") or rel.startswith("convergencia/"):
        b, r = rel.split("/", 1)
        m = _RE_CICLO.match(r)
        if m:
            k, n = m.group(1), (m.group(2) or "")
            if n == "":
                return "." + b
            if n == "runs":
                return f".{b}/runs/c{k}"
            if n.startswith("runs/"):
                return f".{b}/runs/c{k}/{n[5:]}"
            if n == "briefing.md":
                return f".{b}/briefing-c{k}.md"
            if n == "briefing*.md":
                return f".{b}/briefing-c{k}*.md"
            if n.startswith("briefing-") and n.endswith(".md"):
                return f".{b}/briefing-c{k}-{n[len('briefing-'):]}"
            if n.startswith("status-"):
                return f".{b}/.status-c{k}-{n[len('status-'):]}"
            if n.startswith("done-"):
                return f".{b}/.done-c{k}-{n[len('done-'):]}"
            if n == "ciclo.json":
                return f".{b}/.ciclo{k}.json"
            base = n.split(".", 1)[0]
            ext = n[len(base):]
            return f".{b}/.{base}-c{k}{ext}"
        if r == "pre-spec-route.json":
            return f".{b}/{r}"
        return f".{b}/.{r}"
    if rel == "lanes":
        return "pareceres"
    if rel.startswith("lanes/"):
        return "pareceres/." + rel[len("lanes/"):]
    if rel.startswith("fences/"):
        return ".fence-" + rel[len("fences/"):]
    if rel.startswith("gates/"):
        return ".gate-fail-" + rel[len("gates/"):]
    if rel == "plan-checker" or rel.startswith("plan-checker/"):
        return "." + rel
    if rel.startswith("pos-ship/"):
        return ".pos-ship-" + rel[len("pos-ship/"):]
    if rel.startswith("uat/"):
        return ".uat-" + rel[len("uat/"):]
    return ".gad/" + rel


def caminho(pd, rel):
    pd = pd.rstrip("/")
    if fase_formato(pd) == "novo":
        return os.path.join(pd, ".gad", rel)
    return os.path.join(pd, legado_rel(rel))


def glob_fase(pd, relpadrao):
    return sorted(_glob.glob(caminho(pd, relpadrao)))


def curinga(pd, relpadrao, arquivo):
    pat = caminho(pd, relpadrao)
    pre, suf = pat.split("*", 1)
    s = arquivo[len(pre):] if arquivo.startswith(pre) else arquivo
    return s[: len(s) - len(suf)] if suf and s.endswith(suf) else s


def fase_de_base(d):
    """phase_dir a partir da base de trabalho da revisão (.intent, .gad/intent, pareceres…)."""
    d = d.rstrip("/")
    for suf in ("/.gad/intent", "/.gad/convergencia", "/.gad/lanes"):
        if d.endswith(suf):
            return d[: -len(suf)]
    for suf in ("/.intent", "/.convergencia", "/pareceres"):
        if d.endswith(suf):
            return d[: -len(suf)]
    return d


def arq_da_base(base, rel):
    """Arquivo pelo nome novo a partir de uma base de trabalho; base avulsa → nome antigo nela."""
    b = base.rstrip("/")
    pd = fase_de_base(b)
    if pd != b:
        return caminho(pd, rel)
    return os.path.join(b, os.path.basename(legado_rel(rel)))
