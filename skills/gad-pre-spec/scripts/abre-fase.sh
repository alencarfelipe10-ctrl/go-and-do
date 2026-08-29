#!/usr/bin/env bash
# abre-fase.sh — envelope do `gsd-tools query init.phase-op` para a /gad-pre-spec.
#
# Uso:
#   abre-fase.sh <NN> [--raiz <dir>] [--criar]
#   abre-fase.sh <NN> --inserir "<nome da fase>" --apos <M> [--raiz <dir>] [--criar]
#
# Imprime UMA linha de JSON compacto:
#   {"phase_found":bool,"dir":str|null,"padded":str|null,"alvo":str|null,"existe":bool,
#    "numero":str|null,"nome":str|null,"roadmap":str|null,"criado":bool}
#   (no modo --inserir acrescenta "numero_atribuido" e, se divergir do NN pedido,
#    "aviso_numero": "...")
#
# Campos:
#   dir    = phase_dir do GSD; se nulo, expected_phase_dir (a fase está no ROADMAP mas
#            o diretório ainda não existe). NUNCA inventa `$NN-nova`.
#   padded = padded_phase do GSD — é ELE que nomeia o arquivo, nunca o argumento cru
#            (fase 2 → "02"; fase 24.3 → "24.3"). É assim que o abre-rodada.sh detecta.
#   alvo   = "<dir>/<padded>-PRE-SPEC.md"
#   existe = o alvo já está no disco (a skill entra em modo revisão).
#
# --criar   faz `mkdir -p "$dir"` (default: não toca no disco).
# --inserir insere a fase no ROADMAP pelo mesmo caminho do /gsd-phase --insert:
#           `query phase.insert <M> "<nome>"` (o GSD é quem CALCULA o número decimal a
#           partir de <M> e cria o diretório) + `query state.patch` +
#           `query state.add-roadmap-evolution`, ambos best-effort (pulados quando o
#           projeto não tem STATE.md). O número atribuído pelo GSD pode não ser o NN
#           pedido — o script devolve o que o GSD atribuiu e avisa da divergência.
#
# Exit: 0 = ok · 2 = erro de uso/ambiente · 4 = fase fora do ROADMAP (sem --inserir).
set -u

FASE=""; RAIZ=""; INSERIR=""; APOS=""; CRIAR=0
while [ $# -gt 0 ]; do
  case "$1" in
    --raiz)    RAIZ="${2:?--raiz exige um diretório}"; shift 2 ;;
    --inserir) INSERIR="${2:?--inserir exige o nome da fase}"; shift 2 ;;
    --apos)    APOS="${2:?--apos exige o número da fase anterior}"; shift 2 ;;
    --criar)   CRIAR=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    -*)        echo "ERRO: opção desconhecida: $1" >&2; exit 2 ;;
    *)         [ -z "$FASE" ] || { echo "ERRO: número da fase informado duas vezes" >&2; exit 2; }
               FASE="$1"; shift ;;
  esac
done
[ -n "$FASE" ] || { echo "uso: abre-fase.sh <NN> [--inserir \"<nome>\" --apos <M>] [--criar] [--raiz <dir>]" >&2; exit 2; }
[ -z "$INSERIR" ] || [ -n "$APOS" ] || {
  echo "ERRO: --inserir exige --apos <M>. O GSD não cria a fase NN que você pedir: o" >&2
  echo "      phase.insert recebe a fase ANTERIOR e calcula o decimal seguinte (72 → 72.1)." >&2
  exit 2; }
RAIZ="${RAIZ:-$PWD}"
[ -d "$RAIZ/.planning" ] || { echo "ERRO: $RAIZ não é projeto GSD (.planning ausente)" >&2; exit 2; }

command -v python3 >/dev/null 2>&1 || { echo "ERRO: python3 não encontrado" >&2; exit 2; }

# ── resolução do gsd-tools (mesma ordem do lib/gsd-shim.sh da go-and-do) ────────
GSD_TOOLS=""; _VIA=""
_resolve() {
  local nome="gsd-tools.cjs"
  local root="${RUNTIME_DIR:-$(cd "$RAIZ" && git rev-parse --show-toplevel 2>/dev/null || echo "$RAIZ")}"
  if   [ -f "$root/gsd-core/bin/$nome" ];         then GSD_TOOLS="$root/gsd-core/bin/$nome"; _VIA=node
  elif [ -f "$root/.claude/gsd-core/bin/$nome" ]; then GSD_TOOLS="$root/.claude/gsd-core/bin/$nome"; _VIA=node
  elif command -v gsd-tools >/dev/null 2>&1;      then GSD_TOOLS="$(command -v gsd-tools)"; _VIA=direct
  elif [ -f "$HOME/.claude/gsd-core/bin/$nome" ]; then GSD_TOOLS="$HOME/.claude/gsd-core/bin/$nome"; _VIA=node
  else
    echo "ERRO: gsd-tools.cjs não encontrado. Instale: npx -y @opengsd/gsd-core@latest --claude --local" >&2
    return 1
  fi
}
_resolve || exit 2
gsd() { if [ "$_VIA" = node ]; then (cd "$RAIZ" && node "$GSD_TOOLS" "$@"); else (cd "$RAIZ" && "$GSD_TOOLS" "$@"); fi; }

