@~/.claude/gad-core/references/response-language-directive.md

<purpose>
Lightweight codebase assessment. Spawns a single gad-codebase-mapper agent for one focus area,
producing targeted documents in `.planning/codebase/`.
</purpose>

<required_reading>
Read all files referenced by the invoking prompt's execution_context before starting.
</required_reading>

<available_agent_types>
Valid GAD subagent types (use exact names — do not fall back to 'general-purpose'):
- gad-codebase-mapper — Maps project structure and dependencies
</available_agent_types>

<process>

## Focus-to-Document Mapping

| Focus | Documents Produced |
|-------|-------------------|
| `tech` | STACK.md, INTEGRATIONS.md |
| `arch` | ARCHITECTURE.md, STRUCTURE.md |
| `quality` | CONVENTIONS.md, TESTING.md |
| `concerns` | CONCERNS.md |
| `tech+arch` | STACK.md, INTEGRATIONS.md, ARCHITECTURE.md, STRUCTURE.md |

## Step 1: Parse arguments and resolve focus

Parse the user's input for `--focus <area>`. Default to `tech+arch` if not specified.

Validate that the focus is one of: `tech`, `arch`, `quality`, `concerns`, `tech+arch`.

If invalid:
```
Unknown focus area: "{input}". Valid options: tech, arch, quality, concerns, tech+arch
```
Exit.

## Step 2: Check for existing documents

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
INIT=$(gad_run query init.map-codebase 2>/dev/null || echo "{}")
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
```

Parse JSON for: `mapper_model`, `commit_docs`, `search_gitignored`, `parallelization`, `subagent_timeout`, `date`, `codebase_dir`, `existing_maps`, `has_maps`, `planning_exists`, `codebase_dir_exists`.

Look up which documents would be produced for the selected focus (from the mapping table above).

For each target document, check if it already exists in `.planning/codebase/`:
```bash
ls -la .planning/codebase/{DOCUMENT}.md 2>/dev/null
```

If any exist, show their modification dates and ask:
```
Existing documents found:
  - STACK.md (modified 2026-04-03)
  - INTEGRATIONS.md (modified 2026-04-01)

Overwrite with fresh scan? [y/N]
```

If user says no, exit.

## Step 3: Create output directory

```bash
mkdir -p .planning/codebase
```

## Step 4: Spawn mapper agent

Spawn a single `gad-codebase-mapper` agent with the selected focus area:

Print: `◆ Spawning scanner... (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze)`

<!-- #2508 runtime-aware-dispatch -->

> **Runtime-aware dispatch (#2508 Phase 4).** GAD workflows dispatch specialized subagents by role. Before dispatching on a built-in-only runtime (kimi-code — three built-ins only), resolve the role to a built-in via `gad_run query resolve-dispatch-type --requested <role> --raw`. On named-dispatch runtimes (Claude/OpenCode/…) the role is returned unchanged; on kimi-code it maps to `coder`/`explore`/`plan` by role-suffix. The persona rides `${AGENT_SKILLS_<ROLE>}` (Phase 3) regardless. See @gad-core/references/runtime-aware-dispatch.md.

**#2517 model resolution:** `mapper_model` is the field `init.map-codebase` emits (parsed in Step 2) — this is the same binding `map-codebase.md` uses. **Omit the `model=` parameter entirely when `mapper_model` is `"inherit"` or empty**; do NOT pass `model=""` or `model="inherit"`, which 404s on non-Claude runtimes. Omitting inherits the orchestrator's model.

```
Agent(
  prompt="Scan this codebase with focus: {focus}. Write results to {codebase_dir}/. Produce only: {document_list}",
  subagent_type="gad-codebase-mapper",
  model="{mapper_model}"
)
```

> **ORCHESTRATOR RULE — CODEX RUNTIME**: After calling Agent() above, stop working on this task immediately. Do not read more files, edit code, or run tests related to this task while the subagent is active. Wait for the subagent to return its result. This prevents duplicate work, conflicting edits, and wasted context. Only resume when the subagent result is available.

## Step 5: Report

```
## Scan Complete

**Focus:** {focus}
**Documents produced:**
{list of documents written with line counts}

Use `/gad-map-codebase` for a comprehensive 4-area parallel scan.
```

</process>

<success_criteria>
- [ ] Focus area correctly parsed (default: tech+arch)
- [ ] Existing documents detected with modification dates shown
- [ ] User prompted before overwriting
- [ ] Single mapper agent spawned with correct focus
- [ ] Output documents written to .planning/codebase/
</success_criteria>
