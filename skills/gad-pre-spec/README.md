# /gad-pre-spec

Sessão interativa que escreve o **`NN-PRE-SPEC.md`** de uma fase GSD — o insumo que a
`/go-and-do` entrega ao `gsd-spec-phase` e ao `gsd-discuss-phase` antes da rodada.

## O quê

Antes desta skill, cada PRE-SPEC nascia de uma cópia do anterior: 9 documentos reais, 3
linhagens divergentes, 4 convenções de nome e **zero** blocos `gad:decisoes` — o que obrigava
a `/go-and-do` a cair na rota legado (ler o documento inteiro como prosa). A skill fixa o molde
único, o nome do arquivo e o bloco legível por máquina.

Entrega:

- a fase aberta pelos mecanismos do GSD (`init.phase-op`, e `phase.insert` quando o dono
  autoriza), com o diretório certo;
- o documento pelo molde de 11 seções (`templates/PRE-SPEC.md`);
- o bloco `gad:decisoes` v1 preenchido a partir da entrevista e **conferido** pelo
  `confere-pre-spec.sh` da `/go-and-do`;
- gate de PII antes de salvar.

## Quando

Rode **antes** de `/go-and-do NN`, quando a fase tem contexto que a rodada sozinha não
descobriria: uma reunião com o cliente, um laudo, um débito conhecido, uma regra de negócio.
Não rode para fase trivial — o PRE-SPEC é insumo, não burocracia.

## Exemplo

```
/gad-pre-spec 24.4 --insumo ~/Downloads/transcricao-reuniao.md
```

Só o esqueleto, para escrever à mão:

```
/gad-pre-spec 99 --so-molde
```

## O que tem aqui

| Arquivo | Papel |
|---|---|
| `SKILL.md` | o roteiro (passos 0–7) que o Claude da sessão segue |
| `templates/PRE-SPEC.md` | o molde de 11 seções + marcas do bloco |
| `scripts/abre-fase.sh` | envelope do `init.phase-op`/`phase.insert` → JSON com `dir`, `padded`, `alvo`, `existe` |
| `scripts/gera-bloco.py` | respostas da entrevista (JSON em português) → bloco `gad:decisoes` conferido |
| `scripts/confere-pii.sh` | gate de PII: lista dura dos insumos + heurística "Nome Sobrenome" |
| `scripts/nomes-permitidos.txt` | termos capitalizados que nunca são pessoa (modelos, ferramentas, rótulos) |
| `tests/` | 4 suítes; `tests/roda.sh` roda todas |

## Testes

```bash
skills/gad-pre-spec/tests/roda.sh
```

A bancada é um `.planning/` sintético no scratchpad (`CLAUDE_SCRATCHPAD_DIR`, ou um temporário)
com um ROADMAP mínimo — o `init.phase-op` roda **de verdade** contra ele; nenhum teste toca
projeto real e nenhuma fixture tem nome de pessoa real.

O runner da raiz (`tests/roda.sh`) só enxerga `tests/test-*.sh` da **raiz do repo**: esta suíte
não é recolhida por ele e precisa ser chamada pelo caminho acima.

## Dois comportamentos que surpreendem

1. **Bloco vazio passa.** `confere-pre-spec.sh --so-bloco` aprova um `[]` (exit 0,
   `entradas=0`): `[]` é um array bem-formado e o laço de entradas roda zero vez. Não existe
   código `BLOCO-VAZIO`. Logo, o esqueleto do `--so-molde` é "válido" para o script — quem cobra
   decisão é o **passo 6** da skill (revisão + ok do dono). O `test-molde.sh` trava esse
   comportamento para que uma mudança futura no contrato apareça como falha aqui.
2. **O número da fase inserida é do GSD, não seu.** `phase.insert` recebe a fase **anterior** e
   calcula o decimal seguinte (72 → 72.1). Por isso `abre-fase.sh --inserir` exige `--apos <M>`
   e devolve `numero_atribuido` + `aviso_numero` quando difere do que foi pedido.
3. **`phase_name` volta como slug depois de um insert.** Medido na bancada: inserida a fase
   "Fase inserida de teste", o `init.phase-op` seguinte devolve
   `phase_name: "fase-inserida-de-teste"`. Por isso o passo 4 manda ler o nome do **heading do
   ROADMAP** (`### Phase NN: <nome>`) e tratar o campo `nome` do `abre-fase.sh` como fallback:
   slug não é título de documento que o dono vai ler.

## Falsos positivos do gate de PII

A heurística não entende semântica: nome de empresa, produto ou documento com duas palavras
capitalizadas ("Banco Central", "Pull Request", "Nota Fiscal") é acusado. O remédio é
acrescentar o termo a `scripts/nomes-permitidos.txt` (ou a um arquivo próprio via
`--permitidos`), **com um comentário dizendo por que não é pessoa** — nunca desligar a checagem.
Heading, bloco de código, código inline, caminho de arquivo e URL já são isentos da heurística;
a lista dura (`--nomes`, extraída dos insumos) vale em qualquer contexto.

## Instalação

```bash
ln -s /home/alencar/Projetos-Vox-AI/go-and-do/skills/gad-pre-spec ~/.claude/skills/gad-pre-spec
```
