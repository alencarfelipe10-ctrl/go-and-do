# Phase Spec Template

Template for `.planning/phases/XX-name/{phase_num}-SPEC.md` — locks requirements before discuss-phase.

**Purpose:** Capture WHAT a phase delivers and WHY, with enough precision that requirements are falsifiable. discuss-phase reads this file and focuses on HOW to implement (skipping "what/why" questions already answered here).

**Key principle:** Every requirement must be falsifiable — you can write a test or check that proves it was met or not. Vague requirements like "improve performance" are not allowed.

**Downstream consumers:**
- `discuss-phase` — reads SPEC.md at startup; treats Requirements, Boundaries, and Acceptance Criteria as locked; skips "what/why" questions
- `gad-planner` — reads locked requirements to constrain plan scope
- `gad-verifier` — uses acceptance criteria as explicit pass/fail checks
- `/go-and-do` (fork) — `discuss-init.sh` lê `## Artefatos novos commitados`; `confere-pre-spec.sh` lê `## Limitações declaradas`, `## Cobertura do Goal` e o bloco `gsd:acs`; a releitura de ciclo 0 lê `## Consistência interna`. Esses quatro headings são contrato de máquina em português — não traduzir, não renomear, sem subtítulos dentro deles. `gad-planner` lê a classe de cada critério (`gsd:acs`) para decidir o que vira `must_haves.truths`.

---

## File Template

```markdown
# Phase [X]: [Name] — Specification

**Created:** [date]
**Ambiguity score:** [score] (gate: ≤ 0.20)
**Requirements:** [N] locked
<!-- spec-origem: v1 -->
<!-- spec-classe: v1 -->

## Goal

[One precise sentence — specific and measurable. NOT "improve X" — instead "X changes from A to B".]

## Background

[Current state from codebase — what exists today, what's broken or missing, what triggers this work. Grounded in code reality, not abstract description.]

## Requirements

1. **[Short label]**: [Specific, testable statement.]
   - Current: [what exists or does NOT exist today]
   - Target: [what it should become after this phase]
   - Acceptance: [concrete pass/fail check — how a verifier confirms this was met]
   - Trigger: [evidência | fala-do-dono | pedido-do-dono | upstream | higiene | não-regressão] — [one sentence: WHY this requirement exists. `ver NN-PRE-SPEC.md` allowed. The Current line is not a trigger.]

2. **[Short label]**: [Specific, testable statement.]
   - Current: [what exists or does NOT exist today]
   - Target: [what it should become after this phase]
   - Acceptance: [concrete pass/fail check]
   - Trigger: [type] — [one sentence]

[Continue for all requirements. Each must have Current/Target/Acceptance/Trigger.
If any requirement lacks a trigger, the workflow prints `Trigger coverage: N/M` as a
warning — never a gate.]

## Boundaries

**In scope:**
- [Explicit list of what this phase produces]
- [Each item is a concrete deliverable or behavior]

**Out of scope:**
- [Explicit list of what this phase does NOT do] — [brief reason why it's excluded]
- [Adjacent problems excluded from this phase] — [brief reason]

## Constraints

[Performance, compatibility, data volume, dependency, or platform constraints.
If none: "No additional constraints beyond standard project conventions."]

## Acceptance Criteria

- [ ] AC-01 — [Pass/fail criterion — unambiguous, verifiable] [exigido: <motivo em uma frase>] [origem: AA-1, R1]
- [ ] AC-02 — [Pass/fail criterion] [exigido: <motivo>] [diverge: AA-2 — <porquê>] [origem: AA-2, PS-01]
- [ ] AC-03 — [Pass/fail criterion] [desejável] [origem: AC-01]

[Every acceptance criterion must be a checkbox that resolves to PASS or FAIL.
No "should feel good", "looks reasonable", or "generally works" — those are not checkboxes.
Every criterion ends with `[origem: <ids>]`: comma-separated `PS-nn` (pre-spec item), `AA-n` (item n
of the pre-spec's `## Anexo A`), `Goal` (the measured Goal paragraph above), `R-n`/`SC-n` or a
REQUIREMENTS id (`CANC-v3x-03`), or `AC-nn` of this SPEC for a derived criterion. A criterion
with no origin is one nobody asked for — `confere-pre-spec.sh` rejects it (`AC-SEM-ORIGEM`) and
rejects ids that do not exist (`AC-ORIGEM-INEXISTENTE`). The `<!-- spec-origem: v1 -->` marker in
the header is what turns the check on; keep it. The origin is a field, never the body: an AC whose
body is only the origin is a pointer (`AC-POR-PONTEIRO`).

