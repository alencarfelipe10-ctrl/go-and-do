#!/usr/bin/env python3
"""pre-spec-batch.py — bloco `gad:decisoes` do PRE-SPEC → `.discuss-tmp/pre-spec-batch.json` (D5b).

Chamado pelo `discuss-init.sh --pre-spec <arquivo>`. Lê **só** o bloco entre
`<!-- gad:decisoes:begin v1 -->` e `<!-- gad:decisoes:end -->` (JSON canônico, array de
objetos) — o PRE-SPEC inteiro nunca entra na janela do filho, que é o ponto do item
(a 24.3 foi de 35 k a 81 k tokens por ler o arquivo todo).

Filtro ESTRITO `kind == decisao_dono`: `fato_medido` nunca vira decisão — ele vai só para a
lista "Fatos medidos no levantamento — verifique" do briefing e para o `[medido:PS-nn]` do
SPEC. O batch resultante é consumido pelo `checkpoint-write.py map-pre-spec`, único dono
dessas entradas (elas nunca passam por `add-decision --batch`).

Campos gerados por entrada: `source_id` (PS-nn), `kind`, `area` (o rótulo humano do PS),
`anchor` (= `req_anchor`), `answer` (= `decisao`), `options` (= `opcoes_descartadas`),
`evidence`, `reversibility` + `reversibility_rationale`, `prose` (ressalva + span, o que
situa a decisão sem reabri-la).

`req_anchor` aceito é o MESMO do `confere-pre-spec.sh`: `R-n`, `SC-n`, id do REQUIREMENTS
do projeto (DESC-01, RESID-01…) ou `none`. A forma HIFENADA de R/SC é aceita na ENTRADA e
sai NORMALIZADA no `anchor` (`R-2` → `R2`, `SC-1` → `SC1`) — ver `normaliza_anchor`.

Saída em stdout (o shell lê com sed):
    estado: ok | ausente | invalido
    decisoes: <N>
Mensagens humanas vão para stderr. Exit 0 = ok · 1 = bloco ausente · 2 = bloco inválido.
Bloco ausente NÃO é erro do script: o fail-closed é do coordenador (§0.5), que já parou antes.
"""
import json
import os
import re
import sys
import tempfile

BEGIN = "<!-- gad:decisoes:begin v1 -->"
END = "<!-- gad:decisoes:end -->"
KINDS = {"decisao_dono", "fato_medido"}
REVERS = {"reversible", "costly", "one-way"}
RE_ID = re.compile(r"^PS-\d\d$")
RE_ANCHOR = re.compile(r"^(?:[A-Z]{1,8}-?\d+|none)$")   # idêntico ao confere-pre-spec.sh
RE_RSC_HIFEN = re.compile(r"^(R|SC)-(\d+)$")


def normaliza_anchor(a):
    """`R-2` → `R2`, `SC-1` → `SC1`. Todo o resto sai intacto.

    Por quê: no mundo do discuss a âncora é canônica SEM hífen — o `discuss-init.sh` só
    aceita `^R[0-9]+$` em REQ_IDS, o `templates/spec.md` grava `"id": "R1"` e o
    `checkpoint-write.py` recebe `--area "Nome|R2,R3"`. O PRE-SPEC, porém, pode trazer
    `R-2`/`SC-1` (ambas as formas passam no `confere-pre-spec.sh`). Sem esta normalização
    o `map-pre-spec` compararia `R-2` com `R2` e nunca casaria, e o WARN de âncora órfã do
    `context-guard.sh` ficaria mudo. Ids do REQUIREMENTS (`DESC-01`, `RESID-01`) NÃO são
    tocados: ali o hífen faz parte do id.
    """
    return RE_RSC_HIFEN.sub(r"\1\2", a) if isinstance(a, str) else a


