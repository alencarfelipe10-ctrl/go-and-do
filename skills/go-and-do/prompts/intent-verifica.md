<!-- prompts/intent-verifica.md — filho de camada 2 (agente gad-verificador) que funde,
     deduplica e verifica os pareceres adversariais de UM ciclo. Lido do disco PELO
     FILHO. Ele devolve VEREDITOS; o destino de cada achado é da camada 1. -->

# Filho da intenção — verificação de pareceres (ciclo C)

O despacho te entrega: `project_root` e `phase_dir` (absolutos), o número do ciclo `C`,
os caminhos dos pareceres deste ciclo (`<phase_dir>/pareceres/NN-parecer-*-c<C>.md`),
os caminhos de `NN-SPEC.md` e `NN-CONTEXT.md`, e — do ciclo 2 em diante — o caminho do
`NN-INTENT-REVIEW.md` parcial com a tabela dos achados já triados. Comece todo bloco
Bash com `cd "<project_root>"`.

## Trabalho

0. **Modo pipeline (quando o despacho traz marcadores `.done-c<C>-*` e um deadline).**
   As lanes ainda podem estar rodando — o `.md` do parecer só vale quando o marcador da
   lane existir. Espere primeiro o do Codex (chega antes) com um loop barato num único
   Bash (`until [ -f <marcador> ] ...; do sleep 15; done`, teto = deadline) e execute
   os passos 1–4 sobre esse parecer enquanto o agy termina; depois espere o marcador do
   agy e incorpore o parecer dele (funda com o que você já verificou — só os achados
   que ele acrescenta ou corrobora geram trabalho novo). Marcador que não chegou no
   deadline, ou `.md` vazio com marcador presente → devolva a lane no retorno como
   `sem_parecer: <lane>` e siga com o que tem — a regra de degradação é de quem te
   despachou, não sua.

1. **Piso mecânico antes de ler:** rode
   `$HOME/.claude/skills/go-and-do/scripts/confere-ciclo.sh --tabela <parecer(es)>` —
   ele extrai o esqueleto dos achados estruturais (lane · linha · severidade). Sua
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
   real antes de confirmar.
4. **Verifique cada achado `novo`/`reaberto` contra o código/dados** (Read/Grep
   pontuais; nunca aceite sem conferir — em fase real o mesmo parecer acertou uma
   lacuna que 4 planos não viram E errou uma atribuição de dados). Vereditos:
   - `confirmado` — a alegação se sustenta; evidência própria `arquivo:linha`.
   - `nao_sustentado` — a verificação derrubou; registre o porquê em 1 linha (é o que
     evita re-litigar o mesmo falso achado no ciclo seguinte).
   - `ja_coberto` — os artefatos já cobrem a alegação; ponteiro para a seção do
     SPEC/CONTEXT (ou achado anterior) onde está coberto.
5. Você **não** decide destino (correção factual × pausa de negócio × transparência) —
   isso é alçada de quem te despachou. Seu produto termina no veredito.
6. **Prova de máquina de que você rodou (v1.8.2):** como último ato antes do retorno,
   `touch <pareceres_dir>/.verificador-c<C>.done` — é este marcador que o
   `confere-rotas.sh` cruza com a `.tabela-c<C>.txt` no fecho da etapa para provar que
   a rota de verificação independente foi respeitada. Só grave DEPOIS de os vereditos
   estarem prontos; marcador sem trabalho é fabricação de evidência.

## Retorno (obrigatório, sem prosa antes ou depois)

```
ciclo: <C>
achados_brutos: <n no(s) parecer(es), antes da fusão>
achados_fundidos: <n após dedup entre revisores>
convergencias: <n achados com fontes: [codex, agy]>
ponteiros_quebrados: <n reportados pelo spot-check; 0 se nenhum>
achados:
  - id: c<C>-<seq>
    alegacao: <1-2 linhas>
    fontes: [codex|agy|codex, agy]
    classe: novo | reformulado | reaberto
    ref_anterior: <id do achado original — só p/ reformulado/reaberto>
    veredito: confirmado | nao_sustentado | ja_coberto   ← ausente p/ reformulado
    evidencia: <arquivo:linha própria da SUA verificação, ou o porquê da queda, ou o ponteiro do já-coberto>
    severidade: <a estimada pelo revisor, mantida para a triagem>
    toca_requisito_ou_criterio: sim | nao   ← sim = candidato a pausa de negócio na triagem
```
