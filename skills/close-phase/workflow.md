<!-- ============================================================ -->
<!-- workflow.md — o miolo executável da skill close-phase.       -->
<!-- Embutido no SKILL.md via @ (carregado na ativação).          -->
<!-- Instruções imperativas para o orquestrador. Não é doc.       -->
<!-- ============================================================ -->

# close-phase — execução

<role>
You are the orchestrator. You close one GSD phase by invoking native GSD commands in order
and chaining them. You do not reimplement GSD logic. This skill is the bookend to
`/go-and-do`: it runs the last two steps of a phase (`extract-learnings` → `ship`), after
the user's manual UAT.

Toda a sua saída ao usuário — banners, anúncios de status, linhas de "🔔" — é em
**pt-BR**. (As tags estruturais e o papel aqui estão em inglês por convenção; a operação e
tudo que o usuário lê, em pt-BR.)
</role>

<operating_rules>
Operating rules — read once, apply throughout:

- Invoke GSD commands via the `Skill` tool (`/gsd-extract-learnings`, `/gsd-ship` are
  skills). Wait for one to finish before starting the next — you control the chaining.
- Don't read long artifacts into your window. The skill reads status fields by `grep`
  (Sub-rotina V) and orchestrates by them; the native commands you invoke read their own
  artifacts, you do not re-read them.
- Honor every stop point — never skip one to keep going: not a GSD project / phase not
  found (0.3), an unclean UAT while verification is `human_needed` (0.3 / Sub-rotina V),
  `gaps_found` verification (Sub-rotina V), and any environment block ship raises (3.2).
  When you stop, say why in one line to the user.
- **Never promote verification without evidence.** The only path to promoting
  `human_needed` → `passed` is a clean UAT verdict from the native `phase uat-passed`
  predicate (only `pass`/`passed` count; markdown-aware, fail-closed). A real failure
  (pending/blocked/issue/failed/missing/partial) → no promotion → stop and send the user to
  `/gsd-verify-work`. **Skipped tests** (verification deferred, not failed) → **block and ask**:
  the user either resolves them via `/gsd-verify-work` or explicitly accepts shipping unverified
  behavior (recorded in the promotion evidence). See Sub-rotina V.
- Everything is resumable. Re-running `/close-phase N` must never redo finished work:
  skip extraction if `NN-LEARNINGS.md` exists, skip promotion if verification is already
  `passed`, skip PR creation if a PR for the branch already exists.
- No context gate here. Unlike `/go-and-do`, this is a 2-command pipeline — too short to
  warrant the 70% brake. Resumability covers an interruption.
- Paths: the skill lives at `$HOME/.claude/skills/close-phase/`. The phase directory
  (`phase_dir`) and padded phase number (`padded_phase`, e.g. `03` → the `NN` prefix of
  every artifact) come from `init.phase-op`.
</operating_rules>

---

<master_checklist>

## Roteiro-mestre (todas as ações, na ordem)

Legenda: ⏭️ retomada (pula se já feito) · ⏸️ pode parar

**Etapa 0 — Preparação**
1. Lê o argumento (número da fase). Sem número → ⏸️ para e pede.
2. Resolve o SDK e roda `init.phase-op N` → retrato da fase.
3. ⏸️ Portões de entrada: projeto GSD? fase no ROADMAP? **gate UAT/verificação** (Sub-rotina V).
4. Banner e libera.

**Etapa 1 — Aprendizados**
5. ⏭️ Existe `NN-LEARNINGS.md` → pula a extração.
6. `Skill gsd-extract-learnings` → `N`.

**Etapa 2 — Ponte de verificação + commit**
7. Promoção (Sub-rotina P): verificação era `human_needed` + UAT `CLEAN` (ou `SKIPPED_ONLY` aceito) → promove p/ `passed`. Já `passed` → nada.
8. Commit dos docs (Sub-rotina C): se `commit_docs` → commita `LEARNINGS` + `VERIFICATION` + `STATE`, pra árvore ficar limpa pro ship.

**Etapa 3 — Ship**
9. ⏭️ Retomada por PR: `gh pr list --head <branch>` → PR já existe → pula a criação, guarda nº/URL.
10. `Skill gsd-ship` → `N`. ⏸️ Bloqueio de ambiente (sem remote/`gh`/branch) → roda a reconciliação (4.1) e SÓ ENTÃO respeita e reporta (a fase fechou localmente; só a publicação ficou). Os `AskUserQuestion` de revisão do ship ficam.