def sai(estado, n=0, code=0, msg=None):
    if msg:
        sys.stderr.write(f"[pre-spec-batch] {msg}\n")
    print(f"estado: {estado}")
    print(f"decisoes: {n}")
    sys.exit(code)


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("uso: pre-spec-batch.py <PRE-SPEC.md> <saida.json>\n")
        sys.exit(2)
    pre, saida = sys.argv[1], sys.argv[2]
    try:
        linhas = open(pre, encoding="utf-8", errors="replace").read().split("\n")
    except OSError as e:
        sai("invalido", 0, 2, f"não consegui ler {pre}: {e}")

    ini = fim = None
    for n, l in enumerate(linhas, 1):
        if BEGIN in l and ini is None:
            ini = n
        elif END in l and ini is not None and fim is None:
            fim = n
    if ini is None or fim is None:
        sai("ausente", 0, 1,
            f"bloco gad:decisoes ausente em {pre} — nenhum batch gerado "
            "(a rota antiga/migração é decisão do coordenador, §0.5)")

    bruto = "\n".join(linhas[ini:fim - 1])

    def sem_duplicata(pares):
        vistas = set()
        for k, _ in pares:
            if k in vistas:
                sai("invalido", 0, 2, f"chave duplicada no JSON do bloco: {k!r}")
            vistas.add(k)
        return dict(pares)

    try:
        dados = json.loads(bruto, object_pairs_hook=sem_duplicata)
    except json.JSONDecodeError as e:
        sai("invalido", 0, 2, f"JSON do bloco inválido: {e.msg} (linha {e.lineno} do bloco)")
    if not isinstance(dados, list):
        sai("invalido", 0, 2, "o conteúdo do bloco tem de ser um array JSON de objetos")

    batch, vistos, medidos = [], set(), []
    for i, e in enumerate(dados):
        onde = f"bloco[{i}]"
        if not isinstance(e, dict):
            sai("invalido", 0, 2, f"{onde} não é um objeto")
        psid = e.get("id")
        if not isinstance(psid, str) or not RE_ID.match(psid):
            sai("invalido", 0, 2, f"{onde}: id {psid!r} não é PS-nn")
        if psid in vistos:
            sai("invalido", 0, 2, f"{onde}: id {psid} duplicado no bloco")
        vistos.add(psid)
        kind = e.get("kind")
        if kind not in KINDS:
            sai("invalido", 0, 2, f"{psid}: kind {kind!r} fora de {sorted(KINDS)}")
        if kind == "fato_medido":
            medidos.append(psid)
            continue                                    # filtro estrito: nunca vira decisão
        anchor = e.get("req_anchor")
        if not isinstance(anchor, str) or not RE_ANCHOR.match(anchor):
            sai("invalido", 0, 2, f"{psid}: req_anchor {anchor!r} não é R-n / SC-n / id do "
                                  "REQUIREMENTS / none")
        decisao = e.get("decisao")
        if not isinstance(decisao, str) or not decisao.strip():
            sai("invalido", 0, 2, f"{psid}: campo `decisao` vazio ou ausente")
        rev = e.get("reversibilidade")
        if rev is not None and rev not in REVERS:
            sai("invalido", 0, 2, f"{psid}: reversibilidade {rev!r} fora de {sorted(REVERS)}")
        just = e.get("reversibilidade_justificativa") or ""
        if rev in {"costly", "one-way"} and not just.strip():
            sai("invalido", 0, 2, f"{psid}: reversibilidade {rev} exige "
                                  "`reversibilidade_justificativa`")
        opcoes = e.get("opcoes_descartadas") or []
        if not isinstance(opcoes, list) or any(not isinstance(o, str) for o in opcoes):
            sai("invalido", 0, 2, f"{psid}: `opcoes_descartadas` tem de ser lista de strings")
        prosa = []
        if e.get("ressalva"):
            prosa.append(f"Ressalva do PRE-SPEC: {e['ressalva']}")
        if e.get("span"):
            prosa.append(f"Prosa de origem: {e['span']} ({os.path.basename(pre)})")
        if opcoes:
            prosa.append("Descartadas no PRE-SPEC: " + " · ".join(opcoes))
        entrada = {
            "source_id": psid,
            "kind": kind,
            "area": e.get("area") or psid,
            "anchor": normaliza_anchor(anchor),   # valida no bruto, grava no canônico
            "answer": decisao.strip(),
            "options": opcoes,
            "evidence": e.get("evidencia") or "none",
            "prose": "\n".join(prosa),
        }
        if rev:
            entrada["reversibility"] = rev
            if just.strip():
                entrada["reversibility_rationale"] = just.strip()
        batch.append(entrada)

    d = os.path.dirname(os.path.abspath(saida)) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".psb-", suffix=".json", dir=d)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(batch, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, saida)
    if medidos:
        sys.stderr.write(f"[pre-spec-batch] fato_medido fora do batch (vai ao briefing/SPEC "
                         f"como [medido:PS-nn]): {', '.join(medidos)}\n")
    sai("ok", len(batch), 0)


if __name__ == "__main__":
    main()
