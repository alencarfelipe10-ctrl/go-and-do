# discuss-phase — bloco de fecho

Bloco lazy do comando único (plano 06-20): todo passo do `write_context` em diante mora aqui, mais o
`reconcile_existing` (o caminho «refazer»). O `discuss-phase.md` nunca o copia — ele é lido com `Read` em cada
borda que entra num destes passos (fim da régua de ambiguidade, estados `gravar` e `finalizar`, e a resposta
«refazer» dos estados `existe-*`), uma vez por rodada.

Ordem fixa: `write_context` (guarda, explicação, «ok», aprovação, promoção) → `dispatch_discuss_post_hooks` →
`finalize` → `confirm_creation`. O `reconcile_existing` só roda quando o `initialize` manda e devolve à entrevista.
O documento da fase (`$CONTEXT_PATH`) só muda numa promoção, depois do «ok» do dono: antes dela, nada no disco da
fase é tocado — nem para marcar rejeição.

<step name="write_context">
O documento é montado por script a partir do depósito; você só corrige o depósito.

**1. Guarda do rascunho** — render (função pura do depósito) num rascunho em `$T`, conferência do documento e PII:

```bash
. .planning/.discuss-tmp/env.sh
[ -s "$T/pii-nomes.txt" ] && export PII_NOMES="$T/pii-nomes.txt"
bash "$NOSSO/discuss-render-guard.sh" --root .
```

Saída: uma linha `{"rascunho", "sha256", "falhas": [...], "pii", "ok", "falhas_omitidas", "log"}` (o log completo
em `$T/render-guard.log` quando `falhas_omitidas > 0`). A guarda nunca promove.

- `ok: true` → siga com o `sha256` desta saída.
- `ok: false` → corrija pelo writer (`set-secao` da seção apontada; `SECAO-VAZIA <slug>` = seção sem texto;
  `PII-…` = troque o nome da pessoa por número ou papel) e rode a guarda de novo. No máximo duas passadas de
  correção: se a segunda ainda reprova, não grave — o depósito e o rascunho ficam em `$T`, diga ao dono em
  linguagem leiga o que impede a gravação e termine com `[guard] rascunho reprovado: <códigos>`.

**2. Estado `gravar`** (o dono já disse «ok» e a gravação caiu): se o `sha256` da guarda é o `aprovado_sha256` da
linha `DEPOSITO` do init, pule para o item 4 sem nova pergunta. Se difere, trate como gravação nova (item 3).

**3. Explicação e «ok».** Na sessão, em linguagem leiga e sem nome de arquivo, função, ferramenta ou id, explique:
o que a fase entrega, o que fica de fora, o que o dono decidiu (uma frase por decisão) e o que ficou como
suposição para o planner. Depois pergunte se pode gravar (pergunta em `modes/default.md`). Só um «ok» explícito
grava. Qualquer outra resposta volta à entrevista: o que for decisão vai ao depósito (`add-decision --origin
owner`), as seções afetadas são reescritas e este passo recomeça do item 1.

**4. Aprovação e promoção** — com o «ok», grave a aprovação com o sha do rascunho que ele aprovou e promova:

```bash
. .planning/.discuss-tmp/env.sh
SHA="<sha256 da guarda>"
python3 "$NOSSO/checkpoint-write.py" aprovar "$CKPT" --sha256 "$SHA"
python3 "$NOSSO/context-render.py" --promover "$RASCUNHO" "$CONTEXT_PATH" --sha256 "$SHA" --ckpt "$CKPT"
```

A promoção troca o documento de uma vez (temporário irmão + troca atômica): um corte no meio deixa o documento
anterior inteiro ou o novo inteiro, nunca pela metade. Exit 2 = o rascunho ou o depósito mudou depois do «ok»
(sha divergente ou aprovação zerada): o documento ficou como estava; recomece do item 1 e peça o «ok» de novo.
</step>

<step name="dispatch_discuss_post_hooks">
```bash
. .planning/.discuss-tmp/env.sh
ARGUMENTS="$ARGUMENTS" bash "$NOSSO/discuss-hooks-filter.sh"
```

(`ARGUMENTS` é repassado como no `initialize` — o `env.sh` não o carrega.)

O filtro é mecânico e **nunca despacha**: renderiza `discuss:post` e imprime um resumo de uma linha (hooks
reduzidos a `id`/`kind`/`blocking`/`onError`/`ref`, com `check.query`/`check.predicate`/`fragment.inline`
cortados em 200 caracteres e `truncado: true` quando cortados) mais os três vetores extras; o envelope inteiro
fica no arquivo indicado em `envelope` (`$T/hooks-envelope.json`).

