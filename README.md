# go-and-do

A **go-and-do** roda uma fase GSD de ponta a ponta sem você ficar de babá: intenção, contratos, plano, execução,
revisão de código, auditorias, UAT automatizado, resumo executivo e fecho. A partir da v3 ela é um produto próprio:
traz dentro dela uma **cópia congelada do GSD Core**, renomeada para o namespace `gad` (skills, agentes, hooks e o
motor `gad-tools`), junto com a skill `/go-and-do` e as irmãs dela.

O que isso garante: **atualizar o GSD Core instalado na mesma máquina não muda nem quebra a go-and-do instalada.** Os
dois convivem na mesma pasta de configuração do Claude Code, cada um com os próprios arquivos.

## Pré-requisitos

O `install` confere estes programas no `PATH` e para (saída 4) se faltar algum:

| Programa | Versão mínima |
|----------|---------------|
| Claude Code (`claude`) | 2.1.280 |
| Node.js (`node`) | 24 |
| `python3` | qualquer versão legível |
| `bash` | qualquer versão legível |
| `git` | qualquer versão legível |
| `gh` (GitHub CLI) | qualquer versão legível |
| `jq` | qualquer versão legível |

Você também precisa do `npm` (que traz o `npx`) para instalar.

Opcionais: `codex` e `agy`. Sem eles a instalação segue com um aviso, e a `/go-and-do` perde a consultoria externa
nas etapas que usam cada um.

Não é preciso instalar o GSD Core: a cópia que a go-and-do usa já vem dentro do pacote.

## Instalação

```bash
npx github:alencarfelipe10-ctrl/go-and-do#v3.2.0
```

O `#ref` (aqui a tag `v3.2.0`) é **obrigatório**: sem ele o npm instala o que estiver no branch padrão naquele
momento, e você deixa de saber qual versão tem. Sem subcomando vale `install`; para os outros, acrescente o nome no
fim, por exemplo:

```bash
npx github:alencarfelipe10-ctrl/go-and-do#v3.2.0 verify
```

O runtime vai para `~/.claude/go-and-do/runtime/<hash>`, com `~/.claude/go-and-do/current` apontando para ele, e os
hooks `gad-*` entram no `~/.claude/settings.json` sem tocar nas entradas que já existem. Reinicie o Claude Code depois
de instalar.

## Como usar

Para cada fase, dois comandos dentro do Claude Code:

1. `/gad-discuss-phase NN` — abre a intenção da fase: você responde só perguntas de negócio e sai com um documento
   único da fase, aprovado por você.
2. `/go-and-do NN` — leva a fase do plano ao fim a partir desse documento, começando direto na consultoria.

Ou seja: `/gad-discuss-phase NN` → `/go-and-do NN`.

## Voltar para a v3.1.1

Se a v3.2.0 não servir, reinstale a versão anterior por cima, com o comando exato:

```bash
npx github:alencarfelipe10-ctrl/go-and-do#v3.1.1 update
```

O `update` troca o runtime pelo da v3.1.1 e ajusta os hooks registrados pela go-and-do; o que você já escreveu nas
fases (`.planning/`) fica.

Se esse `update` for interrompido no meio (o terminal fechou, a máquina desligou), rodá-lo de novo não conserta: ele
recusa e manda desinstalar. Rode `npx github:alencarfelipe10-ctrl/go-and-do#v3.1.1 uninstall` e depois
`npx github:alencarfelipe10-ctrl/go-and-do#v3.1.1 install`. A v3.1.1 não tem o conserto de queda da v3.2.0: se o
`install` recusar com «conflito de destino» nomeando um arquivo, esse arquivo é sobra do update interrompido — apague
só ele e rode o `install` de novo.

## Se um update cair no meio

Um `update` para a v3.2.0 interrompido no meio deixa a instalação incompleta: o `verify` avisa, e rodar o `update` de
novo recusa e manda desinstalar. O caminho é desinstalar e instalar de novo:

```bash
npx github:alencarfelipe10-ctrl/go-and-do#v3.2.0 uninstall
npx github:alencarfelipe10-ctrl/go-and-do#v3.2.0 install
```

O `uninstall` tira o que é da go-and-do, da versão anterior ou da nova; o que você mudou à mão fica, com aviso.

## Comandos

| Subcomando | O que faz |
|------------|-----------|
| `install` | Instala o runtime, liga skills, agentes e motor e registra os hooks `gad-*` no `settings.json` |
| `update` | Troca o runtime pelo da versão do pacote e ajusta os hooks registrados pela go-and-do |
| `uninstall` | Remove só o que a go-and-do instalou e registrou no recibo dela; o que você mudou fica, com aviso |
| `verify` | Confere a instalação contra o manifesto do runtime, sem escrever nada |
| `doctor` | Relata a convivência com o GSD Core (presença, versão, vigias em dobro); só lê e sempre sai 0 |

Opções:

- `--config-dir <dir>`: só aceita `$HOME/.claude` (com ou sem barra final, ou um atalho que resolva para ele). Para
  instalar numa casa alternativa, troque o `HOME`: `HOME=<casa> npx github:alencarfelipe10-ctrl/go-and-do#v3.2.0`.
- `--dry-run`: mostra o que seria feito, sem escrever nada.
- `--opcional <script>` registra um hook opcional (`gad-rtk-worktree.sh` ou `notify-telegram.sh`); `--copiar-gsd`
  copia o seu `~/.gsd` para `~/.gad` durante o `install`.

### Códigos de saída

| Código | Significado |
|--------|-------------|
| 0 | ok |
| 1 | erro inesperado |
| 2 | uso inválido |
| 3 | casa ou `--config-dir` recusados |
| 4 | pré-requisito faltando |
| 5 | pacote ou manifesto inválido |
| 6 | `settings.json` inválido |
| 7 | conflito de destino |
| 8 | recibo ausente, incompleto ou inválido |
| 9 | `verify` reprovou |
| 10 | cópia de `~/.gsd` recusada |

## Convivência com o GSD Core

Resumo do `CONVIVENCIA.md` que vai com o runtime (depois de instalado, em `~/.claude/go-and-do/current/CONVIVENCIA.md`):

1. **Os vigias gad só agem em projeto marcado** (com `.planning/gad-projeto.json`, criado pela primeira rodada da
   `/go-and-do`). Fora dele ficam quietos.
2. **A go-and-do nunca edita o que é do Core**: nem as entradas de hook dele no `settings.json`, nem os arquivos dele.
   Atualizar ou desinstalar o Core também não muda o runtime da go-and-do.
3. **Num projeto gad, os vigias do Core continuam disparando junto**: um mesmo comando pode ser conferido duas vezes e
   um aviso pode aparecer em dobro. É um risco residual conhecido e aceito.
4. **O `doctor` relata a convivência**: se o Core está presente, a versão dele e cada vigia em dobro.

## Onde está a v2

A v2 (a skill instalada por `npx skills add`, que dependia do GSD Core instalado) continua disponível na tag
`v2.11.0` e no branch `skill-v2` deste repositório, inclusive com o `CHANGELOG.md` dela.

## Licença

MIT. O arquivo `LICENSE` traz dois avisos: o do código da go-and-do e o do GSD Core, cuja cópia renomeada está em
`dist/` (o aviso do Core também está inteiro em `dist/LICENSE`).
