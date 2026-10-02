# Planner — Load Graph Context

> Loaded by `gad-planner` at the `load_graph_context` step.

Check for a knowledge graph and read its freshness in one call. `status` resolves the
graph through `graphify.graph_path`, so it is also the presence gate — a bare
`ls` of the default location misses an umbrella graph shared across sibling repos:

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }
gad_run graphify status
```

If `exists` is `false`, continue without graph context — skip the rest of this step.

If the status response has `stale: true`, note for later: "Graph is {age_hours}h old -- treat semantic relationships as approximate." Include this annotation inline with any graph context injected below.

The same response carries `graph_path` — the resolved graph location. Substitute it for `<graph>` below. `graph_path` comes from `graphify.graph_path` in `.planning/config.json`, a config surface already trusted elsewhere; if it ever carried attacker-controlled content, the literal double-quoted substitution below would need escaping.

Query the graph for phase-relevant dependency context (single query per D-06). Prefer the `graphify` CLI when it is on PATH; fall back to the built-in reader otherwise:

```bash
if command -v graphify >/dev/null 2>&1; then
  graphify query "<phase-goal-keyword>" --graph "<graph>" --budget 2000
  graphify affected "<phase-goal-keyword>" --graph "<graph>" --depth 2
else
  gad_run graphify query "<phase-goal-keyword>" --budget 2000
fi
```

Why the CLI is preferred: it ranks seeds (IDF weighting, fuzzy matching) and applies context filters before traversal, where the built-in reader seeds by case-insensitive substring over label and description — so a term like "auth" seeds equally on `author` and `authorize` — and then expands a fixed two hops. `affected` answers "which subsystems may be affected by changes in this phase" directly, by reverse traversal; it has no built-in equivalent, so the fallback path runs the query alone.

The two paths return **different shapes**: the CLI emits prose, the built-in emits JSON with per-edge confidence tiers and `budget_met`/`budget_estimate`. `--budget` caps rendered output on the CLI and estimated payload bytes in the built-in — same flag name, different unit. Read whichever you get; do not assume a stable shape and do not paste raw output into PLAN.md.

Use the keyword that best captures the phase goal. Prefer the full domain word over a
prefix of it — on the fallback path a prefix is matched as a substring, so "auth" also
seeds on `author` and `authoring`. Examples:
- Phase "User Authentication" -> query term "authentication"
- Phase "Payment Integration" -> query term "payment"
- Phase "Database Migration" -> query term "migration"

If the query returns related nodes, incorporate as dependency context for planning:
- Which modules/files are semantically related to this phase's domain
- Which subsystems may be affected by changes in this phase
- Cross-document relationships that inform task ordering and wave structure

If nothing comes back, continue without graph context.