Cada critério declara a classe. `[exigido: motivo]` é o critério que, falhando, deixa a fase por
fazer; o motivo é a régua e a origem tem de ser régua de resultado — item do Anexo A da pré-spec
(`AA-n`), `PS-nn` (a fala do cliente entra pelo `PS-nn` ou `AA-n` que a registra), não-regressão ou
o Goal. `[desejável]` é o critério que orienta o trabalho: continua verificável e continua entrando
na suíte, mas sozinho não reprova a fase. Um exigido cuja origem é só outro AC, uma célula da grade
de bordas ou um ciclo adversarial não tem régua de resultado — `confere-pre-spec.sh` reprova a
combinação (`EXIGIDO-SEM-REGUA`). Um exigido que diverge do item do Anexo A que cita leva
`[diverge: AA-n — <porquê>]`; sem ela, reprova (`EXIGIDO-DIVERGE-SEM-MOTIVO`). Sem classe, ou com
classe diferente da do bloco `gsd:acs`, reprova (`AC-SEM-CLASSE`); exigido sem motivo reprova
(`EXIGIDO-SEM-MOTIVO`). O marcador `<!-- spec-classe: v1 -->` do cabeçalho é o que liga essas
conferências; mantenha-o. Não há cota: a pergunta é se o critério serve ao objetivo desta fase,
nunca quantos existem.]

## Critérios exigidos

| AC | Régua (origem) | Motivo | Efeito do Goal que cobre |
|----|----------------|--------|--------------------------|
| [AC-01] | [AA-1] | [motivo em uma frase, o mesmo do `[exigido: …]`] | [qual efeito medido do Goal este critério fecha] |

[Uma linha por `[exigido]`. É a decisão escrita: a prosa é o contrato humano, o bloco `gsd:acs` é o
contrato de máquina, e os dois dizem o mesmo. Um exigido que não cabe nesta tabela não é exigido.]

<!-- Heading é CONTRATO DE MÁQUINA (D9): `confere-pre-spec.sh` lê exatamente
     `## Cobertura do Goal` e a linha `**Efeitos sem cobertura:**` (GOAL-SEM-COBERTURA). NÃO
     traduza o heading e NÃO crie subtítulos dentro da seção. -->

## Cobertura do Goal

| Efeito medido do Goal | ACs exigidos que o cobrem | Veredito |
|-----------------------|---------------------------|----------|
| [um efeito medido do parágrafo do Goal] | [AC-01, AC-02] | [coberto / DESCOBERTO — o que falta] |

**Efeitos sem cobertura:** [nenhum · ou um por linha]

[Pergunta de fecho: com todos os exigidos verdes, cada efeito medido do Goal está coberto? Um
efeito por linha; um efeito sem exigido que o cubra é o buraco que a fase não fecha. Repita o
veredito em uma linha na `## Consistência interna`.]

<!-- Heading é CONTRATO DE MÁQUINA (R5a): `discuss-init.sh` lê exatamente
     `## Artefatos novos commitados` e emite uma gray area obrigatória por linha. NÃO
     traduza o heading e NÃO crie subtítulos dentro da seção. -->

## Artefatos novos commitados

| Caminho | Conteúdo |
|---------|----------|
| [tests/fixtures/24.3-dre.json] | [baseline do DRE — 14 meses, sem PII] |

[Todo artefato NOVO que esta fase passa a versionar: baseline, golden, fixture, snapshot,
seed. Um por linha: caminho final no repositório + o que o arquivo contém. Cada linha vira
uma decisão obrigatória no discuss (diretório espelhado/público? dado pessoal? precedente?).
Se a fase não commita nenhum artefato novo, a seção diz exatamente isto e nada mais:
"Nenhum artefato novo commitado."]

