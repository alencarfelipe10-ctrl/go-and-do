<!-- prompts/intent-verifica.md — filho de camada 2 (agente gad-verificador) que funde,
     deduplica e verifica os pareceres da consultoria especializada de UM ciclo. Lido do
     disco PELO FILHO. Ele devolve VEREDITOS em dois eixos (a alegação se sustenta? ela
     protege o Goal?); o destino de cada achado é da camada 1. -->

# Filho da intenção — verificação de pareceres (ciclo C)

O despacho te entrega: `project_root` e `phase_dir` (absolutos), o prefixo da fase `NN`
(precisa dele para o `roda-lanes.sh --esperar` do passo 0), o número do ciclo `C`, o
**`run_id`** das lanes deste ciclo, o run-dir `<phase_dir>/.intent/runs/c<C>/<run_id>/`, o
diretório de status `<phase_dir>/.intent`, o manifesto de perguntas dirigidas
`.intent/.perguntas-c<C>.json`, os caminhos dos pareceres
(`<phase_dir>/pareceres/NN-parecer-*-c<C>.md`), os de `NN-SPEC.md` e `NN-CONTEXT.md`, um
deadline de espera, e — do ciclo 2 em diante — o `NN-INTENT-REVIEW.md` parcial com a tabela
dos achados já triados. Os arquivos de trabalho do ciclo vivem em `<phase_dir>/.intent/`.
Comece todo bloco Bash com `cd "<project_root>"`. **Instrumento ausente** (o script chamado
não existe no caminho absoluto, ou `command not found`) não é «pule e continue» — é
`incidente` (`origem=intent-verifica`, `detalhe=instrumento ausente: <caminho>`) e trava:
pare no passo e devolva o que tiver, nunca contorne à mão o que o script faria.

## Trabalho

0. **Espera pelo STATUS, nunca pelo `.done`.** As lanes ainda estão rodando quando você
   nasce. A autoridade de cada lane é `<phase_dir>/.intent/.status-c<C>-<lane>.json` **com
   o mesmo `run_id` que o despacho te deu** — status com `run_id` diferente é de um run
   anterior: ignore-o e continue esperando. Espere primeiro o do Codex (chega antes) com a
   espera SANCIONADA (48c/E4 — substitui o loop manual antigo; não é `run_in_background`, é
   um `until … sleep` embutido no próprio script):
   ```bash
   $HOME/.claude/skills/go-and-do/scripts/roda-lanes.sh "<phase_dir>" "<NN>" <C> --esperar codex
   ```
   Exit 0 (`esperado:true`) → siga. Exit 124 (`esperado:false, motivo:"timeout"`) → o teto
   do script é 590 s, mas a SUA deadline é de 12 min: **124 não é "a lane morreu"**, é só o
   teto do script vencendo antes da deadline — chame de novo enquanto a deadline não vencer;
   só ao vencer a deadline sem `esperado:true` é que a lane conta como morta (`sem_parecer`).
   Exit 2 (uso errado — ponteiro do ciclo ausente ou argumento faltando) é sinal de que o
   `roda-lanes.sh` do passo 4 do `intent.md` não rodou antes de você: registre `incidente` e
   trate como `sem_parecer` das duas lanes. Com o Codex pronto, execute os passos 1–4 sobre
   esse parecer enquanto o agy termina, depois espere
   `$HOME/.claude/skills/go-and-do/scripts/roda-lanes.sh "<phase_dir>" "<NN>" <C> --esperar agy`
   (mesma régua de exit 0/124/2) e incorpore o parecer dele (funda com o que já verificou —
   só o que ele acrescenta ou corrobora gera trabalho novo). O `--esperar` só confirma que o
   `.status-c<C>-<lane>.json` do run atual existe — você continua lendo `usable`/
   `independent` do próprio JSON, igual a sempre.
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
   consultores vira UMA entrada com `fontes: [codex, agy]` — convergência independente de
   dois modelos é sinal de força; anote-a.
2. **Classifique cada achado contra o histórico** (ciclo 2+, lendo a tabela do
   INTENT-REVIEW): `novo` (alegação sobre fato/decisão que nenhum achado anterior
   tocou) · `reformulado` (mesma alegação de um achado já triado, com outras palavras
   ou outro exemplo — o teste: se a correção do achado antigo também resolve este, é
   reformulado) · `reaberto` (achado descartado antes, agora com evidência NOVA — só a
   evidência nova reabre; a mesma evidência re-apresentada é `reformulado`).
   `reformulado` de achado já resolvido/descartado não se verifica de novo: entra no
   retorno com o ponteiro para a entrada original. A seção `## Dívidas registradas` do
   INTENT-REVIEW também é histórico: achado dispensado que volta com as mesmas palavras é
   `reformulado`, com `ref_anterior` para a entrada da dívida — só evidência nova o reabre
   (na F24.4 a mesma omissão de cardinalidade foi achada e verificada duas vezes).
