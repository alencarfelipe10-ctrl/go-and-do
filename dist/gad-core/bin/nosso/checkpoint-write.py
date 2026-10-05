#!/usr/bin/env python3
"""checkpoint-write.py — writer determinístico do depósito da fase, NN-DISCUSS-CHECKPOINT.json
(gad-discuss-phase, fork; documento único de intenção, plano 06-13, D-12).

O depósito guarda cada resposta do DONO assim que é dada e o texto de cada seção do documento
único; o `context-render.py` monta o NN-CONTEXT.md só a partir dele. Por isso uma queda no
meio da entrevista não perde nada: rodar de novo lê o depósito (`show`) e segue do pendente.

Protocolo: escalares por argumento, texto livre por ARQUIVO (o modelo grava com `Write`,
sem escaping) — nunca heredoc, nunca stdin, nunca delimitador. Os arquivos consumidos são
apagados. Escrita atômica (tmp + os.replace). Sem dependências fora da stdlib.

Operações:
  init <ckpt> --phase NN --phase-name "…" [--area "A[|R1,R2]" …] [--date YYYY-MM-DD]
       [--goal-file F] [--spec PATH] [--req-ids "R1 R2"] [--ref "path|topic|note" …]
       [--refs-file F] [--code-context-file F] [--discretion-file F] [--scope-in-file F]
       [--scope-out-file F] [--force]
       (as flags da segunda linha em diante são do formato antigo; o fluxo do documento único
        usa só --phase, --phase-name, --area e --date)
  add-decision <ckpt> --area "Área" [--id D-01] --origin owner
       [--anchor R2|R4,R5|SC1|none] [--evidence "path:line"] [--reversibility reversible|costly|one-way]
       (âncora de R/SC: a forma hifenada `R-2`/`SC-1` é ACEITA na entrada — em `--area` e
        `--anchor` — e gravada NORMALIZADA como `R2`/`SC1`; ids do REQUIREMENTS como
        `DESC-01` ficam como estão. Ver `normaliza_anchor`. Uma decisão pode cobrir N âncoras:
        `--anchor R4,R5` (lista por vírgula). O checkpoint grava `anchors: [...]` e `anchor`
        = a primeira, para quem só lê o escalar (caso 24.4, P09).)
       [--reversibility-rationale-file F] [--question-file F] --answer-file F
       [--prose-file F] [--option-file F …] [--chosen-option N | --chosen-label "texto"]
       (--chosen-option é 0-indexado: a 1ª opção é 0; --chosen-label casa exato e, senão,
        por prefixo único, ambos case-insensitive — os dois juntos = erro)
  complete-area <ckpt> --area "Área"
  set <ckpt> --field <campo> --file F [--append]
       campos-lista: discretion, deferred_ideas, specifics, folded_todos, reviewed_todos,
                     spec_scope_in, spec_scope_out, areas_remaining
       campos-texto: domain, phase_name
       code_context: arquivo com seções "## reusable", "## patterns", "## integration" (bullets)
       canonical_refs: linhas "path|topic|note"
  set-secao <ckpt> --secao <slug> --file F
       seções do documento único: goal, situacao, requisitos, criterios, limites, proibicoes,
       bordas, regression, artefatos, limitacoes, discricao, pendencias, referencias, codigo,
       reqs_json, scope_json, acs_json. Texto livre por arquivo (consumido); os `*_json` são
       validados como JSON (chave duplicada recusada) e guardados verbatim.
  aprovar <ckpt> --sha256 <hex>
       grava `aprovado_sha256` = sha do rascunho que o dono viu e aprovou («ok»); só ele libera
       `context-render.py --promover`. Toda outra operação que muda o depósito zera a aprovação.
  show <ckpt>            (resumo: áreas feitas/pendentes, decisões por área, ids, secoes
                          preenchidas, aprovado_sha256 — é o que a retomada mostra ao dono)

Origem: só `owner` (AC-11). Qualquer outra → exit 2, nada gravado. A decisão em lote
(`--batch`), o mapeamento do PRE-SPEC e a nota de implementação (`--nota-file`, `superada`)
saíram no plano 06-13: decisão automática e PRE-SPEC não existem no fluxo do documento único.

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
# Plano 06-13 (AC-11, D-12): o depósito só guarda decisão do DONO. Qualquer outra origem → exit 2.
ORIGINS = {"owner"}
REVERSIBILITY = {"reversible", "costly", "one-way"}
ID_RE = re.compile(r"^D-\d{2,}$")
# Seções do documento único (plano 06-13): texto livre por arquivo; os `*_json` são validados
# como JSON (chave duplicada recusada) e guardados VERBATIM — o render os copia como estão.
SECOES = ("goal", "situacao", "requisitos", "criterios", "limites", "proibicoes", "bordas",
          "regression", "artefatos", "limitacoes", "discricao", "pendencias", "referencias",
          "codigo", "reqs_json", "scope_json", "acs_json")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
# Mesmo alvo do `confere-pre-spec.sh` (R-n, SC-n, id do REQUIREMENTS como DESC-01, ou none).
ANCHOR_RE = re.compile(r"^(?:[A-Z]{1,8}-?\d+|none)$")
RSC_HYPHEN_RE = re.compile(r"^(R|SC)-(\d+)$")


def normaliza_anchor(a):
    """`R-2` → `R2`, `SC-1` → `SC1`. Todo o resto (inclusive `DESC-01`) sai intacto.

    A forma canônica da âncora no mundo do discuss é SEM hífen: `discuss-init.sh` só aceita
    `^R[0-9]+$` em REQ_IDS, `templates/spec.md` grava `"id": "R1"` e as áreas chegam como
    `--area "Nome|R2,R3"`. Um insumo antigo (PRE-SPEC da /go-and-do) pode trazer `R-2`/`SC-1`.
    Normalizando em TODA porta de entrada de âncora, o checkpoint nunca guarda forma hifenada
    de R/SC — os consumidores a jusante comparam sempre no mesmo dialeto.
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
        "secoes": {}, "aprovado_sha256": None,
    }
    save(a.ckpt, data)
    consume([a.goal_file, a.refs_file, a.code_context_file, a.discretion_file, a.scope_in_file, a.scope_out_file])
    print(json.dumps({"ok": True, "op": "init", "ckpt": a.ckpt, "areas": data["areas_remaining"],
                      "anchors": {x["name"]: x["anchors"] for x in areas},
                      "spec_loaded": data["spec_loaded"], "req_count": data["req_count"]}))


