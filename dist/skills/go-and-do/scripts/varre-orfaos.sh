#!/usr/bin/env bash
# varre-orfaos.sh — varredura de processos órfãos de uma fase parada (item B3).
#
# Contexto: a Sub-rotina D ("parada graciosa") manda, depois do TaskStop, varrer o que
# ficou de fundo — waiters de disco, processos codex, suítes lançadas em background. Na
# F24.4 essa varredura foi improviso do modelo, feita POR NOME de processo, e falhou
# duas vezes. Este script é a metade automatizável da rotina: identifica por VÍNCULO COM
# A FASE, nunca por nome.
#
# Uso: varre-orfaos.sh <phase_dir> [--matar]
#
#   SEM --matar o script apenas RELATA. Esse é o padrão e é deliberado: um script que
#   mata processo por engano é pior que o problema que ele resolve.
#
# Critérios de candidato (aplicados sobre `ps -eo pid,ppid,pgid,etimes,args`, nunca
# `pgrep` por nome):
#   1. a linha de comando referencia o <phase_dir> canonicalizado; OU
#   2. o diretório de trabalho (/proc/<pid>/cwd) é o <phase_dir> ou está dentro dele.
#   PPID == 1 (reparentado — o rastro do `setsid`/`nohup`) NÃO amplia o conjunto: é uma
#   ANOTAÇÃO na saída (coluna `reparentado`). Num sistema com systemd dezenas de daemons
#   legítimos têm PPID 1; usá-lo como critério independente varreria a máquina inteira.
#   Os candidatos são então AGRUPADOS por `pgid` e o grupo é relatado inteiro.
#
# Exclusões absolutas (nunca entram na lista, nem para relato):
#   PID 1; o próprio processo; TODA a cadeia de ancestrais do script até o PID 1 — o
#   <phase_dir> está na linha de comando do próprio script e na do shell que o chamou,
#   então sem essa poda o script se acusaria a si mesmo.
#
# Salvaguardas de --matar:
#   - mais de 10 candidatos → RECUSA matar (falso positivo em massa é o pior desfecho);
#   - GRUPO-MISTO: um pgid cujo grupo contém processo que NÃO casou os critérios não é
#     morto, só relatado. `dev-server.sh:46-48` registra o precedente de matar pgid
#     alheio ter derrubado o orquestrador;
#   - GRUPO-PROPRIO: o próprio grupo de processos ou a própria sessão são RELATADOS
#     (senão um órfão legítimo lançado pelo mesmo shell ficaria invisível) mas nunca
#     mortos — matá-los derrubaria quem chamou a varredura;
#   - o que sobra: TERM no grupo (`kill -TERM -<pgid>`), 5 segundos, KILL nos remanescentes.
#
# Saída: uma linha por processo, agrupada por pgid; ao final `orfaos: <n>`.
# Exit: 0 = nenhum órfão (ou, com --matar, nenhum restante); 1 = há órfãos (inclusive
#       quando a morte foi recusada); 2 = uso inválido.
#
# GAD_PS_FALSA=<arquivo>: usa um instantâneo de `ps` pré-gravado em vez de ler a tabela
#   real de processos. Serve SÓ para teste — é o que permite exercitar o teto de 10 e o
#   GRUPO-MISTO sem lançar dezenas de processos de verdade. Nesse modo a leitura de
#   /proc/<pid>/cwd é desligada (os pids do arquivo são fictícios).
set -u

MATAR=false
DIR=""
for arg in "$@"; do
  case "$arg" in
    --matar) MATAR=true ;;
    -*) echo "uso: varre-orfaos.sh <phase_dir> [--matar]" >&2; exit 2 ;;
    *)
      if [ -n "$DIR" ]; then
        echo "uso: varre-orfaos.sh <phase_dir> [--matar] (um único diretório)" >&2; exit 2
      fi
      DIR="$arg" ;;
  esac
done

[ -n "$DIR" ] || { echo "uso: varre-orfaos.sh <phase_dir> [--matar]" >&2; exit 2; }
# Diretório inexistente é exit 2, NUNCA `orfaos: 0` — um caminho digitado errado
# relatando zero órfãos é o pior desfecho possível numa rotina de parada.
[ -d "$DIR" ] || { echo "USO-INVALIDO: '$DIR' não é um diretório" >&2; exit 2; }

DIR=$(CDPATH= cd -- "$DIR" && pwd -P) || exit 2

# Guarda contra alvo largo demais: um phase_dir que resolve para /, para o $HOME ou para
# a raiz do repositório casa com quase todo processo da máquina.
RAIZ_REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd -P 2>/dev/null || echo "")
case "$DIR" in
  /) echo "RECUSA: phase_dir resolve para '/' — largo demais" >&2; exit 2 ;;
