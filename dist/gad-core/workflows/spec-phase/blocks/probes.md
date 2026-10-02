# spec-phase — Steps 5.5 and 5.6 (the two completeness probes)

Lazy block of `workflows/spec-phase.md` (S3). Read on arrival at Step 5.5, never before —
a run that stops at the ambiguity gate must not pay for this text. The main workflow
carries only the stub that points here.

**Preconditions carried with the text (they break the probe silently if lost):**
- The `gsd:reqs` draft MUST already be authored into `${phase_dir}/.spec-reqs.md` before the
  Step 5.5 bash block runs — it is the probe's single input, authored once.
- Step 6 (main workflow) transcribes that same block VERBATIM into SPEC.md and then deletes
  the draft. Do not delete it here.
- `gad_run` / `GAD_TOOLS` come from `.planning/.spec-tmp/env.sh` (Step 1 wrote it):
  `. .planning/.spec-tmp/env.sh` — never re-paste a resolution cascade.

## Step 5.5: Edge-Completeness Probe

Run AFTER the ambiguity gate passes (you probe edges of clear requirements, not vague
ones). Reference: **Read** `~/.claude/gad-core/references/edge-probe-digest.md` now (S2a — the
operating digest: the FLOOR-not-ceiling rule, the closed taxonomy of 8, the relevance filter
and reason-string dismissal, `unclassified`/zero-applicable, and the resolution states). The
full `references/edge-probe.md` is only needed to port the probe elsewhere or audit the
taxonomy itself — do not load it here.

**Runtime coverage compute — resolve and invoke edge-probe.cjs:**

