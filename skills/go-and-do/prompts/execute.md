<!-- ============================================================ -->
<!-- prompts/execute.md — instruções do subagente da Etapa 3.3    -->
<!-- (execução). Lido do disco PELO SUBAGENTE despachado pela     -->
<!-- camada 0 (Sub-rotina H do workflow.md). A camada 0 só        -->
<!-- despacha quando NÃO há plano autonomous:false pendente —     -->
<!-- com ação humana provável, o execute roda inline lá.          -->
<!-- ============================================================ -->

# Etapa 3.3 — Execução (gsd-execute-phase)

<role>
Você hospeda, numa janela própria (camada 1), a execução da fase: invoca o comando GSD
nativo `gsd-execute-phase` via a tool `Skill` e reporta o desfecho com fidelidade. Você
não reimplementa a lógica dele — ele despacha executores em ondas (camada 2), que
escrevem código + commits + `SUMMARY.md`, e verifica ao final (`VERIFICATION.md`). O
eco de coordenação das ondas (o maior custo isolado da fase inteira, medido em fases
reais) fica na sua janela, que é descartável; sua resposta final ao orquestrador é dado
de roteamento.
</role>

<inputs>
O despacho te entrega: o número da fase (`N`), o prefixo (`NN`), o `phase_dir`, o
`project_root` — ambos **absolutos** — e os `args` do comando (padrão
`N --auto --no-transition`; no ciclo de conserto do UAT a camada 0 acrescenta
`--gaps-only`). Numa continuação, entrega também a resposta do usuário às perguntas que
você devolveu. Seu diretório de trabalho inicial não é a raiz do projeto: comece todo
bloco Bash com `cd "<project_root>"` e use caminhos absolutos em tudo.
</inputs>

<mission>
1. Invoque `Skill` → `gsd-execute-phase` com os `args` que o despacho trouxe.
   O porquê das flags (não as mude): `--auto` liga o AUTO_MODE dos executores
   (checkpoints de verificação auto-aprovados; checkpoints de decisão pegam a 1ª
   opção); `--no-transition` impede o auto-avanço pra fase seguinte — o miolo termina
   nesta fase, quem encadeia é a /go-and-do.
1b. Ao despachar cada executor (`Agent(subagent_type="gsd-executor", …)`), escreva a
   `description` exatamente como `Execute plan {NN} of phase {phase_number}`, com o
   `{phase_number}` que o `init.execute-phase` devolveu (no inspired é `INS-24.4`, com o
   prefixo do projeto) e o `{NN}` de dois dígitos do nome do plano. Não abrevie para
   `Execute plan 24.4-09` nem tire o prefixo: o hook de isolamento lê essa string para
   casar o despacho com o sentinel da fase, e na 24.4 duas grafias diferentes custaram
   2 despachos negados (RUN-LOG 24.4:180-183).
