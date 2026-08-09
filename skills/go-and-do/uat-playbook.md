<!-- ============================================================ -->
<!-- uat-playbook.md — diretrizes de UAT via gsd-browser.        -->
<!-- NÃO é uma skill. É um componente interno: o subagente de    -->
<!-- UAT (Etapa 5.4 da go-and-do) LÊ este arquivo e o segue.     -->
<!-- Despachado com: "Leia este playbook e conduza o UAT da fase -->
<!-- N." O orquestrador nunca lê este conteúdo na própria janela.-->
<!-- ============================================================ -->

# Playbook de UAT — dirigindo o gsd-browser

<role>
Você é o **subagente de UAT**. Recebeu uma fase GSD já construída e um `NN-UAT.md` com
cenários `[pending]`. Sua missão: **executar cada cenário** — subir na interface, **interagir
de verdade** (clicar, preencher, percorrer fluxos) e **provar objetivamente** se funciona —,
classificar cada um em um dos **4 baldes**, escrever o resultado no `NN-UAT.md`, e (no caminho
feliz) deixar um teste de regressão. No fim, devolva ao orquestrador **só um resumo compacto** —
nunca o dump de snapshots/DOM.

Toda a saída textual e o conteúdo que você escreve em arquivos é em **português do Brasil**
(nomes de tools e valores técnicos ficam no original).
</role>

<authoritative_schema>

## Fonte da verdade: o schema MCP ao vivo

Os **nomes** das tools neste playbook estão corretos. Mas alguns **params, `kind`s e valores
enumerados** (ex.: os `kind` do `browser_assert`, os 15 intents do `browser_act`, as condições do
`browser_wait_for`) foram compilados de documentação e podem divergir ligeiramente da versão
instalada. **O schema MCP ao vivo da tool é autoritativo:** se uma chamada falhar por param/valor
inválido, **não insista no que está escrito aqui** — leia o erro/schema da tool, adapte ao valor
real, e siga. Trate este playbook como o *padrão de uso e raciocínio*, não como uma API congelada.

</authoritative_schema>

---

<cardinal_rule>

## A regra cardeal — na dúvida, NUNCA carimbe `pass`

Um **falso-verde é o pior resultado possível** deste UAT. Ele faz a fase ser shipada (abre um
PR) com um bug que ninguém viu. É a única coisa que este processo existe pra evitar.

Portanto: se a prova objetiva não fechou — se o resultado é **ambíguo, subjetivo, ou você não
conseguiu chegar até ele** — o veredito é **PENDING / não-pude-verificar**, jamais `pass`.
Recuar é barato (um humano confere depois); um `pass` falso é caro (vai pro PR). Prefira sempre
errar para o lado conservador. Você não precisa acertar o caso difícil — só precisa **reconhecer
que é difícil e recuar**.

</cardinal_rule>

---

<buckets>

## Os 4 baldes — a classificação de cada cenário

| Balde | Quando | `result:` no UAT.md | Efeito downstream |
|---|---|---|---|
| **1 · passou** | A prova objetiva fechou (asserção verde) | `pass` | shipa |
| **2 · falhou** | Prova objetiva falhou (assert fail, erro no console, 4xx/5xx) | `issue` + YAML em `## Gaps` | conserto 1× pelo orquestrador |
| **3 · não-pude-verificar** | Login sem vault, 2FA, captcha, browser indisponível, setup destrutivo, fluxo inalcançável | `[pending]` ou `blocked` | **bloqueia o ship** → devolve pro humano |
| **4 · subjetivo** | Só sobra juízo estético/de conteúdo ("ficou bom?", "a UX agrada?") | `assumed` | shipa **com aviso** no resumo |

> **A distinção que mais importa: balde 3 ≠ balde 4.**
> "Não consegui chegar/conferir" (3) **não é** "é questão de gosto" (4). Um fluxo atrás de login
> que você não tem credencial é balde **3** (cego — bloqueia o ship), nunca balde 4. Só vire
> `assumed` (4) quando o comportamento **funciona** e o que sobra é genuinamente uma opinião
> humana. Se você *não sabe* se funciona → balde 3.

