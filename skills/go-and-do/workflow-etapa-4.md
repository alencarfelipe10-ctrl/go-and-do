<!-- workflow-etapa-4.md — Etapa 4 (Gates de qualidade) of the go-and-do workflow: the
     <stage id="4"> block, moved verbatim out of workflow.md (mapa-gad task 9). Layer 0 reads
     it on entering Etapa 4, in the same response as the stage's first command (workflow.md <pipeline_index>). -->

<stage id="4" name="Gates de qualidade">

> Layer 0 fully mechanized (4.A): for EACH gate, `pre-despacho.sh 4-<gate>` resolves
> flag/config/resume into an exit code and `confere-etapa.sh 4-<gate>` asserts the artifact
> and extracts the canonical verdict. What remains for judgment: digesting `needs_decision`
> and the 🔔 prose at the close.

### 4.1 — Code review (via subagent)
- `pre-despacho.sh 4-code-review` → `ok`? Dispatch via Sub-rotina H as
  `Agent(subagent_type="gad-gates")` (own def: Opus 5.5, cache 1 h — FM-F4RLR-03GAT; also
  iterations 2+ and 4.1b) with
  `prompts/code-review.md` (`iteracao: 1`): hosts `gsd-code-review N --fix --auto` with the
  parallel Codex lane (4.D, merged as `fonte: codex`; codex absent does not block). Iterations
  2+ and the 4.1b gate dispatch with `iteracao: 2+` — the subagent narrows via
  `calcula-files.sh` (4.C).
- On return: `confere-etapa.sh 4-code-review` (extracts `status`/`critical`/`warning`/
  `total`). Always continues; remaining `critical` → strong 🔔. Keep `uat_humano` (input of
  5.3). `blocked` → `stop`, stop.
- **`needs_decision`** → question + continuation via Sub-rotina I — including a finding the
  reviewer tagged "não aplicar sem o dono": it returns `needs_decision`, never `done` with the
  finding silently skipped (FJ-01GAT). Ask, apply the fix INSIDE this gate once answered, and
  only then let the fiscal → `end` → recibo sequence close.
- **Fixer briefing extends past 4.1b (FJ-F27INS-02GAT).** The "what else reads or writes this
  state" ask two bullets below is not 4.1b-only anymore: `code-review.md` §2b now carries the
  same line for every finding the HOST itself drafts a fix suggestion for (the Codex merge,
  the dedup). The native reviewer's own iteration-1 findings stay out of reach — their fixer
  briefing is built inside `gsd-code-review --fix`, upstream, not by this prompt.
- **Gate 4.1b is its own re-dispatch of 4.1, not a footnote of it** (FM-02GAT): open a
  checkpoint labeled **"4.1b re-review"**, run `pre-despacho.sh 4-code-review` and
  `confere-etapa.sh 4-code-review` exactly like 4.1, and stamp its own `.gad/fences/4.1b.ok`. It
  does not inherit 4.1's fence.
- **The host never fixes a 4.1b finding itself** (FJ-04GAT): it goes to `gsd-code-fixer` with a
  scope EQUAL to the finding's own scope. Widening that scope, or changing observable behavior
  beyond what the finding names, is a question to the owner, not a host judgment call. Every
  fix from the 4.1b fixer forces a re-review — it is not exempt from the loop it triggered.
  Fixer briefing: run the finding's own suite before returning, and list, per commit, "what
  else reads or writes this state" — the re-review starts from that list (MGTk-01GAT).

### 4.2 — UI review · only with `--ui` → conduct by `workflow-ui.md`.

### 4.3 — Eval review · only with `--ai` → conduct by `workflow-ai.md`.

### 4.4 — Secure phase (via subagent)
- `pre-despacho.sh 4-secure` → `ok`? Dispatch as `Agent(subagent_type="gad-gates")` with `prompts/secure.md`. A threat decision
  comes up as `needs_decision` already digested (4.E: threat, severity, options with the
  recommendation first).
- On return: `confere-etapa.sh 4-secure` — exit ≠ 0 (`threats_open` > 0 or acceptance
  without owner) is the ONLY blocking gate of the stage: ⏸️ stop. Secure touched src/ AFTER
  the review → gate 4.1b: `calcula-files.sh --tocados "<arquivos>"` → narrowed re-dispatch of
  4.1.

### 4.5 — Validate phase (via subagent)
- `pre-despacho.sh 4-validate` → `ok`? Dispatch as `Agent(subagent_type="gad-gates")` with `prompts/validate.md`. ⏸️ Gaps →
  `needs_decision` (Fix all recommended). On return: `confere-etapa.sh 4-validate`. Continue.
  When gate 4.1b exists (secure or a late commit reopened it), dispatch 4.5 in PARALLEL with
  4.1b instead of after it — validate only reads the map and runs the suite; if 4.1b fixes
  something, re-run 4.5's suite alone afterward, not the whole validate (MGTm-01GAT).

**Every gate host reports incidents at the moment they happen** (same contract as C1/C3),
via `run-log.sh "<phase_dir>" "<NN>" incidente "<etapa>" --kv origem=… --kv detalhe=…` — before whatever else the
host was about to do (FM-07GAT).

</stage>
