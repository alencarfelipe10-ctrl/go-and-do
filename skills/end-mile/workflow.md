<!-- ============================================================ -->
<!-- workflow.md — o miolo executável da skill end-mile.          -->
<!-- Embutido no SKILL.md via @ (carregado na ativação).          -->
<!-- Instruções imperativas para o orquestrador. Não é doc.       -->
<!-- ============================================================ -->

# end-mile — execução

<role>
You are the orchestrator. You close out one GSD milestone by invoking native GSD commands
in order and chaining them, gating the chain on the audit verdict. You do not reimplement
GSD logic. This skill is the milestone-level bookend to `/close-phase`: once every phase of
the milestone is shipped, it runs the three native finalization commands
(`audit-milestone` → `milestone-summary` → `complete-milestone`).

Toda a sua saída ao usuário — banners, anúncios de status, linhas de "🔔" — é em
**pt-BR**. (As tags estruturais e o papel aqui estão em inglês por convenção; a operação e
tudo que o usuário lê, em pt-BR.)
</role>

<operating_rules>
Operating rules — read once, apply throughout:

- Invoke GSD commands via the `Skill` tool (`gsd-audit-milestone`, `gsd-milestone-summary`,
  `gsd-complete-milestone` are skills). Wait for one to finish before starting the next —
  you control the chaining.
- Don't read long artifacts into your window. You read exactly one field — the audit
  `status:` — by `grep` (Sub-rotina G). The native commands you invoke read their own
  artifacts; you do not re-read them.
- Honor every stop point — never skip one to keep going: not a GSD project (Etapa 0); an
  audit verdict that is not `passed` (Sub-rotina G); an unresolvable version (Etapa 1); and
  any readiness/environment gate that `complete-milestone` itself raises (Etapa 3). When you
  stop, say why in one line **and** name the way forward (escape hatch) — never leave the
  user trapped.
- **The audit verdict is the gate.** The only verdict that lets the chain reach
  `complete-milestone` is `passed`. `gaps_found` and `tech_debt` **both stop** (the user
  chose to be stricter than native `complete-milestone`, which accepts `tech_debt`). Never
  invoke `complete-milestone` on a non-`passed` audit. See Sub-rotina G.
- Everything is resumable. Re-running `/end-mile` must never redo finished work: reuse an
  existing audit with a terminal verdict (unless `--fresh`), skip the summary if its report
  already exists, and detect an already-archived milestone.
- No context gate here. Like `/close-phase`, this is a short native-command pipeline — too
  short to warrant a token brake. Resumability covers an interruption.
- No git tidy-commit. Unlike `/close-phase` (which commits docs because ship's preflight
  demands a clean tree), `complete-milestone` does not require a clean working tree — it
  `git add`s specific paths and makes its own safety commit, and sweeps `STATE.md` changes
  from audit/summary into that commit. Leaving the audit/summary report files uncommitted is
  harmless; do not add git surface this skill doesn't need.
- Paths: the skill lives at `$HOME/.claude/skills/end-mile/`. The audit report is
  `.planning/v{version}-MILESTONE-AUDIT.md`; the summary report is
  `.planning/reports/MILESTONE_SUMMARY-v{version}.md`; archived milestones live in
  `.planning/milestones/v{version}-ROADMAP.md`.
</operating_rules>

---

<master_checklist>

## Roteiro-mestre (todas as ações, na ordem)

Legenda: ⏭️ retomada (pula se já feito) · ⏸️ pode parar

**Etapa 0 — Preparação**
1. Lê os argumentos: `[version]` (opcional; tira o `v` da frente) e `--fresh`.
2. ⏸️ Portão de entrada: é projeto GSD? (existe `.planning/`?). Senão → para.
3. ⏭️ Retomada por arquivamento: se `version` foi dado e `.planning/milestones/v{version}-ROADMAP.md` já existe → o milestone já foi arquivado; reporta e para.
4. Banner: "Finalizando o milestone {version|atual}: audit → summary → complete."

**Etapa 1 — Auditoria + gate**
5. Localiza o audit (Sub-rotina G, passo 1).
6. ⏭️ Audit já existe e **não** veio `--fresh` → reusa (pula o re-run). Senão → `Skill gsd-audit-milestone` (passa `version` se houver), depois re-localiza o arquivo mais novo.
7. Resolve a `VER` definitiva pelo nome do arquivo de audit (Sub-rotina G, passo 2). ⏸️ Sem audit / `VER` vazia → para (não dá pra gatear nem passar versão adiante).
8. Lê o `ASTATUS` e roteia (Sub-rotina G, passos 3–4): `passed` → segue; `gaps_found`/`tech_debt`/outro → ⏸️ **para com escape hatch**.

**Etapa 2 — Sumário executivo**
9. ⏭️ Existe `.planning/reports/MILESTONE_SUMMARY-v{VER}.md` → pula a geração.
10. `Skill gsd-milestone-summary` → `VER`.

**Etapa 3 — Completar e arquivar**
11. `Skill gsd-complete-milestone` → `VER`. ⏸️ Cede aos gates internos dele (confirmação de readiness, merge de PRs, push da tag) — **não** os duplica. Se ele parar num gate, respeita e reporta.

**Etapa 4 — Encerramento**
12. Banner final: milestone `vVER` arquivado + tag criada. Próximo passo é **manual**: `/gsd-new-milestone "vX.Y Nome"`.

</master_checklist>

---

<subroutines>

<subroutine name="G — gate do audit (Etapa 1)">

## Sub-rotina G — gate do audit (Etapa 1)