esac
if [ "$DIR" = "${HOME:-/dev/null/nao-existe}" ] || { [ -n "$RAIZ_REPO" ] && [ "$DIR" = "$RAIZ_REPO" ]; }; then
  echo "RECUSA: phase_dir '$DIR' é raiz de home/repositório — largo demais" >&2; exit 2
fi

# --- exclusões: cadeia de ancestrais, grupo e sessão próprios -----------------------
EU=$$
ANCESTRAIS=" $EU "
p=$EU
while [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ]; do
  pai=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
  [ -n "$pai" ] || break
  ANCESTRAIS="$ANCESTRAIS$pai "
  p="$pai"
done
MEU_PGID=$(ps -o pgid= -p "$EU" 2>/dev/null | tr -d ' ')
MEU_SID=$(ps -o sid=  -p "$EU" 2>/dev/null | tr -d ' ')

# --- instantâneo da tabela de processos ---------------------------------------------
# Gravado em ARQUIVO antes de filtrar: filtrar direto num pipe faria o próprio `grep`
# (que carrega o phase_dir na linha de comando) aparecer como candidato.
SNAP=$(mktemp "${TMPDIR:-/tmp}/gad-varre-XXXXXX")
trap 'rm -f "$SNAP"' EXIT
FALSA=false
if [ -n "${GAD_PS_FALSA:-}" ]; then
  [ -r "$GAD_PS_FALSA" ] || { echo "USO-INVALIDO: GAD_PS_FALSA='$GAD_PS_FALSA' ilegível" >&2; exit 2; }
  FALSA=true
  cat -- "$GAD_PS_FALSA" > "$SNAP"
else
  ps -eo pid,ppid,pgid,etimes,args -ww 2>/dev/null | tail -n +2 > "$SNAP"
fi