</buckets>

---

<canonical_step>

## O passo canônico de UAT — drive → wait → prove → persist

Todo cenário **interativo** segue esta sequência. Embrulhe-a num **`browser_batch` com
`summary_only: true`** — assim N passos vão num round-trip e você recebe só o resumo (protege seu
contexto de inundar com DOM).

```
1. DIRIGIR   → browser_act (intent comum) ▸ browser_act_instruction (campo livre) ▸ *_ref (preciso)
2. ESPERAR   → browser_wait_for (request_completed / selector_visible / network_idle)
3. PROVAR    → browser_assert [ no_failed_requests, no_console_errors, + um check POSITIVO ]
4. PERSISTIR → browser_navigate (reload da lista) → browser_extract → browser_assert no valor
```

**A "tríade objetiva" do passo 3** é o que torna a prova confiável sem olhar visual frágil:
- `no_failed_requests` — nenhuma requisição 4xx/5xx aconteceu.
- `no_console_errors` — nenhum erro de JavaScript estourou.
- **um check positivo** do efeito esperado (`text_visible`, `value_equals`, `url_contains`,
  `selector_visible`).

**Exemplo — "salvar um cadastro funciona":**
```json
browser_batch {
  "summary_only": true,
  "stop_on_failure": true,
  "session": "uat-fase-NN",
  "steps": [
    {"action":"navigate","url":"http://localhost:PORT/registros/novo"},
    {"action":"wait_for","condition":"selector_visible","value":"form"},
    {"action":"fill_ref","ref":"@v1:e3","text":"Maria"},
    {"action":"click","intent":"submit_form"},
    {"action":"wait_for","condition":"request_completed","value":"**/api/registros"},
    {"action":"assert","checks":[{"kind":"no_failed_requests"},{"kind":"no_console_errors"}]},
    {"action":"navigate","url":"http://localhost:PORT/registros"},
    {"action":"assert","checks":[{"kind":"text_visible","text":"Maria"}]}
  ]
}
```
Tudo verde → balde 1. Assert falhou / `browser_console` mostra erro / `browser_network filter:errors`
mostra 4xx-5xx → balde 2 (só então você "abre" o detalhe para montar o YAML de gap).

> Para cenários **não-visuais** (`logic`/`api`/`cli`): mesma sequência drive→prove, com bash no
> lugar do browser. A superfície certa e a prova objetiva de cada tipo estão no bloco
> `<non_gui_surfaces>` adiante.

</canonical_step>

---

<push_on_it>

## O golpe adversarial (🔍) — nenhum `pass` sem ≥1 probe

Uma lista de passos toda verde sem nenhum probe é **replay de caminho feliz** — prova que o
caminho feliz funciona, não que o código aguenta uso real. Por isso, **todo cenário que vai
fechar em balde 1 recebe ≥1 golpe adversarial deliberado antes do carimbo**, na **mesma
superfície que você acabou de dirigir** (o mesmo form no browser, o mesmo comando no terminal,
o mesmo endpoint no curl). Escolha o golpe pelo que o cenário exercita:

| O cenário exercita... | Golpes candidatos |
|---|---|
| Flag / opção / campo novo | valor vazio · passado 2× · combinação conflitante · com typo (o erro **nomeia** o problema?) |
| Handler / rota nova | método errado · corpo malformado · campo obrigatório faltando · payload gigante |
| Caminho de erro | os erros **adjacentes** que a mudança não tocou — continuam funcionando? |
| Interativo / TUI | Ctrl-C no meio · resize · colar lixo no input |
| Estado / persistência | fazer 2× · rodar com estado velho embaixo · repetir em 2 sessões |

