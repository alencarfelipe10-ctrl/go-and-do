# Protected-branch warning for `branching_strategy: none` (#3552)

Run this from the `handle_branching` step's `"none"` arm, after deciding to
continue on the current branch. It warns without refusing execution — the
`"none"` strategy still runs on whatever branch it started on.

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || true)
IS_PROTECTED=$(gad_run query git.base-branch --is-protected "$CURRENT_BRANCH") || IS_PROTECTED=""
if [ "$IS_PROTECTED" = true ]; then
  echo "⚠ Current branch '$CURRENT_BRANCH' is a protected branch; branching_strategy=none will continue here." >&2
elif [ -z "$IS_PROTECTED" ]; then
  echo "⚠ Could not determine whether '$CURRENT_BRANCH' is protected — the query failed. Continuing." >&2
fi
```

The `IS_PROTECTED=""` fallback on the first line, and the second `elif`, exist
so a failed or missing `gad_run` invocation degrades **visibly** (an explicit
"could not determine" warning) rather than silently reading as "not
protected" under `set -e` (#3648 review, round 5).
