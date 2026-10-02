<purpose>
Clarify WHAT a phase delivers through a Socratic interview loop with quantitative ambiguity scoring.
Produces a SPEC.md with falsifiable requirements that discuss-phase treats as locked decisions.

This workflow handles "what" and "why" — discuss-phase handles "how".
</purpose>

<ambiguity_model>
Score each dimension 0.0 (completely unclear) to 1.0 (crystal clear):

| Dimension         | Weight | Minimum | What it measures                                  |
|-------------------|--------|---------|---------------------------------------------------|
| Goal Clarity      | 35%    | 0.75    | Is the outcome specific and measurable?           |
| Boundary Clarity  | 25%    | 0.70    | What's in scope vs out of scope?                  |
| Constraint Clarity| 20%    | 0.65    | Performance, compatibility, data requirements?    |
| Acceptance Criteria| 20%   | 0.70    | How do we know it's done?                         |

**Ambiguity score** = 1.0 − (0.35×goal + 0.25×boundary + 0.20×constraint + 0.20×acceptance)

**Gate:** ambiguity ≤ 0.20 AND all dimensions ≥ their minimums → ready to write SPEC.md.

A score of 0.20 means 80% weighted clarity — enough precision that the planner won't silently make wrong assumptions.
</ambiguity_model>

<interview_perspectives>
Rotate through these perspectives — each naturally surfaces different blindspots:

**Researcher (rounds 1–2):** Ground the discussion in current reality.
- "What exists in the codebase today related to this phase?"
- "What's the delta between today and the target state?"
- "What triggers this work — what's broken or missing?"

**Simplifier (round 2):** Surface minimum viable scope.
- "What's the simplest version that solves the core problem?"
- "If you had to cut 50%, what's the irreducible core?"
- "What would make this phase a success even without the nice-to-haves?"

**Boundary Keeper (round 3):** Lock the perimeter.
- "What explicitly will NOT be done in this phase?"
- "What adjacent problems is it tempting to solve but shouldn't?"
- "What does 'done' look like — what's the final deliverable?"

**Failure Analyst (round 4):** Find the edge cases that invalidate requirements.
- "What's the worst thing that could go wrong if we get the requirements wrong?"
- "What does a broken version of this look like?"
- "What would cause a verifier to reject the output?"

**Seed Closer (rounds 5–6):** Lock remaining undecided territory.
- "We have [dimension] at [score] — what would make it completely clear?"
- "The remaining ambiguity is in [area] — can we make a decision now?"
- "Is there anything you'd regret not specifying before planning starts?"
</interview_perspectives>

<process>

## Step 1: Initialize

**One call, not twelve** (S1). `spec-init.sh` resolves `gad-tools` (short cascade — no
20-runtime preamble), calls `init phase-op` ONCE, reuses the paths it returns, writes the
whole package to `.planning/.spec-tmp/` and prints an **index** of it — never more than
20 KB, because above ~50 KB the harness persists the output to a file and reading it back
costs turns (P10).

```bash
bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/nosso/spec-init.sh" "${PHASE}"
# optional: --pre-spec <file>   (a /go-and-do PRE-SPEC handed to this phase; it is an INPUT,
# never the SPEC — the script filters `AI-SPEC|PRE-SPEC` out of the SPEC lookup)
```

The result is labelled sections, each opening with `=== <NAME> ===` at column 0:

| section | what it carries |
|---------|-----------------|
| `INIT` | raw JSON of `init phase-op` — `phase_found`, `phase_dir`, `phase_number`, `phase_name`, `phase_slug`, `padded_phase`, `state_path`, `requirements_path`, `roadmap_path`, `response_language`, `commit_docs` |
| `PHASE_ENTRY` | the ROADMAP phase entry: Goal + success criteria (`SC1:`…) |
| `ROADMAP_SECTION` | index: size + path of `section.md` + the entry's first 15 lines (the file holds the entry whole, never the whole roadmap) |
| `REQUIREMENTS_SLICE` | index: the REQ-IDs and block titles of the slice (phase ids + the adjacent ones they cite) + path of `reqs-slice.md` |
| `STATE_HEADINGS` | `grep '^##'` of STATE.md — the map, not the file |
| `STATE_SECTIONS` | decisions as a one-line-per-decision index (`- dNN — plan · title`; the oldest labels collapse to one line each when the budget is short), then blockers/concerns and deferred whole, then the path of `state-sections.md` |
| `SPEC_ANTERIOR_HEADINGS` | HEADINGS ONLY of the previous phase's SPEC — the shape to follow, never its content |
| `SPEC_ATUAL` | this phase's own SPEC, if one already exists (the Update path below) |
| `PRE_SPEC` | path + whether the `gad:decisoes` block is present |
| `R6` | JSON: `goal_roadmap`, `req_ids`, `req_ids_ausentes`, `issues[{tipo}]` — informational here; the gate lives in the /go-and-do `confere-etapa.sh` |

