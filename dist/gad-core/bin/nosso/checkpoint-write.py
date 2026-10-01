#!/usr/bin/env python3
"""checkpoint-write.py — writer determinístico do NN-DISCUSS-CHECKPOINT.json (gad-discuss-phase, fork).

Protocolo: escalares por argumento, texto livre por ARQUIVO (o modelo grava com `Write`,
sem escaping) — nunca heredoc, nunca stdin, nunca delimitador. Os arquivos consumidos são
apagados. Escrita atômica (tmp + os.replace). Sem dependências fora da stdlib.

Operações:
  init <ckpt> --phase NN --phase-name "…" [--goal-file F] [--spec PATH] [--req-ids "R1 R2"]
       [--area "A" …] [--ref "path|topic|note" …] [--refs-file F] [--code-context-file F]
       [--discretion-file F] [--scope-in-file F] [--scope-out-file F] [--date YYYY-MM-DD]
  add-decision <ckpt> --area "Área" [--id D-01] --origin owner|pre-spec|auto|prior-phase|todo
       [--anchor R2|R4,R5|SC1|none] [--evidence "path:line"] [--reversibility reversible|costly|one-way]
       (âncora de R/SC: a forma hifenada `R-2`/`SC-1` é ACEITA na entrada — em `--area`,
        `--anchor`, `--batch` e `map-pre-spec` — e gravada NORMALIZADA como `R2`/`SC1`;
        ids do REQUIREMENTS como `DESC-01` ficam como estão. Ver `normaliza_anchor`.
        Uma decisão pode cobrir N âncoras: `--anchor R4,R5` (lista por vírgula; no `--batch`,
        string com vírgulas ou lista JSON). O checkpoint grava `anchors: [...]` e `anchor`
        = a primeira, para quem só lê o escalar. Motivo: uma área declarada `A|R4,R5`
        decidida numa decisão só deixava R5 sem decisão que a citasse (caso 24.4, P09).)
       [--reversibility-rationale-file F] [--question-file F] --answer-file F
       [--prose-file F] [--nota-file F] [--option-file F …] [--chosen-option N | --chosen-label "texto"]
       (nota = sugestão de implementação; não é a decisão e não é cobrada — o renderer a põe
        em "Implementation Notes"; no --batch, `nota`/`nota_file`. `superada: "c<N>"` marca
        decisão que o ciclo N tornou falsa: o renderer emite `superada-c<N>, informational`.)
       (--chosen-option é 0-indexado: a 1ª opção é 0; --chosen-label casa exato e, senão,
        por prefixo único, ambos case-insensitive — os dois juntos = erro)
  complete-area <ckpt> --area "Área"
  set <ckpt> --field <campo> --file F [--append]
       campos-lista: discretion, deferred_ideas, specifics, folded_todos, reviewed_todos,
                     spec_scope_in, spec_scope_out, areas_remaining
       campos-texto: domain, phase_name
       code_context: arquivo com seções "## reusable", "## patterns", "## integration" (bullets)
       canonical_refs: linhas "path|topic|note"
  show <ckpt>            (resumo: áreas, nº de decisões, ids)

Saída: 1 linha JSON de confirmação em stdout; erros em stderr com exit 2.
"""
import argparse
import datetime as _dt
import json
import os
import re
import sys
import tempfile

LIST_FIELDS = {"discretion", "deferred_ideas", "specifics", "folded_todos", "reviewed_todos",
               "spec_scope_in", "spec_scope_out", "areas_remaining"}
TEXT_FIELDS = {"domain", "phase_name"}
ORIGINS = {"owner", "pre-spec", "auto", "prior-phase", "todo"}
REVERSIBILITY = {"reversible", "costly", "one-way"}
ID_RE = re.compile(r"^D-\d{2,}$")
SOURCE_ID_RE = re.compile(r"^PS-\d\d$")
# Mesmo alvo do `confere-pre-spec.sh` (R-n, SC-n, id do REQUIREMENTS como DESC-01, ou none).
ANCHOR_RE = re.compile(r"^(?:[A-Z]{1,8}-?\d+|none)$")
RSC_HYPHEN_RE = re.compile(r"^(R|SC)-(\d+)$")