**Etapa 4 — Encerramento**
11. Reconciliação de estado (4.1): checkbox da fase no ROADMAP, STATE coerente (inclusive `status`), `.continue-here.md` (raiz E pasta da fase) e `HANDOFF.json` obsoletos.
12. Banner final com o PR e os próximos passos.

</master_checklist>

---

<subroutines>

<subroutine name="V — gate da UAT / verificação (Etapa 0.3)">

## Sub-rotina V — gate da UAT / verificação (Etapa 0.3)

Este é o coração da skill: decidir se a fase pode ser fechada e se a verificação precisa de
promoção. Leia os campos por `grep` (não leia os arquivos inteiros — poupe contexto).

1. Acha a `VERIFICATION.md` e lê o status:
   ```bash
   VFILE=$(ls "$PHASE_DIR"/*-VERIFICATION.md 2>/dev/null | head -1)
   VSTATUS=$(grep -m1 -E '^status:' "$VFILE" 2>/dev/null | sed -E 's/^status:[[:space:]]*"?([a-z_]+)"?.*/\1/')
   ```
2. Decide pelo `VSTATUS`:
   - **vazio / sem `VFILE`** → ⏸️ **para**: "a fase N não foi verificada — rode o miolo (`/go-and-do N`) ou `/gsd-execute-phase N` antes de fechar."
   - **`passed` ou `pass`** → ok. Marca `NEED_PROMOTE=false` e segue (o ship aceita os dois; não precisa de UAT nem promoção: não havia itens humanos).
   - **`gaps_found`** → ⏸️ **para**: "verificação com `gaps_found` (requisitos obrigatórios não entregues) — feche os gaps antes (`/gsd-plan-phase N --gaps` → `/gsd-execute-phase N`)."
   - **`human_needed`** → vai pro passo 3 (precisa da prova da UAT).
   - **qualquer outro valor** (inesperado) → ⏸️ **para** e mostre o `VSTATUS` lido, pedindo
     que o usuário confira a `VERIFICATION.md` (não arrisque um ship com status ambíguo).
