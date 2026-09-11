#!/usr/bin/env bash
# gad-rtk-worktree.sh — hook PreToolUse (matcher Bash) que envelopa o `rtk hook claude`.
#
# Origem: F24.5 (09/09/2026). O hook do RTK reescreve `git status` em `rtk git status`. Para um
# subagente com `isolation: worktree`, a checagem de isolamento do Claude Code recusa o comando
# reescrito — «this command runs rtk with a git command among its operands: what runs it, and
# from which directory, cannot be verified». Os executores dos planos 01, 03 e 04 perderam
# git log/diff/status/add/commit e contornaram por `subprocess.run(["git", …])` dentro de
# `uv run python -c`, que nenhum guarda vê. O guarda perdeu a função e a porta dos fundos ficou.
#
# Regra: dentro de um worktree de agente (`/.claude/worktrees/` no cwd do payload), este hook
# devolve allow SEM reescrita — o comando chega ao harness na forma que o modelo escreveu, e a
# checagem de isolamento consegue verificá-lo. Fora disso, delega ao `rtk hook claude` e repassa
# a saída dele byte a byte (inclusive a ausência de saída).
#
# Instalação: substitui a entrada `rtk hook claude` em ~/.claude/settings.json (PreToolUse/Bash).
# Registro = `registra-hooks.sh` + trecho no README, rodado pelo dono.
IN=$(cat 2>/dev/null) || exit 0
[ -n "$IN" ] || exit 0
CWD=$(printf '%s' "$IN" | sed -n 's/.*"cwd":"\([^"\\]*\)".*/\1/p' | head -n1)
# Caminho rápido pelo nome (default do GSD), e o critério robusto logo abaixo: num worktree
# ligado, `--git-dir` e `--git-common-dir` DIFEREM; no checkout principal são iguais. Não depende
# de onde o GSD põe os worktrees.
case "$CWD" in
  */.claude/worktrees/*) exit 0 ;;   # allow sem reescrita: o isolamento precisa ver o git nu
esac
if [ -n "$CWD" ]; then
  _gd=$(git -C "$CWD" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)
  _gc=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  [ -n "$_gd" ] && [ -n "$_gc" ] && [ "$_gd" != "$_gc" ] && exit 0
fi
printf '%s' "$IN" | rtk hook claude || exit 0