## Regression Surface

**Sweep:** [git grep of each changed constant/value/invariant across code AND tests]

| Existing assertion (file:line) | What this phase changes | Verdict | Reconciliation |
|--------------------------------|-------------------------|---------|----------------|
| [tests/test_report.py:42 — asserts TOTAL == 1,234] | [target becomes 1,456] | [invert / re-anchor / remove] | [which plan owns the fix] |

[What stops being true when this phase lands. For each constant, count, target value, or
invariant a requirement changes, list every existing assertion/contract/golden it
falsifies. If the sweep found none, say so explicitly: "No existing assertions falsified
— swept [date]". The planner carries each row into the owning plan.]

## Edge Coverage

**Coverage:** [resolved]/[applicable] applicable edges resolved · [unresolved] unresolved

| Category | Requirement | Status | Resolution / Reason |
|----------|-------------|--------|---------------------|
| [category] | [Rn] | [✅ covered / ⛔ dismissed / 🧪 backstop / ⚠ UNRESOLVED] | [acceptance criterion ref, dismissal reason, or backstop test note] |

[Generated by the edge-completeness probe (Step 5.5). `covered` rows correspond to
Acceptance Criteria above; `backstop` rows must be carried into plan-phase `must_haves`.
`⚠ UNRESOLVED` rows are flagged: planner must treat as assumption.]

## Prohibitions (must-NOT)

**Coverage:** [resolved]/[applicable] applicable prohibitions resolved · [unresolved] unresolved

| Prohibition (must-NOT statement) | Requirement | Status | Verification / Reason |
|----------------------------------|-------------|--------|------------------------|
| [MUST NOT … must-NOT statement] | [Rn] | [resolved / dismissed / ⚠ UNRESOLVED] | [verification: test \| judgment, or dismissal reason] |

[Generated by the prohibition probe (Step 5.6). `resolved` prohibitions become NEGATIVE
acceptance criteria; a `resolved`/`test` row is a checkable negative the verifier iterates
over, a `resolved`/`judgment` row routes to judgment review. Resolved prohibitions are lifted
into `must_haves.prohibitions` by plan-phase. `dismissed` rows carry a required non-empty
reason. `⚠ UNRESOLVED` rows are flagged: planner must treat as assumption.]

<!-- Heading é CONTRATO DE MÁQUINA (R4): a releitura de ciclo 0 da /go-and-do
     (`prompts/intent-releitura.md`) lê exatamente `## Consistência interna`. NÃO traduza o
     heading e NÃO crie subtítulos dentro da seção. -->

## Consistência interna

| MUST NOT | AC que precisam do recurso proibido | Veredito |
|----------|-------------------------------------|----------|
| [MUST NOT … ] | [AC-10, AC-42] | [compatível / CONFLITO — como foi resolvido] |

**Conflitos encontrados:** [nenhum · ou uma linha por par insatisfazível, dizendo se foi
corrigido no SPEC ou virou sino para o revisor]

**Goal coberto:** [sim · ou os efeitos descobertos, um por linha — o mesmo veredito da `## Cobertura do Goal`]

[Passe de consistência rodado depois de escrever as Prohibitions e antes do commit: cada
`MUST NOT` é cruzado com os ACs que precisariam do recurso proibido. Par insatisfazível se
corrige aqui ou vira sino — nunca fica em silêncio. Se não há `MUST NOT`, a seção diz
"Sem MUST NOT — nada a cruzar." A linha `**Goal coberto:**` repete o veredito da cobertura para
a releitura de ciclo 0, que recebe esta seção inteira.]

<!-- Heading é CONTRATO DE MÁQUINA (R7): `confere-pre-spec.sh` exige, para cada PS-nn do
     bloco `gad:decisoes` do PRE-SPEC que tenha `ressalva`, UMA LINHA aqui citando o
     `PS-nn`. A varredura para no próximo heading de qualquer nível. NÃO traduza o heading e
     NÃO crie subtítulos dentro da seção. -->

## Limitações declaradas

- [PS-01] — [a ressalva, dita como limitação que o SPEC assume] · [consequência observável]
- [PS-02] — descartada: [por que a ressalva não se aplica a este SPEC]

[Uma linha por `PS-nn` com `ressalva` no PRE-SPEC. Ou o SPEC assume a limitação (e a
descreve), ou a descarta com o porquê — `descartada: …`. Uma linha solta sem `PS-nn` não
cobre nada. Sem PRE-SPEC, ou sem nenhuma ressalva: "Nenhuma ressalva do PRE-SPEC — nada a
declarar."]

## Machine-Readable Requirements

<!-- gsd:reqs:begin -->
[
  { "id": "R1", "text": "[the requirement, verbatim, in the project language]", "text_en": "[faithful English translation — only when response_language is set]", "shapes": ["[authored shape]"], "trigger": "[trigger type]", "files": ["[relative path the scout found for this requirement — optional]"] }
]
<!-- gsd:reqs:end -->

<!-- gsd:scope:begin -->
{"in": ["[each In-scope bullet, verbatim]"], "out": ["[each Out-of-scope bullet, verbatim]"]}
<!-- gsd:scope:end -->

<!-- gsd:acs:begin -->
[
  { "id": "AC-01", "classe": "exigido", "motivo": "[one sentence]", "origem": ["AA-1", "R1"], "diverge": null },
  { "id": "AC-02", "classe": "exigido", "motivo": "[one sentence]", "origem": ["AA-2", "PS-01"], "diverge": { "item": "AA-2", "porque": "[why this criterion departs from the annex item]" } },
  { "id": "AC-03", "classe": "desejavel", "motivo": null, "origem": ["AC-01"], "diverge": null }
]
<!-- gsd:acs:end -->

[One object per requirement. `text` is the requirement itself, in the project language (same
words as the prose above); `text_en` is its faithful English translation, present for EVERY
requirement when `response_language` is set and omitted otherwise — the edge probe reads
`text_en ?? text` (upstream #4156); `shapes` is ALWAYS authored by the model; `trigger` is
the type from the requirement's Trigger line. The edge probe (Step 5.5) consumes exactly
this block via the markers — it is the bridge between the prose SPEC and the engine. `files` is
optional and never validated by the probe; the `gsd:scope` block is a separate marker pair (never an
item of the array) that discuss-phase renders into `<spec_lock>` without parsing prose.

Um objeto por critério de aceite no bloco `gsd:acs`. `classe` ∈ `exigido|desejavel` (ASCII, sem
acento — é chave lida por máquina); `motivo` obrigatório em `exigido`, `null` em `desejavel`;
`origem` é a mesma lista do `[origem: …]` da prosa; `diverge` é `{"item": "AA-n", "porque": "…"}`
ou `null`. A classe é o que a máquina lê; o rótulo com acento na prosa é o que a pessoa lê, e os
dois têm de dizer o mesmo. Este bloco é irmão do `gsd:reqs`, nunca um item dele: o motor da sonda
de bordas valida cada item do array contra o padrão `R<n>` e falha fechado com qualquer outro id.]

## Ambiguity Report

[If any requirement lacks a trigger, record here: `Trigger coverage: N/M — sem trigger: [R…]`]

| Dimension          | Score | Min  | Status | Notes                              |
|--------------------|-------|------|--------|------------------------------------|
| Goal Clarity       |       | 0.75 |        |                                    |
| Boundary Clarity   |       | 0.70 |        |                                    |
| Constraint Clarity |       | 0.65 |        |                                    |
| Acceptance Criteria|       | 0.70 |        |                                    |
| **Ambiguity**      |       | ≤0.20|        |                                    |

Status: ✓ = met minimum, ⚠ = below minimum (planner treats as assumption)

## Interview Log

[Key decisions made during the Socratic interview. Format: round → question → answer → decision locked.]

| Round | Perspective    | Question summary         | Decision locked                    |
|-------|----------------|-------------------------|------------------------------------|
| 1     | Researcher     | [what was asked]        | [what was decided]                 |
| 2     | Simplifier     | [what was asked]        | [what was decided]                 |
| 3     | Boundary Keeper| [what was asked]        | [what was decided]                 |

[If --auto mode: note "auto-selected" decisions with the reasoning Claude used.]

---

*Phase: [XX-name]*
*Spec created: [date]*
*Next step: /gad-discuss-phase [X] — implementation decisions (how to build what's specified above)*
```

<good_examples>

**Example 1: Feature addition (Post Feed)**

```markdown
# Phase 3: Post Feed — Specification

**Created:** 2025-01-20
**Ambiguity score:** 0.12
**Requirements:** 4 locked
<!-- spec-origem: v1 -->
<!-- spec-classe: v1 -->

## Goal

Users can scroll through posts from accounts they follow, with new posts available after pull-to-refresh.

## Background

The database has a `posts` table and `follows` table. No feed query or feed UI exists today. The home screen shows a placeholder "Your feed will appear here." This phase builds the feed query, API endpoint, and the feed list component.

## Requirements

1. **Feed query**: Returns posts from followed accounts ordered by creation time, descending.
   - Current: No feed query exists — `posts` table is queried directly only from profile pages
   - Target: `GET /api/feed` returns paginated posts from followed accounts, newest first, max 20 per page
   - Acceptance: Query returns correct posts for a user who follows 3 accounts with known post counts; cursor-based pagination advances correctly

2. **Feed display**: Posts display in a scrollable card list.
   - Current: Home screen shows static placeholder text
   - Target: Home screen renders feed cards with author, timestamp, post content, and reaction count
   - Acceptance: Feed renders without error for 0 posts (empty state shown), 1 post, and 20+ posts

3. **Pull-to-refresh**: User can refresh the feed manually.
   - Current: No refresh mechanism exists
   - Target: Pull-down gesture triggers refetch; new posts appear at top of list
   - Acceptance: After a new post is created in test, pull-to-refresh shows the new post without full app restart

4. **New posts indicator**: When new posts arrive, a banner appears instead of auto-scrolling.
   - Current: No such mechanism
   - Target: "3 new posts" banner appears when refetch returns posts newer than the oldest visible post; tapping banner scrolls to top and shows new posts
   - Acceptance: Banner appears for ≥1 new post, does not appear when no new posts, tap navigates to top

## Boundaries

**In scope:**
- Feed query (backend) — posts from followed accounts, paginated
- Feed list UI (frontend) — post cards with author, timestamp, content, reaction counts
- Pull-to-refresh gesture
- New posts indicator banner
- Empty state when user follows no one or no posts exist

**Out of scope:**
- Creating posts — that is Phase 4
- Reacting to posts — that is Phase 5
- Following/unfollowing accounts — that is Phase 2 (already done)
- Push notifications for new posts — separate backlog item

## Constraints

- Feed query must use cursor-based pagination (not offset) — the database has 500K+ posts and offset pagination is unacceptably slow beyond page 3
- The feed card component must reuse the existing `<AvatarImage>` component from Phase 2

## Acceptance Criteria

- [ ] AC-01 — `GET /api/feed` returns posts only from followed accounts (not all posts) [exigido: a feed that shows unfollowed posts is not the feed the Goal names] [origem: Goal, R1]
- [ ] AC-02 — `GET /api/feed` supports `cursor` parameter for pagination [exigido: without cursor pagination the feed is unusable past page 3 on 500K posts] [origem: R1]
- [ ] AC-03 — Feed renders correctly at 0, 1, and 20+ posts [desejável] [origem: R2]
- [ ] AC-04 — Pull-to-refresh triggers refetch [exigido: "new posts after pull-to-refresh" is the second half of the Goal] [origem: Goal, R3]
- [ ] AC-05 — New posts indicator appears when posts newer than current view exist [desejável] [origem: R4]
- [ ] AC-06 — Empty state renders when user follows no one [desejável] [origem: AC-03]

## Critérios exigidos

| AC | Régua (origem) | Motivo | Efeito do Goal que cobre |
|----|----------------|--------|--------------------------|
| AC-01 | Goal, R1 | a feed that shows unfollowed posts is not the feed the Goal names | posts from followed accounts |
| AC-02 | R1 | without cursor pagination the feed is unusable past page 3 on 500K posts | scroll through posts |
| AC-04 | Goal, R3 | "new posts after pull-to-refresh" is the second half of the Goal | new posts after pull-to-refresh |

## Cobertura do Goal

| Efeito medido do Goal | ACs exigidos que o cobrem | Veredito |
|-----------------------|---------------------------|----------|
| scroll through posts from followed accounts | AC-01, AC-02 | coberto |
| new posts available after pull-to-refresh | AC-04 | coberto |

**Efeitos sem cobertura:** nenhum

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                            |
|--------------------|-------|------|--------|----------------------------------|
| Goal Clarity       | 0.92  | 0.75 | ✓      |                                  |
| Boundary Clarity   | 0.95  | 0.70 | ✓      | Explicit out-of-scope list       |
| Constraint Clarity | 0.80  | 0.65 | ✓      | Cursor pagination required       |
| Acceptance Criteria| 0.85  | 0.70 | ✓      | 6 pass/fail criteria             |
| **Ambiguity**      | 0.12  | ≤0.20| ✓      |                                  |

## Interview Log

| Round | Perspective     | Question summary              | Decision locked                         |
|-------|-----------------|------------------------------|-----------------------------------------|
| 1     | Researcher      | What exists in posts today?  | posts + follows tables exist, no feed  |
| 2     | Simplifier      | Minimum viable feed?         | Cards + pull-refresh, no auto-scroll   |
| 3     | Boundary Keeper | What's NOT this phase?       | Creating posts, reactions out of scope |
| 3     | Boundary Keeper | What does done look like?    | Scrollable feed with 4 card fields     |

---

*Phase: 03-post-feed*
*Spec created: 2025-01-20*
*Next step: /gad-discuss-phase 3 — implementation decisions (card layout, loading skeleton, etc.)*
```

**Example 2: CLI tool (Database backup)**

```markdown
# Phase 2: Backup Command — Specification

**Created:** 2025-01-20
**Ambiguity score:** 0.15
**Requirements:** 3 locked
<!-- spec-origem: v1 -->
<!-- spec-classe: v1 -->

## Goal

A `gad backup` CLI command creates a reproducible database snapshot that can be restored by `gad restore` (a separate phase).

## Background

No backup tooling exists. The project uses PostgreSQL. Developers currently use `pg_dump` manually — there is no standardized process, no output naming convention, and no CI integration. Three incidents in the last quarter involved restoring from wrong or corrupt dumps.

## Requirements

1. **Backup creation**: CLI command executes a full database backup.
   - Current: No `backup` subcommand exists in the CLI
   - Target: `gad backup` connects to the database (via `DATABASE_URL` env or `--db` flag), runs pg_dump, writes output to `./backups/YYYY-MM-DD_HH-MM-SS.dump`
   - Acceptance: Running `gad backup` on a test database creates a `.dump` file; running `pg_restore` on that file recreates the database without error

2. **Network retry**: Transient network failures are retried automatically.
   - Current: pg_dump fails immediately on network error
   - Target: Backup retries up to 3 times with 5-second delay; 4th failure exits with code 1 and a message to stderr
   - Acceptance: Simulating 2 sequential network failures causes 2 retries then success; simulating 4 failures causes exit code 1 and stderr message

3. **Partial cleanup**: Failed backups do not leave corrupt files.
   - Current: Manual pg_dump leaves partial files on failure
   - Target: If backup fails after starting, the partial `.dump` file is deleted before exit
   - Acceptance: After a simulated failure mid-dump, no `.dump` file exists in `./backups/`

## Boundaries

**In scope:**
- `gad backup` subcommand (full dump only)
- Output to `./backups/` directory (created if missing)
- Network retry (3 attempts)
- Partial file cleanup on failure

**Out of scope:**
- `gad restore` — that is Phase 3
- Incremental backups — separate backlog item (full dump only for now)
- S3 or remote storage — separate backlog item
- Encryption — separate backlog item
- Scheduled/cron backups — separate backlog item

## Constraints

- Must use `pg_dump` (not a custom query) — ensures compatibility with standard `pg_restore`
- `--no-retry` flag must be available for CI use (fail fast, no retries)

## Acceptance Criteria

- [ ] AC-01 — `gad backup` creates a `.dump` file in `./backups/YYYY-MM-DD_HH-MM-SS.dump` format [exigido: the snapshot `gad restore` will read is the Goal itself] [origem: Goal, R1]
- [ ] AC-02 — `gad backup` uses `DATABASE_URL` env var or `--db` flag for connection [desejável] [origem: R1]
- [ ] AC-03 — 3 retries on network failure, then exit code 1 with stderr message [desejável] [origem: R2]
- [ ] AC-04 — `--no-retry` flag skips retries and fails immediately on first error [desejável] [origem: R2]
- [ ] AC-05 — No partial `.dump` file left after a failed backup [exigido: a corrupt partial dump is the incident class this phase exists to end] [origem: Goal, R3]

## Critérios exigidos

| AC | Régua (origem) | Motivo | Efeito do Goal que cobre |
|----|----------------|--------|--------------------------|
| AC-01 | Goal, R1 | the snapshot `gad restore` will read is the Goal itself | reproducible snapshot exists |
| AC-05 | Goal, R3 | a corrupt partial dump is the incident class this phase exists to end | snapshot is restorable (never corrupt) |

## Cobertura do Goal

| Efeito medido do Goal | ACs exigidos que o cobrem | Veredito |
|-----------------------|---------------------------|----------|
| a reproducible snapshot is created | AC-01 | coberto |
| the snapshot can be restored | AC-05 | coberto |

**Efeitos sem cobertura:** nenhum

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                          |
|--------------------|-------|------|--------|--------------------------------|
| Goal Clarity       | 0.90  | 0.75 | ✓      |                                |
| Boundary Clarity   | 0.95  | 0.70 | ✓      | Explicit out-of-scope list     |
| Constraint Clarity | 0.75  | 0.65 | ✓      | pg_dump required               |
| Acceptance Criteria| 0.80  | 0.70 | ✓      | 5 pass/fail criteria           |
| **Ambiguity**      | 0.15  | ≤0.20| ✓      |                                |

## Interview Log

| Round | Perspective     | Question summary              | Decision locked                         |
|-------|-----------------|------------------------------|-----------------------------------------|
| 1     | Researcher      | What backup tooling exists?  | None — pg_dump manual only             |
| 2     | Simplifier      | Minimum viable backup?       | Full dump only, local only             |
| 3     | Boundary Keeper | What's NOT this phase?       | Restore, S3, encryption excluded       |
| 4     | Failure Analyst | What goes wrong on failure?  | Partial files, CI fail-fast needed     |

---

*Phase: 02-backup-command*
*Spec created: 2025-01-20*
*Next step: /gad-discuss-phase 2 — implementation decisions (progress reporting, flag design, etc.)*
```

</good_examples>

<guidelines>
**Every requirement needs all three fields:**
- Current: grounds the requirement in reality — what exists today?
- Target: the concrete change — not "improve X" but "X becomes Y"
- Acceptance: the falsifiable check — how does a verifier confirm this?

**Ambiguity Report must reflect the actual interview.** If a dimension is below minimum, mark it ⚠ — the planner knows to treat it as an assumption rather than a locked requirement.

**Interview Log is evidence of rigor.** Don't skip it. It shows that requirements came from discovery, not assumption.

**Boundaries protect the phase from scope creep.** The out-of-scope list with reasoning is as important as the in-scope list. Future phases that touch adjacent areas can point to this SPEC.md to understand what was intentionally excluded.

**SPEC.md is a one-way door for requirements.** discuss-phase will treat these as locked. If requirements change after SPEC.md is written, the user should update SPEC.md first, then re-run discuss-phase.

**SPEC.md does NOT replace CONTEXT.md.** They serve different purposes:
- SPEC.md: what the phase delivers (requirements, boundaries, acceptance criteria)
- CONTEXT.md: how the phase will be implemented (decisions, patterns, tradeoffs)

discuss-phase generates CONTEXT.md after reading SPEC.md.
</guidelines>
