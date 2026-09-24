#!/usr/bin/env python3
"""pos-ship.py — balde «observação pós-ship» do UAT (v2.7.0).

Origem: F4 rl-representation (20/09/2026). 7 cenários caíram no balde 3 e travaram o
ship; 5 deles perguntavam COMO A PRODUÇÃO SE COMPORTA (forma real de uma API externa,
frequência de um veredito no piloto) — pergunta que só tem resposta DEPOIS do ship.
A mecânica estava provada por teste; o que faltava não existe antes do deploy.

Por que ARQUIVO PRÓPRIO e não um `result:` novo no NN-UAT.md: o predicado nativo
`phase uat-passed` só aceita `pass`/`passed` — qualquer outro valor bloqueia o ship
(medido no uat-predicate.cjs). O item sai do NN-UAT.md e passa a morar em
NN-POS-SHIP.md, que o predicado não lê.

Anti-fuga (este balde NÃO é saída de emergência do balde 3): o `move` só leva o
cenário que cumpre TODAS as condições abaixo; o que falha em qualquer uma FICA no
NN-UAT.md como balde 3 e continua bloqueando o ship.
  1. `pos_ship: candidato` no bloco;
  2. `result:` é `blocked`/`[pending]` — nunca `pass`, `issue` ou `assumed`;
  3. `prova_mecanica:` aponta arquivo que EXISTE no projeto (a mecânica tem teste);
  4. `bloqueia_proxima:` é `sim` ou `nao`;
  5. `verificavel_em:` nomeia onde se observa;
  6. veredito `confirmado` para o cenário em `.pos-ship-vereditos.json` (formato novo: `.gad/pos-ship/vereditos.json`), gravado pelo
     verificador cético (prompts/uat-pos-ship.md) — quem classifica não é quem julga.

Subcomandos (saída = JSON de 1 linha):
  move     <phase_dir> <NN> <project_root>   move os candidatos válidos; exit 0 sempre que rodou
                                             sem candidato malformado (ver abaixo)
  conferir <phase_dir> <NN> <project_root>   FJ-F4RLR-06UAT: mesma checagem de formato do `move`,
                                             mas NUNCA escreve nada — roda antes do cético
                                             (workflow-etapa-5.md §5.6 passo 2). Exit 1 = há candidato
                                             malformado; o condutor devolve antes de despachar.
  lista    <phase_dir> <NN>                  itens do NN-POS-SHIP.md (para o resumo/banner)
  gate     <project_root> <fase>             Etapa 0: itens `bloqueia_proxima: sim` ainda não
                                             observados em OUTRAS fases → exit 1. Isenta a fase
                                             nomeada no `verificavel_em` do item (é nela que o
                                             item se observa).

FM-F4RLR-07UAT: se «pos_ship: candidato» aparece N vezes no NN-UAT.md e o script só
reconhece < N como candidato bem formado, `move`/`conferir` saem com exit 1 e o JSON traz
`malformados` (cenário + motivo) em vez de mover em silêncio o que dá para mover. Dois
jeitos de um marcador escapar do reconhecimento: (a) o campo `pos_ship:` está indentado —
a mesma régua do predicado nativo só lê coluna 0, então o marcador vira invisível; (b) o
candidato foi reconhecido mas uma «sonda» obrigatória (prova_mecanica/bloqueia_proxima/
verificavel_em) está de todo ausente (string vazia), não apenas com valor inválido — valor
presente e inválido (ex.: `bloqueia_proxima: talvez`) ou prova que não existe no repo
continuam no fluxo normal de `recusados` (exit 0), pois isso é a mecânica de elegibilidade
funcionando, não malformação.
Exit: 0 ok · 1 gate reprovou / há candidato malformado · 2 uso inválido.
"""

import json
import re
import sys
from datetime import datetime
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import gad_caminhos  # noqa: E402 — v2.10.1: caminhos da fase (formato novo × antigo)

RE_TITULO = re.compile(r"^###\s*(\d+)\.\s*(.+)$")
RE_FASE = re.compile(r"[Ff]ase\s+([0-9]+(?:\.[0-9]+)?)")
RE_MARCADOR_INDENTADO = re.compile(r"^([ \t]+)pos_ship:\s*candidato\s*$")
RESULT_ELEGIVEL = {"blocked", "[pending]", "pending"}


def _norm_fase(texto: str) -> str:
    """'04' == '4', '04.1' == '4.1' — comparação textual crua já furou (I-03)."""
    inteiro, _, resto = texto.strip().partition(".")
    inteiro = inteiro.lstrip("0") or "0"
    return f"{inteiro}.{resto}" if resto else inteiro


def _campo(linhas: list[str], nome: str) -> str:
    """Valor de `nome:` em coluna 0 (mesma régua do predicado nativo)."""
    for linha in linhas:
        if linha.startswith(f"{nome}:"):
            return linha.split(":", 1)[1].strip()
    return ""


