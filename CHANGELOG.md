# Histórico de versões

Todas as versões da go-and-do como produto próprio. Cada entrada diz qual GSD Core vai vendorizado dentro do pacote
(a cópia congelada e renomeada para o namespace `gad`), conferido por hash na montagem.

## [3.2.1] — 2026-10-05

Consertos feitos depois da publicação da 3.2.0, saídos do code review e do UAT da fase 6. O Core vendorizado não
muda: continua o **Core 1.15.0**, a mesma cópia conferida por hash desde a 3.1.0.

### Recibo perdido ou ilegível: sempre há um passo de saída

- Com o recibo da instalação (`<cfg>/go-and-do/recibo.json`) corrompido, ilegível ou de formato desconhecido, o
  `update`, o `uninstall`, o `install` e o `verify` recusam como antes, e agora dizem o passo de saída com o caminho
  da sua casa: mover o recibo para fora de `<cfg>/go-and-do`, apagar a pasta `<cfg>/go-and-do` (com `chmod -R u+w`
  antes, porque o runtime é só-leitura) e os arquivos `gad-file-manifest.json` e `.gad-profile`, e rodar o `install`.
  Se o `install` ainda recusar com «conflito de destino», o passo manda conferir o caminho nomeado: se for um atalho
  ou um arquivo do go-and-do, apague só ele; se for seu, mova-o para fora antes. O passo avisa também que apagar o
  `.gad-profile` devolve ao padrão a escolha feita com `/gad-surface`.
- O recibo sem runtime registrado, que a 3.2.0 grava quando o recibo foi apagado e o produto reinstalado, deixava o
  `install`, o `update` e o `verify` recusando em laço, um mandando para o outro. Agora os quatro subcomandos recusam
  esse recibo com o mesmo passo de saída. Antes, o `uninstall` dizia «desinstalado» e deixava o runtime, os ponteiros
  e os hooks do go-and-do ativos no `settings.json`.
- O `install` sem recibo (o recibo foi apagado) passa a reconhecer o que já é do go-and-do e confere com o pacote: o
  runtime, os ponteiros, os atalhos, os recibos do motor e os grupos de hook do pacote no `settings.json`, inclusive
  um hook opcional aceito antes. Com isso, o `verify` passa e o `uninstall` seguinte tira tudo; antes ficavam 27
  comandos de hook do go-and-do apontando para um runtime que já não existia.
- Sem recibo, o `install` não tem como saber se as pastas `skills/`, `agents/` e `go-and-do/`, o objeto `hooks` ou
  um evento de hook já eram seus antes da primeira instalação. Por isso ele não os toma como do go-and-do: o
  `uninstall` nunca apaga uma pasta ou uma entrada que estava lá antes. Pode sobrar uma pasta vazia ou um evento
  vazio (`[]`) do produto, que não fazem nada.
- Entraram testes de que o `uninstall` de um `update` interrompido recusa, sem remover nada, um link ou recibo do
  motor da versão anterior com caminho fora de `<cfg>`. O comportamento não muda.

### Documento único de intenção

- A marca do documento único (a linha 2 do `NN-CONTEXT.md`) é lida pela mesma regra nos cinco leitores: a linha sem
  o `\r` do fim e sem espaço ASCII (espaço, tab) nas pontas. Antes, um `CONTEXT` salvo com CRLF ou com um espaço
  sobrando era lido como fase antiga por um leitor e como documento novo por outro. Espaço Unicode (NBSP, U+3000)
  não conta como espaço em nenhum deles, qualquer que seja o idioma do terminal.
- O fecho do `/gad-discuss-phase` volta a registrar a versão aprovada do documento. Sem esse registro, a
  conferência que acusa um critério de aceite sumido do documento depois da aprovação nunca rodava nas fases novas.
- Quando o motor do go-and-do falta, a mensagem de erro do `/gad-discuss-phase` citava `go-and-do install` entre
  crases dentro de aspas duplas, e o shell **executava** o `go-and-do install` em vez de só mostrar o texto. Agora a
  mensagem só mostra o comando.
- Num projeto que já tinha usado o `/gad-spec-phase` antes da 3.2.0, o `/gad-discuss-phase` montava o mapa do código
  com o objetivo da fase antiga, que ficou guardado numa pasta escondida, e não com o da fase em discussão. Isso
  acontecia sem nenhum aviso, e a «Situação de hoje» da entrevista saía apontando para os arquivos errados. Agora o
  mapa usa sempre o objetivo da fase em discussão. A pasta antiga pode ser apagada à mão, mas não precisa: ela não é
  mais lida.