3. **Cheque os ponteiros mecanicamente antes de julgar:** rode
   `$HOME/.claude/skills/go-and-do/scripts/spot-check-ponteiros.sh <parecer>` para cada
   parecer — ele confere se cada citação `arquivo:linha` existe e devolve as quebradas.
   Ponteiro quebrado não mata o achado sozinho (o consultor pode ter errado a linha e
   acertado a tese) — mas rebaixa a confiança e obriga você a localizar a evidência
   real antes de confirmar. **`referencias_vistas=0` no sumário (nenhuma citação) =
   parecer não aterrado** — mesma régua do carimbo `[reviewed-without-source-citations]`
   do GSD 1.11.0 (#3194): o consultor leu o texto colado, não o repositório. Não descarte (a tese
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
   - `confirmado_irrelevante` — a alegação se sustenta **e** você não achou efeito medido
     do Goal que ela proteja. Evidência própria do fato, mais uma linha de motivo dizendo
     o que você procurou no Goal e não achou. É registro, não descarte: o achado segue
     para as dívidas e pode virar tarefa de plano ou de code-review.

   O `vinculo_goal` de cada achado é seu, não do consultor: o parecer traz uma linha
   `vinculo_goal:` e você a julga contra o `## Goal` do SPEC — se o vínculo alegado não se
   sustenta, reescreva-o (ou ponha `nenhum`); o consultor propõe, você decide. Desempate
   do eixo de vínculo (proposta do plano 3, marcada como tal): na dúvida, achado
   `A-produto` fica `confirmado` — o custo de errar para baixo é defeito em produção;
   achado `B`, `C` ou `D` fica `confirmado_irrelevante` com a dúvida escrita no motivo —
   quem te despachou pode promovê-lo, e promover custa uma linha.
4b. **Revalide a categoria de cada achado** pela régua canônica de
   `$HOME/.claude/skills/go-and-do/prompts/categorias-achados.md` (a MESMA que o
   consultor recebeu): confirme a tag `[A-E]-*` que ele pôs ou reclassifique.
   **Regra de desempate obrigatória** (a régua canônica, nos dois eixos): na dúvida
   entre A/B e C/D, classifique para cima — a parada por custo marginal do loop
   (`decide-ciclo.sh`) só olha A/B, e um achado A fantasiado de C encerraria a revisão
   cedo demais. Achado sem tag → você classifica.
5. Você **não** decide destino (correção factual × pausa de negócio × transparência) —
   isso é alçada de quem te despachou. Seu produto termina no veredito.

   **Não atribua causa a um instrumento sem abri-lo (FJ-10INT).** Se um script/fiscal deu um
   resultado que parece errado, a causa só entra no seu retorno depois de você ler o código
   dele e confirmar — nunca por dedução da saída. Registre só o que você conferiu; um "parece
   que o script X está bugado" sem tê-lo aberto não vira alegação.
6. **Vereditos em disco (insumo do decide-ciclo.sh):** grave
   `<phase_dir>/.intent/.vereditos-c<C>.txt` — uma linha por achado, formato exato:
   `id | classe | veredito | categoria` (ex.: `c2-03 | novo | confirmado | A-produto`;
   `confirmado_irrelevante` é o quarto valor do terceiro campo — nunca um quinto campo: o
   `decide-ciclo.sh` lê quatro e um excedente cairia dentro de `categoria` em silêncio).
   **A célula `veredito` da tabela do INTENT-REVIEW.** Quem escreve a tabela é quem te despachou,
   mas o valor é seu: entregue-o na forma `<veredito>` ou `<veredito> (<categoria>)`, e nunca com o
   veredito dentro de uma frase. Os quatro valores são `confirmado`, `confirmado_irrelevante`,
   `nao_sustentado` e `ja_coberto`; a categoria entre parênteses é opcional e informativa. O medidor
   da auditoria (`etiqueta-achados.py`) lê a célula inteira: «o consultor tem razão, mas…» sai como
   achado sem veredito, e a régua de proveniência da fase inteira sai `não_medida` — foi o que
   aconteceu nas F24.3, F24.4 e F24.5.
6b. **Vereditos das perguntas dirigidas (R8) — arquivo próprio, ao lado dos achados.**
   O briefing pediu ao consultor uma linha `- Q<n>: sim|não|incerto — evidência` na seção
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
6c. **Tabela cheia dos achados, em disco (48d/E4).** O retorno deixou de carregar a lista
   `achados:` inteira (só sumário, ver `## Retorno`) — a tabela com `alegacao`, `evidencia`,
   `vinculo_goal`, `severidade` etc. por achado é o que quem te despachou usa para montar a
   triagem e o `NN-INTENT-REVIEW.md`, e agora mora só no disco. Grave
   `<run_dir>/achados-verificados.json` — array JSON, um objeto por achado, com **exatamente**
   os campos do bloco `achados:` de antes (id, alegacao, fontes, classe, ref_anterior,
   veredito, categoria, evidencia, vinculo_goal, independente, severidade,
   toca_requisito_ou_criterio — omita `ref_anterior` fora de `reformulado`/`reaberto`):
   ```bash
   cat > "<run_dir>/achados-verificados.json.tmp" <<'JSON'
   [{"id":"c<C>-01","alegacao":"...","fontes":["codex","agy"],"classe":"novo",
     "veredito":"confirmado","categoria":"A-produto","evidencia":"arquivo:linha",
     "vinculo_goal":"...","independente":"sim","severidade":"...",
     "toca_requisito_ou_criterio":"nao"}]
   JSON
   mv -f "<run_dir>/achados-verificados.json.tmp" "<run_dir>/achados-verificados.json"
   ```
   `<run_dir>` sobrevive à limpeza do passo 7b do `intent.md` (`runs/` já está na lista do
   que não se apaga) — o arquivo continua legível quando o coordenador voltar a ler para
   escrever o INTENT-REVIEW.
7. **Prova de máquina de que você rodou:** como últimos atos antes do retorno, nesta ordem:
   ```bash
   IN="<phase_dir>/.intent"
   printf '{"v":1,"ciclo":"<C>","run_id":"<run_id>","agente":"gad-verificador","mode":"<child|inline>","ts":"%s","n_linhas":%s,"sha256":"%s"}\n' \
     "$(date -Is)" "$(grep -cvE '^\s*(#|$)' "$IN/.vereditos-c<C>.txt")" \
     "$(sha256sum "$IN/.vereditos-c<C>.txt" | cut -d' ' -f1)" \
     > "$IN/.vereditos-c<C>.origem.json"
   touch "$IN/.verificador-c<C>.done"
   ```
   O `.verificador-c<C>.done` é o marcador que o `confere-rotas.sh` cruza com a
   `.tabela-c<C>.txt` no fecho da etapa, para provar que a rota de verificação independente foi
   respeitada. O recibo `.vereditos-c<C>.origem.json` é o que torna o arquivo de vereditos
   **fechado**: o `confere-ciclo.sh --origem-vereditos` recalcula o sha256 e reprova qualquer linha
   acrescentada depois de você sair. Grave-o só DEPOIS de os vereditos estarem completos em disco e
   ANTES do `.done`: marcador sem trabalho é fabricação de evidência, e recibo sem os vereditos
   finais é pior — sela o arquivo errado.
   **Na rota `inline`** (ciclos 3+ com ≤ 2 brutos, quando quem te despachou verifica ele mesmo) o
   recibo é gravado pelo coordenador com `"mode":"inline"`: a rota já está declarada na
   `.rota-verificacao-c<C>.json` e o `confere-ciclo.sh` só aceita `inline` quando as duas dizem o
   mesmo.

## Retorno (obrigatório, sem prosa antes ou depois)

**48d/E4 — retorno enxuto.** A tabela de achados (alegação, evidência, vínculo_goal,
severidade por item) não vem mais aqui: ela mora só em disco
(`achados-verificados.json`, passo 6c). O retorno é sumário — contagens e ponteiros
absolutos para os três arquivos que quem te despachou vai ler.

```
ciclo: <C>
achados_brutos: <n no(s) parecer(es), antes da fusão>
achados_fundidos: <n após dedup entre consultores>
convergencias: <n achados com fontes: [codex, agy]>
ponteiros_quebrados: <n reportados pelo spot-check; 0 se nenhum>
pareceres_sem_citacao: [<lanes cujo parecer não tem nenhuma citação arquivo:linha; [] se todas citam>]
sem_parecer: [<lanes com usable:false ou sem status no deadline; [] se nenhuma>]
lanes_nao_independentes: [<lanes com independent:false; [] se nenhuma>]
vereditos_txt: <caminho absoluto de .vereditos-c<C>.txt>
vereditos_dirigidos: <caminho absoluto do vereditos-dirigidos.json que você gravou>
achados_json: <caminho absoluto de achados-verificados.json (passo 6c) — a tabela cheia mora lá>
```