def normaliza_anchor(a):
    """`R-2` → `R2`, `SC-1` → `SC1`. Todo o resto (inclusive `DESC-01`) sai intacto.

    A forma canônica da âncora no mundo do discuss é SEM hífen: `discuss-init.sh` só aceita
    `^R[0-9]+$` em REQ_IDS, `templates/spec.md` grava `"id": "R1"` e as áreas chegam como
    `--area "Nome|R2,R3"`. O PRE-SPEC da /go-and-do, porém, pode trazer `R-2`/`SC-1`. Sem
    normalizar em TODA porta de entrada de âncora, o `map-pre-spec` compararia `R-2` com
    `R2` e nunca casaria. Normalizando aqui, o checkpoint nunca guarda forma hifenada de
    R/SC — os consumidores a jusante comparam sempre no mesmo dialeto.
    Regra: validar no BRUTO (a mensagem de erro cita o que o chamador escreveu), gravar no
    canônico. Ids do REQUIREMENTS não são tocados: neles o hífen faz parte do id.
    """
    return RSC_HYPHEN_RE.sub(r"\1\2", a) if isinstance(a, str) else a


def parse_anchor_list(raw, where):
    """`"R4,R5"` / `["R-4","R5"]` / `"none"` / None → lista normalizada, sem repetição.
    Valida cada uma no BRUTO com ANCHOR_RE; `none` só sobrevive sozinho (`R4,none` = `R4`)."""
    if raw is None:
        return []
    items = raw if isinstance(raw, list) else str(raw).split(",")
    out = []
    for a in items:
        if not isinstance(a, str):
            die(f"{where}: anchor {a!r} must be a string — nothing was written")
        a = a.strip()
        if not a:
            continue
        if not ANCHOR_RE.match(a):
            die(f"{where}: anchor {a!r} is not R-n / SC-n / a REQUIREMENTS id / none — nothing was written")
        a = normaliza_anchor(a)
        if a != "none" and a not in out:
            out.append(a)
    return out


def die(msg, code=2):
    sys.stderr.write(f"[checkpoint-write] ERROR: {msg}\n")
    sys.exit(code)


def read_text(path, required=False):
    if not path:
        if required:
            die("required file argument missing")
        return None
    if not os.path.isfile(path):
        if required:
            die(f"file not found: {path}")
        return None
    with open(path, encoding="utf-8") as f:
        return f.read().rstrip("\n")


def read_lines(path):
    txt = read_text(path)
    if txt is None:
        return None
    out = []
    for ln in txt.splitlines():
        s = ln.strip()
        if not s:
            continue
        s = re.sub(r"^[-*•]\s+", "", s)
        out.append(s)
    return out


def consume(paths):
    for p in paths:
        if p and os.path.isfile(p):
            try:
                os.remove(p)
            except OSError:
                pass


def parse_area_spec(spec):
    """`"Nome|R2,R3"` → {"name": "Nome", "anchors": ["R2", "R3"], ...}. Sem `|` = sem anchors."""
    name, _, raw = str(spec).partition("|")
    name = name.strip()
    if not name:
        die(f"--area {spec!r} has an empty name (expected \"<nome>|<anchor1>[,anchor2]\")")
    anchors = []
    for a in raw.split(","):
        a = a.strip()
        if not a:
            continue
        if not ANCHOR_RE.match(a):
            die(f"--area {spec!r}: anchor {a!r} is not R-n / SC-n / a REQUIREMENTS id / none")
        a = normaliza_anchor(a)          # dedup DEPOIS: "R-1,R1" colapsa em um só
        if a != "none" and a not in anchors:
            anchors.append(a)
    return {"name": name, "anchors": anchors, "anchors_remaining": list(anchors)}


def areas_of(data):
    """`areas` canônico, promovendo checkpoint antigo (areas_remaining = lista de strings)."""
    areas = data.get("areas")
    if isinstance(areas, list) and all(isinstance(a, dict) for a in areas):
        for a in areas:
            a.setdefault("name", "")
            a.setdefault("anchors", [])
            a.setdefault("anchors_remaining", list(a["anchors"]))
        return areas
    promoted = []
    for name in (list(data.get("areas_completed") or []) + list(data.get("areas_remaining") or [])
                 + list((data.get("decisions") or {}).keys())):
        if isinstance(name, str) and name and name not in [a["name"] for a in promoted]:
            promoted.append({"name": name, "anchors": [], "anchors_remaining": []})
    data["areas"] = promoted
    return promoted


def area_named(data, name):
    for a in areas_of(data):
        if a["name"] == name:
            return a
    return None