### Correção da nota da 3.2.0

- A nota da 3.2.0 lista `text` entre os modos do discuss que saíram. Só o arquivo do modo (`modes/text.md`) saiu: a
  opção `--text` do `/gad-discuss-phase` continua aceita, e faz as perguntas em lista numerada, sem menus.

### Texto do `/gad-discuss-phase` que ainda citava o comando que saiu

- Duas frases internas do roteiro do `/gad-discuss-phase` ainda diziam que a régua de clareza e as sondas de casos
  de borda e de proibições vinham do `/gad-spec-phase`, o comando que saiu na 3.2.0. A régua e as sondas continuam
  as mesmas: só a menção ao comando que saiu foi tirada. Uma instalação nova a partir deste repositório já vem sem
  essas menções; quem tem a 3.2.0 instalada as perde ao atualizar para a 3.2.1.

### Voltar para a v3.2.0

Se a 3.2.1 não servir, reinstale a versão anterior por cima, com o comando exato:

```bash
npx github:alencarfelipe10-ctrl/go-and-do#v3.2.0 update
```

## [3.2.0] — 2026-10-05

A intenção de uma fase passa a ser um **documento único**, aberto por um comando só. O Core vendorizado não muda:
continua o **Core 1.15.0**, a mesma cópia conferida por hash desde a 3.1.0.

### Core vendorizado

- `@opengsd/gsd-core 1.15.0`, sem alteração desde a 3.1.0.
- O manifesto do runtime (`dist/manifest.json`) registra `core.versao` 1.15.0 e `produto.versao` 3.2.0.

### O que muda para você

- **Um comando abre a intenção:** `/gad-discuss-phase NN`. Ele faz só perguntas de negócio e termina num documento
  único da fase, aprovado por você. Depois, `/go-and-do NN` leva a fase do plano ao fim a partir desse documento.
- **A `/go-and-do` começa direto na consultoria:** a etapa de intenção em três passos (spec, discuss e releitura
  separados) saiu; o plano, a execução e a verificação leem o documento único.
- **Saíram do produto:** o comando `/gad-spec-phase` (com o workflow e a skill dele), a skill `/gad-pre-spec`, os
  agentes de autoria `gad-spec` e `gad-discuss` e os modos do discuss que o comando único não usa (`advisor`, `all`,
  `analyze`, `auto`, `batch`, `chain`, `power`, `text`).
- **O for-humans saiu do fluxo da intenção:** nenhum passo da intenção gera mais a versão «para humanos».

### Voltar para a v3.1.1

Se a 3.2.0 não servir, reinstale a versão anterior por cima, com o comando exato:

```bash
npx github:alencarfelipe10-ctrl/go-and-do#v3.1.1 update
```

O `update` troca o runtime pelo da 3.1.1 e ajusta os hooks; o que você já escreveu nas fases (`.planning/`) fica.

Se esse `update` for interrompido no meio (o terminal fechou, a máquina desligou), rodá-lo de novo não conserta: ele
recusa e manda desinstalar. Rode `npx github:alencarfelipe10-ctrl/go-and-do#v3.1.1 uninstall` e depois
`npx github:alencarfelipe10-ctrl/go-and-do#v3.1.1 install`. A v3.1.1 não tem o conserto de queda da 3.2.0 (abaixo):
se o `install` recusar com «conflito de destino» nomeando um arquivo, esse arquivo é sobra do update interrompido —
apague só ele e rode o `install` de novo.

### Update interrompido no meio

- Um `update` para a 3.2.0 que cai no meio (o processo morto em qualquer ponto da troca) agora se conserta pelos
  comandos do produto: o `verify` acusa instalação incompleta, o `update` de novo recusa e manda desinstalar, e
  `npx github:alencarfelipe10-ctrl/go-and-do#v3.2.0 uninstall` seguido de
  `npx github:alencarfelipe10-ctrl/go-and-do#v3.2.0 install` deixa a casa instalada e conferida. Antes, o `uninstall`
  deixava para trás o `gad-file-manifest.json` (ou o `go-and-do/current`) da versão anterior e o `install` recusava.
  O que você mudou à mão continua ficando, com aviso.

### Pacote

- Instalação pela tag nova: `npx github:alencarfelipe10-ctrl/go-and-do#v3.2.0`.

## [3.1.1] — 2026-10-02

Versão de correções sobre a 3.1.0. O Core vendorizado não muda: continua o **Core 1.15.0**, a mesma cópia conferida
por hash na 3.1.0.

### Core vendorizado

