# Codebase scout — map selection table

> **Applied by `bin/nosso/scout.sh`** (fork gen5-patches, P11, 01/09/2026): spec-phase Step 2 and the
> `scout_codebase` step of discuss-phase call the script and read `$T/scout.md`; the model no longer
> reads this file. It stays as the documentation of the funnel the script implements.

> Lazy-loaded reference shared by `workflows/spec-phase.md` (Step 2) and the
> `scout_codebase` step of `workflows/discuss-phase.md` (fork: one text, one behaviour).
> It holds the three-layer funnel, the map selection table, the single-read rule, the
> fallbacks and the `<codebase_context>` schema.

## Three-layer funnel — stop at the first layer that answers the question

1. **Codebase docs:** if `.planning/codebase/*.md` exists, read the 2–3 maps the table below
   selects. Freshness check: compare the docs' dates against `git log --oneline --since=<doc date> | head`;
   if many commits landed since, treat the docs as a map with drift — verify load-bearing
   claims in layer 3 before citing them.
2. **Structural graph:** if a code-graph tool is available and populated (Nodes > 0), query
   it for callers/impact/related symbols before any grep.
3. **Surgical Grep/Read:** confirm only what the artifact will actually cite — existing
   implementations, integration points, test coverage gaps.

If neither docs nor graph exist, fall back to full agentic search (the no-maps fallback
below). **discuss-phase with a SPEC:** the SPEC's scout already ran — read the `files`
the SPEC lists and open the funnel only for a fact no gray area can decide without it.

## Phase-type → recommended maps

Read 2–3 maps based on inferred phase type. Do NOT read all seven —
that inflates context without improving discussion quality.

| Phase type (infer from title + ROADMAP entry) | Read these maps |
|---|---|
| UI / frontend / styling / design | CONVENTIONS.md, STRUCTURE.md, STACK.md |
| Backend / API / service / data model | STACK.md, ARCHITECTURE.md, INTEGRATIONS.md |
| Integration / third-party / provider | STACK.md, INTEGRATIONS.md, ARCHITECTURE.md |
| Infrastructure / DevOps / CI / deploy | STACK.md, ARCHITECTURE.md, INTEGRATIONS.md |
| Testing / QA / coverage | TESTING.md, CONVENTIONS.md, STRUCTURE.md |
| Documentation / content | CONVENTIONS.md, STRUCTURE.md |
| Mixed / unclear | STACK.md, ARCHITECTURE.md, CONVENTIONS.md |

Read CONCERNS.md only if the phase explicitly addresses known concerns or
security issues.

## Single-read rule

Read each map file in a **single** Read call. Do not read the same file at
two different offsets — split reads break prompt-cache reuse and cost more
than a single full read.

## No-maps fallback

If `.planning/codebase/*.md` does not exist:
1. Extract key terms from the phase goal (e.g., "feed" → "post", "card",
   "list"; "auth" → "login", "session", "token")
2. `grep -rlE "{term1}|{term2}" src/ app/ --include="*.ts" ...` (use `-E`
   for extended regex so the `|` alternation works on both GNU grep and BSD
   grep / macOS), and `ls` the conventional component/hook/util dirs
3. Read the 3–5 most relevant files

## Output (internal `<codebase_context>`)

From the scan, identify:
- **Reusable assets** — components, hooks, utilities usable in this phase
- **Established patterns** — state management, styling, data fetching
- **Integration points** — routes, nav, providers where new code connects
- **Creative options** — approaches the architecture enables or constrains

Used in `analyze_phase` and `present_gray_areas`. NOT written to a file —
session-only.