def ensure_area(data, name, anchors=None):
    a = area_named(data, name)
    if a is None:
        a = {"name": name, "anchors": list(anchors or []), "anchors_remaining": list(anchors or [])}
        areas_of(data).append(a)
    return a


def sync_areas(data):
    """`areas` manda; `areas_remaining`/`areas_completed` são derivados. Chamar antes de todo save."""
    areas = areas_of(data)
    done = [n for n in (data.get("areas_completed") or []) if isinstance(n, str)]
    known = [a["name"] for a in areas]
    data["areas_completed"] = [n for n in done if n in known]
    data["areas_remaining"] = [n for n in known if n not in data["areas_completed"]]
    return data


def load(ckpt, must_exist=True):
    if not os.path.isfile(ckpt):
        if must_exist:
            die(f"checkpoint not found: {ckpt} (run `init` first)")
        return None
    try:
        with open(ckpt, encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        die(f"checkpoint is not valid JSON ({e}) — refusing to overwrite; move it aside and re-init")


def save(ckpt, data):
    sync_areas(data)
    data["timestamp"] = _dt.datetime.now().astimezone().isoformat(timespec="seconds")
    d = os.path.dirname(os.path.abspath(ckpt)) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".ckpt-", suffix=".json", dir=d)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, ckpt)


def parse_refs(lines):
    refs = []
    for ln in lines or []:
        parts = [p.strip() for p in ln.split("|", 2)]
        while len(parts) < 3:
            parts.append("")
        path, topic, note = parts
        if not path:
            continue
        refs.append({"path": path, "topic": topic or "References", "note": note})
    return refs


def parse_code_context(text):
    cc = {"reusable": [], "patterns": [], "integration": []}
    if not text:
        return cc
    cur = None
    for ln in text.splitlines():
        s = ln.strip()
        if not s:
            continue
        m = re.match(r"^#+\s*(reusable|patterns|integration)\b", s, re.I)
        if m:
            cur = m.group(1).lower()
            continue
        if cur:
            cc[cur].append(re.sub(r"^[-*•]\s+", "", s))
    return cc


def all_ids(data):
    ids = []
    for lst in data.get("decisions", {}).values():
        ids += [d.get("id") for d in lst if d.get("id")]
    return ids


def next_id(data):
    nums = [int(i[2:]) for i in all_ids(data) if ID_RE.match(i or "")]
    return f"D-{(max(nums) + 1) if nums else 1:02d}"


def resolve_chosen(options, chosen_option, chosen_label):
    """Devolve o índice 0-based escolhido (ou None). Não grava nada: só valida."""
    if chosen_option is not None and chosen_label is not None:
        die("--chosen-option and --chosen-label are mutually exclusive — pass only one")
    if chosen_option is not None:
        if not options:
            die(f"--chosen-option {chosen_option} given but no --option-file was provided "
                "(nothing to choose from)")
        if chosen_option < 0 or chosen_option >= len(options):
            die(f"--chosen-option {chosen_option} out of range: {len(options)} option(s) given, "
                f"valid range is 0..{len(options) - 1} (0-indexed: the 1st option is 0)")
        return chosen_option
    if chosen_label is not None:
        key = chosen_label.strip().casefold()
        if not key:
            die("--chosen-label is empty")
        if not options:
            die(f"--chosen-label {chosen_label!r} given but no --option-file was provided "
                "(nothing to choose from)")
        norm = [o.strip().casefold() for o in options]
        cand = "; ".join(f"[{i}] {o}" for i, o in enumerate(options))
        exact = [i for i, o in enumerate(norm) if o == key]
        if len(exact) == 1:
            return exact[0]
        if len(exact) > 1:
            die(f"--chosen-label {chosen_label!r} is ambiguous: exact match on indexes {exact} "
                f"— options: {cand}")
        pref = [i for i, o in enumerate(norm) if o.startswith(key)]
        if len(pref) == 1:
            return pref[0]
        if len(pref) > 1:
            die(f"--chosen-label {chosen_label!r} is an ambiguous prefix of indexes {pref} "
                f"— options: {cand}")
        die(f"--chosen-label {chosen_label!r} matches no option — options: {cand}")
    return None


