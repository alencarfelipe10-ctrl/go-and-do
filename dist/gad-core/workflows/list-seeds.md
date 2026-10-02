@~/.claude/gad-core/references/response-language-directive.md

<purpose>
List captured seeds for browsing and audit, with an optional status filter. Read-only — never mutates seeds.
</purpose>

<required_reading>
Read all files referenced by the invoking prompt's execution_context before starting.
</required_reading>

<process>

<step name="load_seeds">
Load seed context. An optional status filter (e.g. `dormant`, `active`, `triggered`) may follow `--list-seeds`.

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; _gad_id_ok() { case "$("$1" runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') return 0;; *) return 1;; esac; }; _gad_homes() { _gad_at "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; elif _gad_homes; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; _gad_id_ok gad_run && GAD_IDENTITY_STATUS=ok; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
SEEDS=$(gad_run list-seeds "$STATUS_FILTER")
if [[ "$SEEDS" == @file:* ]]; then SEEDS=$(cat "${SEEDS#@file:}"); fi
```

Replace `$STATUS_FILTER` with the filter token from `$ARGUMENTS` if one was given, otherwise omit it.

Extract from the JSON: `count`, `seeds[]` (each has `seed_id`, `status`, `scope`, `trigger_when`, `planted`, `title`), and `summary` (a `{ status: count }` map).
</step>

<step name="empty_case">
If `count` is 0:
```
No seeds found.

Plant one with /gad-capture --seed "<forward-looking idea>".
```
(If a status filter was given and nothing matched, say so: `No seeds with status "<filter>".`) Exit.
</step>

<step name="render_table">
Render the seeds as a table, sorted by `seed_id` (already sorted by the tool). Truncate `trigger_when` and `title` to keep the table readable.

```
Seeds

---
ID        Status     Scope    Trigger                  Title
SEED-001  dormant    large    when websockets land     Real-time collaboration
SEED-006  triggered  medium   MILE-04 planning         Remove legacy auth crates

---
<count> seeds  (<summary rendered as "N status" pairs, e.g. "1 dormant, 1 triggered">)
```

Then offer next actions as plain text (no mutation here):
```
- /gad-capture --seed --enrich <ID>   enrich a seed with trigger, why, and scope
- /gad-capture --list-seeds <status>  filter by status
```
</step>

</process>

<success_criteria>
- [ ] Seeds listed with ID, status, scope, trigger, and title
- [ ] Status filter applied when provided
- [ ] Empty / no-match case handled with guidance
- [ ] Summary line shows total and per-status counts
- [ ] No seed files were modified (read-only)
</success_criteria>
