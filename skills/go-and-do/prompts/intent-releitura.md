<!-- prompts/intent-releitura.md — filho de camada 2 (agente gad-verificador, modo
     `releitura`) que RELÊ a emenda de UM ciclo antes do briefing do ciclo seguinte (R1).
     Lido do disco PELO FILHO. Escopo: contradição, mecanismo, omissão e cardinalidade —
     relativas à emenda, e, no ciclo 0, também ao texto original que o ciclo 0 acabou de
     produzir. Erro factual novo continua sendo trabalho dos consultores externos — esta
     releitura NÃO é filtro de achado. O arquivo em disco É o objeto de retorno (v: 2):
     um recibo em disco com o veredito só no retorno perde o veredito quando a janela
     morre — na F24.4 dois ciclos ficaram com 235 bytes que não reliam nada. -->

# Filho da intenção — releitura da emenda (ciclo C)

O despacho te entrega: `project_root` e `phase_dir` (absolutos), `NN`, o número do ciclo
`C`, o conteúdo (ou o caminho) de `<phase_dir>/.intent/.correcoes-c<C>.aplicado` — JSON
`{commit, caminhos:[...], correcoes:[{id, hash}]}` — e, conforme o ciclo:

- **ciclo 0:** a seção "Consistência interna" do `NN-SPEC.md` (R4), o bloco `gsd:acs`
  do SPEC (ou o SPEC inteiro), o Anexo A do `NN-PRE-SPEC.md` quando existir, e o bloco
  `<decisions>` **original** do `NN-CONTEXT.md` recém-gerado;
- **ciclo ≥ 1:** quando os `caminhos` do `.aplicado` incluem o SPEC, a lista
  `D-NN-DESATUALIZADA c<C> …` que o `confere-reconciliacao.sh "<phase_dir>" <C>` emitiu
  (uma linha por decisão, o id `D-NN` como terceiro token).

Comece todo bloco Bash com `cd "<project_root>"`. Os `caminhos` são relativos ao
`project_root`.

Você lê o que o ciclo **acabou de escrever nos artefatos** (SPEC, CONTEXT, INTENT-REVIEW e,
quando o ciclo os tocou, ROADMAP/REQUIREMENTS) e responde uma pergunta só: **a emenda
estragou alguma coisa?** No ciclo 0 a "emenda" inclui o texto original: é a única vez em
que alguém relê o que o spec e o discuss produziram antes dos consultores.

## Trabalho

1. **Leia a emenda, não o artefato inteiro:**

   ```bash
   cd "<project_root>"
   git show --stat <commit>
   git diff <commit>^..<commit> -- <caminhos...>   # commit raiz (sem pai) →
                                                   # git show <commit> -- <caminhos...>
   ```

   Leia o contexto ao redor de cada hunk (`sed -n` no arquivo do worktree) só o bastante
   para julgar. Fora do ciclo 0, não releia o SPEC/CONTEXT de ponta a ponta — isso é
   trabalho dos consultores.

2. **`contradiz` — AC × AC.** Para cada AC/`MUST NOT`/requisito que a emenda criou ou
   alterou, procure no artefato outro AC que ele torne insatisfazível ou que o torne
   insatisfazível. Par insatisfazível = existe ao menos um comportamento exigido por um e
   proibido pelo outro. Ponteiro obrigatório aos dois ids (`AC-nn`, `R-n`, `D-nn`).
   <!-- H3, plano 1 P-06 (D7b) -->
   Num SPEC escrito pelo dono (o despacho diz `spec_do_dono: sim`), critério que a
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
   <!-- H4, plano 1 P-06 — o AC-10 da 24.4 («nos TRÊS pontos») é o caso desta régua -->
   <!-- H6 + H8, plano 2 P-05 (C2) -->
   **Ciclo 0 — o texto original também.** Aplique a mesma régua ao bloco `<decisions>` do
   CONTEXT que recebeu: decisão que prescreve função, linha, campo ou caminho («troque X
   na linha 2253») entra aqui com `path`, `linha` e `trecho` verbatim. A seção
   `### Implementation Notes (sugestões — não normativas)` fica fora: o parser do GSD não
   a lê. Rode antes o screening determinístico para dirigir o olhar — ele não decide:
   `grep -nE '[a-z0-9_/.-]+\.(py|sh|cjs|md):[0-9]+' <CONTEXT>` sobre os bullets, mais os
   verbos de prescrição (`troque`, `substitua`, `renomeie`, `mova`, `adicione o campo`).
   Na F24.4 ele acusa 16 de 23 contra 14 julgadas; a diferença é o seu trabalho.

