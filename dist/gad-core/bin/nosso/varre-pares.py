#!/usr/bin/env python3
"""varre-pares.py — varredura par a par de arquivos por onda, ANTES do plan-checker
(fork gen5-patches, tarefa 48/h, 23/09/2026).

Complementa o §13a-bis (`plan-gate.py`), que roda DEPOIS do checker aprovar, bloqueia, e só
enxerga `files_modified` × `files_modified` (via `gad_run query phase-plan-index`). Este
script lê os `*-PLAN.md` de uma fase DIRETO DO DISCO (sem depender do gad-tools instalado),
roda ANTES do 1º despacho do checker e de novo a cada correção, e enxerga um caso a mais:
A MODIFICA um arquivo que B LÊ (não só que B também modifica) — na mesma onda declarada.

É sino, nunca gate: a saída vira uma sonda informativa no briefing do checker
(`<pair_conflict_probe>`, plan-phase/blocks/checker.md step 10), nunca reprova a fase — quem
decide o que fazer com um par conflitante é o checker (dimensão de julgamento) ou o humano.

Onda: o `wave:` DECLARADO no frontmatter de cada plano (o planner escreve; o §13a-bis já
reconcilia `wave:` declarado × DAG de `depends_on` via WAVE-DECLARADA-DIVERGE — não duplicado
aqui). Leitura: fonte primária é o campo formal `<read_first>` por `<task>` (a única declaração
estruturada de leitura que o molde do PLAN.md tem — ver `agents/gad-planner.md:361`,
`path/to/file.ext#symbol · NN-SPEC.md §Section, lines a-b`); quando um plano não usa
`<read_first>` nenhuma vez, cai para citações de caminho de arquivo soltas no corpo (mesma
forma de token que a sonda de lastro do plan-gate.py usa), sempre excluindo o que o próprio
plano já declara como `files_modified`/`files_deleted` (modificar não é "ler de outro").

Uso:
  varre-pares.py <phase_dir> [--out ARQ | --no-out]

Saída (stdout): JSON {pares: [{onda, planos:[A,B], arquivo, tipo}], planos_sem_wave: [...],
resumo: {...}}. `tipo` é `modifica-modifica` (mesmo achado que SOBREPOSICAO-NA-ONDA do
plan-gate.py reprovaria mais tarde — sinalizado aqui cedo, sem reprovar) ou
`<id>-modifica-<id>-le` (A modifica, B lê; sempre nomeando quem faz o quê).

Exit: sempre 0 (nunca bloqueia — é sino; erro de uso/entrada ainda sai 2, como as outras
ferramentas de `bin/nosso/`).
"""
import argparse
import json
import os
import re
import sys

RE_TASK = re.compile(r"<task\b([^>]*)>(.*?)</task>", re.S)
RE_READ_FIRST = re.compile(r"<read_first>(.*?)</read_first>", re.S)
# token de arquivo: precisa de extensão reconhecida OU barra de caminho, para não casar prosa
RE_FILE = re.compile(
    r"[\w][\w/.\-]*\.(?:py|js|jsx|ts|tsx|cjs|mjs|md|json|yaml|yml|sh|sql|toml|html|css|txt|cfg|ini|env)\b"
    r"|[\w][\w\-]*(?:/[\w][\w.\-]*)+"
)


def ler_frontmatter(texto):
    """Leitor mínimo de YAML de frontmatter: escalares, listas inline e listas em bloco de
    1º nível — só os campos que este script usa (wave, files_modified, files_deleted). Mesma
    forma do leitor em plan-gate.py (fork gen5-patches, P13); duplicado aqui de propósito —
    nome de arquivo com hífen não importa limpo, e são ~30 linhas."""
    if not texto.startswith("---"):
        return {}, texto
    fim = texto.find("\n---", 3)
    if fim < 0:
        return {}, texto
    bloco = texto[3:fim]
    corpo = texto[fim + 4:]
    fm = {}
    chave = None
    for linha in bloco.splitlines():
        if not linha.strip() or linha.lstrip().startswith("#"):
            continue
        if not linha.startswith((" ", "\t")):
            m = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", linha)
            if not m:
                chave = None
                continue
            chave, val = m.group(1), m.group(2).strip()
            if val.startswith("["):
                itens = val.strip("[]").split(",")
                fm[chave] = [i.strip().strip("'\"") for i in itens if i.strip()]
            elif val == "":
                fm[chave] = []
            else:
                fm[chave] = val.strip("'\"")
        elif chave is not None and isinstance(fm.get(chave), list):
            s = linha.strip()
            if s.startswith("- "):
                fm[chave].append(s[2:].strip().strip("'\""))
    return fm, corpo


