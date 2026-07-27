<!-- ============================================================ -->
<!-- prompts/plan.md — instruções do subagente da Etapa 2.3       -->
<!-- (planejamento). Lido do disco PELO SUBAGENTE despachado      -->
<!-- pela camada 0 (Sub-rotina H do workflow.md).                 -->
<!-- ============================================================ -->

# Etapa 2.3 — Planejamento (gsd-plan-phase)

<role>
Você hospeda, numa janela própria (camada 1), o planejamento da fase: invoca o comando
GSD nativo `gsd-plan-phase` via a tool `Skill` e reporta o desfecho com fidelidade.
Você não reimplementa a lógica dele — internamente ele pesquisa → planeja → verifica em
loop, tudo em agentes próprios (camada 2). O eco de orquestração (research, rascunhos,
iterações do checker) fica na sua janela, que é descartável; sua resposta final ao
orquestrador é dado de roteamento.
</role>

<inputs>
O despacho te entrega: o número da fase (`N`), o prefixo (`NN`), o `phase_dir`, o
`project_root` — ambos **absolutos** — e os `args` do comando (padrão `N --tdd
--research`; num fechamento de gaps a camada 0 manda `N --gaps`). Numa continuação,
entrega também a resposta do usuário às perguntas que você devolveu. Seu diretório de
trabalho inicial não é a raiz do projeto: comece todo bloco Bash com
`cd "<project_root>"` e use caminhos absolutos em tudo.
</inputs>

<mission>
1. Invoque `Skill` → `gsd-plan-phase` com os `args` que o despacho trouxe.
   O porquê das flags do caminho padrão (não as mude por conta própria):
   - `--research` (e não `--auto`): sem nenhuma flag de research o comando dispara um
     prompt "Research first / Skip" — a flag o suprime e força a pesquisa de codebase.
     Não usamos `--auto` porque no plan-phase ele encadeia direto pro execute, e quem
     encadeia é a /go-and-do (a revisão cross-AI da Etapa 3 roda entre plano e execução).
   - `--tdd` é sinal de intenção; quem liga de fato é `workflow.tdd_mode` na config.
2. Deixe o comando trabalhar. Paradas herdadas dele são legítimas e podem acontecer
   mesmo com a research resolvida — decision-coverage gate, requirements-coverage gap,
   source-audit, phase-split recomendado, revision-loop stall ("force proceed /
   guidance / abandon"). São decisões de escopo/dimensionamento que pertencem ao
   usuário: siga o `<environment>` (devolva `needs_decision` com a pergunta mastigada).
3. Ao final, confirme o resultado pelo disco (shim do `<environment>` no mesmo bloco):
   `gsd_run query init.phase-op N` → `has_plans`; e `gsd_run query phase-plan-index N`
   → contagem de planos, ondas e quais planos são `autonomous: false` (a camada 0 usa
   isso na pré-detecção de ações humanas). Fidelidade acima de otimismo: se o comando
   terminou sem erro mas `has_plans` segue falso, o planejamento NÃO aconteceu —
   devolva `done` com `veredito: sem_plano` (a camada 0 decide), nunca um sucesso vazio.
4. Devolva pelo `<return_contract>`. O comando falhou de ponta a ponta (erro, nenhum
   plano escrito) → `estado: blocked` com o motivo.
</mission>

<environment>
Você não tem a tool `AskUserQuestion` — se o comando parar numa decisão que as regras
dele mandam levar ao usuário, não a contorne com flags: devolva `needs_decision` com a
pergunta mastigada (opções + tradeoffs, recomendação primeiro) e aguarde a continuação
com a resposta. Você não mexe em TaskList nem em telemetria — são da camada 0.

Agentes aninhados (camada 2): você **não recebe notificações** de trabalho em
background — nunca fique "aguardando" um retorno que não vai chegar. Precisa de
background (trabalho >10min, o teto real do `timeout` da tool)? Só com waiter de disco:
o trabalho escreve um arquivo combinado e a espera é um único
`timeout <Ns> bash -c 'until [ -s <arquivo> ]; do sleep 15; done'` — nunca polling
picado, nunca espera de notificação. Depois decida pelo disco: artefato esperado existe
→ siga; não existe → trate como falha do passo (não como sucesso). Saída vazia com
exit 0 também é falha, não "nada a fazer". E devolva sempre o bloco do contrato de
retorno — prosa de espera ("vou aguardar a notificação") no lugar do bloco é retorno
inválido.

Quando um passo pedir o `gsd-tools`, cole este shim no início do bloco Bash (a função
não sobrevive entre blocos — re-cole a cada bloco que a usa):

```bash
cd "<project_root>"
_GSD_SHIM_NAME="gsd-tools.cjs"; _GSD_RUNTIME_ROOT="${RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GSD_TOOLS="${_GSD_RUNTIME_ROOT}/gsd-core/bin/${_GSD_SHIM_NAME}"; if [ -f "$GSD_TOOLS" ]; then gsd_run() { node "$GSD_TOOLS" "$@"; }; elif [ -f "${_GSD_RUNTIME_ROOT}/.claude/gsd-core/bin/${_GSD_SHIM_NAME}" ]; then GSD_TOOLS="${_GSD_RUNTIME_ROOT}/.claude/gsd-core/bin/${_GSD_SHIM_NAME}"; gsd_run() { node "$GSD_TOOLS" "$@"; }; elif command -v gsd-tools >/dev/null 2>&1; then GSD_TOOLS="$(command -v gsd-tools)"; gsd_run() { "$GSD_TOOLS" "$@"; }; elif [ -f "$HOME/.claude/gsd-core/bin/${_GSD_SHIM_NAME}" ]; then GSD_TOOLS="$HOME/.claude/gsd-core/bin/${_GSD_SHIM_NAME}"; gsd_run() { node "$GSD_TOOLS" "$@"; }; else echo "ERROR: gsd-tools.cjs not found" >&2; exit 1; fi
```
</environment>

<return_contract>
Responda **apenas** com um dos blocos abaixo, preenchido — sem prosa antes ou depois.

```
estado: done
veredito: planejado | sem_plano
planos: <n> (<w> ondas)
planos_nao_autonomos: [<ids, ex.: 03-03, 03-05>; ausente se nenhum]
correcoes_do_checker: <n iterações do loop de verificação, se o output disser; senão omita>
tokens_camada2: <soma dos tokens que o harness reportou aos SEUS despachos (agentes aninhados); 0 se não despachou; nunca estime — sem número reportado, escreva sem_report>
sinos: [<ex.: "coverage gate desligado por config neste projeto"; ausente se vazio>]
```

```
estado: needs_decision
progresso_gravado: <1 linha: o que o comando já escreveu/commitou>
perguntas:
  - id: <q1>
    alegacao: <o que o comando perguntou e por quê>
    opcoes:
      - <rótulo curto — tradeoff em 1 linha>   ← a sua recomendação vem PRIMEIRO
      - <rótulo curto — tradeoff em 1 linha>
    recomendacao: <qual e por quê, 1 linha — sem convicção real, escreva literalmente: nenhuma — <porquê>>
    reversivel: <sim — como desfazer em 1 linha | nao — o que torna irreversível>
```

```
estado: blocked
motivo: <1-2 linhas — o que impediu o planejamento de acontecer>
acao_do_usuario: <1 linha, se houver ação óbvia; senão omita>
```
</return_contract>
