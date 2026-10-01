#!/usr/bin/env python3
"""context-render.py — renderiza NN-CONTEXT.md a partir do NN-DISCUSS-CHECKPOINT.json (gad-discuss-phase, fork).

A moldura (tags, headings, ordem) é a de workflows/discuss-phase/templates/context.md —
byte a byte: <domain> → <spec_lock> (sse spec_loaded) → <decisions> → <canonical_refs> →
<code_context> → <specifics> → <deferred>. O modelo nunca escreve a moldura; só preenche o JSON.

Uso: context-render.py <checkpoint.json> [--out NN-CONTEXT.md] [--root DIR]
  --root: raiz do projeto para testar existência dos canonical refs (default: cwd).
Sem --out, grava em $T/context-render.out.md (quando $T existe) ou em <ckpt>.rendered.md
ao lado do checkpoint e imprime uma linha `{"out": "<caminho>", "bytes": N}`. O CONTEXT
nunca vai para o stdout: um checkpoint real rende ~50 KB, e acima de 20 KB o texto entra
inteiro na conversa a cada turno (teto de 20 KB dos scripts do fork, P18). Stdlib apenas.

Regras de neutralização de `prose` (o parser downstream, decisions.cjs, lê qualquer
`- **D-NN:**` dentro de <decisions>; o gate de cobertura bloqueia em parse-miss):
  linha começando por `#`            → prefixo `\\#`
  linha começando por `- **`/`* **`  → prefixo `·`
  fence ```                          → removido
  `</tag>` de tags conhecidas        → `&lt;/tag>`
Conteúdo se preserva; só a sintaxe que o parser lê é neutralizada.

Plano 2 (C1/C2/C3, 05/09/2026):
  · decisão de `origin: pre-spec` com `source_id` (ou `pointer: true`) sai em FORMA DE
    PONTEIRO — uma linha, tag `informational`, sem prose/options/evidence: a regra já está
    no SPEC marcada `[pre-spec:PS-nn]`, e copiá-la aqui era o que a guarda (checagem 8)
    acusa. `informational` a tira do gate de cobertura (decisions.cjs:30), que continua
    cobrando o que decide de verdade.
  · `nota` (sugestão de implementação) vai para `### Implementation Notes`, a ÚLTIMA seção
    de <decisions>: depois da Discretion, senão desligaria o modo discretion do parser; o
    parser ignora bullets que não sejam `- **D-NN` — provado 23/23 na 24.4.
  · `superada: c<N>` emite `superada-c<N>, informational` — decisão que um ciclo tornou
    falsa deixa de ser rastreável sem sumir do texto.
"""
import argparse
import json
import os
import re
import sys

KNOWN_TAGS = ("decisions", "domain", "spec_lock", "canonical_refs", "code_context",
              "specifics", "deferred", "plan", "task", "reversibility", "user_constraints")
CLOSE_RE = re.compile(r"</(" + "|".join(KNOWN_TAGS) + r")\b", re.I)
OPEN_RE = re.compile(r"<(task|plan|decisions|reversibility)\b", re.I)


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
    """Texto de 1 linha (answer/option): sem quebras, sem tags de plano."""
    s = " ".join((text or "").split())
    s = CLOSE_RE.sub(lambda m: "&lt;/" + m.group(1), s)
    s = OPEN_RE.sub(lambda m: "&lt;" + m.group(1), s)
    return s


def tags_for(d):
    """Tags do bullet: `[pre-spec:PS-nn, R-n]` · `[medido:PS-nn]` · `[auto, R2]` · `[auto, R4, R5]` · …

    A marca do PRE-SPEC carrega o `source_id` para o revisor saber que a decisão está
    TRAVADA e por quem (§0.5): ele ataca a consequência, não a decisão. O `R-n` é o
    `anchor` — omitido quando é `none`. `medido:PS-nn` é a marca do `fato_medido`, que
    NÃO trava; hoje nenhum produtor a emite no checkpoint (o filtro do
    `discuss-init.sh --pre-spec` barra `fato_medido`), a marca vive no SPEC — o
    renderer a suporta para o dia em que um `kind` desses chegar aqui.
    Conferido contra o parser real (decisions.cjs, forma colon): `pre-spec:ps-01`
    vira uma tag só, o bullet segue `parsed` e `trackable`.
    """
    t = []
    origin, sid = d.get("origin"), d.get("source_id")
    if d.get("kind") == "fato_medido":
        t.append(f"medido:{sid}" if sid else "medido")
    elif origin and origin not in ("owner",):
        t.append(f"{origin}:{sid}" if origin == "pre-spec" and sid else origin)
    # N âncoras por decisão (P09): `anchors` manda; `anchor` escalar é o fallback dos
    # checkpoints antigos. Cada uma vira um token separado por vírgula — o formato que
    # decisions.cjs já parseia (split(',')) e que a guarda lê token a token.
    anchors = d.get("anchors")
    if not isinstance(anchors, list):
        anchors = [d.get("anchor")]
    for a in anchors:
        if a and a != "none" and a not in t:
            t.append(a)
    sup = d.get("superada")
    if isinstance(sup, str) and re.match(r"^c\d+$", sup):
        t.append(f"superada-{sup}")
    if (is_pointer(d) or sup) and "informational" not in t:
        t.append("informational")
    return f" [{', '.join(t)}]" if t else ""


