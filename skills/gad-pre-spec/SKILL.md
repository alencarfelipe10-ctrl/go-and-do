---
name: gad-pre-spec
description: "Sessão interativa que produz o NN-PRE-SPEC.md de uma fase GSD — o insumo que a /go-and-do entrega ao gsd-spec-phase e ao gsd-discuss-phase antes da rodada. Abre a fase pelos mecanismos do GSD (init.phase-op, phase.insert), explica o objetivo dela em linguagem de leigo, investiga e mede o código de verdade (toda medição com fonte executada), entrevista você em blocos de AskUserQuestion com opções, recomendação e consequência, e grava o documento pelo molde único com o bloco gad:decisoes já preenchido e conferido pelo confere-pre-spec.sh. Regra fixa de PII: pessoas só por número ou papel. Rode antes de /go-and-do NN; não roda spec, não roda discuss, não despacha subagente."
argument-hint: "<NN> [--insumo <arquivo>]… [--so-molde] [--apos <M>]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - AskUserQuestion
---

<contrato>
- **Quem trabalha é você**, nesta janela, herdando o modelo da sessão. A skill **não despacha
  subagente** e `context: fork` é PROIBIDO (remove o AskUserQuestion). Foi assim nas 9 sessões
  reais que geraram PRE-SPEC; a única delegação já observada foi o `/advisor` antes de salvar.
- O produto é **um arquivo**: `<phase_dir>/<padded_phase>-PRE-SPEC.md`. O nome sai do
  `padded_phase` do GSD, nunca do argumento cru — é por esse caminho exato que o
  `abre-rodada.sh` da /go-and-do detecta o insumo (fase 2 → `02-PRE-SPEC.md`).