3. `human_needed` → **veredito da UAT pelo predicado nativo** (`phase uat-passed`, GSD 1.5.0+),
   com fallback por grep para installs antigos. Rode **no mesmo bloco bash do shim** (Etapa 0.2 —
   a função `gsd_run` não sobrevive entre chamadas Bash):
   ```bash
   UATP=$(gsd_run phase uat-passed "${N}" --raw 2>/dev/null)
   UAT_VERDICT=$(printf '%s' "$UATP" | node -e '
     let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
       let j; try { j = JSON.parse(s); } catch(e) { console.log("NATIVE_UNAVAILABLE"); return; }
       if (j.passed) { console.log("CLEAN"); return; }
       const bad = (j.checks||[]).filter(c=>!c.passing);
       const nonSkip = bad.filter(c=>String(c.result).toLowerCase()!=="skipped");
       const hard = (j.blockers||[]).some(b=>/frontmatter|malformed|policy|verification required/i.test(b));
       if (j.no_uat_artifacts || hard || nonSkip.length>0 || (j.checks||[]).length===0) {
         console.log("FAIL");
         (j.blockers||[]).forEach(b=>console.error("  - "+b));
       } else {
         console.log("SKIPPED_ONLY");
         bad.forEach(c=>console.error("  - test "+c.test+": "+c.name));
       }
     });
   ' 2>/tmp/uat-detail.$$ )
   DETAIL=$(cat /tmp/uat-detail.$$ 2>/dev/null); rm -f /tmp/uat-detail.$$
   ```
   > Por que o predicado nativo: é *markdown-aware* e *fail-closed* — varre **todos** os
   > `*-UAT.md` (inclusive `*-HUMAN-UAT.md`), ignora `result:` dentro de code-block/comentário/
   > citação, e conta como aprovado **só** `pass`/`passed`. O grep antigo desta sub-rotina olhava
   > um arquivo só (`head -1`) e rejeitava só `pending|blocked`, deixando `result: skipped` passar —
   > o que podia **shipar comportamento não-verificado** (ex.: teste pulado por faltar precondição).

   Decida pelo `UAT_VERDICT` (mesmas rotas no nativo e no fallback):
   - **`CLEAN`** → `NEED_PROMOTE=true`, `SKIPPED_ACCEPTED=false`; segue (promoção na Etapa 2).
   - **`SKIPPED_ONLY`** — a UAT só não passou porque há testes `skipped` (comportamento que
     **ninguém verificou**, não uma reprovação) → **bloquear e perguntar** (`AskUserQuestion`):
     - Pergunta (mostre o `DETAIL`): *"A fase N tem teste(s) pulado(s), não verificado(s):\n{DETAIL}\n
       Bloquear o ship (recomendado) ou aceitar mesmo assim?"*
     - Opções: **"Bloquear — rodar /gsd-verify-work"** (recomendada) · **"Aceitar e shipar assim"**.
     - **Bloquear** → ⏸️ **para**: "rode `/gsd-verify-work N`, resolva os skipped (ex.: crie a
       precondição que faltou) e rode `/close-phase N` de novo."
     - **Aceitar** → `NEED_PROMOTE=true`, `SKIPPED_ACCEPTED=true` (a evidência da promoção vai
       registrar que os skipped foram **aceitos explicitamente** pelo humano).
   - **`FAIL`** — reprovação real (`pending`/`blocked`/`issue`/`failed`/`missing`, frontmatter
     `partial`, markdown malformado, ou sem artefato de UAT) → ⏸️ **para**: "a UAT da fase N não
     passou — rode `/gsd-verify-work N` e resolva antes de fechar." Mostre o `DETAIL`.
   - **`NATIVE_UNAVAILABLE`** (install < 1.5.0 / predicado ausente) → fallback endurecido por grep
     (varre todos os `*-UAT.md`, rejeita `pending|blocked|issue|failed`, conta `skipped`):
     ```bash
     UFILES=$(ls "$PHASE_DIR"/*-UAT.md 2>/dev/null)
     if [ -z "$UFILES" ]; then UAT_VERDICT=FAIL; DETAIL="sem arquivo *-UAT.md"; else
       FB_FAIL=false; FB_SK=0
       while IFS= read -r U; do
         { grep -qE '^status:[[:space:]]*complete' "$U" \
           && grep -qE '^issues:[[:space:]]*0\b' "$U" \
           && grep -qE '^pending:[[:space:]]*0\b' "$U" \
           && ! grep -qE '^[[:space:]]*result:[[:space:]]*\[?(pending|blocked|issue|failed)\]?' "$U"; } \
           || FB_FAIL=true
         FB_SK=$((FB_SK + $(grep -cE '^[[:space:]]*result:[[:space:]]*\[?skipped\]?' "$U" 2>/dev/null)))
       done <<< "$UFILES"
       if $FB_FAIL; then UAT_VERDICT=FAIL
       elif [ "$FB_SK" -gt 0 ]; then UAT_VERDICT=SKIPPED_ONLY; DETAIL="$FB_SK teste(s) skipped (fallback)"
       else UAT_VERDICT=CLEAN; fi
     fi
     ```
     Classifique e siga as **mesmas três rotas** (CLEAN / SKIPPED_ONLY / FAIL) acima.

> **Por que a UAT é a prova.** O `/gsd-verify-work` não promove o `status` da
> `VERIFICATION.md` (nem o `transition`/`verify-phase` o fazem) — `human_needed` fica
> "grudado". Mas a UAT limpa é a verificação humana concluída. Então usamos a `UAT.md`
> como fonte da verdade e promovemos na Etapa 2 com essa evidência registrada.

</subroutine>

<subroutine name="P — promover a verificação (human_needed → passed)">

## Sub-rotina P — promover a verificação (`human_needed` → `passed`)

Só roda se `NEED_PROMOTE=true`. Promova fora da sua janela, com um script (não leia o
`VFILE` inteiro pra dentro do orquestrador).

> **Honradez da evidência:** o UAT pode ter sido **humano** (`/gsd-verify-work`) ou **automatizado**
> pela `/go-and-do` (subagente). Não afirme "verificação humana" quando foi a máquina. Detecte pelo
> marcador `pre_uat: executed` no `UAT.md` (campo custom que só o UAT automatizado escreve) e ajuste
> a linha de evidência. Quando automatizado, registre também que itens subjetivos podem ter sido
> **assumidos** (estão no `NN-RESUMO-EXECUTIVO.md`).