def _blocos(texto: str) -> tuple[list[str], list[dict], list[str]]:
    """(prefácio, blocos `### N. título`, rodapé a partir do 1º `## ` após os blocos)."""
    linhas = texto.split("\n")
    prefacio: list[str] = []
    blocos: list[dict] = []
    rodape: list[str] = []
    atual: dict | None = None
    for i, linha in enumerate(linhas):
        m = RE_TITULO.match(linha)
        if m:
            atual = {"n": int(m.group(1)), "titulo": m.group(2).strip(), "linhas": [linha], "inicio": i}
            blocos.append(atual)
        elif atual is not None and linha.startswith("## "):
            rodape = linhas[i:]
            break
        elif atual is None:
            prefacio.append(linha)
        else:
            atual["linhas"].append(linha)
    return prefacio, blocos, rodape


def _vereditos(phase_dir: Path) -> dict[int, str]:
    arq = Path(gad_caminhos.caminho(str(phase_dir), "pos-ship/vereditos.json"))
    if not arq.is_file():
        return {}
    try:
        dados = json.loads(arq.read_text(encoding="utf-8"))
    except ValueError:
        return {}
    saida: dict[int, str] = {}
    for item in dados if isinstance(dados, list) else []:
        if isinstance(item, dict) and isinstance(item.get("cenario"), int):
            saida[item["cenario"]] = str(item.get("veredito", ""))
    return saida


def _malformados(texto: str, blocos: list[dict]) -> list[dict]:
    """FM-F4RLR-07UAT: candidatos que o parser não reconhece de jeito nenhum."""
    linhas = texto.split("\n")
    achados: list[dict] = []
    for i, linha in enumerate(linhas):
        m = RE_MARCADOR_INDENTADO.match(linha)
        if not m:
            continue
        dono = None
        for b in blocos:
            fim = b["inicio"] + len(b["linhas"])
            if b["inicio"] <= i < fim:
                dono = b
                break
        cenario = dono["n"] if dono else f"linha {i + 1}"
        achados.append({"cenario": cenario, "motivo": "campo pos_ship indentado (coluna 0 exigida)"})
    for b in blocos:
        if _campo(b["linhas"], "pos_ship") != "candidato":
            continue
        for campo, rotulo in (("prova_mecanica", "sonda (prova_mecanica) ausente"),
                               ("bloqueia_proxima", "bloqueia_proxima ausente"),
                               ("verificavel_em", "verificavel_em ausente")):
            if not _campo(b["linhas"], campo):
                achados.append({"cenario": b["n"], "motivo": rotulo})
    return achados


def _recusa(bloco: dict, vereditos: dict[int, str], raiz: Path) -> str | None:
    """Motivo pelo qual o candidato NÃO pode sair do balde 3; None = pode."""
    ls = bloco["linhas"]
    if _campo(ls, "result") not in RESULT_ELEGIVEL:
        return "result não é blocked/[pending]"
    prova = _campo(ls, "prova_mecanica").split(" ")[0].split("::")[0]
    if not prova:
        return "sem prova_mecanica"
    if not (raiz / prova).is_file():
        return f"prova_mecanica não existe: {prova}"
    if _campo(ls, "bloqueia_proxima").lower().replace("ã", "a") not in {"sim", "nao"}:
        return "bloqueia_proxima ausente ou fora de sim|nao"
    if not _campo(ls, "verificavel_em"):
        return "sem verificavel_em"
    if vereditos.get(bloco["n"]) != "confirmado":
        return "sem veredito confirmado do verificador"
    return None


def cmd_move(phase_dir: Path, nn: str, raiz: Path) -> int:
    uat = phase_dir / f"{nn}-UAT.md"
    if not uat.is_file():
        print(json.dumps({"movidos": [], "recusados": [], "motivo": "sem UAT.md"}))
        return 0
    texto = uat.read_text(encoding="utf-8")
    prefacio, blocos, rodape = _blocos(texto)
    malformados = _malformados(texto, blocos)
    if malformados:
        print(json.dumps({"malformados": malformados,
                          "motivo": "candidato(s) pos_ship malformado(s); nada foi movido"},
                         ensure_ascii=False))
        return 1
    vereditos = _vereditos(phase_dir)
    ficam, movidos, recusados = [], [], []
    for b in blocos:
        if _campo(b["linhas"], "pos_ship") != "candidato":
            ficam.append(b)
            continue
        motivo = _recusa(b, vereditos, raiz)
        if motivo:
            recusados.append({"cenario": b["n"], "motivo": motivo})
            ficam.append(b)
        else:
            movidos.append(b)
    if movidos:
        destino = phase_dir / f"{nn}-POS-SHIP.md"
        agora = datetime.now().astimezone().isoformat(timespec="seconds")
        partes = []
        if not destino.is_file():
            partes.append(
                f"# Observação pós-ship — fase {nn}\n\n"
                "Cenários cuja mecânica está provada por teste e cuja pergunta só tem resposta\n"
                "em produção. Não bloqueiam o ship desta fase. Item com `bloqueia_proxima: sim`\n"
                "bloqueia a abertura das fases seguintes (exceto a nomeada em `verificavel_em`)\n"
                "até ganhar `observado_em: <data> — <o que se viu>`.\n"
            )
        for b in movidos:
            corpo = [l for l in b["linhas"][1:]
                     if not l.startswith(("result:", "pos_ship:"))]
            while corpo and not corpo[-1].strip():
                corpo.pop()
            partes.append("\n".join(
                [f"### {nn}-{b['n']}. {b['titulo']}",
                 f"origem: {nn}-UAT.md cenário {b['n']}",
                 f"movido_em: {agora}",
                 "observado_em:"] + corpo) + "\n")
        with destino.open("a", encoding="utf-8") as f:
            f.write("\n" + "\n".join(partes))
        novo = prefacio + [l for b in ficam for l in b["linhas"]] + rodape
        uat.write_text("\n".join(novo), encoding="utf-8")
    print(json.dumps({
        "movidos": [b["n"] for b in movidos],
        "recusados": recusados,
        "restam_no_uat": len(ficam),
    }, ensure_ascii=False))
    return 0


