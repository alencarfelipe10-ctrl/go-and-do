#!/usr/bin/env bash
# confere-sinos.sh — gate mecânico: nenhum sino pode ficar "aberto" quando a etapa
# de intenção fecha (item C3 do plano de consertos F24.4).
#
# O que já está certo e este script NÃO mexe: `briefing-build.sh:183-191` valida
# `.ciclo0.json` linha a linha — `corrigido` exige `correcao_id`; `aberto` PROÍBE
# `correcao_id`. Um sino aberto sem correcao_id é comportamento desenhado (carrega
# para o briefing do ciclo seguinte via revalidação dirigida — R3). O buraco real é
# outro: quando não há próximo ciclo (teto de ciclos atingido, ou o dono fecha a
# etapa), o sino aberto some sem que ninguém o conte. Este script é esse contador.
#
# Schema replicado de `briefing-build.sh:155-194` (não inventamos um schema novo):
#   .ciclo0.json = {v:1, sinos:[{id, origem, disposicao, correcao_id?, destino?}], ...}
#   disposicao ∈ {corrigido, descartado, aberto, levado_aos_consultores};
#   só "corrigido" tem correcao_id; só "levado_aos_consultores" tem destino.
#
# `levado_aos_consultores` (FM-F27INS-09INT, tarefa 59 b5) — o estado FINAL de um sino do
# ciclo 0 que foi entregue à consultoria e lá virou achado ou dívida. Antes dele o único
# estado aprovável no fecho, sem correção no ciclo 0, era «descartado» — e na F27 INS o
# coordenador reescreveu três sinos aberto→descartado (c0-01 tinha virado o achado corrigido
# c1-02; c0-02/c0-03, dívidas). Exige `destino` = o id em que o sino se transformou (um achado
# `c<N>-NN` ou uma dívida — pode ser o próprio id do sino). Destino vazio reprova; quando a fase
# tem INTENT-REVIEW ou vereditos no disco, o id tem de aparecer em um deles (senão é
# destino inventado) → `SINOS-SEM-DESTINO`, exit 1, mesmo gate dos abertos.
# O schema de sinos NÃO tem campo "texto" — id/origem/disposicao/correcao_id é tudo
# que existe hoje. A saída deste script usa id + origem + o ciclo do arquivo de
# onde o sino veio (a informação mais próxima de "texto" disponível no schema real).
#
# Hoje só `.ciclo0.json` carrega uma lista `sinos[]` — ciclos >= 1 não têm um
# `.cicloN.json` próprio (a revalidação deles vive em `.sinos-*.txt`, formato de
# texto, fora do escopo deste gate). Este script varre por precaução qualquer
# `.cicloN.json` (N >= 0) que aparecer em `.intent/`, para não quebrar se um dia
# passar a existir, mas hoje só encontrará o do ciclo 0.
#
# Uso: confere-sinos.sh <phase_dir>
#
# Exit 0 = zero sinos abertos (ou nenhum .cicloN.json — fase sem sinos é legítima).
# Exit 1 = há sino(s) `aberto` sobrando ao fim da etapa de intenção, ou sino
#          `levado_aos_consultores` sem destino (vazio ou inexistente nos artefatos).
# Exit 2 = uso inválido, phase_dir inexistente, ou algum `.cicloN.json` ilegível.
#
# Somente leitura: nunca escreve nada em disco.

set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gsd-shim.sh" 2>/dev/null && trap 'gad_autoregistro "confere-sinos.sh" "$?"' EXIT || true

PD="${1:-}"
[ -n "$PD" ] || { echo "uso: confere-sinos.sh <phase_dir>" >&2; exit 2; }
[ -d "$PD" ] || { echo "ERRO: phase_dir inexistente: $PD" >&2; exit 2; }

# v2.10.1 (57): helper de caminhos (formato da fase).
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gad-caminhos.sh"
IN="$(gad_fase_caminho "$PD" intent)"

# Nem procuramos arquivo se o diretório .intent/ nem existe — fase sem etapa de
# intenção rodada ainda é caso legítimo de "sem sinos", não erro.
if [ ! -d "$IN" ]; then
  echo "sinos_abertos: n/a (sem .ciclo0.json)"
  exit 0
fi

# shellcheck disable=SC2012
ARQS=$(gad_fase_glob "$PD" 'intent/c[0-9]*/ciclo.json' | sort -V)
if [ -z "$ARQS" ]; then
  echo "sinos_abertos: n/a (sem .ciclo0.json)"
  exit 0
fi

