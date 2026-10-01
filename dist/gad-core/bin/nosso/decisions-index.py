#!/usr/bin/env python3
"""decisions-index.py — produtor determinístico do .planning/DECISIONS-INDEX.md (gad-discuss-phase, fork).

O workflow upstream promete o arquivo ("If .planning/DECISIONS-INDEX.md exists, read that
instead", discuss-phase.md) mas nada o produz. Este script varre
.planning/phases/*/*-CONTEXT.md, recorta <decisions> E <specifics> de cada um e regrava o
índice DO ZERO (idempotente — rodar 2× dá arquivo idêntico).

Uso: decisions-index.py <.planning dir> [--last N] [--out PATH] [--soft-limit-kb 60] [--recent 12]
     decisions-index.py <.planning dir> --vista --out PATH [--recent 1] [--linha-max 160]

Ordem das fases: token numérico após prefixo opcional `[A-Z]+-` (AOS-07, INS-24.2, RLR-02,
24.1, 21) → tupla numérica; variante de letra desempata; dir que não casa vai ao fim em ordem
lexical com aviso em stderr (nunca omitido). Ignora BACKLOG-CONTEXT.md e fases 999.*.

Compactação ([C2-26]/[C3-07]): acima do limite suave, fases além das N mais recentes ficam em
forma compacta E completa (todo bullet D-NN mantido — só a 1ª linha; Claude's Discretion
colapsado a 1 linha com contagem; specifics deduplicados). Nunca digest, nunca omissão: se
ainda passar do limite, o índice fica maior e avisa.

Vista recortada (C6, plano 2 / 05/09/2026): `--vista` escreve em `--out` (obrigatório e nunca
o índice canônico) a VISÃO DE LEITURA do discuss — compactação incondicional das fases além
das `--recent` mais recentes e, nelas, cada bullet D-NN cortado em `--linha-max` chars com o
sufixo ` → <arquivo>#D-NN` (o caminho está no `source:` do cabeçalho da fase). A regra "nunca resumir" rege o
arquivo commitado, que continua completo; a vista é o que entra na janela (265 KB → ~71 KB
no inspired com --recent 1). Todo D-NN continua presente na vista: só o corpo é cortado.
"""
import argparse
import os
import re
import sys

PHASE_TOKEN = re.compile(r"^(?:[A-Z]+-)?(\d+)([A-Z])?((?:\.\d+)*)-?(.*)$")
TITLE_RE = re.compile(r"^#\s+Phase\s+[^:]+:\s*(.+?)\s*-\s*Context\s*$", re.I)


def log(msg):
    sys.stderr.write(f"[index] {msg}\n")


def phase_key(dirname):
    m = PHASE_TOKEN.match(dirname)
    if not m:
        return None
    major, letter, minors, _ = m.groups()
    nums = (int(major),) + tuple(int(x) for x in minors.split(".") if x)
    return (nums, letter or "")


def extract_block(text, tag):
    m = re.search(rf"<{tag}>\n?(.*?)\n?</{tag}>", text, re.S)
    return (m.group(1).strip("\n") if m else "")


def phase_name(text, dirname):
    for ln in text.splitlines()[:5]:
        m = TITLE_RE.match(ln.strip())
        if m:
            return m.group(1)
    m = PHASE_TOKEN.match(dirname)
    return (m.group(4) if m else dirname).replace("-", " ")


def compact_decisions(block, linha_max=0, rel=""):
    """`linha_max` > 0 (vista): o bullet é cortado em N chars e ganha ` → <arquivo>#<D-NN>`.
    Só o nome do arquivo, não o caminho: o `source:` do cabeçalho da fase já traz o caminho
    inteiro, e repeti-lo em cada um dos 201 bullets do inspired custava 16 KB da vista."""
    out, disc_count, in_disc = [], 0, False
    for ln in block.splitlines():
        s = ln.rstrip()
        if s.startswith("### "):
            if in_disc:
                out.append(f"- ({disc_count} discretion item(s) — see source)")
            in_disc = bool(re.match(r"^### Claude.s Discretion", s))
            disc_count = 0
            out.append("#" + s)
            continue
        if s.startswith("## "):
            continue
        if in_disc:
            if re.match(r"^\s*-\s+\S", s):
                disc_count += 1
            continue
        m = re.match(r"^\s*-\s+\*\*(D-[A-Za-z0-9_-]+)", s)
        if m:
            b = s.strip()
            if linha_max and len(b) > linha_max:
                b = b[:linha_max].rstrip() + "…"
            if linha_max:
                b += f" → {os.path.basename(rel)}#{m.group(1)}"
            out.append(b)
    if in_disc:
        out.append(f"- ({disc_count} discretion item(s) — see source)")
    return "\n".join(out)


def compact_specifics(block):
    seen, out = set(), []
    for ln in block.splitlines():
        s = ln.strip()
        if not s or s.startswith("## "):
            continue
        key = re.sub(r"\W+", "", s.lower())
        if key in seen:
            continue
        seen.add(key)
        out.append(s if s.startswith("-") else f"- {s}")
    return "\n".join(out)


