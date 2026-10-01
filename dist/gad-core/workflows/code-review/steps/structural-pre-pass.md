When `FALLOW_ENABLED=true`:

1) Resolve binary via `node_modules/.bin/fallow` first, then PATH.
```bash
FALLOW_BIN=$(FALLOW_CWD="$(pwd)" node -e "
const { resolveFallowBinary } = require('./gad-core/bin/lib/fallow-runner.cjs');
const resolved = resolveFallowBinary({ cwd: process.env.FALLOW_CWD });
if (resolved) process.stdout.write(resolved);
")
```

2) If binary is missing, fail with actionable message:
```bash
if [ -z \"$FALLOW_BIN\" ]; then
  echo \"Error: fallow is enabled but no binary was found.\"
  echo \"Install fallow via \`npm install -D fallow\` or \`cargo install fallow\`.\"
  # Exit workflow
fi
```

3) Execute structural pass and persist JSON (bounded at 120s). Note: `fallow audit` exits 0 when clean and 1 when issues are found — BOTH are successful runs. Only a timeout (124), usage error (2), or crash yields no usable JSON; success is decided by whether the output parses as a valid fallow report, not by exit code:
```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
FALLOW_JSON_PATH="${PHASE_DIR}/FALLOW.json"
FALLOW_STDERR_TMP=$(mktemp)

# Phase scope uses fallow's native changed-files scoping (--changed-since <base>).
# Derive the phase base commit; if none is found, fall back to repo scope (fallow
# auto-detects the base branch). #3191/#3503: the grep is the SAME anchored,
# Phase-directory-anchor derivation, lockstep with the workflow's Tier-3
# scope step (#3191/#3995): base = the parent of the first commit that added
# anything under the phase's own directory. Commit subjects carry no milestone
# bound — a same-numbered phase in a previous milestone used to win the grep.
# #4467: the BASE half above is lockstep with Tier 3 (#3995); the TIP is not.
# fallow's own --changed-since is one-sided by design (no upper-bound flag
# exists in fallow 2.70.0 — --diff-file only scopes line ranges within the
# hot-path-touched verdict, it is not a general file-scoping control), so
# reviewing an earlier phase after a later one has landed pulls the later
# phase's files into this pass's audited set. Do not assume this step and
# Tier 3's scope step agree on the tip just because they agree on the base.
FALLOW_SCOPE_ARGS=()
if [ \"$FALLOW_SCOPE\" = \"phase\" ]; then
  # #3995: phase-directory anchor — same derivation as the Tier-3 scope step
  # (lockstep per #3191). A phase number is unique within a milestone, not a
  # repository; the former message grep matched previous milestones'
  # same-numbered phases and tail -1 selected the oldest.
  FALLOW_PHASE_START=$(git log --format=\"%H\" --diff-filter=A -- \"${PHASE_DIR}\" 2>/dev/null | tail -1)
  if [ -n \"$FALLOW_PHASE_START\" ]; then
    if git rev-parse \"${FALLOW_PHASE_START}^\" >/dev/null 2>&1; then
      FALLOW_BASE=\"${FALLOW_PHASE_START}^\"
    else
      FALLOW_BASE=\"${FALLOW_PHASE_START}\"
    fi
    FALLOW_SCOPE_ARGS=(--changed-since \"$FALLOW_BASE\")
  fi
fi

gad_run run-with-timeout 120 -- \"$FALLOW_BIN\" audit --format json --quiet --max-crap \"$FALLOW_MAX_CRAP\" \"${FALLOW_SCOPE_ARGS[@]+\"${FALLOW_SCOPE_ARGS[@]}\"}\" > \"${FALLOW_JSON_PATH}.tmp\" 2>\"$FALLOW_STDERR_TMP\"
FALLOW_EXIT=$?

# fallow exits 0 (clean) or 1 (issues found) — BOTH are successful runs that produce a
# valid JSON report. Only a timeout (124), usage error (2), or crash yields no usable JSON.
# Decide success by whether the output parses as a fallow report, not by exit code.
FALLOW_OK=$(FALLOW_TMP=\"${FALLOW_JSON_PATH}.tmp\" node -e \"
  try {
    const fs = require('fs');
    const txt = fs.readFileSync(process.env.FALLOW_TMP, 'utf8');
    const o = JSON.parse(txt);
    process.stdout.write(o && typeof o === 'object' && 'verdict' in o ? '1' : '0');
  } catch { process.stdout.write('0'); }
\")
if [ \"$FALLOW_OK\" != \"1\" ]; then
  FALLOW_STDERR_SUMMARY=$(head -5 \"$FALLOW_STDERR_TMP\")
  rm -f \"${FALLOW_JSON_PATH}.tmp\" \"$FALLOW_STDERR_TMP\"
  # #2667: distinguish a hard EXECUTION failure (the binary was found at step 1
  # but would not run) from the binary-missing path (step 2). Exit 124 = timeout,
  # 2 = usage error, 125 = spawn failure (e.g. Windows EINVAL on a .cmd shim —
  # CVE-2024-27980, now mediated by run-with-timeout), 126/127 = not executable /
  # not found. A non-zero exit here with a resolved binary means fallow is
  # installed but did not produce a report — surface that loudly so a Windows
  # user does not mistake it for "fallow absent".
  case \"$FALLOW_EXIT\" in
    124) FALLOW_FAIL_KIND=\"timed out\" ;;
    2)   FALLOW_FAIL_KIND=\"usage error\" ;;
    125) FALLOW_FAIL_KIND=\"spawn failure (the binary was found but did not start — e.g. a Windows .cmd shim; run-with-timeout mediates this)\" ;;
    126) FALLOW_FAIL_KIND=\"not executable\" ;;
    127) FALLOW_FAIL_KIND=\"not found\" ;;
    *)   FALLOW_FAIL_KIND=\"crashed\" ;;
  esac
  echo \"WARNING: fallow structural pre-pass failed (${FALLOW_FAIL_KIND}, exit ${FALLOW_EXIT}): ${FALLOW_STDERR_SUMMARY}\"
  FALLOW_JSON_PATH=\"\"
else
  mv \"${FALLOW_JSON_PATH}.tmp\" \"$FALLOW_JSON_PATH\"
  rm -f \"$FALLOW_STDERR_TMP\"
fi
```

On any failure of the structural pre-pass (binary missing at step 2, or an execution failure here — timeout, spawn failure, crash, empty output, or unparseable JSON), the workflow continues with no `<structural_findings>` injection; the reviewer agent receives a normal review request. The WARNING above names the failure KIND so a hard execution failure (e.g. a Windows `.cmd` spawn failure) is not mistaken for an absent optional dependency.

4) Optional MCP bridge path (runtime-dependent):
- If `FALLOW_MCP=true`, set reviewer input mode to MCP-backed structural findings.
- Otherwise pass static JSON findings from `FALLOW.json`.
