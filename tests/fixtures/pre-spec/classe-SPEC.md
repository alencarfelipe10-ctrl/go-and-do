# Fase 99 — SPEC com classe (fixture sintética do plano 1, um defeito por sino)
<!-- spec-origem: v1 -->
<!-- spec-classe: v1 -->

## Goal

O DRE agrega por responsável-mês e o Δ fecha em zero nas 9 janelas.

## Critérios de aceite

- [ ] AC-01 — o Δ do DRE fecha em zero no grão responsável-mês. [exigido: é o efeito medido do Goal] [origem: AA-1]
- [ ] AC-02 — as 9 janelas continuam sem sobreposição. [desejável] [origem: R2]
- [ ] AC-03 — o Δ de desconto também fecha em zero. [exigido: deriva do AC-01] [origem: AC-01]
- [ ] AC-04 — o rótulo canônico aparece na aba Balanço. [exigido] [origem: PS-01]
- [ ] AC-05 — MUST NOT: nenhuma linha do razão é rateada por aluno. [origem: PS-01]
- [ ] AC-06 — o harness confronta o razão por responsável. [exigido: harness é a prova] [diverge: AA-2] [origem: AA-2]
- [ ] AC-07 — a janela de expediente vale só para compor texto. [desejável] [origem: PS-03]
- [ ] AC-08 — a Urca fica byte-idêntica. [exigido: não-regressão] [origem: AA-9]
- [ ] AC-09 — o mês fechado é 2026-05. [desejável] [origem: Goal]
- [ ] AC-10 — o relatório lista as janelas. [desejável] [origem: R2]

## Cobertura do Goal

| Efeito medido do Goal | ACs exigidos que o cobrem | Veredito |
|---|---|---|
| Δ a zero | AC-01 | coberto |
| 9 janelas | — | DESCOBERTO |

**Efeitos sem cobertura:** 9 janelas sem sobreposição

## Limitações declaradas

- PS-01: o relatório passa a saber mais que o razão — aceito nesta fase.

<!-- gsd:acs:begin -->
[
  { "id": "AC-01", "classe": "exigido", "motivo": "é o efeito medido do Goal", "origem": ["AA-1"], "diverge": null },
  { "id": "AC-02", "classe": "desejavel", "motivo": null, "origem": ["R2"], "diverge": null },
  { "id": "AC-03", "classe": "exigido", "motivo": "deriva do AC-01", "origem": ["AC-01"], "diverge": null },
  { "id": "AC-04", "classe": "exigido", "motivo": null, "origem": ["PS-01"], "diverge": null },
  { "id": "AC-05", "classe": "desejavel", "motivo": null, "origem": ["PS-01"], "diverge": null },
  { "id": "AC-06", "classe": "exigido", "motivo": "harness é a prova", "origem": ["AA-2"], "diverge": { "item": "AA-2" } },
  { "id": "AC-07", "classe": "exigido", "motivo": "x", "origem": ["PS-03"], "diverge": null },
  { "id": "AC-08", "classe": "exigido", "motivo": "não-regressão", "origem": ["AA-9"], "diverge": null },
  { "id": "AC-09", "classe": "desejavel", "motivo": null, "origem": ["Goal"], "diverge": null },
  { "id": "AC-11", "classe": "desejavel", "motivo": null, "origem": ["R2"], "diverge": null }
]
<!-- gsd:acs:end -->