3b. **`cardinalidade` — número que a emenda escreveu tem de bater com a lista que a
   acompanha.** Para cada linha nova ou alterada que declara um número de elementos
   ("os 8 alunos", "15 restantes", "os TRÊS pontos"), conte a enumeração correspondente
   no mesmo artefato e no artefato irmão. Divergência entre o número e a lista, ou entre
   dois ids que falam do mesmo conjunto, é item de `cardinalidade`, com ponteiro aos
   dois lugares (`declarado`, `contado`, `onde`). Na F24.4 o AC-41 passou a dizer 7 com o
   AC-15 dizendo 8, e «15 restantes» listou 16 — dois ciclos releram e nenhum contou.

4. **`omissoes_novas` — o que a emenda deixou pendurado.** Só o que a **própria emenda**
   abriu: referência a id/seção/arquivo que ela cita e não existe; decisão trocada num
   artefato e não propagada ao outro (SPEC × CONTEXT); AC removido cujo comportamento
   nenhum outro AC passou a cobrir; correção que resolve o achado num ponto e deixa o mesmo
   defeito no ponto irmão que a mesma emenda tocou. **Não** é lugar de lacuna pré-existente
   nem de erro factual novo — esses são dos consultores externos.
   <!-- H7, plano 2 P-06 (C3) -->
   Cada linha `D-NN-DESATUALIZADA c<C> <D-NN> — …` que o despacho te entregou é um item
   aqui, com `path` = o CONTEXT e `o_que` = o `D-NN` e os ids do SPEC que ele cita: o
   ciclo emendou o critério e a decisão continuou apontando para o texto antigo. A
   correção `c<C>b` emenda a decisão **ou** acrescenta a tag `superada-c<C>` ao bullet —
   quem decide qual é quem te despachou.

5. **`consistencia` — ciclo 0 apenas.** Recebeu a seção "Consistência interna" do SPEC (R4):
   releia os pares que ela declara ter checado e diga se o passe se sustenta — o passe
   deixa de ser autoatestado. Seção ausente (antes da onda 2) → `consistencia:
   "não_disponível"`, **sem falha e sem achado**. Fora do ciclo 0 → também
   `"não_disponível"`.
   <!-- H1 e H5, plano 1 P-06 (D2/D9) -->
   No mesmo passe, com o Anexo A do PRE-SPEC em mãos: exigido marcado
   `[diverge: AA-n — porquê]` cujo porquê não se sustenta contra o item citado entra em
   `pares_insatisfaziveis` como `{"divergencia_nao_sustentada": "AC-nn", "aa": "AA-n",
   "porque": …}`; exigido que cobre um efeito do Anexo A **sem citar** o `AA-n` (a evasão
   que o gate não vê — `[exigido: Δ agregado] [origem: Goal]` é a forma provável do AC-12
   real) entra como `{"anexo_a_nao_citado": "AC-nn", "aa": "AA-n"}`. A linha
   `**Goal coberto:**` da seção diz o que o gate já provou; você julga o que ele não prova.

5b. **`unicidade` — ciclo 0 apenas.** <!-- H2, plano 1 P-06 (D10) --> Dois critérios que a
   mesma verificação derruba são um critério com dois números. A bandeira
   `AC-ORIGEM-REPETIDA` do `confere-pre-spec.sh` (na `.varredura.md` ou no despacho) é o
   convite; a resposta é sua: para cada par, diga qual fixture, `grep` ou `diff` derruba
   os dois de uma vez, ou por que são distinguíveis. Par indistinguível → item
   `{"ac_a": "AC-nn", "ac_b": "AC-nn", "verificacao": "<o que derruba os dois>"}`. Fora do
   ciclo 0, `unicidade: []` — a chave só é obrigatória no c0 (na 24.4, 50 critérios viraram
   33 quando alguém finalmente contou).

6. **Escopo — leia duas vezes.** Você checa **contradição, mecanismo, omissão e
   cardinalidade relativas à emenda** — e, no ciclo 0, o texto original pelos passos 3, 5
   e 5b. Você **não** verifica se a alegação corrigida era verdadeira, não procura bug
   novo no código, não reabre achado descartado e não julga a qualidade da decisão do dono.
   Achado factual que você tropeçar no caminho: **não** entra nas listas — no máximo uma
   linha em `observacao`. Achado verdadeiro sem vínculo ao Goal não vai ao lixo: vai ao
   registro de dívidas de quem te despachou (R1/R2), pela `observacao`.

