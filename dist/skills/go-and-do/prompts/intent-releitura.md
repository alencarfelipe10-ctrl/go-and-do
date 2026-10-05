<!-- prompts/intent-releitura.md — filho de camada 2 (agente gad-verificador, modo
     `releitura`) que RELÊ a emenda de UM ciclo antes do briefing do ciclo seguinte (R1).
     Lido do disco PELO FILHO. Escopo: contradição, mecanismo, omissão e cardinalidade —
     relativas à emenda, e, no ciclo 1, também ao documento único inteiro (`NN-CONTEXT.md`):
     a leitura de inconsistência dentro do documento (AC × AC, número declarado × lista,
     critério repetido) que ninguém fez antes dos consultores — o comando que escreveu o
     texto não se autorrevisa (Fase 6 do gad, GODO-03/AC-36). Erro factual novo continua
     sendo trabalho dos consultores externos — esta releitura NÃO é filtro de achado. O
     arquivo em disco É o objeto de retorno (v: 2): um recibo em disco com o veredito só no
     retorno perde o veredito quando a janela morre — na F24.4 dois ciclos ficaram com 235
     bytes que não reliam nada. -->

# Filho da intenção — releitura da emenda (ciclo C)

O despacho te entrega: `project_root` e `phase_dir` (absolutos), `NN`, o número do ciclo
`C`, o conteúdo (ou o caminho) de `<phase_dir>/.gad/intent/c<C>/correcoes.aplicado` — JSON
`{commit, caminhos:[...], correcoes:[{id, hash}]}` — e, conforme o ciclo:

- **ciclo 1:** leitura de inconsistência dentro do documento — AC × AC, número declarado × lista, critério repetido — sobre o `NN-CONTEXT.md` inteiro; você não escreveu o texto
  (o comando que o gravou não se autorrevisa antes de gravar, e não há ciclo anterior que o
  tenha relido). É a mesma conferência que o briefing do ciclo 1 pede aos consultores; a
  sua é a leitura independente. Ela vem **além** da emenda, pelos passos 2, 3b e 5b.
- **todo ciclo (C ≥ 1, inclusive os ciclos ≥ 2):** a emenda do ciclo e as linhas `PROSA-BLOCO-DIVERGE c<C> …` que
  `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/go-and-do/scripts/confere-reconciliacao.sh "<phase_dir>" <C>` emitiu
  — a conferência de coerência texto × bloco da máquina do `NN-CONTEXT.md` depois das
  correções do ciclo (uma linha por divergência; nenhuma linha = nada divergiu).

Comece todo bloco Bash com `cd "<project_root>"`. **Instrumento ausente** (script chamado
sem existir no caminho absoluto, `command not found`) não é «pule e continue» — é
`incidente` (`origem=intent-releitura`, `detalhe=instrumento ausente: <caminho>`) e trava:
pare e devolva o objeto com `ok: false` e a falha em `observacao`, nunca contorne à mão o
que o script faria. Os `caminhos` são relativos ao
`project_root`.

Você lê o que o ciclo **acabou de escrever nos artefatos** (o `NN-CONTEXT.md`, o
INTENT-REVIEW e, quando o ciclo os tocou, ROADMAP/REQUIREMENTS) e responde uma pergunta só:
**a emenda estragou alguma coisa?** No ciclo 1 a pergunta cresce: **o documento, inteiro,
se contradiz?** — é a única vez em que alguém que não o escreveu o relê de ponta a ponta
antes de a consultoria seguir.

**Caminhos de evidência (v2.10.1).** Os arquivos de trabalho da fase moram em
`<phase_dir>/.gad/` e aparecem aqui pelo NOME NOVO (ex.: `.gad/intent/c<C>/vereditos.txt`) — o
formato de toda fase com `<phase_dir>/.gad/FORMATO`. Fase SEM esse arquivo (aberta antes da
v2.10.1) usa os nomes antigos: o caminho real é o que
`bash ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/go-and-do/scripts/caminho-fase.sh "<phase_dir>" <nome depois de .gad/>`
imprime (ex.: `intent/c1/vereditos.txt` → `.intent/.vereditos-c1.txt`). Os blocos bash abaixo já
resolvem por ele (função `G`). Nunca misture os dois formatos na mesma fase.

## Trabalho