- **Não faz:** não roda `gsd-spec-phase` nem `gsd-discuss-phase`; não toca no ROADMAP além do
  `phase.insert` que o dono autorizar; não escreve instrução de execução (`--obs`, "como rodar
  esta fase"); não commita sem o dono pedir.
- Tudo em português do Brasil. O dono **não é técnico**: nada de jargão sem tradução na §1.
- **PII:** nenhuma pessoa aparece por nome — nem no corpo, nem nas citações, nem no bloco.
  Use papel ou número ("o cliente", "o responsável 1", "o aluno 7").
- **Número sem fonte executada nesta sessão é `[herdado]`**, fica no corpo com essa marca e
  **nunca** vira `fato_medido` no bloco. Precedente: uma fase montada sobre números de auditoria
  velha teve os números reprovados depois, quando foram re-derivados.
</contrato>

<setup>
```bash
S=~/.claude/skills/gad-pre-spec
D="${CLAUDE_SCRATCHPAD_DIR:-$(mktemp -d)}"
bash "$S/scripts/abre-fase.sh" "$NN"        # sem --criar: só olha
```
Modos de entrada:
- `--so-molde` → passos 0 e 4 só (grava o esqueleto do molde, bloco vazio `[]`) e **pare**.
  Diga ao dono, em uma frase, que o esqueleto **passa** no `confere-pre-spec.sh --so-bloco`
  (`entradas=0`, exit 0) porque bloco vazio é bem-formado — quem cobra decisão é o passo 6,
  não o script.
- `--insumo <arquivo>` (repetível) → transcrição, laudo ou print que abre a conversa. Lidos no
  passo 2. Extraia deles a lista de nomes de pessoas para o `--nomes` do passo 6.
- Arquivo já existe → **modo revisão**: leia o que está lá, resuma em 5 linhas o que já foi
  decidido, e entre no passo 3 só com o que falta. Nunca reescreva do zero uma decisão travada.
</setup>

## Passo 0 — abrir a fase pelos mecanismos do GSD

```bash
bash "$S/scripts/abre-fase.sh" "$NN" --criar
```
Devolve uma linha de JSON: `phase_found`, `dir`, `padded`, `alvo`, `existe`.

- `phase_found: true` → siga. `existe: true` → modo revisão.
- `phase_found: false` (exit 4) → a fase não está no ROADMAP. **Uma tela de AskUserQuestion**:
  (a) inserir no ROADMAP; (b) abortar. Se inserir, pergunte também **depois de qual fase**, e
  rode `abre-fase.sh <NN> --inserir "<nome>" --apos <M> --criar`.
  Avise o dono do que o GSD faz aqui: o `phase.insert` recebe a fase **anterior** e **calcula**
  o decimal seguinte (72 → 72.1). O número que sai pode não ser o que ele pediu — o script
  devolve `numero_atribuido` e `aviso_numero`; repasse a divergência com essas palavras.

Nunca invente `$NN-nova` como diretório: se o script não devolveu `dir`, é erro de ambiente, não
um caminho a adivinhar.

## Passo 1 — explicar a fase em linguagem de leigo

Leia `ROADMAP.md` (a entrada da fase), os requisitos citados no `REQUIREMENTS.md` e o que já
existe no código a respeito. Escreva **no terminal** (ainda não no arquivo), em ≤ 15 linhas e
sem jargão: qual é o problema, o que a fase entrega, como se percebe que funcionou.

Termine com **uma** pergunta aberta, em texto normal (não AskUserQuestion): *"é isso que você
tem em mente?"* — é aqui que o dono despeja o comportamento desejado e as particularidades do
negócio que a /go-and-do sozinha não acharia. Espere a resposta. Não avance sem ela.

## Passo 2 — investigar e medir

Trabalho inline (Bash, Read, Grep). Scripts auxiliares vão para o scratchpad, nunca para o repo.

- Toda afirmação sobre o código sai com `arquivo:linha` — o que você não leu não entra.
- Toda medição vira uma linha `o que se mediu · como (comando executado / fonte) · resultado`.
  Rode o comando de verdade nesta sessão. Se só copiou de um documento, marque `[herdado]`.
- Leia os `--insumo` aqui. Deles saem: a origem (§2), as regras de negócio ditadas pelo cliente
  (§7) e a lista de nomes para o gate de PII.
- Faltou informação que só o cliente tem? **Redija a pergunta** para o dono encaminhar, mostre-a,
  e espere a resposta antes de decidir o que depende dela. Foi assim nas fases reais: o dono cola
  a resposta e ela vira §7.

Ao final, apresente ao dono um resumo do que foi medido — números com fonte de um lado, números
`[herdado]` do outro.

## Passo 3 — perguntas ao dono (AskUserQuestion)

Proponha as decisões, **≤ 4 perguntas por tela**, cada uma com até 4 opções. Cada opção traz:

- **label** curto (a escolha);
- **description** com: o que muda na prática · a consequência · e, na recomendada, a palavra
  "recomendo" e o porquê em uma linha.

Regras da entrevista:
- Só pergunte o que muda o desenho. Detalhe que o spec resolve sozinho não vira tela.
- Quando o dono disser "deixa para o spec", registre como **aberto deliberadamente** (§9) — é
  uma resposta, não uma omissão.
- Quando a escolha for cara ou sem volta, pergunte na mesma tela **por quê** aceitar o custo:
  essa frase é a `justificativa` obrigatória do bloco.
- Registre as opções descartadas com o motivo. Elas viram §6 e `opcoes_descartadas` — memória do
  porquê, para a consultoria especializada da intenção não reabrir o assunto.

## Passo 4 — escrever o documento

O **nome da fase** sai do heading do ROADMAP (`### Phase NN: <nome>`) — leia-o de lá. O campo
`nome` do `abre-fase.sh` é só fallback: depois de um `phase.insert` o GSD devolve o *slug*
(`fase-inserida-de-teste`), e slug não é título de documento que o dono vai ler.

Materialize o esqueleto **sem `sed`** — nome de fase com `/` mata o `sed` e nome com `&`
corrompe o título em silêncio:

```bash
NN="$PADDED" NOME="$NOME_DO_ROADMAP" DATA="$(date +%F)" \
python3 -c 'import os,sys
t=open(sys.argv[1],encoding="utf-8").read()
for k in ("NN","NOME","DATA"): t=t.replace("{{%s}}"%k, os.environ[k])
open(sys.argv[2],"w",encoding="utf-8").write(t)' "$S/templates/PRE-SPEC.md" "$ALVO"
```
Depois preencha as 11 seções com Edit/Write. Regras do molde:

- Seção sem conteúdo fica com `— nada —`. **Nunca remova seção**: o leitor precisa saber que o
  assunto foi considerado e deu vazio.
- Os comentários HTML do molde dizem o que entra em cada seção — apague-os ao preencher.
- Nada de instrução de execução, nada de "escopo sugerido em planos", nada de `--obs`. O
  consumidor deste arquivo é o spec/discuss, não o executor.

## Passo 5 — bloco `gad:decisoes` (**gate mecânico**)

Monte o JSON da entrevista (nomes em português; veja o cabeçalho do script) e rode:

```bash
python3 "$S/scripts/gera-bloco.py" --entrada "$D/respostas.json" --arquivo "$ALVO"
```

O script traduz para o contrato v1, numera `PS-01…PS-99`, insere entre as marcas e **chama o
`confere-pre-spec.sh --so-bloco`**. Se reprovar, ele **restaura o arquivo** e sai ≠ 0.

**Nada é salvo com o bloco reprovado.** Não edite o bloco à mão para "passar": corrija a
resposta na entrada e rode de novo. Não altere o `confere-pre-spec.sh` — ele é o contrato.

O que entra no bloco:
- `decisao` (→ `decisao_dono`): cada decisão travada no passo 3. É o que o spec **não pode
  re-decidir**.
- `medicao` (→ `fato_medido`): só medição do passo 2 que sustenta uma decisão, e só com
  evidência reproduzível (`arquivo:linha` ou `comando → saída`). Fato **não** trava nada: entra
  no SPEC como `[medido:PS-nn]`, oferecido ao revisor para verificar.
- `requisito` = o `R-n`/`SC-n` do ROADMAP ou o ID do REQUIREMENTS do projeto (ex. `DESC-01`) quando existir; vazio vira `none`.
- `ressalva` só quando a medição tem limite real — ela **obriga** uma linha em "Limitações
  declaradas" no SPEC depois. Ressalva decorativa custa caro lá na frente.

Bloco vazio (`[]`) é bem-formado e **passa** no script (`entradas=0`, exit 0). Ele não é o gate
de conteúdo — o gate de conteúdo é o passo 6.

## Passo 6 — revisão antes de salvar (**gate humano — não pule**)

Três conferências, nesta ordem:

**(a) PII.** Junte num arquivo os nomes de pessoas que apareceram nos insumos e rode:
```bash
bash "$S/scripts/confere-pii.sh" "$ALVO" --nomes "$D/nomes.txt"
```
Exit ≠ 0 → **corrija o texto**, trocando o nome por papel ou número, e rode de novo. Achado
`PII-NOME-SUSPEITO` que for empresa, produto ou título de documento é falso positivo conhecido:
acrescente o termo ao `--permitidos` com um comentário dizendo por que não é pessoa — nunca
desligue a checagem.

**(b) Coerência.** Releia as decisões em conjunto: nenhuma contradiz outra; nenhuma decisão
contradiz o ROADMAP ou o REQUIREMENTS; nenhuma seção afirma número que a §4 não sustenta.
Contradição achada aqui vira pergunta ao dono, não conserto silencioso.

**(c) Ok do dono.** Mostre a lista final, uma linha por entrada:
`PS-nn · <decisão em uma frase> · <reversibilidade>` — mais a contagem de fatos medidos e a
lista do que ficou aberto deliberadamente. **Pergunte se pode gravar. Só grave com o ok.**

Com o ok, ofereça o commit (não faça sozinho): `docs(fase NN): PRE-SPEC`.

## Passo 7 — saída

Imprima, em quatro linhas:
```
Arquivo:   <caminho absoluto do NN-PRE-SPEC.md>
Bloco:     N decisões · M fatos medidos · K abertos deliberadamente
Conferido: confere-pre-spec.sh --so-bloco → ok · confere-pii.sh → limpo
Próximo:   /clear e depois  /go-and-do <NN>
```
