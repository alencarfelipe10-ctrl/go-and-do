# Prohibition-Probe — operating digest

Working digest of `references/prohibition-probe.md`: every rule the schema/projection layer
does NOT enforce, without the didactics (rationale essay, N18 experiment notes, ADR history,
worked examples, verify-time prover internals). Read the full reference only to port the
probe elsewhere or audit the protocol itself. Axis here = the **must-NOT** axis (product,
values, safety, ethics) — the orthogonal data/behaviour-shape axis is
`references/edge-probe-digest.md`.

## There is NO engine — the prose IS the recall stage

Unlike the edge probe there is **no compiled `prohibition-probe.cjs`** and no `node`
invocation (ADR-550 D7b): the must-NOT axis is open, so no closed taxonomy a classifier
could apply exists. Only the schema/projection layer is code. The recall stage is an LLM
prose pass over the SAME requirement list the edge probe used — run it AFTER the edge probe.

**Input:** requirements as `{ id, text }`, `text` a testable statement. No shape override,
no classifier.

## Two-stage protocol — recall THEN precision

**Stage 1 — Recall (adversarial prose probe).** Ask each requirement the single question:

> *What could this feature silently become that the author would NOT want, but the spec does
> not forbid?*

Deliberately over-produce (~10 raw candidates per requirement, routine items included).
Recall first — narrowing here is the failure mode.

**Stage 2 — Precision (one-pass drop/keep filter).**

- **DROP routine engineering** — normal correctness/hygiene: "must not mutate its input",
  "must not throw on empty list", "must not leak a file handle". Owned by the edge probe or
  ordinary code review, not here.
- **KEEP values / safety / ethics** — anything that, if violated, makes the feature do
  something the author would object to on product, fairness, privacy, transparency or safety
  grounds: manipulative framing, protected-attribute proxies, raw PII in plaintext.
- **KEEP a prohibition that mirrors an Out-of-scope bullet** — the Out-of-scope section has no
  reader downstream; the prohibition is the only wiring that carries the boundary to the
  verifier (`test` when a mechanical check exists, `judgment` otherwise). A `judgment` item
  that only restates SPEC prose is a flag in the report, never work in `must_haves` (D6).

~10 raw collapses to ~2–3 genuine prohibitions. **Zero kept is a valid outcome** for a pure
utility with no intent surface — an empty list is the correct precision result, not a
failure. That discipline is what keeps a non-empty list meaningful.

## Canon-referral — refer, never mint (and never restate the canon)

A kept candidate that is **canon** security/compliance is already owned by a dedicated tool.
Do NOT mint a prohibition for it: emit a one-line breadcrumb and stop.

| candidate class | breadcrumb to |
|---|---|
| OWASP / prototype-pollution / path-traversal / injection | `/gad-secure-phase` + `eslint` (security plugins) |
| GDPR / data-retention / consent | `/gad-secure-phase` |
| generic fairness / bias canon | `/gad-secure-phase` |

Form: *"prototype-pollution is canon — covered by /gad-secure-phase + eslint; not minted
here."* One line, a pointer — never a copy of the canon rule's content into the SPEC.
Minting canon items duplicates other tooling and drowns the ~2–3 **bespoke** items that no
other tool would catch, which is the entire value of the probe.

## Resolution — two orthogonal axes

Lifecycle and verification are separate enums (ADR-550 D7; lifecycle identical to the edge
probe, verification tiers differ).

- **status** — `resolved | dismissed | unresolved`:
  - `resolved` — addressed; *how* is the verification tier.
  - `dismissed` — not a genuine prohibition here, with a **required non-empty reason**
    ("N/A — no user-facing surface, no values constraint applies"). The reason is the audit
    trail; silence is not a dismissal. **Never auto-dismiss** — a wrong dismissal is the
    exact silent failure this probe exists to kill.
  - `unresolved` — carried forward and flagged; an explicit assumption the planner must
    surface, never a silent drop.
- **verification** — `test | judgment`, only when `status` is `resolved`, `null` otherwise
  (this REPLACES the edge probe's `explicit | backstop`):
  - `test` — mechanically checkable (a negative test, a lint rule, an assertion that the
    audit log holds no raw SSN). Hard-gates at verify time: a wired check that is missing or
    not machine-proven fail-first flags `gaps_found`, never a silent pass.
  - `judgment` — real but not reducible to a mechanical test (framing is not manipulative).
    Routes to a never-silent soft gate (`unverified-prohibition — human review recommended`).

## Promotion — every kept prohibition becomes a negative AC

A `resolved` prohibition is written into the SPEC as a **negative acceptance criterion** (a
must-NOT line) and lands in the `## Prohibitions` section; `plan-phase` lifts it into
`must_haves.prohibitions` (NOT `truths`). `resolved`/`test` → a checkable negative the
verifier iterates over; `resolved`/`judgment` → recorded intent routed to judgment review;
`unresolved` → a flagged assumption. Portable equivalents: Gherkin → a negative `Then` /
tagged scenario; OpenAPI → a contract test asserting the forbidden behaviour never occurs;
docstring contract → a negative assertion in the contract test.

## Output schema

Per kept prohibition:

```
{ requirement_id, category, status, verification, resolution, reason, statement,
  check_kind?, check_target?, check_rule?, check_violation_fixture?, check_clean_fixture? }
```

`statement` is the must-NOT sentence; `category` is the values/safety/ethics class
(`values`, `fairness`, `privacy`, `transparency`, `safety`, …). The `check_*` descriptor is
optional, present only on a `resolved`/`test` item with a wired check, and is **five flat
scalars — never a nested `check: {}`** (the shared `parseMustHavesBlock` is a flat parser and
would mangle a nested object). A partial, unknown or absent descriptor falls through to the
producer's fail-closed path — never a silent green.

Plus the coverage rollup:

```
coverage: { applicable, resolved, unresolved, byVerification: { test, judgment } }
```

`applicable` = kept prohibitions; `resolved` = **closed** items (`resolved` + `dismissed`);
`unresolved` = the remainder; `byVerification` breaks the `resolved`-status items down by
tier. This JSON is the stable contract every port emits.