1. **Leia a emenda — e, no ciclo 1, o documento inteiro:**

   ```bash
   cd "<project_root>"
   git show --stat <commit>
   git diff <commit>^..<commit> -- <caminhos...>   # commit raiz (sem pai) →
                                                   # git show <commit> -- <caminhos...>
   ```

   Leia o contexto ao redor de cada hunk (`sed -n` no arquivo do worktree) só o bastante
   para julgar. No ciclo 1, leia também o `NN-CONTEXT.md` de ponta a ponta (a versão do
   commit). Do ciclo 2 em diante, não releia o documento inteiro — isso é trabalho dos
   consultores.

2. **`contradiz` — AC × AC.** Para cada AC/`MUST NOT`/requisito que a emenda criou ou
   alterou, procure no documento outro AC que ele torne insatisfazível ou que o torne
   insatisfazível. Par insatisfazível = existe ao menos um comportamento exigido por um e
   proibido pelo outro. Ponteiro obrigatório aos dois ids (`AC-nn`, `R-n`, `D-nn`).
   **No ciclo 1, o documento inteiro:** todo par de critérios do `NN-CONTEXT.md`, não só os
   que a emenda tocou.
   <!-- H3, plano 1 P-06 (D7b) -->
   O documento é do dono (nasceu do `/gad-discuss-phase` com ele presente): critério que a
   emenda **acrescentou** como `[exigido]` sem passar por pergunta ao dono é item aqui,
   na forma `{"exigido_novo_sem_pergunta": "AC-nn"}`: endurecer um critério do dono sem
   pergunta é decidir no lugar dele.

3. **`prescreve_mecanismo` — invariante, não mecanismo.** A regra que a triagem tem de
   obedecer: **AC é `MUST NOT` + modo de falha observável**, nunca a receita de como
   implementar. Acuse toda linha nova que prescreva implementação. Anti-exemplos genéricos
   (a forma, não o caso):
   - ❌ "usar um dicionário indexado pelo id para casar as linhas" → ✅ "MUST NOT casar
     duas linhas com ids diferentes; casamento ambíguo falha com erro que nomeia os dois
     ids".
   - ❌ "o script roda em duas passadas, a primeira montando o índice" → ✅ "MUST NOT
     escrever saída antes de todas as entradas terem sido lidas; saída parcial após falha
     é violação observável no arquivo de destino".
   - ❌ "gravar em `/tmp` e depois mover" → ✅ "MUST NOT deixar o arquivo de destino em
     estado meio-escrito; leitor concorrente lê a versão anterior inteira ou a nova
     inteira".
   Se a emenda só reformulou prosa explicativa (não-normativa) fora de AC, não acuse.
   **Mesmo item, gatilho novo (FJ-06INT):** toda frase que a emenda acrescentou também entra
   aqui — não só como prescrição de mecanismo — quando ela é **impossível de cumprir** (exige
   algo que o código citado não permite) ou **contradiz** o `arquivo:linha` que ela mesma
   cita. Confira contra o repositório, não contra a sua leitura da intenção; o item vai no
   mesmo array, com o `trecho` sendo a frase nova e o `path`/`linha` o que ela contradiz.
   <!-- H4, plano 1 P-06 — o AC-10 da 24.4 («nos TRÊS pontos») é o caso desta régua -->

3b. **`cardinalidade` — número declarado × lista.** Para cada linha nova ou alterada que
   declara um número de elementos ("os 8 alunos", "15 restantes", "os TRÊS pontos"), conte a
   enumeração correspondente no documento. Divergência entre o número e a lista, número sem
   a lista, ou dois ids que falam do mesmo conjunto com contagens diferentes, é item de
   `cardinalidade`, com ponteiro aos dois lugares (`declarado`, `contado`, `onde`). **No
   ciclo 1, todo número declarado do documento inteiro**, não só o da emenda. Na F24.4 o
   AC-41 passou a dizer 7 com o AC-15 dizendo 8, e «15 restantes» listou 16 — dois ciclos
   releram e nenhum contou.

