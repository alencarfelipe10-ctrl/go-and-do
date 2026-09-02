# Fase 99 — SPEC com origem nos ACs (fixture sintética do P12)

## Goal

Corrigir a atribuição de receita mantendo o grão responsável-mês. [pre-spec:PS-01, R2]

## Critérios de aceite

- [ ] AC-01 — o DRE agrega por responsável-mês e o Δ fecha em zero. [origem: PS-01, R2]
- [ ] AC-02 — MUST NOT: nenhuma linha do razão é rateada por aluno. [origem: PS-99]
- [ ] AC-03 — o rótulo canônico aparece na aba Balanço. [origem: SC-1, DESC-01]
- [ ] AC-04 — o Δ de desconto também fecha em zero. [origem: AC-01]
- [ ] AC-05 — a janela de expediente vale só para compor texto.
- [ ] AC-06 — [origem: PS-01]
- [ ] AC-07 — o mês fechado é 2026-05. [origem: AC-07]
- [ ] AC-08 — a Urca fica byte-idêntica. [origem: AC-42, capítulo 3]

## Limitações declaradas

- PS-01: o relatório passa a saber mais que o razão — aceito nesta fase.