**Você despacha** cada entrada de `activeHooks` per @~/.claude/gad-core/references/loop-hook-dispatch.md — todos
os tipos: `contribution` (injete `fragment.inline` verbatim; com `truncado: true`, leia o texto do arquivo
`envelope`, nunca do resumo), `ref.skill` (ferramenta Skill, id `gad-<ref.skill>`), `ref.command`
(`gad_run <command> --phase "${PHASE_NUMBER}" --raw`), `gate` (avalie `check`, respeite `blocking`/`onError`).
`activeHooks` vazio → nenhum despacho, siga em `finalize`.

- `nao_despachaveis` não vazio → para cada entrada, toque o sino `hook_nao_despachado: <ref.agent|gate>` e
  registre um incidente (host sem a ferramenta Agent). Nunca pule em silêncio; `agentVerdict` nunca bloqueia.
- `rejeitados` não vazio → manifesto malformado: mostre cada `motivo` como aviso alto e não rode a entrada.
- **Exit 3** = um `gate` bloqueante foi rejeitado: falhe fechado — pare, não faça commit, toque o sino com os
  motivos.
</step>

<step name="finalize">
Uma chamada faz conferência do documento promovido, índice de decisões, STATE, commit e limpeza — nessa ordem:

```bash
. .planning/.discuss-tmp/env.sh
bash "$NOSSO/discuss-finalize.sh"
```

Saída: `{"commit", "hash", "skipped", "rejected_path", "reason", "files", "gad_tools", "cleaned", "msgs",
"msgs_truncadas", "log"}` — `msgs` = últimas 60 linhas do log; `log` é `$T/finalize.log` na falha e
`${phase_dir}/.discuss-finalize.log` depois de uma limpeza bem-sucedida.

- `commit: true` → confirme `Committed: docs(${padded_phase}): capture phase context + decisions index`.
- `skipped: true` (`commit_docs=false` ou `.planning` ignorado) → registre `[commit] skipped by commit_docs
  policy` — **nunca improvise um `git commit`**.
- Nenhum dos dois (exit 2) → o commit falhou ou o conferidor reprovou o documento promovido (`reason: guard`,
  `rejected_path` = o documento, que fica onde está). `$T` e o depósito foram preservados: mostre `reason` e
  `msgs`, não declare sucesso; corrija pelo writer e refaça `write_context` (o «ok» é pedido de novo).

A limpeza (`$CKPT` + `$T`) só acontece depois do sucesso; daqui em diante o `env.sh` não existe mais.
</step>

<step name="reconcile_existing">
O caminho «refazer», escolhido pelo dono nos estados `existe-novo` / `existe-antigo`.
O documento existente só é trocado na promoção, depois do novo «ok»: até lá ele continua valendo e nada nele muda.

1. Recomece o depósito (o init não escreveu nada nesses estados). Com `$NOSSO` e `$GAD_TOOLS` das quatro
   primeiras linhas do bloco do `initialize`, troque `<phase_dir>`, `<padded_phase>` e `<phase_name>` pelos
   valores do INIT (nenhum pode ficar vazio):

```bash
CKPT="<phase_dir>/<padded_phase>-DISCUSS-CHECKPOINT.json"
python3 "$NOSSO/checkpoint-write.py" init "$CKPT" --phase "<padded_phase>" --phase-name "<phase_name>"
GAD_TOOLS="$GAD_TOOLS" ARGUMENTS="$ARGUMENTS" bash "$NOSSO/discuss-init.sh" "${PHASE}"   # + --insumo <arquivo> …
```

   O init agora devolve `ESTADO_INTENCAO=retomar` e grava o `env.sh`.
2. Leia o documento existente como texto de apoio, como um `--insumo`: o que nele foi decidido vira pergunta de
   confirmação ao dono, nunca decisão copiada.
3. Volte ao `discuss-phase.md` e siga em `explain_phase`. Uma queda daqui em diante retoma pelo depósito, com o
   documento existente intacto.
</step>

<step name="confirm_creation">
Resuma ao dono, em linguagem leiga:

```
Gravado: a especificação da fase ${padded_phase} — {N} decisões suas, {M} critérios de aceite.
Próximo: /go-and-do ${padded_phase} — a Go & Do leva a fase do plano ao fim a partir deste documento, começando pela consultoria.
```

Com `skipped: true`, diga que o documento está gravado mas não foi para o histórico do projeto (política de commit).
</step>
