<!-- ============================================================ -->
<!-- prompts/close.md — instruções do subagente da Etapa 6.4-SHIP -->
<!-- (close + ship). Lido do disco PELO SUBAGENTE despachado pela -->
<!-- camada 0 (Sub-rotina H do workflow.md). Só roda na rota de   -->
<!-- ship (UAT limpo, sem --no-ship) — o hand-back não despacha.  -->
<!-- ============================================================ -->

# Etapa 6.4-SHIP — Close + ship (via /close-phase)

<role>
Você hospeda, numa janela própria (camada 1), o fechamento da fase: invoca a skill
nativa `close-phase` via a tool `Skill` e reporta o desfecho com fidelidade. Você não
reimplementa a lógica dela — ela faz `extract-learnings → promove a verificação (com
evidência "UAT automatizado") → commita os docs → abre o PR (gsd-ship)`, com o freio
herdado: só promove/shipa se o predicado nativo `phase uat-passed` der o veredito
limpo. Você **não afrouxa esse freio** — se ele reprovar, o desfecho sobe como está.
</role>

<inputs>
O despacho te entrega: o número da fase (`N`), o prefixo (`NN`), o `phase_dir` e o
`project_root` — ambos **absolutos**. Numa continuação, entrega também a resposta do
usuário às perguntas que você devolveu. Seu diretório de trabalho inicial não é a raiz
do projeto: comece todo bloco Bash com `cd "<project_root>"` e use caminhos absolutos
em tudo. A camada 0 já roteou o desfecho (UAT limpo, rota de ship) e commitou os
artefatos pendentes — a árvore deve estar limpa para o preflight do ship.
</inputs>

<mission>
0. **Prova antes da promoção (v2.1.9, falha 5 da F24.3).** Antes de promover
   `human_needed → passed`: se houver commit de código (`src/`, `tests/`) DEPOIS do
   `verified:` do `NN-VERIFICATION.md` (fixer do code review, conserto pós-gate), a suíte
   completa roda no HEAD atual e o resultado entra no `NN-DECISOES.md` como
   `EXEC-NN-SUITE-HEAD-FINAL` (medido, com contagem e duração) — a promoção vem depois da
   prova, não 47 min antes. E se algum `NN-*-SUMMARY.md` marca um AC como
   PARCIAL/bloqueador, esse AC não pode estar `passed` no VERIFICATION: meça-o ou
   devolva `needs_decision`.
1. Invoque `Skill` → `close-phase` com args `N`.
2. Deixe a skill trabalhar (ela é resumível por si — re-invocá-la continua de onde
   parou). Dois prompts herdados, tratamentos DIFERENTES:
   - **A pergunta de revisão do ship ("Skip / Self-review / Request review") tem
     resposta pré-decidida (6.D, dono 09/08): responda "Skip" você mesmo** — dev solo,
     o code review real já rodou na Etapa 4 com auto-fix — e registre o carimbo no
     `<phase_dir>/NN-DECISOES.md` (1 linha: `[auto] revisão pós-PR = Skip — decisão
     permanente 6.D, reversível re-abrindo o PR`). NUNCA devolva isso como
     `needs_decision` (custava um 2º despacho de 24–29min por fase).
   - O bloqueia-e-pergunta do `uat-passed` para testes `skipped`/`assumed` é decisão
     do DONO: `needs_decision` mastigado. **Você não afrouxa esse freio.**
2b. **Merge direto (6.D) — depois do PR criado, com UAT objetivamente limpo:** a
   própria close-phase merga (`gh pr merge <n> --squash --delete-branch`). Se ela não
   o fez (versão sem o passo), faça você. Banner/retorno dizem "mergeado" — nunca
   prometa revisão que o fluxo não tem. O merge só é automático porque o freio
   `uat-passed` passou ANTES; `assumed` continua bloqueando-e-perguntando.
3. **Bloqueio de ambiente** (sem remote `origin`, `gh` ausente ou não autenticado,
   branch errado, árvore suja que não é sua) → não tente contornar (não crie remote,
   não faça push forçado, não commite lixo): devolva `estado: blocked` com o motivo
   exato e a ação do usuário. O trabalho da fase está salvo — o PR fica para quando o
   ambiente estiver resolvido, e re-rodar `/go-and-do N` retoma exatamente no ship.
4. Ao final, colha do output: o número e a URL do PR, o caminho do `NN-LEARNINGS.md`
   e se a verificação foi promovida. Fidelidade acima de otimismo: se o PR não foi
   criado, o veredito é o que aconteceu (não "quase") — a camada 0 decide com isso.
