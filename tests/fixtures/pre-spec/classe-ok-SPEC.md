# Fase 99 — SPEC com classe (fixture sintética do plano 1, caso limpo)
<!-- spec-origem: v1 -->
<!-- spec-classe: v1 -->

## Goal

O DRE agrega por responsável-mês e o Δ fecha em zero nas 9 janelas.

## Critérios de aceite

- [ ] AC-01 — o Δ do DRE fecha em zero no grão responsável-mês. [exigido: é o efeito medido do Goal] [origem: AA-1, Goal]
- [ ] AC-02 — as 9 janelas continuam sem sobreposição. [exigido: não-regressão medida no PS-02] [diverge: AA-2 — a régua é por janela, não por mês] [origem: AA-2, PS-02]
- [ ] AC-03 — MUST NOT: nenhuma linha do razão é rateada por aluno. [desejável] [origem: PS-01]
- [ ] AC-04 — o rótulo canônico aparece na aba Balanço. [desejável] [origem: AC-01]

## Cobertura do Goal

| Efeito medido do Goal | ACs exigidos que o cobrem | Veredito |
|---|---|---|
| Δ a zero | AC-01 | coberto |
| 9 janelas | AC-02 | coberto |

**Efeitos sem cobertura:** nenhum

## Limitações declaradas

- PS-01: o relatório passa a saber mais que o razão — aceito nesta fase.

<!-- gsd:acs:begin -->
[
  { "id": "AC-01", "classe": "exigido", "motivo": "é o efeito medido do Goal", "origem": ["AA-1", "Goal"], "diverge": null },
  { "id": "AC-02", "classe": "exigido", "motivo": "não-regressão medida no PS-02", "origem": ["AA-2", "PS-02"], "diverge": { "item": "AA-2", "porque": "a régua é por janela, não por mês" } },
  { "id": "AC-03", "classe": "desejavel", "motivo": null, "origem": ["PS-01"], "diverge": null },
  { "id": "AC-04", "classe": "desejavel", "motivo": null, "origem": ["AC-01"], "diverge": null }
]
<!-- gsd:acs:end -->
