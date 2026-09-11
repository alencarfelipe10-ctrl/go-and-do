#!/usr/bin/env bash
# test-gad-rtk-worktree.sh — bancada do envelope do hook do RTK (45n, F24.5).
#
# O hook do RTK reescreve `git …` em `rtk git …`; dentro de um worktree de agente a checagem
# de isolamento do Claude Code recusa a forma reescrita, e os executores dos planos 01, 03 e 04
# perderam git e contornaram por subprocess. O envelope devolve allow SEM reescrita dentro de
# worktree e delega ao RTK fora dele.
#
# LIMITE DA BANCADA: os payloads são fabricados. Ela prova o envelope, NÃO que o `cwd` que o
# Claude Code entrega dentro de um worktree seja o do worktree (isso é fase real / bancada).
#   bash tests/test-gad-rtk-worktree.sh      · exit 0 = verde
set -u
RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
H="$RAIZ/hooks/gad-rtk-worktree.sh"
OK=0; FALHAS=0
ok()    { OK=$((OK+1)); printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
paga() { printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"git status"},"agent_type":"gsd-executor"}' "$1"; }

if ! command -v rtk >/dev/null 2>&1; then
  echo "  … rtk ausente: só os casos de allow silencioso são conferidos"
fi

# 1. fora de worktree → delega ao RTK (reescreve), exit 0
SAIDA="$(paga "$HOME" | bash "$H" 2>/dev/null)"; RC=$?
eq "fora de worktree: exit 0" "$RC" "0"
if command -v rtk >/dev/null 2>&1; then
  case "$SAIDA" in
    *'"command":"rtk git status"'*) ok "fora de worktree: o RTK reescreveu (comportamento de hoje)" ;;
    *) falha "fora de worktree: o RTK reescreveu" "obtido: $(printf '%s' "$SAIDA" | head -c 200)" ;;
  esac
fi

# 2. cwd em .claude/worktrees/ → allow silencioso, SEM reescrita
SAIDA="$(paga "$HOME/x/.claude/worktrees/agent-abc" | bash "$H" 2>/dev/null)"; RC=$?
eq "worktree pelo nome: exit 0"        "$RC" "0"
eq "worktree pelo nome: saída vazia"   "$SAIDA" ""

# 3. worktree REAL fora de .claude/worktrees/ → allow silencioso pelo critério de git
#    (--git-dir ≠ --git-common-dir), sem depender do nome do diretório
git init -q "$TMP/repo"; git -C "$TMP/repo" config user.email t@t; git -C "$TMP/repo" config user.name t
echo x > "$TMP/repo/a"; git -C "$TMP/repo" add -A; git -C "$TMP/repo" commit -qm base
git -C "$TMP/repo" worktree add -q -b wt "$TMP/wt" >/dev/null 2>&1
SAIDA="$(paga "$TMP/wt" | bash "$H" 2>/dev/null)"; RC=$?
eq "worktree real fora do nome padrão: exit 0"      "$RC" "0"
eq "worktree real fora do nome padrão: saída vazia" "$SAIDA" ""

# 4. payload sem cwd → delega (comportamento de hoje)
SAIDA="$(printf '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | bash "$H" 2>/dev/null)"; RC=$?
eq "sem cwd: exit 0" "$RC" "0"
if command -v rtk >/dev/null 2>&1; then
  case "$SAIDA" in
    *'"updatedInput"'*) ok "sem cwd: delegou ao RTK" ;;
    *) falha "sem cwd: delegou ao RTK" "obtido: $(printf '%s' "$SAIDA" | head -c 200)" ;;
  esac
fi

# 5. entrada vazia → exit 0 sem saída
SAIDA="$(printf '' | bash "$H" 2>/dev/null)"; RC=$?
eq "entrada vazia: exit 0"      "$RC" "0"
eq "entrada vazia: sem saída"   "$SAIDA" ""

echo
echo "── resumo: $OK ok / $FALHAS falhas ──"
[ "$FALHAS" -eq 0 ]
