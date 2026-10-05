# Documento único de intenção — moldura do `NN-CONTEXT.md` (fork, plano 06-13)

> **Documentação, não molde de execução.** Nada lê este arquivo em tempo de execução: quem
> escreve o documento é `bin/nosso/context-render.py`, a partir do depósito da fase
> (`<phase_dir>/<NN>-DISCUSS-CHECKPOINT.json`, gravado só por `bin/nosso/checkpoint-write.py`).
> O modelo nunca escreve a moldura (título, marca, headings, tags, marcas do bloco da
> máquina); ele só entrega o TEXTO de cada seção ao depósito, por arquivo
> (`checkpoint-write.py set-secao <ckpt> --secao <slug> --file F`). Mudou a moldura?
> Mude o `context-render.py` e o `confere-documento.py` juntos, e depois este texto.

## A máquina de estados da gravação (D-12)

1. Cada resposta do dono → `checkpoint-write.py add-decision --origin owner` na hora (só a
   origem `owner` é aceita; outra → exit 2). Cada seção redigida → `set-secao`. Escrita
   atômica do depósito (temporário + `os.replace`); toda mudança derruba uma aprovação anterior.
2. `context-render.py <ckpt> --out $T/rascunho/<NN>-CONTEXT.md` → rascunho (função pura do
   depósito: o mesmo depósito rende o mesmo documento, byte a byte) e uma linha
   `{"out", "bytes", "sha256", "vazias"}`.
3. `discuss-render-guard.sh` confere o rascunho (`confere-documento.py`, `confere-pii.sh`) antes
   de ele ir ao dono.
4. «ok» explícito do dono → `checkpoint-write.py aprovar <ckpt> --sha256 <sha do rascunho>`.
5. `context-render.py --promover <rascunho> <phase_dir>/<NN>-CONTEXT.md --sha256 <sha> [--ckpt <ckpt>]`
   → só promove se o sha do rascunho, o `--sha256` e o `aprovado_sha256` do depósito forem o
   mesmo; copia para um temporário irmão do destino e troca por `os.replace`. Um kill antes da
   troca deixa o destino ausente (ou o anterior inteiro), nunca pela metade.

O render nunca cria `NN-SPEC.md` nem `NN-PRE-SPEC.md` (AC-10).

## Slugs do depósito → seções

| Seção (heading, nesta ordem) | Slug do depósito | Moldura em volta do texto |
|------------------------------|------------------|---------------------------|
| `## Goal` | `goal` | — |
| `## Situação de hoje` | `situacao` | — |
| `## Decisões do dono` | (decisões do depósito) | `<decisions>` … `</decisions>` |
| `## Requisitos` | `requisitos` | — |
| `## Critérios de aceite` | `criterios` | — |
| `## Limites e restrições` | `limites` | — |
| `## Prohibitions (Proibições)` | `proibicoes` | — |
| `## Edge Coverage (Bordas)` | `bordas` | — |
| `## Regression Surface` | `regression` | — |
| `## Artefatos novos` | `artefatos` | — |
| `## Limitações declaradas` | `limitacoes` | — |
| `## A critério do planner (Claude's Discretion)` | `discricao` | — |
| `## Pendências e ideias adiadas` | `pendencias` | `<deferred>` … `</deferred>` |
| `## Referências e mapa do código` | `referencias`, `codigo` | `<canonical_refs>` … `</canonical_refs>` e `<code_context>` … `</code_context>` |
| `## Bloco da máquina` | `reqs_json`, `scope_json`, `acs_json` | marcas `<!-- gsd:reqs:begin -->` … `end`, idem `scope` e `acs` |

O texto de cada seção entra como está; só aberturas/fechamentos das tags da moldura são
neutralizados (`</decisions>` → `&lt;/decisions>`). Os três `*_json` são validados como JSON
(chave duplicada recusada) no `set-secao` e copiados verbatim.

## O bloco `<decisions>`

Uma linha por decisão do dono, em ordem numérica do id — `- **D-NN:** <resposta>` —, com a
prosa da decisão (se houver) indentada embaixo e neutralizada: linha começando por `#` →
`\#`; linha começando por `- **`/`* **` → `·`; fence removido; tags da moldura escapadas.
Sem tag `[auto]`, `[pre-spec:…]`, `informational`: o documento só traz decisões do dono, e o
`decisions.cjs` as lê todas como rastreáveis. Sem nenhuma decisão, o bloco traz a frase
«Nenhuma decisão do dono registrada nesta fase.» (sem token `D-`, que o parser leria como
tentativa de id).

## Esqueleto renderizado

```markdown
# Especificação da fase [NN] — [nome da fase]
<!-- gad:documento-unico: v1 -->

## Goal

[goal]

## Situação de hoje

[situacao]

## Decisões do dono

<decisions>
- **D-01:** [resposta do dono]
- **D-02:** [resposta do dono]
  [prosa da decisão, neutralizada]
</decisions>

## Requisitos

[requisitos]

## Critérios de aceite

[criterios]

## Limites e restrições

[limites]

## Prohibitions (Proibições)

[proibicoes]

## Edge Coverage (Bordas)

[bordas]

## Regression Surface

[regression]

## Artefatos novos

[artefatos]

## Limitações declaradas

[limitacoes]

## A critério do planner (Claude's Discretion)

[discricao]

## Pendências e ideias adiadas

<deferred>
[pendencias]
</deferred>

## Referências e mapa do código

<canonical_refs>
[referencias]
</canonical_refs>

<code_context>
[codigo]
</code_context>

## Bloco da máquina

<!-- gsd:reqs:begin -->
[reqs_json]
<!-- gsd:reqs:end -->

<!-- gsd:scope:begin -->
[scope_json]
<!-- gsd:scope:end -->

<!-- gsd:acs:begin -->
[acs_json]
<!-- gsd:acs:end -->
```

Um exemplo completo, que passa no `confere-documento.py`, é
`testes/intencao/documento-unico/ok-CONTEXT.md`; o depósito que o rende byte a byte é
`fontes/fork/tests/fixtures/render/documento-unico.ckpt.json`.

As seções descartadas pelo ADR 0001 não existem nesta moldura: `<domain>`, `<spec_lock>`,
`<specifics>`, «Implementation Notes», «Interview Log», «Ambiguity Report», «Critérios
exigidos», «Cobertura do Goal», «Consistência interna».
