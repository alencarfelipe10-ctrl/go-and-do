@~/.claude/gad-core/references/response-language-directive.md

# Ultraplan Phase Workflow [BETA]

Offload GAD's plan phase to Claude Code's ultraplan cloud infrastructure.

⚠ **BETA feature.** Ultraplan is in research preview and may change. This workflow is
intentionally isolated from /gad-plan-phase so upstream changes to ultraplan cannot
affect the core planning pipeline.

---

<step name="banner">

Display the stage banner:

```text
### GAD ► ULTRAPLAN PHASE  ⚠ BETA
Ultraplan is in research preview (Claude Code v2.1.91+).
Use /gad-plan-phase for stable local planning.
```

</step>

---

<step name="runtime_gate">

Check that the session is running inside Claude Code:

```bash
if [ "$CLAUDECODE" = "1" ] || [ -n "$CLAUDE_CODE_ENTRYPOINT" ]; then
  CC_VERSION="$(claude --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
  if [ -n "$CC_VERSION" ] && [ "$(printf '%s\n' "2.1.91" "$CC_VERSION" | sort -V | head -n1)" = "2.1.91" ]; then
    echo "claude-code:${CC_VERSION}"
  else
    echo ""
  fi
else
  echo ""
fi
```

If the output is empty or unset, display the following error and exit:

```text
### RUNTIME ERROR

/gad-ultraplan-phase requires Claude Code.
ultraplan is not available in this runtime.

Use /gad-plan-phase for local planning instead.
```

</step>

---

<step name="initialize">

Parse phase number from `$ARGUMENTS`. If no phase number is provided, detect the next
unplanned phase from the roadmap (same logic as /gad-plan-phase).

Load GAD phase context:

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
INIT=$(gad_run query init.plan-phase "$PHASE")
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
```

Parse JSON for: `phase_found`, `phase_number`, `phase_name`, `phase_slug`, `padded_phase`,
`phase_dir`, `roadmap_path`, `requirements_path`, `research_path`, `planning_exists`.

**If `planning_exists` is false:** Error and exit:

```text
No .planning directory found. Initialize the project first:

/gad-new-project
```

**If `phase_found` is false:** Error with the phase number provided and exit.

Display detected phase:

```text
Phase {N}: {phase name}
```

</step>

---

<step name="build_prompt">

Build the ultraplan prompt from GAD context.

1. Read the phase scope from ROADMAP.md — extract the goal, deliverables, and scope for
   the target phase.

2. Read REQUIREMENTS.md if it exists (`requirements_path` is not null) — extract a
   concise summary (key requirements relevant to this phase, not the full document).

3. Read RESEARCH.md if it exists (`research_path` is not null) — extract a concise
   summary of technical findings. Including this reduces redundant cloud research.

Construct the prompt:

```text
Plan phase {phase_number}: {phase_name}

## Phase Scope (from ROADMAP.md)

{phase scope block extracted from ROADMAP.md}

## Requirements Context

{requirements summary, or "No REQUIREMENTS.md found — infer from phase scope."}

## Existing Research

{research summary, or "No RESEARCH.md found — research from scratch."}

## Output Format

Produce a GAD PLAN.md with the following YAML frontmatter:

---
phase: "{padded_phase}-{phase_slug}"
plan: "{padded_phase}-01"
type: "feature"
wave: 1
depends_on: []
files_modified: []
autonomous: true
must_haves:
  truths: []
  artifacts: []
---

Then a ## Plan section with numbered tasks. Each task should have:
- A clear imperative title
- Files to create or modify
- Specific implementation steps

Keep the plan focused and executable.
```

</step>

---

<step name="return_path_card">

Display the return-path instructions **before** triggering ultraplan so they are visible
in the terminal scroll-back after ultraplan launches:

```text
### WHEN THE PLAN IS READY — WHAT TO DO

When ◆ ultraplan ready appears in your terminal:

  1. Open the session link in your browser
  2. Review the plan — use inline comments and emoji reactions to give feedback
  3. Ask Claude to revise until you're satisfied
  4. Click "Approve plan and teleport back to terminal"
  5. At the terminal dialog, choose Cancel  ← saves the plan to a file
  6. Note the file path Claude prints
  7. Run: /gad-import --from <the file path>

/gad-import will run conflict detection, convert to GAD format,
validate via plan-checker, update ROADMAP.md, and commit.

### Launching ultraplan for Phase {N}: {phase_name}...
```

</step>

---

<step name="trigger">

Trigger ultraplan with the constructed prompt:

```text
/ultraplan {constructed prompt from build_prompt step}
```

Your terminal will show a `◇ ultraplan` status indicator while the remote session works.
Use `/tasks` to open the detail view with the session link, agent activity, and a stop action.

</step>
