<step name="handle_partial_wave_execution">
If `WAVE_FILTER` was used, re-run plan discovery after execution:

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
POST_PLAN_INDEX=$(gad_run query phase-plan-index "${PHASE_NUMBER}")
```

Apply the same "incomplete" filtering rules as earlier:
- ignore plans with `has_summary: true`
- if `--gaps-only`, only consider `gap_closure: true` plans

**If incomplete plans still remain anywhere in the phase:**
- STOP here
- Do NOT run phase verification
- Do NOT mark the phase complete in ROADMAP/STATE
- Present:

```markdown
## Wave {WAVE_FILTER} Complete

Selected wave finished successfully. This phase still has incomplete plans, so phase-level verification and completion were intentionally skipped.

/gad-execute-phase {phase} ${GAD_WS}                # Continue remaining waves
/gad-execute-phase {phase} --wave {next} ${GAD_WS}  # Run the next wave explicitly
```

**If no incomplete plans remain after the selected wave finishes:**
- continue with the normal phase-level verification and completion flow below
- this means the selected wave happened to be the last remaining work in the phase
</step>
