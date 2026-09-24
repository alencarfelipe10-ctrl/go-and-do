#!/usr/bin/env bash
# test-registra-hooks.sh — modo --confere do hooks/registra-hooks.sh (tarefa 8 do mapa-gad).
#
# Régua: --confere só LÊ. Exit 0 = gad-lifecycle.sh existe em $HOME/.claude/hooks e está em
# PreToolUse + PostToolUse (matcher com Agent) + SubagentStop; exit 1 = falta algo (uma linha
# `falta:` por item); exit 2 = erro de uso ou settings ausente. Tudo roda com HOME falso em
# mktemp -d — nunca o ~/.claude real — e o sha256 do settings é conferido antes/depois.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SCRIPT="$AQUI/../hooks/registra-hooks.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gad-registra-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
falhas=0
ok()   { echo "  ok   — $1"; }
erro() { echo "  FALHA — $1"; [ $# -lt 2 ] || echo "$2" | sed 's/^/         /'; falhas=$((falhas+1)); }

LIFE='bash \"$HOME/.claude/hooks/gad-lifecycle.sh\"'
CMD="{\"type\": \"command\", \"command\": \"$LIFE\", \"timeout\": 5}"

# monta <nome> <com_arquivo:0|1> <pre_matcher|-> <post_matcher|-> <com_stop:0|1>
# "-" = evento ausente. Devolve o HOME falso em $H.
monta() {
  local nome="$1" arq="$2" pre="$3" post="$4" stop="$5" partes=()
  H="$TMP/$nome"; mkdir -p "$H/.claude/hooks"
  [ "$arq" = 1 ] && : > "$H/.claude/hooks/gad-lifecycle.sh"
  [ "$pre" != - ]  && partes+=("\"PreToolUse\": [{\"matcher\": \"$pre\", \"hooks\": [$CMD]}]")
  [ "$post" != - ] && partes+=("\"PostToolUse\": [{\"matcher\": \"$post\", \"hooks\": [$CMD]}]")
  [ "$stop" = 1 ]  && partes+=("\"SubagentStop\": [{\"hooks\": [$CMD]}]")
  local IFS=,
  printf '{"hooks": {%s}}\n' "${partes[*]}" > "$H/.claude/settings.json"
}

# checa <descrição> <exit_esperado> <trecho_esperado_na_saída|""> [args extras...]
checa() {
  local desc="$1" rc_esp="$2" trecho="$3"; shift 3
  local antes depois saida rc
  antes=$(sha256sum "$H/.claude/settings.json" 2>/dev/null | cut -d' ' -f1)
  saida=$(HOME="$H" bash "$SCRIPT" --confere "$@" 2>&1); rc=$?
  depois=$(sha256sum "$H/.claude/settings.json" 2>/dev/null | cut -d' ' -f1)
  if [ "$rc" != "$rc_esp" ]; then
    erro "$desc: esperava exit $rc_esp, veio $rc" "$saida"; return
  fi
  if [ -n "$trecho" ] && ! printf '%s' "$saida" | grep -qF -- "$trecho"; then
    erro "$desc: saída sem «$trecho»" "$saida"; return
  fi
  if [ "$antes" != "$depois" ]; then
    erro "$desc: --confere ALTEROU o settings (sha256 mudou)"; return
  fi
  if ls "$H/.claude/"settings.json.bak-* >/dev/null 2>&1; then
    erro "$desc: --confere criou backup .bak-*"; return
  fi
  ok "$desc → exit $rc_esp"
}

echo "== --confere: caminho feliz"
monta completo 1 'Agent|Task|SendMessage' 'Agent|Task|SendMessage' 1
checa "tudo presente" 0 "ok:"

echo "== --confere: cada falta vira exit 1 com a linha certa"
monta sem-arquivo 0 'Agent|Task|SendMessage' 'Agent|Task|SendMessage' 1
checa "sem o arquivo do hook" 1 "falta: arquivo do hook"
monta sem-post 1 'Agent|Task|SendMessage' - 1
checa "sem PostToolUse" 1 "falta: gad-lifecycle.sh em PostToolUse"
monta sem-agent 1 'Task|SendMessage' 'Agent|Task|SendMessage' 1
checa "matcher do PreToolUse sem Agent" 1 "falta: gad-lifecycle.sh em PreToolUse"
monta sem-stop 1 'Agent|Task|SendMessage' 'Agent|Task|SendMessage' 0
checa "sem SubagentStop" 1 "falta: gad-lifecycle.sh em SubagentStop"

echo "== --confere: uma linha por item faltante"
monta vazio 0 - - 0
saida=$(HOME="$H" bash "$SCRIPT" --confere 2>&1); rc=$?
n=$(printf '%s\n' "$saida" | grep -c '^falta:')
if [ "$rc" = 1 ] && [ "$n" = 4 ]; then ok "settings sem hooks e sem arquivo → 4 linhas falta:, exit 1"
else erro "esperava 4 linhas falta: e exit 1 (veio $n linhas, exit $rc)" "$saida"; fi

echo "== --confere: erros de uso"
monta sem-settings 1 - - 0
rm -f "$H/.claude/settings.json"
checa "settings ausente" 2 "settings não encontrado"
monta explicito 1 'Agent|Task|SendMessage' 'Agent|Task|SendMessage' 1
mv "$H/.claude/settings.json" "$H/outro.json"
saida=$(HOME="$H" bash "$SCRIPT" --confere --settings "$H/outro.json" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "--confere --settings <arquivo> → exit 0" || erro "--settings explícito: exit $rc" "$saida"
saida=$(HOME="$H" bash "$SCRIPT" --confere --dry-run --settings "$H/outro.json" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "--confere + --dry-run → exit 2" || erro "--confere --dry-run: exit $rc" "$saida"

echo
[ "$falhas" -eq 0 ] && echo "test-registra-hooks: tudo ok" || echo "test-registra-hooks: $falhas falha(s)"
[ "$falhas" -eq 0 ]