def arquivos_citados(texto):
    return {m.group(0).strip("`") for m in RE_FILE.finditer(texto)}


def le_do_plano(corpo, modificados):
    """Arquivos que o plano LÊ: união dos `<read_first>` de cada `<task>`; se nenhuma
    `<task>` do plano usa `<read_first>`, cai para citações de caminho soltas no corpo
    inteiro. Nunca conta o que o próprio plano modifica."""
    tasks = RE_TASK.findall(corpo)
    lidos = set()
    achou_read_first = False
    for _attrs, miolo in tasks:
        for m in RE_READ_FIRST.finditer(miolo):
            achou_read_first = True
            lidos |= arquivos_citados(m.group(1))
    if not achou_read_first:
        lidos = arquivos_citados(corpo)
    return lidos - modificados


def carregar_planos(phase_dir):
    planos = {}
    for f in sorted(os.listdir(phase_dir)):
        if not f.endswith("-PLAN.md"):
            continue
        caminho = os.path.join(phase_dir, f)
        with open(caminho, encoding="utf-8") as fh:
            texto = fh.read()
        fm, corpo = ler_frontmatter(texto)
        pid = f[: -len("-PLAN.md")]
        modifica = set(fm.get("files_modified") or []) | set(fm.get("files_deleted") or [])
        wave = fm.get("wave")
        wave = str(wave).strip() if wave not in (None, "") else None
        planos[pid] = {"wave": wave, "modifica": modifica, "le": le_do_plano(corpo, modifica)}
    return planos


def varrer(planos):
    pares = []
    sem_wave = sorted(pid for pid, info in planos.items() if not info["wave"])
    por_onda = {}
    for pid, info in planos.items():
        if not info["wave"]:
            continue
        por_onda.setdefault(info["wave"], []).append(pid)
    for onda in sorted(por_onda):
        ids = sorted(por_onda[onda])
        for i in range(len(ids)):
            for j in range(i + 1, len(ids)):
                a, b = ids[i], ids[j]
                for arq in sorted(planos[a]["modifica"] & planos[b]["modifica"]):
                    pares.append({"onda": onda, "planos": [a, b], "arquivo": arq,
                                  "tipo": "modifica-modifica"})
                for arq in sorted(planos[a]["modifica"] & planos[b]["le"]):
                    pares.append({"onda": onda, "planos": [a, b], "arquivo": arq,
                                  "tipo": f"{a}-modifica-{b}-le"})
                for arq in sorted(planos[b]["modifica"] & planos[a]["le"]):
                    pares.append({"onda": onda, "planos": [a, b], "arquivo": arq,
                                  "tipo": f"{b}-modifica-{a}-le"})
    return pares, sem_wave


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("phase_dir")
    ap.add_argument("--out", default=None, help="arquivo JSON de saída, além do stdout")
    ap.add_argument("--no-out", action="store_true")
    a = ap.parse_args()

    if not os.path.isdir(a.phase_dir):
        print(f"erro: phase_dir não existe: {a.phase_dir}", file=sys.stderr)
        return 2

    planos = carregar_planos(a.phase_dir)
    pares, sem_wave = varrer(planos)
    saida = {
        "pares": pares,
        "planos_sem_wave": sem_wave,
        "resumo": {"planos": len(planos), "pares_conflitantes": len(pares)},
    }
    txt = json.dumps(saida, ensure_ascii=False, indent=2)
    print(txt)
    if not a.no_out and a.out:
        try:
            os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
            with open(a.out, "w", encoding="utf-8") as fh:
                fh.write(txt + "\n")
        except OSError as e:
            print(f"aviso: não gravei {a.out}: {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
