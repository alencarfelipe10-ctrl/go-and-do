# discuss-phase — finish block

Lazy block (D6): every step from `write_context` onwards lives here, plus
`reconcile_existing`. `discuss-phase.md` never inlines it — it is `Read` at each
border that enters one of these steps (end of the area loop, the `--auto`
objective skip, `check_existing → reconcile_existing`, and `modes/auto.md`'s
"go to `write_context`").

Order is fixed (D4): `write_context` (script) → `write_for_humans` (model) →
`dispatch_discuss_post_hooks` (model) → `finalize` (script). There is **no
re-read of the rendered CONTEXT** — the guard is the proof.

<step name="write_context">
The frame is rendered by script; you only complete the free-text fields still missing.

1. With `Write`, produce (only if non-empty): `$T/specifics.txt` (particular references, "I want it like X" moments — one per line), `$T/deferred.txt` (deferred ideas), `$T/discretion.txt` (final "Claude's Discretion" list — replaces the initial one), `$T/refs-more.txt` (refs collected during discussion), `$T/folded.txt` / `$T/reviewed.txt` (from `cross_reference_todos`).
2. One call renders, guards and re-checks with the real parser (it also persists the files above through the writer — never edit the rendered file):

```bash
. .planning/.discuss-tmp/env.sh
bash "$NOSSO/discuss-render-guard.sh" --root .
```

It prints `{"guard_exit": N, "render_exit": N, "context_path": "...", "msgs": [...], "msgs_truncadas": N, "log": "..."}`. `msgs` holds the last 60 log lines — the guard verdict and the coverage gate line are always among them; `log` (`$T/render-guard.log`) has everything when `msgs_truncadas > 0`.

`guard_exit: 0` (WARNs allowed — they are quality signals; fix what you can by adjusting the checkpoint JSON through the writer and re-running this block) → continue to `write_for_humans`. **`guard_exit: 2`** (structural corruption: missing/unbalanced/out-of-order tag, `<spec_lock>` without SPEC, SPEC missing from refs, parser `could-not-parse`, or a failed render) → **one** correction attempt (fix the checkpoint through the writer and re-run — the script is safe to run twice, that is the pass cap). If it fails again: **do not commit**, keep the checkpoint, and

```bash
. .planning/.discuss-tmp/env.sh
mv "$CONTEXT_PATH" "${CONTEXT_PATH%.md}.rejected.md"
```

then end with the bell `[guard] CONTEXT rejected: <reasons>` (in the /go-and-do this is `estado: falha`). The coverage gate line inside `msgs` is informational (`no trackable decisions` is expected on a skipped phase and must be declared in "Claude's Discretion").

**SPEC integration is automatic:** `<spec_lock>` comes from `scope-in/out.txt`, the SPEC is first in `<canonical_refs>` with "Locked requirements — MUST read before planning"; requirements text is never duplicated into `<decisions>`.
</step>

<step name="write_for_humans">
Write `${phase_dir}/for-humans/${padded_phase}-CONTEXT-FH.md` per `@~/.claude/gad-core/references/for-humans.md` (the 5-section skeleton; here it translates the decisions document: "o que decidimos e por quê", not the spec). **Do not render the `.html` here** — `finalize` runs `fh-render.py` before building the commit's `FILES`.
</step>

<step name="dispatch_discuss_post_hooks">
```bash
. .planning/.discuss-tmp/env.sh
ARGUMENTS="$ARGUMENTS" bash "$NOSSO/discuss-hooks-filter.sh"
```

