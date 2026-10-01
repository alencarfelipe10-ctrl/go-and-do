@~/.claude/gad-core/references/response-language-directive.md

<purpose>
Remove an unstarted future phase from the project roadmap, delete its directory, renumber all subsequent phases to maintain a clean linear sequence, and commit the change. The git commit serves as the historical record of removal.
</purpose>

<required_reading>
Read all files referenced by the invoking prompt's execution_context before starting.
</required_reading>

<process>

<step name="parse_arguments">
Parse the command arguments:
- Argument is the phase number to remove (integer or decimal)
- Example: `/gad-remove-phase 17` → phase = 17
- Example: `/gad-remove-phase 16.1` → phase = 16.1

If no argument provided:

```
ERROR: Phase number required
Usage: /gad-remove-phase <phase-number>
Example: /gad-remove-phase 17
```

Exit.
</step>

<step name="init_context">
Load phase operation context:

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
INIT=$(gad_run query init.phase-op "${target}")
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
```

Extract: `phase_found`, `phase_dir`, `phase_number`, `commit_docs`, `roadmap_exists`.

Also read STATE.md and ROADMAP.md content for parsing current position.
</step>

<step name="validate_future_phase">
Verify the phase is a future phase (not started):

1. Compare target phase to current phase from STATE.md
2. Target must be > current phase number

If target <= current phase:

```
ERROR: Cannot remove Phase {target}

Only future phases can be removed:
- Current phase: {current}
- Phase {target} is current or completed

To abandon current work, use /gad-pause-work instead.
```

Exit.
</step>

<step name="confirm_removal">
Present removal summary and confirm:

```
Removing Phase {target}: {Name}

This will:
- Delete: .planning/phases/{target}-{slug}/
- Renumber all subsequent phases
- Update: ROADMAP.md, STATE.md

Proceed? (y/n)
```

Wait for confirmation.
</step>

<step name="execute_removal">
**Delegate the entire removal operation to `gad_run query phase.remove`:**

```bash
RESULT=$(gad_run query phase.remove "${target}")
```

If the phase has executed plans (SUMMARY.md files), the CLI will error. Use `--force` only if the user confirms:

```bash
RESULT=$(gad_run query phase.remove "${target}" --force)
```

The CLI handles:
- Deleting the phase directory
- Renumbering all subsequent directories (in reverse order to avoid conflicts)
- Renaming all files inside renumbered directories (PLAN.md, SUMMARY.md, etc.)
- Updating ROADMAP.md (removing section, renumbering all phase references, updating dependencies)
- Updating STATE.md (decrementing phase count)

Extract from result: `removed`, `directory_deleted`, `renamed_directories`, `renamed_files`, `roadmap_updated`, `state_updated`.
</step>

<step name="commit">
Stage and commit the removal:

```bash
gad_run query commit "chore: remove phase {target} ({original-phase-name})" --files .planning/
```

The commit message preserves the historical record of what was removed.
</step>

<step name="completion">
Present completion summary:

```
Phase {target} ({original-name}) removed.

Changes:
- Deleted: .planning/phases/{target}-{slug}/
- Renumbered: {N} directories and {M} files
- Updated: ROADMAP.md, STATE.md
- Committed: chore: remove phase {target} ({original-name})

---

## What's Next

Would you like to:
- `/gad-progress` — see updated roadmap status
- Continue with current phase
- Review roadmap

---
```
</step>

</process>

<anti_patterns>

- Don't remove completed phases (have SUMMARY.md files) without --force
- Don't remove current or past phases
- Don't manually renumber — use `gad_run query phase.remove` which handles all renumbering
- Don't add "removed phase" notes to STATE.md — git commit is the record
- Don't modify completed phase directories
</anti_patterns>

<success_criteria>
Phase removal is complete when:

- [ ] Target phase validated as future/unstarted
- [ ] `gad_run query phase.remove` executed successfully
- [ ] Changes committed with descriptive message
- [ ] User informed of changes
</success_criteria>