4. **`omissoes_novas` — o que a emenda deixou pendurado.** Só o que a **própria emenda**
   abriu: referência a id/seção/arquivo que ela cita e não existe; decisão trocada numa
   seção do documento e não propagada à outra (prosa × bloco da máquina, «Decisões do dono»
   × critérios); AC removido cujo comportamento nenhum outro AC passou a cobrir; correção
   que resolve o achado num ponto e deixa o mesmo defeito no ponto irmão que a mesma emenda
   tocou. **Não** é lugar de lacuna pré-existente nem de erro factual novo — esses são dos
   consultores externos.
   <!-- H7, plano 2 P-06 (C3); Fase 6 do gad: a coerência texto × bloco no lugar da
        reconciliação entre dois documentos -->
   Cada linha `PROSA-BLOCO-DIVERGE c<C> …` que o despacho te entregou é um item aqui, com
   `path` = o `NN-CONTEXT.md` e `o_que` = o que a prosa diz e o bloco da máquina não (ou o
   contrário), com os ids envolvidos: o ciclo emendou um lado do documento e deixou o outro
   para trás. A correção `c<C>b` emenda o lado que ficou para trás — quem decide qual é quem
   te despachou.

5. **`consistencia` — sem seção a reler.** O documento único não tem seção de
   autoconferência para você julgar (a conferência dele é a sua leitura do ciclo 1, nos
   passos 2, 3b e 5b): devolva sempre `consistencia: "não_disponível"`, **sem falha e sem
   achado**. A chave continua obrigatória no objeto — o gate do `briefing-build.sh` a exige.

5b. **`unicidade` — critério repetido.** <!-- H2, plano 1 P-06 (D10) --> Dois critérios que a
   mesma verificação derruba são um critério com dois números. Para cada par suspeito, diga
   qual fixture, `grep` ou `diff` derruba os dois de uma vez, ou por que são distinguíveis.
   Par indistinguível → item `{"ac_a": "AC-nn", "ac_b": "AC-nn", "verificacao": "<o que
   derruba os dois>"}`. **No ciclo 1, todos os critérios do documento inteiro**; do ciclo 2
   em diante, só os pares que a emenda criou ou alterou (na 24.4, 50 critérios viraram 33
   quando alguém finalmente contou).

6. **Escopo — leia duas vezes.** Você checa **contradição, mecanismo, omissão e
   cardinalidade relativas à emenda** — e, no ciclo 1, o documento inteiro pelos passos 2,
   3b e 5b. Você **não** verifica se a alegação corrigida era verdadeira, não procura bug
   novo no código, não reabre achado descartado e não julga a qualidade da decisão do dono.
   Achado factual que você tropeçar no caminho: **não** entra nas listas — no máximo uma
   linha em `observacao`. Achado verdadeiro sem vínculo ao Goal não vai ao lixo: vai ao
   registro de dívidas de quem te despachou (R1/R2), pela `observacao`.

6b. **Rodada de correção (`c<C>b`, `c<C>c`, …) — escopo mais estreito (48a/E4).** Só a
   PRIMEIRA rodada do ciclo (`c<C>`) roda os passos 2–5b inteiros sobre a emenda (e, no
   ciclo 1, sobre o documento inteiro). A partir da
   correção que promove tudo junto num lote só (bloqueante e documental, ver `intent.md`
   passo 5), a rodada seguinte roda de novo **só os passos 2 (`contradiz`) e 3
   (`prescreve_mecanismo`)**, sobre o diff DESSA correção — as duas categorias que ainda
   podem abrir uma `c<C>c`. Devolva `omissoes_novas: []`, `cardinalidade: []` e
   `unicidade: []` por contrato: não são re-derivados de novo, já foram fechados no lote da
   correção anterior. Item documental que a PRÓPRIA correção reabrir (raro) não vai para
   essas listas — uma linha em `observacao`, e quem te despachou registra como dívida em vez
   de abrir outra rodada por causa dele. É o que fecha "uma releitura só" para o documental:
   ele dispara no máximo UM `c<C>b`, nunca um `c<C>c`. `ok` continua `true` quando as cinco
   listas exigidas pelo `v: 2` estão vazias — nesta rodada elas já chegam vazias por
   contrato nas três documentais, então só `contradiz`/`prescreve_mecanismo` decidem `ok`.