def op_init(a):
    if os.path.isfile(a.ckpt) and not a.force:
        data = load(a.ckpt)
        print(json.dumps({"ok": True, "op": "init", "existing": True, "decisions": len(all_ids(data))}))
        return
    refs = parse_refs((read_lines(a.refs_file) or []) + list(a.ref or []))
    areas = []
    for spec in (a.area or []):
        ar = parse_area_spec(spec)
        if ar["name"] in [x["name"] for x in areas]:
            die(f"--area {ar['name']!r} declared twice")
        areas.append(ar)
    data = {
        "phase": a.phase, "phase_name": a.phase_name or "", "date": a.date or _dt.date.today().isoformat(),
        "timestamp": "", "areas": areas, "areas_completed": [], "areas_remaining": [x["name"] for x in areas],
        "domain": read_text(a.goal_file) or "",
        "spec_loaded": bool(a.spec), "spec_path": a.spec or "",
        "req_ids": (a.req_ids or "").split(), "req_count": len((a.req_ids or "").split()),
        "spec_scope_in": read_lines(a.scope_in_file) or [], "spec_scope_out": read_lines(a.scope_out_file) or [],
        "decisions": {}, "discretion": read_lines(a.discretion_file) or [],
        "folded_todos": [], "reviewed_todos": [], "deferred_ideas": [],
        "canonical_refs": refs, "specifics": [],
        "code_context": parse_code_context(read_text(a.code_context_file)),
    }
    save(a.ckpt, data)
    consume([a.goal_file, a.refs_file, a.code_context_file, a.discretion_file, a.scope_in_file, a.scope_out_file])
    print(json.dumps({"ok": True, "op": "init", "ckpt": a.ckpt, "areas": data["areas_remaining"],
                      "anchors": {x["name"]: x["anchors"] for x in areas},
                      "spec_loaded": data["spec_loaded"], "req_count": data["req_count"]}))


def op_add(a):
    if a.batch:
        # `is not None`, não truthiness: `--chosen-option 0` é falsy e passaria batido,
        # sendo ignorado em silêncio — exatamente o erro que este writer não pode cometer.
        for flag, val in (("--area", a.area), ("--origin", a.origin), ("--answer-file", a.answer_file),
                          ("--id", a.id), ("--anchor", a.anchor), ("--evidence", a.evidence),
                          ("--reversibility", a.reversibility),
                          ("--reversibility-rationale-file", a.reversibility_rationale_file),
                          ("--question-file", a.question_file), ("--prose-file", a.prose_file),
                          ("--nota-file", a.nota_file),
                          ("--option-file", a.option_file), ("--chosen-option", a.chosen_option),
                          ("--chosen-label", a.chosen_label)):
            if val is not None:
                die(f"{flag} cannot be combined with --batch (every field travels inside the JSON)")
        return op_batch(a)
    for flag, val in (("--area", a.area), ("--origin", a.origin), ("--answer-file", a.answer_file)):
        if not val:
            die(f"{flag} is required (or pass --batch <arquivo.json>)")
    data = load(a.ckpt)
    if a.origin not in ORIGINS:
        die(f"--origin must be one of {sorted(ORIGINS)}")
    if a.reversibility and a.reversibility not in REVERSIBILITY:
        die(f"--reversibility must be one of {sorted(REVERSIBILITY)}")
    rationale = read_text(a.reversibility_rationale_file)
    if a.reversibility in {"costly", "one-way"} and not rationale:
        die("--reversibility costly|one-way requires --reversibility-rationale-file (templates/context.md:56-68)")
    nota = read_text(a.nota_file) or ""
    did = a.id or next_id(data)
    if not ID_RE.match(did):
        die(f"--id must look like D-01 (got {did})")
    if did in all_ids(data):
        die(f"decision {did} already exists — ids are never reused or renumbered")
    answer = read_text(a.answer_file, required=True)
    if not answer.strip():
        die("answer file is empty")
    anchors = parse_anchor_list(a.anchor, "--anchor")
    anchor = anchors[0] if anchors else "none"
    reqs = data.get("req_ids") or []
    for an in anchors:
        if reqs and an not in reqs and not re.match(r"^SC\d+$", an):
            sys.stderr.write(f"[checkpoint-write] WARN: anchor {an} not in req_ids {reqs} (orphan anchor)\n")
    options = [read_text(p, required=True) for p in (a.option_file or [])]
    chosen = resolve_chosen(options, a.chosen_option, a.chosen_label)
    dec = {
        "id": did, "question": read_text(a.question_file) or "", "options_presented": options,
        "chosen_option": chosen,
        "answer": answer, "evidence": a.evidence or "none", "reversibility": a.reversibility or None,
        "reversibility_rationale": rationale or "", "anchor": anchor, "anchors": anchors,
        "origin": a.origin, "prose": read_text(a.prose_file) or "",
    }
    if nota.strip():
        dec["nota"] = nota
    data.setdefault("decisions", {}).setdefault(a.area, []).append(dec)
    ensure_area(data, a.area)
    save(a.ckpt, data)
    consume([a.answer_file, a.question_file, a.prose_file, a.nota_file, a.reversibility_rationale_file] + list(a.option_file or []))
    print(json.dumps({"ok": True, "op": "add-decision", "id": did, "area": a.area, "anchor": anchor,
                      "anchors": anchors, "origin": a.origin, "total": len(all_ids(data))}))