def strip_heading(block):
    out = []
    for ln in block.splitlines():
        if re.match(r"^## ", ln):
            continue
        out.append("#" + ln if ln.startswith("### ") else ln)   # areas nest under "### Decisions"
    return "\n".join(out).strip("\n")


def render_phase(p, compact, linha_max=0):
    head = f"## Phase {p['label']} — {p['name']}   (source: {p['rel']})"
    dec = compact_decisions(p["decisions"], linha_max, p["rel"]) if compact else strip_heading(p["decisions"])
    spe = compact_specifics(p["specifics"]) if compact else strip_heading(p["specifics"])
    parts = [head, "### Decisions", dec or "(none)"]
    if spe.strip() and not re.match(r"^(No specific requirements|Nenhum)", spe.strip(), re.I):
        parts += ["### Specifics", spe]
    return "\n".join(parts) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("planning")
    ap.add_argument("--last", type=int, default=0)
    ap.add_argument("--out")
    ap.add_argument("--soft-limit-kb", type=int, default=60)
    ap.add_argument("--recent", type=int, default=12)
    ap.add_argument("--vista", action="store_true", help="visão recortada (nunca sobrescreve o índice canônico)")
    ap.add_argument("--linha-max", type=int, default=160)
    a = ap.parse_args()
    planning = a.planning.rstrip("/")
    phases_dir = os.path.join(planning, "phases")
    canon = os.path.join(planning, "DECISIONS-INDEX.md")
    if a.vista and (not a.out or os.path.realpath(a.out) == os.path.realpath(canon)):
        log("--vista requires --out and it cannot be the canonical DECISIONS-INDEX.md")
        return 2
    out_path = a.out or canon
    if not os.path.isdir(phases_dir):
        log(f"no phases dir at {phases_dir} — nothing to index")
        return 0

    parsed, unparsed = [], []
    for d in sorted(os.listdir(phases_dir)):
        full = os.path.join(phases_dir, d)
        if not os.path.isdir(full) or d.startswith("999."):
            continue
        ctxs = [f for f in sorted(os.listdir(full)) if f.endswith("-CONTEXT.md") and f != "BACKLOG-CONTEXT.md"]
        if not ctxs:
            continue
        key = phase_key(d)
        for f in ctxs:
            path = os.path.join(full, f)
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            m = PHASE_TOKEN.match(d)
            label = (m.group(1) + (m.group(2) or "") + m.group(3)) if m else d
            entry = {"dir": d, "rel": os.path.relpath(path, os.path.dirname(planning) or "."),
                     "label": label, "name": phase_name(text, d),
                     "decisions": extract_block(text, "decisions"), "specifics": extract_block(text, "specifics")}
            if key is None:
                log(f"unparsed phase dir: {d} (appended at the end)")
                unparsed.append(entry)
            else:
                parsed.append((key, entry))
    parsed.sort(key=lambda kv: kv[0])
    phases = [e for _, e in parsed] + sorted(unparsed, key=lambda e: e["dir"])
    if a.last and len(phases) > a.last:
        phases = phases[-a.last:]
    if not phases:
        log("no CONTEXT.md found — index not created")
        return 0

    def build(compact_older):
        n = len(phases)
        body = []
        for i, p in enumerate(phases):
            compact = compact_older and i < n - a.recent
            body.append(render_phase(p, compact, a.linha_max if a.vista else 0))
        if a.vista:
            header = [f"<!-- vista recortada — texto completo em {os.path.relpath(canon, os.path.dirname(planning) or '.')}; "
                      f"{n} CONTEXT.md file(s); {max(0, n - a.recent)} older phase(s) compacted, bullets cut at {a.linha_max} chars -->", ""]
        else:
            header = ["# Decisions Index (generated — do not edit)",
                      f"<!-- generated by bin/nosso/decisions-index.py; source: {n} CONTEXT.md file(s); "
                      f"older phases {'compacted' if compact_older else 'complete'} -->", ""]
        return "\n".join(header) + "\n".join(body)

    limit = a.soft_limit_kb * 1024
    if a.vista:
        text = build(True)    # incondicional: a vista existe para caber na janela
    else:
        text = build(False)
    if not a.vista and len(text.encode()) > limit:
        text = build(True)
        older = max(0, len(phases) - a.recent)
        log(f"compacted {older} older phase(s) (soft limit {a.soft_limit_kb} KB)")
        if len(text.encode()) > limit:
            log(f"size {len(text.encode()) // 1024} KB exceeds soft limit — kept complete (never digested)")
    if os.path.isfile(out_path):
        with open(out_path, encoding="utf-8") as fh:
            if fh.read() == text:
                log(f"unchanged: {out_path}")
                return 0
    tmp = out_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, out_path)
    log(f"wrote {out_path} ({len(text.encode()) // 1024} KB, {len(phases)} phase(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