# casa_criterio <pid> <args> → 0 se o processo tem vínculo com o phase_dir
casa_criterio() {
  local pid="$1" args="$2" cwd=""
  case "$args" in *"$DIR"*) return 0 ;; esac
  if [ "$FALSA" = false ]; then
    # o pid pode ter morrido entre o instantâneo e agora — silêncio é o certo aqui
    cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null) || cwd=""
    [ -n "$cwd" ] || return 1
    [ "$cwd" = "$DIR" ] && return 0
    case "$cwd" in "$DIR"/*) return 0 ;; esac
  fi
  return 1
}

# intocavel <pid> → 0 se o processo não pode nem aparecer no relato (é o script, um
# ancestral dele, ou o PID 1)
intocavel() {
  local pid="$1"
  [ "$pid" = 1 ] && return 0
  case "$ANCESTRAIS" in *" $pid "*) return 0 ;; esac
  return 1
}

# grupo_proprio <pgid> <pid_amostra> → 0 se o grupo é o meu, ou está na minha sessão.
# Relatável, jamais matável.
grupo_proprio() {
  local pgid="$1" pid="$2" sid
  [ -n "$MEU_PGID" ] && [ "$pgid" = "$MEU_PGID" ] && return 0
  if [ "$FALSA" = false ] && [ -n "$MEU_SID" ]; then
    sid=$(ps -o sid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$sid" ] && [ "$sid" = "$MEU_SID" ] && return 0
  fi
  return 1
}

# --- classificação -------------------------------------------------------------------
casados=()          # "pid|ppid|pgid|etimes|args"
pgids_casados=""    # " pgid pgid "
pgids_com_estranho="" # pgids que também abrigam processo ESTRANHO (ver abaixo)
MAPA=""             # " pid:pgid " de todo o instantâneo, para saber se um pai está no grupo

while read -r pid ppid pgid etimes args; do
  case "${pid:-}" in ''|*[!0-9]*) continue ;; esac
  MAPA="$MAPA $pid:$pgid "
done < "$SNAP"

while read -r pid ppid pgid etimes args; do
  [ -n "${pid:-}" ] || continue
  case "$pid" in ''|*[!0-9]*) continue ;; esac
  if casa_criterio "$pid" "$args"; then
    intocavel "$pid" && continue
    casados+=("$pid|$ppid|$pgid|$etimes|$args")
    case "$pgids_casados" in *" $pgid "*) : ;; *) pgids_casados="$pgids_casados $pgid " ;; esac
  fi
done < "$SNAP"

# Segunda passada: um pgid casado que abriga um ESTRANHO não pode ser morto em bloco.
# Estranho = (a) processo intocável (o script ou um ancestral dele — foi o que derrubou
# o orquestrador no aceite do dev-server.sh), ou (b) processo que não casa o critério E
# cujo pai está FORA do grupo. A ressalva (b) importa: o `sleep` filho de um waiter tem
# `sleep 60` na linha de comando e o cwd herdado, logo não casa nada — mas é parte
# legítima da árvore órfã e sem essa exceção todo grupo real sairia "misto".
if [ -n "$pgids_casados" ]; then
  while read -r pid ppid pgid etimes args; do
    [ -n "${pid:-}" ] || continue
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    case "$pgids_casados" in *" $pgid "*) : ;; *) continue ;; esac
    estranho=nao
    if intocavel "$pid"; then
      estranho=sim
    elif ! casa_criterio "$pid" "$args"; then
      case "$MAPA" in
        *" $ppid:$pgid "*) : ;;   # filho de alguém do próprio grupo — parte da árvore
        *) estranho=sim ;;
      esac
    fi
    if [ "$estranho" = sim ]; then
      case "$pgids_com_estranho" in *" $pgid "*) : ;; *) pgids_com_estranho="$pgids_com_estranho $pgid " ;; esac
    fi
  done < "$SNAP"
fi

N=${#casados[@]}

echo "phase_dir: $DIR"
if [ "$N" -eq 0 ]; then
  echo "orfaos: 0"
  exit 0
fi

# --- relato, agrupado por pgid --------------------------------------------------------
for g in $pgids_casados; do
  # pid de amostra do grupo, para consultar a sessão
  amostra=""
  for reg in "${casados[@]}"; do
    IFS='|' read -r pid _ pgid _ _ <<< "$reg"
    [ "$pgid" = "$g" ] && { amostra="$pid"; break; }
  done
  marca=""
  case "$pgids_com_estranho" in
    *" $g "*) marca="  [GRUPO-MISTO: abriga processo que não casou os critérios — não será morto]" ;;
  esac
  if grupo_proprio "$g" "$amostra"; then
    marca="$marca  [GRUPO-PROPRIO: é o grupo/sessão de quem chamou — não será morto]"
  fi
  echo "grupo pgid=$g$marca"
  for reg in "${casados[@]}"; do
    IFS='|' read -r pid ppid pgid etimes args <<< "$reg"
    [ "$pgid" = "$g" ] || continue
    rep=nao; [ "$ppid" = 1 ] && rep=sim
    echo "  pid=$pid ppid=$ppid pgid=$pgid vida=${etimes}s reparentado=$rep cmd=${args:0:120}"
  done
done
echo "orfaos: $N"

[ "$MATAR" = true ] || exit 1

# --- rota de morte --------------------------------------------------------------------
# Teto contado em PROCESSOS, não em grupos: é o número maior, logo o mais conservador.
if [ "$N" -gt 10 ]; then
  echo "RECUSA: $N candidatos — acima do teto; inspecione à mão"
  exit 1
fi

mataveis=""
for g in $pgids_casados; do
  case "$pgids_com_estranho" in
    *" $g "*) echo "pula pgid=$g — GRUPO-MISTO, morte recusada"; continue ;;
  esac
  case "$g" in ''|0|1) echo "pula pgid=$g — grupo reservado"; continue ;; esac
  amostra=""
  for reg in "${casados[@]}"; do
    IFS='|' read -r pid _ pgid _ _ <<< "$reg"
    [ "$pgid" = "$g" ] && { amostra="$pid"; break; }
  done
  if grupo_proprio "$g" "$amostra"; then
    echo "pula pgid=$g — GRUPO-PROPRIO, morte recusada"; continue
  fi
  mataveis="$mataveis $g"
done

for g in $mataveis; do
  if kill -TERM -- "-$g" 2>/dev/null; then
    echo "TERM enviado ao grupo pgid=$g"
  else
    echo "TERM falhou no grupo pgid=$g (grupo já ausente ou sem permissão)"
  fi
done

if [ -n "$mataveis" ]; then
  sleep 5
  for g in $mataveis; do
    if kill -0 -- "-$g" 2>/dev/null; then
      if kill -KILL -- "-$g" 2>/dev/null; then
        echo "KILL enviado ao grupo pgid=$g (sobreviveu aos 5s de TERM)"
      else
        echo "KILL falhou no grupo pgid=$g"
      fi
    else
      echo "grupo pgid=$g encerrou com TERM"
    fi
  done
fi

# recontagem: o exit reflete o estado ATUAL, não o inicial
restantes=0
if [ "$FALSA" = false ]; then
  ps -eo pid,ppid,pgid,etimes,args -ww 2>/dev/null | tail -n +2 > "$SNAP"
fi
while read -r pid ppid pgid etimes args; do
  [ -n "${pid:-}" ] || continue
  case "$pid" in ''|*[!0-9]*) continue ;; esac
  if casa_criterio "$pid" "$args"; then
    intocavel "$pid" && continue
    restantes=$((restantes+1))
  fi
done < "$SNAP"
echo "restantes: $restantes"
[ "$restantes" -eq 0 ]
