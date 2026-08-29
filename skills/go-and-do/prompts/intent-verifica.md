<!-- prompts/intent-verifica.md — filho de camada 2 (agente gad-verificador) que funde,
     deduplica e verifica os pareceres adversariais de UM ciclo. Lido do disco PELO
     FILHO. Ele devolve VEREDITOS; o destino de cada achado é da camada 1. -->

# Filho da intenção — verificação de pareceres (ciclo C)

O despacho te entrega: `project_root` e `phase_dir` (absolutos), o número do ciclo `C`, o
**`run_id`** das lanes deste ciclo, o run-dir `<phase_dir>/.intent/runs/c<C>/<run_id>/`, o
diretório de status `<phase_dir>/.intent`, o manifesto de perguntas dirigidas
`.intent/.perguntas-c<C>.json`, os caminhos dos pareceres
(`<phase_dir>/pareceres/NN-parecer-*-c<C>.md`), os de `NN-SPEC.md` e `NN-CONTEXT.md`, um
deadline de espera, e — do ciclo 2 em diante — o `NN-INTENT-REVIEW.md` parcial com a tabela
dos achados já triados. Os arquivos de trabalho do ciclo vivem em `<phase_dir>/.intent/`.
Comece todo bloco Bash com `cd "<project_root>"`.

## Trabalho

0. **Espera pelo STATUS, nunca pelo `.done`.** As lanes ainda estão rodando quando você
   nasce. A autoridade de cada lane é `<phase_dir>/.intent/.status-c<C>-<lane>.json` **com
   o mesmo `run_id` que o despacho te deu** — status com `run_id` diferente é de um run
   anterior: ignore-o e continue esperando. Espere primeiro o do Codex (chega antes) com um
   loop barato num único Bash (`until … ; do sleep 15; done`, teto = deadline, testando o
   `run_id` com `jq`), execute os passos 1–4 sobre esse parecer enquanto o agy termina,
   depois espere o status do agy e incorpore o parecer dele (funda com o que já verificou —
   só o que ele acrescenta ou corrobora gera trabalho novo).
   O status traz dois eixos:
   - `usable: false` (parecer ausente, vazio, obsoleto ou ilegível) → devolva a lane como
     `sem_parecer: <lane>` **imediatamente**, sem esperar o deadline; a regra de degradação
     é de quem te despachou, não sua.
   - `independent: false` (`nonce_ok`/`modelo_ok` falso, ou espelho malformado) → o parecer
     **vale e é lido**: os achados dele entram no seu retorno marcados `independente: nao`
     e só recebem veredito `confirmado` com **evidência própria sua** (`arquivo:linha` que
     VOCÊ conferiu). **Nenhum achado é descartado por isso.**
   Status que não chegou até o deadline → `sem_parecer: <lane>` e siga com o que tem.

1. **Piso mecânico antes de ler:** rode
   `$HOME/.claude/skills/go-and-do/scripts/confere-ciclo.sh --tabela --perguntas
   <.intent/.perguntas-c<C>.json> --status-dir <phase_dir>/.intent <parecer(es)>` —
   ele extrai o esqueleto dos achados estruturais (lane · linha · elicitação). Sua
   fusão parte desse esqueleto: cada linha dele precisa de destino na sua tabela final
   (é o piso anti-omissão; prosa sem marcador o script não vê — a sua leitura cobre o
   resto). **Leia os pareceres do ciclo e funda-os.** O mesmo achado apontado pelos dois
   revisores vira UMA entrada com `fontes: [codex, agy]` — convergência independente de
   dois modelos é sinal de força; anote-a.
2. **Classifique cada achado contra o histórico** (ciclo 2+, lendo a tabela do
   INTENT-REVIEW): `novo` (alegação sobre fato/decisão que nenhum achado anterior
   tocou) · `reformulado` (mesma alegação de um achado já triado, com outras palavras
   ou outro exemplo — o teste: se a correção do achado antigo também resolve este, é
   reformulado) · `reaberto` (achado descartado antes, agora com evidência NOVA — só a
   evidência nova reabre; a mesma evidência re-apresentada é `reformulado`).
   `reformulado` de achado já resolvido/descartado não se verifica de novo: entra no
   retorno com o ponteiro para a entrada original.
3. **Cheque os ponteiros mecanicamente antes de julgar:** rode
   `$HOME/.claude/skills/go-and-do/scripts/spot-check-ponteiros.sh <parecer>` para cada
   parecer — ele confere se cada citação `arquivo:linha` existe e devolve as quebradas.
   Ponteiro quebrado não mata o achado sozinho (o revisor pode ter errado a linha e
   acertado a tese) — mas rebaixa a confiança e obriga você a localizar a evidência
   real antes de confirmar. **`referencias_vistas=0` no sumário (nenhuma citação) =
   parecer não aterrado** — mesma régua do carimbo `[reviewed-without-source-citations]`
   do GSD 1.11.0 (#3194): o revisor leu o texto colado, não o repositório. Não descarte (a tese
   pode estar certa), mas TODO achado dessa lane só vira `confirmado` com evidência sua,
   e a lane entra em `pareceres_sem_citacao` no retorno — quem te despachou rebaixa o
   peso dela na triagem.