def close_area(data, name):
    """Fecha a área (idempotente). Só `areas_completed` muda; `sync_areas` deriva o resto."""
    if name not in data.setdefault("areas_completed", []):
        data["areas_completed"].append(name)


# ---------------------------------------------------------------- lote (D3) --
BATCH_TEXT = ("question", "answer", "prose", "reversibility_rationale", "nota")
BATCH_KEYS = (set(BATCH_TEXT) | {k + "_file" for k in BATCH_TEXT}
              | {"area", "id", "origin", "anchor", "evidence", "reversibility", "options",
                 "option_files", "chosen_option", "chosen_label", "complete_area",
                 "source_id", "kind", "superada"})
SUPERADA_RE = re.compile(r"^c\d+$")


def load_batch(path):
    if not os.path.isfile(path):
        die(f"batch file not found: {path}")
    try:
        with open(path, encoding="utf-8") as f:
            arr = json.load(f)
    except json.JSONDecodeError as e:
        die(f"batch {path} is not valid JSON ({e}) — nothing was written")
    if not isinstance(arr, list) or not arr:
        die(f"batch {path} must be a non-empty JSON array of objects — nothing was written")
    for i, e in enumerate(arr):
        if not isinstance(e, dict):
            die(f"batch[{i}] is not an object — nothing was written")
    return arr


def _text_field(e, key, where):
    """Valor de texto vindo do literal `key` ou do arquivo `key_file`. Devolve (texto, arquivo)."""
    fkey = key + "_file"
    if e.get(key) is not None and e.get(fkey) is not None:
        die(f"{where}: {key!r} and {fkey!r} are mutually exclusive — nothing was written")
    if e.get(key) is not None:
        v = e[key]
        if not isinstance(v, str):
            die(f"{where}: {key!r} must be a string — nothing was written")
        return v.rstrip("\n"), None
    f = e.get(fkey)
    if f is not None:
        if not isinstance(f, str) or not os.path.isfile(f):
            die(f"{where}: {fkey} file not found: {f!r} — nothing was written")
        return read_text(f, required=True), f
    return None, None


