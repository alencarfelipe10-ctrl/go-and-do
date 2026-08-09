<!-- ============================================================ -->
<!-- workflow-ui.md — conteúdo condicional da rota --ui (T.3).    -->
<!-- A camada 0 lê UMA vez por rodada, quando a fase tem --ui     -->
<!-- (ou UI-SPEC existente): cobre a Etapa 1.5-UI e o gate 4.2.   -->
<!-- Sem --ui, este arquivo nunca entra na janela.                -->
<!-- ============================================================ -->

# Rota `--ui` — contratos de design e UI review

## Etapa 1.5 — paradas herdadas do `gsd-ui-phase`

O host `gad-contratos` intercepta e devolve como `needs_decision` mastigado (triagem
da Sub-rotina I decide se chega ao dono):

- **UI-SPEC BLOCKED** — o `gsd-ui-researcher` não consegue montar o contrato (falta
  decisão crítica de design que o CONTEXT.md não cobre, ou registry de terceiros sem
  vetar). Para.
- **Revision stall** — o `gsd-ui-checker` reprovou 2× sem convergir → "force approve /
  edit / abandon". Parada saudável: melhor um contrato revisado do que design débito.

## Gate 4.2 — UI review (via subagente)

- `pre-despacho.sh 4-ui-review` resolve flag/config/retomada (`pular_flag` sem `--ui`
  e sem UI-SPEC) → `ok`? Despache pela **Sub-rotina H** com `prompts/ui-review.md`: o
  subagente sobe o server via `dev-server.sh up` (receita persistida ou heurística —
  `workflow-dev-server.md`), roda `gsd-ui-review N`, derruba via `down`.
- Tela atrás de login → credencial pela **regra de nascença** da Sub-rotina H (via
  sancionada preparada pela camada 0; nunca login improvisado; sem via sancionada =
  code-only com ressalva declarada).
- Ao voltar: `confere-etapa.sh 4-ui-review` extrai `overall`/`pilar1`/`pilar2`
  (Overall não parseável = **fail-up** → leia o relatório). Sempre segue; pilar 1–2
  com nota 1–2 ou flag de Registry Safety → 🔔 forte no banner.

## UAT com UI (lembretes — a craft mora no `uat-playbook.md`)

- A janela do subagente de UAT é dona do server (`dev-server.sh up|down`, seção
  lifecycle do playbook); o despacho leva a URL, nunca o processo.
- `--vault <profile>` → o profile desce no despacho para os fluxos com login.
