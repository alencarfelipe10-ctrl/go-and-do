#!/usr/bin/env bash
# confere-ponteiros-plano.sh — FJ-F4RLR-02PLAN: irmã da MGTm-F4RLR-01INT (revalida-
# documentos.sh), agora para os PLANOS de uma fase. SÓ AVISA — nunca reprova o ciclo;
# o julgamento de trocar por nome de símbolo é do planner/hospedeiro.
#
# Três checagens, cada uma lendo <read_first> de cada <task> de cada NN-PLAN.md da fase:
#
#   (1) PONTEIRO-ONDA-ANTERIOR — o read_first cita `arquivo:linha`, e esse arquivo está
#       em `files_modified` de um plano de ONDA ANTERIOR (roda antes, no mesmo despacho
#       dependency-aware). O número de linha citado pode já estar errado quando este
#       plano de fato lê o arquivo — a onda anterior reescreveu o arquivo antes.
#
#   (2) SECAO-FORA-DA-POSICAO — o read_first cita "§N, linhas X-Y" (ou "linhas X-Y") de
#       um documento .md da fase; confere se a posição real do título §N (ou do heading
#       mais próximo) bate com X-Y. FM-F27INS-03PLAN: quando §N não é título de verdade
#       mas uma decisão D-NN citada como item de lista (`§Atalhos D-14`), procura a
#       posição do item `D-14` em vez de reclamar — os planos citam D-NN assim (mesmo
#       formato do confere-plano.sh). Ponteiro de linha citando outro ARQUIVO cujo dono é
#       outra ferramenta (spot-check-ponteiros.sh) fica fora daqui — o foco é a seção.
#
#   (3) CITACAO-CODIGO-FORA-DO-ARQUIVO — FM-F27INS-03PLAN (metade parcial — ver nota):
#       o read_first cita `arquivo:linha` de código (não `.md` — isso é a checagem 2) e
#       o arquivo citado, no disco, tem MENOS linhas do que o número citado — piso de
#       LIMITE (a linha existe?), nunca de CONTEÚDO (a linha diz o que a citação afirma?).
#       Ignora arquivo que está em `files_modified` de QUALQUER plano da fase (risco
#       anotado na melhoria aprovada: ele está para mudar, o número de linha de HOJE não é
#       critério de nada).
#       NOTA (conferido contra o INS-27-executavel-windows real, 26/09): os 3 ponteiros
#       deslocados citados na melhoria (`ship.py:502→503`, `conftest.py:57→59`,
#       `test_bat_commands.py:23-25→25-26`) NÃO estão em `<read_first>` de PLAN.md — estão
#       na tabela de "source-grounding pass" do 27-REVIEWS.md (achado da CONVERGÊNCIA, um
#       artefato e um agente diferentes). Esta checagem não os pega, e não pegaria mesmo
#       sem o filtro de files_modified: as 3 linhas citadas EXISTEM no arquivo (só o
#       conteúdo mudou 1-2 linhas) — checagem de limite não vê isso, precisaria comparar
#       conteúdo ou exigir citação por símbolo (`arquivo.py#simbolo`, já usado nos
#       `<read_first>` reais desta fase). O ganho real desta checagem (3) é mais estreito:
#       pegar citação de código apontando para FORA do arquivo (typo grosseiro de linha),
#       não deslocamento fino de conteúdo. Descrito para o coordenador no relatório da L4.
#
# Uso: confere-ponteiros-plano.sh <phase_dir>
# Saída: JSON de 1 linha {"avisos":[{codigo,plano,detalhe}], "total":N}. Exit sempre 0.

set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gsd-shim.sh" 2>/dev/null \
  && trap 'gad_autoregistro "confere-ponteiros-plano.sh" "$?"' EXIT || true

PD="${1:-}"
[ -n "$PD" ] && [ -d "$PD" ] || { echo "uso: confere-ponteiros-plano.sh <phase_dir>" >&2; exit 2; }
command -v jq >/dev/null || { echo "ERRO: jq ausente" >&2; exit 2; }
ROOT="$(cd "$PD" && git rev-parse --show-toplevel 2>/dev/null || echo "$PD")"