def is_pointer(d):
    """Decisão-ponteiro: confirma o SPEC em vez de decidir (C1). Default derivado de `origin`."""
    if d.get("pointer") is not None:
        return bool(d.get("pointer"))
    return d.get("origin") == "pre-spec" and bool(d.get("source_id")) and d.get("kind") != "fato_medido"


def resumo(text, max_words=8):
    """Primeira sentença da `answer`, no máximo `max_words` palavras — curto o bastante para
    nunca formar uma corrida de 15 palavras com o SPEC."""
    s = inline(text)
    s = re.split(r"(?<=[.!?;:])\s", s, 1)[0]
    w = s.split()
    return " ".join(w[:max_words]) + ("…" if len(w) > max_words else "")


def render_pointer(d, spec_base):
    sid = d.get("source_id") or ""
    onde = f"ver `{spec_base}`, linha `[pre-spec:{sid}]`" if sid else f"ver `{spec_base}`"
    return [f"- **{d['id']}{tags_for(d)}:** {onde} — {resumo(d.get('answer'))}"]


def render_decision(d, spec_base=""):
    if is_pointer(d):
        return render_pointer(d, spec_base)
    head = f"- **{d['id']}{tags_for(d)}:** {inline(d.get('answer'))}"
    rev = d.get("reversibility")
    if rev and rev != "reversible":
        head += f" — **Reversibility:** [{rev}] — {inline(d.get('reversibility_rationale') or '')}".rstrip(" —")
    lines = [head]
    ev = d.get("evidence")
    if ev and ev != "none":
        lines.append(f"  evidence: {inline(ev)}")
    opts = d.get("options_presented") or []
    if opts:
        chosen = d.get("chosen_option")
        rendered = []
        for i, o in enumerate(opts):
            o = inline(o)
            rendered.append(f"**{o}** (chosen)" if chosen is not None and i == chosen else o)
        lines.append("  options: " + " · ".join(rendered))
    if d.get("question"):
        lines.append(f"  question: {inline(d['question'])}")
    for pl in neutralize(d.get("prose")):
        lines.append(("  " + pl) if pl.strip() else "")
    return lines


def bullets(items, empty_line=None):
    items = [i for i in (items or []) if str(i).strip()]
    if not items:
        return [empty_line] if empty_line else []
    return ["- " + inline(i) if "\n" not in str(i) else "- " + "\n  ".join(neutralize(i)) for i in items]