def cmd_conferir(phase_dir: Path, nn: str, raiz: Path) -> int:
    """FJ-F4RLR-06UAT: mesma checagem de `move`, nunca escreve — para rodar antes do cético."""
    uat = phase_dir / f"{nn}-UAT.md"
    if not uat.is_file():
        print(json.dumps({"malformados": [], "motivo": "sem UAT.md"}))
        return 0
    texto = uat.read_text(encoding="utf-8")
    _, blocos, _ = _blocos(texto)
    malformados = _malformados(texto, blocos)
    if malformados:
        print(json.dumps({"malformados": malformados}, ensure_ascii=False))
        return 1
    print(json.dumps({"malformados": []}))
    return 0


def _itens(arq: Path) -> list[dict]:
    # no POS-SHIP o título é `### NN-n. …` — de propósito fora da régua `### N.` do UAT
    itens = []
    atual: dict | None = None
    for linha in arq.read_text(encoding="utf-8").split("\n"):
        if linha.startswith("### "):
            atual = {"titulo": linha[4:].strip(), "linhas": []}
            itens.append(atual)
        elif atual is not None:
            atual["linhas"].append(linha)
    saida = []
    for it in itens:
        ls = it["linhas"]
        saida.append({
            "titulo": it["titulo"],
            "bloqueia_proxima": _campo(ls, "bloqueia_proxima").lower().replace("ã", "a") == "sim",
            "verificavel_em": _campo(ls, "verificavel_em"),
            "observado": bool(_campo(ls, "observado_em")),
        })
    return saida


def cmd_lista(phase_dir: Path, nn: str) -> int:
    arq = phase_dir / f"{nn}-POS-SHIP.md"
    itens = _itens(arq) if arq.is_file() else []
    print(json.dumps({
        "total": len(itens),
        "bloqueiam_proxima": sum(1 for i in itens if i["bloqueia_proxima"] and not i["observado"]),
        "itens": itens,
    }, ensure_ascii=False))
    return 0


def cmd_gate(raiz: Path, fase: str) -> int:
    alvo = _norm_fase(fase)
    pendentes = []
    for arq in sorted((raiz / ".planning" / "phases").glob("*/*-POS-SHIP.md")):
        dona = re.match(r"([0-9]+(?:\.[0-9]+)?)-POS-SHIP\.md$", arq.name)
        if dona and _norm_fase(dona.group(1)) == alvo:
            continue  # a própria fase não se bloqueia
        for it in _itens(arq):
            if not it["bloqueia_proxima"] or it["observado"]:
                continue
            m = RE_FASE.search(it["verificavel_em"])
            if m and _norm_fase(m.group(1)) == alvo:
                continue  # é NESTA fase que o item se observa
            pendentes.append({"arquivo": str(arq.relative_to(raiz)), "item": it["titulo"],
                              "verificavel_em": it["verificavel_em"]})
    print(json.dumps({"fase": fase, "veredito": "falha" if pendentes else "ok",
                      "pendentes": pendentes}, ensure_ascii=False))
    return 1 if pendentes else 0


def main(argv: list[str]) -> int:
    try:
        if argv[1] == "move" and len(argv) == 5:
            return cmd_move(Path(argv[2]), argv[3], Path(argv[4]))
        if argv[1] in ("conferir", "--conferir") and len(argv) == 5:
            return cmd_conferir(Path(argv[2]), argv[3], Path(argv[4]))
        if argv[1] == "lista" and len(argv) == 4:
            return cmd_lista(Path(argv[2]), argv[3])
        if argv[1] == "gate" and len(argv) == 4:
            return cmd_gate(Path(argv[2]), argv[3])
    except IndexError:
        pass
    print("uso: pos-ship.py move <phase_dir> <NN> <root> | conferir <phase_dir> <NN> <root> "
          "| lista <phase_dir> <NN> | gate <root> <fase>",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
