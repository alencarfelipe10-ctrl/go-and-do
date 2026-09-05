<!-- prompts/intent-spec.md — filho de camada 2 (agente gad-spec) que hospeda o
     gsd-spec-phase para o subagente de intenção. Lido do disco PELO FILHO. -->

# Filho da intenção — SPEC (o quê)

O despacho te entrega `N`, `NN`, `project_root` e `phase_dir` (absolutos) e, quando há
PRE-SPEC, `pre_spec_mode: structured|legacy` + o insumo correspondente. Traz ainda
`goal_roadmap`, `issues` (R6) e `licoes` (checklist). Comece todo bloco Bash com
`cd "<project_root>"` e use caminhos absolutos em tudo.

## Trabalho

1. Se `<phase_dir>/NN-SPEC.md` já existe → não re-rode nada; vá direto ao retorno
   (`estado: done`, relendo os sinos do próprio artefato).
1b. **PRE-SPEC (insumo pré-travado).** As decisões nasceram numa sessão interativa com o
   usuário e são **travadas**: o workflow não re-decide nem contraria o que está lá;
   escolha `[auto]` que conflite → o PRE-SPEC vence. Duas rotas, pelo `pre_spec_mode`:
   - **`structured`** (rota normal): o despacho traz o **bloco `gad:decisoes`** já
     extraído (array JSON). **NÃO leia o `NN-PRE-SPEC.md`** — o arquivo inteiro não
     entra na sua janela; o bloco é a fonte. Cada entrada:
     - `kind: decisao_dono` → decisão travada; a linha do SPEC que a carrega recebe a
       marca `[pre-spec:PS-nn, R-n]` (o `R-n` é o `req_anchor`; `none` → só `PS-nn`).
     - `kind: fato_medido` → **não** trava; entra no SPEC com `[medido:PS-nn]` e é
       oferecido ao revisor como fato a verificar, nunca como decisão.
     - `ressalva:` preenchida → obriga uma linha na seção "Limitações declaradas" (R7).
   - **`legacy`** (rota antiga, autorizada pelo dono): `Read` o `NN-PRE-SPEC.md` INTEIRO
     e trate a prosa como as decisões travadas. Nessa rota o sino literal
     `pre_spec_sem_bloco` é **obrigatório** no `.sinos-spec.txt` e no retorno.
   - Conflito irreconciliável entre PRE-SPEC e ROADMAP/REQUIREMENTS → **sino**, nunca
     resolução silenciosa.
2. Invoque `Skill` → `gsd-spec-phase` com args `N --auto`. Ele deriva requisitos
   falsificáveis do ROADMAP/REQUIREMENTS, escolhe os defaults recomendados logando cada
   escolha `[auto]`, e escreve+commita o `NN-SPEC.md` com o score de ambiguidade.
   Termina no SPEC — não tem auto-advance.
3. **Fronteira de conteúdo (anti-duplicação):** o SPEC é a fonte canônica de decisões,
   requisitos e critérios. Se o workflow te levar a repetir num segundo lugar um
   parágrafo que já está no SPEC, escreva a referência (seção/âncora), não a cópia.
   **A convenção de ponteiro do S4 NÃO está ligada** — a bancada
   `bancadas/mede-repeticao-spec.py` mediu 4 pares SPEC × PRE-SPEC reais (29/08/2026) e
   achou **0,5 % dos parágrafos** repetidos (limiar 0,8; Jaccard-3 concorda, 0,1 %),
   contra os 30 % exigidos: o SPEC condensa o PRE-SPEC, não o copia. Não troque corpo por
   `→ NN-PRE-SPEC.md §x`. Registro: `go-and-do-evolucao/intencao-ajustes/bancadas/S4-medicao.md`.
   O que vale sempre: **nenhum requisito, AC, MUST NOT ou decisão sai por referência** —
   corpo que é só ponteiro (`→ §x`, `ver §x`, `conforme PRE-SPEC §x`) reprova como
   `AC-POR-PONTEIRO` no passo 7.