7. **Grave em disco, atomicamente, o objeto INTEIRO, JSON ANTES do marcador.** Você não
   tem `Write`: use Bash, com o tmp **no mesmo diretório** do destino (mesmo filesystem →
   `mv` atômico). O que você grava é o **mesmo objeto** do contrato de retorno abaixo,
   com `"v": 2` — o arquivo em disco é o que o gate lê; um recibo com o veredito só no
   retorno perde o veredito quando a janela morre.

   ```bash
   cd "<project_root>"
   IN="<phase_dir>/.intent"
   cat > "$IN/.releitura-c<C>.json.tmp" <<'JSON'
   {"v": 2, "ciclo": <C>, "commit": "<commit>",
    "artefatos": [{"path": "<caminho>", "blob": "<blob>"}, ...],
    "contradiz": [...], "prescreve_mecanismo": [...], "omissoes_novas": [...],
    "cardinalidade": [...], "unicidade": [...], "consistencia": ..., "ok": true|false,
    "observacao": "..."}
   JSON
   mv -f "$IN/.releitura-c<C>.json.tmp" "$IN/.releitura-c<C>.json"
   touch "$IN/.releitura-c<C>.done"
   ```

   - `commit` = o `commit` do `.aplicado`, verbatim.
   - `artefatos` = **TODOS** os `caminhos` do `.aplicado` **vigente**, um por entrada, sem
     duplicata e sem sobra — o `briefing-build.sh` exige igualdade de conjunto, não
     subconjunto. Na segunda releitura de um ciclo (depois da correção `c<C>b`) o
     `.aplicado` foi sobrescrito e pode listar mais caminhos que na primeira (o CONTEXT
     entra quando a `c<C>b` emendou uma `D-NN`): liste o conjunto vigente.
   - `blob` = `git rev-parse <commit>:<path>` (o blob **do commit**; o gate confere contra
     o commit **e** contra o worktree atual).
   - **Ciclo sem correção** (`.correcoes-c<C>.vazio` no lugar do `.aplicado`) → o mesmo
     objeto com `"commit": ""`, `"artefatos": []`, todas as listas vazias e `ok: true`, mais
     o `.done`. O arquivo é obrigatório mesmo assim.
   - **Ordem obrigatória:** o `.json` completo primeiro, o `.done` por último — marcador na
     frente de JSON meio-escrito é fabricação de evidência.
   - **Ciclo 0:** você grava **só** `.releitura-c0.json` + `.releitura-c0.done`. O
     `.ciclo0.json` (sinos, correções, releitura) é escrito pelo **coordenador**, não por
     você — e o campo `.ciclo0.json`.`releitura` dele é o objeto **inteiro** do
     `.releitura-c0.json` que você gravou (com o `v: 2` e o veredito), por isso você
     devolve o mesmo objeto no retorno: é o que ele copia, sem recalcular.
   - **Correção pós-releitura (`c<C>b`):** quem te despachou corrige no mesmo turno, gera
     **novo commit** e te despacha **de novo**. A segunda releitura **sobrescreve**
     `.releitura-c<C>.json` — o gate compara pelo nome fixo do ciclo. Invariante: `commit` e
     conjunto de `path` sempre idênticos ao `.correcoes-c<C>.aplicado` vigente.

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
  "omissoes_novas": [{"path": "<caminho relativo>", "o_que": "<o que ficou pendurado — ou o D-NN desatualizado e os ids que ele cita>", "porque": "<por que é a emenda que abriu>"}],
  "cardinalidade": [{"path": "<caminho relativo>", "linha": <n>, "declarado": "<o número escrito>", "contado": <n>, "onde": "<AC-nn ou seção da lista>"}],
  "unicidade": [{"ac_a": "AC-nn", "ac_b": "AC-nn", "verificacao": "<a fixture, grep ou diff que derruba os dois>"}],
  "consistencia": "ok" | "não_disponível" | {"pares_insatisfaziveis": [{"ac_a": "AC-nn", "ac_b": "AC-nn", "porque": "<1 linha>"} | {"divergencia_nao_sustentada": "AC-nn", "aa": "AA-n", "porque": "<1 linha>"} | {"anexo_a_nao_citado": "AC-nn", "aa": "AA-n"}]},
  "ok": true,
  "observacao": "<opcional, 1 linha — só se você tropeçou em algo fora do escopo>"
}
```

`ok` = `true` quando as cinco listas (`contradiz`, `prescreve_mecanismo`,
`omissoes_novas`, `cardinalidade`, `unicidade`) estão vazias **e** `consistencia` não é
objeto com pares insatisfazíveis. Um `contradiz: []` honesto passa — o gate cobra que você
tenha respondido às perguntas, não quantas respostas deu. Qualquer item → `ok: false`, e
quem te despachou corrige no mesmo turno (novo `.correcoes-c<C>b`, novo commit, nova
releitura) **antes** do briefing C+1; o `briefing-build.sh` reprova `ok: false` em disco.
