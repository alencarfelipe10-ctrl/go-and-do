# Roadmap — fixture sintética da bancada do setup-intencao.sh (R6)

Sem PII: fases, requisitos e números são inventados.

## Milestone v9.9

### Phase 24: Fase com número-prefixo (armadilha do lookahead)

**Goal:** Entrada-armadilha do lookahead: a busca por `Phase 24` não pode casar com a entrada da `Phase 24.3` logo abaixo.
**Requirements**: BANC-02

### Phase 24.3: Fase com ponto no número

**Goal:** Cada contrato é atribuído ao seu próprio responsável, não ao do aluno.
**Requirements**: BANC-01

### Phase 99: Entrada saudável, com id de requisito existente

**Goal:** Corrigir a atribuição de receita mantendo o grão responsável-mês, sem tocar o
Balanço.
**Depends on:** Phase 24.3
**Requirements**: **BANC-01**, BANC-02 — criados na etapa de spec.

**Fora de escopo (herdado, não reabrir):** regra de cancelamento por tipo de linha
(CANC-02); critério da coluna "Contrato cancelado" (D-q90-01); débito D-q90-05; a trava
do AC-30 e o requisito FALTA-01 citado aqui **em prosa** — nada disto é citação de
requisito e nada disto pode acender um gate.

**Plans:** 0/0 plans executed

### Phase 98: Entrada sem REQ-ID nenhum

**Goal:** Entrada cuja linha de requisitos é um TBD — `phase_without_req_id`.
**Requirements**: TBD (derivar na spec)

### Phase 97: Entrada citando requisito que não existe

**Goal:** Entrada que cita um id ausente do REQUIREMENTS.md — `missing_requirement`.
**Requirements**: BANC-01, FALTA-01

### Phase 95: Goal quebrado em duas linhas + ids que NÃO são requisito

**Goal:** Primeira linha do Goal, que quebra no meio;
segunda linha com a outra promessa da fase.
**Requirements**: BANC-01, D-11, PRE-SPEC, D-q90-05

### Phase 96: Entrada sem linha de requisitos

**Goal:** Entrada sem a linha `**Requirements**` — também `phase_without_req_id`.
**Depends on:** Phase 99
