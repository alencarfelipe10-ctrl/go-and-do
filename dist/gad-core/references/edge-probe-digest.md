# Edge-Probe — operating digest

Working digest of `references/edge-probe.md`: every rule the compiled engine does NOT
enforce, without the didactics (rationale, literature, worked examples, host mapping). Read
the full reference only to port the probe elsewhere or audit the taxonomy itself. Axis here
= data/behaviour shape; the technology axis is `references/domain-probes.md`.

## The engine is a FLOOR, never a ceiling

`edge-probe.cjs` classifies each requirement's shape from prose cues and raises the
categories that apply. Its `items[]` are the **deterministic floor**: every proposed
`(requirement_id, category)` MUST be resolved — Specify / Dismiss-with-reason / Backstop /
Defer — none silently dropped.

**And you must ADD what the classifier missed.** It has a measured recall gap on terse
prose (ADR-857 §98 / ADR-550 D7b) — e.g. a CSV-export requirement whose `encoding` edge
under-fires. Walk the taxonomy yourself, apply the relevance filter, and **union** your
categories with the engine's rows. Never narrow to them.

Input rule: `text` is always a faithful English translation (non-English input lands every
requirement in `unclassified`, #1110); authored `shapes` override the cue heuristic.

## Taxonomy — closed, eight categories

Eight the author must explicitly clear beats thirty nobody finishes. Shapes:
`numeric-range`, `collection`, `text`, `stateful`, `io`. Growth via optional domain packs,
never by bloating this core. The QA names (Boundary Value Analysis, Equivalence
Partitioning, Category-Partition, Metamorphic Relations; backstop = property-based testing)
are adopted verbatim — the differentiated move is placement at the spec layer, not technique.

| id | name (QA term) | applies to shapes | probe question |
|----|----------------|-------------------|----------------|
| boundary | Boundary values | numeric-range | What happens exactly at each min/max/threshold — and one step either side? |
| adjacency | Adjacency / touching | collection | When two things are exactly equal or just touch, do they merge, collide, or separate? |
| empty | Empty / degenerate | collection, text | What is the result for empty, single-element, or null input? |
| encoding | Encoding / representation | text | Whose definition of length/equality applies — bytes, code points, grapheme clusters, or normalized form? |
| ordering | Ordering / stability | collection | When elements compare equal, is output order specified and stable? |
| precision | Precision / overflow | numeric-range | Where can precision loss, overflow, or rounding/tie-breaking occur — and what is the exact contract (half-up vs half-to-even, ceil/floor/truncate)? |
| idempotency | Idempotency / repetition | stateful | What happens if this runs twice on the same input? |
| concurrency | Concurrency / effect ordering | stateful, io | If interrupted or run in parallel, what is guaranteed? |

## Relevance filter + dismissal — the two honesty rules

1. **Relevance filter first.** Classify the requirement's shapes, then raise only the
   categories whose `applies to shapes` intersect them — a pure-text requirement is never
   asked about overflow. This is what makes an unresolved edge *mean* something: it applies
   and was not addressed.
2. **Dismissal requires a reason string.** `"N/A — input is a bounded enum, no boundary
   exists"` is valid; silence is not — the reason is the audit trail. Never auto-dismiss: a
   wrong dismissal is the exact silent failure this probe exists to kill. The one dismissal
   `--auto` may write is measured zero prevalence, with the command and the number in the
   reason string (`dismissed — prevalence 0 in 10/10 cases (cmd: …)`), and only where a real
   corpus exists to count; a harness-only requirement authors the smallest shape set or
   `shapes: []` instead of lighting empty categories (D5).

## `unclassified` and zero-applicable — the two blind-spot alarms

**`unclassified` (#1110).** A requirement with non-empty prose, no authored `shapes` and
zero matched shapes surfaces exactly one soft candidate (`category: "unclassified"`,
`status: "unresolved"`) — otherwise it classifies to zero edges and vanishes from coverage
with no signal. A **review nudge, not a ninth category**, never a hard block: resolve it or
dismiss it with a reason. An explicit `shapes: []` opt-out stays silent (deliberate "no edge
surface"). Under `--auto` it stays `unresolved` and is **named as a question** in the log
and in the Edge Coverage row — a missing shape cue is not evidence an edge exists, so
minting a backstop obligation there would be a false claim.

**Zero applicable across ALL requirements** is far more likely a classification miss or
malformed requirements than a genuinely edge-free spec. Never write a green empty
`## Edge Coverage` section on it — ask for explicit confirmation first.

## Resolution states — two orthogonal axes

ADR-550 Decision 7: lifecycle and verification are separate enums — collapsing them
smuggles a verification fact into the lifecycle.

- **status** — `resolved | dismissed | unresolved`: `resolved` (addressed; *how* = the
  verification tier) · `dismissed` (not applicable, required non-empty reason) ·
  `unresolved` (carried forward and flagged).
- **verification** — `explicit | backstop`, only when `status` is `resolved`, `null`
  otherwise: `explicit` (a
  checkable assertion is written — a SPEC Acceptance Criterion) · `backstop` (a held-out /
  property-based test stands in for an edge the author knows but cannot fully articulate in
  prose; records intent, body authored later).

`coverage.resolved` counts **closed** edges — `resolved` + `dismissed`. An `unresolved`
*applicable* edge is the precise signal a soft completeness gate raises.

Output contract, per edge and in summary:

```
{ requirement_id, category, status, verification, resolution, reason, probe }
coverage: { applicable, resolved, unresolved, byVerification: { explicit, backstop } }
```

Downstream: `resolved`/`explicit` → an Acceptance Criterion that `plan-phase` lifts into
`must_haves.truths`; `resolved`/`backstop` → a non-inferable check in the same set;
`unresolved` → an explicit assumption the planner must surface, never a silent drop.