7. **Grave em disco, atomicamente, o objeto INTEIRO, JSON ANTES do marcador.** Você não
   tem `Write`: use Bash, com o tmp **no mesmo diretório** do destino (mesmo filesystem →
   `mv` atômico). O que você grava é o **mesmo objeto** do contrato de retorno abaixo,
   com `"v": 2` — o arquivo em disco é o que o gate lê; um recibo com o veredito só no
   retorno perde o veredito quando a janela morre.

   ```bash
   cd "<project_root>"
   G() { bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/go-and-do/scripts/caminho-fase.sh" "<phase_dir>" "$1"; }
   R=$(G intent/<RODADA>/releitura.json); mkdir -p "$(dirname "$R")"
   cat > "$R.tmp" <<'JSON'
   {"v": 2, "ciclo": <C>, "commit": "<commit>",
    "artefatos": [{"path": "<caminho>", "blob": "<blob>"}, ...],
    "contradiz": [...], "prescreve_mecanismo": [...], "omissoes_novas": [...],
    "cardinalidade": [...], "unicidade": [...], "consistencia": "não_disponível", "ok": true|false,
    "observacao": "..."}
   JSON
   mv -f "$R.tmp" "$R"
   touch "$(G intent/<RODADA>/releitura.done)"
   ```

   - `commit` = o `commit` do `.aplicado`, verbatim.
   - `artefatos` = **TODOS** os `caminhos` do `.aplicado` **vigente**, um por entrada, sem
     duplicata e sem sobra — o `briefing-build.sh` exige igualdade de conjunto, não
     subconjunto. Na segunda releitura de um ciclo (depois da correção `c<C>b`) o
     `.aplicado` guarda todas as rodadas do ciclo (`commits`, `rodadas`), mas o `commit` e
     os `caminhos` do topo são só os da rodada vigente: liste esses, não a união das
     rodadas.
   - `blob` = `git rev-parse <commit>:<path>` (o blob **do commit**; o gate confere contra
     o commit **e** contra o worktree atual).
   - **Ciclo sem correção** (`c<C>/correcoes.vazio` no lugar do `.aplicado`) → o mesmo
     objeto com `"commit": ""`, `"artefatos": []`, todas as listas vazias e `ok: true`, mais
     o `.done`. O arquivo é obrigatório mesmo assim. No ciclo 1 a leitura do documento
     inteiro vale mesmo sem emenda: item que ela achar entra nas listas (e `ok: false`), como
     em qualquer outro caso.
   - **Ordem obrigatória:** o `.json` completo primeiro, o `.done` por último — marcador na
     frente de JSON meio-escrito é fabricação de evidência.
   - **`<RODADA>` é o rótulo que o despacho te passou**, não o número do ciclo: `c1` na primeira
     rodada do ciclo 1, `c1b` na correção pós-releitura, `c1c` na seguinte, e assim por diante
     (`c2`, `c2b`, …). O **`.json` leva o nome da própria rodada** (`<RODADA>/releitura.json`,
     igual ao `.done`): a primeira rodada do ciclo (`c<C>`) grava `c<C>/releitura.json` — o
     nome fixo de sempre —, e CADA rodada de correção pós-releitura (`c<C>b`, `c<C>c`, …)
     grava um arquivo PRÓPRIO — `c<C>b/releitura.json`, `c<C>c/releitura.json`, … —, sem
     sobrescrever o da rodada anterior do mesmo ciclo. O `.done` já ganhava o nome da rodada
     por este mesmo motivo: sem isso, o marcador da rodada anterior satisfaz a espera da
     seguinte e o coordenador abre a rodada nova sobre premissa falsa (F24.5: 5 rodadas de
     releitura num mesmo ciclo, a 3ª lançada 51 s antes de a 2ª acabar — a mesma fase em que
     a rodada MAIS RECENTE, não a primeira, importa). O gate do `briefing-build.sh` lê, para
     cada ciclo, a rodada de letra mais alta que existir — senão a primeira (`c<C>/releitura.json`).
   - Despacho sem `<RODADA>` declarado → use o próprio ciclo (`c<C>`), que é o comportamento antigo
     (grava `c<C>/releitura.json`, igual a sempre).
   - **Veredito dos itens que você devolveu (J5b).** Todo item que você devolve (`contradiz`,
     `prescreve_mecanismo`, `omissoes_novas`, `cardinalidade`, `unicidade`)
     vira uma correção que quem te despachou vai promover no mesmo turno — e o fiscal da etapa exige
     linha de veredito por id promovido. **Quem julga escreve.** Acrescente, para cada item, uma
     linha em `<phase_dir>/.gad/intent/c<C>/vereditos.txt`, no formato de quatro campos de sempre:
     `<id> | releitura | confirmado | <categoria>`, com o `id` continuando a série do ciclo a partir
     do último já usado (nunca reaproveitando um id de achado). `classe: releitura` é o que distingue
     estas linhas das do consultor na tabela do INTENT-REVIEW.
   - **Re-sele o recibo.** Depois de acrescentar as linhas, regrave
     `<phase_dir>/.gad/intent/c<C>/vereditos.origem.json` com o sha256 novo e acrescente-se ao histórico:
     ```bash
     G() { bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/go-and-do/scripts/caminho-fase.sh" "<phase_dir>" "$1"; }
     V=$(G intent/c<C>/vereditos.txt); O=$(G intent/c<C>/vereditos.origem.json)
     jq --arg s "$(sha256sum "$V" | cut -d' ' -f1)" --arg t "$(date -Is)" --argjson n "$(grep -cvE '^\s*(#|$)' "$V")" \
        '.sha256=$s | .n_linhas=$n | .escritores += [{"agente":"gad-verificador","modo":"releitura","ts":$t}]' \
        "$O" > "$O.tmp" && mv -f "$O.tmp" "$O"
     ```
     Recibo ausente (ciclo sem verificação, ou fase antiga) → crie-o com o mesmo schema do
     `intent-verifica.md`, com `escritores` contendo só a sua entrada.
   - Você **não** decide destino nem promove nada: continua valendo o item 5 do
     `intent-verifica.md`. O que muda é que o veredito do que você achou não passa mais pela mão de
     quem você está auditando.
   - **Correção pós-releitura (`c<C>b`, `c<C>c`, …):** quem te despachou corrige no mesmo
     turno, gera **novo commit** e te despacha **de novo**. Cada releitura seguinte grava um
     arquivo **próprio** (`c<C>b/releitura.json`, `c<C>c/releitura.json`, …) — **não
     sobrescreve** o da rodada anterior do mesmo ciclo. O briefing do ciclo seguinte lê a
     rodada mais recente do ciclo (a de letra mais alta, senão a primeira). Invariante:
     `commit` e conjunto de `path` sempre idênticos ao `c<C>/correcoes.aplicado` vigente.

