# Fase 99 — PRÉ-SPEC (fixture sintética, sem PII)

## 5. Recomendação → DECISÃO DO DONO

O grão do DRE fica no "responsável-mês" (Opção A).

<!-- gad:decisoes:begin v1 -->
[
  {
    "id": "PS-01",
    "kind": "decisao_dono",
    "area": "Grão do DRE: agregação",
    "req_anchor": "R2",
    "decisao": "A agregação do DRE fica no grão responsável-mês (Opção A).",
    "opcoes_descartadas": ["Opção B — linha por aluno", "Opção C — híbrida"],
    "evidencia": "src/dre/motor.py:121-127",
    "reversibilidade": "costly",
    "reversibilidade_justificativa": "migrar o grão depois exige reprocessar 14 meses",
    "ressalva": "o relatório passa a saber mais que o razão",
    "span": "§5 Recomendação"
  },
  {
    "id": "PS-02",
    "kind": "fato_medido",
    "area": "Sobreposição de janelas",
    "req_anchor": "none",
    "decisao": "As janelas de responsável nunca se sobrepõem no mesmo mês (9/9 medidos).",
    "opcoes_descartadas": [],
    "evidencia": "scripts/mede-janelas.py → saída em 99-PRE-SPEC.md §3.5",
    "reversibilidade": "reversible",
    "span": "§3.5"
  },
  {
    "id": "PS-03",
    "kind": "decisao_dono",
    "area": "Unicode, dois-pontos e aspas: ~50 % \"cabem\" — teste #1",
    "req_anchor": "SC-1",
    "decisao": "Rótulo canônico: \"Resultado (DRE) — receita/desconto\"; separador `:` mantido.",
    "opcoes_descartadas": ["rótulo curto"],
    "evidencia": "none",
    "reversibilidade": "reversible",
    "span": "§6.1 Travas"
  }
]
<!-- gad:decisoes:end -->

## Anexo A — Critérios candidatos de "pronto"

1. **Δ fecha em zero** no grão responsável-mês.
2. **Zero regressão** nas 9 janelas medidas.
3. Harness por responsável contra o razão.

## Anexo B

Nada aqui é item do Anexo A.