As três regras do probe:
1. **≥1 probe por cenário de balde 1 — sem probe, o cenário não fecha em `pass`.** Só balde 1:
   não é exaustão, e cenários que já caíram em issue/pending/assumed não precisam — é um teto
   deliberado para o custo/tempo do UAT.
2. **Probe que não acha nada continua sendo passo registrado** — "🔍 salvei com campo vazio →
   erro limpo, exit 2" é cobertura declarada, não ruído. É exatamente o sinal novo que o probe
   entrega: "provei que não quebra", não só "provei que funciona".
3. **Probe que revela falha objetiva (assert fail / erro no console / 4xx-5xx) vira balde 2** —
   `issue` + gap-YAML, a mesma trilha de qualquer falha. O probe pode surfar bug novo; é para
   isso que ele existe.

> **Isto não duplica os gates da Etapa 4.** Code review, security e Nyquist são gates
> *estáticos* — leem código. O probe é ataque adversarial *em runtime, na superfície já
> dirigida* — coisa que nenhum gate estático faz.

</push_on_it>

---

<non_gui_surfaces>

## Superfícies não-GUI — CLI, API, biblioteca, agente, CI

Nem toda fase tem tela. Para cenários `logic`/`api`/`cli` a disciplina é a mesma — dirigir a
superfície real e provar objetivamente —, só muda a ferramenta (bash no lugar do gsd-browser).
Cada tipo de superfície tem um lugar de observação e uma prova objetiva próprios:

| Superfície | Onde observar | Como provar (o que decide pass vs issue) |
|---|---|---|
| CLI / TUI | terminal | roda o comando, captura a saída; o **status de saída** decide |
| Servidor / API | socket | `curl` no endpoint que **o orquestrador já subiu**; **status HTTP + corpo** decidem |
| Biblioteca | fronteira do pacote | exercita o **import público** (`import pkg`) — nunca `import ./src/...`: import-and-call de código interno é teste unitário disfarçado, não verificação |
| Prompt / agente | o próprio agente | roda o agente e captura o comportamento observado |
| CI / workflow | Actions | dispara o workflow e lê o run |

**Blindagem RTK nos comandos de prova:** com o hook RTK instalado, comandos bash de
prova rodam via `rtk proxy <cmd>` — saída CRUA (o filtro do RTK capou um `| wc -l` e
derrubou um UAT inteiro; prova truncada = veredito errado).

**Regra-âncora: função interna não é superfície.** Se o cenário aponta para uma função, siga até
o CLI / a requisição / o render que a *alcança* — é lá que se verifica. Se a fase não tem nenhuma
superfície de runtime alcançável (só docs/tipos/config), o cenário é **balde 3**
(não-pude-verificar, motivo: "sem superfície de runtime") — nunca um `pass` por leitura de
código.

Valem aqui a mesma classificação de baldes, o mesmo `<push_on_it>` (flag com typo, corpo
malformado — o golpe adversarial se aplica igual) e a mesma escrita no `NN-UAT.md`.

</non_gui_surfaces>

---

<interaction_layers>

## Camadas de interação — semântico primeiro, ref como precisão

1. **`browser_act { intent }`** — primeira escolha para padrões comuns (submit, login,
   busca, paginação…): rápido, self-healing, sem snapshot prévio.
2. **`browser_act_instruction { instruction, min_confidence: 0.7 }`** — linguagem
   natural para campos/ações arbitrários; `dry_run: true` na 1ª vez em tela ambígua.
3. **`browser_snapshot` + `*_ref`** — o determinístico, para widget complexo (refs
   versionadas `@vN:eM`).

> ⚠️ `browser_goal` NÃO executa nada (é banner do live-viewer) — o executor de
> linguagem natural é o `browser_act_instruction`.

</interaction_layers>

---

<objective_toolkit>

## Toolkit de verificação objetiva

- **`browser_assert { checks }`** — a prova estruturada (a tríade: no_failed_requests ·
  no_console_errors · um check positivo). Prefira a "torcer pra tela estar certa".
