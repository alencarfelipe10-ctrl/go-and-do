# Fase 99 — SPEC (fixture sintética)

## Goal

Corrigir a atribuição de receita mantendo o grão responsável-mês, com 9/9 janelas sem sobreposição, em 14 meses. [pre-spec:PS-01, R2]

## Requisitos

- R2 — a agregação do DRE fica no grão responsável-mês (Opção A). [pre-spec:PS-01, R2]
- SC-1 — o rótulo canônico é "Resultado (DRE) — receita/desconto"; separador `:` mantido. [pre-spec:PS-03, SC-1]
- R3 — as janelas de responsável não se sobrepõem no mesmo mês. [medido:PS-02]

## Critérios de aceite

- AC-01 — o DRE agrega por responsável-mês e o Δ fecha em zero.
- AC-02 — MUST NOT: nenhuma linha do razão é rateada por aluno.

## Limitações declaradas

- PS-01: o relatório passa a saber mais que o razão — aceito nesta fase.
