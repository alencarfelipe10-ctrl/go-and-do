# go-and-do

Skills de [Claude Code](https://claude.com/claude-code) que automatizam uma fase [GSD](https://opengsd.net) de ponta a ponta — da intenção ao Pull Request — sem você precisar babá-la.

Este repositório contém **três skills** que trabalham juntas:

| Skill | O que faz |
|-------|-----------|
| **go-and-do** | Roda uma fase GSD inteira: intenção (spec + discuss automáticos + revisão adversarial cross-AI) → planejamento → revisão cruzada do plano → execução → code review → auditorias de qualidade (UI/AI/segurança/Nyquist) → UAT automatizado interativo (um subagente dirige o navegador de verdade) → resumo executivo narrativo → fechamento com PR. |
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
| Spawn aninhado de subagentes | Só configurar na CC 2.1.217–2.1.218 | A orquestração em camadas depende dele (a etapa despachada precisa spawnar os agentes GSD). **Na CC ≥ 2.1.219 vem ligado de fábrica** (profundidade 3) — não faça nada. Só as versões **2.1.217 e 2.1.218** o desligaram por padrão; nelas, defina `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=2` (ver [Instalação](#instalação)). ⚠️ Da 2.1.219 em diante essa env var **inverteu de papel**: ela só serve para *desligar* o aninhamento, e qualquer valor abaixo de 3 limita o padrão — se você a configurou no passado, **remova**. Sem aninhamento disponível, a skill detecta via probe e cai no **fallback inline** (funciona, mas as etapas rodam na janela do orquestrador e consomem o contexto dela). |
| [GSD (OpenGSD)](https://opengsd.net) ≥ 1.8.0 | ✅ Sim | `npx -y @opengsd/gsd-core@latest --claude` — as skills orquestram os comandos `gsd-*`. |
| `gh` (GitHub CLI) autenticado | Para o ship | Sem ele, a etapa de PR reporta bloqueio de ambiente e o resto da fase funciona. |
| [Codex CLI](https://github.com/openai/codex) e/ou Antigravity CLI (`agy`) | Recomendado | São os **revisores adversariais cross-AI** (revisão de intenção e convergência do plano). Sem nenhum dos dois, essas revisões são **puladas com aviso destacado no resumo executivo** (modo degradado) — a skill funciona, mas você perde a segunda opinião de máquina. |
| gsd-browser (MCP) | Recomendado | Motor do **UAT automatizado** (o subagente clica, preenche e prova no navegador). Sem ele, os cenários caem no balde "não pude verificar" e a fase faz hand-back para verificação humana (`/gsd-verify-work`). |

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
```

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