```bash
DATE=$(date +%Y-%m-%d)
UFILE=$(ls "$(dirname "$VFILE")"/*-UAT.md 2>/dev/null | head -1)
if grep -qE '^pre_uat:[[:space:]]*executed' "$UFILE" 2>/dev/null; then
  EVID='UAT automatizado (go-and-do) concluído — 0 issues, 0 pendências objetivas; itens subjetivos, se houver, foram assumidos e registrados no resumo executivo.'
else
  EVID='UAT humano (`/gsd-verify-work`) concluído — `UAT.md` em `complete`, 0 issues, 0 pending/blocked.'
fi
if [ "${SKIPPED_ACCEPTED:-false}" = "true" ]; then
  EVID="$EVID Testes pulados (skipped) aceitos explicitamente pelo humano no fechamento — comportamento NÃO verificado."
fi
node -e '
  const fs=require("fs");
  const p=process.argv[1], date=process.argv[2], evid=process.argv[3];
  let s=fs.readFileSync(p,"utf8");
  const before=s;
  s=s.replace(/^(status:\s*)"?human_needed"?\s*$/m, "$1passed");
  // O corpo também — é o corpo que um humano lê (caso real, F19: frontmatter `passed`
  // com o corpo ainda afirmando `human_needed` na linha de status).
  s=s.replace(/^(\*\*Status:\*\*\s*)`?human_needed`?/m, "$1passed *(promovido — ver § Promoção de status)*");
  if(!/## Promoção de status \(close-phase\)/.test(s)){
    s=s.replace(/\s*$/,"")+"\n\n## Promoção de status (close-phase)\n\n"
      +"Status promovido de `human_needed` para `passed` em "+date+".\n"
      +"Evidência: "+evid+"\n";
  }
  if(s===before){ process.stderr.write("NOFLIP\n"); process.exit(2); }
  fs.writeFileSync(p,s);
' "$VFILE" "$DATE" "$EVID"
```

> Depois de rodar, confirme o flip:
> `grep -qE '^status:[[:space:]]*"?passed"?' "$VFILE"` (no `grep` o `[[:space:]]` é válido;
> só no regex do `node`/JS é que se usa `\s`).

- **Flip confirmado** → segue (a evidência ficou registrada no corpo da `VERIFICATION.md`).
- **`NOFLIP` / flip não confirmado** (formato inesperado do frontmatter) → ⏸️ **para** e
  avise: "não consegui promover a `VERIFICATION.md` automaticamente — ajuste `status: passed`
  à mão e rode `/close-phase N` de novo." (Nunca force um `ship` com a verificação travada.)

</subroutine>

<subroutine name="C — commitar os docs (deixar a árvore limpa pro ship)">

## Sub-rotina C — commitar os docs (deixar a árvore limpa pro ship)

Só roda se `commit_docs` (do `init.phase-op`) for verdadeiro. O preflight do `ship` exige
árvore limpa; o extract e a promoção sujam o `LEARNINGS.md`/`VERIFICATION.md`/`STATE.md`.

```bash
git add "$PHASE_DIR"/*-LEARNINGS.md "$PHASE_DIR"/*-VERIFICATION.md \
        .planning/STATE.md 2>/dev/null
git diff --cached --quiet 2>/dev/null || \
  git commit -m "docs(${PADDED_PHASE}): close phase ${N} — learnings + verification" >/dev/null
```

- O `git add ... 2>/dev/null` ignora arquivos que não existem; o `git diff --cached --quiet`
  pula o commit se nada foi staged (ex.: `.planning/` está no `.gitignore` — nada a fazer).
- `commit_docs` é falso → não commita. Avise no banner que, se o `.planning/` for trackeado,
  o ship vai perguntar "commit ou stash" (comportamento esperado de quem desligou o
  auto-commit de docs).

</subroutine>

</subroutines>

---

<stages>

<stage id="0" name="Preparação">

## Etapa 0 — Preparação

**0.1 — Argumento.** Pegue o número da fase (primeiro número de `$ARGUMENTS`). Sem número →
**pare** e peça o número da fase.

**0.2 — Retrato da fase.** Resolva o `gsd-tools` (shim canônico — o mesmo dos comandos GSD
nativos; o antigo `gsd-sdk` foi removido na migração pro OpenGSD) e rode o `init.phase-op`:

```bash
# Resolve gsd-tools.cjs: <runtime>/gsd-core/bin → <root>/.claude/gsd-core/bin → gsd-tools no PATH → ~/.claude/gsd-core/bin
_GSD_SHIM_NAME="gsd-tools.cjs"; _GSD_RUNTIME_ROOT="${RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GSD_TOOLS="${_GSD_RUNTIME_ROOT}/gsd-core/bin/${_GSD_SHIM_NAME}"; if [ -f "$GSD_TOOLS" ]; then gsd_run() { node "$GSD_TOOLS" "$@"; }; elif [ -f "${_GSD_RUNTIME_ROOT}/.claude/gsd-core/bin/${_GSD_SHIM_NAME}" ]; then GSD_TOOLS="${_GSD_RUNTIME_ROOT}/.claude/gsd-core/bin/${_GSD_SHIM_NAME}"; gsd_run() { node "$GSD_TOOLS" "$@"; }; elif command -v gsd-tools >/dev/null 2>&1; then GSD_TOOLS="$(command -v gsd-tools)"; gsd_run() { "$GSD_TOOLS" "$@"; }; elif [ -f "$HOME/.claude/gsd-core/bin/${_GSD_SHIM_NAME}" ]; then GSD_TOOLS="$HOME/.claude/gsd-core/bin/${_GSD_SHIM_NAME}"; gsd_run() { node "$GSD_TOOLS" "$@"; }; else echo "ERROR: gsd-tools.cjs not found at $GSD_TOOLS and gsd-tools is not on PATH. Run: npx -y @opengsd/gsd-core@latest --claude --local" >&2; exit 1; fi
INIT=$(gsd_run query init.phase-op "${N}")
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
```

Guarde do JSON: `planning_exists`, `phase_found`, `phase_dir` (→ `PHASE_DIR`),
`padded_phase` (→ `PADDED_PHASE`), `commit_docs`. Detecte o branch atual
(`git branch --show-current`) pra retomada por PR.

**0.3 — Portões de entrada (stop points), em ordem:**
1. `planning_exists` falso → **pare**: "não é um projeto GSD aqui".
2. `phase_found` falso → **pare**: "fase N não está no ROADMAP (número errado?)".
3. **Gate UAT/verificação** → rode a Sub-rotina V. Ela define `NEED_PROMOTE` e pode parar.

**0.4 — Banner.** Imprima fase + nome + "fechando a fase (extract-learnings → ship)" e diga
que o usuário pode acompanhar; se `NEED_PROMOTE=true`, avise que a verificação vai ser
promovida com base na UAT limpa.

</stage>

<stage id="1" name="Aprendizados">

## Etapa 1 — Aprendizados

**1.1 — Retomada.** Existe `<PHASE_DIR>/*-LEARNINGS.md`? → pule a extração (vá pra Etapa 2).
*(O extract é idempotente — sobrescreve —, mas pular evita re-trabalho numa retomada.)*

**1.2 — Extrair.** `Skill gsd-extract-learnings` com args `N`. O comando lê PLAN/SUMMARY
(obrigatórios) + VERIFICATION/UAT/STATE (opcionais), extrai decisões/lições/padrões/surpresas
e grava o `NN-LEARNINGS.md`. Sem PLAN/SUMMARY ele sai com erro → **pare** e reporte.

</stage>

<stage id="2" name="Ponte de verificação + commit">

## Etapa 2 — Ponte de verificação + commit

**2.1 — Promoção.** Se `NEED_PROMOTE=true` → Sub-rotina P (promove a `VERIFICATION.md` pra
`passed`, registrando a evidência). Se `NEED_PROMOTE=false` (já era `passed`) → nada.

**2.2 — Commit dos docs.** Sub-rotina C (deixa a árvore limpa pro preflight do ship).

</stage>

<stage id="3" name="Ship">

## Etapa 3 — Ship

**3.1 — Retomada por PR.** Antes de chamar o ship, cheque se já existe PR pro branch:

```bash
EXISTING_PR=$(gh pr list --head "$(git branch --show-current)" --json number,url --jq '.[0]' 2>/dev/null)
```

- PR já existe → pule a chamada do ship. Guarde número/URL e vá pra Etapa 4.
  *(Re-chamar o ship com PR aberto falharia no `gh pr create`.)*
