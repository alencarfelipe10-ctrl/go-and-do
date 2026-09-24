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