- `@opengsd/gsd-core 1.15.0`, sem alteração desde a 3.1.0.
- O manifesto do runtime (`dist/manifest.json`) registra `core.versao` 1.15.0 e `produto.versao` 3.1.1.

### Correções

- O fiscal de etapas não acusa mais incidente tardio quando a etapa reabre no mesmo segundo ou num replan, e não dá
  recibo vencido depois de um merge squash.
- O aviso pelo Telegram enviado fora de uma rodada não grava mais evidência na fase errada.
- O gate de onda passa a rodar também os testes JavaScript (`node --test`).
- A mensagem da Etapa 1 da `/go-and-do` ficou mais clara.
- O instalador limpa os temporários órfãos deixados por uma instalação interrompida à força.

### Pacote

- Instalação pela tag nova: `npx github:alencarfelipe10-ctrl/go-and-do#v3.1.1`.

## [3.1.0] — 2026-10-02

Primeiro ciclo real de atualização do Core vendorizado: o **Core 1.15.0** foi absorvido pela receita de ciclo —
montar, triar, rebasear, remontar, conferir — sem regressão no script de prova da v3.0.0.

### Core vendorizado

- `@opengsd/gsd-core 1.15.0` (antes 1.14.0), tarball conferido por sha256
  `33cbfc408523e34a701209bf57c2f4b0e01a20f7a2289768ea6a56fa66fe4590` e pela `integrity` publicada no registro npm.
- O manifesto do runtime (`dist/manifest.json`) registra `core.versao` 1.15.0 e `produto.versao` 3.1.0.

### Mudanças que vêm do Core 1.15.0

- Inventário diferencial da instalação 1.14.0 × 1.15.0: 950 → 932 arquivos, 285 alterados, 11 novos e 29 removidos.
- Novidades da 1.15.0 mantidas no runtime: os passos novos do `execute-phase` (`code-review-disposition`,
  `ready-wave-gate`, `stale-reverification`, `threat-id-gate`, `worktree-base-check`), a convenção de identificador de
  fase (`phase-id-convention`) e as bibliotecas novas do motor que a acompanham.
- Saem do runtime os 29 `agents/*.compact.md`, retirados pelo próprio Core 1.15.0.
- O lançador do motor que a skill `/go-and-do` carrega (as cópias em `execute.md`, `close-phase/workflow.md` e
  `intent-discuss.md`) passa a ser a linha canônica do lançador da 1.15.0, sem sonda própria.

### Fork rebaseado

- O fork aplicado sobre o Core foi rebaseado por merge 3-way (`git merge-file --diff3`) só sobre as entradas
  marcadas na triagem: 16 arquivos, 8 fundidos sem conflito, 7 com conflito resolvido antes da remontagem e 1
  recebendo a cópia instalada da 1.15.0.
- A triagem na forma instalada classificou 64 linhas: 47 🟢 (sem ação), 6 🟡 e 11 🔴.

### Receita de ciclo

- Triagem feita sobre a instalação real das duas versões (não sobre o tarball cru).
- Inventário diferencial gravado por ciclo, com cada alteração explicada e o ruído do instalador separado.
- Teste de contrato: os 20 verbos do motor que a skill `/go-and-do` chama rodam nas duas versões e as respostas são
  comparadas campo a campo.
- A trava das entradas da montagem passa a guardar a versão do Core do ciclo; a remontagem é reproduzível a partir
  dela.

### Pacote

- Este `CHANGELOG.md` passa a ir dentro do pacote publicado.
- Instalação pela tag nova: `npx github:alencarfelipe10-ctrl/go-and-do#v3.1.0`.

## [3.0.0] — 2026-10-01

Primeira versão da go-and-do como produto próprio, isolado do GSD Core instalado na mesma máquina.

### Core vendorizado

- `@opengsd/gsd-core 1.14.0`, tarball conferido por sha256
  `9831fe309179021f82e01998108d43784625364a8a7af33efbfc7525b3da2d95`, com o fork do produto aplicado e tudo
  renomeado para o namespace `gad` (skills, agentes, hooks e o motor `gad-tools`) por script reproduzível.

### Produto

- Instalador `npx` com os subcomandos `install`, `update`, `uninstall`, `verify` e `doctor`.
- Runtime em `~/.claude/go-and-do/runtime/<hash>`, com `~/.claude/go-and-do/current` apontando para ele e o
  manifesto conferido na instalação.
- Hooks `gad-*` registrados no `settings.json` sem tocar nas entradas existentes; o `uninstall` remove só o que a
  go-and-do registrou no recibo dela.
- Convivência com o GSD Core: atualizar o Core instalado não muda nem quebra a go-and-do instalada.
