# Fase 99 — SPEC com ACs por ponteiro (fixture sintética do S4)

## Goal

Corrigir a atribuição de receita mantendo o grão responsável-mês.

## Critérios de aceite

- AC-01 — ver §3.2
- AC-02 — ver 99-PRE-SPEC.md §3.2
- AC-03 — → §3.2
- AC-04 — conforme PRE-SPEC §2
- AC-05 — MUST NOT: → 99-PRE-SPEC.md §6.1
- AC-06 — o DRE agrega por responsável-mês e o Δ fecha em zero, ver 99-PRE-SPEC.md §5.
- AC-07 — MUST NOT: nenhuma linha do razão é rateada por aluno (§4).
- AC-08 — a janela de expediente §4 vale só para compor texto, nunca como gate.

## Limitações declaradas

- PS-01: o relatório passa a saber mais que o razão — aceito nesta fase.