# `query` pode devolver "@file:/caminho" quando a saída é grande.
gsd_json() {
  local out; out=$(gsd "$@" 2>/dev/null) || return 1
  case "$out" in @file:*) cat "${out#@file:}" ;; *) printf '%s' "$out" ;; esac
}

campo() {  # campo <json> <chave> — string vazia quando null/ausente
  printf '%s' "$1" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
v=d.get(sys.argv[1])
print("" if v is None else (v if isinstance(v,str) else json.dumps(v)))
' "$2"
}

INIT=$(gsd_json query init.phase-op "$FASE") || { echo "ERRO: init.phase-op $FASE falhou" >&2; exit 2; }
FOUND=$(campo "$INIT" phase_found)

ATRIBUIDO=""; AVISO=""
if [ "$FOUND" != "true" ] && [ -n "$INSERIR" ]; then
  RES=$(gsd_json query phase.insert "$APOS" "$INSERIR") || { echo "ERRO: phase.insert $APOS falhou" >&2; exit 2; }
  ATRIBUIDO=$(campo "$RES" phase_number)
  [ -n "$ATRIBUIDO" ] || { echo "ERRO: phase.insert não devolveu phase_number" >&2; exit 2; }
  [ "$ATRIBUIDO" = "$FASE" ] || AVISO="o GSD atribuiu a fase $ATRIBUIDO (você pediu $FASE) — o número sai do phase.insert, não do argumento"
  # espelhos de estado: best-effort, só quando o projeto tem STATE.md
  if [ -n "$(campo "$INIT" state_path)" ]; then
    gsd query state.patch "{\"Current Phase\":\"$ATRIBUIDO\"}" >/dev/null 2>&1 || true
    gsd query state.add-roadmap-evolution --phase "$ATRIBUIDO" --action inserted \
        --after "$APOS" --note "$INSERIR" --urgent >/dev/null 2>&1 || true
  fi
  FASE="$ATRIBUIDO"
  INIT=$(gsd_json query init.phase-op "$FASE") || { echo "ERRO: init.phase-op $FASE falhou após o insert" >&2; exit 2; }
  FOUND=$(campo "$INIT" phase_found)
fi

if [ "$FOUND" != "true" ]; then
  printf '{"phase_found":false,"dir":null,"padded":null,"alvo":null,"existe":false,"numero":null,"nome":null,"roadmap":%s,"criado":false}\n' \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1] or None))' "$(campo "$INIT" roadmap_path)")"
  exit 4
fi

DIR=$(campo "$INIT" phase_dir); [ -n "$DIR" ] || DIR=$(campo "$INIT" expected_phase_dir)
PADDED=$(campo "$INIT" padded_phase)
[ -n "$DIR" ] && [ -n "$PADDED" ] || {
  echo "ERRO: init.phase-op $FASE achou a fase mas não devolveu phase_dir/expected_phase_dir nem padded_phase" >&2
  exit 2; }

CRIADO=false
if [ "$CRIAR" = 1 ] && [ ! -d "$DIR" ]; then mkdir -p "$DIR" && CRIADO=true; fi

ALVO="$DIR/$PADDED-PRE-SPEC.md"
EXISTE=false; [ -f "$ALVO" ] && EXISTE=true

python3 - "$DIR" "$PADDED" "$ALVO" "$EXISTE" "$(campo "$INIT" phase_number)" \
         "$(campo "$INIT" phase_name)" "$(campo "$INIT" roadmap_path)" "$CRIADO" \
         "$ATRIBUIDO" "$AVISO" <<'PY'
import json, sys
d, padded, alvo, existe, numero, nome, roadmap, criado, atribuido, aviso = sys.argv[1:11]
saida = {
    "phase_found": True,
    "dir": d,
    "padded": padded,
    "alvo": alvo,
    "existe": existe == "true",
    "numero": numero or None,
    "nome": nome or None,
    "roadmap": roadmap or None,
    "criado": criado == "true",
}
if atribuido:
    saida["numero_atribuido"] = atribuido
if aviso:
    saida["aviso_numero"] = aviso
print(json.dumps(saida, ensure_ascii=False))
PY
