#!/usr/bin/env python3
"""mede-tokens.py — ledger-lite da go-and-do (decisão G.1-d/e do gad-major-update).

Mede TOKENS REAIS e CUSTO de uma sessão (ou de uma janela dela) direto dos
transcripts JSONL do Claude Code — a mesma mecânica comprovada do token-ledger
da /audit-gad (dedup por requestId, 4 campos de usage), reimplementada autônoma
porque este repo é público (PC-8). É a ÚNICA fonte legítima dos campos
`--tokens-reais`/`--custo` do run-log: subagente não reporta token nenhum.

Uso (normalmente chamado pelo confere-etapa.sh no fecho de cada etapa):
  mede-tokens.py --sessao <id-ou-prefixo> [--desde ISO] [--ate ISO]
                 [--transcript PATH] [--subagents DIR] [--pretty] [--sem-espelho]

  --sessao      id (ou prefixo) da sessão; o transcript é achado em
                ~/.claude/projects/**/<id>*.jsonl (não montar caminho na mão).
  --desde/--ate janela da etapa (ISO-8601). Sem janela = sessão inteira.
                Camada 0: entram os requests com timestamp dentro da janela.
                Subagentes: entra INTEIRO o subagente cujo 1º request cai na
                janela (atribuição por despacho, igual ao ledger da auditoria).
  --transcript/--subagents  sobrescrevem a descoberta (teste/aceite).

Saída: JSON compacto em 1 linha no stdout + espelho em
<root>/.planning/.gad-last-mede-tokens.json (PC-5: o RTK capa o stdout).
Campos: camada0/subagentes/total (4 campos de usage + custo_usd), n_requests,
n_subagentes, precos_de (proveniência da tabela — PC-7), avisos.

Política de falha: medição indisponível (sem transcript, sem jq… não há jq
aqui — sem arquivo) = FAIL-OPEN DECLARADO — exit 0 com status="sem_medicao" e
reason; quem consome decide seguir sem os campos. Argumento inválido = defeito
de LÓGICA = exit 2.

Caveat conhecido (investigação da falha 5 da F24, 10/08): medir NO INSTANTE do
fecho da etapa subconta — o usage das últimas respostas dos subagentes ainda está
sendo descarregado no JSONL (flush lag; F24 etapa 2: 2.822.326 no fecho vs
2.959.862 re-medindo a mesma janela depois, −4,6%). A re-medição a posteriori
(auditoria) é a mais fiel; a divergência fecho×ledger até ~5% tem essa causa
mecânica antes de ser suspeita de bug.
"""
import argparse
import glob
import json
import os
import sys
from datetime import datetime

CAMPOS = ("input_tokens", "cache_creation_input_tokens",
          "cache_read_input_tokens", "output_tokens")
SAIDA = {"input_tokens": "input_tokens",
         "cache_creation_input_tokens": "cache_creation_tokens",
         "cache_read_input_tokens": "cache_read_tokens",
         "output_tokens": "output_tokens"}
PRECO_CAMPO = {"input_tokens": "input",
               "cache_creation_input_tokens": "cache_write",
               "cache_read_input_tokens": "cache_read",
               "output_tokens": "output"}


