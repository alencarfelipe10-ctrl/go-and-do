#!/usr/bin/env bash
# test-limpa-intencao.sh — bancada do limpa-intencao.sh (FM-F27INS-08INT, tarefa 59 b7).
#
# Régua: a limpeza do fecho da intenção apaga EXATAMENTE os 4 alvos (sinos-*.txt,
# c*/briefing*.md, varredura.md, c*/mudancas.md) nos dois formatos de fase, deixa todo o
# resto intacto, e dá o mesmo resultado chamada de bash ou de zsh (na F27 o glob inline não
# expandiu sob zsh). O phase_dir tem ESPAÇO no nome para provar que não há word-splitting.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../skills/go-and-do/scripts/limpa-intencao.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-limpa-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }
# o gad_autoregistro não pode achar rodada ativa de verdade a partir do TMP
export GAD_DRY_RUN=1

# formato NOVO: <pd>/.gad/FORMATO + .gad/intent/…
monta_novo() { # <pd>
  local pd="$1" I="$1/.gad/intent"
  mkdir -p "$I/c0" "$I/c1/runs/r1" "$I/c2" "$I/c1b"
  echo "formato" > "$pd/.gad/FORMATO"
  # os 4 alvos
  echo s > "$I/sinos-spec.txt"; echo s > "$I/sinos-discuss.txt"
  echo b > "$I/c1/briefing.md"; echo b > "$I/c1/briefing-devolucao.md"; echo b > "$I/c2/briefing.md"
  echo v > "$I/varredura.md"
  echo m > "$I/c2/mudancas.md"
  # sobreviventes (lista do passo 7b do intent.md)
  echo x > "$I/c1/vereditos.txt"; echo x > "$I/c1/correcoes.aplicado"; echo x > "$I/c0/ciclo.json"
  echo x > "$I/c1/runs/r1/achados.json"; echo x > "$I/c1/tabela.txt"; echo x > "$I/c1/prova-leitura.txt"
  echo x > "$I/c1b/releitura.json"; echo x > "$I/c1/status-codex.json"; echo x > "$I/pre-spec-route.json"
  echo x > "$pd/NN-SPEC.md"
}
SOBREV_NOVO=(c1/vereditos.txt c1/correcoes.aplicado c0/ciclo.json c1/runs/r1/achados.json c1/tabela.txt
             c1/prova-leitura.txt c1b/releitura.json c1/status-codex.json pre-spec-route.json)
ALVOS_NOVO=(sinos-spec.txt sinos-discuss.txt c1/briefing.md c1/briefing-devolucao.md c2/briefing.md
            varredura.md c2/mudancas.md)

# formato ANTIGO: <pd>/.intent/.…
monta_antigo() { # <pd>
  local pd="$1" I="$1/.intent"
  mkdir -p "$I/runs/c1"
  echo s > "$I/.sinos-spec.txt"; echo s > "$I/.sinos-discuss.txt"
  echo b > "$I/briefing-c1.md"; echo b > "$I/briefing-c2.md"
  echo v > "$I/.varredura.md"
  echo m > "$I/.mudancas-c2.md"
  echo x > "$I/.vereditos-c1.txt"; echo x > "$I/.correcoes-c1.aplicado"; echo x > "$I/.ciclo0.json"
  echo x > "$I/runs/c1/achados.json"; echo x > "$I/.releitura-c1.json"
  echo x > "$pd/NN-SPEC.md"
}
SOBREV_ANTIGO=(.vereditos-c1.txt .correcoes-c1.aplicado .ciclo0.json runs/c1/achados.json .releitura-c1.json)
ALVOS_ANTIGO=(.sinos-spec.txt .sinos-discuss.txt briefing-c1.md briefing-c2.md .varredura.md .mudancas-c2.md)