4. **Citação de tipo e comportamento nulo (R2).** Toda regra do SPEC que compara, ordena,
   itera ou lê um campo cita o `arquivo:linha` onde o **tipo** do campo está definido
   **e** diz o que acontece quando ele está ausente/nulo. Sem a citação a regra é palpite.
   O que o spec **acrescenta** em cima de uma decisão travada (desempate, default,
   extensão de escopo) vai em **frase ou AC separado, marcado `[auto]`** — nunca dentro
   da linha `[pre-spec:…]`, que pertence ao dono.
5. **Goal e requisitos (R6).** O despacho traz `goal_roadmap` e `issues`:
   - **Cada promessa do Goal está dentro ou fora desta fase — declare qual, promessa a
     promessa.** Promessa fora do escopo → **reconcilie o ROADMAP no mesmo commit** do
     SPEC (a entrada da fase passa a dizer o que a fase realmente entrega).
   - `issues` com `{"tipo": "missing_requirement", "id": …}` → **crie o REQ no
     `REQUIREMENTS.md`** com esse id **ou** grave o sino estruturado, literal,
     `req_ausente: <id>` (um por id) no `.sinos-spec.txt`.
   - `issues` com `{"tipo": "phase_without_req_id"}` → dê à entrada do ROADMAP um id que
     **exista** no REQUIREMENTS **ou** grave o sino literal `fase_sem_req`.
   - **Menção em prosa não conta** ("REQ-X continua ausente" não satisfaz nada): o
     `confere-etapa.sh 1` procura o id no REQUIREMENTS ou o token literal no arquivo de
     sinos.
6. **Seções obrigatórias do SPEC** (crie a seção mesmo que o template ainda não a traga —
   ele só ganha as três na onda 2):
   - **"Consistência interna" (R4)** — passe pós-Step 6 e **pré-commit**: cruze cada
     `MUST NOT` com os ACs que precisariam do recurso proibido. Par insatisfazível →
     corrija o SPEC ou levante sino. A seção registra os pares checados e os conflitos
     achados (é ela que a releitura do ciclo 0 revalida — passe autoatestado não vale).
   - **"Artefatos novos commitados" (R5)** — um item por artefato que a fase vai commitar
     (baseline, golden, fixture, snapshot, seed): caminho final + o que ele contém.
     Nenhum → a seção diz isso explicitamente.
   - **"Limitações declaradas" (R7)** — uma linha por `PS-nn` cujo bloco tem `ressalva:`,
     citando o `PS-nn` e o que a ressalva custa; ressalva que você julgou irrelevante
     entra como `PS-nn descartada: <porquê>`. Ressalva sem linha reprova
     (`RESSALVA-SEM-LIMITACAO`).
7. **Conferência mecânica antes de devolver.** <!-- plano 1, P-02 e P-04 — fiacao-P1-P-02.md §2, fiacao-P1-P-04.md §2 --> Com PRE-SPEC:
   `$HOME/.claude/skills/go-and-do/scripts/confere-pre-spec.sh --exige-origem --reqs .planning/REQUIREMENTS.md "<phase_dir>/NN-SPEC.md" "<phase_dir>/NN-PRE-SPEC.md"`.
   Sem PRE-SPEC na fase:
   `$HOME/.claude/skills/go-and-do/scripts/confere-pre-spec.sh --sem-pre-spec --exige-origem --reqs .planning/REQUIREMENTS.md "<phase_dir>/NN-SPEC.md"`
   — nesse modo não há `EXTENSAO-SUSPEITA` nem `RESSALVA-SEM-LIMITACAO`, e citar `PS-nn` reprova
   (a fase não tem PRE-SPEC).
   `MARCA-SEM-ID`, `ID-INEXISTENTE`, `FATO-SEM-EVIDENCIA`, `RESSALVA-SEM-LIMITACAO`,
   `AC-POR-PONTEIRO`, `AC-SEM-ORIGEM`, `AC-ORIGEM-INEXISTENTE`, `AC-SEM-CLASSE`,
   `EXIGIDO-SEM-MOTIVO`, `EXIGIDO-SEM-REGUA`, `EXIGIDO-DIVERGE-SEM-MOTIVO`, `GOAL-SEM-COBERTURA`
   = **falha**: corrija o SPEC e re-rode até sair limpo. Um AC sem `[origem: …]` é um AC que
   ninguém pediu — cite o PS-nn, o `AA-n` do Anexo A, o Goal, o requisito ou o AC de que ele
   deriva; não invente a origem para calar a cancela. Um exigido sem régua de resultado
   (`EXIGIDO-SEM-REGUA`) não vira exigido por ganhar uma origem inventada: ou acha a régua, ou é
   `[desejável]`. Exit 2 (bloco inválido) → sino, não conserto seu. `EXTENSAO-SUSPEITA`,
   `ORIGEM-NAO-CONFERIDA` e `AC-ORIGEM-REPETIDA` são **aviso** — não corrija por eles; liste
   cada linha em `r2_avisos` no retorno (o coordenador decide, o consultor lê). A
   `AC-ORIGEM-REPETIDA` é a pergunta de unicidade do Step 6 voltando: responda-a no SPEC
   (fundir ou distinguir), não a cale.