Este é o coração da skill: rodar/reaproveitar o audit e decidir se a cadeia continua.
Leia **só** o campo `status:` por `grep` — nunca leia o relatório inteiro pra dentro da sua
janela.

**1. Localiza o arquivo de audit.**
```bash
# Com versão no argumento: caminho canônico, com fallback defensivo pro typo
# 'v{version}-v{version}-MILESTONE-AUDIT.md' que existe num workflow nativo.
if [ -n "$VER" ]; then
  AUDIT_FILE=".planning/v${VER}-MILESTONE-AUDIT.md"
  [ -f "$AUDIT_FILE" ] || AUDIT_FILE=$(ls -t .planning/*v${VER}*-MILESTONE-AUDIT.md 2>/dev/null | head -1)
else
  # Sem versão: pega o relatório de audit mais recente
  AUDIT_FILE=$(ls -t .planning/*-MILESTONE-AUDIT.md 2>/dev/null | head -1)
fi
```
- Se for rodar o audit (não há arquivo, ou veio `--fresh`): invoque `Skill gsd-audit-milestone`
  (passe a versão se houver). **Depois** rode de novo o bloco acima pra re-localizar o
  arquivo recém-escrito (`ls -t … | head -1`).

**2. Resolve a `VER` definitiva pelo nome do arquivo.** (Quando o usuário não passou versão,
o nome do arquivo é a fonte da verdade.)
```bash
if [ -z "$VER" ] && [ -n "$AUDIT_FILE" ]; then
  VER=$(basename "$AUDIT_FILE" | sed -E 's/^v//; s/-MILESTONE-AUDIT\.md$//; s/^v//')
fi
```
- ⏸️ `AUDIT_FILE` vazio **ou** `VER` vazia → **para**: "não consegui localizar/identificar o
  audit do milestone. Rode `/gsd-audit-milestone <versão>` e depois `/end-mile <versão>`."

**3. Lê o veredito.**
```bash
# Âncora ^status: é OBRIGATÓRIA e -m1 pega a 1ª ocorrência (a do frontmatter).
# O corpo do audit tem 'status:' e 'verification_status:' INDENTADOS dentro dos
# objetos por-requisito; sem a âncora ^ (ou afrouxando pra 'status:') você leria
# o status de um requisito, não o veredito do milestone. NÃO afrouxe isto.
ASTATUS=$(grep -m1 -E '^status:' "$AUDIT_FILE" 2>/dev/null | sed -E 's/^status:[[:space:]]*"?([a-z_]+)"?.*/\1/')
```

**4. Roteia pelo `ASTATUS`:**
- **`passed`** → ✅ segue pra Etapa 2. (Anuncia: "Audit do milestone vVER: passed — seguindo pro sumário.")
- **`gaps_found`** → ⏸️ **para**:
  > "🔔 Audit do milestone vVER voltou **`gaps_found`** — há blockers críticos (requisitos
  > obrigatórios não entregues). A `/end-mile` não arquiva com gaps. O próprio relatório
  > (`.planning/vVER-MILESTONE-AUDIT.md`) lista os gaps. Caminhos:
  > • **Fechar os gaps** — pra cada gap: `/gsd-phase --insert <N>` → `/gsd-discuss-phase <N>` →
  >   `/gsd-plan-phase <N>` → `/gsd-execute-phase <N>` → `/close-phase <N>`, depois rode
  >   `/end-mile vVER` de novo.
  > • **Aceitar mesmo assim** (assume os gaps como débito) — rode `/gsd-complete-milestone vVER`
  >   direto; ele oferece o override de aceitação."
- **`tech_debt`** → ⏸️ **para**:
  > "🔔 Audit do milestone vVER voltou **`tech_debt`** — sem blockers, mas há débito acumulado
  > que merece revisão. Por configuração, a `/end-mile` não auto-arquiva com débito. Caminhos:
  > • **Resolver o débito** que o relatório aponta e rodar `/end-mile vVER` de novo.
  > • **Aceitar e arquivar assim** — rode `/gsd-complete-milestone vVER` direto (o nativo aceita
  >   `tech_debt`)."
- **vazio / qualquer outro valor** → ⏸️ **para** e mostre o `ASTATUS` lido: "veredito do audit
  inesperado (`{ASTATUS}`) — confira `.planning/vVER-MILESTONE-AUDIT.md` à mão antes de arquivar."

> **Por que o gate é a cola.** Nem `audit-milestone` nem `complete-milestone` impedem
> sozinhos um arquivamento indevido do jeito que você quer: o `complete` nativo *aceita*
> `tech_debt`. A `/end-mile` lê o veredito uma vez e curto-circuita, poupando uma tentativa de
> `complete` que você teria que abortar — e sempre apontando a saída, pra rigidez não virar beco.

</subroutine>

</subroutines>

---

<final_banner>

## Banner final (Etapa 4)

Depois que o `complete-milestone` terminar (milestone arquivado + tag git criada), feche em pt-BR:

```
🔔 Milestone vVER finalizado
   • Audit: passed
   • Sumário: .planning/reports/MILESTONE_SUMMARY-vVER.md
   • Arquivado: .planning/milestones/vVER-ROADMAP.md (+ REQUIREMENTS)
   • Tag git: vVER

Próximo passo (manual): /gsd-new-milestone "vX.Y Nome do próximo ciclo"
```

Se o `complete-milestone` parou num gate próprio (readiness, merge de PR, push de tag),
**não** anuncie sucesso — reporte onde ele parou e o que falta, em uma linha.

</final_banner>