- Não existe → vá pra 3.2.

**3.2 — Ship.** `Skill gsd-ship` com args `N`. O ship faz o próprio preflight (agora passa:
status promovido + árvore limpa), faz push, gera o corpo do PR e cria o PR; depois oferece
revisão (`AskUserQuestion`: Skip / Self-review / Request review) — deixe esses prompts
chegarem ao usuário, são a granularidade certa.
- **Bloqueio de ambiente** que não controlamos — sem `origin`, `gh` ausente/não autenticado,
  ou branch errado → o ship reporta e sai. **Respeite o bloqueio**, mas antes de parar rode a
  **reconciliação de estado (4.1)**: o bloqueio é de PUBLICAÇÃO; a fase está fechada
  localmente (verificação promovida, learnings extraídos) e os marcadores têm que refletir
  isso — foi exatamente assim que a Fase 17 ficou `- [ ]` no ROADMAP e `verifying` no STATE
  com o trabalho todo pronto. Depois registre no banner o que faltou (ex.: "configure o
  remote / `gh auth login` / mude de branch") e **pare** (sem 4.2 — não há PR). Esses são
  pré-requisitos de ambiente que só o usuário resolve.

</stage>

<stage id="4" name="Encerramento">

## Etapa 4 — Encerramento

Só se chegou até aqui (se parou antes, já reportou o bloqueio e parou — com uma exceção: o
bloqueio de ambiente do ship roda a 4.1 antes de parar, ver 3.2).

**4.1 — Reconciliação de estado.** O fecho não termina nos artefatos: os MARCADORES têm
que dizer a mesma coisa (casos reais: a Fase 16 do grupo-inspired ficou `- [ ]` no ROADMAP
por dias, com verificação `passed` e PR mergeado; as Fases 18 e 19 fecharam com um
`HANDOFF.json` commitado dizendo `status: paused` — quem retomar o repo pelo handoff é
enganado). Cheque e corrija, nesta ordem:

1. **ROADMAP:** `grep -n "Phase ${N}\b" .planning/ROADMAP.md` — a linha da fase está
   `- [ ]` com a verificação `passed`? → troque para `- [x]` (e acrescente
   `(completed YYYY-MM-DD)` se as outras fases fechadas seguem esse padrão).
2. **`.planning/.continue-here.md`:** existe e aponta para ESTA fase? → remova (é
   marcador de pausa; a fase está fechada). Aponta para outra fase → não toque.
3. **`.planning/HANDOFF.json`:** existe e aponta para ESTA fase (`"phase"` = N)? → remova
   — mesmo estatuto do caso 2: marcador de pausa numa fase fechada. Aponta para outra
   fase → não toque.
4. **`.continue-here.md` da PASTA DA FASE** (`<phase_dir>/.continue-here.md`): existe? →
   ele pode ficar como histórico, mas não pode afirmar pendência: garanta
   `status: resolved` no frontmatter e corrija contagens/frases que digam trabalho em
   aberto (caso real, F19: `task: 2 / total_tasks: 7` commitado numa fase 7/7).
5. **STATE.md:** `completed_phases`/`current_phase`/`status` coerentes com a fase fechada
   (um `status: executing` com a fase encerrada é marcador enganoso da mesma família)?
   O GSD nativo costuma atualizar; divergiu → corrija só os campos divergentes.

Mudou qualquer arquivo e `commit_docs` é verdadeiro → commite:
`git add .planning/ROADMAP.md .planning/STATE.md && git rm -q --cached --ignore-unmatch .planning/.continue-here.md .planning/HANDOFF.json 2>/dev/null; git add -A "<phase_dir>/.continue-here.md" 2>/dev/null; git diff --cached --quiet || git commit -m "docs(${PADDED_PHASE}): reconciliar marcadores de estado (ROADMAP/STATE/handoff)"`
(mais `rm -f` no disco dos arquivos removidos nos casos 2 e 3).
Nada divergente → siga em silêncio (não gere commit vazio).

**4.2 — Banner final.** Imprima fase + PR (#N e URL) + próximos passos: aprovar/merge ·
`/gsd-complete-milestone` se for a última fase da milestone · `/gsd-progress`. Encerre — o
volante é seu. Idempotente: re-rodar depois de pronto detecta o PR existente e cai direto
aqui.

</stage>

</stages>