```bash
# Resolve the compiled edge-probe.cjs against the GAD install dir via GAD_RUNTIME_DIR (#448)
# — NOT the consuming project's git root — falling back to git toplevel / $HOME/.claude.
# Mirrors the ui-safety-gate.cjs resolution idiom at autonomous.md:290 / plan-phase.md:631.
_GAD_RT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
EDGE_PROBE_JS=$(for _c in \
  "$_GAD_RT/gad-core/bin/lib/edge-probe.cjs" \
  "$_GAD_RT/bin/lib/edge-probe.cjs" \
  "$_GAD_RT/.claude/bin/lib/edge-probe.cjs" \
  "$HOME/.claude/gad-core/bin/lib/edge-probe.cjs" \
  "$HOME/.claude/bin/lib/edge-probe.cjs"; do
  [ -f "$_c" ] && { echo "$_c"; break; }
done)

# Graceful degradation — never silent skip (RR-04). Build ONLY when $_GAD_RT is a verified
# GAD source checkout (has tsconfig.build.json + src/edge-probe.cts), and pin npm to it with
# --prefix so we never trigger the CONSUMING project's own build:lib (its cwd package scripts:
# codegen/migrations/writes) during a spec workflow. Real installs ship the compiled .cjs via
# prepublishOnly, so this build path only matters in a GAD dev checkout (review High).
if [ -z "$EDGE_PROBE_JS" ]; then
  if [ -f "$_GAD_RT/tsconfig.build.json" ] && [ -f "$_GAD_RT/src/edge-probe.cts" ]; then
    npm --prefix "$_GAD_RT" run build:lib 2>/dev/null || true
    EDGE_PROBE_JS=$(for _c in \
      "$_GAD_RT/gad-core/bin/lib/edge-probe.cjs" \
      "$_GAD_RT/bin/lib/edge-probe.cjs" \
      "$_GAD_RT/.claude/bin/lib/edge-probe.cjs" \
      "$HOME/.claude/gad-core/bin/lib/edge-probe.cjs" \
      "$HOME/.claude/bin/lib/edge-probe.cjs"; do
      [ -f "$_c" ] && { echo "$_c"; break; }
    done)
  fi
  if [ -z "$EDGE_PROBE_JS" ]; then
    echo "ERROR: edge-probe.cjs not found — reinstall GAD or run \`npm run build:lib\` in your GAD checkout." >&2
    exit 1
  fi
fi

# The probe input is the SPEC's Machine-Readable Requirements block, authored ONCE and
# extracted here — never a re-typed heredoc. BEFORE this bash runs, write the draft block to
# ${phase_dir}/.spec-reqs.md (Step 6 transcribes the same block verbatim into SPEC.md):
#
#   <!-- gsd:reqs:begin -->
#   [ { "id": "R1", "text": "<the requirement, verbatim, in the project language>",
#       "text_en": "<faithful English translation>", "shapes": ["collection"], "trigger": "evidência" } ]
#   <!-- gsd:reqs:end -->
#
# "text" is the requirement's own words (the language of the SPEC). "text_en" is a faithful
# ENGLISH translation, engine input only, never user-facing: the classifier's cues are English
# word-boundary patterns, so original-language text classifies to zero shapes and lands in
# `unclassified` (#1110). The engine reads `text_en ?? text` (upstream #3717/#4156) and REJECTS
# an empty `text_en`. When `response_language` is set, populate `text_en` for EVERY requirement,
# not only the edge-looking ones: the `$APPLICABLE = 0` warning below fires only when ALL are
# unclassified, so a partly-translated block slips through with no signal. (#4656) The warning
# now ALSO fires on the all-unclassified case itself: `coverage.unclassified` counts the
# soft-signal rows, and the guard below fires when `$UNCLASSIFIED = $APPLICABLE` — the case
# where the classifier learned nothing about ANY requirement. When the project is
# English, omit `text_en`. "shapes" is ALWAYS authored by the model — the engine's regex cues
# are a conference log, not the classifier (#2773). One object per requirement.
# `id`s are never translated or renumbered — coverage rows join back on `id`. A requirement
# that still classifies to zero shapes after translation carries no cue in any language
# (ADR-857 §98 recall gap, not a translation failure): author its `shapes` explicitly.
# For a requirement that only describes a harness, a test or a reconciliation of existing
# assertions, author the smallest shape set that describes what it actually manipulates, or
# `shapes: []` — the engine accepts an empty array as a deliberate opt-out. A wide shape on a
# requirement with no real data lights categories that have no case behind them (D5).
REQS_SRC="${phase_dir}/.spec-reqs.md"
REQS_JSON=$(mktemp "${TMPDIR:-/tmp}/edge-probe-reqs-XXXXXX") && mv "$REQS_JSON" "${REQS_JSON}.json" && REQS_JSON="${REQS_JSON}.json" || exit 1
sed -n '/<!-- gsd:reqs:begin -->/,/<!-- gsd:reqs:end -->/p' "$REQS_SRC" | sed '1d;$d' > "$REQS_JSON"
# Guard — never invoke on an empty/invalid array or a leftover placeholder. Fail loud, not silent no-op.
if ! node -e 'const a=require(process.argv[1]);if(!Array.isArray(a)||a.length===0)process.exit(1);if(a.some(r=>typeof r.text!=="string"||!r.text.trim()||r.text.includes("<")))process.exit(1);if(a.some(r=>r.text_en!=null&&(typeof r.text_en!=="string"||!r.text_en.trim()||r.text_en.includes("<"))))process.exit(1);const ids=new Set();for(const r of a){if(typeof r.id!=="string"||!/^R[0-9]+$/.test(r.id)||ids.has(r.id))process.exit(1);ids.add(r.id);if(r.files!==undefined&&(!Array.isArray(r.files)||r.files.some(f=>typeof f!=="string"||!f||f.startsWith("/")||f.split("/").includes(".."))))process.exit(1)}' "$REQS_JSON" 2>/dev/null; then
  echo "ERROR: no valid Machine-Readable Requirements block found in $REQS_SRC — author the gsd:reqs block before Step 5.5 runs (ids must be unique R1, R2…; text_en, when present, a non-empty English string; files, when present, relative paths without ..)." >&2
  exit 1
fi
# Invoke the compiled engine and CAPTURE its report — it computes which categories apply per
# requirement. The report is RENDERED into context below (#3102); its resolved/dismissed/
# unresolved rows (resolved items carry verification: explicit|backstop) are the deterministic
# FLOOR the resolution loop consumes and unions with its own classification — the loop no longer
# re-derives the taxonomy from prose unaided. Floor, never ceiling: the classifier has a measured
# recall gap (ADR-857 §98 / ADR-550 D7b), so the model still ADDS any category the engine missed.
# The engine FAILS CLOSED (exit 2) on an invalid authored shape or bad input — so the capture
# MUST be exit-checked. A bare `COVERAGE=$(node …)` swallows that exit code, leaves $COVERAGE
# empty, and lets the workflow fall through to prose re-derivation: fail-OPEN at the boundary
# the engine validation exists to protect. Make the run fatal, then validate the captured
# report is well-formed JSON before the resolution loop consumes it.
if ! COVERAGE=$(node "$EDGE_PROBE_JS" "$REQS_JSON"); then
  rm -f "$REQS_JSON"
  echo "ERROR: edge-probe engine failed (invalid shapes or bad input) — fix the requirement(s) and re-run; never proceed with empty coverage." >&2
  exit 1
fi
rm -f "$REQS_JSON"
# Exit-0-but-garbage guard: the report must parse as JSON with the expected { items[], coverage{} } shape.
if ! printf '%s' "$COVERAGE" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let r;try{r=JSON.parse(s)}catch{process.exit(1)}if(!r||!Array.isArray(r.items)||typeof r.coverage!=="object"||r.coverage===null)process.exit(1)})'; then
  echo "ERROR: edge-probe produced an unparseable or malformed coverage report — refusing to proceed with the resolution loop." >&2
  exit 1
fi
# Render the validated report into the model's visible context (#3102). Until here $COVERAGE was
# captured, shape-checked, and reduced to coverage.applicable — the engine's per-requirement
# items[] never reached the model, so the resolution loop below re-derived edge categories from
# requirement PROSE (the data-flow twin of #2733's control-flow discard). These rows are the
# deterministic FLOOR the resolution loop consumes. Printed RAW (not a bespoke table) so this
# step holds NO knowledge of the item schema: an ADR-550 D7a-style re-cut of the item/coverage
# shape cannot silently desync a hand-rolled renderer here — the engine stays the single source.
echo "### Edge-probe coverage report (deterministic proposals — the FLOOR for the resolution loop below):"
printf '%s\n' "$COVERAGE"
echo "### (end edge-probe coverage report)"
# Zero-applicable guard: a report where the engine proposed NO applicable edge across ANY
# requirement is far more likely a shape-classification miss (or malformed requirements) than
# a genuinely edge-free spec — the same fail-open shape as an invalid shape yielding
# applicable:0. Surface it loudly; the author must explicitly confirm "no applicable edges"
# below rather than silently emitting a green empty ## Edge Coverage section.
APPLICABLE=$(printf '%s' "$COVERAGE" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let n=0;try{n=JSON.parse(s).coverage.applicable}catch{n=0}process.stdout.write(String(n))})')
UNCLASSIFIED=$(printf '%s' "$COVERAGE" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let n=0;try{n=JSON.parse(s).coverage.unclassified}catch{n=0}process.stdout.write(String(n))})')
# #4656: all-unclassified is the accidental-miss case the applicable:0 guard could never
# reach — #1110's soft-signal rows make applicable non-zero by construction there.
if [ "$APPLICABLE" = "0" ] || [ "$UNCLASSIFIED" = "$APPLICABLE" ]; then
  echo "WARNING: edge-probe proposed ZERO applicable edges across all requirements — likely a classification miss or malformed requirements, not a genuinely edge-free spec. Do NOT silently write an empty Edge Coverage section." >&2
fi
```