JSON=$(python3 - "$PD" "$ROOT" <<'PY'
import glob, json, os, re, sys

PD, ROOT = sys.argv[1], sys.argv[2]

def frontmatter(txt):
    m = re.match(r'^---\n(.*?\n)---\n', txt, re.S)
    return m.group(1) if m else ""

def campo_lista(fm, chave):
    m = re.search(rf'^{chave}:\s*\[(.*?)\]\s*$', fm, re.M)
    if m:
        return [x.strip().strip('"\'') for x in m.group(1).split(",") if x.strip()]
    m = re.search(rf'^{chave}:\s*\n((?:[ \t]+-[^\n]*\n?)+)', fm, re.M)
    if not m:
        return []
    return [re.sub(r'^[ \t]+-[ \t]*', '', l).strip().strip('"\'')
            for l in m.group(1).splitlines() if l.strip()]

def campo_num(fm, chave):
    m = re.search(rf'^{chave}:\s*(\d+)', fm, re.M)
    return int(m.group(1)) if m else None

planos = []  # {arquivo, wave, files_modified, read_first:[str]}
for f in sorted(glob.glob(os.path.join(PD, "*-PLAN.md"))):
    txt = open(f, encoding="utf-8", errors="replace").read()
    fm = frontmatter(txt)
    wave = campo_num(fm, "wave")
    fmod = campo_lista(fm, "files_modified")
    rf = []
    for bloco in re.findall(r'<read_first>(.*?)</read_first>', txt, re.S):
        for linha in bloco.splitlines():
            linha = re.sub(r'^\s*-\s*', '', linha).strip()
            if linha:
                rf.append(linha)
    planos.append({"arquivo": os.path.basename(f), "wave": wave,
                    "files_modified": fmod, "read_first": rf})

avisos = []

# ── (1) PONTEIRO-ONDA-ANTERIOR ───────────────────────────────────────────────
RE_PTR = re.compile(r'([\w./-]+\.[A-Za-z0-9_]+):(\d+)')
for p in planos:
    if p["wave"] is None:
        continue
    for outro in planos:
        if outro["wave"] is None or outro["wave"] >= p["wave"]:
            continue
        anteriores = set(os.path.basename(x) for x in outro["files_modified"])
        for linha in p["read_first"]:
            for m in RE_PTR.finditer(linha):
                caminho, num = m.group(1), m.group(2)
                if os.path.basename(caminho) in anteriores:
                    avisos.append({
                        "codigo": "PONTEIRO-ONDA-ANTERIOR",
                        "plano": p["arquivo"],
                        "detalhe": f"read_first cita {caminho}:{num}, que {outro['arquivo']} "
                                   f"(onda {outro['wave']}, antes da onda {p['wave']} deste plano) "
                                   "reescreve antes deste plano rodar — o número de linha pode já estar errado"
                    })

# ── (2) SECAO-FORA-DA-POSICAO ────────────────────────────────────────────────
RE_SECAO = re.compile(r'([\w./-]+\.md)\s+§([\w.\-À-ÿ ]+?),?\s*linhas?\s+(\d+)\s*[-–]\s*(\d+)')
RE_DNN = re.compile(r'\bD-(\d+)\b')
for p in planos:
    for linha in p["read_first"]:
        m = RE_SECAO.search(linha)
        if not m:
            continue
        doc, secao, x, y = m.group(1), m.group(2).strip(), int(m.group(3)), int(m.group(4))
        alvo = doc if os.path.isabs(doc) else os.path.join(ROOT, doc)
        if not os.path.isfile(alvo):
            alvo2 = os.path.join(PD, os.path.basename(doc))
            alvo = alvo2 if os.path.isfile(alvo2) else alvo
        if not os.path.isfile(alvo):
            continue
        conteudo = open(alvo, encoding="utf-8", errors="replace").read().splitlines()
        achou = None
        for i, l in enumerate(conteudo, 1):
            if re.match(r'^#{1,4}\s*' + re.escape(secao), l) or secao.lower() in l.lower():
                achou = i
                break
        # FM-F27INS-03PLAN: §N não é título — é uma decisão D-NN citada como item de
        # lista (ex.: «§Atalhos D-14»). Procura o item «D-14» (bullet, não heading)
        # antes de reclamar de "nenhum título encontrado".
        if achou is None:
            m_dnn = RE_DNN.search(secao)
            if m_dnn:
                dnn = f"D-{m_dnn.group(1)}"
                for i, l in enumerate(conteudo, 1):
                    if re.match(r'^\s*[-*]\s*\**' + re.escape(dnn) + r'\b', l):
                        achou = i
                        break
        if achou is None:
            avisos.append({"codigo": "SECAO-FORA-DA-POSICAO", "plano": p["arquivo"],
                            "detalhe": f"read_first cita §{secao} em {doc} (linhas {x}-{y}), "
                                       "mas nenhum título (nem item D-NN) com esse texto foi encontrado no arquivo"})
        elif abs(achou - x) > 10:
            avisos.append({"codigo": "SECAO-FORA-DA-POSICAO", "plano": p["arquivo"],
                            "detalhe": f"read_first cita §{secao} em {doc} como linhas {x}-{y}, "
                                       f"mas o título/item real está na linha {achou}"})

# ── (3) CITACAO-CODIGO-FORA-DO-ARQUIVO ───────────────────────────────────────
# FM-F27INS-03PLAN: confere as citações `arquivo:linha` de CÓDIGO (não .md, isso é a
# checagem 2 acima) contra o tamanho real do arquivo no disco. Ignora qualquer caminho
# que apareça em `files_modified` de QUALQUER plano da fase — o risco anotado na
# melhoria aprovada: esses arquivos estão para mudar, então checar contra o estado de
# HOJE geraria aviso num arquivo que a própria fase vai reescrever.
TODOS_MODIFICADOS = set()
for p in planos:
    for f in p["files_modified"]:
        TODOS_MODIFICADOS.add(os.path.basename(f))

for p in planos:
    for linha in p["read_first"]:
        for m in RE_PTR.finditer(linha):
            caminho, num_s = m.group(1), m.group(2)
            if caminho.endswith(".md"):
                continue  # é a checagem 2 (seção), não código
            if os.path.basename(caminho) in TODOS_MODIFICADOS:
                continue
            num = int(num_s)
            alvo = caminho if os.path.isabs(caminho) else os.path.join(ROOT, caminho)
            if not os.path.isfile(alvo):
                continue
            n_linhas = sum(1 for _ in open(alvo, encoding="utf-8", errors="replace"))
            if num > n_linhas:
                avisos.append({
                    "codigo": "CITACAO-CODIGO-FORA-DO-ARQUIVO",
                    "plano": p["arquivo"],
                    "detalhe": f"read_first cita {caminho}:{num}, mas o arquivo tem só {n_linhas} linha(s)"
                })

print(json.dumps({"avisos": avisos, "total": len(avisos)}, ensure_ascii=False))
PY
)
gad_json_out confere-ponteiros-plano "$JSON" || echo "$JSON"
exit 0