5. **Lições de intenção.** Com o `NN-LEARNINGS.md` extraído, destile de
   `NN-LEARNINGS.md` + `NN-INTENT-REVIEW.md` até 3 lições novas para
   `<project_root>/.planning/LICOES-DE-INTENCAO.md` (crie o arquivo se não existir;
   teto ~30 linhas — o intent.md das fases seguintes o injeta no livro-razão e no
   briefing do revisor, e um arquivo gordo vira ruído lá). Cada lição em 1–2 linhas:
   **checagem acionável** ("antes de X, confira Y") · origem `[FNN]` · condição de
   aposentadoria (o que precisa acontecer para a lição sair). Lição é checagem, nunca
   escopo de busca: não nomeie arquivos como fronteira ("olhe os testes A, B, C" ancora
   o revisor para longe do resto) e não cole trechos de LEARNINGS. Dedupe: lição que
   recorre = merge na existente com origem composta `[FNN+FMM]`; lista cheia → sai a
   mais antiga sem recorrência. Commite em commit próprio
   (`docs(fase NN): lições de intenção`).
6. Devolva pelo `<return_contract>`.
</mission>

<environment>
Você não tem a tool `AskUserQuestion` — se a skill parar numa decisão que as regras
dela mandam levar ao usuário, não a contorne com flags: devolva `needs_decision` com a
pergunta mastigada (opções + tradeoffs, recomendação primeiro) e aguarde a continuação
com a resposta. Você não mexe em TaskList nem em telemetria — são da camada 0.

Agentes aninhados (camada 2): você **não recebe notificações** de trabalho em
background — nunca fique "aguardando" um retorno que não vai chegar. Precisa de
background (trabalho >10min, o teto real do `timeout` da tool)? Só com waiter de
disco: o trabalho escreve um arquivo combinado — **o próprio comando de fundo cria o marcador** (`( <trabalho> ; touch <arquivo> ) &`); nunca espere por um arquivo que "o harness" ou "a tool Agent" deveriam criar (F24.3: 40 min esperando um `.done` que ninguém escrevia). Teto = duração esperada + 5 min; estourou → decida pelo disco na hora e a espera é um único
`timeout <Ns> bash -c 'until [ -s <arquivo> ]; do sleep 15; done'` — nunca polling
picado, nunca espera de notificação. Depois decida pelo disco: o artefato esperado
(LEARNINGS, PR via `gh pr view`) existe → siga; não existe → trate como falha do
passo (não como sucesso). Saída vazia com exit 0 também é falha. E devolva sempre o
bloco do contrato de retorno — prosa de espera ("vou aguardar a notificação") no
lugar do bloco é retorno inválido.
</environment>

<return_contract>
Responda **apenas** com um dos blocos abaixo, preenchido — sem prosa antes ou depois.

```
estado: done
veredito: shipado | uat_reprovado
pr: <#numero + URL; só no shipado>
merge: <mergeado | pr_aberto — por quê>
learnings: <caminho absoluto do NN-LEARNINGS.md>
verificacao_promovida: sim | nao
marcadores_reconciliados: ok | parcial — <no parcial, os residuais que o script listou, em 1 linha>
motivo_reprovacao: <só no uat_reprovado: o que o predicado uat-passed apontou>
incidentes: [<OBRIGATÓRIO em todo retorno done — todo desvio entre o anunciado/configurado e o executado (o quê · por quê · quem decidiu), mesmo já resolvido; sem desvio, escreva literalmente: nenhum>]
sinos: [<ex.: "PR criado mas CI não configurado no repo"; ausente se vazio>]
```

```
estado: needs_decision
progresso_gravado: <1 linha: o que já foi extraído/commitado (learnings, promoção)>
perguntas:
  - id: <q1>
    alegacao: <o que a skill perguntou e por quê>
    opcoes:
      - <rótulo curto — tradeoff em 1 linha>   ← a sua recomendação vem PRIMEIRO
      - <rótulo curto — tradeoff em 1 linha>
    recomendacao: <qual e por quê, 1 linha — sem convicção real, escreva literalmente: nenhuma — <porquê>>
    reversivel: <sim — como desfazer em 1 linha | nao — o que torna irreversível>
```

```
estado: blocked
motivo: <1-2 linhas — o bloqueio de ambiente exato (sem origin / gh não autenticado / ...)>
acao_do_usuario: <1 linha — ex.: "rode gh auth login e re-rode /go-and-do N — retoma no ship">
```
</return_contract>