4. **Verifique cada achado `novo`/`reaberto` contra o código/dados** (Read/Grep
   pontuais; nunca aceite sem conferir — em fase real o mesmo parecer acertou uma
   lacuna que 4 planos não viram E errou uma atribuição de dados). Vereditos:
   - `confirmado` — a alegação se sustenta; evidência própria `arquivo:linha`.
   - `nao_sustentado` — a verificação derrubou; registre o porquê em 1 linha (é o que
     evita re-litigar o mesmo falso achado no ciclo seguinte).
   - `ja_coberto` — os artefatos já cobrem a alegação; ponteiro para a seção do
     SPEC/CONTEXT (ou achado anterior) onde está coberto.
4b. **Revalide a categoria de cada achado** pela régua canônica de
   `$HOME/.claude/skills/go-and-do/prompts/categorias-achados.md` (a MESMA que o
   revisor recebeu): confirme a tag `[A-E]-*` que o revisor pôs ou reclassifique.
   **Regra fail-up obrigatória:** na dúvida entre A/B e C/D, classifique para cima —
   a parada por custo marginal do loop (`decide-ciclo.sh`) só olha A/B, e um achado A
   fantasiado de C encerraria a revisão cedo demais. Achado sem tag → você classifica.
5. Você **não** decide destino (correção factual × pausa de negócio × transparência) —
   isso é alçada de quem te despachou. Seu produto termina no veredito.
6. **Vereditos em disco (insumo do decide-ciclo.sh):** grave
   `<phase_dir>/.intent/.vereditos-c<C>.txt` — uma linha por achado, formato exato:
   `id | classe | veredito | categoria` (ex.: `c2-03 | novo | confirmado | A-produto`).
6b. **Vereditos das perguntas dirigidas (R8) — arquivo próprio, ao lado dos achados.**
   O briefing pediu ao revisor uma linha `- Q<n>: sim|não|incerto — evidência` na seção
   `## Respostas dirigidas`. Toda resposta **`não`** é provisória: só sai da contagem de
   brutos se VOCÊ sustentar a exclusão. Grave `<run_dir>/vereditos-dirigidos.json` — array
   JSON, **uma entrada por `(lane, qid)`** do manifesto, sem duplicata:
   ```json
   [{"lane":"codex","qid":"Q1","raw":"não — o parser já rejeita id duplicado",
     "verdict":"supported_no","evidence":"parser.py:88-94"}]
   ```
   `verdict`:
   - `supported_no` — a resposta é `não` **e** você conferiu a evidência no código/dados;
     só este veredito tira a Q da contagem.
   - `unsupported_no` — respondeu `não` sem evidência sustentável (`N/A`, "porque não",
     reticências, ponteiro inexistente). Continua bruto.
   - `uncertain` — `sim`, `incerto`, resposta ausente, duplicada ou malformada; e o `não`
     cuja verificação você não conseguiu fechar. Continua bruto.
   Lane com `usable: false` não entra (já é `sem_parecer`); lane usável **sem nonce** entra
   normalmente — falta de independência muda o peso do achado, não a completude das Q.
   `evidence` é obrigatória em `supported_no` e `unsupported_no` (neste, o que você
   procurou e não achou).
7. **Prova de máquina de que você rodou:** como último ato antes do retorno,
   `touch <phase_dir>/.intent/.verificador-c<C>.done` — é este marcador que o
   `confere-rotas.sh` cruza com a `.tabela-c<C>.txt` no fecho da etapa para provar que
   a rota de verificação independente foi respeitada. Só grave DEPOIS de os vereditos
   estarem em disco; marcador sem trabalho é fabricação de evidência.

## Retorno (obrigatório, sem prosa antes ou depois)

```
ciclo: <C>
achados_brutos: <n no(s) parecer(es), antes da fusão>
achados_fundidos: <n após dedup entre revisores>
convergencias: <n achados com fontes: [codex, agy]>
ponteiros_quebrados: <n reportados pelo spot-check; 0 se nenhum>
pareceres_sem_citacao: [<lanes cujo parecer não tem nenhuma citação arquivo:linha; [] se todas citam>]
sem_parecer: [<lanes com usable:false ou sem status no deadline; [] se nenhuma>]
lanes_nao_independentes: [<lanes com independent:false; [] se nenhuma>]
vereditos_dirigidos: <caminho absoluto do vereditos-dirigidos.json que você gravou>
achados:
  - id: c<C>-<seq>
    alegacao: <1-2 linhas>
    fontes: [codex|agy|codex, agy]
    classe: novo | reformulado | reaberto
    ref_anterior: <id do achado original — só p/ reformulado/reaberto>
    veredito: confirmado | nao_sustentado | ja_coberto   ← ausente p/ reformulado
    categoria: A-produto | B-viabilidade | C-instrumentacao | D-documental | E-decisao-do-dono   ← revalidada por você (fail-up)
    evidencia: <arquivo:linha própria da SUA verificação, ou o porquê da queda, ou o ponteiro do já-coberto>
    independente: sim | nao   ← nao = lane com independent:false (exige evidência sua)
    severidade: <a estimada pelo revisor, mantida para a triagem>
    toca_requisito_ou_criterio: sim | nao   ← sim = candidato a pausa de negócio na triagem
```
