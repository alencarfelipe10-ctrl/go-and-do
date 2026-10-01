<purpose>
Interactive configuration of third-party integrations for GAD — search API keys
(Brave / Firecrawl / Exa), code-review CLI routing (`review.models.<cli>`), and
agent-skill injection (`agent_skills.<agent-type>`). Writes to
`.planning/config.json` via `gad-tools` so unrelated keys are
preserved, never clobbered.

This command is deliberately separate from `/gad-settings` (workflow toggles)
and any `/gad-settings-advanced` tuning surface. It exists because API keys and
cross-tool routing are *connectivity* concerns, not workflow or tuning knobs.
</purpose>

<security>
**API keys are secrets.** They are written as plaintext to
`.planning/config.json` — that is where secrets live on disk, and file
permissions are the security boundary. The UI must never display, echo, or
log the plaintext value. The workflow follows these rules:

- **Masking convention: `****<last-4>`** (e.g. `sk-abc123def456` → `****f456`).
  Strings shorter than 8 characters render as `****` with no tail so a short
  secret does not leak a meaningful fraction of its bytes. Unset values render
  as `(unset)`.
- **Plaintext is never echoed by AskUserQuestion descriptions, confirmation
  tables, or any log line.** It is not written to any file under `.planning/`
  other than `config.json` itself.
- **`config-set` output is masked** for keys in the secret set
  (`brave_search`, `firecrawl`, `exa_search`) — see
  `gad-core/bin/lib/secrets.cjs`.