(`ARGUMENTS` **must** be passed through — `env.sh` does not carry it, and without it the script cannot see `--auto` and filters nothing. Same shape as `initialize`'s call to `discuss-init.sh`. The other two scripts are mode-independent and are called bare.)

The filter is mechanical and **never dispatches**: it renders `discuss:post`, and in `--auto` with `features.mempalace_capture_on_auto_discuss` ≠ `true` removes **only** the `ref.skill: "mempalace-capture"` entry (log `[auto] discuss:post: mempalace-capture filtrado (capture_on_auto_discuss=false)`). Outside `--auto` nothing is removed. It prints a one-line summary (hooks reduced to `id`/`kind`/`blocking`/`onError`/`ref`, with `check.query`/`check.predicate`/`fragment.inline` cut at 200 chars and `truncado: true` when cut) plus the three extra arrays; the whole envelope with the full classification is in the file named by `envelope` (`$T/hooks-envelope.json`).

**You dispatch** every remaining entry of `activeHooks` per @~/.claude/gad-core/references/loop-hook-dispatch.md — **all kinds**, not one shape: `contribution` (inject `fragment.inline` verbatim — when the entry carries `truncado: true`, Read the text from the `envelope` file, never from the summary), `ref.skill` (Skill tool, id `gad-<ref.skill>`), `ref.command` (`gad_run <command> --phase "${PHASE_NUMBER}" --raw`), `gate` (evaluate `check`, honor `blocking`/`onError`). Empty `activeHooks` → **zero dispatches**, continue to `finalize`.

- `nao_despachaveis` (non-empty) → for each entry, ring the bell `hook_nao_despachado: <ref.agent|gate name>` and record an incident. The host `gad-discuss` has no `Agent` tool by design (`agents/gad-discuss.md`), so `ref.agent` steps and `gate.check.agentVerdict` cannot run here. **Never skip in silence.** `agentVerdict` is always non-blocking (`capability-validator.cjs:2802-2806`), so this is an incident + continuation, never a stop.
- `rejeitados` (non-empty) → malformed manifest: surface each `motivo` as a loud warning (R-8: a denied dispatch is loud, never silent) and do not run that entry.
- **Exit 3** from the script = a *blocking* `gate` was rejected (its `query`/`predicate` is malformed): fail closed — stop the workflow, do not commit, ring the bell with the reasons.
</step>

<step name="finalize">
**Optional discussion log:** only when `LOG_ON=true` and not `--auto` — Read `workflows/discuss-phase/templates/discussion-log.md` and write `${phase_dir}/${padded_phase}-DISCUSSION-LOG.md` from the accumulated log (audit trail only; the rationale that matters is already in the CONTEXT as `evidence:`/`options:`/prose lines).

**One call does for-humans render, index, state, commit and cleanup — in that order:**

```bash
. .planning/.discuss-tmp/env.sh
bash "$NOSSO/discuss-finalize.sh"
```

It prints `{"commit", "hash", "skipped", "rejected_path", "reason", "files", "gad_tools", "cleaned", "msgs", "msgs_truncadas", "log"}` — `msgs` = last 60 log lines; `log` is `$T/finalize.log` on failure and `${phase_dir}/.discuss-finalize.log` after a successful cleanup.

- `commit: true` → confirm `Committed: docs(${padded_phase}): capture phase context + decisions index` (`hash` is the short hash).
- `skipped: true` (`commit_docs=false` or `.planning` ignored) → log `[commit] skipped by commit_docs policy` — **never improvise a raw `git commit`**.
- Neither (exit 2) → the commit failed, or the guard rejected the CONTEXT (`reason: guard`, `rejected_path` = the CONTEXT — the script runs `context-guard.sh` with `--spec`/`--reqs` before touching anything, so a CONTEXT edited after `write_context` never gets committed): `$T` and the checkpoint were **preserved** on purpose. Surface `reason` and `msgs`, do not clean up, do not claim success; fix through the writer and re-run `write_context`.

Cleanup (`$CKPT` + `$T`) happens **only after** success, so `env.sh` is gone from here on. The guard arguments survive in `${phase_dir}/.discuss-guard-args` (one line, `--spec "…" --reqs "…"`) — `reconcile_existing` uses it so the guard is never run bare. `auto_advance` must use the `gad_tools` path from this JSON (`node <gad_tools> query config-get …`) or `modes/chain.md`'s own preamble.
</step>

<step name="reconcile_existing">
Entered only from `check_existing` when a CONTEXT.md already exists. The file is **immutable except for additions** — the checkpoint that produced it is gone, D-NN ids are contracts that plans already cite, and there is no CONTEXT→JSON importer.

- Run `load_prior_context`'s todo match only (`gad_run query todo.match-phase "${PHASE_NUMBER}"`). New todos with `score >= TODO_THRESHOLD` (auto) or selected by the user → append bullets under `### Folded Todos` inside `<decisions>` (create the heading right before `</decisions>` if absent — three hashes; the parser only recognises `###` categories). Never renumber or rewrite existing D-NN; new decisions (interactive "Update it") continue the sequence and are added with `Edit`.
- After any edit: `xargs -a "${phase_dir}/.discuss-guard-args" bash "$NOSSO/context-guard.sh" "$CONTEXT_PATH" --root .` (the file was written by `finalize` and carries the `--spec`/`--reqs` that `write_context` used; `xargs` honours its quotes) and confirm with the parser that every previous D-NN is still present in the same category. If the file is missing (CONTEXT from before this fork), pass `--spec "$SPEC_PATH" --reqs "$REQ_IDS"` from `env.sh` by hand.
- Something changed → `finalize` (index + commit). Nothing changed → log `[auto] nothing to reconcile` and end with no commit.
</step>

<step name="confirm_creation">
Not `--auto`: present the summary —

```
Created: ${phase_dir}/${padded_phase}-CONTEXT.md — {N} decisions, {M} deferred ideas
Guard: {OK | N warnings}
Next: /clear then /gad-plan-phase ${PHASE} ${GAD_WS}
Also: --chain for auto plan+execute; /gad-plan-phase ${PHASE} --skip-research ${GAD_WS}; /gad-ui-phase ${PHASE} ${GAD_WS}; review/edit CONTEXT.md before continuing.
```

`--auto`: two lines only — the CONTEXT path and the decision count.
</step>

<step name="auto_advance">
Read `workflows/discuss-phase/modes/chain.md` and execute its `auto_advance` step **only if** `--chain` is in $ARGUMENTS, **or** `workflow.auto_advance` is true, **or** `workflow._auto_chain_active` is true (check with `gad_run query config-get <key> --raw`; `$T/env.sh` no longer exists — use the `gad_tools` path returned by `finalize`, or `chain.md`'s own preamble). **`--auto` alone does not chain** — log `[auto] auto_advance skipped — no --chain and auto_chain_active=false` and end. Otherwise end here — `confirm_creation` already ran; do not route back to it.
</step>