def op_add(a):
    for flag, val in (("--area", a.area), ("--origin", a.origin), ("--answer-file", a.answer_file)):
        if not val:
            die(f"{flag} is required")
    data = load(a.ckpt)
    if a.origin not in ORIGINS:
        die(f"--origin must be one of {sorted(ORIGINS)} — the deposit only records the owner's decisions "
            "(AC-11); nothing was written")
    if a.reversibility and a.reversibility not in REVERSIBILITY:
        die(f"--reversibility must be one of {sorted(REVERSIBILITY)}")
    rationale = read_text(a.reversibility_rationale_file)
    if a.reversibility in {"costly", "one-way"} and not rationale:
        die("--reversibility costly|one-way requires --reversibility-rationale-file (templates/context.md:56-68)")
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
    data.setdefault("decisions", {}).setdefault(a.area, []).append(dec)
    ensure_area(data, a.area)
    invalida_aprovacao(data)
    save(a.ckpt, data)
    consume([a.answer_file, a.question_file, a.prose_file, a.reversibility_rationale_file] + list(a.option_file or []))
    print(json.dumps({"ok": True, "op": "add-decision", "id": did, "area": a.area, "anchor": anchor,
                      "anchors": anchors, "origin": a.origin, "total": len(all_ids(data))}))


def close_area(data, name):
    """Fecha a área (idempotente). Só `areas_completed` muda; `sync_areas` deriva o resto."""
    if name not in data.setdefault("areas_completed", []):
        data["areas_completed"].append(name)