confere() { # <rótulo> <base intent> <alvos…> -- <sobreviventes…>
  local rot="$1" base="$2"; shift 2
  local fase=alvo a restam=() sumiram=()
  for a in "$@"; do
    if [ "$a" = -- ]; then fase=sobrev; continue; fi
    if [ "$fase" = alvo ]; then [ -e "$base/$a" ] && restam+=("$a")
    else [ -e "$base/$a" ] || sumiram+=("$a"); fi
  done
  [ ${#restam[@]} -eq 0 ] && ok "$rot: os alvos sumiram" || erro "$rot: alvos que ficaram" "${restam[*]}"
  [ ${#sumiram[@]} -eq 0 ] && ok "$rot: os sobreviventes ficaram" || erro "$rot: sobrevivente apagado" "${sumiram[*]}"
}

roda_com() { # <shell: bash|zsh> <pd> → saída; rc em $RC
  local sh="$1" pd="$2"
  if [ "$sh" = zsh ]; then
    # zsh chama o script do jeito que o intent.md manda (caminho do executável + "<phase_dir>")
    SAIDA=$(zsh -f -c '"$1" "$2"' zsh "$SCRIPT" "$pd" 2>&1); RC=$?
  else
    SAIDA=$(bash -c '"$1" "$2"' bash "$SCRIPT" "$pd" 2>&1); RC=$?
  fi
}

SHELLS=(bash)
if command -v zsh >/dev/null 2>&1; then SHELLS+=(zsh); else echo "  (zsh ausente — só bash)"; fi

for sh in "${SHELLS[@]}"; do
  echo "== [$sh] formato novo (.gad/intent), phase_dir com espaço"
  PD="$TMP/$sh novo/27-fase x"; mkdir -p "$PD"; monta_novo "$PD"
  roda_com "$sh" "$PD"
  [ "$RC" = 0 ] && ok "exit 0" || erro "exit $RC" "$SAIDA"
  case "$SAIDA" in *"7 arquivo(s)"*) ok "relata 7 removidos" ;; *) erro "contagem na saída" "$SAIDA" ;; esac
  confere "novo/$sh" "$PD/.gad/intent" "${ALVOS_NOVO[@]}" -- "${SOBREV_NOVO[@]}"
  [ -f "$PD/NN-SPEC.md" ] && [ -f "$PD/.gad/FORMATO" ] && ok "fora de intent/ nada é tocado" || erro "apagou fora de intent/"

  echo "== [$sh] segunda passada: nada casou → exit 0 em silêncio"
  roda_com "$sh" "$PD"
  { [ "$RC" = 0 ] && [ -z "$SAIDA" ]; } && ok "exit 0 sem saída" || erro "esperado silêncio/0" "rc=$RC saída=$SAIDA"

  echo "== [$sh] formato antigo (.intent/.…), phase_dir com espaço"
  PD="$TMP/$sh antigo/24 fase"; mkdir -p "$PD"; monta_antigo "$PD"
  roda_com "$sh" "$PD"
  [ "$RC" = 0 ] && ok "exit 0" || erro "exit $RC" "$SAIDA"
  confere "antigo/$sh" "$PD/.intent" "${ALVOS_ANTIGO[@]}" -- "${SOBREV_ANTIGO[@]}"

  echo "== [$sh] fase sem pasta de intenção → exit 0 em silêncio"
  PD="$TMP/$sh vazia"; mkdir -p "$PD"
  roda_com "$sh" "$PD"
  { [ "$RC" = 0 ] && [ -z "$SAIDA" ]; } && ok "exit 0 sem saída" || erro "esperado silêncio/0" "rc=$RC saída=$SAIDA"

  echo "== [$sh] phase_dir inexistente → exit 2 com mensagem"
  roda_com "$sh" "$TMP/nao existe"
  [ "$RC" = 2 ] && ok "exit 2" || erro "esperado exit 2, veio $RC" "$SAIDA"
  case "$SAIDA" in *inexistente*) ok "mensagem nomeia o problema" ;; *) erro "sem mensagem" "$SAIDA" ;; esac
done

echo "== uso: sem argumento ou com dois → exit 2"
bash "$SCRIPT" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "sem argumento → 2" || erro "sem argumento → $rc"
bash "$SCRIPT" "$TMP" extra >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "dois argumentos → 2" || erro "dois argumentos → $rc"

echo "== pasta com nome de alvo não é apagada (só arquivos)"
PD="$TMP/pasta"; mkdir -p "$PD/.gad/intent/c1/briefing-x.md"; echo f > "$PD/.gad/FORMATO"
bash "$SCRIPT" "$PD" >/dev/null 2>&1
[ -d "$PD/.gad/intent/c1/briefing-x.md" ] && ok "pasta preservada" || erro "apagou uma pasta"

echo
if [ "$falhas" -eq 0 ]; then echo "test-limpa-intencao: OK"; exit 0
else echo "test-limpa-intencao: $falhas falha(s)"; exit 1; fi
