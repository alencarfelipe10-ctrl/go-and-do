#!/usr/bin/env python3
"""uat-fiscal.py — leitor único do NN-UAT.md para o fiscal da etapa 5.

Nasceu da auditoria F4 RLR. Quatro achados, um leitor só (dois parsers do mesmo
arquivo é como o fiscal do 4.1 acabou lendo a iteração errada — FM-04GAT):

  FM-01UAT  cenário CONDUZIDO em `pass` sem arquivo de evidência. Medido: 3 cenários
            tinham menos prova do que a nota alegava (o 4 sem arquivo nenhum).
            Exceção declarável na nota: «ação sem saída».
  FJ-01UAT  cenário `type: logic` conduzido em `pass` sem nenhuma linha `$ ` na
            evidência — «pass por leitura de código», contra a regra do playbook.
  FJ-02UAT  cenário conduzido em `pass` sem linha 🔍 (sondagem adversarial). Medido:
            cenários 1, 3 e 6 fecharam assim. Aceita «🔍 não se aplica: <motivo>».
  FM-02UAT  o bloco `## Summary` é RECALCULADO e ESCRITO por este script, o `status`
            é promovido, e o bloco `## Current Test` some. Medido: o recibo do fiscal
            apontava para um commit em que o cabeçalho dizia `testing` e o resumo
            dizia 33/20/13 com 29 `pass` no corpo.

`source: automated` = cenário de suíte: fica fora dos três primeiros asserts (não há
condutor para sondar nem evidência conduzida a cobrar).

Uso: uat-fiscal.py <NN-UAT.md> <phase_dir> [--escrever]
     sem --escrever nada é tocado (modo seco); o JSON de saída traz `summary_novo`
     com o que SERIA escrito.
"""
import json
import os
import re
import sys


def cenarios(txto):
    """Fatia o corpo em cenários pelo cabeçalho `### N. nome`."""
    corte = re.split(r"^### +", txto, flags=re.M)[1:]
    saida = []
    for bloco in corte:
        linhas = bloco.splitlines()
        titulo = linhas[0].strip() if linhas else ""
        num = titulo.split(".", 1)[0].strip()
        campo = {}
        for k in ("type", "result", "source", "evidencia"):
            m = re.search(r"^%s: *(.+)$" % k, bloco, flags=re.M)
            if m:
                campo[k] = m.group(1).strip()
        saida.append({
            "num": num, "titulo": titulo[:80], "corpo": bloco,
            "type": campo.get("type", ""), "result": campo.get("result", ""),
            "source": campo.get("source", ""), "evidencia": campo.get("evidencia", ""),
        })
    return saida


def main():
    if len(sys.argv) < 3:
        print(json.dumps({"erro": "uso: uat-fiscal.py <uat.md> <phase_dir> [--escrever]"}))
        return 2
    caminho, pd = sys.argv[1], sys.argv[2]
    escrever = "--escrever" in sys.argv[3:]
    try:
        txto = open(caminho, encoding="utf-8", errors="replace").read()
    except OSError as e:
        print(json.dumps({"erro": str(e)}))
        return 2

    # Só o corpo dos cenários — nem o cabeçalho YAML nem `## Summary`/`## Gaps`.
    corpo = txto
    m = re.search(r"^## Tests *$", txto, flags=re.M)
    if m:
        corpo = txto[m.end():]
    m = re.search(r"^## (Summary|Gaps) *$", corpo, flags=re.M)
    if m:
        corpo = corpo[:m.start()]

    cs = cenarios(corpo)
    sem_evidencia, logic_sem_comando, sem_sondagem = [], [], []
    placar = {"pass": 0, "issue": 0, "pending": 0, "blocked": 0, "assumed": 0, "skipped": 0}
    for c in cs:
        r = c["result"].lower()
        for k in placar:
            if re.match(r"^\[?%s\]?$" % k, r):
                placar[k] += 1
        conduzido = "automated" not in c["source"]
        if r != "pass" or not conduzido:
            continue
        rot = "%s (%s)" % (c["num"] or "?", c["titulo"][:40])
        ev = c["evidencia"]
        ev_abs = os.path.join(pd, ev) if ev and not os.path.isabs(ev) else ev
        tem_ev = bool(ev) and os.path.isfile(ev_abs)
        # «ação sem saída»: exceção declarável na nota do próprio cenário
        if not tem_ev and "ação sem saída" not in c["corpo"] and "acao sem saida" not in c["corpo"]:
            sem_evidencia.append(rot)
        if c["type"] == "logic" and tem_ev:
            try:
                bruto = open(ev_abs, encoding="utf-8", errors="replace").read()
            except OSError:
                bruto = ""
            if not re.search(r"^\$ ", bruto, flags=re.M):
                logic_sem_comando.append(rot)
        if "🔍" not in c["corpo"]:
            sem_sondagem.append(rot)

    total = len(cs)
    sem_result = sum(1 for c in cs if not c["result"])
    summary_novo = (
        "total: %d\npassed: %d\nissues: %d\npending: %d\nskipped: %d\nblocked: %d\n"
        % (total, placar["pass"], placar["issue"],
           placar["pending"] + placar["assumed"], placar["skipped"], placar["blocked"])
    )

    escrito = []
    if escrever:
        novo = txto
        # (1) bloco `## Summary` recalculado — se não existe, entra antes do `## Gaps`
        alvo = re.search(r"^## Summary *$\n(.*?)(?=^## |\Z)", novo, flags=re.M | re.S)
        if alvo:
            if alvo.group(1).strip() != summary_novo.strip():
                novo = novo[:alvo.start()] + "## Summary\n\n" + summary_novo + "\n" + novo[alvo.end():]
                escrito.append("summary")
        else:
            m2 = re.search(r"^## Gaps *$", novo, flags=re.M)
            ins = "## Summary\n\n" + summary_novo + "\n"
            novo = (novo[:m2.start()] + ins + novo[m2.start():]) if m2 else (novo.rstrip() + "\n\n" + ins)
            escrito.append("summary")
        # (2) `## Current Test` some: é rascunho do condutor, não resultado
        cur = re.search(r"^## Current Test *$\n.*?(?=^## |\Z)", novo, flags=re.M | re.S)
        if cur:
            novo = novo[:cur.start()] + novo[cur.end():]
            escrito.append("current_test")
        # (3) status promovido só quando não sobra nada em aberto
        if (placar["issue"] == 0 and placar["pending"] == 0 and placar["blocked"] == 0
                and placar["pass"] > 0 and re.search(r"^status: testing", novo, flags=re.M)):
            novo = re.sub(r"^status: testing", "status: complete", novo, count=1, flags=re.M)
            escrito.append("status")
        if novo != txto:  # idempotente: conteúdo igual não toca o arquivo
            open(caminho, "w", encoding="utf-8").write(novo)

    print(json.dumps({
        "cenarios": total, "sem_result": sem_result, "placar": placar,
        "pass_sem_evidencia": sem_evidencia,
        "logic_sem_comando": logic_sem_comando,
        "pass_sem_sondagem": sem_sondagem,
        "summary_novo": summary_novo.strip().replace("\n", " · "),
        "escrito": escrito,
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