def op_complete(a):
    data = load(a.ckpt)
    known = [x["name"] for x in areas_of(data)]
    if a.area not in known:
        die(f"area {a.area!r} does not exist in this checkpoint — known areas: "
            f"{sorted(set(known)) or '(none)'}")
    close_area(data, a.area)
    invalida_aprovacao(data)
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
    invalida_aprovacao(data)
    save(a.ckpt, data)
    consume([a.file])
    v = data[f]
    print(json.dumps({"ok": True, "op": "set", "field": f, "size": len(v) if isinstance(v, (list, dict)) else len(str(v))}))


def invalida_aprovacao(data):
    """Toda mudança no depósito depois do «ok» derruba a aprovação: o documento aprovado era outro."""
    data["aprovado_sha256"] = None


def _sem_duplicata(pares):
    vistos = {}
    for k, v in pares:
        if k in vistos:
            raise ValueError(f"chave duplicada {k!r}")
        vistos[k] = v
    return vistos


def op_set_secao(a):
    """Seção do documento único: texto livre por arquivo (consumido). `*_json` → JSON válido,
    sem chave duplicada, guardado verbatim (o render o copia como está)."""
    if a.secao not in SECOES:
        die(f"--secao {a.secao!r} desconhecida — slugs: {', '.join(SECOES)}")
    data = load(a.ckpt)
    texto = read_text(a.file, required=True)
    if a.secao.endswith("_json"):
        try:
            json.loads(texto, object_pairs_hook=_sem_duplicata)
        except (json.JSONDecodeError, ValueError) as e:
            die(f"--secao {a.secao}: JSON inválido ({e}) — nothing was written")
    data.setdefault("secoes", {})[a.secao] = texto
    invalida_aprovacao(data)
    save(a.ckpt, data)
    consume([a.file])
    print(json.dumps({"ok": True, "op": "set-secao", "secao": a.secao, "size": len(texto),
                      "secoes": sorted(data["secoes"])}, ensure_ascii=False))


def op_aprovar(a):
    """Grava o sha256 do rascunho que o dono viu e aprovou («ok»). Só ele libera a promoção."""
    if not SHA_RE.match(a.sha256 or ""):
        die(f"--sha256 deve ser hex de 64 caracteres minúsculos (got {a.sha256!r})")
    data = load(a.ckpt)
    data["aprovado_sha256"] = a.sha256
    save(a.ckpt, data)
    print(json.dumps({"ok": True, "op": "aprovar", "aprovado_sha256": a.sha256}))


def op_show(a):
    data = load(a.ckpt)
    per = {k: [d["id"] for d in v] for k, v in data.get("decisions", {}).items()}
    sec = data.get("secoes") or {}
    print(json.dumps({"phase": data.get("phase"), "areas_completed": data.get("areas_completed"),
                      "areas_remaining": data.get("areas_remaining"), "decisions": per,
                      "ids": all_ids(data),
                      "secoes": [k for k in SECOES if str(sec.get(k) or "").strip()],
                      "aprovado_sha256": data.get("aprovado_sha256"),
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
    s.add_argument("--answer-file"); s.add_argument("--prose-file")
    s.add_argument("--option-file", action="append"); s.add_argument("--chosen-option", type=int)
    s.add_argument("--chosen-label")
    s.set_defaults(fn=op_add)

    s = sub.add_parser("complete-area"); s.add_argument("ckpt"); s.add_argument("--area", required=True)
    s.set_defaults(fn=op_complete)

    s = sub.add_parser("set"); s.add_argument("ckpt"); s.add_argument("--field", required=True)
    s.add_argument("--file", required=True); s.add_argument("--append", action="store_true")
    s.set_defaults(fn=op_set)

    s = sub.add_parser("set-secao"); s.add_argument("ckpt"); s.add_argument("--secao", required=True)
    s.add_argument("--file", required=True); s.set_defaults(fn=op_set_secao)

    s = sub.add_parser("aprovar"); s.add_argument("ckpt"); s.add_argument("--sha256", required=True)
    s.set_defaults(fn=op_aprovar)

    s = sub.add_parser("show"); s.add_argument("ckpt"); s.set_defaults(fn=op_show)

    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