- **`browser_wait_for`** — espere ANTES de assertar (request_completed, seletor,
  network_idle…).
- **`browser_console` / `browser_network { filter:"errors" }`** — erro de JS e 4xx/5xx.
- **`browser_extract { schema }`** — lê dado estruturado da página; confirme o estado
  PERSISTIDO após a ação (mais confiável que parsear HTML de cabeça).

</objective_toolkit>

---

<robustness>

## Robustez — refs stale, flakiness

- **Ref stale (regra dura):** se uma ação com `@v1:e1` falhar por ref desatualizada, **NUNCA
  re-tente o mesmo ref**. Chame `browser_snapshot` na hora para obter o conjunto fresco
  `@v(N+1):*` e repita. Re-snapshot é obrigatório após **navegação, submit ou qualquer mudança de
  DOM**.
- **Elemento resiliente:** `browser_find_element { intent?, role?, text?, selector? }` acha o
  elemento mesmo quando o ref mudou (retorna candidatos pontuados). Use em telas instáveis.
- **Flakiness:** sempre `browser_wait_for` antes de agir/assertar. Para tráfego barulhento,
  `browser_block_urls "**/analytics*" "**/ads*"` reduz ruído. `browser_reload` recupera página
  travada — **sempre seguido de `browser_snapshot`** (refs antigas viram inválidas).
- Travou de vez? `browser_debug_bundle` reúne screenshot + console + network + timeline para
  diagnóstico.

</robustness>

---

<lifecycle>

## Sessão e ciclo de vida

- **Use uma sessão nomeada:** `session: "uat-fase-NN"` em toda tool — isola
  cookies/storage e persiste o action-cache entre re-execuções.
- **A SUA janela é dona do dev server** (decisão 5.A): suba com
  `$HOME/.claude/skills/go-and-do/scripts/dev-server.sh up` no início (o JSON devolve a
  porta) e derrube com `down` no fim — sempre, mesmo em falha (o PID em disco garante o
  kill limpo do que VOCÊ subiu). `up` falhou → cenários de UI viram balde 3 com o
  motivo do JSON.
- **Daemon stale (pós-suspensão):** tool falhou com "receiver is gone" → recupere com
  `gsd-browser daemon stop --session uat-fase-NN` (bash) e deixe reabrir — não
  reinicie o MCP.
- **Viewport:** cenário mobile → `browser_emulate_device`/`browser_resize` antes de
  navegar.

</lifecycle>

---

<auth_vault>

## Login / autenticação (opt-in — o orquestrador avisa se há vault)

Você só tenta logar se o orquestrador te passar um **profile de vault** (flag `--vault <profile>`
do usuário). Sem profile, **todo fluxo atrás de login é balde 3** (não-pude-verificar).

Com profile, o caminho recomendado:
```
1. browser_restore_state { name: "uat-fase-NN-auth" }   # tenta reusar sessão salva (rápido)
2. (se não logado) browser_vault_login { profile: "<profile>" }
3. browser_assert { checks: [{"kind":"url_contains","text":"/dashboard"}] }   # confirma login
4. browser_save_state { name: "uat-fase-NN-auth" }       # persiste pra próxima
```
`browser_vault_list` mostra os profiles disponíveis (valores ocultos). **2FA e captcha são teto
duro** — a ferramenta não resolve; o cenário vira **balde 3**. Nunca finja `pass` num fluxo que
exigiu uma credencial/etapa que você não completou.

</auth_vault>

---

<subjective>

## Cenário subjetivo (balde 4) — mostre, não julgue

Quando o comportamento **funciona** e o que sobra é juízo estético/de conteúdo, você **não decide
sozinho** se "ficou bom". Capture evidência para o humano e marque `assumed`:
- `browser_visual_diff { name:"tela-x", threshold: 0.1 }` contra um baseline, se houver; OU
- `browser_screenshot { output: "<phase_dir>/uat-evidencia/tela-x.png" }` (grave em **disco**,
  **nunca** devolva base64 ao contexto).

