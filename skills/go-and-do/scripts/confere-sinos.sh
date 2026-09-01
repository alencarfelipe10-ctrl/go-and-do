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
#   .ciclo0.json = {v:1, sinos:[{id, origem, disposicao, correcao_id?}], ...}
#   disposicao ∈ {corrigido, descartado, aberto}; só "corrigido" tem correcao_id.
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
# Exit 1 = há sino(s) `aberto` sobrando ao fim da etapa de intenção.
# Exit 2 = uso inválido, phase_dir inexistente, ou algum `.cicloN.json` ilegível.
#
# Somente leitura: nunca escreve nada em disco.

set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gsd-shim.sh" 2>/dev/null && trap 'gad_autoregistro "confere-sinos.sh" "$?"' EXIT || true

PD="${1:-}"
[ -n "$PD" ] || { echo "uso: confere-sinos.sh <phase_dir>" >&2; exit 2; }
[ -d "$PD" ] || { echo "ERRO: phase_dir inexistente: $PD" >&2; exit 2; }

IN="$PD/.intent"

# Nem procuramos arquivo se o diretório .intent/ nem existe — fase sem etapa de
# intenção rodada ainda é caso legítimo de "sem sinos", não erro.
if [ ! -d "$IN" ]; then
  echo "sinos_abertos: n/a (sem .ciclo0.json)"
  exit 0
fi

# shellcheck disable=SC2012
ARQS=$(ls "$IN"/.ciclo[0-9]*.json 2>/dev/null | sort -V)
if [ -z "$ARQS" ]; then
  echo "sinos_abertos: n/a (sem .ciclo0.json)"
  exit 0
fi

SAIDA=$(GAD_ARQS="$ARQS" python3 - <<'PY'
import json, os, sys

arqs = [a for a in os.environ["GAD_ARQS"].splitlines() if a]

def erro(msg):
    print("ERRO: %s" % msg)
    sys.exit(2)

abertos = []  # (id, origem, ciclo)
total_sinos = 0

for caminho in arqs:
    nome = os.path.basename(caminho)
    # `.cicloN.json` -> N
    ciclo = nome[len(".ciclo"):-len(".json")]

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
        if s["disposicao"] not in ("corrigido", "descartado", "aberto"):
            erro("%s: sino %s com disposicao `%s` inválida" % (caminho, s["id"], s["disposicao"]))
        total_sinos += 1
        if s["disposicao"] == "aberto":
            abertos.append((s["id"], s.get("origem", ""), ciclo))

print(json.dumps({"total_sinos": total_sinos, "abertos": abertos}, ensure_ascii=False))
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

if [ "$N_ABERTOS" -eq 0 ]; then
  echo "sinos_abertos: 0"
  exit 0
fi

echo "sinos_abertos: $N_ABERTOS"
printf '%s' "$SAIDA" | jq -r '.abertos[] | "aberto: \(.[0]) (origem=\(.[1]), ciclo=\(.[2]))"'
echo "SINOS-ABERTOS: $N_ABERTOS sino(s) sem destino ao fim da etapa de intenção"
exit 1