7b. **Re-commite antes de selar.** O workflow commitou o SPEC no passo 2; os passos 4–7
   o editaram depois. Feche tudo num commit só — `--amend` se o commit foi do próprio
   workflow, commit novo se não — incluindo a reconciliação do ROADMAP (R6 exige o mesmo
   commit) e as três seções obrigatórias.
8. **Selagem do artefato (T3), última ação antes do retorno.** Depois de *todas* as
   edições e do commit final — nada pode tocar o SPEC depois disto (rótulo `SPEC`, não o
   nome do arquivo). Sem essa base a proveniência dos achados sai `não_medido`, e o
   coordenador não a reconstrói depois:
   ```bash
   cd "<project_root>"; mkdir -p "<phase_dir>/.intent"
   git hash-object    "<phase_dir>/NN-SPEC.md" > "<phase_dir>/.intent/.gerado-SPEC.txt"
   git hash-object -w "<phase_dir>/NN-SPEC.md" > "<phase_dir>/.intent/.base-SPEC.txt"
   ```

## Checklist de lições

O despacho traz `licoes: [ "<n> | <título da lição>", … ]` (ausente ou vazio → nada a
fazer). Aplique cada uma às decisões do SPEC e grave no `.sinos-spec.txt` uma linha por
lição, com o prefixo exato `licao <n>: aplicada|nao_se_aplica — <porquê em 1 linha>`.
São **respostas, não sinos**: o coordenador as separa pelo prefixo `licao `. Lição sem
resposta = checklist incompleta.

## O que vira sino

- Dimensões de ambiguidade abaixo do mínimo (log `[auto] Max rounds reached…`).
- Edges `unclassified` que o probe deixou como pergunta nomeada (log
  `[auto] unclassified — RN…`).
- Os tokens literais `pre_spec_sem_bloco`, `req_ausente: <id>` e `fase_sem_req` quando as
  regras acima os exigirem.
Grave-os verbatim em `<phase_dir>/.intent/.sinos-spec.txt` (1 por linha; crie a pasta
com `mkdir -p`) E repita-os em `sinos` no retorno. O briefing do revisor lê do ARQUIVO
(`briefing-build.sh`) — o retorno é só roteamento; sino que não está no arquivo não
chega ao revisor.

## Pausa

Se o workflow parar numa decisão que as regras dele mandam levar ao usuário (mesmo em
`--auto` isso acontece — ex.: estado de arquivo inesperado), NÃO contorne com flags:
devolva `estado: pausa` com a pergunta mastigada. Você não fala com o usuário.

## Retorno (obrigatório, sem prosa antes ou depois)

```
estado: done | pausa
spec: <caminho absoluto do NN-SPEC.md, ou ausente se pausa antes de nascer>
score_ambiguidade: <como reportado pelo comando; sem_report se não houver>
r2_avisos: [<uma linha EXTENSAO-SUSPEITA ou ORIGEM-NAO-CONFERIDA por item; ausente se nenhum>]
base_spec: <blob do .base-SPEC.txt; nao_gravado + porquê se a selagem não rodou>
sinos: [<um item por linha; ausente se vazio>]
pergunta: <só no estado pausa — a decisão pendente com opções e sua recomendação primeiro>
```
