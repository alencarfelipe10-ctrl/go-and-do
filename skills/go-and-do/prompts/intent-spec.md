<!-- prompts/intent-spec.md — filho de camada 2 (agente gad-spec) que hospeda o
     gsd-spec-phase para o subagente de intenção. Lido do disco PELO FILHO. -->

# Filho da intenção — SPEC (o quê)

O despacho te entrega `N`, `NN`, `project_root` e `phase_dir` (absolutos). Comece todo
bloco Bash com `cd "<project_root>"` e use caminhos absolutos em tudo.

## Trabalho

1. Se `<phase_dir>/NN-SPEC.md` já existe → não re-rode nada; vá direto ao retorno
   (`estado: done`, relendo os sinos do próprio artefato).
1b. **PRE-SPEC (insumo pré-travado).** Se o despacho trouxe `pre_spec: <caminho>`,
   `Read` o arquivo INTEIRO antes de invocar o workflow — ele nasceu numa sessão
   interativa com o usuário e suas decisões são **travadas**:
   - O workflow não re-decide nem contraria o que está lá; escolha `[auto]` que
     conflite com o PRE-SPEC → o PRE-SPEC vence.
   - Rastreabilidade: cada decisão do SPEC que veio do PRE-SPEC recebe a marca
     `[pre-spec]` na mesma linha (análogo ao `[auto]` — o briefing do revisor enumera
     as duas marcas e o revisor sabe que `[pre-spec]` tem dono).
   - Conflito irreconciliável entre PRE-SPEC e ROADMAP/REQUIREMENTS → **sino**, nunca
     resolução silenciosa (grave em `.sinos-spec.txt` como os demais).
2. Invoque `Skill` → `gsd-spec-phase` com args `N --auto`. Ele deriva requisitos
   falsificáveis do ROADMAP/REQUIREMENTS, escolhe os defaults recomendados logando cada
   escolha `[auto]`, e escreve+commita o `NN-SPEC.md` com o score de ambiguidade.
   Termina no SPEC — não tem auto-advance.
3. **Fronteira de conteúdo (anti-duplicação):** o SPEC é a fonte canônica de decisões,
   requisitos e critérios. Se o workflow te levar a repetir num segundo lugar um
   parágrafo que já está no SPEC, escreva a referência (seção/âncora), não a cópia.

## O que vira sino

- Dimensões de ambiguidade abaixo do mínimo (log `[auto] Max rounds reached…`).
- Edges `unclassified` que o probe deixou como pergunta nomeada (log
  `[auto] unclassified — RN…`).
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
sinos: [<um item por linha; ausente se vazio>]
pergunta: <só no estado pausa — a decisão pendente com opções e sua recomendação primeiro>
```
