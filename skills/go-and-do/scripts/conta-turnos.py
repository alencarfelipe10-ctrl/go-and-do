#!/usr/bin/env python3
"""conta-turnos.py — medição determinística dos turnos do coordenador de intenção
por ciclo da revisão adversarial (v1.8.2; régua da dieta v2: <=4 turnos/ciclo — na
F22 a régua em prosa rendeu 12-12-9-9-2, este script torna o estouro um número).

Uso: conta-turnos.py <transcript-do-coordenador.jsonl> <pareceres_dir>

Fronteiras de ciclo = mtime dos arquivos .prova-leitura-cN.txt (o nonce é criado no
início de cada ciclo, antes do lançamento das lanes). Turno = mensagem `assistant`
com >=1 tool_use. Saída: uma linha por ciclo `cN: T turnos [ESTOURO >4]` + a taxa de
batching (tool_use por turno). Exit 0 = tudo dentro do teto · 1 = houve estouro ·
2 = uso/arquivo inválido. Medição, não freio: o estouro vira evento `incidente` no
run-log (quem chamou registra).
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


def main() -> None:
    if len(sys.argv) != 3:
        die("uso: conta-turnos.py <transcript.jsonl> <pareceres_dir>")
    transcript, pareceres = Path(sys.argv[1]), Path(sys.argv[2])
    if not transcript.is_file():
        die(f"transcript não encontrado: {transcript}")
    if not pareceres.is_dir():
        die(f"pareceres_dir não encontrado: {pareceres}")

    fronteiras = []  # (ciclo, ts_inicio)
    for f in pareceres.glob(".prova-leitura-c*.txt"):
        m = re.match(r"\.prova-leitura-c(\d+)\.txt$", f.name)
        if m:
            ts = datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc)
            fronteiras.append((int(m.group(1)), ts))
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
    sys.exit(1 if estouro else 0)


if __name__ == "__main__":
    main()
