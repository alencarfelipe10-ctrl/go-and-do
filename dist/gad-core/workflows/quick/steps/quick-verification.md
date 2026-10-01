**Step 6.5: Verification (only when `$VALIDATE_MODE`)**

Skip this step entirely if NOT `$VALIDATE_MODE`.

Display banner:
```
### GAD ► VERIFYING RESULTS

◆ Spawning verifier... (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze)
```

```
Agent(
  prompt="Verify quick task goal achievement.
Task directory: ${QUICK_DIR}
Task goal: ${DESCRIPTION}

<required_reading>
- ${QUICK_DIR}/${quick_id}-PLAN.md (Plan)
</required_reading>

${AGENT_SKILLS_VERIFIER}

Check must_haves against actual codebase. Create VERIFICATION.md at ${QUICK_DIR}/${quick_id}-VERIFICATION.md.",
  subagent_type="gad-verifier",
  model="{verifier_model}",
  description="Verify: ${DESCRIPTION}"
)
```

> **ORCHESTRATOR RULE — CODEX RUNTIME**: After calling Agent() above, stop working on this task immediately. Do not read more files, edit code, or run tests related to this task while the subagent is active. Wait for the subagent to return its result. This prevents duplicate work, conflicting edits, and wasted context. Only resume when the subagent result is available.

Read verification status via the canonical query (frontmatter-anchored, and total over its input space):
```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
STATUS=$(gad_run query verification.status "${QUICK_DIR}" --pick status 2>/dev/null)
```

`--pick status` returns the bare value, so this path needs **no `jq`**. That is deliberate: #2589
established that a `| jq -r '.field'` pipe yields an **empty** variable with no diagnostic on any
machine without jq — the default on Windows/Git-Bash — which here would route a perfectly good
`passed` verification into the recovery arm below.

Route on `$STATUS` and store the display string as `$VERIFICATION_STATUS` (consumed by the quick index row and the completion banner).

The query is **total**: beyond the verifier's own statuses it can also return `missing` (no `*-VERIFICATION.md`, or no `status` in its frontmatter), `unknown` (a value outside the verifier's schema) or `stale` (a summary newer than the verification file). Which one wins when more than one applies is the query's own precedence, not this table's concern — all three land in the same arm here. That arm is reachable in normal operation and must never be dropped.

| `$STATUS` | Action |
|--------|--------|
| `passed` | Store `$VERIFICATION_STATUS = "Verified"`, continue to step 7 |
| `human_needed` | Display items needing manual check, store `$VERIFICATION_STATUS = "Needs Review"`, continue |
| `gaps_found` | Display gap summary, offer: 1) Re-run executor to fix gaps, 2) Accept as-is. Store `$VERIFICATION_STATUS = "Gaps"` |
| anything else — `missing`, `unknown`, `stale`, or empty | Do **not** improvise a result. Report that verification produced no usable status, naming `$STATUS`, then offer: 1) Re-run the verifier, 2) Accept as-is without verification. Store `$VERIFICATION_STATUS = "Unverified (${STATUS:-no result})"` |

> **Why the status only, and not `next_action` / `next_command`.** The query projects those two for
> the phase pipeline — they name `execute-phase`, `plan-phase --gaps` and `verify-work`, and they
> append a phase-number argument taken from the directory basename. A quick task directory is named
> `${quick_id}-${slug}` with a date-derived `quick_id`, so that argument resolves to the date: for
> `260808-abc-some-slug` the projected recovery command carries `260808` as its phase argument — a
> date posing as a phase number.
> Quick therefore supplies its own recovery actions above. The split is the point:
> `readVerificationStatus` *discovers and parses* shape-agnostically — it scans whatever directory
> it is given for `*-VERIFICATION.md` — which is what makes the status half correct for
> `${QUICK_DIR}`; but it also reads that directory's basename as a phase token to build the
> projected commands, and that is the half quick must not use.