def build_decision(data, e, used_ids, where):
    """Valida UMA entrada e devolve (area, dec, complete_area, arquivos_a_consumir).
    Não grava e não muta o checkpoint — a gravação é do chamador, num `save` só."""
    desconhecidas = sorted(set(e) - BATCH_KEYS)
    if desconhecidas:
        die(f"{where}: unknown field(s) {desconhecidas} — nothing was written")
    area = e.get("area")
    if not isinstance(area, str) or not area.strip():
        die(f"{where}: 'area' is required and must be a non-empty string — nothing was written")
    origin = e.get("origin")
    if origin not in ORIGINS:
        die(f"{where}: 'origin' must be one of {sorted(ORIGINS)} (got {origin!r}) — nothing was written")
    rev = e.get("reversibility")
    if rev is not None and rev not in REVERSIBILITY:
        die(f"{where}: 'reversibility' must be one of {sorted(REVERSIBILITY)} — nothing was written")
    files = []
    question, f = _text_field(e, "question", where); files += [f] if f else []
    answer, f = _text_field(e, "answer", where); files += [f] if f else []
    prose, f = _text_field(e, "prose", where); files += [f] if f else []
    rationale, f = _text_field(e, "reversibility_rationale", where); files += [f] if f else []
    nota, f = _text_field(e, "nota", where); files += [f] if f else []
    if answer is None or not answer.strip():
        die(f"{where}: 'answer' (or 'answer_file') is required and must be non-empty — nothing was written")
    if rev in {"costly", "one-way"} and not (rationale or "").strip():
        die(f"{where}: reversibility {rev!r} requires 'reversibility_rationale' — nothing was written")
    did = e.get("id")
    if did is None:
        did = alloc_id(data, used_ids)
    if not isinstance(did, str) or not ID_RE.match(did):
        die(f"{where}: 'id' must look like D-01 (got {did!r}) — nothing was written")
    if did in used_ids:
        die(f"{where}: decision {did} already exists (or repeats in this batch) — "
            "ids are never reused or renumbered; nothing was written")
    used_ids.add(did)
    anchors = parse_anchor_list(e.get("anchor"), where)    # valida no bruto, grava no canônico
    anchor = anchors[0] if anchors else "none"
    options = e.get("options")
    ofiles = e.get("option_files")
    if options is not None and ofiles is not None:
        die(f"{where}: 'options' and 'option_files' are mutually exclusive — nothing was written")
    if options is not None:
        if not isinstance(options, list) or any(not isinstance(o, str) for o in options):
            die(f"{where}: 'options' must be a list of strings — nothing was written")
    elif ofiles is not None:
        if not isinstance(ofiles, list) or any(not isinstance(o, str) for o in ofiles):
            die(f"{where}: 'option_files' must be a list of paths — nothing was written")
        for o in ofiles:
            if not os.path.isfile(o):
                die(f"{where}: option file not found: {o!r} — nothing was written")
        options = [read_text(o, required=True) for o in ofiles]
        files += list(ofiles)
    else:
        options = []
    chosen = resolve_chosen(options, e.get("chosen_option"), e.get("chosen_label"))
    ca = e.get("complete_area", False)
    if not isinstance(ca, bool):
        die(f"{where}: 'complete_area' must be a boolean — nothing was written")
    dec = {
        "id": did, "question": question or "", "options_presented": options,
        "chosen_option": chosen, "answer": answer,
        "evidence": e.get("evidence") or "none", "reversibility": rev,
        "reversibility_rationale": rationale or "", "anchor": anchor, "anchors": anchors,
        "origin": origin, "prose": prose or "",
    }
    sid = e.get("source_id")
    if sid is not None:
        if not isinstance(sid, str) or not SOURCE_ID_RE.match(sid):
            die(f"{where}: 'source_id' must look like PS-01 (got {sid!r}) — nothing was written")
        dec["source_id"] = sid
    if (nota or "").strip():
        dec["nota"] = nota
    sup = e.get("superada")
    if sup is not None:
        if not isinstance(sup, str) or not SUPERADA_RE.match(sup):
            die(f"{where}: 'superada' must look like c1 (the cycle that outdated it) — nothing was written")
        dec["superada"] = sup
    return area, dec, ca, files


def alloc_id(data, used_ids):
    nums = [int(i[2:]) for i in used_ids if ID_RE.match(i or "")]
    return f"D-{(max(nums) + 1) if nums else 1:02d}"


def op_batch(a):
    """add-decision --batch: valida TUDO antes de gravar; ids na ordem; um `save` só."""
    data = load(a.ckpt)
    entradas = load_batch(a.batch)
    used = set(all_ids(data))
    plano, arquivos = [], []
    for i, e in enumerate(entradas):
        where = f"batch[{i}]"
        # filtro estrito: decisão do PRE-SPEC só entra por `map-pre-spec`
        if e.get("origin") == "pre-spec" or e.get("source_id") is not None:
            die(f"{where}: PRE-SPEC entries (origin 'pre-spec' / 'source_id') never go through "
                "--batch — use `map-pre-spec`, the single owner of those; nothing was written")
        plano.append(build_decision(data, e, used, where))
        arquivos += plano[-1][3]
    for area, dec, ca, _ in plano:
        data.setdefault("decisions", {}).setdefault(area, []).append(dec)
        ensure_area(data, area)
        if ca:
            close_area(data, area)
    save(a.ckpt, data)
    consume(arquivos)
    print(json.dumps({"ok": True, "op": "add-decision", "batch": a.batch,
                      "added": [d["id"] for _, d, _, _ in plano],
                      "areas_completed": data["areas_completed"],
                      "areas_remaining": data["areas_remaining"],
                      "total": len(all_ids(data))}, ensure_ascii=False))