def render(data, root="."):
    phase = str(data.get("phase", "")).strip()
    disp = data.get("phase_display") or (phase.lstrip("0") or phase)
    name = data.get("phase_name", "")
    date = data.get("date", "")
    padded = phase
    spec_loaded = bool(data.get("spec_loaded"))
    spec_path = data.get("spec_path", "")
    _root = os.path.realpath(root)
    if spec_path and os.path.isabs(spec_path) and os.path.realpath(spec_path).startswith(_root + os.sep):
        spec_path = os.path.relpath(os.path.realpath(spec_path), _root)
    spec_base = os.path.basename(spec_path) if spec_path else f"{padded}-SPEC.md"
    L = []
    L += [f"# Phase {disp}: {name} - Context", "", f"**Gathered:** {date}", "**Status:** Ready for planning", ""]

    # <domain>
    L += ["<domain>", "## Phase Boundary", ""]
    L += neutralize(data.get("domain") or "[Phase boundary not captured]") or [""]
    L += ["", "</domain>", ""]

    # <spec_lock>
    if spec_loaded:
        n = data.get("req_count") or len(data.get("req_ids") or [])
        L += ["<spec_lock>", "## Requirements (locked via SPEC.md)", "",
              f"**{n} requirements are locked.** See `{spec_base}` for full requirements, boundaries, and acceptance criteria.",
              "",
              f"Downstream agents MUST read `{spec_base}` before planning or implementing. Requirements are not duplicated here.",
              ""]
        sin = [i for i in data.get("spec_scope_in") or [] if str(i).strip()]
        sout = [i for i in data.get("spec_scope_out") or [] if str(i).strip()]
        L += ["**In scope (from SPEC.md):**"] + (bullets(sin) or ["- (see SPEC.md Boundaries)"])
        L += ["**Out of scope (from SPEC.md):**"] + (bullets(sout) or ["- (see SPEC.md Boundaries)"])
        L += ["", "</spec_lock>", ""]

    # <decisions>
    L += ["<decisions>", "## Implementation Decisions", ""]
    decs = data.get("decisions") or {}
    order = list(data.get("areas_completed") or []) + [a for a in decs if a not in (data.get("areas_completed") or [])]
    for area in order:
        items = decs.get(area) or []
        if not items:
            continue
        L.append(f"### {inline(area)}")
        for d in items:
            L += render_decision(d, spec_base)
        L.append("")
    L.append("### Claude's Discretion")
    L += bullets(data.get("discretion"), "[None — every decision above is locked; no open discretion]")
    L.append("")
    folded = data.get("folded_todos") or []
    if folded:
        L.append("### Folded Todos")
        L += bullets(folded)
        L.append("")
    notas = [(d["id"], d["nota"]) for area in order for d in (decs.get(area) or [])
             if str(d.get("nota") or "").strip()]
    if notas:   # sempre por último: um `###` depois da Discretion encerra o modo discretion do parser
        L.append("### Implementation Notes (sugestões — não normativas)")
        for did, nota in notas:
            L.append(f"- {did} · " + " ".join(neutralize(nota)).strip())
        L.append("")
    L += ["</decisions>", ""]

    # <canonical_refs>
    L += ["<canonical_refs>", "## Canonical References", "",
          "**Downstream agents MUST read these before planning or implementing.**", ""]
    refs = [dict(r) for r in (data.get("canonical_refs") or []) if r.get("path")]
    if spec_loaded and spec_path:
        refs = [r for r in refs if os.path.basename(r["path"]) != spec_base]
        refs.insert(0, {"path": spec_path, "topic": "Locked requirements", "note": "Locked requirements — MUST read before planning"})
    groups, seen = {}, set()
    for r in refs:
        if r["path"] in seen:
            continue
        seen.add(r["path"])
        groups.setdefault(r.get("topic") or "References", []).append(r)
    if not groups:
        L.append("No external specs — requirements fully captured in decisions above")
    for topic, items in groups.items():
        L.append(f"### {inline(topic)}")
        for r in items:
            p = r["path"]
            p_fs = p.split(" §")[0].strip("`")
            exists = p_fs.startswith("http") or os.path.exists(os.path.join(root, p_fs)) or os.path.exists(p_fs)
            line = f"- `{p}`" + (f" — {inline(r['note'])}" if r.get("note") else "")
            if not exists:
                line += " <!-- ref not found on disk -->"
            L.append(line)
        L.append("")
    L += ["</canonical_refs>", ""]

    # <code_context>
    cc = data.get("code_context") or {}
    L += ["<code_context>", "## Existing Code Insights", ""]
    L += ["### Reusable Assets"] + bullets(cc.get("reusable"), "- None identified") + [""]
    L += ["### Established Patterns"] + bullets(cc.get("patterns"), "- None identified") + [""]
    L += ["### Integration Points"] + bullets(cc.get("integration"), "- None identified") + [""]
    L += ["</code_context>", ""]

    # <specifics>
    L += ["<specifics>", "## Specific Ideas", ""]
    L += bullets(data.get("specifics"), "No specific requirements — open to standard approaches")
    L += ["", "</specifics>", ""]

    # <deferred>
    L += ["<deferred>", "## Deferred Ideas", ""]
    deferred = data.get("deferred_ideas") or []
    reviewed = data.get("reviewed_todos") or []
    L += bullets(deferred, None if reviewed else "None — discussion stayed within phase scope")
    if reviewed:
        L += ["", "### Reviewed Todos (not folded)"] + bullets(reviewed)
    L += ["", "</deferred>", "", "---", "", f"*Phase: {disp}-{name}*", f"*Context gathered: {date}*", ""]
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("--out")
    ap.add_argument("--root", default=".")
    a = ap.parse_args()
    with open(a.ckpt, encoding="utf-8") as f:
        data = json.load(f)
    md = render(data, a.root)
    out = a.out
    if not out:
        t = os.environ.get("T", "")
        out = os.path.join(t, "context-render.out.md") if t and os.path.isdir(t) else a.ckpt + ".rendered.md"
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(md)
    os.replace(tmp, out)
    n = len(md.encode())
    if a.out:
        sys.stderr.write(f"[context-render] wrote {out} ({n} bytes)\n")
    else:
        print(json.dumps({"out": out, "bytes": n}, ensure_ascii=False))


if __name__ == "__main__":
    main()