A section that ends in `[truncado: N B; veja o arquivo …]` hit the 20 KB ceiling: the file
has the rest.

It also writes `.planning/.spec-tmp/env.sh` with `GAD_TOOLS`, the `gad_run` function,
every scalar above and the package paths `SECTION_MD`, `REQS_SLICE_MD`, `STATE_SECTIONS_MD`.
**Later bash blocks in this session (Steps 5.5, 6.5, 7) source it** — never re-resolve,
never re-paste a cascade:

```bash
. .planning/.spec-tmp/env.sh
```

**If `response_language` is set:** All user-facing text in this workflow — narration between tool calls, status updates, progress notes, findings, questions, and report prose — MUST be in `{response_language}`. Technical terms, code, and file paths stay in English.

**If `phase_found` is false:**
```
Phase [X] not found in roadmap.
Use /gad-progress to see available phases.
```
Exit.

**If `SPEC_ATUAL` says a SPEC already exists:**

**If `--auto`:** Auto-select "Skip" — leave the existing SPEC.md unchanged and exit with the same
message the interactive "Skip" prints. Log: `[auto] SPEC.md exists — reusing as-is.` An unattended
run reuses an existing artifact rather than regenerating it (#4776): "Update it" re-scores and
rewrites the spec, discarding answers a person already recorded in it, and nobody is present to
notice.

**Otherwise:** Use AskUserQuestion:
- header: "Spec"
- question: "Phase [X] already has a SPEC.md. What do you want to do?"
- options:
  - "Update it" — Revise and re-score
  - "View it" — Show current spec
  - "Skip" — Exit (use existing spec as-is)

If "View": Display SPEC.md, then offer Update/Skip.
If "Skip": Exit with message: "Existing SPEC.md unchanged. Run /gad-discuss-phase [X] to continue."
If "Update": Load existing SPEC.md, continue to Step 3.

## Step 2: Scout Codebase

**The index is in context; the bodies are on disk** (S1, P10). Step 1's single call
delivered the ROADMAP phase entry (`PHASE_ENTRY` + the head of `ROADMAP_SECTION`), the ids
of the REQUIREMENTS slice (`REQUIREMENTS_SLICE`), and the STATE.md map with the decisions
index, blockers/concerns and deferred (`STATE_HEADINGS` + `STATE_SECTIONS`). When you need a
body, open **only that section** of the package file, by the paths `env.sh` exports:

```bash
. .planning/.spec-tmp/env.sh
sed -n '16,$p' "$SECTION_MD"                       # rest of the ROADMAP entry
grep -n -A20 'CANC-v3x-03' "$REQS_SLICE_MD"        # one requirement block
awk -v RS='\\\\n- |\n- ' '/trecho do título/' "$STATE_SECTIONS_MD"   # one decision (its bullet), by its index title
```

The decisions body may be one JSON line (`state get` form), so the bullet split above is
the unit there, never `grep -n` — that would return the whole 48 KB line.

Never read a package file whole, and never ROADMAP.md / REQUIREMENTS.md / STATE.md
themselves: the package already holds the phase's cut. Re-open a source file only when a
section came back empty or a `[fallback]`/`[warn]` line named it; that is degradation,
never a block. The previous phase's SPEC headings (`SPEC_ANTERIOR_HEADINGS`) are the shape
to follow — read that SPEC's body only if you genuinely need a precedent, never by default.

**Prior-phase artifacts — bounded window** (source `.planning/.spec-tmp/env.sh` first if you
need `gad_run` here):
- LEARNINGS.md of the last 2 completed phases, plus any phase the current one lists as a dependency in ROADMAP.md.
- SUMMARY.md of those same phases via `gad_run summary-extract <path>` (structured extract, not the whole file).
- VERIFICATION.md only if the previous phase had a failed or assumed item.

**Explore the codebase** with one call — `bin/nosso/scout.sh` applies the three-layer funnel
(codebase docs → structural graph, refreshed if stale → grep fallback) and writes a resume
≤ 8 KB; the funnel is documented in `references/scout-codebase.md`, which you do not read:

```bash
. .planning/.spec-tmp/env.sh
bash "$NOSSO/scout.sh" "$PHASE" ${SPEC_PATH:+--spec "$SPEC_PATH"} --out "$T/scout.md"
```

Read `$T/scout.md` (origin line, relevant files with symbols and neighbours, existing tests,
`## reusable` / `## patterns` / `## integration`); Grep/Read only what a requirement will
actually cite. The paths each requirement will touch become the `files` field of the
Machine-Readable block (Step 6) so discuss-phase reads exactly those instead of scouting again.

**Synthesize current state** — the grounded baseline for the interview:
- What exists today related to this phase
- The gap between current state and the phase goal
- The primary deliverable: what file/behavior/capability does NOT exist yet?

Keep this synthesis internal at this point — use it to ask precise, grounded questions.

## Step 3: First Ambiguity Assessment

Before questioning begins, score the phase's current ambiguity based only on what ROADMAP.md and REQUIREMENTS.md say:

```
Goal Clarity:       [score 0.0–1.0]
Boundary Clarity:   [score 0.0–1.0]
Constraint Clarity: [score 0.0–1.0]
Acceptance Criteria:[score 0.0–1.0]

Ambiguity: [score] ([calculate])
```

**If `--auto` and initial ambiguity already ≤ 0.20 with all minimums met:** Skip interview — derive SPEC.md directly from roadmap + requirements. Log: `[auto] Phase requirements are already sufficiently clear — generating SPEC.md from existing context.` Jump to Step 5.5.

**Otherwise:** Continue to Step 4.

## Step 4: Socratic Interview Loop

**Max 6 rounds.** Each round: 2–3 questions max. End round after user responds.

**Round selection by perspective:**
- Round 1: Researcher
- Round 2: Researcher + Simplifier
- Round 3: Boundary Keeper
- Round 4: Failure Analyst
- Rounds 5–6: Seed Closer (focus on lowest-scoring dimensions)

**After each round:**
1. Update all 4 dimension scores from the user's answers
2. Calculate new ambiguity score
3. Display the updated scoring:

```
After round [N]:
  Goal Clarity:       [score] (min 0.75) [✓ or ↑ needed]
  Boundary Clarity:   [score] (min 0.70) [✓ or ↑ needed]
  Constraint Clarity: [score] (min 0.65) [✓ or ↑ needed]
  Acceptance Criteria:[score] (min 0.70) [✓ or ↑ needed]
  Ambiguity: [score] (gate: ≤ 0.20)
```

**Gate check after each round:**

If gate passes (ambiguity ≤ 0.20 AND all minimums met):

**If `--auto`:** Jump to Step 5.5.

**Otherwise:** AskUserQuestion:
- header: "Spec Gate Passed"
- question: "Ambiguity is [score] — requirements are clear enough to write SPEC.md. Proceed?"
- options:
  - "Yes — write SPEC.md" → Jump to Step 5.5
  - "One more round" → Continue interview
  - "Done talking — write it" → Jump to Step 5.5

**If max rounds reached (6) and gate not passed:**

**If `--auto`:** Write SPEC.md anyway — flag unresolved dimensions. Log: `[auto] Max rounds reached. Writing SPEC.md with [N] dimensions below minimum. Planner will need to treat these as assumptions.`

**Otherwise:** AskUserQuestion:
- header: "Max Rounds"
- question: "After 6 rounds, ambiguity is [score]. [List dimensions still below minimum.] What would you like to do?"
- options:
  - "Write SPEC.md anyway — flag gaps" → Write SPEC.md, mark unresolved dimensions in Ambiguity Report
  - "Keep talking" → Continue (no round limit from here)
  - "Abandon" → Exit without writing

**If `--auto` mode throughout:** Replace all AskUserQuestion calls above with Claude's recommended choice. Log decisions inline. Apply the same logic as `--auto` in discuss-phase.

One decision stays above `--auto`'s authority: refuting or replacing a requirement's source — concluding that the ROADMAP/REQUIREMENTS entry is wrong about WHAT to build, or swapping the document/dataset a requirement derives from. That is the owner's call: surface it as a question (hosted runs relay it through their decision contract) instead of auto-deciding. Auto mode picks among implementations; it does not overrule the requirement's origin.

**Text mode (`workflow.text_mode: true` or `--text` flag):** Use plain-text numbered lists instead of AskUserQuestion TUI menus.

## Steps 5.5 and 5.6: the completeness probes (lazy block)

Run AFTER the ambiguity gate passes — you probe the edges and the must-NOTs of CLEAR
requirements, not vague ones.

**Both steps live in a separate block so this file does not carry ~19 KB every run** (S3).
Before authoring the `gsd:reqs` draft, **Read**
`~/.claude/gad-core/workflows/spec-phase/blocks/probes.md` and follow it end to end:

- **Step 5.5 — Edge-Completeness Probe:** author `${phase_dir}/.spec-reqs.md`, invoke the
  compiled `edge-probe.cjs`, and resolve every proposed `(requirement, category)` plus the
  ones the classifier missed. Populates `## Edge Coverage`.
- **Step 5.6 — Prohibition-Completeness Probe (must-NOT):** the two-stage protocol over the
  same requirement list. Populates `## Prohibitions`.

The block carries its own references and its own `--auto` rules. Return here for Step 6.

**Obedience is observability, not prevention** (risk R-2): if the block was not read, the
SPEC arrives with an empty or hand-waved `## Edge Coverage` / `## Prohibitions` — that is
what the audit measures.

## Step 6: Generate SPEC.md

Use the SPEC.md template from @~/.claude/gad-core/templates/spec.md.

- Transcribe the **Machine-Readable Requirements** block from `{phase_dir}/.spec-reqs.md` VERBATIM into the SPEC's `## Machine-Readable Requirements` section (same `<!-- gsd:reqs:begin/end -->` markers — it is the single authored copy the probe already consumed), then delete the draft file. If the engine's cue-based classification in the rendered `items[]` diverged from an authored shape, note the divergence as a one-line warning next to the block — a conference log, never a block.
- Populate the **Edge Coverage** section from Step 5.5 (resolved/dismissed/unresolved rows; resolved items carry `verification: explicit|backstop`).
- Populate the **Prohibitions** section from Step 5.6 (resolved/dismissed/unresolved rows with the test|judgment tier).
- Populate the **Regression Surface** section: for each constant, count, target value, or
  invariant a requirement changes, `git grep` the symbol across code AND tests, and list
  every existing assertion, contract, or golden the change falsifies (file:line · verdict:
  invert / re-anchor / remove · which plan reconciles it). If the sweep finds none, the
  section says so explicitly. New requirements get all the attention; the recurring blind
  spot is what already exists and stops being true.

**Requirements for every requirement entry:**
- One specific, testable statement
- Current state (what exists now)
- Target state (what it should become)
- Acceptance criterion (how to verify it was met)
- Trigger (WHY this requirement exists): `- Trigger: <type> — <one sentence>` where type is one of `evidência | fala-do-dono | pedido-do-dono | upstream | higiene | não-regressão`. `Trigger: ver NN-PRE-SPEC.md` is allowed when the pre-spec holds the rationale. The `Current:` line does NOT count as a trigger — restating what exists is not a reason to change it.

**Trigger coverage (warning, not a gate):** after writing all requirements, count them. If any lack a trigger, print `Trigger coverage: N/M — sem trigger: [R…]` and record the same line in the SPEC next to the Ambiguity Report. Never block on it.

**`--auto` and triggers:** fill each trigger from the Background/roadmap evidence; when no source exists, write `pedido-do-dono` explicitly — never fabricate evidence.

**Vague requirements are rejected:**
- ✗ "The system should be fast"
- ✗ "Improve user experience"
- ✓ "API endpoint responds in < 200ms at p95 under 100 concurrent requests"
- ✓ "CLI command exits with code 1 and prints to stderr on invalid input"

**Count requirements.** The display in discuss-phase reads: "Found SPEC.md — {N} requirements locked."

**Boundaries must be explicit lists:**
- "In scope" — what this phase produces
- "Out of scope" — what it explicitly does NOT do (with brief reasoning)
- **And a machine-readable copy** right after the `gsd:reqs` block, in its own markers (never inside the requirements array — the edge probe validates every array item):
  ```
  <!-- gsd:scope:begin -->
  {"in": ["<each In-scope bullet, verbatim>"], "out": ["<each Out-of-scope bullet, verbatim>"]}
  <!-- gsd:scope:end -->
  ```
  discuss-phase renders `<spec_lock>` from it; when absent it falls back to a regex over the prose.
- **`files` per requirement** (optional, in the `gsd:reqs` objects): the relative paths the Step 2 scout found for that requirement — `"files": ["src/x.py", "docs/adr-1.md"]`. discuss-phase reads exactly those instead of re-scouting.

**Acceptance criteria must be pass/fail checkboxes** — no "should feel good" or "looks reasonable."

Apply a falsifiability lens to each criterion: state what a FAIL looks like. A criterion
that cannot fail is not a criterion. Escape-hatch disjunctions ("totals match, **or** a
warning is shown") are vacuously satisfiable — split them: the primary condition is the
criterion; the fallback behavior, if legitimate, becomes its own criterion with its own
pass/fail line.

**Classe (D9).** Para cada critério, pergunte: se este critério falhar, o Goal ainda está atingido?
Não → `[exigido: <motivo>]`, com a régua nomeada. Sim → `[desejável]`, ou o critério cai. O Goal
aqui é o parágrafo medido que você reescreveu acima, não o título da fase. Critério nascido da
grade de bordas responde à mesma pergunta: borda no caminho do objetivo é exigido; fora dele é
desejável, e continua verificável e continua na suíte.

**Régua (D2).** Um exigido só se sustenta em régua de resultado: item do Anexo A da pré-spec
(`AA-n`), decisão `PS-nn` — inclusive a fala do cliente, que entra pelo `PS-nn` ou `AA-n` que a
registra —, trava de não-regressão ou o Goal. Divergir do item do Anexo A que você cita é permitido
e escrito: `[diverge: AA-n — <porquê>]`. Contradizê-lo em silêncio não é.

**Unicidade (D10).** Para cada critério, pergunte: qual verificação derruba só este critério? Se a
resposta nomeia a fixture, o grep ou o diff de outro critério, os dois são o mesmo critério —
funda. Critério que prescreve mecanismo vira nota do critério de comportamento; o mecanismo é
assunto do planejamento. Não há cota: fundir é sobre distinguir, não sobre encurtar.

**Fecho (D9).** Com todos os exigidos verdes, cada efeito medido do Goal está coberto? Escreva a
resposta em `## Cobertura do Goal`, um efeito por linha, e repita o veredito na linha
`**Goal coberto:**` da `## Consistência interna`. Preencha `## Critérios exigidos` e o bloco
`gsd:acs` a partir das respostas acima — o molde diz a forma; a prosa e o bloco dizem o mesmo.

Each criterion cites its origin in brackets at the end — `[origem: PS-01, R2]` (pre-spec item,
`AA-n` annex item, `Goal`, requirement or REQUIREMENTS id, or `AC-nn` of this SPEC). An AC without
an origin is an AC nobody asked for: the pre-spec gate rejects it. Keep the
`<!-- spec-origem: v1 -->` and `<!-- spec-classe: v1 -->` markers from the template.

**If any dimensions are below minimum**, mark them in the Ambiguity Report with: `⚠ Below minimum — planner must treat as assumption`.

Write to: `{phase_dir}/{padded_phase}-SPEC.md`

**Origin cancellation gate (S-3, fork gen5-patches, tarefa 48/e, 23/09/2026).** Line 343–346
above only tells the model to cite `[origem: …]` and keep `<!-- spec-origem: v1 -->` — nothing
mechanical confirmed it before now. `confere-pre-spec.sh` (the /go-and-do skill's own gate for
this exact contract: `AC-SEM-ORIGEM`, `AC-ORIGEM-INEXISTENTE`, `AC-POR-PONTEIRO`) is the cancela;
run it here, BEFORE the for-humans companion and the commit, so an AC nobody asked for never
reaches either. It degrades to a no-op when the /go-and-do skill isn't installed (standalone GAD),
same pattern as `roda-suite.sh`'s `gad_registra_suite`:

```bash
. .planning/.spec-tmp/env.sh   # GAD_TOOLS + gad_run + scalars, from Step 1 (S1); also PRE_SPEC/PRE_SPEC_BLOCO
CANCELA="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/go-and-do/scripts/confere-pre-spec.sh"
if [ ! -r "$CANCELA" ]; then
  echo "ℹ origin cancellation skipped — go-and-do skill not installed (standalone GAD run)"
else
  REQS_FLAG=""; [ -n "${requirements_path:-}" ] && REQS_FLAG="--reqs ${requirements_path}"
  if [ "${PRE_SPEC_BLOCO:-nao_aplicavel}" = "presente" ]; then
    bash "$CANCELA" --exige-origem $REQS_FLAG "$SPEC_PATH" "$PRE_SPEC"
  else
    bash "$CANCELA" --sem-pre-spec --exige-origem $REQS_FLAG "$SPEC_PATH"
  fi
fi
```

**Exit 0** (or skipped, above): continue to Step 6.5. **Non-zero** (1 = `CODIGO arquivo:linha`
findings printed to stdout, an AC without a valid origin; 2 = the pre-spec decision block itself
is malformed): fix the flagged criteria in the SPEC — add or correct their `[origem: …]` tag —
and re-run this same block. The script is safe to run twice; that is the pass cap (same rule as
`discuss-render-guard.sh`). If it fails again on the second attempt: **do not** proceed to Step
6.5 or the Step 7 commit — surface the remaining findings to the user and stop the workflow.

## Step 6.5: For-Humans Companion

Write `{phase_dir}/for-humans/{padded_phase}-SPEC-FH.md` following
@~/.claude/gad-core/references/for-humans.md (skeleton, translation rules, ~40 lines,
owner's language), then render the `.html` with the converter command from that reference —
source `.planning/.spec-tmp/env.sh` first (`GAD_TOOLS`, `padded_phase`, `phase_dir` come
from Step 1; the converter resolves `fh-render.py` off `GAD_TOOLS`).
You just wrote the SPEC — this is a translation pass, not new analysis.

## Step 7: Commit

```bash
. .planning/.spec-tmp/env.sh   # GAD_TOOLS + gad_run + scalars, from Step 1 (S1)
gad_run query commit "spec(phase-${phase_number}): add SPEC.md for ${phase_name} — ${requirement_count} requirements (#2213)" --files "${phase_dir}/${padded_phase}-SPEC.md" "${phase_dir}/for-humans/${padded_phase}-SPEC-FH.md" "${phase_dir}/for-humans/${padded_phase}-SPEC-FH.html"
```

If `commit_docs` is false the CLI returns `skipped`; SPEC.md is written, not committed.

## Step 8: Wrap Up

Display:

```
SPEC.md written — {N} requirements locked.

  Phase {X}: {name}
  Ambiguity: {final_score} (gate: ≤ 0.20)

Next: /gad-discuss-phase {X}
  discuss-phase will detect SPEC.md and focus on implementation decisions only.
```

</process>

<critical_rules>
- spec-phase owns "what/why"; "how" is discuss-phase territory — ask about outcomes, not implementation
- Scout the codebase before the first question; ask 2–3 grounded questions per round
- If the user selects "Abandon", exit without writing SPEC.md
</critical_rules>

<success_criteria>
- Codebase scouted and current state understood before questioning
- All 4 dimensions scored after every round
- Gate passed OR user explicitly chose to write despite gaps
- SPEC.md contains only falsifiable requirements
- Boundaries are explicit (in scope / out of scope with reasoning)
- Acceptance criteria are pass/fail checkboxes
- SPEC.md committed atomically (when commit_docs is true)
- User directed to /gad-discuss-phase as next step
- Edge-completeness probe run; Edge Coverage section populated; unresolved edges flagged as assumptions
- Prohibition-completeness probe run; Prohibitions section populated; unresolved prohibitions flagged as assumptions
- Every requirement carries a Trigger line; missing triggers surfaced as `Trigger coverage: N/M` warning (never a gate)
- Machine-Readable Requirements block present in SPEC.md (English text, authored shapes) — the same block the edge probe consumed
- For-humans companion written and rendered (`for-humans/{padded_phase}-SPEC-FH.md` + `.html`), committed with the SPEC
</success_criteria>
