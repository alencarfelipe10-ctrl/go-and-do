Apply response_language to all user-facing prose — narration between tool calls, status updates, progress notes, and findings included; preserve code, paths, and identifiers.

# Entrevista de negócio — o roteiro do /gad-discuss-phase

> **Lido uma vez**, no `initialize` do `workflows/discuss-phase.md`: toda rodada do comando único é interativa
> (sem dono, a barreira para antes). Aqui estão as telas de pergunta e as falas ao dono; a regra que as governa é a
> `<regra_da_entrevista>` do workflow, e as gravações são as do passo `interview`.

## Quem é quem

O dono decide o negócio: o que é entregue, o que fica público, o que é irreversível, custo, prazo e risco de perder
algo. Ele não tem formação técnica e segue a recomendação do modelo em toda escolha técnica. O modelo constrói e
decide sozinho todo o resto — arquitetura, bibliotecas, formato interno, como testar — e escreve isso em «A critério
do planner» quando vale registrar.

## A tela de perguntas

- São até 4 perguntas por tela, cada uma com até 4 opções.
- Cada opção traz um rótulo curto (a escolha) e uma descrição com: o que muda na prática · a consequência · e, na
  recomendada, a palavra «recomendo» e o porquê em uma linha. A recomendada vem primeiro.
- Só vira pergunta o que muda algo que o dono sente. O que o modelo resolve sozinho não vira tela.
- O texto da pergunta e das opções nunca cita arquivo, função ou ferramenta, nem id (`D-NN`, `R-n`, `AC-nn`):
  fala da consequência, em linguagem leiga. Exemplo: em vez de «a tag pública depende do gate de prova?», pergunte
  «a versão nova só sai para o público depois de provada, mesmo que isso atrase a entrega?».
- Quando a escolha sair caro ou sem volta, pergunte na mesma tela por quê aceitar o custo: essa frase vai ao depósito
  como justificativa (`--reversibility costly|one-way --reversibility-rationale-file`).
- Pergunta que só o cliente responde: redija-a para o dono encaminhar e espere a resposta.

## Depois de cada resposta

A resposta vai ao depósito assim que é dada, antes da próxima pergunta (`checkpoint-write.py add-decision "$CKPT"
--origin owner …`, forma completa no passo `interview` do workflow): a pergunta, as opções mostradas, a escolhida e a
resposta como o dono quis dizer. Só o dono decide; o depósito não aceita outra origem.

- «Você decide» / «tanto faz» não é decisão: vira uma linha em «A critério do planner».
- «Isso fica para depois» é resposta: vira pendência, com o motivo.
- Ideia fora do escopo da fase: «[ideia] seria uma entrega nova — fica anotada para uma fase futura. Voltando a
  [tema]: …». Vai para «Pendências e ideias adiadas»; não se discute agora.
- Quando o dono citar um documento, leia-o (ou confirme que existe) na hora e acrescente-o às referências.

## Respostas vazias

Resposta vazia ou só com espaços: «Outro» sem texto → escreva «O que você quer dizer?», pare e espere a mensagem
dele. Qualquer outra resposta vazia → repita a pergunta uma vez; se vier vazia de novo, mostre as opções como lista
numerada em texto. Nunca siga com resposta vazia.

## Sem menus (`--text`)

Com `TEXT_MODE=true` (o dono rodou com `--text`), não use AskUserQuestion: mostre as mesmas perguntas como
lista numerada em texto normal, com as mesmas opções, consequências e «recomendo», e aceite a resposta por número ou por
extenso.

## Retomada

Estado `retomar` (a conversa caiu no meio): conte ao dono, em linguagem leiga, o que já ficou decidido e o que falta,
sem id e sem arquivo. Exemplo: «Da última vez você já decidiu que o relatório sai com as mesmas colunas da tela e que
o arquivo fica só na sua máquina. Falta decidir o que acontece num mês sem lançamentos. Vamos seguir daí.» Nada que
já tem resposta é perguntado de novo.

## Documento existente

Estados `existe-novo` / `existe-antigo` — uma tela, nada muda antes da resposta. Diga o que existe e pergunte se
refaz:

- formato novo: «Esta fase já tem uma especificação aprovada por você. Quer refazer?» — opções: «Manter a atual»
  (recomendo, se nada mudou: ela continua valendo e nada é gravado) · «Refazer» (a atual só é trocada quando você
  aprovar a nova; até lá ela continua valendo).
- formato antigo: «Esta fase tem um documento de intenção num formato antigo, de antes do comando único. Quer
  refazer?» — opções: «Refazer» (recomendo: o documento novo traz só as suas decisões e o planner lê melhor; o atual
  só é trocado quando você aprovar o novo) · «Manter o antigo» (nada é gravado).

## Fase fora do plano

Fase que ainda não está no ROADMAP: «Essa fase ainda não está no plano do projeto. Como ela se chama, em poucas
palavras, e depois de qual fase ela entra?» — opções: as fases vizinhas, com a recomendada primeiro e o porquê. Se o
número que o sistema der for outro, diga: «a fase ficou com o número X».

## Aviso de ambiguidade

Quando a régua interna não passa: «Ainda há pontos vagos: [o que falta, em uma linha cada]. Se eu gravar assim, quem
planeja vai ter de supor isso. Recomendo responder mais [N] perguntas antes de gravar. Quer seguir com as perguntas
ou gravar assim mesmo?» Sem número de nota. Só grave com a ordem dele.

## Pergunta de gravação

Depois da explicação do passo `write_context` (o que a fase entrega, o que fica de fora, o que você decidiu, o que
ficou como suposição): «Posso gravar a especificação assim?» — opções: «ok, pode gravar» · «Quero mudar algo». Só um
«ok» explícito grava; qualquer outra resposta volta à entrevista.