If the guard above fired (`$APPLICABLE` is `0`, or every requirement is unclassified — `$UNCLASSIFIED = $APPLICABLE`, #4656), do NOT proceed silently: ask the author to confirm via AskUserQuestion
("The edge probe found no applicable edges for any requirement — is this genuinely an
edge-free spec, or should we revisit the requirement wording / authored shapes?"). Only write
an empty `## Edge Coverage` section after explicit confirmation.

For each Requirement gathered so far:
1. Start from the edge-probe rows RENDERED above — the deterministic `items[]` are the FLOOR:
   every proposed `(requirement_id, category)` MUST be resolved below (Specify / Dismiss-with-
   reason / Backstop / Defer), none silently dropped. Then raise any applicable category the
   engine MISSED — the rows are a floor, never a ceiling: the classifier has a measured recall
   gap on terse prose (ADR-857 §98 / ADR-550 D7b), e.g. a CSV-export requirement whose
   `encoding` edge the shape cue under-fires. Union the engine's rows with your own
   classification (relevance filter — see the taxonomy in the reference); do not narrow to them.
   Reuse any edges the Round-4 Failure Analyst already surfaced as pre-resolved.
2. For each raised category, propose a CONCRETE candidate edge (not "consider
   boundaries" — e.g. "R2 merges intervals; what about `[[1,2],[2,3]]` that only touch?").
3. Resolve each with the user (AskUserQuestion; text mode → numbered list):
   - **Specify it** → write a new pass/fail line into Acceptance Criteria AND mark the
     edge `resolved` with `verification: explicit`.
   - **Dismiss (reason)** → mark `dismissed` with a required non-empty reason.
   - **Backstop with a test** → mark `resolved` with `verification: backstop`; note
     "held-out edge test" for plan-phase.
   - **Defer** → leave `unresolved`.
   - An `unclassified` row (probe `unclassified — review manually`) means the requirement's
     prose matched no shape cue (#1110) — treat it like any other candidate (**Specify**,
     **Dismiss (reason)**, or **Defer**). A manual-review nudge, not a hard block.

**Soft gate (after resolving):**
- All applicable edges resolved → proceed to Step 5.6.
- Any `unresolved` → AskUserQuestion:
  - header: "Edge Coverage"
  - question: "[N] edge(s) are unresolved: [list]. What do you want to do?"
  - options: "Resolve now" (loop back) / "Write SPEC.md anyway — flag unresolved" /
    "Keep probing"
  - On "anyway": write SPEC.md with those rows marked `⚠ Edge unresolved — planner must
    treat as assumption`.

**`--auto` mode:** resolve over the **same rendered floor** (#3102) — every engine-proposed row
from Step 5.5's report (step 1) plus any category the classifier missed, never a narrower set.
For each: auto-`resolved` (verification: explicit) where a defensible acceptance criterion can be
written; otherwise auto-`resolved` (verification: backstop) (never auto-dismiss — a wrong
dismissal is the exact silent failure being eliminated). One dismissal is allowed in `--auto`:
measured zero prevalence. Dismiss the cell only with the command and the number written into
the reason string — `dismissed — prevalence 0 in 10/10 cases (cmd: …)` — and only where a real
corpus exists to count (the data this phase processes, not the code). With no corpus there is
nothing to measure: resolve as backstop instead. The measurement is a snapshot; new data
carrying the case reopens the cell (D5). Log:
`[auto] edge coverage: E explicit, B backstop, D dismissed-by-prevalence, U unresolved`.

**`unclassified` exception (#1110):** `--auto` leaves an `unclassified` candidate
**`unresolved`** (the soft gate surfaces it as a flagged planner assumption) — it never
auto-resolves it with `verification: backstop`. A missing shape is not evidence an edge exists, so minting a held-out
edge obligation on a requirement that may be genuinely edge-free would be a false claim and
risks a vacuous edge test. Leaving it `unresolved` keeps the zero-cue requirement visible
(never a silent drop) without fabricating an edge — which is exactly #1110's purpose: surface
it for review, do not auto-handle it. Name each one as a question in the log and in the
Edge Coverage row, e.g. `[auto] unclassified — R3 ("merge intervals"): no shape cue
matched; is there an edge here?` — a named question travels into review briefings and
stays answerable; a bare count disappears.

Populate the `## Edge Coverage` section of SPEC.md from the resolved edges.

## Step 5.6: Prohibition-Completeness Probe (must-NOT)

Run AFTER Step 5.5 (you probe the must-NOT axis of clear requirements, over the same
requirement list). Reference: @~/.claude/gad-core/references/prohibition-probe-digest.md — the
portable two-stage protocol, the canon-referral rule, and the status×verification schema
live there (size-cap discipline; keep this step lean).
(The digest is the operating text: it keeps every rule the schema/projection layer does NOT
enforce — the prose IS the recall stage, ADR-550 D7b — and drops only the didactics. Read
`references/prohibition-probe.md` whole only to port the probe elsewhere or audit the
protocol itself.)

**D1 — no compiled engine (ADR-550 D7b).** Unlike Step 5.5, the prohibition probe has NO
compiled recall engine and runs NO `node` invocation here. The recall stage is an LLM prose
pass: the closed eight-category edge taxonomy a classifier can apply does not exist for the
open values/safety/ethics must-NOT axis. Do NOT copy the Step 5.5 engine-resolution block.
Only the schema/projection layer is real code; the recall is prose.

For each Requirement gathered so far, run the two-stage recall→precision pass:

1. **Stage 1 — Recall (adversarial prose probe).** Ask the single adversarial question of the
   requirement: *"What could this feature silently become that the author would NOT want, but
   the spec does not forbid?"* Over-produce (~10 raw must-NOT candidates) — recall first.
2. **Stage 2 — Precision (one-pass classifier).** Filter the raw list in a single pass:
   **DROP routine-engineering** items (normal correctness/hygiene — "must not mutate input",
   "must not throw on empty" — owned by the edge probe or code review); **KEEP
   values / safety / ethics** items (manipulative framing, protected-attribute proxies, raw
   PII in plaintext). This collapses ~10 → ~2–3 genuine prohibitions.
   **KEEP a prohibition that mirrors an Out-of-scope bullet.** The SPEC's Out-of-scope section
   has no reader downstream — planner, plan-checker, executor and verifier never read it — so
   the prohibition is the only wiring that carries the boundary to the verifier (D6). Resolve
   it `test` whenever a mechanical check exists (a diff, a grep, a lint rule); `judgment`
   otherwise.
3. **Canon-referral (ADR-550 D6, PROB-13).** A kept candidate that is canon security/compliance
   (OWASP / prototype-pollution / path-traversal / injection / GDPR / generic fairness) is
   NOT minted here — emit a one-line breadcrumb (*"prototype-pollution is canon — owned by
   /gad-secure-phase + eslint; not minted here"*) and DROP it. Minting canon items duplicates
   /gad-secure-phase and drowns the bespoke signal.
4. **Resolve each surfaced (non-canon) prohibition** (AskUserQuestion; text mode → numbered list):
   - **Keep it** → write a NEGATIVE acceptance criterion (a must-NOT line) into Acceptance
     Criteria AND mark the prohibition `resolved` with a verification tier: `test` (a
     mechanical negative test/lint/assertion exists) or `judgment` (real but not mechanically
     checkable — routes to judgment review). A `judgment` prohibition that only restates prose
     already written elsewhere in the SPEC is a flag, not a task: it goes into the report and
     never into `must_haves` as work — the verifier's judgment routing (ADR-550 D4) already
     handles it as a flagged item (D6).
     - **Capture the wired-check descriptor on `test`-tier (#1278, SOFT).** When a prohibition is
       resolved `verification: test`, ALSO capture the descriptor of the wired check so
       `verify-phase` can LOCATE it deterministically (no verifier invention at verify time).
       Capture the flat scalars — persisted into SPEC and projected onto the
       `must_haves.prohibitions` item by `projectProhibitions`:
       - `check_kind` — `node-test` | `lint-rule`.
       - `check_target` — the negative-test file path (for `node-test`), or the path to lint
         (for `lint-rule`).
       - `check_rule` — the eslint rule id (e.g. `local/no-source-grep`); `lint-rule` only.
       - `check_violation_fixture` (#1279) — path to a KNOWN-BAD subject the wired check is run
         against to **machine-prove fail-first**; rides BOTH kinds. Capture it to let the item green
         end-to-end with zero hand-authoring at verify time; for `node-test` the negative test should
         read its subject from the `GAD_PROHIB_SUBJECT` env var so the prover can inject this fixture.
       - `check_clean_fixture` (#1346; **REQUIRED for `node-test` as of #1906**) — path to a
         KNOWN-CLEAN control subject. The `node-test` prover runs the check against it and requires
         GREEN — proving the violation's RED is caused by the subject's *content*, not by
         `GAD_PROHIB_SUBJECT` merely being set. For a `node-test` this is **mandatory**: omit it and
         the check is un-provable (fail-closed), never proven on the violation alone — so a deceptive
         content-independent test cannot pass. (`lint-rule` needs no clean fixture: its subject IS the
         linted file, no `GAD_PROHIB_SUBJECT` indirection.)
       This is a **SOFT capture (CHK-04): a `test`-tier prohibition WITHOUT a descriptor is still
       allowed** — if the author cannot yet name the wired check, leave the descriptor empty and
       proceed. It is NOT a hard authoring block; the item simply stays fail-closed/flagged
       downstream (an absent/partial descriptor — or one with no `check_violation_fixture` —
       → `descriptorFromProjection` null/under-specified/fixture-less → producer fail-closed
       locate-or-unprovable, never green). Do NOT capture `failFirst` here — it is a
       verify-time caller attestation, not a spec-authored field (#1279).
   - **Dismiss (reason)** → mark `dismissed` with a REQUIRED non-empty reason (PROB-05). The
     reason string is the audit trail; silence is not a valid dismissal.
   - **Defer** → leave `unresolved`.

**Soft gate (after resolving) — PROB-06:**
- All applicable prohibitions resolved → proceed to Step 6.
- Any `unresolved` → AskUserQuestion:
  - header: "Prohibitions"
  - question: "[N] prohibition(s) are unresolved: [list]. What do you want to do?"
  - options: "Resolve now" (loop back) / "Write SPEC.md anyway — flag unresolved" /
    "Keep probing"
  - On "anyway": write SPEC.md with those rows marked `⚠ Prohibition unresolved — planner
    must treat as assumption`. This is a soft gate (write-anyway-with-flags), never a silent
    skip — the soft gate IS the control.

**`--auto` mode:** auto-`resolved` where a defensible negative acceptance criterion can be
written (test or judgment tier); otherwise leave `unresolved`. **`--auto` NEVER auto-dismisses
a prohibition** — a wrong dismissal is the exact silent failure this probe eliminates (PROB-06,
the load-bearing safety property). On a `test`-tier auto-resolution, capture the `check_kind` /
`check_target` / `check_rule` / `check_violation_fixture` / `check_clean_fixture` descriptor **only when a wired check is unambiguous**; otherwise
leave it empty — `--auto` NEVER fabricates a check path or fixture (a wrong locate is re-validated and
fails closed at the producer, but a fabricated path is still noise to avoid). Log:
`[auto] prohibitions: R resolved, U unresolved`.

**Text mode (PROB-09):** per Step 5's text-mode rule, replace the AskUserQuestion menus above
with plain-text numbered lists — there is NO hard AskUserQuestion dependency, so the probe
runs identically for non-Claude / text-mode hosts.

Populate the `## Prohibitions` section of SPEC.md from the resolved prohibitions (each
`resolved`/`test` row is a checkable negative acceptance criterion; `resolved`/`judgment`
rows route to judgment review; `⚠ UNRESOLVED` rows are flagged as assumptions). A
`resolved`/`test` row ALSO carries its captured `check_kind` / `check_target` / `check_rule` /
`check_violation_fixture` / `check_clean_fixture` descriptor when present (so the projection feeds `verify-phase`'s deterministic locate + machine-proof + causation control, #1278 + #1279 + #1346);
a `test` row with no captured descriptor is still valid — it stays fail-closed/flagged
downstream rather than blocking authoring.