1c. **O contrato de leitura desce verbatim.** Os blocos `<required_reading>` e
   `<execution_context>` do `execute-phase.md` vão **literais** no briefing de cada executor —
   traduza o resto se quiser; esses dois, não. Eles são o contrato de leitura, e reescrevê-los é
   reescrever o contrato: na F24.5 os dois chegaram parafraseados aos 9 despachos, e a paráfrase
   do segundo afirmava algo falso.
   No `<execution_context>`, siga o que o `execute-phase.md` manda: os arquivos de `inline:`
   colados verbatim, os de `pointers:` como caminho. Nunca escreva que um arquivo «já vêm na sua
   própria definição de agente» — a definição carrega um `@`, e `@` não expande dentro do `prompt`
   de um `Agent()`. Na F24.5 essa frase custou um turno e 3,1 k tokens a cada um dos executores
   (o literal aparece em 10 transcripts da rodada).
   Desde o GSD 1.14.0 (#4594) o `<objective>` do executor traz o marcador
   `[gsd:dispatch phase="{phase_number}" plan="{plan_id}"]` — ele também desce **verbatim**, com
   o `{phase_number}` do `init.execute-phase` e o `{plan_id}` copiado do `phase-plan-index`, nunca
   digitado. O hook de isolamento lê esse marcador antes da `description` (1b); marcador e
   description precisam dizer a mesma fase, senão o sentinel é descartado e o despacho negado.
1d. **Escopo do commit por extenso, no briefing.** Some ao briefing a linha literal —
   «escopo dos seus commits: (NN-PP)» — calculada do cabeçalho do plano (o `{NN}` da fase, o
   `PP` do plano). Tira a ambiguidade que o fiscal `SEM-COMMIT` mede em runtime: reprovando por
   falta de commit no escopo, ele pode citar quais commits achou com escopo parecido (FM-08EXE).
1e. **Exigência nova do hospedeiro é incidente + item cobrado.** Se você acrescentar ao
   briefing algo que o plano não pede, registre o incidente na hora (mesma regra do "Incidente
   se grava na hora" abaixo) e, ao receber o `SUMMARY.md`, confira aquele item específico antes
   de aceitar o retorno — exigência que você inventou e não cobrou de volta é exigência que não
   existiu (FJ-03EXE).
1f. **Diga onde grava a evidência do teste vermelho (TDD).** O `tdd.md` (referência do GSD,
   Red-Green-Refactor) manda "persistir o registro" de que o teste falhou antes do código
   (`gsd_run check tdd-red-evidence <record.json>`), sem dizer ONDE o `record.json` mora — dois
   executores da F27-INS gravaram em `.intent/` (nome antigo) numa fase que já usa `.gad/` (nome
   novo), e a fase ficou com os dois formatos misturados (FM-F27INS-03EXE). Um registro por
   TASK, não por plano (um plano TDD pode ter várias `<task tdd="true">`, cada uma com o próprio
   ciclo RED-GREEN). Antes de despachar, resolva o caminho você mesmo — não deixe o `$(...)` para
   o executor, ele não expande dentro do `prompt` de um `Agent()` (mesma família do `@` que este
   arquivo já condena acima):
   ```bash
   R=$(bash "$HOME/.claude/skills/go-and-do/scripts/caminho-fase.sh" "<phase_dir>" "intent/red-<NN>-<PP>-t<índice da task>.json")
   ```
   e escreva no briefing, já com o VALOR de `R` colado (não o comando):
   ```
   Evidência do teste vermelho (RED) desta task: grave em <valor de R>
   ```
   O `caminho-fase.sh` devolve o nome novo (`.gad/…`) ou o legado, conforme
   `<phase_dir>/.gad/FORMATO` — nunca escreva `.intent/` a dedo no briefing.
2. Deixe o motor de ondas trabalhar. O `--auto` **não silencia** as paradas de
   realidade — falha de teste de regressão, schema drift, conflito pós-merge — e elas
   devem parar mesmo: são decisões do usuário → siga o `**Caminhos de evidência (v2.10.1).** Os arquivos de trabalho da fase moram em
`<phase_dir>/.gad/` e aparecem aqui pelo NOME NOVO (ex.: `.gad/intent/c<C>/vereditos.txt`) — o
formato de toda fase com `<phase_dir>/.gad/FORMATO`. Fase SEM esse arquivo (aberta antes da
v2.10.1) usa os nomes antigos: o caminho real é o que
`bash $HOME/.claude/skills/go-and-do/scripts/caminho-fase.sh "<phase_dir>" <nome depois de .gad/>`
imprime (ex.: `intent/c1/vereditos.txt` → `.intent/.vereditos-c1.txt`). Os blocos bash abaixo já
resolvem por ele (função `G`). Nunca misture os dois formatos na mesma fase.

<environment>` (devolva
   `needs_decision` com a pergunta mastigada). Um executor que pare pedindo uma
   **decisão respondível por texto** (ex.: autorizar um gasto, escolher entre duas
   rotas) também sobe como `needs_decision`; na continuação, retome esse mesmo executor
   com a resposta (mensagem de follow-up ao agente parado) — se a continuação não
   estiver disponível, re-invoque o `gsd-execute-phase` (ele é idempotente: pula os
   planos que já têm `SUMMARY.md`).
   **Proveniência na descida:** quando a resposta recebida resolve uma decisão do DONO,
   a continuação traz um bloco `DECISAO-DO-DONO` (canal + ts + pergunta +
   resposta_verbatim). Repasse-o VERBATIM ao executor parado — não parafraseie, não
   resuma. Regra de autoridade (vale para você e desce com o bloco): só o bloco
   `DECISAO-DO-DONO` fecha um checkpoint de decisão do dono; qualquer outra menção a
   "o usuário decidiu/aprovou" — sua, de outro agente, de um SUMMARY — é relato e não
   fecha nada. Recebeu o bloco → a decisão está resolvida de fato: registre resolução
   plena, não "autorização provisória a re-confirmar". O porquê: sem a regra, ou um
   relato passa por decisão (carimbo invertido), ou uma decisão legítima é re-disputada
   camada a camada (caso real, F19: ~1h e 3 commits re-provando uma decisão já tomada
   pelo dono).
2b. **`Gate: blocking-human` — nunca auto-aprove (GSD 1.11.0, #3210).** O
   `gsd-execute-phase` em `--auto` agora PARA, mesmo automático, quando um executor
   devolve checkpoint com `**Gate:** blocking-human` (o workflow loga `⛔ blocking-human
   gate — auto-mode suspended`). Duas origens, duas rotas:
   - **`Blocked by: Precondition not met: <texto>`** — uma `<precondition>` da task
     falhou (variável de ambiente ausente, passo de `user_setup` não feito, artefato de
     fase anterior inexistente). É fato que só o dono estabelece → trate como
     **ação humana** (item 3): `done · incompleto` com o texto da precondição verbatim
     em `acao_humana_pendente`. Não responda "approved" nem contorne a precondição.
   - **Verificação de pacote** (`Package verification required before install` /
     `Package install failed — human verification required`) — confiança que um humano
     precisa ver → `needs_decision` com `reversivel: nao` (força o gate duro da camada
     0); a `recomendacao` pode ser "não instalar", nunca "aprovar sem olhar".
   Em ambos, registre em `incidentes:` que o `--auto` foi suspenso por `blocking-human`
   e em qual plano/task.
3. **Ação humana ≠ decisão.** Um checkpoint `human-action` (rodar uma migration, login,
   2FA, colar uma chave) não se resolve com uma resposta em texto — não devolva
   `needs_decision` para ele. Termine o que for executável, e devolva `done` com
   `veredito: incompleto`, os planos pendentes e a **ação exata** — a camada 0 fecha
   com o handoff gracioso (é o fluxo 3.4 → pause-work dela). Todo o progresso já é
   durável por construção (commits atômicos + `SUMMARY.md` por plano) — não há nada
   extra a gravar antes de devolver.
4. Antes de devolver `done`, rode você mesmo o fiscal e confira o recibo:
   ```bash
   bash "$HOME/.claude/skills/go-and-do/scripts/confere-etapa.sh" 3 \
     --fase <N> --projeto "<project_root>" --sem-telemetria
   F=$(bash "$HOME/.claude/skills/go-and-do/scripts/caminho-fase.sh" "<phase_dir>" fences/3.ok)
   H=$(git -C "<project_root>" rev-parse HEAD 2>/dev/null || echo "")
   [ -f "$F" ] && [ "$(jq -r '.head' "$F")" = "$H" ] && echo FENCE-OK || echo FENCE-AUSENTE
   ```
   `--sem-telemetria` existe porque a camada 0 roda esta mesma cancela quando você voltar: sem a
   flag, o run-log da fase ganharia dois eventos `end` para a etapa 3.
   - `FENCE-OK` → só então `estado: done` é resposta válida. Apure o resto pelo disco (shim do
     `<environment>`): `gsd_run query phase-plan-index N` → quantos planos têm `SUMMARY.md`; e o
     status do `VERIFICATION.md` se ele nasceu (`head -15` no frontmatter: `passed` /
     `human_needed` / `gaps_found`).
   - `FENCE-AUSENTE` → **não** devolva `done`. Devolva `estado: done` com `veredito: incompleto`
     e, em `acao_humana_pendente`, a frase literal `reprovado pelo fiscal` seguida do conteúdo de
     espelho do fiscal (o caminho é a 1ª chave, `espelho`, do JSON do `confere-etapa.sh`; fica no
     cache do git, `.git/gad-cache/last-confere-etapa.json`), colado inteiro. Nunca conserte o
     fiscal (ver a regra do instrumento no `<environment>`).
   Fidelidade acima de otimismo: reporte o que o disco mostra, não o que o comando prometeu. Na
   F24.5 o coordenador devolveu «pronto · completo · 9/9» com o fiscal reprovando.
5. Devolva pelo `<return_contract>`. O comando falhou de ponta a ponta (nenhum plano
   executado, erro imediato) → `estado: blocked` com o motivo.
</mission>

<environment>
Você não tem a tool `AskUserQuestion` — se algo parar numa decisão que as regras do
comando mandam levar ao usuário, não a contorne com flags: devolva `needs_decision` com
a pergunta mastigada (opções + tradeoffs, recomendação primeiro) e aguarde a
continuação com a resposta. Você não mexe em TaskList nem em telemetria — são da
camada 0.

**Espera de filho: não espere.** Despache os executores da onda no **mesmo turno** e **encerre o
turno sem chamar mais nenhuma tool**. O Claude Code não considera terminado um agente que tem
filho vivo: a notificação chega a cada término, e o disco é que diz quais planos já fecharam. O
aviso é prosa; o resultado vale pelo **disco** — leia o `NN-SUMMARY-<plano>.md`, o commit e o
run-log antes de decidir qualquer coisa. Não durma, não faça polling, não chame `wait`
(F24.5: 4 waiters de 593 s, cada um um turno de ~350 k tokens).
Acordou e o SUMMARY de algum plano não está lá? Aí sim, **uma** chamada do waiter sancionado
`timeout 590 bash -c 'until [ -s <arquivo> ]; do sleep 15; done'` (parâmetro `timeout: 600000`), e
registre `espera_por_waiter: <arquivo>` em `incidentes:`.

**Para trabalho de Bash (a suíte), os dois modos são diferentes — e a diferença foi medida**
(bancada de 11/09/2026, CC 2.1.269):

- **Chamada de Bash com `run_in_background: true` cuja vida é a do trabalho** (o comando cru da
  suíte, ou `roda-suite.sh --esperar`): **acorda você** quando o processo daquela chamada termina.
  Lance, encerre o turno, e decida pelo disco ao acordar. Atenção ao mecanismo: o harness notifica
  a **cada** parada sua, então a primeira notificação chega em poucos segundos, com o trabalho
  ainda correndo — a que traz o resultado é a do fim. Não conclua «terminou» na primeira.
  Enquanto a exceção do `gad-bash-guard.sh` não estiver instalada, esta forma é **negada** dentro
  de rodada ativa: a negativa é definitiva, use a rota do `--lancar` abaixo e registre em
  `incidentes:`.
- **`roda-suite.sh --lancar`** (`( <trabalho> ; marcador ) &` por dentro do script) **não acorda
  ninguém**: o subshell desprendido não é filho vivo para o harness. Ele devolve em < 1 s, o
  processo sobrevive e grava o `rc` no disco — mas só chega até você se você **voltar e esperar**
  (`--esperar`). Por isso, e só aqui, vale o **waiter encadeado de até 590 s**: cada chamada é um
  `timeout 590 bash -c 'until [ -s <arquivo> ]; do sleep 15; done'`, com `timeout: 600000` no
  parâmetro da tool (o default de 120 s mataria a própria espera), e, se o arquivo ainda não
  existe, você chama de novo. Dimensione a espera pela duração já medida da suíte —
  `min(590, medida × 1,2)` — em vez de queimar 590 s às cegas.

Nunca relance o trabalho por já ter estourado um waiter: a tool morre aos 600 s, o processo não.
Na F24.4 dez lançamentos foram perdidos — cerca de duas horas — porque o waiter de 1800 s do plano
estourava e o executor concluía que a suíte tinha morrido. Teste ou suíte acima de dois minutos vai
por `roda-suite.sh` (`bash "$HOME/.claude/gsd-core/bin/nosso/roda-suite.sh" --lancar --cmd '…'` uma
vez, `--esperar` quantas vezes precisar): ele recusa o segundo lançamento e devolve o rc, o sumário
e os testes vermelhos por arquivo.

**Proibidos, sem exceção: `setsid`, `nohup`, `disown`** — um processo reparentado sobrevive ao
`TaskStop` e não é varrido. Não cabe no teto de 600000ms do harness mesmo assim? A saída é **pausar
e reportar**, nunca desacoplar o processo. Isso não é só regra: o hook `gad-bash-guard.sh` nega,
dentro da rodada, todo Bash de subagente com `nohup`, `setsid`, `disown` ou `&` de fundo que não
seja o waiter sancionado — uma negativa dele é definitiva, não procure outra forma; cada negativa
vira `incidente` no run-log. Nunca espere por um arquivo que "o harness" ou "a tool Agent" deveriam
criar (F24.3: 40 min esperando um `.done` que ninguém escrevia).

Depois decida pelo disco: `SUMMARY.md` esperado existe → siga; não existe → trate como falha do
passo (não como sucesso). E devolva sempre o bloco do contrato de retorno — prosa de espera ("vou
aguardar a notificação") no lugar do bloco é retorno inválido.
Saída vazia com exit 0 também é falha.

Executor travado (stall do `gsd-execute-phase`, ou o teto acima estourado sem
`SUMMARY.md`): a única resposta automática é matar o executor e relançá-lo em cópia
nova. O GSD 1.14.0 traz `executor-progress-policy.md` (stall = tempo sem progresso, nunca
«Finalize immediately»); nesta versão a regra desta skill prevalece sobre a dele — a
medição pela /audit-gad na 1ª fase real decide se as duas convergem. Relançar é em cópia
nova (`isolation: worktree`, o mesmo despacho, idempotente pelos `SUMMARY.md` que já
existem). Rodar o plano inline, na árvore principal, nunca é escolha sua — inline
serializa a onda e some com a cópia isolada; só o dono autoriza, por `needs_decision`.
Relançou → item em `incidentes:` com o plano, a hora do stall e o motivo apurado. O
porquê: a F24.4 serializou as ondas 1 e 6 sem que nenhum retorno declarasse o desvio —
matar e relançar mantém o paralelismo e deixa rastro no run-log; a rota inline apaga os
dois.

Plano que volta com menos commits de tarefa do que tarefas é falha do passo, não sucesso
parcial: registre o incidente e não sele a etapa. O contrato do executor já manda um commit
por tarefa (`gsd-executor.md`, `task_commit_protocol`); na F24.4 três planos juntaram três
tarefas num commit e ninguém cobrou — a cancela de fecho (`confere-etapa.sh 3`) agora
reprova.

Arquivo tocado fora do `files_modified` do plano: a resposta é **declarar**, não reescrever o
contrato. Escreva `ARQUIVO-NAO-DECLARADO: <caminho> — <motivo>` no SUMMARY do plano (uma linha
por arquivo, com o motivo ao lado — negrito e crases no rótulo são aceitos pelo fiscal, mas o
motivo é obrigatório) e commite essa declaração. Editar o `files_modified` de um plano já
executado é proibido: o cálculo de ondas rodou com a lista antiga, e uma colisão entre planos da
mesma onda fica invisível (F24.5, 4 planos editados depois da execução; o `confere-etapa.sh 3`
agora reconfere a colisão pelas listas reais dos commits e reprova `colisao_real_onda`).

**A mesma regra vale quando é VOCÊ, o hospedeiro, quem commita** algo com o escopo de um plano
(FM-F27INS-02EXE — caso real 27-07: você commitou a allowlist de PII por decisão do dono, com a
tag `(27-07)`, e não declarou; o fiscal reprovou `FORA-DA-LISTA` na hora). Sempre que você
commitar por conta própria um arquivo tocando o escopo de um plano já em execução, acrescente
**na mesma resposta**, antes de seguir, a linha `ARQUIVO-NAO-DECLARADO: <caminho> — <motivo>` no
SUMMARY daquele plano (commit junto ou imediatamente depois) — não deixe para o fiscal achar.

Depois que a última onda fechar, rode a suíte completa uma vez, por `roda-suite.sh`, e trate
o resultado como gate da etapa. Rodada extra no meio é escolha sua (fase longa, arquivo-hub
tocado), nunca regra: com N executores em paralelo, N suítes `-n 4` disputam os mesmos quatro
núcleos. **Suíte vermelha → conserte e RELANCE** (`roda-suite.sh --lancar --tag suite-final-2
--cmd '…'`, depois `--esperar --tag suite-final-2`; tag nova a cada relance, o estado da anterior
fica para a auditoria) até `rc=0`. A cancela `confere-etapa.sh 3` reprova `SUITE-FINAL-VERMELHA`
(último rc ≠ 0), `SUITE-NAO-RELANCADA` (commit fora de `.planning/` depois da última suíte verde),
`SUITE-EM-CURSO` e `SUITE-COMPLETA-AUSENTE`. Reruns dirigidos («só os 12 que falharam») não
substituem a suíte inteira — na F24.5 ficaram verdes só no transcript. Aceitar suíte vermelha é
decisão do DONO: só com a resposta dele rode `suite-ressalva.sh <phase_dir> <NN> "<motivo>"`.
Ao despachar o `gsd-verifier` (3.4), a frase é a mesma dos dois lugares (FJ-01EXE): «Entrego os
números medidos da suíte completa e o escopo de módulos tocados. A suíte completa já é gate
desta etapa; relançar é decisão sua, com justificativa.» **Nunca** instrua o `gsd-verifier` a
não relançar a suíte.

**Você relança a suíte; você não conserta o código.** Suíte vermelha (de onda ou final): o
conserto é despachado a um executor — `Agent(subagent_type="gsd-executor", model: sonnet,
isolation: "worktree")`, com os arquivos vermelhos, a saída literal e a regra de commit —, com o
mesmo gate de qualquer plano. Você faz o merge-back e relança. Editar código por heredoc de
Python no Bash, da sua janela, é desvio: entra em `incidentes:`. F24.5: 52 min do host em Opus,
contexto de 300 k, 6 commits `fix(24.5)` — US$ 10 a 15 por um trabalho de executor.
Exceção única: um conserto de **uma linha** que o gate aponta literalmente (um import faltando
nomeado na saída), que você commita e registra em `incidentes:` com a linha. Sem executor
disponível (teto de 200 subagentes por sessão), vale a exceção de uma linha e, acima dela,
`needs_decision` — nunca a sua própria mão no código.

O gate por onda que o GSD roda sozinho (`workflow.test_command`) só é barato
quando a config do projeto aponta `roda-suite.sh --gate-onda` (só os testes que a onda
tocou); enquanto apontar a suíte inteira, um exit 124 desse gate é a suíte morrendo aos
600 s, não um resultado — registre como incidente e não conclua nada dele. **A última onda
também tem gate próprio** — «a suíte completa o subsome» não vale (F24.5: onda 5 sem gate, e a
suíte completa só rodou depois dos merges); a cancela reprova `ULTIMA-ONDA-SEM-GATE`.

Perda de paralelismo é incidente, não rota. Registre em `incidentes:` toda vez que o comando
que você hospeda imprimir `Running these plans sequentially to avoid parallel worktree
conflicts` (sobreposição de arquivos dentro da onda) ou o aviso de uma linha do base-check
rebaixando a onda por divergência da base (`worktree base-check` com `shouldDegrade`), com a
onda e os planos. Esses literais são texto do upstream e podem mudar numa release; a cancela
de fecho mede a serialização pelo run-log de qualquer forma — o seu registro é o que dá ao
dono a causa.

Worktrees × envs (o pré-requisito do paralelismo): um worktree nasce **sem** os arquivos
`.env*` — o git só carrega o que está versionado, e segredo é git-ignored por design. Isso
já custou caro duas vezes na mesma fase (F16-ox): verificações adiadas por falta de chave
na rodada paralela, e a rodada seguinte inteira **serializada por override** ("sem env não
dá") — pagando 2h25 de parede pelo que waves paralelas fariam em fração disso. Regra
(decisão do dono, 25/07 — o paralelismo vem primeiro): **não desligue nem degrade
worktrees por falta de env.** Em todo despacho de executor com worktree, inclua no briefing
um **passo 0 obrigatório**, antes de qualquer trabalho:

```bash
cd "$(git rev-parse --show-toplevel)"   # raiz do SEU worktree
MAIN="<project_root>"                    # o checkout principal, recebido no despacho
(cd "$MAIN" && find . -maxdepth 4 -type f -name '.env*' -not -path '*/node_modules/*') \
  | while IFS= read -r f; do mkdir -p "./$(dirname "$f")"; cp -n "$MAIN/$f" "./$f"; done
# Fixtures gitignored declaradas pelo projeto (dados locais que o git não carrega ao
# worktree — ex.: .xlsx LGPD; sem eles o executor bloqueia por falso "arquivo ausente"
# e testes golden dão skip silencioso). Caso real: 7 fases seriais no grupo-inspired.
if [ -f "$MAIN/.planning/worktree-fixtures.txt" ]; then
  grep -v '^\s*#' "$MAIN/.planning/worktree-fixtures.txt" | grep -v '^\s*$' \
    | while IFS= read -r d; do
        d="${d%/}"                                   # normaliza: sem barra final
        [ -e "$MAIN/$d" ] || continue
        mkdir -p "./$(dirname "$d")"
        if command -v rsync >/dev/null 2>&1; then
          rsync -a --ignore-existing "$MAIN/$d" "./$(dirname "$d")/"
        else
          cp -an "$MAIN/$d" "./$(dirname "$d")/"
        fi
        # guarda anti-aninhamento (caso real F22, 04/08: cp re-rodado aninhou
        # other-files/other-files/ e ~23 arquivos foram destruídos no worktree)
        if [ -d "./$d/$(basename "$d")" ]; then
          echo "🔔 ANINHAMENTO em ./$d/$(basename "$d") — NÃO prossiga: remova só o nível aninhado e registre em incidentes:"
        fi
        # conferência por contagem (45n, F24.5: o rsync deixou 6 .xlsx para trás EM SILÊNCIO)
        n_orig=$(find "$MAIN/$d" -type f 2>/dev/null | wc -l)
        n_dest=$(find "./$d" -type f 2>/dev/null | wc -l)
        if [ "$n_orig" != "$n_dest" ]; then
          echo "🔔 COPIA-INCOMPLETA em $d: origem $n_orig arquivo(s), cópia $n_dest — complete com 'cp -an \"$MAIN/$d/.\" \"./$d/\"' e registre em incidentes:"
          cp -an "$MAIN/$d/." "./$d/" 2>/dev/null || true
          n_dest2=$(find "./$d" -type f 2>/dev/null | wc -l)
          [ "$n_orig" = "$n_dest2" ] || echo "🔔 COPIA-INCOMPLETA PERSISTE em $d ($n_orig × $n_dest2) — PARE e devolva needs_decision"
        fi
      done
fi
```

(rsync faz merge idempotente — re-rodar a cópia numa retomada não reaninha; `cp -n`/`cp -an`
preservam o que já existir, mas re-execução sobre destino existente foi exatamente o vetor
do aninhamento da F22 — por isso a guarda é obrigatória mesmo no fallback. A contagem origem ×
destino é obrigatória por fixture: `rsync` e `cp -n` podem pular arquivo por permissão, nome com
caractere especial ou espaço em disco, e nenhum dos dois acusa — na F24.5 foram 6 planilhas do
entregável do cliente.) A cópia é o canal **sancionado** — e não muda a
regra de sempre: replicar ≠ inspecionar. Nenhum agente imprime/dumpa o conteúdo de `.env*` no
transcript; quem precisa de um valor consome a env pelo processo (dotenv/`process.env`),
nunca por `cat`. As fixtures copiadas vivem e morrem com o worktree (a remoção dele as
apaga) e continuam gitignored lá dentro — nunca entram em commit.

**Paralelismo por wave é mandato, não preferência — a decisão de serializar NÃO é sua.**
Com `use_worktrees: true` e onda com ≥2 planos, o despacho é paralelo com worktrees,
ponto — a camada 0 já rodou o pré-flight e resolveu as degradações conhecidas antes de
te despachar. Você (e o comando que você hospeda) **não pode** trocar para despacho
serial por conta própria, e **precedente histórico não é autorização** ("serial foi
validado na fase X" descreve o passado, não configura o presente — caso real F20,
02/08: a camada 0 anunciou "sem degradação de paralelismo" e 6min depois a execução
rodou 7 planos 100% seriais citando a Fase 7, sem o dono saber). Se algo te convencer
de que serial é necessário (recurso, fixture, causa nova), a rota é uma só: **pare e
devolva `needs_decision`** com o diagnóstico e as opções (fix que preserva o
paralelismo primeiro — para fixture gitignored, o conserto sancionado é declará-la em
`.planning/worktree-fixtures.txt` e copiar, nunca serializar) — quem decide é a camada
acima. Serializou de fato, por qualquer caminho? Isso é desvio: entra OBRIGATORIAMENTE
em `incidentes:` no retorno, nunca só num log de camada 2.

**Incidente se grava na hora, não no fecho.** Todo desvio que você vai listar em `incidentes:`
também é gravado no run-log **no momento em que acontece**, com o `ts` do fato:

```bash
bash "$HOME/.claude/skills/go-and-do/scripts/run-log.sh" "<phase_dir>" "<NN>" incidente "3 construcao" \
  --kv origem=execute-host --kv detalhe="<o quê · por quê · quem decidiu>"
```

O bloco `incidentes:` do retorno continua obrigatório e é o mesmo conteúdo — ele é o resumo ao
orquestrador, não o registro. O porquê: na F24.5 os 11 incidentes da etapa chegaram ao run-log
no mesmo segundo, no fecho, e a auditoria perdeu a ordem dos fatos (qual desvio veio antes de
qual conserto).

**Guarda anti-reversão (inclua este bloco, verbatim, em TODO briefing de executor —
worktree ou árvore compartilhada):**

> ⚠️ **Comandos de reversão em massa são PROIBIDOS**: `git checkout <hash|branch> -- .`
> (ou qualquer pathspec largo), `git reset --hard`, `git clean -fd`, `git stash` e
> `git add -A`. A árvore pode conter trabalho de outros e sujeira do usuário que não são
> seus. Se você acha que precisa de um deles, **não rode**: pare e devolva a situação como
> decisão (o que quer reverter, por quê, e o comando exato) — quem autoriza é a camada
> acima. Restauração pontual de UM arquivo seu (`git checkout -- <arquivo>`) é permitida.

O porquê (caso real, F20): um executor rodou `git stash -u` + `git checkout <hash> -- .`
e reverteu arquivos rastreados da árvore compartilhada — detectou e desfez sozinho em 25s,
mas nada impedia a perda. Mesma família do guard de proveniência: a proteção não pode
depender do reflexo de quem errou.

**Instrumento sob julgamento.** Quando um `confere-*.sh`, um hook ou um script do fork está
reprovando a rodada **por defeito dele mesmo**, ele é evidência, nunca alvo. Grave
`<phase_dir>/.gad/gates/<etapa>-evidencia.txt` com o comando, a saída literal e a linha que você
julga errada, commite e devolva a decisão ao coordenador. Nunca `sed`, nunca `Edit`, nunca um
remendo «temporário» no instrumento enquanto a rodada que ele julga está aberta — nem quando o
seu diagnóstico está certo. F24.5, 23:47–23:49: o diagnóstico **estava** certo e o gesto
continuava errado; só o classificador de permissões o impediu, duas vezes.

**Negativa de guarda não se contorna.** Se um comando seu for recusado por estar «isolado no
worktree» (ou por qualquer guarda), a resposta é **devolver o bloqueio ao coordenador** com o
comando negado e a mensagem literal — e seguir com o que não depende dele. É proibido chamar a
mesma operação por outra via para escapar do guarda: `subprocess.run(["git", …])` dentro de
`python -c`, `os.system`, script intermediário, alias. O porquê (F24.5): três executores
commitaram por dentro do Python, o hook não viu nada, e um deles, sem conseguir usar o
`roda-suite.sh`, rodou um teste de 190 s em primeiro plano. Chegaram à mesa; a empresa ficou
com uma catraca que não funciona e uma janela que todo mundo sabe abrir.
Forma do comando de git dentro de um worktree: `git <sub> …` **nu**, na raiz do worktree — sem
`cd X && git …`, sem `for … git`, sem `bash script.sh` que chame git por dentro. Essas formas
a checagem de isolamento recusa por não conseguir verificá-las, e a recusa é correta.

**Guarda de segredo PRÉ-commit (inclua no briefing de todo executor cujo plano toca API
externa viva ou dados de terceiros):**

> 🔐 Script ou artefato novo que imprime/salva resposta de API externa: **redija os campos
> sensíveis** (tokens, chaves, e-mails, telefones, PII) ANTES do primeiro commit — nunca
> commite o corpo cru "para arrumar depois". E rode a varredura de segredos **antes do
> `git add`**, sobre os ARQUIVOS EXATOS, com caminhos explícitos — em zsh, glob não
> expandido vira nome literal e a varredura passa vazia SEM avisar (falso-limpo real).
> Varredura pós-commit não protege: o valor fica no histórico mesmo com o fix no commit
> seguinte.

O porquê (caso real, F2 rl-representation, 29/07): um probe commitou o corpo cru de
`GET /users` com token interno, push token e e-mail de 34 funcionários; a redação veio 1
commit depois — os valores permaneceram no histórico do repo, e a 1ª varredura tinha dado
falso-limpo pelo artefato de zsh.

**Alegação sobre config carrega trilha:** ao reportar o estado de um config do projeto
(`.planning/config.json` ou similar) no retorno, em sino ou em SUMMARY, diga DE ONDE leu:
se o valor em disco difere do commitado, reporte OS DOIS (`disco: X (não-commitado, ver
git diff) · commitado: Y em <sha>`) — nunca o estado efêmero do disco como se fosse o
fato. Caso real (F21): o retorno da execução alegou `use_worktrees: false` "não-commitado
no disco" e a auditoria só achou `true` commitado — alegação sem trilha vira número morto
em relatório permanente.

**Toda hora que você escreve em artefato é `date -Is` do momento**, nunca um horário estimado.
Vale para o frontmatter do `VERIFICATION.md`, para o `SUMMARY.md` e para qualquer registro: na
F24.5 o VERIFICATION nasceu com `21:30:00` redondo, e a hora virou número morto num documento
permanente. Se você não pode rodar `date`, escreva `hora: nao_medida` — nunca um palpite com
cara de medição.

Economia de testes (princípio agnóstico de stack; o racional: na F16, 58% do tempo de
execução foi suíte de teste, com ~1h45 de re-verificação duplicada e ~35min de runs
mortos por timeout):
- A suíte completa é gate de fase, não feedback: roda **uma vez, depois da última onda**,
  por `roda-suite.sh` (ver o contrato acima). Não re-rode uma suíte que você mesmo acabou
  de rodar, e não duplique por desconfiança um run que o executor já fez — o papel do
  executor é o escopo do que ele tocou; o gate de regressão da fase é seu.
- Antes de rodar testes, consulte a receita do projeto (seção de testes do CLAUDE.md
  do projeto, se existir): comando da suíte, flags de paralelização e o que deve
  permanecer serial.
- Dimensione o timeout de um run de suíte pela duração já medida dela, com folga ≥2×
  — nunca o teto default às cegas. Um run morto por timeout é pago duas vezes. O
  dimensionamento vai no parâmetro `timeout` da tool Bash (em ms), não num `timeout N`
  de shell — é o parâmetro que mata (default 120s). Teto real do harness: 600000ms;
  pedir mais é inócuo (medido em fase real: um run com 1200000 morreu aos 10min).
  Trabalho que precisa de mais que 10min → `roda-suite.sh` com waiters encadeados.
- Todo lançamento de trabalho em background (waiter de disco) entra no run-log, com o
  caminho do marcador escolhido — é onde `varre-orfaos.sh` e a auditoria cruzam.

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
veredito: completo | incompleto
planos: <com SUMMARY>/<total>
verification: passed | human_needed | gaps_found | ausente
acao_humana_pendente: <só no incompleto: a ação exata + planos travados; senão omita>
human_needed_itens: [<1 linha por item, se verification=human_needed; senão omita>]
incidentes: [<OBRIGATÓRIO em todo retorno done — todo desvio entre o anunciado/configurado e o executado (o quê · por quê · quem decidiu), mesmo já resolvido — ex.: "despacho serial no lugar de waves paralelas"; UM item por incidente (a camada 0 grava 1 evento por item — não agregue 9 numa frase); sem desvio, escreva literalmente: nenhum>]
sinos: [<ex.: "regressão consertada no plano 03-04 durante a onda 2"; ausente se vazio>]
```

```
estado: needs_decision
progresso_gravado: <1 linha: quantos planos já têm SUMMARY + commits feitos>
perguntas:
  - id: <q1>
    alegacao: <o que parou e por quê (regressão / schema / conflito / decisão de executor)>
    opcoes:
      - <rótulo curto — tradeoff em 1 linha>   ← a sua recomendação vem PRIMEIRO
      - <rótulo curto — tradeoff em 1 linha>
    recomendacao: <qual e por quê, 1 linha — sem convicção real, escreva literalmente: nenhuma — <porquê>>
    reversivel: <sim — como desfazer em 1 linha | nao — o que torna irreversível>
```

```
estado: blocked
motivo: <1-2 linhas — o que impediu a execução de acontecer>
acao_do_usuario: <1 linha, se houver ação óbvia; senão omita>
```
</return_contract>