# ------------------------------------------------------- map-pre-spec (§0.5) --
def op_map_pre_spec(a):
    """Único dono das entradas do PRE-SPEC. Casa pelo `anchor` contra a estrutura `areas`."""
    data = load(a.ckpt)
    entradas = load_batch(a.batch)
    areas = areas_of(data)
    used = set(all_ids(data))
    plano, arquivos = [], []
    for i, e in enumerate(entradas):
        where = f"{os.path.basename(a.batch)}[{i}]"
        kind = e.get("kind")
        if kind is None:
            die(f"{where}: 'kind' is required in a PRE-SPEC batch — nothing was written")
        if kind != "decisao_dono":
            die(f"{where}: map-pre-spec only accepts kind 'decisao_dono' (got {kind!r}); "
                "'fato_medido' never becomes a decision — nothing was written")
        sid = e.get("source_id")
        if not isinstance(sid, str) or not SOURCE_ID_RE.match(sid or ""):
            die(f"{where}: 'source_id' (PS-nn) is required in a PRE-SPEC batch — nothing was written")
        ent = dict(e); ent.pop("kind", None)
        ent["origin"] = "pre-spec"
        if ent.get("complete_area"):
            die(f"{where}: 'complete_area' is not accepted here — map-pre-spec owns the closing "
                "rule (an area closes only when its anchors_remaining empties); nothing was written")
        area_ps, dec, _, files = build_decision(data, ent, used, where)
        anchor = dec["anchor"]
        casadas = [x for x in areas if anchor != "none" and anchor in x["anchors_remaining"]]
        plano.append((sid, area_ps, dec, anchor, casadas))
        arquivos += files

    resultado = []
    for sid, area_ps, dec, anchor, casadas in plano:
        if len(casadas) == 1:
            alvo = casadas[0]
            alvo["anchors_remaining"] = [x for x in alvo["anchors_remaining"] if x != anchor]
            data.setdefault("decisions", {}).setdefault(alvo["name"], []).append(dec)
            fechou = not alvo["anchors_remaining"]
            if fechou:
                close_area(data, alvo["name"])
            resultado.append({"source_id": sid, "id": dec["id"], "rota": "casou",
                              "area": alvo["name"], "anchor": anchor,
                              "anchors_remaining": alvo["anchors_remaining"], "fechou": fechou})
        elif len(casadas) == 0:
            nome = f"PS-{sid[3:]} — {area_ps}" if sid.startswith("PS-") else f"{sid} — {area_ps}"
            ensure_area(data, nome)
            data.setdefault("decisions", {}).setdefault(nome, []).append(dec)
            close_area(data, nome)
            resultado.append({"source_id": sid, "id": dec["id"],
                              "rota": "area_dedicada" if anchor != "none" else "anchor_none",
                              "area": nome, "anchor": anchor, "anchors_remaining": [], "fechou": True})
        else:
            # ≥ 2: a PRIMÁRIA é a 1ª na ordem de declaração de `init --area`.
            primaria = casadas[0]
            data.setdefault("decisions", {}).setdefault(primaria["name"], []).append(dec)
            for x in casadas:
                x["anchors_remaining"] = [y for y in x["anchors_remaining"] if y != anchor]
            # NENHUMA área fecha neste ramo, nem a que esvaziou: o casamento múltiplo é um
            # SINO (§0.5) — a PS não identifica sozinha a área dona, e fechar aqui esconderia
            # do coordenador a ambiguidade que ele tem de resolver. Fechar é do
            # `complete-area`, depois da decisão humana. (Fixture do plano: primária `R2,R3`
            # + secundária `R2` + uma PS `R2` → as DUAS abertas, com R3 e — .)
            fechadas = []
            resultado.append({"source_id": sid, "id": dec["id"], "rota": "sino_multiplo",
                              "area": primaria["name"],
                              "secundarias": [x["name"] for x in casadas[1:]], "anchor": anchor,
                              "anchors_remaining": {x["name"]: x["anchors_remaining"] for x in casadas},
                              "fechou": fechadas})
    save(a.ckpt, data)
    consume(arquivos)
    print(json.dumps({"ok": True, "op": "map-pre-spec", "batch": a.batch, "mapeadas": resultado,
                      "areas_completed": data["areas_completed"],
                      "areas_remaining": data["areas_remaining"],
                      "total": len(all_ids(data))}, ensure_ascii=False))


def op_complete(a):
    data = load(a.ckpt)
    known = [x["name"] for x in areas_of(data)]
    if a.area not in known:
        die(f"area {a.area!r} does not exist in this checkpoint — known areas: "
            f"{sorted(set(known)) or '(none)'}")
    close_area(data, a.area)
    save(a.ckpt, data)
    print(json.dumps({"ok": True, "op": "complete-area", "area": a.area,
                      "completed": data["areas_completed"], "remaining": data["areas_remaining"]}))