## Retorno (obrigatório, sem prosa antes ou depois)

Um objeto JSON só — **o mesmo que você gravou em disco** (abaixo com `<…>` e uniões `|`
para leitura; o que você devolve é JSON válido, sem cerca de código):

```
{
  "v": 2,
  "ciclo": <C>,
  "commit": "<commit do .aplicado, ou \"\" no ciclo vazio>",
  "artefatos": [{"path": "<caminho relativo>", "blob": "<blob do commit>"}],
  "contradiz": [{"ac_a": "AC-16", "ac_b": "AC-42", "porque": "<1 linha: o comportamento exigido por um é proibido pelo outro>"} | {"exigido_novo_sem_pergunta": "AC-nn"}],
  "prescreve_mecanismo": [{"path": "<caminho relativo>", "linha": <n>, "trecho": "<a prescrição, verbatim, ≤ 1 linha>"}],
  "omissoes_novas": [{"path": "<caminho relativo>", "o_que": "<o que ficou pendurado — ou a divergência PROSA-BLOCO-DIVERGE e os ids envolvidos>", "porque": "<por que é a emenda que abriu>"}],
  "cardinalidade": [{"path": "<caminho relativo>", "linha": <n>, "declarado": "<o número escrito>", "contado": <n>, "onde": "<AC-nn ou seção da lista>"}],
  "unicidade": [{"ac_a": "AC-nn", "ac_b": "AC-nn", "verificacao": "<a fixture, grep ou diff que derruba os dois>"}],
  "consistencia": "não_disponível",
  "ok": true,
  "observacao": "<opcional, 1 linha — só se você tropeçou em algo fora do escopo>"
}
```

`ok` = `true` quando as cinco listas (`contradiz`, `prescreve_mecanismo`,
`omissoes_novas`, `cardinalidade`, `unicidade`) estão vazias. Um `contradiz: []` honesto
passa — o gate cobra que você tenha respondido às perguntas, não quantas respostas deu.
Qualquer item → `ok: false`, e quem te despachou corrige no mesmo turno (novo
`c<C>b/correcoes`, novo commit, nova releitura) **antes** do briefing C+1; o
`briefing-build.sh` reprova `ok: false` em disco.
