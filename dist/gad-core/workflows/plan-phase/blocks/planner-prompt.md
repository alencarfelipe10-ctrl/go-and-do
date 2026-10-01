# plan-phase — planner prompt (step 8)

Lazy block of `workflows/plan-phase.md`. Read it at step 8, right before the `Agent()` call, and pass the filled result as the planner prompt — exactly the text the workflow used to carry inline. Every `{placeholder}` and `${…}` expression below is filled by the orchestrator from the init JSON and the variables of steps 1–7 (`state_path`, `roadmap_path`, `PATTERNS_PATH`, `SPEC_PATH`, `AGENT_SKILLS_PLANNER`, `phase_req_ids`, `PLAN_PRE_HOOKS_JSON` contributions, `COVERAGE`, `MVP_MODE`, `TRACER_MODE`, `REVERSIBILITY_GATES`, `WALKING_SKELETON`, `granularity`, `prior_verify_commands`, `API_SURFACE_PATH`, `CONTEXT_WINDOW`); the planner never sees this file, only the filled prompt. `references/agent-contracts.md` (marker table) is not needed here: the markers the orchestrator waits for are listed in the core's step 8 and 9.

The prompt starts at `<planning_context>` and ends at `</quality_gate>`.

<planning_context>
**Phase:** {phase_number}
**Mode:** {standard | gap_closure | reviews}