SAIDA=$(GAD_ARQS="$ARQS" GAD_PD="$PD" GAD_LIB="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib" python3 - <<'PY'
import json, os, sys

arqs = [a for a in os.environ["GAD_ARQS"].splitlines() if a]

def erro(msg):
    print("ERRO: %s" % msg)
    sys.exit(2)

abertos = []  # (id, origem, ciclo)
sem_destino = []  # (id, destino, motivo)
total_sinos = 0
DISPOSICOES = ("corrigido", "descartado", "aberto", "levado_aos_consultores")

# Onde o destino de um sino levado aos consultores pode aparecer: a coluna de id dos
# vereditos de qualquer ciclo e o texto do NN-INTENT-REVIEW.md (tabela de achados e
# «Dívidas registradas»). Sem nenhuma das fontes, só a forma (não vazio) é conferida.
import glob, re
sys.dont_write_bytecode = True
sys.path.insert(0, os.environ["GAD_LIB"])
import gad_caminhos
PD = os.environ["GAD_PD"]
ids_vereditos = set()
for f in gad_caminhos.glob_fase(PD, "intent/c*/vereditos.txt"):
    for linha in open(f, encoding="utf-8", errors="replace"):
        cel = linha.split("|")[0].strip()
        if cel and not cel.startswith("#"):
            ids_vereditos.add(cel)
texto_ir = ""
for f in sorted(glob.glob(os.path.join(PD, "*-INTENT-REVIEW.md"))):
    texto_ir += open(f, encoding="utf-8", errors="replace").read() + "\n"
tem_fonte = bool(ids_vereditos) or bool(texto_ir)

def destino_existe(d):
    if d in ids_vereditos:
        return True
    return re.search(r"(?<![\w-])%s(?![\w-])" % re.escape(d), texto_ir) is not None

for caminho in arqs:
    # `.cicloN.json` (antigo) ou `cN/ciclo.json` (novo, v2.10.1) -> N
    sys.dont_write_bytecode = True
    sys.path.insert(0, os.environ["GAD_LIB"])
    import gad_caminhos
    ciclo = gad_caminhos.curinga(os.environ["GAD_PD"], "intent/c*/ciclo.json", caminho)

    try:
        with open(caminho, encoding="utf-8") as fh:
            z = json.load(fh)
    except Exception as e:
        erro("%s ilegível: %s" % (caminho, e))

    if not isinstance(z, dict) or "sinos" not in z:
        erro("%s: schema inválido — sem chave `sinos`" % caminho)
    sinos = z["sinos"]
    if not isinstance(sinos, list):
        erro("%s: `sinos` não é uma lista" % caminho)

    for s in sinos:
        if not isinstance(s, dict) or "id" not in s or "disposicao" not in s:
            erro("%s: item de `sinos` sem id/disposicao" % caminho)
        if s["disposicao"] not in DISPOSICOES:
            erro("%s: sino %s com disposicao `%s` inválida" % (caminho, s["id"], s["disposicao"]))
        total_sinos += 1
        if s["disposicao"] == "aberto":
            abertos.append((s["id"], s.get("origem", ""), ciclo))
        elif s["disposicao"] == "levado_aos_consultores":
            d = str(s.get("destino") or "").strip()
            if not d:
                sem_destino.append((s["id"], "", "destino vazio"))
            elif tem_fonte and not destino_existe(d):
                sem_destino.append((s["id"], d, "destino ausente do INTENT-REVIEW e dos vereditos"))

print(json.dumps({"total_sinos": total_sinos, "abertos": abertos,
                  "sem_destino": sem_destino}, ensure_ascii=False))
PY
)
RC=$?
if [ "$RC" -eq 2 ]; then
  echo "$SAIDA" >&2
  exit 2
elif [ "$RC" -ne 0 ]; then
  echo "ERRO: confere-sinos.sh: falha inesperada ao ler .intent/ (rc=$RC)" >&2
  exit 2
fi

N_ABERTOS=$(printf '%s' "$SAIDA" | jq -r '.abertos | length')
N_SEMDEST=$(printf '%s' "$SAIDA" | jq -r '(.sem_destino // []) | length')

if [ "$N_ABERTOS" -eq 0 ] && [ "$N_SEMDEST" -eq 0 ]; then
  echo "sinos_abertos: 0"
  exit 0
fi

echo "sinos_abertos: $N_ABERTOS"
printf '%s' "$SAIDA" | jq -r '.abertos[] | "aberto: \(.[0]) (origem=\(.[1]), ciclo=\(.[2]))"'
printf '%s' "$SAIDA" | jq -r '(.sem_destino // [])[] | "levado_aos_consultores sem destino: \(.[0]) (destino=«\(.[1])» — \(.[2]))"'
[ "$N_ABERTOS" -eq 0 ] || echo "SINOS-ABERTOS: $N_ABERTOS sino(s) sem destino ao fim da etapa de intenção"
[ "$N_SEMDEST" -eq 0 ] || echo "SINOS-SEM-DESTINO: $N_SEMDEST sino(s) levado(s) aos consultores sem destino verificável"
exit 1
