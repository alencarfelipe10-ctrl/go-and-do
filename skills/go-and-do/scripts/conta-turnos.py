#!/usr/bin/env python3
"""conta-turnos.py — medição determinística dos turnos do coordenador de intenção
por ciclo da revisão adversarial (v1.8.2; régua da dieta v2: <=4 turnos/ciclo — na
F22 a régua em prosa rendeu 12-12-9-9-2, este script torna o estouro um número).

Uso: conta-turnos.py <transcript-do-coordenador.jsonl> <pareceres_dir>
     conta-turnos.py --auto <pareceres_dir>

--auto (fix da falha 4 da auditoria F24, 10/08 — 3ª fase sem o script rodar): acha
SOZINHO o transcript do coordenador (gad-intent) da sessão atual, via os meta.json de
~/.claude/projects/*/<session_id>/subagents/ (agentType == gad-intent, o mais recente).
A camada 0 nunca soube preencher <transcript> — a prosa pedia um caminho que ninguém
tinha; com --auto o confere-etapa.sh 1 chama sem argumento adivinhado.

Fronteiras de ciclo = mtime dos arquivos .prova-leitura-cN.txt (o nonce é criado no
início de cada ciclo, antes do lançamento das lanes). Turno = mensagem `assistant`
com >=1 tool_use. Saída: uma linha por ciclo `cN: T turnos [ESTOURO >4]` + a taxa de
batching (tool_use por turno). Exit 0 = tudo dentro do teto · 1 = houve estouro ·
2 = uso/arquivo inválido. Medição, não freio: o estouro é gravado como evento
`incidente` no run-log pelo próprio script (auto-registro).
"""
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

TETO = 4


def die(msg: str) -> None:
    print(f"ERRO: {msg}", file=sys.stderr)
    sys.exit(2)


def _acha_transcript() -> Path:
    """--auto: localiza o transcript do gad-intent da sessão atual pelos meta.json."""
    import os

    sid = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if not sid:
        die("--auto sem CLAUDE_CODE_SESSION_ID no ambiente")
    candidatos = []
    for meta in Path.home().glob(f".claude/projects/*/{sid}/subagents/agent-*.meta.json"):
        try:
            d = json.loads(meta.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if d.get("agentType") == "gad-intent":
            candidatos.append(meta)
    if not candidatos:
        die(f"--auto: nenhum meta.json de gad-intent na sessão {sid[:8]} — SEM MEDIÇÃO (não é zero)")
    meta = max(candidatos, key=lambda p: p.stat().st_mtime)
    t = meta.with_name(meta.name.replace(".meta.json", ".jsonl"))
    if not t.is_file():
        die(f"--auto: transcript ausente para {meta.name}")
    return t


def main() -> None:
    if len(sys.argv) != 3:
        die("uso: conta-turnos.py <transcript.jsonl>|--auto <pareceres_dir>")
    if sys.argv[1] == "--auto":
        transcript, pareceres = _acha_transcript(), Path(sys.argv[2])
    else:
        transcript, pareceres = Path(sys.argv[1]), Path(sys.argv[2])
    if not transcript.is_file():
        die(f"transcript não encontrado: {transcript}")
    if not pareceres.is_dir():
        die(f"pareceres_dir não encontrado: {pareceres}")

    fronteiras = []  # (ciclo, ts_inicio)

    def coleta(d: Path) -> None:
        for f in d.glob(".prova-leitura-c*.txt"):
            m = re.match(r"\.prova-leitura-c(\d+)\.txt$", f.name)
            if m:
                ts = datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc)
                fronteiras.append((int(m.group(1)), ts))

    coleta(pareceres)
    # Fase anterior à pasta .intent/ (gad-major): as provas moravam em pareceres/ —
    # fallback declarado para fase antiga (PC-2).
    if not fronteiras and pareceres.name == ".intent" and (pareceres.parent / "pareceres").is_dir():
        print(f"aviso: nada em .intent/ — usando layout legado {pareceres.parent / 'pareceres'}")
        coleta(pareceres.parent / "pareceres")
    if not fronteiras:
        print("nenhum ciclo detectado (sem .prova-leitura-c*.txt) — nada a medir")
        sys.exit(0)
    fronteiras.sort(key=lambda x: x[1])

    turnos = {c: 0 for c, _ in fronteiras}
    tools = {c: 0 for c, _ in fronteiras}
    with transcript.open() as fh:
        for line in fh:
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue
            if e.get("type") != "assistant" or not e.get("timestamp"):
                continue
            msg = e.get("message") or {}
            n_tools = sum(
                1
                for b in (msg.get("content") or [])
                if isinstance(b, dict) and b.get("type") == "tool_use"
            )
            if n_tools == 0:
                continue
            t = datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00"))
            ciclo = None
            for c, ini in fronteiras:
                if t >= ini:
                    ciclo = c
            if ciclo is not None:
                turnos[ciclo] += 1
                tools[ciclo] += n_tools

    estouro = False
    for c, _ in fronteiras:
        flag = ""
        if turnos[c] > TETO:
            flag = f"  [ESTOURO >{TETO}]"
            estouro = True
        batch = f"{tools[c] / turnos[c]:.1f}" if turnos[c] else "-"
        print(f"c{c}: {turnos[c]} turnos · {tools[c]} tool_use ({batch}/turno){flag}")
    codigo = 1 if estouro else 0
    resumo = " ".join(f"c{c}:{turnos[c]}" for c, _ in fronteiras)
    _autoregistro(codigo, resumo)
    sys.exit(codigo)


def _autoregistro(codigo, resumo=""):
    """Auto-registro G.2-ii: grava o próprio resultado no run-log quando há rodada
    ativa (ponteiro PC-3); fora de rodada é no-op. Estouro do teto vira também um
    evento `incidente` (a régua 27(a) da auditoria lê dali). Nunca falha o script."""
    import os
    import subprocess
    try:
        root = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                              capture_output=True, text=True).stdout.strip() or os.getcwd()
        p = os.path.join(root, ".planning", ".gad-rodada-ativa.json")
        if not os.path.isfile(p):
            return
        with open(p, encoding="utf-8") as fh:
            d = json.load(fh)
        # rodada pausada (último evento = stop) → no-op, mesmo guard do hook: um
        # ponteiro que sobreviveu à pausa não pode receber eventos pós-stop
        try:
            with open(os.path.join(d["phase_dir"], f"{d['nn']}-RUN-LOG.jsonl"), encoding="utf-8") as fh:
                if '"evento":"stop"' in list(fh)[-1]:
                    return
        except (OSError, IndexError, KeyError):
            pass
        rl = os.path.join(os.path.dirname(os.path.realpath(__file__)), "run-log.sh")
        subprocess.run(["bash", rl, d["phase_dir"], d["nn"], "script", "1 intencao",
                        "--kv", "script=conta-turnos.py", "--kv", f"exit={codigo}",
                        *(["--kv", f"resumo={resumo}"] if resumo else [])],
                       capture_output=True, timeout=10)
        if codigo == 1:
            subprocess.run(["bash", rl, d["phase_dir"], d["nn"], "incidente", "1 intencao",
                            "--kv", "origem=conta-turnos.py",
                            "--kv", f"detalhe=teto de {TETO} turnos/ciclo estourado ({resumo})"],
                           capture_output=True, timeout=10)
    except Exception:
        pass


if __name__ == "__main__":
    main()
