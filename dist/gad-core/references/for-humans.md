# For-Humans Companion Docs

Every SPEC.md **and every CONTEXT.md** gets a plain-language companion the project owner can actually read:
`{phase_dir}/for-humans/{padded_phase}-SPEC-FH.md` / `{padded_phase}-CONTEXT-FH.md` plus a styled `.html` rendered from it.
The SPEC/CONTEXT stays canonical; the FH doc is a faithful translation for a non-technical reader.
For a CONTEXT the same 5 sections apply with the decisions document as source: "O que vai existir"
translates the decisions (what was chosen and why), "deixar de fora" the deferred ideas, "Como saberemos"
the evidence/anchors, "Pontos de atenção" the one-way/costly reversibility notes.

## Rules of translation

- **Translate, don't transpose.** Say what the thing does for the reader, not what the
  code does. "O alarme de segurança do banco volta a funcionar" beats "o workflow de CI
  de RLS é corrigido".
- **A technical term gets half a sentence of explanation** the first time it appears —
  e.g. "RLS (a regra que impede um usuário de ver dados dos outros)". Never a glossary.
- **Keep the depth.** Simplify the language, never the content: numbers, counts, and
  consequences from the SPEC survive into the FH doc.
- **Write in the project's `response_language`** (the owner's language).
- ~40 lines total. If it grows past that, you are transposing, not translating.

## Skeleton (all 5 sections, in this order)

```markdown
# Fase [X] — [Nome] · resumo para humanos

**Em uma frase:** [o resultado da fase, dito como benefício concreto para o dono.]

## Por que estamos fazendo isso

[O gatilho e o problema, em 1 parágrafo. Traduz o Background do SPEC.]

## O que vai existir quando terminar

- [Um bullet por entregável visível — traduz os Requirements.]

## O que decidimos deixar de fora (e por quê)

- [Um bullet por exclusão relevante — traduz o Out of scope, com a razão.]

## Como saberemos que deu certo

- [Perguntas de sim/não que o dono consegue responder — traduzem os Acceptance Criteria.]

## Pontos de atenção

- [Riscos, limitações e comportamentos que podem surpreender — traduz Constraints/Prohibitions.]

*Gerado do [NN]-SPEC.md ([projeto]) em [data] — o documento canônico é o SPEC.*
```

## Rendering the HTML

After writing the `.md`, render the `.html` next to it with the deterministic converter:

```bash
FH_RENDER="$(dirname "$(readlink -f "$GAD_TOOLS")")/nosso/fh-render.py"
[ -f "$FH_RENDER" ] || FH_RENDER="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/nosso/fh-render.py"
python3 "$FH_RENDER" "{phase_dir}/for-humans/{padded_phase}-SPEC-FH.md"   # or …-CONTEXT-FH.md
```

(`GAD_TOOLS` comes from the Step 1 preamble — it may be the `~/.local/bin` symlink, hence
`readlink -f` before `dirname`; the converter lives at `gad-core/bin/nosso/fh-render.py`.) The converter is stdlib-only and idempotent — safe
to re-run after any edit to the `.md`.
