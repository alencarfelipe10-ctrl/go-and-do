#!/usr/bin/env bash
# digest-onda.sh — digest dos planos das ondas ANTERIORES a uma onda, para o bloco
# <prior_waves_digest> do despacho do executor (tarefa 47 b, item 3B-03, 11/09/2026).
#
# Por que existe: montar esse digest "em prosa" faz o orquestrador abrir os SUMMARYs inteiros —
# na F24.5 eram 489.648 B (18,1 % do piso de leitura de cada executor, 45,3 % do último). O
# script lê o disco e imprime ≤ 15 linhas por plano; o host não entra no texto.
#
# Uso: digest-onda.sh <phase_dir> <onda>
#   <phase_dir>  diretório da fase (com os *-PLAN.md e *-SUMMARY.md)
#   <onda>       a onda que está para ser despachada; o digest cobre as ondas < onda
# Saída: stdout, texto puro (vazio quando não há onda anterior). Teto de 20.480 B (regra P18).
set -u

DIR="${1:-}"; ONDA="${2:-}"
if [ -z "$DIR" ] || [ -z "$ONDA" ]; then
  echo "uso: digest-onda.sh <phase_dir> <onda>" >&2
  exit 2
fi
[ -d "$DIR" ] || { echo "ERRO: phase_dir inexistente: $DIR" >&2; exit 2; }
case "$ONDA" in (*[!0-9]*|"") echo "ERRO: onda não numérica: $ONDA" >&2; exit 2;; esac

DIR="$DIR" ONDA="$ONDA" python3 - <<'PY'
import os, re, glob

dir_fase = os.environ["DIR"]
onda_alvo = int(os.environ["ONDA"])
TETO_LINHAS_POR_PLANO = 15


def frontmatter(caminho):
    """Devolve as linhas do frontmatter YAML (sem os delimitadores)."""
    try:
        linhas = open(caminho, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return []
    if not linhas or linhas[0].strip() != "---":
        return []
    fim = next((i for i, l in enumerate(linhas[1:], 1) if l.strip() == "---"), None)
    return linhas[1:fim] if fim else []


def escalar(linhas, chave):
    for l in linhas:
        if l.startswith(chave + ":"):
            return l[len(chave) + 1:].strip().strip("\"'")
    return ""


def lista_aninhada(linhas, chave):
    """Itens de `chave:` — aceita sublistas nomeadas (created:/modified:) e itens diretos."""
    itens, dentro, base = [], False, None
    for l in linhas:
        if l.startswith(chave + ":"):
            dentro, base = True, len(l) - len(l.lstrip())
            continue
        if not dentro:
            continue
        if l.strip() and (len(l) - len(l.lstrip())) <= base:
            break
        t = l.strip()
        if t.startswith("-"):
            itens.append(t[1:].strip().strip("\"'"))
    return itens


def secao(caminho, titulo):
    """Linhas de uma seção `## <titulo>` até o próximo heading de mesmo nível."""
    try:
        linhas = open(caminho, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return []
    out, dentro = [], False
    for l in linhas:
        if l.startswith("## "):
            if dentro:
                break
            dentro = l[3:].strip().lower().startswith(titulo.lower())
            continue
        if dentro:
            out.append(l)
    return out


def deferrals_do_plano(dir_fase, pid):
    """Entradas do deferred-items.md sob `## Plano <pid>` (o id vem com ou sem o prefixo da fase)."""
    caminho = os.path.join(dir_fase, "deferred-items.md")
    if not os.path.isfile(caminho):
        return []
    curto = pid.split("-")[-1]
    out, dentro = [], False
    for l in open(caminho, encoding="utf-8", errors="replace").read().splitlines():
        if l.startswith("## "):
            alvo = l[3:].strip()
            dentro = alvo.endswith(pid) or alvo.endswith(curto)
            continue
        if dentro and l.lstrip().startswith("-"):
            out.append(re.sub(r"\s+", " ", l.lstrip()[1:].strip().strip("*")))
    return out


planos = []
for p in sorted(glob.glob(os.path.join(dir_fase, "*-PLAN.md"))):
    fm = frontmatter(p)
    onda = escalar(fm, "wave")
    if not onda.isdigit() or int(onda) >= onda_alvo:
        continue
    pid = os.path.basename(p)[: -len("-PLAN.md")]
    planos.append((int(onda), pid, p))

if not planos:
    raise SystemExit(0)

blocos = []
for onda, pid, caminho_plan in sorted(planos):
    s = caminho_plan[: -len("-PLAN.md")] + "-SUMMARY.md"
    linhas = ["plano %s · onda %d" % (pid, onda)]
    if not os.path.isfile(s):
        linhas.append("  (sem SUMMARY — plano não fechou)")
        blocos.append("\n".join(linhas))
        continue

    fm = frontmatter(s)
    entregou = [x for x in lista_aninhada(fm, "key-files") if "/" in x or "." in x]
    if not entregou:
        entregou = [l.strip()[1:].strip().split(" - ")[0].strip("`")
                    for l in secao(s, "Files Created/Modified") if l.strip().startswith("-")]
    if entregou:
        linhas.append("  entregou: " + ", ".join(entregou[:8]))

    simbolos = []
    for l in secao(s, "Task Commits"):
        m = re.match(r"\s*\d+\.\s+\*\*(.+?)\*\*", l)
        if m:
            simbolos.append(re.sub(r"\s+", " ", m.group(1)))
    for t in simbolos[:4]:
        linhas.append("  tarefa: " + t[:160])

    # só os títulos em negrito das deviations; os headings `### Auto-fixed Issues`, o
    # `**Total deviations:**` e o `**Impact on plan:**` são moldura, não desvio.
    desvios = [re.sub(r"\s+", " ", l.strip())
               for l in secao(s, "Deviations from Plan")
               if l.strip().startswith("**")
               and not l.strip().startswith(("**Total deviations", "**Impact on plan"))]
    for d in desvios[:3]:
        linhas.append("  desvio: " + d.strip("*# ")[:160])

    for d in deferrals_do_plano(dir_fase, pid)[:3]:
        linhas.append("  deferral: " + d[:160])

    blocos.append("\n".join(linhas[:TETO_LINHAS_POR_PLANO]))

saida = "\n".join(blocos)
TETO = 20480
if len(saida.encode("utf-8")) > TETO:
    saida = saida.encode("utf-8")[:TETO].decode("utf-8", "ignore")
    saida += "\n[digest truncado no teto de 20.480 B — abra os SUMMARYs que faltam por nome]"
print(saida)
PY
