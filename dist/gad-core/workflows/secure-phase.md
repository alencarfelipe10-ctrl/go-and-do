<purpose>
Verify threat mitigations for a completed phase. Confirm PLAN.md threat register dispositions are resolved. Update SECURITY.md.
</purpose>

<required_reading>
@~/.claude/gad-core/references/ui-brand.md
</required_reading>

<available_agent_types>
Valid GAD subagent types (use exact names — do not fall back to 'general-purpose'):
- gad-security-auditor — Verifies threat mitigation coverage
</available_agent_types>

<process>

## 0. Initialize

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
RESPONSE_LANGUAGE=$(gad_run query config-get response_language --raw --default "" 2>/dev/null || echo "")
INIT=$(gad_run query init.phase-op "${PHASE_ARG}")
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
AGENT_SKILLS_AUDITOR=$(gad_run query agent-skills gad-security-auditor)
```

**If `response_language` is set:** All user-facing output of this workflow — narration between tool calls, status updates, progress notes, findings, questions, prompts, and explanations — MUST be presented in `{response_language}`. Technical terms, code, file paths, and subagent prompts stay in English — only user-facing output is translated.

Parse: `phase_dir`, `phase_number`, `phase_name`, `phase_slug`, `padded_phase`.

```bash
AUDITOR_MODEL=$(gad_run query resolve-model gad-security-auditor --raw)
VERIFY_POST_HOOKS_JSON=$(gad_run loop render-hooks verify:post --raw)
SECURITY_ASVS=$(gad_run query config-get workflow.security_asvs_level --raw 2>/dev/null || echo "1")
SECURITY_BLOCK_ON=$(gad_run query config-get workflow.security_block_on --raw 2>/dev/null || echo "high")
```

Resolve active step hooks from `VERIFY_POST_HOOKS_JSON` where `kind == "step"` and `ref.skill == "secure-phase"`.

If no active secure-phase step hook exists: exit with "Security enforcement disabled. Enable via /gad-settings."

Display banner: `GAD > SECURE PHASE {N}: {name}`

## 1. Detect Input State

```bash
SECURITY_FILE=$(ls "${PHASE_DIR}"/*-SECURITY.md 2>/dev/null | head -1)
PLAN_FILES=$(ls "${PHASE_DIR}"/*-PLAN.md 2>/dev/null)
SUMMARY_FILES=$(ls "${PHASE_DIR}"/*-SUMMARY.md 2>/dev/null)
```

- **State A** (`SECURITY_FILE` non-empty): Audit existing
- **State B** (`SECURITY_FILE` empty, `PLAN_FILES` and `SUMMARY_FILES` non-empty): Run from artifacts
- **State C** (`SUMMARY_FILES` empty): Exit — "Phase {N} not executed. Run /gad-execute-phase {N} first."

## 2. Discovery

### 2a. Read Phase Artifacts

Read PLAN.md — extract `<threat_model>` block: trust boundaries, STRIDE register (`threat_id`, `category`, `component`, `severity`, `disposition`, `mitigation_plan`).

### 2b. Read Summary Threat Flags

Read SUMMARY.md — extract `## Threat Flags` entries.

### 2c. Build Threat Register

Per threat: `{ threat_id, category, component, severity, disposition, mitigation_pattern, files_to_check }`

Also set `register_authored_at_plan_time: true` if **at least one** PLAN file contained a parseable `<threat_model>` block; `false` if no PLAN files had any `<threat_model>` block (legacy phase authored before formal threat modelling was standard).

## 3. Threat Classification

Classify each threat:

| Status | Criteria |
|--------|----------|
| CLOSED | mitigation found OR accepted risk documented in SECURITY.md OR transfer documented |
| OPEN | none of the above |

Build: `{ threat_id, category, component, severity, disposition, status, evidence }`

**Short-circuit rule:**
- If `threats_open: 0 AND register_authored_at_plan_time: true AND asvs_level == 1` → skip to Step 6 directly. No open threats at or above the block threshold remain (threats_open: 0); below-threshold open threats may remain and are non-blocking. L1 grep-depth is sufficient; no deeper verification required.
- If `threats_open: 0 AND register_authored_at_plan_time: true AND asvs_level >= 2` → **do NOT skip**. The preliminary threat classification is grep-level (L1 depth) and is insufficient for L2/L3. Proceed to Step 5 (spawn the auditor) so that L2 boundary-placement checks and L3 end-to-end trace checks are performed. Skipping the auditor here would defeat ASVS level scaling for "clean" phases.
- If `threats_open: 0 AND register_authored_at_plan_time: false` → **do NOT skip**. Empty-by-no-planning must not rubber-stamp a clean SECURITY.md. Proceed to Step 5 in **retroactive-STRIDE mode** — the auditor builds a register from implementation files first, then verifies mitigations.
- If `threats_open > 0` → proceed to Step 4 (present threat plan to user).

## 4. Present Threat Plan

**Text mode (`workflow.text_mode: true` in config or `--text` flag):** Set `TEXT_MODE=true` if `--text` is present in `$ARGUMENTS` OR `text_mode` from init JSON is `true`. When TEXT_MODE is active, replace every `AskUserQuestion` call with a plain-text numbered list and ask the user to type their choice number. This is required for non-Claude runtimes (OpenAI Codex, Gemini CLI, etc.) where `AskUserQuestion` is not available.
Call AskUserQuestion with threat table and options:
1. "Verify all open threats" → Step 5
2. "Accept all open — document in accepted risks log" → add to SECURITY.md accepted risks, set all CLOSED, Step 6
3. "Cancel" → exit

## 5. Spawn gad-security-auditor

**Auditor constraint — varies by register origin:**

- `register_authored_at_plan_time: true` — **Verify mitigations exist** — do not scan for new threats. The register is complete; verify each threat's mitigation is present in the implementation.
- `register_authored_at_plan_time: false` (retroactive-STRIDE mode) — **Retroactive-STRIDE: build a STRIDE register from implementation files first, then verify mitigations.** The phase was authored before formal threat modelling; the auditor must construct the register from scratch before verifying.

Substitute `{SECURITY_ASVS}` with the value of `$SECURITY_ASVS` and `{SECURITY_BLOCK_ON}` with the value of `$SECURITY_BLOCK_ON` resolved in Step 0 via `config-get`.

Print: `◆ Spawning security auditor... (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze)`

<!-- #2508 runtime-aware-dispatch -->

> **Runtime-aware dispatch (#2508 Phase 4).** GAD workflows dispatch specialized subagents by role. Before dispatching on a built-in-only runtime (kimi-code — three built-ins only), resolve the role to a built-in via `gad_run query resolve-dispatch-type --requested <role> --raw`. On named-dispatch runtimes (Claude/OpenCode/…) the role is returned unchanged; on kimi-code it maps to `coder`/`explore`/`plan` by role-suffix. The persona rides `${AGENT_SKILLS_<ROLE>}` (Phase 3) regardless. See @gad-core/references/runtime-aware-dispatch.md.

<!-- #2517 model-omit-on-inherit -->

> **Model omission (#2517).** Omit the `model` parameter entirely when the value it would carry (`AUDITOR_MODEL`) is `"inherit"` or empty. An empty value 404s on runtimes without native tier aliases — the default on non-Claude runtimes. Omitting it inherits the orchestrator's model. See @gad-core/references/model-profile-resolution.md.

```
Agent(
  prompt="Read $HOME/.claude/agents/gad-security-auditor.md for instructions.\n\n" +
    "<required_reading>{PLAN, SUMMARY, impl files, SECURITY.md}</required_reading>" +
    "<threat_register>{threat register}</threat_register>" +
    "<config>asvs_level: {SECURITY_ASVS}, block_on: {SECURITY_BLOCK_ON}</config>" +
    "<constraints>Never modify implementation files. Verify mitigations exist — do not scan for new threats. Escalate implementation gaps. Return a structured verdict only — do NOT write SECURITY.md (the orchestrator owns the file write).</constraints>" +
    "${AGENT_SKILLS_AUDITOR}",
  subagent_type="gad-security-auditor",
  model="{AUDITOR_MODEL}",
  description="Verify threat mitigations for Phase {N}"
)
```

> **ORCHESTRATOR RULE — CODEX RUNTIME**: After calling Agent() above, stop working on this task immediately. Do not read more files, edit code, or run tests related to this task while the subagent is active. Wait for the subagent to return its result. This prevents duplicate work, conflicting edits, and wasted context. Only resume when the subagent result is available.

Handle return:
- `## SECURED` → record closures → Step 6
- `## OPEN_THREATS` → record closed + open, present user with accept/block choice → Step 6
- `## ESCALATE` → present to user → Step 6

## 6. Write/Update SECURITY.md

**State B (create):**
1. Read template from `$HOME/.claude/gad-core/templates/SECURITY.md`
2. Fill: frontmatter, threat register, accepted risks, audit trail
3. Write to `${PHASE_DIR}/${PADDED_PHASE}-SECURITY.md`

**State A (update):**
1. Update threat register statuses, append to audit trail:

```markdown
## Security Audit {date}
| Metric | Count |
|--------|-------|
| Threats found | {N} |
| Closed | {M} |
| Open | {K} |
```

**ENFORCING GATE:** If `threats_open > 0` after all options exhausted (user did not accept, not all verified closed):

```
GAD > PHASE {N} SECURITY BLOCKED
{K} blocking threats open — phase advancement blocked until threats_open: 0
▶ Fix mitigations then re-run: /gad-secure-phase {N}
▶ Or document accepted risks in SECURITY.md and re-run.
```

Do NOT emit next-phase routing. Stop here.

## 7. Commit

```bash
gad_run query commit "docs(phase-${PHASE}): add/update security threat verification" \
  --files "${PHASE_DIR}/${PADDED_PHASE}-SECURITY.md"
```

## 8. Results + Routing

**Secured (threats_open: 0):**
```
GAD > PHASE {N} THREAT-SECURE
threats_open: 0 — no blocking threats remain (threats_open: 0).
▶ /gad-validate-phase {N}    validate test coverage
▶ /gad-verify-work {N}       run UAT
```

Display `/clear` reminder.

</process>

<success_criteria>
- [ ] Security enforcement checked — exit if false
- [ ] Input state detected (A/B/C) — state C exits cleanly
- [ ] PLAN.md threat model parsed, register built
- [ ] SUMMARY.md threat flags incorporated
- [ ] threats_open: 0 AND register_authored_at_plan_time: true AND asvs_level == 1 → skip directly to Step 6 (L1 grep-depth sufficient)
- [ ] threats_open: 0 AND register_authored_at_plan_time: true AND asvs_level >= 2 → do NOT skip; auditor spawned for L2/L3 deep verification
- [ ] threats_open: 0 AND register_authored_at_plan_time: false → retroactive-STRIDE mode (Step 5), not skipped
- [ ] User gate with threat table presented
- [ ] Auditor spawned with complete context
- [ ] All three return formats (SECURED/OPEN_THREATS/ESCALATE) handled
- [ ] SECURITY.md created or updated
- [ ] threats_open > 0 BLOCKS advancement (no next-phase routing emitted)
- [ ] Results with routing presented on success
</success_criteria>