def parse_ts(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def zero():
    return {c: 0 for c in CAMPOS}


def carrega_precos(avisos):
    caminho = os.path.join(os.path.dirname(os.path.realpath(__file__)), "precos.json")
    try:
        with open(caminho, encoding="utf-8") as fh:
            p = json.load(fh)
        return p.get("anthropic_por_1m") or {}, p.get("atualizado_em") or "?"
    except (OSError, json.JSONDecodeError) as e:
        avisos.append(f"precos.json ilegível ({e}) — custo não calculado")
        return {}, None


def preco_do_modelo(tabela, modelo):
    """Prefixo mais longo do id vence; 'default' cobre o resto."""
    melhor, tam = tabela.get("default"), -1
    for prefixo, preco in tabela.items():
        if prefixo != "default" and modelo.startswith(prefixo) and len(prefixo) > tam:
            melhor, tam = preco, len(prefixo)
    return melhor


def custo_de(usage, modelo, tabela):
    preco = preco_do_modelo(tabela, modelo or "")
    if not preco:
        return 0.0
    return sum((usage.get(c, 0) or 0) * preco.get(PRECO_CAMPO[c], 0) / 1e6
               for c in CAMPOS)


def le_transcript(path, avisos):
    """(requests, primeiro_ts) — requests = [(ts, usage, modelo)] dedup por
    requestId, vale a ÚLTIMA ocorrência (streaming grava o mesmo usage N vezes)."""
    por_request, ordem = {}, []
    try:
        fh = open(path, encoding="utf-8")
    except OSError as e:
        avisos.append(f"ilegível: {path} ({e})")
        return [], None
    with fh:
        for n, linha in enumerate(fh, 1):
            linha = linha.strip()
            if not linha:
                continue
            try:
                obj = json.loads(linha)
            except json.JSONDecodeError:
                avisos.append(f"linha {n} inválida em {os.path.basename(path)}")
                continue
            msg = obj.get("message")
            usage = msg.get("usage") if isinstance(msg, dict) else None
            if not isinstance(usage, dict):
                continue
            chave = obj.get("requestId") or obj.get("uuid") or f"{path}:{n}"
            if chave not in por_request:
                ordem.append(chave)
            por_request[chave] = (parse_ts(obj.get("timestamp")),
                                  usage, msg.get("model") or "")
    reqs = [por_request[k] for k in ordem]
    primeiro = next((ts for ts, _, _ in reqs if ts), None)
    return reqs, primeiro


def sem_medicao(reason):
    print(json.dumps({"status": "sem_medicao", "reason": reason},
                     ensure_ascii=False, separators=(",", ":")))
    sys.exit(0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sessao")
    ap.add_argument("--desde")
    ap.add_argument("--ate")
    ap.add_argument("--transcript")
    ap.add_argument("--subagents")
    ap.add_argument("--pretty", action="store_true")
    ap.add_argument("--sem-espelho", action="store_true")
    args = ap.parse_args()
    if not args.sessao and not args.transcript:
        ap.error("informe --sessao ou --transcript")
    desde, ate = parse_ts(args.desde), parse_ts(args.ate)
    if args.desde and not desde:
        ap.error(f"--desde inválido: {args.desde}")
    if args.ate and not ate:
        ap.error(f"--ate inválido: {args.ate}")

    avisos = []

    # ---- descoberta do transcript pela sessão
    transcript = args.transcript
    if not transcript:
        candidatos = sorted(
            glob.glob(os.path.join(os.path.expanduser("~"), ".claude", "projects",
                                   "*", f"{args.sessao}*.jsonl")),
            key=lambda p: os.path.getmtime(p), reverse=True)
        if not candidatos:
            sem_medicao(f"transcript não encontrado para sessão {args.sessao}")
        if len(candidatos) > 1:
            avisos.append(f"{len(candidatos)} transcripts casam com o prefixo — "
                          f"usando o mais recente: {os.path.basename(candidatos[0])}")
        transcript = candidatos[0]
    if not os.path.isfile(transcript):
        sem_medicao(f"transcript inexistente: {transcript}")

    subdir = args.subagents or os.path.join(transcript[:-len(".jsonl")], "subagents")

    tabela, precos_de = carrega_precos(avisos)

    def na_janela(ts):
        if ts is None:
            return desde is None and ate is None
        if desde and ts < desde:
            return False
        if ate and ts > ate:
            return False
        return True

    # ---- camada 0 (só requests dentro da janela)
    reqs0, _ = le_transcript(transcript, avisos)
    if not reqs0:
        sem_medicao(f"transcript sem requests com usage: {transcript}")
    tot0, custo0, n0 = zero(), 0.0, 0
    sem_ts = 0
    for ts, usage, modelo in reqs0:
        if ts is None:
            sem_ts += 1
        if not na_janela(ts):
            continue
        n0 += 1
        for c in CAMPOS:
            tot0[c] += usage.get(c, 0) or 0
        custo0 += custo_de(usage, modelo, tabela)
    if sem_ts:
        avisos.append(f"{sem_ts} requests da camada 0 sem timestamp "
                      f"({'dentro' if not (desde or ate) else 'FORA'} da medição)")

    # ---- subagentes (inteiros, pelo ts do 1º request)
    totS, custoS, nS = zero(), 0.0, 0
    for jsonl in sorted(glob.glob(os.path.join(subdir, "agent-*.jsonl"))):
        reqs, primeiro = le_transcript(jsonl, avisos)
        if not reqs or not na_janela(primeiro):
            continue
        nS += 1
        for ts, usage, modelo in reqs:
            for c in CAMPOS:
                totS[c] += usage.get(c, 0) or 0
            custoS += custo_de(usage, modelo, tabela)

    def fmt(u, custo, extra=None):
        d = {SAIDA[c]: u[c] for c in CAMPOS}
        d["custo_usd"] = round(custo, 4) if precos_de else None
        if extra:
            d.update(extra)
        return d

    total = zero()
    for c in CAMPOS:
        total[c] = tot0[c] + totS[c]
    resultado = {
        "status": "ok",
        "sessao": os.path.basename(transcript)[:8],
        "desde": args.desde, "ate": args.ate,
        "camada0": fmt(tot0, custo0, {"n_requests": n0}),
        "subagentes": fmt(totS, custoS, {"n": nS}),
        "total": fmt(total, custo0 + custoS),
        "precos_de": precos_de,
        "avisos": avisos,
    }

    compacto = json.dumps(resultado, ensure_ascii=False, separators=(",", ":"))
    if not args.sem_espelho:
        d = os.getcwd()
        while d != os.path.dirname(d):
            if os.path.isdir(os.path.join(d, ".planning")):
                with open(os.path.join(d, ".planning",
                                       ".gad-last-mede-tokens.json"),
                          "w", encoding="utf-8") as fh:
                    fh.write(compacto + "\n")
                break
            d = os.path.dirname(d)
    print(json.dumps(resultado, ensure_ascii=False, indent=2) if args.pretty
          else compacto)


if __name__ == "__main__":
    main()
