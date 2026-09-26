---
phase: 27
intent_review: done
revisores_efetivos: [codex, agy]
codex_model_evidencia: "model: gpt-5.6-sol (banner do Codex, c1/runs/20260925T133612-2d0bd5/espelho-codex.json)"
agy_model_evidencia: "Propagating selected model override to backend: label=\"Gemini 3.7 Flash (High)\" (c1/runs/20260925T133612-2d0bd5/agy.log)"
ciclos: 2
motivo_encerramento: "ciclo 2: nenhum achado novo confirmado — convergiu"
achados_confirmados: 3
achados_descartados: 0
achados_dispensados: 3
pausas_de_negocio: 0
transparencia:
  - "ciclo 0: 7 sinos do discuss triados sem correção; c0-01..03 levados aos consultores e, no fecho, registrados como descartados no c0 com destino (c0-01 → c1-02; c0-02/c0-03 → dívida plan-phase); releitura c0 ok"
  - "c1-07 veio da releitura c1 (omissão SPEC×CONTEXT sobre revert_clean) e foi corrigido na rodada c1b; releitura c1b ok"
  - "D-NN-DESATUALIZADA D-18/D-23 (informativas do confere-reconciliacao) conferidas pela releitura c1b: não procedem"
  - "c1-02 abriu exceção na D-22 (pyproject só na config do hook, se a auditoria do AC-13 provar que o hook não compila no Windows) — tradeoff de implementação, sem mudar AC"
---

# Phase 27 — Revisão de intenção (consultoria cross-AI)

`fase_sem_req` — o ROADMAP da Phase 27 chegou sem REQ-ID (`issues: phase_without_req_id` do setup); o SPEC registrou WIN-v3x-01 no REQUIREMENTS.

## Ciclo 0

| id | sino (origem discuss) | disposição |
|----|-----------------------|------------|
| c0-01 | risco_nao_medido: glob do hook Cython nunca rodou no Windows | descartado no c0 (sem correção no c0; a consultoria o tratou como c1-02, corrigido) |
| c0-02 | risco_nao_medido: py.exe em C:\Windows no runner (filtro de PATH do AC-02) | descartado no c0 (dívida c0-02 → plan-phase) |
| c0-03 | reversibilidade_nao_marcada: D-11 caminho/formato da config vira contrato com a máquina do cliente | descartado no c0 (dívida c0-03 → plan-phase) |
| c0-04 | dedup_aplicada D-17 | descartado (informativo) |
| c0-05 | gate_cobertura_informativo (sem PLAN.md) | descartado (informativo) |
| c0-06 | ruido_shell do próprio filho | descartado (informativo) |
| c0-07 | pre_spec ok n=10 | descartado (informativo) |

## Novos confirmados por ciclo

- Ciclo 1: 3 confirmados (B-viabilidade: c1-01, c1-02, c1-03) + 1 da releitura (c1-07, omissão documental) · 3 dispensados (D-documental: c1-04, c1-05, c1-06).
- Ciclo 2: 0 (as duas lanes: "nenhum achado novo"; 6 respostas dirigidas `não`, todas `supported_no`).

## Tabela de achados

