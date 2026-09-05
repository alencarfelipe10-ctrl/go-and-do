<!-- ============================================================ -->
<!-- prompts/categorias-achados.md — taxonomia canônica ÚNICA dos -->
<!-- achados da consultoria especializada de intenção (decisão   -->
<!-- 1.8 do gad-major). Injetado pelo briefing-build.sh no        -->
<!-- briefing dos consultores E referenciado pelo gad-verificador -->
<!-- — consultor e verificador julgam pela MESMA régua; duas      -->
<!-- redações derivariam.                                         -->
<!-- ============================================================ -->

# Categorias de achado (classifique TODO achado em exatamente uma)

- **A-produto** — faria o software errar em produção, trair um requisito ou
  abrir/deixar aberta uma brecha de segurança. *Ex.: o SPEC prescreve mudar o alvo de
  promoção sem tocar os 7 testes que asseveram o alvo antigo.*
- **B-viabilidade** — faria a execução da fase falhar ou exigir retrabalho (premissa
  falsa sobre o código/dados, dependência inexistente, plano insatisfazível). *Ex.: o
  CONTEXT assume tabela que a migration da fase anterior não criou.*
- **C-instrumentacao** — melhora medição, telemetria, logging ou tooling; o produto
  funciona sem isso. *Ex.: sugerir métrica extra no painel de rollout.*
- **D-documental** — corrige texto, nomenclatura ou consistência entre documentos, sem
  efeito no comportamento. *Ex.: contagem divergente entre SPEC e ROADMAP.*
- **E-decisao-do-dono** — não é defeito: é escolha de escopo/risco que só o dono pode
  fazer. *Ex.: aceitar ou não janela de indisponibilidade no deploy.*

**Regra de desempate (obrigatória para o verificador):** na dúvida entre A/B e C/D,
classifique para cima — a parada por custo marginal só olha A/B, e um achado A
fantasiado de C encerraria a revisão cedo demais. Na dúvida sobre o **vínculo ao
Goal**, o desempate é o inverso fora de A-produto: sem efeito medido que o achado
proteja, ele entra como `confirmado_irrelevante`, porque o custo do falso A é um ciclo
mais uma emenda — e a emenda é o que criou o defeito seguinte em três dos quatro ciclos
da fase medida. Achado `A-produto` na dúvida vai para cima nos dois eixos.

**Agrupamento:** achados C e D da mesma classe de erro entram como UM item de classe
com a lista de ocorrências, não N itens repetidos.