def op_set(a):
    data = load(a.ckpt)
    f = a.field
    if f in LIST_FIELDS:
        vals = read_lines(a.file)
        if vals is None:
            die(f"file not found: {a.file}")
        data[f] = (data.get(f, []) + vals) if a.append else vals
        if f == "areas_remaining":
            # `areas` é canônico: reconstruir a partir da lista dada, preservando os anchors
            # já conhecidos; nome novo entra sem anchors. Nunca deixa os dois dessincronizados.
            atuais = {x["name"]: x for x in areas_of(data)}
            done = [n for n in (data.get("areas_completed") or []) if n in atuais]
            novas = [atuais.get(n) or {"name": n, "anchors": [], "anchors_remaining": []}
                     for n in done + [v for v in data[f] if v not in done]]
            data["areas"] = novas
    elif f in TEXT_FIELDS:
        data[f] = read_text(a.file, required=True)
    elif f == "code_context":
        data[f] = parse_code_context(read_text(a.file, required=True))
    elif f == "canonical_refs":
        refs = parse_refs(read_lines(a.file) or [])
        if a.append:
            seen = {r["path"] for r in data.get("canonical_refs", [])}
            data["canonical_refs"] = data.get("canonical_refs", []) + [r for r in refs if r["path"] not in seen]
        else:
            data["canonical_refs"] = refs
    else:
        die(f"unknown field {f}")
    save(a.ckpt, data)
    consume([a.file])
    v = data[f]
    print(json.dumps({"ok": True, "op": "set", "field": f, "size": len(v) if isinstance(v, (list, dict)) else len(str(v))}))


def op_show(a):
    data = load(a.ckpt)
    per = {k: [d["id"] for d in v] for k, v in data.get("decisions", {}).items()}
    print(json.dumps({"phase": data.get("phase"), "areas_completed": data.get("areas_completed"),
                      "areas_remaining": data.get("areas_remaining"), "decisions": per,
                      "spec_loaded": data.get("spec_loaded"), "req_ids": data.get("req_ids")}, ensure_ascii=False))


def main():
    p = argparse.ArgumentParser(prog="checkpoint-write.py")
    sub = p.add_subparsers(dest="op", required=True)

    s = sub.add_parser("init"); s.add_argument("ckpt")
    s.add_argument("--phase", required=True); s.add_argument("--phase-name", default="")
    s.add_argument("--goal-file"); s.add_argument("--spec"); s.add_argument("--req-ids", default="")
    s.add_argument("--area", action="append"); s.add_argument("--ref", action="append")
    s.add_argument("--refs-file"); s.add_argument("--code-context-file"); s.add_argument("--discretion-file")
    s.add_argument("--scope-in-file"); s.add_argument("--scope-out-file"); s.add_argument("--date")
    s.add_argument("--force", action="store_true"); s.set_defaults(fn=op_init)

    s = sub.add_parser("add-decision"); s.add_argument("ckpt")
    s.add_argument("--area"); s.add_argument("--id"); s.add_argument("--origin")
    s.add_argument("--anchor"); s.add_argument("--evidence"); s.add_argument("--reversibility")
    s.add_argument("--reversibility-rationale-file"); s.add_argument("--question-file")
    s.add_argument("--answer-file"); s.add_argument("--prose-file"); s.add_argument("--nota-file")
    s.add_argument("--option-file", action="append"); s.add_argument("--chosen-option", type=int)
    s.add_argument("--chosen-label"); s.add_argument("--batch")
    s.set_defaults(fn=op_add)

    s = sub.add_parser("map-pre-spec"); s.add_argument("ckpt"); s.add_argument("batch")
    s.set_defaults(fn=op_map_pre_spec)

    s = sub.add_parser("complete-area"); s.add_argument("ckpt"); s.add_argument("--area", required=True)
    s.set_defaults(fn=op_complete)

    s = sub.add_parser("set"); s.add_argument("ckpt"); s.add_argument("--field", required=True)
    s.add_argument("--file", required=True); s.add_argument("--append", action="store_true")
    s.set_defaults(fn=op_set)

    s = sub.add_parser("show"); s.add_argument("ckpt"); s.set_defaults(fn=op_show)

    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