<required_reading>
- {state_path} (Project State)
- {roadmap_path} (Roadmap)
- {requirements_path} (Requirements)
- {context_path} (USER DECISIONS from /gad-discuss-phase)
- {research_path} (Technical Research)
- {PATTERNS_PATH} (Pattern Map — analog files and code excerpts, if exists)
- {verification_path} (Verification Gaps - if --gaps)
- {uat_path} (UAT Gaps - if --gaps)
- {reviews_path} (Cross-AI Review Feedback - if --reviews; actionable findings must be incorporated or explicitly deferred/rejected in PLAN.md)
- {AI_SPEC_PATH} (AI Design Contract — framework and evaluation strategy, if exists)
- {UI_SPEC_PATH} (UI Design Contract — visual/interaction specs, if exists)
- {SPEC_PATH} (Phase SPEC — carries the ## Edge Coverage section to lift resolved edges from, if exists)
- {SPIKE_FINDINGS_PATH} (Spike Findings — validated patterns, constraints, landmines from experiments, if exists)
- {SKETCH_FINDINGS_PATH} (Sketch Findings — validated design decisions, CSS patterns, visual direction, if exists)
- {API_SURFACE_PATH} (API Surface — HINT ONLY, when intel capability is active; see <intel_surface_hint> below)

Leia arquivos grandes por faixa com `sed -n 'a,bp'` (ou `grep -n` para achar a faixa), nunca por `cat`: o proxy de tokens do ambiente trunca a saída de `cat` em silêncio e você acredita ter lido o arquivo inteiro — na F24.4 o STATE.md de 76 KB chegou como 2 KB ao planner.
${CONTEXT_WINDOW >= 500000 ? `
**Cross-phase context (1M model enrichment):**
- CONTEXT.md files from the 3 most recent completed phases (locked decisions — maintain consistency)
- SUMMARY.md files from the 3 most recent completed phases (what was built — reuse patterns, avoid duplication)
- LEARNINGS.md files from the 3 most recent completed phases (structured decisions, patterns, lessons, surprises — skip silently if a phase has no LEARNINGS.md; prefix each block with \`[from Phase N LEARNINGS]\` for source attribution; if total size exceeds 15% of context budget, drop oldest first)
- CONTEXT.md, SUMMARY.md, and LEARNINGS.md from any phases listed in the current phase's "Depends on:" field in ROADMAP.md (regardless of recency — explicit dependencies always load, deduplicated against the 3 most recent)
- Skip all other prior phases to stay within context budget
` : ''}
</required_reading>
${prior_verify_commands.length > 0 ? `
<proven_verify_commands>
**Verify commands the previous phase actually ran (#2401) — reuse before re-deriving.** These
are the `<automated>` commands from the nearest prior phase that had any. They resolved from
the executor's cwd in a real run, so a path here is grounded evidence, not a guess. When this
phase's build/test story is the same, **copy the command verbatim**; do not re-derive a
directory. Surfaced at every context window — not part of the 1M enrichment above.

{For each entry in \`prior_verify_commands\`: \`- Phase {phase} · {task}: \\\`{command}\\\`\`}
</proven_verify_commands>
` : ''}
${API_SURFACE_PATH ? `
<intel_surface_hint>
**API Surface (HINT — may be incomplete):** When \`intel.enabled\` is true, \`${API_SURFACE_PATH}\` lists symbols extracted from the codebase by regex/JS analysis. Prefer symbols listed there when referencing existing code. This surface is regex/JS-derived and MAY BE INCOMPLETE — a symbol's absence means *unknown*, not *nonexistent*. Never treat the surface as exhaustive. If you reference a symbol that is not in the surface and this phase creates it, list it under "Artifacts this phase produces".
</intel_surface_hint>
` : ''}
${AGENT_SKILLS_PLANNER}

<review_incorporation_contract>
**If Mode is reviews:** REVIEWS.md is feedback input, not a hidden execution contract. /gad-execute-phase primarily consumes PLAN.md plus the normal phase context, so every current actionable review finding must become visible in the relevant PLAN.md before planning can pass.

For each current actionable finding in REVIEWS.md, the planner MUST either:
- incorporate it into a PLAN.md task, `<action>`, `<acceptance_criteria>`, `<verify>`, `must_haves`, threat model, or artifact list; or
- explicitly document a deferral/rejection rationale in the relevant PLAN.md, using the Review Dispositions Ledger in `gad-core/references/planner-reviews.md`.

Historical findings already incorporated, explicitly deferred/rejected in PLAN.md, or marked fully resolved do not require new plan changes.
</review_incorporation_contract>

**Phase requirement IDs (every ID MUST appear in a plan's `requirements` field):** {phase_req_ids}

<tracked_source_paths>
**Tracked-source paths (#3645):** Every path you write into PLAN.md —
`files_modified`, `must_haves.artifacts`, action paths, and paths inherited
from `{PATTERNS_PATH}` or prior-phase plans — must name git-tracked source,
never a gitignored install/runtime mirror (e.g. `<root>/.gad/capabilities/<id>/...`
synced from a plugin's tracked tree; executor edits to a mirror die on the
next capability sync). Verify existing-file paths with `git ls-files -- <path>`
(non-empty = tracked); resolve a gitignored hit to its tracked origin
(`plugins/*/.gad/capabilities/<id>/...`, root `capabilities/<id>/...`). A
not-yet-existing path is a new file — keep the intended path. Re-verify
inherited paths: fix a mirror path, never inherit. Submodule files: check
from within the submodule.
</tracked_source_paths>

<failing_direction_contract>
**Stated failing direction (#3172):** Every runnable `<automated>` verify command
you write MUST be followed by a `<fails_when>` sibling naming what output
constitutes failure — an exit code, a string in the output, a missing line. A
command with no expressible failure mode is not an acceptance test.

```xml
<verify>
  <automated>npm --prefix apps/api test -- auth.spec.ts</automated>
  <fails_when>non-zero exit, or "0 passed" in the summary line</fails_when>
</verify>
```

One statement per runnable command, placed immediately after it: within a task
each `<fails_when>` binds to the nearest preceding `<automated>`, and the first
statement after a command is the binding one. Name an OBSERVABLE signal, never
the word "failure" — `non-zero exit` is complete, `the command fails` is a
restatement. `TBD`/`TODO`/`N/A`/`none`/`unknown`/`?`/`-` are rejected outright as
whole values. The `MISSING — Wave 0 …` sentinel is exempt: it is not runnable, so
it has no failure mode to state. Ask yourself: if this command were silently
doing nothing, what in its output would tell me? If you cannot answer, fix the
command — do not invent a statement for it.
Rules + worked examples: @gad-core/references/planner-failing-direction.md
</failing_direction_contract>

**Project instructions:** Read ./CLAUDE.md or ./.claude/CLAUDE.md if either exists — follow project-specific guidelines
**Project skills:** Check .claude/skills/ or .agents/skills/ directory (if either exists) — read SKILL.md files, plans should account for project skill rules

{For each active entry in `PLAN_PRE_HOOKS_JSON` where `kind == "contribution"` and `into == "planner"` (in array order): inject the entry's `fragment.inline` verbatim here. This delivers all planner-targeted contributions — including tdd's `<tdd_mode_active>` block (type:tdd heuristics), schema-gate's schema-push detection guidance (if active at plan:pre), and security's threat-model guidance. For the security contribution, also surface the resolved `configValues`: `security_asvs_level` (ASVS enforcement level) and `security_block_on` (severity threshold) so the planner uses the configured values when generating `<threat_model>` blocks. If no active planner contributions exist, omit this block entirely.}

**TRACER_MODE:** ${TRACER_MODE} (false = horizontal layers instead of a leading `type="tracer"` slice; see `planner-mvp-mode.md`.)
**REVERSIBILITY_GATES:** ${REVERSIBILITY_GATES} (false = rate but do not gate; see `planner-reversibility.md`.)
**MVP_MODE:** ${MVP_MODE} (when true, follow vertical-slice rules from `$HOME/.claude/gad-core/references/planner-mvp-mode.md`; when false, ignore MVP guidance entirely.)
**WALKING_SKELETON:** ${WALKING_SKELETON} (when true, the first deliverable must be a Walking Skeleton — Read the template at `$HOME/.claude/gad-core/references/skeleton-template.md` and produce SKELETON.md alongside PLAN.md.)
**Granularity:** {granularity}
**Forma das ondas (o portão §13a-bis confere):** com 4 planos ou mais, ondas/planos abaixo de 0,6 e ao menos uma onda com 2 planos ou mais. É alvo de forma, não cota: o portão reprova cadeia sem lastro e avisa arquivo-hub, nunca um número de planos.

${MVP_MODE === 'true' ? `
<mvp_mode_active>
**MVP Mode is ENABLED.** Read `$HOME/.claude/gad-core/references/planner-mvp-mode.md` now and follow its vertical-slice planning rules. Each plan must deliver a complete vertical slice — thin end-to-end functionality rather than horizontal layers.
</mvp_mode_active>
` : ''}

<specless_probe_fallback>
**Spec-less probe fallback** (only when step 7.95 set `EDGE_ABSENT` and/or `PROHIB_ABSENT`). The SPEC
omitted that section — author its predicates into `must_haves` via the `<downstream_consumer>`
else-branch below, per §A/§B/§C of `$HOME/.claude/gad-core/references/specless-probe-fallback.md`
(descriptor-less prohibitions, never auto-dismiss, no silent drops).

Edge coverage report (`$COVERAGE`, present when `EDGE_ABSENT`):

```json
{COVERAGE}
```
${SPECLESS_FALLBACK_DISABLED ? `
**⚠ ${SPECLESS_FALLBACK_DISABLED}** — record this in the plan (a visible, recorded choice); do not generate probe predicates this run.
` : ''}

</planning_context>

<downstream_consumer>
Output consumed by /gad-execute-phase. Plans need:
- Frontmatter (wave, depends_on, files_modified, autonomous). `wave:` is computed from `depends_on` by the orchestrator's index; write the value that computation gives, or omit it — a declared wave that disagrees with the DAG fails the plan shape gate. Do not edit ROADMAP.md; the orchestrator annotates the waves there in step 13c.
- Tasks in XML format with read_first and acceptance_criteria fields (MANDATORY on every task)
- Verification criteria
- `<verify>` roda só os testes dos módulos que a tarefa tocou. A suíte completa é gate de fase e roda uma vez, pelo host, depois da última onda — não escreva suíte completa em plano nenhum. Comando que passe de dois minutos vai por `roda-suite.sh --lancar/--esperar` (`bin/nosso/`, esperado com `timeout: 600000` na tool), nunca por `( … ) & timeout 1800`: na F24.4 esse waiter estourava dentro de uma tool que morre aos 600 s e dez lançamentos de suíte foram perdidos.
- Teste que o plano deixa vermelho **de propósito** (transitório até outro plano fechar) entra no frontmatter do PLAN.md como `vermelho_esperado: ["tests/golden/test_x.py — até o plano 06"]`. O gate da onda lê essa lista e reporta o vermelho como **esperado**, com o plano que o fecha. Declare o **arquivo**, não o node id: a exclusão do gate é por arquivo. Sem a declaração, vermelho é vermelho: a F24.5 teve a onda 3 verde com dois goldens vermelhos ao lado, e ninguém soube até a suíte completa.
- Comando de `<verify>` cuja duração você **não** conhece: escreva-o com o recorte já embutido (`-k`, node id) e diga, em `<fails_when>`, qual é o comando cheio de confirmação. O executor roda o cheio uma vez, no fim da tarefa; o recorte, quantas vezes precisar. Acima de cinco minutos medidos, o comando cheio vai por `roda-suite.sh --lancar/--esperar`.
- Toda citação de artefato leva **título de seção e faixa de linhas** (`24.4-SPEC.md §Regression Surface, linhas 193-227`), em `<read_first>` e em `<action>`. O executor lê a faixa, não o arquivo; o título é o que permite perceber que a faixa se deslocou. Cite `<read_first>` por símbolo (`arquivo.py#simbolo`) quando o arquivo é editado por uma tarefa anterior do mesmo plano — na F24.4 o plano 03 citou `base.py:N` 28 vezes e a tarefa 1 deslocou todas. DECISOES e SUMMARYs anteriores entram por ponteiro ou trecho citado, nunca por leitura integral.
- must_haves for goal-backward verification
- If the SPEC has an `## Edge Coverage` section, lift every resolved (verification: explicit) edge's acceptance criterion into `must_haves.truths` as a plain string, and every resolved (verification: backstop) edge **as a structured flat-scalar marker** — an object item `{ statement: <the check>, verification: backstop }`, NOT a prose note (the verifier branches deterministically on the `verification: backstop` field; a parenthetical is unparseable — the #1110 fragility). Use a flat scalar `verification:` continuation key, never a nested object (ADR-550 #1278). At verify time a `backstop` truth the verifier cannot confirm with explicit evidence abstains → `human_needed` (reason `insufficient_spec`), never a silent pass (#1154; see `gad-core/references/honest-verifier.md`). `unresolved` edges are explicit assumptions — surface them in the plan, do not silently drop them. **Otherwise** (`EDGE_ABSENT`): apply the SAME lift to the fallback report `{COVERAGE}` (per §C of `gad-core/references/specless-probe-fallback.md`); a SPEC-supplied section is never re-run. Se o SPEC traz o bloco `gsd:acs`, respeite a classe: eleve a `must_haves.truths` os critérios de classe `exigido` e as bordas resolvidas cujo critério é exigido; um critério `desejavel` vira tarefa normal do plano e, quando for verificável, entra em `must_haves.desejaveis` — nunca em `truths` (um critério que não decide a fase não pode reprová-la). Sem o bloco, mantenha a regra de hoje.
- If the SPEC has a `## Prohibitions` section, lift every resolved prohibition into the `must_haves.prohibitions:` sibling block (NOT `truths` — ADR-550 D3) with `statement`+`status`+`verification`, via the single `projectProhibitions` serializer (Hyrum — no second serializer); unresolved -> flagged assumptions, don't drop; never put a must-NOT under `truths`. **Otherwise** (`PROHIB_ABSENT`), author the recalled prohibitions into the SAME block via the SAME `projectProhibitions` contract but **descriptor-less** (no `check_*`) so each disposes flagged-unverified; never auto-dismiss. Section-level precedence + no-silent-drop equality apply (§C).
- If a `-UI-SPEC.md` exists (resolved above as `UI_SPEC_PATH`) with a `## UI Considerations` section, lift it by the **identical rule** as `## Edge Coverage` above — resolved (explicit) → `must_haves.truths` string, resolved (backstop) → flat scalar `{ statement, verification: backstop }`, `unresolved` → explicit planner assumption (no new verb — ADR-550 #1278/#1154; #1867). Read it from `UI_SPEC_PATH` (the SPEC glob excludes `-UI-SPEC.md`).
- **"Artifacts this phase produces" section (MANDATORY)** — list every symbol this phase creates: decorators, classes, functions, CLI flags, struct/dataclass fields, new file paths. The plan-review-convergence source-grounding pass reads this section to exclude newly-created symbols from drift verification; omitting it causes new symbols to be flagged for acknowledgement.
</downstream_consumer>

<deep_work_rules>
## Anti-Shallow Execution Rules (MANDATORY)

Every task MUST include these fields — they are NOT optional:

1. **`<read_first>`** — Files the executor MUST read before touching anything. Always include:
   - The file being modified (so executor sees current state, not assumptions)
   - Any "source of truth" file referenced in CONTEXT.md (reference implementations, existing patterns, config files, schemas)
   - Any file whose patterns, signatures, types, or conventions must be replicated or respected

2. **`<acceptance_criteria>`** — Verifiable conditions that prove the task was done correctly. Rules:
   - Every criterion must be checkable as a source assertion, behavior assertion, test command, or CLI output
   - NEVER use subjective language ("looks correct", "properly configured", "consistent with")
   - Include exact strings, patterns, values, command outputs, or observable behavior where that is the right proof
   - Examples:
     - Code: `auth.py contains def verify_token(` / `test_auth.py exits 0`
     - Behavior: `POST /api/auth/login returns 200 + httpOnly JWT cookie for valid credentials`
     - Config: `.env.example contains DATABASE_URL=` / `Dockerfile contains HEALTHCHECK`
     - Docs: `README.md contains '## Installation'` / `API.md lists all endpoints`
     - Infra: `deploy.yml has rollback step` / `docker-compose.yml has healthcheck for db`

3. **`<action>`** — Must include CONCRETE values, not references. Rules:
   - NEVER say "align X with Y", "match X to Y", "update to be consistent" without specifying the exact target state
   - Include concrete identifiers and reference values: config keys, function signatures, SQL table names, class names, import paths, env vars, endpoint paths, etc.
   - If CONTEXT.md has a comparison table or expected values, copy only the target identifiers/values needed to remove ambiguity
   - Do not include full file contents, fenced code blocks, or complete implementations in `<action>`
   - The executor should understand the intended target state from `<action>` and use `<read_first>` files for current implementation details, patterns, and source-of-truth context

**Why this matters:** Executor agents work from the plan text. Vague instructions like "update the config to match production" produce shallow one-line changes. Concrete instructions like "add DATABASE_URL, set POOL_SIZE=20, add REDIS_URL, and read config/runtime.ts before editing" produce complete work without turning the planner into the executor.
</deep_work_rules>

<quality_gate>
- [ ] PLAN.md files created in phase directory
- [ ] Each plan has valid frontmatter
- [ ] Tasks are specific and actionable
- [ ] Every task has `<read_first>` with at least the file being modified
- [ ] Every task has `<acceptance_criteria>` with behavior, test-command, CLI, or source assertions
- [ ] Every `<action>` contains concrete identifiers without fenced code blocks or full implementations
- [ ] Dependencies correctly identified
- [ ] Waves assigned for parallel execution
- [ ] must_haves derived from phase goal
- [ ] Every PLAN.md includes an "Artifacts this phase produces" section listing symbols created by this phase (decorators, classes, functions, CLI flags, struct/dataclass fields, new file paths)
- [ ] Every SPEC ## Edge Coverage resolved edge is represented in a plan's must_haves (no silent drops)
- [ ] Todo AC de classe `exigido` do SPEC (bloco `gsd:acs`) está representado em `must_haves.truths` de algum plano; nenhum `desejavel` está em `truths`
- [ ] Every UI-SPEC ## UI Considerations resolved consideration is represented in a plan's must_haves (no silent drops)
- [ ] Every SPEC ## Prohibitions resolved item is represented in a plan's must_haves.prohibitions (no silent drops)
</quality_gate>
