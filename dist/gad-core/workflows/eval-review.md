<purpose>
Retroactive audit of an implemented AI phase's evaluation coverage. Standalone command that works on any GAD-managed AI phase. Produces a scored EVAL-REVIEW.md with gap analysis and remediation plan.

Use after /gad-execute-phase to verify that the evaluation strategy from AI-SPEC.md was actually implemented. Mirrors the pattern of /gad-ui-review and /gad-validate-phase.
</purpose>

<required_reading>
@~/.claude/gad-core/references/ai-evals.md
</required_reading>

<process>

## 0. Initialize

```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
RESPONSE_LANGUAGE=$(gad_run query config-get response_language --raw --default "" 2>/dev/null || echo "")
INIT=$(gad_run query init.phase-op "${PHASE_ARG}")
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
```

**If `response_language` is set:** All user-facing output of this workflow — narration between tool calls, status updates, progress notes, findings, questions, prompts, and explanations — MUST be presented in `{response_language}`. Technical terms, code, file paths, and subagent prompts stay in English — only user-facing output is translated.

Parse: `phase_dir`, `phase_number`, `phase_name`, `phase_slug`, `padded_phase`, `commit_docs`.

```bash
AUDITOR_MODEL=$(gad_run query resolve-model gad-eval-auditor --pick model 2>/dev/null || true)
AGENT_SKILLS_AUDITOR=$(gad_run query agent-skills gad-eval-auditor)
```

Display banner:
```
### GAD ► EVAL AUDIT — PHASE {N}: {name}
```

## 1. Detect Input State

```bash
SUMMARY_FILES=$(ls "${PHASE_DIR}"/*-SUMMARY.md 2>/dev/null)
AI_SPEC_FILE=$(ls "${PHASE_DIR}"/*-AI-SPEC.md 2>/dev/null | head -1)
EVAL_REVIEW_FILE=$(ls "${PHASE_DIR}"/*-EVAL-REVIEW.md 2>/dev/null | head -1)
```

**State A** — AI-SPEC.md + SUMMARY.md exist: Full audit against spec
**State B** — SUMMARY.md exists, no AI-SPEC.md: Audit against general best practices
**State C** — No SUMMARY.md: Exit — "Phase {N} not executed. Run /gad-execute-phase {N} first."

**Text mode (`workflow.text_mode: true` in config or `--text` flag):** Set `TEXT_MODE=true` if `--text` is present in `$ARGUMENTS` OR `text_mode` from init JSON is `true`. When TEXT_MODE is active, replace every `AskUserQuestion` call with a plain-text numbered list and ask the user to type their choice number. This is required for non-Claude runtimes (OpenAI Codex, Gemini CLI, etc.) where `AskUserQuestion` is not available.
**If `EVAL_REVIEW_FILE` non-empty:** Use AskUserQuestion:
- header: "Existing Eval Review"
- question: "EVAL-REVIEW.md already exists for Phase {N}."
- options:
  - "Re-audit — run fresh audit"
  - "View — display current review and exit"

If "View": display file, exit.
If "Re-audit": continue.

**If State B (no AI-SPEC.md):** Warn:
```
No AI-SPEC.md found for Phase {N}.
Audit will evaluate against general AI eval best practices rather than a phase-specific plan.
Consider running /gad-ai-integration-phase {N} before implementation next time.
```
Continue (non-blocking).

## 2. Gather Context Paths

Build file list for auditor:
- AI-SPEC.md (if exists — the planned eval strategy)
- All SUMMARY.md files in phase dir
- All PLAN.md files in phase dir

## 3. Spawn gad-eval-auditor

```
◆ Spawning eval auditor... (runs in a subagent — no output until it returns, ~1–5 min; expected, not a freeze)
```

Build prompt:

```markdown
Read $HOME/.claude/agents/gad-eval-auditor.md for instructions.

<objective>
Conduct evaluation coverage audit of Phase {phase_number}: {phase_name}
{If AI-SPEC exists: "Audit against AI-SPEC.md evaluation plan."}
{If no AI-SPEC: "Audit against general AI eval best practices."}
</objective>

<required_reading>
- {summary_paths}
- {plan_paths}
- {ai_spec_path if exists}
</required_reading>

<input>
ai_spec_path: {ai_spec_path or "none"}
phase_dir: {phase_dir}
phase_number: {phase_number}
phase_name: {phase_name}
padded_phase: {padded_phase}
state: {A or B}
</input>

${AGENT_SKILLS_AUDITOR}
```

Spawn as Task with model `AUDITOR_MODEL`.

## 4. Parse Auditor Result

Read the written EVAL-REVIEW.md. Extract:
- `overall_score`
- `verdict` (PRODUCTION READY | NEEDS WORK | SIGNIFICANT GAPS | NOT IMPLEMENTED)
- `critical_gap_count`

## 5. Display Summary

```
### GAD ► EVAL AUDIT COMPLETE — PHASE {N}: {name}

◆ Score: {overall_score}/100
◆ Verdict: {verdict}
◆ Critical Gaps: {critical_gap_count}
◆ Output: {eval_review_path}

{If PRODUCTION READY:}
  Next step: /gad-plan-phase (next phase) or deploy

{If NEEDS WORK:}
  Address critical gaps in EVAL-REVIEW.md, then re-run /gad-eval-review {N}

{If SIGNIFICANT GAPS or NOT IMPLEMENTED:}
  Review AI-SPEC.md evaluation plan. Critical eval dimensions are not implemented.
  Do not deploy until gaps are addressed.
```

## 6. Commit

```bash
gad_run query commit "docs({phase_slug}): add EVAL-REVIEW.md — score {overall_score}/100 ({verdict})" --files "${EVAL_REVIEW_FILE}"
```

</process>

<success_criteria>
- [ ] Phase execution state detected correctly
- [ ] AI-SPEC.md presence handled (with or without)
- [ ] gad-eval-auditor spawned with correct context
- [ ] EVAL-REVIEW.md written (by auditor)
- [ ] Score and verdict displayed to user
- [ ] Appropriate next steps surfaced based on verdict
- [ ] Committed if commit_docs enabled
</success_criteria>
