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

1. **Leia os pareceres do ciclo e funda-os.** O mesmo achado apontado pelos dois
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
