# go-and-do

Skills de [Claude Code](https://claude.com/claude-code) que automatizam uma fase [GSD](https://opengsd.net) de ponta a ponta — da intenção ao Pull Request — sem você precisar babá-la.

Este repositório contém **três skills** que trabalham juntas:

| Skill | O que faz |
|-------|-----------|
| **go-and-do** | Roda uma fase GSD inteira: intenção (spec + discuss automáticos + consultoria especializada cross-AI) → planejamento → revisão cruzada do plano → execução → code review → auditorias de qualidade (UI/AI/segurança/Nyquist) → UAT automatizado interativo (um subagente dirige o navegador de verdade) → resumo executivo narrativo → fechamento com PR. |
| **close-phase** | Fecha uma fase depois do UAT: extract-learnings → promove a verificação → cria o PR. É invocada pela go-and-do na etapa de ship, mas também funciona sozinha. |
| **end-mile** | Finaliza um milestone: audit → summary → complete (com tag git). Gate do audit decide se pode arquivar. |

## Filosofia

- **Rigor máximo, sempre.** Toda fase passa pelo pipeline completo. O que não rodar (ferramenta ausente, gate de config desligado) é **declarado no resumo executivo** — nunca silencioso.
- **Orquestração em camadas.** Cada etapa verbosa roda numa janela descartável de subagente e devolve um status compacto — o orquestrador atravessa uma fase longa sem estourar o contexto.
- **Triagem de decisão.** Perguntas que você só carimbaria são auto-decididas e logadas em `NN-DECISOES.md` (com caminho de desfazer). Gates duros — informação que só você tem, mudança de escopo, ação irreversível — param e esperam. De madrugada (23h–07h), um gate duro vira pausa graciosa em vez de pergunta pendurada.
- **Retomável.** Rodou de novo, continua de onde parou. Tudo que importa vive em disco.

## Pré-requisitos

| Requisito | Obrigatório? | Notas |
|-----------|--------------|-------|
| [Claude Code](https://claude.com/claude-code) | ✅ Sim | É o runtime das skills. |
| Spawn aninhado de subagentes | Só configurar na CC 2.1.217–2.1.218 | A orquestração em camadas depende dele (a etapa despachada precisa spawnar os agentes GSD). **Na CC ≥ 2.1.219 vem ligado de fábrica** (profundidade 3) — não faça nada. Só as versões **2.1.217 e 2.1.218** o desligaram por padrão; nelas, defina `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=2` (ver [Instalação](#instalação)). ⚠️ Da 2.1.219 em diante essa env var **inverteu de papel**: ela só serve para *desligar* o aninhamento, e qualquer valor abaixo de 3 limita o padrão — se você a configurou no passado, **remova**. Sem aninhamento disponível, o spawn é negado e a skill **para e pergunta** se assume a etapa inline nesta rodada (funciona, mas a etapa roda na janela do orquestrador e consome o contexto dela). |
| [GSD (OpenGSD)](https://opengsd.net) ≥ 1.8.0 | ✅ Sim | `npx -y @opengsd/gsd-core@latest --claude` — as skills orquestram os comandos `gsd-*`. |
| `gh` (GitHub CLI) autenticado | Para o ship | Sem ele, a etapa de PR reporta bloqueio de ambiente e o resto da fase funciona. |
| [Codex CLI](https://github.com/openai/codex) e/ou Antigravity CLI (`agy`) | Recomendado | São os **revisores adversariais cross-AI** (revisão de intenção e convergência do plano). Sem nenhum dos dois, essas revisões são **puladas com aviso destacado no resumo executivo** (modo degradado) — a skill funciona, mas você perde a segunda opinião de máquina. |
| gsd-browser (MCP) | Recomendado | Motor do **UAT automatizado** (o subagente clica, preenche e prova no navegador). Sem ele, os cenários caem no balde "não pude verificar" e a fase faz hand-back para verificação humana (`/gsd-verify-work`). |
| Bot do Telegram + arquivo de config | Opcional | Alimenta o **[aviso no Telegram](#aviso-no-telegram-opcional)**: quando uma pergunta interativa ou um pedido de permissão fica pendurado esperando você, o celular pinga em segundos — em vez de a sessão esperar horas até você olhar o terminal. Sem o config, o script sai calado e nada muda. |

## Instalação

Com a CLI [`skills`](https://skills.sh):

```bash
npx skills add alencarfelipe10-ctrl/go-and-do
```

A CLI lista as três skills do repo — instale as três (a `go-and-do` invoca a `close-phase` na etapa de ship).

Instalação manual (alternativa):

```bash
git clone https://github.com/alencarfelipe10-ctrl/go-and-do.git
cp -r go-and-do/skills/* ~/.claude/skills/
cp go-and-do/agents/*.md ~/.claude/agents/
```

**Agentes `gad-*` (obrigatórios desde a v1.5.0):** a etapa de intenção despacha filhos
descartáveis (`gad-spec`, `gad-discuss`, `gad-explore`, `gad-verificador`) cujas definições
— modelo, effort e ferramentas — moram em `agents/`. Instale-os em `~/.claude/agents/`
(o `cp` acima; symlinks também funcionam). Sem eles o despacho do filho falha e a
intenção degrada para o fluxo inline antigo.

As etapas 1, 1.5, 2, 3, os gates (4.1/4.1b/4.4/4.5) e a rota A do close têm **hospedeiro próprio**
(`gad-intent`, `gad-contratos`, `gad-plan`, `gad-execute`, `gad-gates`), com modelo e effort pinados
na def e `experimental: cacheTtl: 1h` — o TTL longo é o que evita que a espera do hospedeiro
reescreva o cache a cada 5 minutos (medido na F24.5: o host da execução, então um `general-purpose`
sem def, escreveu 9,6 M de cache, 95,6 % em reescritas por expiração; bancada de 22/09 sobre 1.422
requests reais: o 1 h economiza 31–38 % nos hospedeiros). **As defs `gad-execute` (v2.6.0) e
`gad-gates` (v2.8.1) precisam estar instaladas antes da primeira rodada** e o Claude Code só carrega
defs novas **na abertura da sessão**:

```bash
ln -s "$(pwd)/go-and-do/agents/gad-execute.md" ~/.claude/agents/gad-execute.md
ln -s "$(pwd)/go-and-do/agents/gad-gates.md"   ~/.claude/agents/gad-gates.md
# e reinicie a sessão do Claude Code
```

Se o despacho de `gad-execute` falhar, isso é **erro de instalação**: pare e avise — não é motivo
para cair na rota inline.

**Spawn aninhado de subagentes** (ver [Pré-requisitos](#pré-requisitos)): na CC ≥ 2.1.219 já
vem ligado por padrão, com profundidade 3 — **não configure nada**. Se você tem
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` no `~/.claude/settings.json` de quando isso era
necessário, remova: nessa versão ela passou a servir só para *desligar* o aninhamento, e
qualquer valor abaixo de 3 vira um limitador.

Só nas versões **2.1.217 e 2.1.218** o aninhamento vinha desligado. Nelas, no
`~/.claude/settings.json`, dentro do bloco `env`:

```json
{
  "env": {
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "2"
  }
}
```

Vale a partir da próxima sessão do Claude Code. `2` é o suficiente: orquestrador (0) →
etapa despachada (1) → agentes GSD (2).

### Hook de telemetria `gad-lifecycle` (recomendado)

O run-log da fase registra o início/fim de **todo** despacho de subagente (com camada,
modelo e effort) por um hook do Claude Code — sem depender do modelo lembrar de anotar.

```bash
ln -s "$(pwd)/go-and-do/hooks/gad-lifecycle.sh" ~/.claude/hooks/gad-lifecycle.sh
```

E registre no `~/.claude/settings.json`, dentro de `hooks`, em três listas: `PreToolUse` e
`PostToolUse` com o matcher abaixo, e `SubagentStop` **sem matcher** (é ele que grava o fim real
do subagente — a tool `Agent` é assíncrona desde o CC 2.1.26x e o `PostToolUse` dispara no retorno
da chamada, não do agente):

```json
{
  "matcher": "Agent|Task|SendMessage",
  "hooks": [
    { "type": "command", "command": "bash \"$HOME/.claude/hooks/gad-lifecycle.sh\"", "timeout": 5 }
  ]
}
```
```json
{
  "hooks": [
    { "type": "command", "command": "bash \"$HOME/.claude/hooks/gad-lifecycle.sh\"", "timeout": 5 }
  ]
}
```

O hook é global mas só age quando encontra uma rodada `/go-and-do` ativa **da própria
sessão** (ponteiro `.planning/.gad/rodada-ativa.json`; o antigo `.planning/.gad-rodada-ativa.json`
ainda é lido por uma release); fora disso é no-op em
milissegundos. **Sem o hook a skill funciona normalmente** — o evento `run` registra
`hook_instalado: false` (o run-log fica sem os eventos `despacho`/`retorno`, e as
conferências que dependem deles viram informativas).

Atalho idempotente para o `SubagentStop` e para o `gad-gate-guard` (seção abaixo):
`bash hooks/registra-hooks.sh --dry-run` mostra o que faria; sem `--dry-run` faz backup do
`settings.json` e grava. Rode você mesmo, na sua sessão — a skill nunca edita o settings.

Para conferir a instalação (ao instalar ou atualizar a skill), sem gravar nada:
`bash hooks/registra-hooks.sh --confere` — exit 0 se o `gad-lifecycle.sh` existe em
`~/.claude/hooks/` e está em `PreToolUse`/`PostToolUse` (matcher com `Agent`) e `SubagentStop`;
exit 1 com uma linha `falta: …` por item faltante.

### Hook de cerimônia `gad-gate-guard` (recomendado)

`hooks/gad-gate-guard.sh` nega um `AskUserQuestion` dentro de uma rodada ativa quando (a) a hora
está na janela de silêncio (23h–07h) — a rota é a parada graciosa — ou (b) o `pre-gate.sh` não
rodou nos últimos 15 min para o HEAD atual (ele commita os artefatos da fase antes da pergunta).
Registro em `hooks.PreToolUse` com `"matcher": "AskUserQuestion"`, apontando para o clone:

```json
{
  "matcher": "AskUserQuestion",
  "hooks": [
    { "type": "command", "command": "bash \"$HOME/Projetos-Vox-AI/go-and-do/hooks/gad-gate-guard.sh\"", "timeout": 10 }
  ]
}
```

Registre só DEPOIS de atualizar a skill instalada para a v2.5.4 (o hook exige o `pre-gate.sh`
na árvore instalada; sem ele, toda pergunta real seria negada).

### Hook de guarda do Bash `gad-bash-guard` (recomendado)

Nega, dentro de uma rodada ativa, comando de subagente em segundo plano ou desprendido
(`run_in_background`, `nohup`, `setsid`, `disown`, `&` de fundo); só o waiter de disco
`( trabalho ; touch marcador ) &` passa. Fora de rodada, ou na sessão principal, é no-op.
Registre no `~/.claude/settings.json`, em `hooks.PreToolUse`, apontando para o clone
(caminho absoluto — `~/.claude/hooks/` é do GSD e some no update):

```json
{
  "matcher": "Bash",
  "hooks": [
    { "type": "command", "command": "bash \"/caminho/para/go-and-do/hooks/gad-bash-guard.sh\"", "timeout": 5 }
  ]
}
```

Cada negativa vira um `incidente` no run-log da fase.

### Hook `gad-rtk-worktree` (só quem usa o RTK como hook de Bash)

Se o seu `~/.claude/settings.json` tem um `PreToolUse`/`Bash` com `rtk hook claude`, ele
reescreve `git status` em `rtk git status`. Para um subagente com `isolation: worktree` a
checagem de isolamento do Claude Code **recusa** a forma reescrita («this command runs rtk with
a git command among its operands: what runs it, and from which directory, cannot be verified»),
e o subagente fica sem `git` dentro da própria cópia. Na F24.5 três executores contornaram
chamando git por `subprocess.run` dentro de Python — invisível para qualquer guarda.

`hooks/gad-rtk-worktree.sh` é um envelope: dentro de um worktree de agente devolve `allow` **sem
reescrita** (o comando chega ao harness como o modelo o escreveu); fora dele delega ao
`rtk hook claude` e repassa a saída byte a byte. Detecta o worktree pelo caminho
(`*/.claude/worktrees/*`) **e** pelo critério robusto de git (`--git-dir` ≠ `--git-common-dir`).

Para instalar, **troque** a entrada `rtk hook claude` do seu `PreToolUse`/`Bash` por:

```json
{ "type": "command", "command": "bash \"/caminho/para/go-and-do/hooks/gad-rtk-worktree.sh\"" }
```

Custo: dentro dos worktrees você perde a compactação de saída do RTK (saída de `git log`/`diff`
entra inteira no contexto do subagente — use sempre `--format`/`-n`). Sem o envelope, os
executores seguem sem `git` dentro do worktree. A troca é **do dono**: a skill nunca edita o
`settings.json`.

## Aviso no Telegram (opcional)

Quando o Claude Code para e espera você — uma pergunta interativa (`AskUserQuestion`) ou um
pedido de permissão — a sessão fica pendurada até você voltar ao terminal. O script
[`tools/notify-telegram.sh`](tools/notify-telegram.sh) fecha esse buraco: um aviso chega no seu
Telegram em segundos, com o texto da pergunta e as opções. Entre **23h e 07h** a mensagem chega
**muda** (sem som nem vibração) — você não perde nada e não acorda por nada.

Setup em três passos:

1. **Crie o bot**: no Telegram, fale com o [@BotFather](https://t.me/BotFather), mande `/newbot`
   e guarde o **token** que ele devolve. Depois abra o chat do seu bot novo e mande `/start`.
2. **Descubra seu `chat_id`**: `curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates"` — é o
   número em `message.chat.id`.
3. **Grave as credenciais** (fora de qualquer repo) em `~/.config/telegram-notify/config`, com
   `chmod 600`:

   ```
   TELEGRAM_BOT_TOKEN=...
   TELEGRAM_CHAT_ID=...
   ```

E ligue o hook no `~/.claude/settings.json` (ajuste o caminho para onde você clonou o repo):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"/caminho/para/go-and-do/tools/notify-telegram.sh\"",
            "timeout": 30,
            "async": true
          }
        ]
      }
    ]
  }
}
```

Notas de comportamento: o aviso vale para **qualquer sessão** do Claude Code, não só para a
go-and-do (o gatilho é o hook `Notification` do próprio CC — perguntas interativas disparam como
`permission_prompt`). Se a pergunta vem de uma fase da go-and-do, a mensagem ganha a fase e a
etapa correntes (lidas do `NN-RUN-LOG.jsonl`). E o script **nunca atrapalha a sessão**: sem
config, sem `jq` ou sem rede, ele sai calado com exit 0.

## Uso

Dentro de um projeto GSD (com `.planning/` e fase no ROADMAP):

```bash
/go-and-do 3                 # roda a fase 3 inteira, até o PR
/go-and-do 3 --no-ship       # para depois do UAT, sem criar PR
/go-and-do 3 --ui            # inclui contrato de design de UI (UI-SPEC)
/go-and-do 3 --ai            # inclui contrato de design de IA (AI-SPEC)
/go-and-do 3 --vault perfil  # UAT com login via vault do gsd-browser
/go-and-do 3 --obs "texto"   # nota repassada a todas as etapas da rodada
```

Fase interrompida? Rode o mesmo comando de novo — ela retoma de onde parou.

Depois do milestone completo:

```bash
/end-mile
```

## O que a skill grava na `.planning/`

Duas pastas ocultas com o mesmo nome e papéis opostos — leia a diferença antes de mexer:

| Pasta | O que guarda | Git |
|---|---|---|
| `.planning/.gad/` (raiz) | **Estado efêmero da rodada**: `rodada-ativa.json` (o ponteiro que os hooks procuram), `dev-server.{json,log}`, `worktrees-arquivo/` e os 4 espelhos que algum script lê para decidir (`last-pre-despacho.json`, `last-pre-despacho-3.json`, `last-pre-gate.json`, `last-plan-gate.json`) | **ignorada** — a skill grava ali um `.gitignore` com `*`, sem tocar no `.gitignore` do projeto |
| `.planning/phases/NN-x/.gad/` (uma por fase) | **Evidência da rodada**: `intent/c<N>/…` (lanes, tabela, vereditos, correções e releituras de cada ciclo), `convergencia/c<N>/…`, `lanes/` (espelhos e marcadores das lanes Codex/agy), `fences/<etapa>.ok` (recibo do fiscal), `gates/<etapa>-evidencia.txt` (evidência de gate; a trava de gate reprovado mora em `.planning/.gad/gates/<pasta da fase>/<etapa>.json`, ignorada), `plan-checker/`, `pos-ship/`, `uat/` e o marcador `FORMATO` | **commitada** — o fiscal cobra (`commita-artefatos.sh … evidencia`); só `lanes/codex-*` e `lanes/*.launch.log` ficam fora, pelo `.gitignore` da própria pasta |

- As **cópias contra o corte do RTK** (`last-<script>.json` de todo script) moram no cache do git,
  `.git/gad-cache/` (numa worktree, `.git/worktrees/<nome>/gad-cache/`, que some com ela; fora de
  repositório git, `$XDG_CACHE_HOME/gad/<projeto>-<hash>/`). Nunca aparecem no `git status`. O
  caminho sai como primeira chave (`espelho`) do JSON de cada script.
- **Fase nova × fase antiga.** Quem decide é o `abre-rodada.sh`: fase sem nenhuma evidência no
  formato antigo nasce com `.gad/FORMATO` (commitado na abertura, com `git commit --only` — o que
  você tiver staged fica como estava). Fase que já tem evidência antiga (`.intent/`, `.fence-*.ok`,
  `pareceres/.roda-*`…) continua no formato antigo até o fim: uma fase nunca mistura os dois. Os
  scripts, os hooks e a `/audit-gad` leem os dois. Para ver a tradução nome novo → antigo:
  `bash ~/.claude/skills/go-and-do/scripts/caminho-fase.sh --tabela`.
- **Limpeza automática.** A cada abertura, o `abre-rodada.sh` apaga os `.planning/.gad-last-*.json`
  órfãos (convenção anterior a 2026-08), o ponteiro antigo e as cópias velhas em `.planning/.gad/`
  — **só o que não está no git**. O que está rastreado sai listado em `legado_rastreado` e a skill
  não mexe no índice. Para tirar do índice de uma vez (os arquivos continuam no disco e o
  `.gitignore` da pasta passa a ignorá-los):

  ```bash
  git rm -r -q --cached .planning/.gad && git commit -m "chore: .planning/.gad fora do git (go-and-do 2.10.1)"
  ```

## Atualização

```bash
npx skills check    # há versão nova?
npx skills update   # atualiza
```

Veja o [CHANGELOG.md](CHANGELOG.md) antes de atualizar.

## Transparência e modo degradado

A regra de ouro da skill: **um passo que não roda nunca é silencioso.** Cada degradação (revisor externo ausente, browser indisponível, gate de config desligado) gera um item no bloco de transparência do resumo executivo, com o motivo. Você sempre sabe o que a fase *não* verificou.

## Licença

[MIT](LICENSE)
