#!/usr/bin/env python3
"""fh-render.py — conversor determinístico NN-SPEC-FH.md → NN-SPEC-FH.html.

Uso: python3 fh-render.py caminho/para/NN-SPEC-FH.md
Escreve o .html ao lado do .md. Sem dependências fora da stdlib.
Formato de entrada: o molde de references/for-humans.md (título, "**Em uma
frase:**", seções ##, listas, rodapé em itálico).
"""
import html
import re
import sys
from pathlib import Path

CSS = """:root{--bg:#0e0f12;--panel:#16181d;--border:#2a2e37;--text:#e8eaed;--muted:#9aa0ab;--accent:#7aa2f7;--green:#9ece6a}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font-family:'Geist','Inter',system-ui,sans-serif;line-height:1.7;font-size:17px}
.wrap{max-width:760px;margin:0 auto;padding:48px 24px 80px}
h1{font-size:1.7rem;line-height:1.3;margin:0 0 8px}
.lead{background:var(--panel);border:1px solid var(--border);border-left:4px solid var(--accent);border-radius:10px;padding:14px 18px;margin:20px 0;font-size:1.05rem}
h2{font-size:1.15rem;color:var(--accent);margin:36px 0 10px;padding-bottom:6px;border-bottom:1px solid var(--border)}
ul{margin:10px 0;padding-left:24px}
li{margin:8px 0}
footer{margin-top:44px;color:var(--muted);font-size:.85rem;border-top:1px solid var(--border);padding-top:14px;font-style:italic}
b{color:#fff}"""


def inline(s: str) -> str:
    s = html.escape(s, quote=False).replace('"', "&quot;")
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<i>\1</i>", s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return s


def render(md: str) -> str:
    lines = md.splitlines()
    title = ""
    body = []
    in_list = False
    footer = ""

    def close_list():
        nonlocal in_list
        if in_list:
            body.append("</ul>")
            in_list = False

    for ln in lines:
        s = ln.strip()
        if not s:
            close_list()
            continue
        if s.startswith("# ") and not title:
            title = s[2:].strip()
        elif s.startswith("## "):
            close_list()
            body.append(f"<h2>{inline(s[3:].strip())}</h2>")
        elif s.startswith("- "):
            if not in_list:
                body.append("<ul>")
                in_list = True
            body.append(f"<li>{inline(s[2:].strip())}</li>")
        elif s.startswith("**Em uma frase:**"):
            close_list()
            body.append(f'<div class="lead">{inline(s)}</div>')
        elif s.startswith("*") and s.endswith("*") and not s.startswith("**"):
            close_list()
            footer = inline(s[1:-1])
        else:
            close_list()
            body.append(f"<p>{inline(s)}</p>")
    close_list()

    parts = [
        "<!DOCTYPE html>",
        '<html lang="pt-BR"><head><meta charset="UTF-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
        f"<title>{html.escape(title)}</title>",
        f"<style>\n{CSS}\n</style>",
        '</head><body><div class="wrap">',
        f"<h1>{inline(title)}</h1>",
        *body,
    ]
    if footer:
        parts.append(f"<footer>{footer}</footer>")
    parts.append("</div></body></html>")
    return "\n".join(parts) + "\n"


def main() -> int:
    if len(sys.argv) != 2:
        print("uso: fh-render.py <NN-SPEC-FH.md>", file=sys.stderr)
        return 1
    src = Path(sys.argv[1])
    if not src.is_file():
        print(f"ERRO: {src} não existe", file=sys.stderr)
        return 1
    out = src.with_suffix(".html")
    out.write_text(render(src.read_text(encoding="utf-8")), encoding="utf-8")
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