| id | alegação | veredito | destino | ação tomada | proposicao |
|----|----------|----------|---------|-------------|------------|
| c1-01 | ship por delta não publica pyproject.toml/uv.lock/.gitattributes sem diff; merge 3-way contra o pyproject antigo do espelho tende a conflito (clean-room/ship.py:411-415, :441-459) | confirmado | 1 — correção factual | D-19 passa a exigir que os caminhos extras cheguem ao espelho sem diff, com o estado do commit de trabalho anonimizado, nunca merge com a versão antiga (commit f2f67b42) | {artefato: CONTEXT, ancora: D-19, span_linhas: [125, 125], texto: "senão o ship falha. Ver 27-SPEC.md R6 · AC-16, AC-17. Falha visível: arquivo publicado que o gate não leu,", origem_texto: de_artefato_pos_ciclo} |
| c1-02 | D-16 prevê conserto do hook no pyproject; D-22 proíbe mudar o pyproject | confirmado | 3 — tradeoff de implementação | D-22 ganha exceção única restrita à configuração do hook, com build Docker e `uv export --no-dev` idênticos (AC-19) | {artefato: CONTEXT, ancora: D-22, span_linhas: [145, 145], texto: "Falha visível: qualquer linha nova em [project].dependencies, versão do projeto alterada, ou lock com conjunto de produção diferente.", origem_texto: de_artefato_pos_ciclo} |
| c1-03 | revert_clean (clean-room/ship.py:541) limpa só `src tests`, fora da re-ancoragem da D-23 | confirmado | 1 — correção factual | D-23 inclui a limpeza de revert_clean na re-ancoragem | {artefato: CONTEXT, ancora: D-23, span_linhas: [152, 152], texto: "usos de MIRROR_DIRS em clean-room/ship.py (:61, :226, :271, :411, :552) — re-ancorar para a lista ampliada;", origem_texto: de_artefato_pos_ciclo} |
| c1-07 | (releitura c1) a tabela §Regression Surface do SPEC não tinha a linha de ship.py:541 que a D-23 passou a citar | confirmado | 1 — correção factual | linha nova no SPEC §Regression Surface; D-23 options e citação da D-19 alinhados (rodada c1b) | {artefato: SPEC, ancora: "Regression Surface", span_linhas: [223, 223], texto: "| clean-room/test_gate.py, clean-room/test_verify_pacote.py — testes da ferramenta de ship |", origem_texto: de_artefato_pos_ciclo} |
| c1-04 | comentários/docstrings dizem que o espelho só carrega src/ e tests/ (clean-room/ship.py:60, tests/deploy/test_bat_commands.py:23-25, tests/deploy/test_build_pacote.py:21-23, tests/golden/test_baseline_atribuicao_243.py:17-19) | confirmado_irrelevante | dispensa — code-review | ver Dívidas | — |
| c1-05 | CONTEXT trava mecanismos internos (D-11, D-15, D-18, D-20, D-21) já medidos por AC | confirmado_irrelevante | dispensa — plan-phase | ver Dívidas | — |
| c1-06 | AC-18 não nomeia as 3 abas (vivem em ORDEM_ABAS, src/report/estilos.py) | confirmado_irrelevante | dispensa — plan-phase | ver Dívidas | — |

Respostas dirigidas c1: codex 5 `sim` + 1 `não` → cobertas pelos achados estruturais (uncertain/supported_no); agy 6 `não` → 5 `unsupported_no` (contraditas por c1-01/02/03/04/06), 1 `supported_no` (Q4). c2: 6 `não`, todas `supported_no`.

Reconciliação mecânica (`confere-reconciliacao.sh --ordem`): `resumo: ok=7 INVERSAO=0 CONFIRMADO-NAO-APLICADO=0 APLICADO-SEM-VEREDITO=0 VEREDITO-ILEGIVEL=0 fora-do-escopo=0 dispensados=3 dispensados_aplicados=0 confirmados_fora_de_escopo=0` · `reconciliacao: ok` · `ordem: ok`.

## Dívidas registradas

| id | alegação | evidência | dono | destino |
|----|----------|-----------|------|---------|
| c1-04 | docstrings/comentários afirmam que o espelho carrega só src/ e tests/; ficam falsos com a D-19 | clean-room/ship.py:60; tests/deploy/test_bat_commands.py:23-25; tests/deploy/test_build_pacote.py:21-23 | executor da publicação | code-review |
| c1-05 | decisões do CONTEXT fixam mecanismo interno onde o AC já mede o comportamento (vinculo_goal: nenhum) | 27-CONTEXT.md D-11, D-15, D-18, D-20, D-21 | planner | plan-phase |
| c1-06 | AC-18 não enumera as 3 abas; o digest itera ORDEM_ABAS (vinculo_goal: nenhum) | 27-SPEC.md AC-18; src/report/estilos.py ORDEM_ABAS | planner | plan-phase |
| c0-02 | runner Windows pode ter py.exe em C:\Windows; o filtro de PATH do AC-02 tem de tirá-lo mantendo System32 (origem: sino do discuss) | 27-CONTEXT.md D-20 (Implementation Notes) | planner | plan-phase |
| c0-03 | D-11 (caminho e formato da config em %APPDATA%) vira contrato com a máquina do cliente após a 1ª entrega; mudar depois quebra o AC-04 (origem: sino do discuss) | 27-CONTEXT.md D-11 | planner | plan-phase |

## Perguntas pendentes

nenhuma
