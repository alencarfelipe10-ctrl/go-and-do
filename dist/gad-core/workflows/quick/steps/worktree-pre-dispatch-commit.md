**Step 5.6: Pre-dispatch plan commit (worktree mode only)**

When `USE_WORKTREES !== "false"`, commit PLAN.md to the current branch **before** spawning the executor. This ensures the worktree inherits PLAN.md at its branch HEAD so the executor can read it via a worktree-rooted path — avoiding the main-repo path priming that triggers CC #36182 path-resolution drift.

Skip this step entirely if `USE_WORKTREES === "false"` (non-worktree mode: PLAN.md is committed in Step 8 as usual).

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
QUICK_PLAN_PARENT=""
QUICK_PLAN_COMMIT=""
if [ "${USE_WORKTREES}" != "false" ]; then
  QUICK_PLAN_PARENT=$(git rev-parse HEAD)
  COMMIT_DOCS=$(gad_run query config-get commit_docs --raw 2>/dev/null || echo "true")
  if [ "$COMMIT_DOCS" != "false" ]; then
    git add "${QUICK_DIR}/${quick_id}-PLAN.md"
    # No-op skip if nothing actually staged (idempotent re-runs).
    if git diff --cached --quiet -- "${QUICK_DIR}/${quick_id}-PLAN.md"; then
      echo "ℹ Pre-dispatch PLAN.md commit skipped (no staged changes)"
    else
      # Run hooks normally (#2924). If a project opts out via
      # workflow.worktree_skip_hooks=true, honor that opt-in only.
      SKIP_HOOKS=$(gad_run query config-get workflow.worktree_skip_hooks --raw 2>/dev/null || echo "false")
      if [ "$SKIP_HOOKS" = "true" ]; then
        git commit --no-verify -m "docs(${quick_id}): pre-dispatch plan for ${DESCRIPTION}" -- "${QUICK_DIR}/${quick_id}-PLAN.md" \
          || { echo "ERROR: pre-dispatch PLAN.md commit failed (--no-verify path). Aborting before executor dispatch." >&2; exit 1; }
      else
        git commit -m "docs(${quick_id}): pre-dispatch plan for ${DESCRIPTION}" -- "${QUICK_DIR}/${quick_id}-PLAN.md" \
          || { echo "ERROR: pre-dispatch PLAN.md commit failed — likely a pre-commit hook failure. Fix the hook output above (or set workflow.worktree_skip_hooks=true to bypass) and re-run." >&2; exit 1; }
      fi
      QUICK_PLAN_COMMIT=$(git rev-parse HEAD)
    fi
  fi
  if [ -z "$QUICK_PLAN_COMMIT" ]; then
    QUICK_PLAN_COMMIT=$(git rev-parse HEAD)
  fi
fi
```