- **Agent-type and CLI slug validation.** `agent_skills.<agent-type>` slug
  inputs are checked against `^[a-zA-Z0-9_-]+$` before any write; inputs
  containing path separators (`/`, `\`, `..`), whitespace, or shell
  metacharacters are rejected. This closes off skill-injection attacks on
  that open namespace (dynamic key pattern). For `review.models.<cli>` no
  slug-shape check is needed or performed: the gate is membership in the
  closed, registry-derived settable set (see the review-models section
  below), which subsumes slug shape — slug shape alone never makes a
  `review.models.*` key writable.
</security>

<required_reading>
Read all files referenced by the invoking prompt's execution_context before starting.
</required_reading>

<process>

<step name="ensure_and_load_config">
Ensure config exists and resolve the active config path (flat vs workstream, #2282):

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
RESPONSE_LANGUAGE=$(gad_run query config-get response_language --raw --default "" 2>/dev/null || echo "")
gad_run query config-ensure-section
if [[ -z "${GAD_CONFIG_PATH:-}" ]]; then
  if [[ -f .planning/active-workstream ]]; then
    WS=$(tr -d '\n\r' < .planning/active-workstream)
    GAD_CONFIG_PATH=".planning/workstreams/${WS}/config.json"
  else
    GAD_CONFIG_PATH=".planning/config.json"
  fi
fi
```

**If `response_language` is set:** All user-facing output of this workflow — narration between tool calls, status updates, progress notes, findings, questions, prompts, and explanations — MUST be presented in `{response_language}`. Technical terms, code, file paths, and subagent prompts stay in English — only user-facing output is translated.

Store `$GAD_CONFIG_PATH`. Every subsequent read/write uses it.
</step>

<step name="read_current">
Read the current config and compute a masked view for display. For each
integration field, compute one of:

- `(unset)` — field is null / missing
- `****<last-4>` — secret field that is populated (plaintext never shown)
- `<value>` — non-secret routing/skill string, shown as-is

```bash
BRAVE=$(gad_run query config-get brave_search --raw --default null)
FIRECRAWL=$(gad_run query config-get firecrawl --raw --default null)
EXA=$(gad_run query config-get exa_search --raw --default null)
SEARCH_GITIGNORED=$(gad_run query config-get search_gitignored --raw --default false)
```

For each secret key (`brave_search`, `firecrawl`, `exa_search`) the displayed
value is `****<last-4>` when set, never the raw string. Never echo the
plaintext to stdout, stderr, or any log.
</step>

<step name="section_1_search_integrations">

**Text mode (`workflow.text_mode: true` or `--text` flag):** Set
`TEXT_MODE=true` and replace every `AskUserQuestion` call with a plain-text
numbered list. Required for non-Claude runtimes.

Ask the user what they want to do for each search API key. For keys that are
already set, show `**** already set` and offer Leave / Replace / Clear. For
unset keys, offer Skip / Set.

```text
AskUserQuestion([
  {
    question: "Brave Search API key — used for web research during plan/discuss phases",
    header: "Brave",
    multiSelect: false,
    options: [
      // When already set:
      { label: "Leave (**** already set)", description: "Keep current value" },
      { label: "Replace", description: "Enter a new API key" },
      { label: "Clear", description: "Remove the stored key" }
      // When unset, use the two-option shape: Skip / Set.
    ]
  },
  {
    question: "Firecrawl API key — used for deep-crawl scraping",
    header: "Firecrawl",
    multiSelect: false,
    options: [ /* same Leave/Replace/Clear or Skip/Set */ ]
  },
  {
    question: "Exa Search API key — used for semantic search",
    header: "Exa",
    multiSelect: false,
    options: [ /* same Leave/Replace/Clear or Skip/Set */ ]
  },
  {
    question: "Include gitignored files in local code searches?",
    header: "Gitignored",
    multiSelect: false,
    options: [
      { label: "No (Recommended)", description: "Respect .gitignore. Safer — excludes secrets, node_modules, build artifacts." },
      { label: "Yes", description: "Include gitignored files. Useful when secrets/artifacts genuinely contain searchable intent." }
    ]
  }
])
```

For each "Set" or "Replace", follow with a text-input prompt that asks for the
key value. **The answer must not be echoed back** in subsequent question
descriptions or confirmation text. Write the value via:

```bash
gad_run query config-set brave_search "<value>"     # masked in output
gad_run query config-set firecrawl "<value>"        # masked in output
gad_run query config-set exa_search "<value>"       # masked in output
gad_run query config-set search_gitignored true|false
```

For "Clear", write `null`:

```bash
gad_run query config-set brave_search null
```
</step>

<step name="section_2_review_models">

`review.models.<cli>` is a closed, registry-derived map that tells the review
workflow which model id a reviewer lane uses. It is not an open namespace: a
`review.models.<cli>` key is settable only when that lane's capability
declares a `modelConfigKey`, and `config-set` accepts exactly those keys
(federated from the capability registry). No dynamic-key regex governs this
namespace — any other slug fails with `Unknown config key`.

Settable keys (the shipped registry's model-bearing lanes):

`review.models.agy` (Antigravity), `review.models.claude`, `review.models.codex`,
`review.models.cursor`, `review.models.gemini`, `review.models.kimi-code`,
`review.models.llama_cpp`, `review.models.lm_studio`, `review.models.ollama`,
`review.models.opencode`.

Reviewer lanes `qwen` and `coderabbit` declare no `modelConfigKey` — there is
nothing to configure for them here (whether they should have a per-lane model
key is a separate question, out of scope for this workflow).
If the user asks for one of those, say exactly that and skip.

```text
AskUserQuestion([
  {
    question: "Review model CLI mapping — what next?",
    header: "Review",
    multiSelect: false,
    options: [
      { label: "Configure CLI", description: "Pick a reviewer lane and set/clear its model id" },
      { label: "Done", description: "Finish this section" }
    ]
  }
])
```

If "Configure CLI" is selected, ask:

```text
AskUserQuestion([
  {
    question: "Which reviewer lane do you want to configure? (Common lanes below; any settable lane from the list above works — or type its slug)",
    header: "CLI",
    multiSelect: false,
    options: [
      { label: "Claude", description: "review.models.claude — defaults to session model when unset" },
      { label: "Codex", description: "review.models.codex — bare model id injected into --model, e.g. 'gpt-5'" },
      { label: "Gemini", description: "review.models.gemini — bare model id injected into -m, e.g. 'gemini-2.5-pro'" },
      { label: "OpenCode", description: "review.models.opencode — bare model id injected into --model, e.g. 'claude-sonnet-4'" }
    ]
  }
])
```

For a slug received as free text, check it against the settable set above.
If it is not one of the settable keys, print:

```text
Rejected: review.models.<slug> is not settable — only the reviewer lanes whose
keys are enumerated above can be configured here. (qwen and coderabbit have no
per-lane model key.)
```

and re-prompt.

For the selected lane, show the current value (or `(unset)`) and offer
Leave / Replace / Clear, followed by a text-input prompt for the model id
string. Write via:

```bash
gad_run query config-set review.models.<cli> "<model id>"
```

After each update, return to the "Review model CLI mapping — what next?" question.
Loop until the user selects "Done".
</step>

<step name="section_3_agent_skills">

`agent_skills.<agent-type>` injects extra skill names into an agent's spawn
frontmatter. The slug is user-extensible, so input is free-text validated
against `^[a-zA-Z0-9_-]+$`. Inputs with path separators, spaces, or shell
metacharacters are rejected.

```text
AskUserQuestion([
  {
    question: "Agent skills mapping — what next?",
    header: "Agent Skills",
    multiSelect: false,
    options: [
      { label: "Configure agent", description: "Pick an agent type and set/clear skills" },
      { label: "Done", description: "Finish this section" }
    ]
  }
])
```

If "Configure agent" is selected, ask:

```text
AskUserQuestion([
  {
    question: "Configure agent_skills for which agent type?",
    header: "Agent Type",
    multiSelect: false,
    options: [
      { label: "gad-executor", description: "Skills injected when spawning executor agents" },
      { label: "gad-planner", description: "Skills injected when spawning planner agents" },
      { label: "gad-verifier", description: "Skills injected when spawning verifier agents" },
      { label: "Custom…", description: "Enter a custom agent-type slug" }
    ]
  }
])
```

For "Custom…", prompt for a slug and validate it matches
`^[a-zA-Z0-9_-]+$`. If it fails validation, print:

```text
Rejected: agent-type '<slug>' must match [a-zA-Z0-9_-]+ (no path separators,
spaces, or shell metacharacters).
```

and re-prompt.

For a selected slug, prompt for the skill list (text input; a comma-separated
reply is fine). Show the current value if any, offer Leave / Replace / Clear.

Split the reply before writing: the resolver never splits strings, so a
comma-joined string would be stored as ONE skill path that silently fails
resolution at spawn time (#3651 — `gad-core/references/planning-config.md`:
"Paths cannot be comma-joined into one string; each path must be its own
array element"). Split on commas, trim each entry, drop empty entries, reject
any entry containing a quote character (`'` or `"` — it cannot be written
safely through the single-quoted form), and write the JSON array form:

```bash
gad_run query config-set agent_skills.<slug> '["skills/alpha","skills/beta"]'
```

A single skill may be written as one bare string or a one-element array —
both resolve identically.

After each update, return to the "Agent skills mapping — what next?" question.
Loop until "Done".
</step>

<step name="confirm">
Display the masked confirmation table. **No plaintext API keys appear in this
output under any circumstance.**

```text
### GAD ► INTEGRATIONS UPDATED

Search Integrations
| Field              | Value             |
|--------------------|-------------------|
| brave_search       | ****<last-4>      |  (or "(unset)")
| firecrawl          | ****<last-4>      |
| exa_search         | ****<last-4>      |
| search_gitignored  | true | false      |

Code Review CLI Routing
| Lane        | Model id                             |
|-------------|--------------------------------------|
| <lane>      | <value or (unset)>                   |
| ...         | ... one row per lane the user set    |

Agent Skills Injection
| Agent Type       | Skills                    |
|------------------|---------------------------|
| <slug>           | <skill-a, skill-b>        |
| ...              | ...                       |

Notes:
- API keys are stored plaintext in .planning/config.json. The confirmation
  table above never displays plaintext — keys appear as ****<last-4>.
- Plaintext is not echoed back by this workflow, not written to any log,
  and not displayed in error messages.

Quick commands:
- /gad-settings — workflow toggles and model profile
- /gad-set-profile <profile> — switch model profile
```
</step>

</process>

<success_criteria>
- [ ] Current config read from `$GAD_CONFIG_PATH`
- [ ] User presented with three sections: Search Integrations, Review CLI Routing, Agent Skills Injection
- [ ] API keys written plaintext only to `config.json`; never echoed, never logged, never displayed
- [ ] Masked confirmation table uses `****<last-4>` for set keys and `(unset)` for null
- [ ] `agent_skills.<agent-type>` slugs validated against `[a-zA-Z0-9_-]+` before write; `review.models.<cli>` slugs accepted only from the registry-derived settable set; skill lists written as JSON arrays (never comma-joined strings)
- [ ] Config merge preserves all keys outside the three sections this workflow owns
</success_criteria>
