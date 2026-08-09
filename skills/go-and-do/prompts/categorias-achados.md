<!-- ============================================================ -->
<!-- prompts/categorias-achados.md — taxonomia canônica ÚNICA dos -->
<!-- achados da revisão adversarial (decisão 1.8 do gad-major).   -->
<!-- Injetado pelo briefing-build.sh no briefing dos revisores E  -->
<!-- referenciado pelo gad-verificador — revisor e verificador    -->
<!-- julgam pela MESMA régua; duas redações derivariam.           -->
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

**Regra fail-up (obrigatória para o verificador):** na dúvida entre A/B e C/D,
classifique PARA CIMA (A/B). A parada por custo marginal do loop só olha A/B — um
achado A fantasiado de C encerraria a revisão cedo demais; o custo do fail-up é um
ciclo a mais, o custo do fail-down é defeito em produção.

**Agrupamento:** achados C e D da mesma classe de erro entram como UM item de classe
com a lista de ocorrências, não N itens repetidos.