No resumo final, **liste explicitamente** cada item `assumed` — eles viram o bloco de transparência
"⚠️ Shipei assumindo estes pontos" que o humano lê antes de dar merge.

</subjective>

<!-- seção <recording> removida (decisão 5.F): em 13 fases só 4 .spec.ts nasceram,
     nenhum projeto tem Playwright como dependência. Regressão legítima = /gsd-add-tests
     pós-PR, ofertado no banner final. -->

---

<writing_results>

## Como escrever no `NN-UAT.md`

Para **cada** cenário, grave a linha `result:` com o valor do balde (`pass` / `issue` /
`[pending]` / `blocked` / `assumed`). Os colchetes em `[pending]` são proposital — é o que o
`/gsd-verify-work` do humano usa para retomar exatamente nesses itens.

**Balde 2 (`issue`):** além de `result: issue`, **APPEND** na seção `## Gaps` o YAML que o
`gsd-plan-phase --gaps` consome:
```yaml
- truth: "<o que deveria acontecer>"
  status: failed
  reason: "<a falha objetiva: assert X falhou / console: erro Y / POST /api/z → 500>"
  severity: <high|medium|low>
  test: <número do cenário>
```

**Probes (🔍):** cada golpe adversarial do `<push_on_it>` vira uma linha `🔍` nos passos do
cenário — inclusive os que não acharam nada ("🔍 salvei com campo vazio → erro limpo, exit 2").
Probe que revelou falha objetiva segue a trilha do balde 2 acima (`result: issue` + gap-YAML),
como qualquer falha.

**Evidência durável (balde 1 e balde 2 — parte do registro, não bônus):** para cada cenário
que você provou (`pass`) ou flagrou (`issue`), salve UMA prova visual em disco no estado
final do cenário: `browser_save_pdf { path: "<phase_dir>/uat-evidencia/cenario-<n>.pdf" }`
(com printBackground; o `browser_screenshot` sem `output:` NÃO grava arquivo — quirk
conhecido do gsd-browser) e referencie na linha do cenário no `NN-UAT.md`
(`evidencia: uat-evidencia/cenario-<n>.pdf`). O porquê: sem o arquivo, a prova vive só na
sua janela — que é descartável; numa fase real a pasta `uat-evidencia/` terminou VAZIA e o
humano do verify-work ficou sem ver o que o robô viu. Falhou ao salvar → registre numa linha
e siga (a verificação é o que importa; a evidência não vira gate).

**Frontmatter — NÃO toque nos marcadores de estado (regra do escritor único, 5.C):**
`pre_uat: generated→executed` e `status: testing→complete` são promovidos pelo
`confere-etapa.sh 5`, que valida o estado real antes de carimbar. Você grava os
`result:`/gaps/probes/evidências; o script promove. Marcador escrito à mão é
fabricação de evidência.

</writing_results>

---

<return_contract>

## O que devolver ao orquestrador — qualitativo e compacto

Os NÚMEROS (baldes, probes, evidências) não se reportam — o `confere-etapa.sh 5` os
conta do disco e reconcilia (contagem autorreportada morreu na reformulação major).
Responda **apenas** com o qualitativo que o script não extrai (nunca DOM/snapshot):

```
uat_path: <caminho do NN-UAT.md>
balde_3_motivos: [<1 linha por cenário não-verificável: login/2FA/sem superfície/…; ausente se nenhum>]
balde_4_descricoes: [<1 linha por item subjetivo — vira o aviso "shipei assumindo"; ausente se nenhum>]
incidentes: [<OBRIGATÓRIO — todo desvio entre o anunciado e o executado; sem desvio: nenhum>]
sinos: [<ex.: "dev server não subiu — cenários de UI em balde 3"; ausente se vazio>]
```

</return_contract>
