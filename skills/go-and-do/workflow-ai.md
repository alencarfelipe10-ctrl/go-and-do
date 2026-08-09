<!-- ============================================================ -->
<!-- workflow-ai.md — conteúdo condicional da rota --ai (T.3).    -->
<!-- A camada 0 lê UMA vez por rodada, quando a fase tem --ai     -->
<!-- (ou AI-SPEC existente): cobre a Etapa 1.5-IA e o gate 4.3.   -->
<!-- Sem --ai, este arquivo nunca entra na janela.                -->
<!-- ============================================================ -->

# Rota `--ai` — contrato de IA e eval review

## Etapa 1.5 — paradas herdadas do `gsd-ai-integration-phase`

O host `gad-contratos` intercepta e devolve como `needs_decision` mastigado:

- **Entrevista do `gsd-framework-selector`** — quando o CONTEXT.md não cobre as
  decisões de IA (tipo de sistema, provider, linguagem, requisito), o selector faz
  uma entrevista de ≤6 perguntas. Decisão de arquitetura legítima: **deixe chegar ao
  dono** (escolher framework de IA não se automatiza às cegas — a 1ª opção pode ser a
  errada pro caso; gate duro por escopo/intenção na triagem da Sub-rotina I).
- **AI validation fail** — o AI-SPEC.md saiu incompleto e o comando pergunta re-run /
  continuar.

## Gate 4.3 — Eval review (via subagente)

- `pre-despacho.sh 4-eval-review` resolve flag/config/retomada (`pular_flag` sem
  `--ai`; **`sino_esquecimento`** quando há AI-SPEC sem `--ai` — provável flag
  esquecida, 4.F: pergunte antes de pular) → `ok`? Despache pela **Sub-rotina H** com
  `prompts/eval-review.md` (hospeda `gsd-eval-review N` — State A com AI-SPEC, State B
  sem, com aviso).
- Ao voltar: `confere-etapa.sh 4-eval-review` extrai o `verdict` ENUM canônico —
  **verbatim, nunca recompute**. Sempre segue; abaixo de PRODUCTION READY → 🔔.
