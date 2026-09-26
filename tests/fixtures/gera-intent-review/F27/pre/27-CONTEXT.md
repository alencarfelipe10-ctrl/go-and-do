# Phase 27: Executável Windows - Context

**Gathered:** 2026-09-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Segundo pacote de entrega, só para Windows: uma pasta zipada com runtime CPython 3.12 embutido, os 7 pacotes do motor compilados (sem fonte) e um lançador fora deles que configura a primeira abertura em AppData, sobe o Uvicorn em 127.0.0.1:8000 numa janela visível e abre o navegador. O pacote é montado e testado (Windows × Linux, régua digest_abas) por workflow manual no espelho do GitHub, alimentado por uma publicação clean-room ampliada; pacote Docker e motor ficam sem diff.

</domain>

<spec_lock>
## Requirements (locked via SPEC.md)

**9 requirements are locked.** See `27-SPEC.md` for full requirements, boundaries, and acceptance criteria.

Downstream agents MUST read `27-SPEC.md` before planning or implementing. Requirements are not duplicated here.

**In scope (from SPEC.md):**
- Pasta zipada para Windows com runtime Python 3.12 embutido, `iniciar.bat` e `redefinir-senha.bat`
- Lançador fora dos 7 pacotes: primeira configuração em AppData, variáveis de ambiente antes do import, Uvicorn em 127.0.0.1:8000, janela com aviso e v3.1, abertura do navegador
- Compilação dos 7 pacotes para Windows e auditoria de ausência de fonte na pasta entregue
- Workflow manual do GitHub Actions no espelho que monta e testa (Windows) e gera a referência (Linux)
- Ampliação da publicação clean-room para levar os arquivos de montagem, sob o gate de PII
- Tutorial Windows novo, dentro do zip
- Testes do lançador e do pacote (os que dependem de Windows pulam fora dele)
**Out of scope (from SPEC.md):**
- .exe único autoextraível (onefile) — descartado pelo dono (PS-01)
- Serverless / hospedar o serviço — descartado pelo dono (PS-01, ROADMAP)
- Mudar o pacote Docker, o fluxo `subir.bat`/`criar-senha.bat` ou congelar o pacote da Fase 26 — PS-09
- Mudar o motor, a trava de identidade, a lista de escolas ou as telas do app — PS-03, PS-07, PS-10
- Assinatura de código, liberação no antivírus ou executável de teste prévio — decisão do dono (direção 6 do ROADMAP): se o TI bloquear, o Átila pede liberação
- Comparação com dado real contra o pacote Docker — acontece depois do fechamento e não trava o UAT (PS-08)
- Opção de desligar a trava de identidade no pacote Windows — PS-10 pede a trava ligada
- Publicar `Dockerfile`/`deploy/`/`scripts/` do Docker no espelho — FU-11-01 segue diferido; esta fase publica só o que a montagem Windows usa
- Instalador, atalho na área de trabalho, serviço do Windows ou início automático — PS-01 fixa pasta + .bat
- Versão na tela do app — PS-07 (só na janela)

</spec_lock>

<decisions>
## Implementation Decisions

### PS-01 — Formato de entrega
- **D-01 [pre-spec:PS-01, informational]:** ver `27-SPEC.md`, linha `[pre-spec:PS-01]` — Entrega em pasta zipada com atalho .bat;

### PS-02 — Onde monta
- **D-02 [pre-spec:PS-02, informational]:** ver `27-SPEC.md`, linha `[pre-spec:PS-02]` — Montagem no GitHub Actions (Windows) no repositório espelho…

### PS-03 — Primeira configuração
- **D-03 [pre-spec:PS-03, informational]:** ver `27-SPEC.md`, linha `[pre-spec:PS-03]` — Na primeira abertura o programa pede usuário e…

### PS-04 — Local da configuração
- **D-04 [pre-spec:PS-04, informational]:** ver `27-SPEC.md`, linha `[pre-spec:PS-04]` — A configuração fica na pasta do usuário do…

### PS-05 — Esqueci a senha
- **D-05 [pre-spec:PS-05, informational]:** ver `27-SPEC.md`, linha `[pre-spec:PS-05]` — Um redefinir-senha.bat apaga a configuração;

### PS-06 — Janela
- **D-06 [pre-spec:PS-06, informational]:** ver `27-SPEC.md`, linha `[pre-spec:PS-06]` — Janela visível enquanto roda, avisando para não fechar;

### PS-07 — Versão exibida
- **D-07 [pre-spec:PS-07, informational]:** ver `27-SPEC.md`, linha `[pre-spec:PS-07]` — A janela exibe a versão como v3.1;

### PS-08 — Aceitação
- **D-08 [pre-spec:PS-08, informational]:** ver `27-SPEC.md`, linha `[pre-spec:PS-08]` — Fecha a fase o teste automático no Windows…

### PS-09 — Pacote Docker
- **D-09 [pre-spec:PS-09, informational]:** ver `27-SPEC.md`, linha `[pre-spec:PS-09]` — O pacote Docker continua sendo gerado pelo processo…

### PS-10 — Proteção do código
- **D-10 [pre-spec:PS-10, informational]:** ver `27-SPEC.md`, linha `[pre-spec:PS-10]` — A proteção da Fase 26 vale para o…

### Lançador (windows/lancador.py)
- **D-11 [auto, R2, R3]:** A configuração é um único arquivo JSON UTF-8 em %APPDATA%\ReconhecimentoReceita\config.json com exatamente as chaves ADMIN_USER, ADMIN_HASH e SECRET_KEY (conteúdo e validações: ver 27-SPEC.md §Requirements R2 · AC-03, AC-06, AC-07); o nome da pasta não contém nome nem código de escola. O mesmo lançador é o único dono desse caminho: iniciar lê/cria, `redefinir-senha.bat` chama o lançador em modo de apagar (ver 27-SPEC.md R3 · AC-05). Falha visível: qualquer arquivo gravado dentro da pasta do programa, configuração parcial aceita após interrupção, ou o caminho da configuração escrito em dois lugares diferentes (bat e lançador) que possam divergir.
  evidence: src/web/config.py:38-40
  options: **JSON em %APPDATA%\ReconhecimentoReceita\config.json; redefinir via o próprio lançador (recomendada)** (chosen) · Arquivo .env-like em %APPDATA%; redefinir com rmdir direto no .bat · Registro do Windows (HKCU)
  question: Onde e em que formato o lançador grava a configuração da primeira abertura, e como o redefinir-senha a apaga?
  JSON foi escolhido por ser lido pela biblioteca padrão sem dependência nova e por deixar a validação (chave faltando, hash que não começa com $argon2id$, arquivo truncado) trivial e fail-closed. O modo de apagar não é um atalho de teste: ele só remove a configuração e nunca dispensa a pergunta de senha (AC-24). Ter o caminho num lugar só evita que o .bat apague uma pasta e o lançador leia outra.
- **D-12 [auto, R4]:** O servidor roda dentro do próprio processo do lançador (um processo Python, sem workers, sem reload, sem subprocesso), escutando só em 127.0.0.1:8000; antes de subir, o lançador verifica se a porta está livre e, se não estiver, mostra mensagem legível sem traceback e não abre o navegador; o navegador só é aberto depois que GET /login responde; a janela mostra o literal v3.1 e o aviso de não fechar; o lançador não define ENVIRONMENT (o cookie https_only quebraria o login em http). Critérios: ver 27-SPEC.md R4 · AC-08..AC-12. Falha visível: qualquer processo filho do servidor (fechar a janela deixaria órfão), escuta fora do loopback, ou ENVIRONMENT=production no ambiente do lançador.
  evidence: src/web/app.py:102
  options: **Uvicorn no mesmo processo do lançador, checagem prévia de porta, navegador após /login responder (recomendada)** (chosen) · Lançador dispara uvicorn como subprocesso e supervisiona · Uvicorn via linha de comando direta no iniciar.bat, sem lançador
  question: Como o lançador sobe o servidor, trata porta ocupada, abre o navegador, mostra a versão e garante que fechar a janela desliga tudo?
  Processo único é o que torna o AC-11 verdadeiro por construção: o Windows encerra todos os processos anexados ao console quando a janela fecha, e sem processo filho não há órfão. O throttle de login e o _store de download vivem na memória do processo (mesma razão do -w 1 do Docker). A versão v3.1 é constante literal no lançador — o campo version do pyproject (0.1.0) não é tocado. Descartado: subprocesso uvicorn (cria filho que pode sobreviver ao fechamento da janela) e pythonw/janela oculta (contraria PS-06).
- **D-13 [auto, R5]:** O lançador importa só biblioteca padrão, uvicorn, hash_password (para gerar_hash) e web.app — este último só depois de as 3 variáveis estarem definidas — e não contém nome nem código de escola nem lógica de identidade, cálculo ou relatório; não expõe nenhuma flag ou variável que pule a senha ou mexa na trava (ver 27-SPEC.md R5 · AC-14, AC-15, AC-24). Falha visível: import de parsing/calculation/comparison/report/domain, qualquer literal de escola, ou qualquer opção além de --redefinir.
  evidence: src/hash_password/__init__.py:19
  options: **Somente stdlib + uvicorn + hash_password + web.app, sem flags além de --redefinir (recomendada)** (chosen) · Lançador também compilado pelo Cython
  question: O que o lançador pode importar e conter, sendo ele o único código legível da pasta?
  O lançador fica fora do conjunto compilado (PS-10) e portanto legível; limitar suas dependências ao mínimo é o que impede que ele vire um vazamento da lógica protegida. gerar_hash é a mesma função compilada que o criar-senha.bat do Docker usa, então o formato do hash é idêntico.

### Atalhos .bat (iniciar.bat, redefinir-senha.bat)
- **D-14 [auto, R1]:** A raiz da pasta entregue contém só iniciar.bat, redefinir-senha.bat, o tutorial Windows e uma subpasta programa/ (runtime CPython 3.12 + lancador.py); cada .bat resolve tudo relativo à própria localização (%~dp0), entre aspas, e chama o python.exe de programa/runtime em modo isolado (-I), para que PYTHONPATH, PYTHONHOME e o site do usuário não influenciem o import. Os .bat são versionados com CRLF pelo .gitattributes. Falha visível: .bat que depende do diretório atual, caminho sem aspas (quebra com espaço/acento, AC-21), chamada a python/py do PATH (AC-01/AC-02), ou execução sem -I (uma variável de ambiente poderia sombrear um pacote compilado — AC-14).
  evidence: .gitattributes:3
  options: **Raiz com 2 .bat + tutorial; programa/ com runtime e lançador; python -I via %~dp0 (recomendada)** (chosen) · Tudo na raiz, sem subpasta · Atalho .lnk em vez de .bat
  question: Como fica a árvore da pasta entregue e como os .bat chamam o runtime?
  Deixar só os dois atalhos e o tutorial na raiz reduz a chance de o Átila clicar no arquivo errado. O modo isolado fecha o único caminho plausível de desligar a trava sem mexer na pasta: um PYTHONPATH apontando para um pacote parsing falso. chcp 65001 no início dos .bat deixa os acentos legíveis (AC-08). Descartado: lancador.py na raiz (confunde o usuário) e .bat chamando uvicorn direto (perde a primeira configuração).

### Runtime embutido e receita de montagem
- **D-15 [auto, R1]:** O runtime é uma distribuição CPython 3.12 completa e relocável (python-build-standalone, a mesma que o uv instala), copiada inteira para programa/runtime, com as dependências e os 7 pacotes compilados instalados no site-packages dele; não há venv nem caminho absoluto da máquina de montagem em nenhum arquivo do runtime. Falha visível: runtime de outro minor que não 3.12 (as extensões não carregam), pyvenv.cfg ou ._pth com caminho da máquina de montagem, ou o app só subir se a pasta estiver no mesmo caminho da montagem (AC-21 pega).
  evidence: pyproject.toml:4
  options: **CPython 3.12 python-build-standalone copiado para programa/runtime (recomendada)** (chosen) · Pacote embeddable oficial do python.org 3.12 · PyInstaller --onedir · venv copiado
  question: Qual runtime Python vai na pasta e como ele fica relocável?
  Descartados: venv (o pyvenv.cfg aponta o interpretador base por caminho absoluto — não sobrevive à extração em outra pasta); PyInstaller onedir (guarda bytecode num arquivo-contêiner, aumenta atrito com antivírus e complica a auditoria do AC-13); pacote embeddable do python.org (funciona, mas exige editar o ._pth e não traz pip nem estrutura padrão de site-packages — é a alternativa se o standalone falhar).
- **D-16 [auto, R5]:** A receita (script Python em windows/, rodado no runner Windows) compila os 7 pacotes pelo hook Cython do pyproject.toml, com a mesma chave do builder do Dockerfile (HATCH_BUILD_HOOK_ENABLE_CYTHON=1) e as versões exatas do uv.lock (conjunto sem dev), instala no runtime, remove da árvore toda fonte dos 7 pacotes e roda a auditoria do AC-13 sobre a pasta final; a auditoria é código separado da montagem, reprova o run e declara sua própria lista dos 7 pacotes, presa por teste à _SETE_PACOTES da Fase 26 (tests/deploy/test_image_audit.py:41). Falha visível: build que 'passa' sem gerar .pyd para algum módulo, versões de dependência diferentes do lock, ou auditoria que só roda quando a montagem já decidiu que está tudo certo.
  evidence: Dockerfile:111-112
  options: **Build com o hook do pyproject + lock exato; auditoria separada que reprova o run (recomendada)** (chosen) · Compilar com cythonize direto na receita, fora do hatch
  question: Como os 7 pacotes são compilados e instalados no runtime Windows, e como a ausência de fonte é auditada?
  Mesma chave e mesmo lock que o Docker usam é o que sustenta a comparação Windows × Linux. A contagem por módulo (.pyd por .py de src) é a defesa contra o caso em que o glob do hook (./src/web/* com barra) não case no Windows e o wheel saia sem compilar — nesse caso o run fica vermelho e o conserto passa a ser uma mudança no pyproject que precisa manter a saída do build Docker idêntica. A lista própria com teste de igualdade evita importar um módulo de teste Docker dentro da receita.

### hash_password/__main__.py na pasta entregue
- **D-17 [auto, R5]:** hash_password/__main__.py não é artefato novo e não muda: continua em src/ e no force-include do wheel (pyproject.toml:97-98) para o criar-senha.bat do Docker; a receita Windows o remove da pasta entregue depois da instalação e a auditoria reprova se ele (ou seu .pyc) existir lá. Caminho final: nenhum no pacote Windows. Vai ao espelho público: já vai hoje, dentro de src/ (sem mudança). Dado pessoal: nenhum. Precedente: a isenção da Fase 26 vale só para o pacote Docker; no Windows não há isenção de fonte. Falha visível: o arquivo presente na pasta extraída, ou uma edição no pyproject/src para tirá-lo (quebraria o criar-senha.bat — AC-19/AC-20).
  evidence: pyproject.toml:97-98
  options: **Remover só da pasta Windows, na receita; wheel e src intocados (recomendada)** (chosen) · Tirar o force-include do pyproject
  question: O que acontece com hash_password/__main__.py, isento da proteção na Fase 26?
  Por que o arquivo não é usado no Windows: ver 27-SPEC.md R5 · AC-13 (e D-13). Remover no pós-instalação mantém Docker e wheel intocados.

### Workflow .github/workflows/executavel-windows.yml
- **D-18 [auto, R6, R7]:** O arquivo .github/workflows/executavel-windows.yml é criado no repositório de trabalho e publicado no espelho público (só lá ele roda); tem apenas disparo manual (workflow_dispatch), não usa segredos e não contém dado pessoal nem planilha real. Três jobs encadeados: referência Linux (Python 3.12, instalação compilada pela receita do builder do Dockerfile, gera as planilhas fictícias uma única vez e o relatório de referência, publica ambos como artefato), montagem Windows (receita + auditoria, publica o .zip) e teste Windows (baixa o .zip e as planilhas, extrai em caminho com espaço e acento, roda a aceitação e compara digest_abas com a referência). Qualquer passo falho deixa o run vermelho. Precedente: primeiro workflow de CI do espelho — abre a porta para outros, que também terão de caber no gate de PII do ship. Falha visível: gatilho em push/pull_request, planilha gerada separadamente em cada runner, ou teste rodando sobre a árvore de montagem em vez do .zip baixado.
  options: **3 jobs (referência Linux → montagem Windows → teste Windows), só workflow_dispatch (recomendada)** (chosen) · Um job Windows único que monta e testa, referência Linux em paralelo · Matriz Linux/Windows do mesmo job
  question: Como é estruturado o workflow do espelho e o que ele carrega?
  Separar montagem e teste em jobs diferentes garante que o teste consome exatamente o .zip entregue (baixado como artefato), não a pasta de trabalho da montagem. Gerar as planilhas uma vez no Linux e reusar os mesmos bytes no Windows elimina qualquer dúvida de 'mesma planilha' no AC-18.

### Publicação clean-room (clean-room/ship.py)
- **D-19 [auto, R6]:** A publicação espelha, além de src/ e tests/, uma lista explícita e fechada de caminhos (windows/, .github/workflows/executavel-windows.yml, pyproject.toml, uv.lock, .gitattributes), e essa mesma lista entra no espelhamento, no vocabulário, no gate de PII, no pathspec do delta e no diff-stat; o gate de PII varre todos os arquivos publicados desses caminhos, inclusive .bat, .yml, .lock e .gitattributes; depois da anonimização, o pyproject.toml publicado lido como TOML tem [project], [build-system] e [tool.hatch.*] iguais ao de trabalho, senão o ship falha. Ver 27-SPEC.md R6 · AC-16, AC-17. Falha visível: arquivo publicado que o gate não leu, ship que morre em 'delta vazio' quando a fase só mexeu em arquivos de montagem, ou tabela do pyproject alterada pela anonimização.
  evidence: clean-room/ship.py:61
  options: **Lista explícita de caminhos extras usada em todos os pontos de MIRROR_DIRS + gate por sufixo ampliado + checagem tomllib (recomendada)** (chosen) · Espelhar a raiz inteira com lista de exclusão · Copiar os arquivos de montagem à mão no espelho
  question: Como a publicação passa a levar os arquivos de montagem sem abrir brecha no gate de PII?
  Medido: o gate filtra por TEXT_SUFFIXES (clean-room/ship.py:63), que não tem .bat, .yml, .lock nem arquivo sem sufixo — com a lista de hoje os arquivos novos passariam pelo gate sem serem lidos (lição 5). O die de delta vazio (ship.py:415) está escopado a MIRROR_DIRS (:411). Lista explícita de caminhos, em vez de espelhar a raiz inteira, mantém initial-data/, .planning/, other-files/ e .env* fora por construção.

### Testes e planilhas do CI (tests/windows/)
- **D-20 [auto, R7]:** As planilhas fictícias saem das fixtures existentes xlsx_com_dados_minimos e xlsx_com_escola_renomeada, sem alterá-las, por um exportador que vive sob tests/web/ (única pasta onde essas fixtures são visíveis) e que só escreve quando uma variável de saída está definida (senão pula); o teste de aceitação em tests/windows/ recebe a pasta extraída por variável de ambiente, pula fora do Windows ou sem ela, grava o arquivo de configuração no formato da R2 em %APPDATA% apontado para caminho com espaço e acento, e roda o iniciar.bat com PATH sem nenhum diretório que contenha python.exe ou py.exe. Os testes de lógica do lançador (validação, escrita atômica, prompt com entrada injetada) rodam também no Linux. Ver 27-SPEC.md R7 · AC-18, AC-21, AC-23, AC-24. Falha visível: planilha montada à mão em cópia paralela das fixtures, teste Windows que falha (em vez de pular) no Linux ou no espelho, ou iniciar.bat enxergando um Python do runner.
  evidence: tests/web/conftest.py:447-479
  options: **Exportador sob tests/web/ reusando as fixtures; aceitação em tests/windows/ com skip fora do Windows (recomendada)** (chosen) · Copiar a construção das planilhas para tests/windows/ · Mover as fixtures para um conftest raiz
  question: De onde vêm as planilhas fictícias do CI e como o teste de aceitação dirige o pacote?
  As fixtures são @pytest.fixture (conftest.py:447 e :478) e o conftest de tests/web só é visível abaixo dele — chamar a função direto ou copiar o corpo criaria uma segunda fonte da verdade. Lição 10: digest_relatorio_26.py e tests/web/conftest.py já estão no espelho (MIRROR_DIRS inclui tests).

### Tutorial Windows
- **D-21 [auto, R9]:** O tutorial é um único HTML autocontido, UTF-8 declarado, versionado como windows/tutorial-windows.html e copiado pela receita para a raiz da pasta entregue; é escrito diretamente (não gerado por scripts/build_pacote.py nem a partir de docs/DEPLOY.md, que ficam sem diff); sem dado de pessoa. Conteúdo obrigatório: ver 27-SPEC.md R9 · AC-22. Falha visível: tutorial gerado por ferramenta do pacote Docker (diff em build_pacote.py) ou fora do .zip.
  options: **HTML único escrito à mão em windows/ (recomendada)** (chosen) · Markdown + geração na receita · PDF
  question: Em que formato e onde vive o tutorial Windows?
  HTML abre com dois cliques no navegador em qualquer Windows, como o tutorial Docker. Gerar a partir de markdown exigiria tocar build_pacote.py (proibido por R8) ou criar outro gerador sem ganho real.

### pyproject.toml e uv.lock
- **D-22 [auto, R8]:** A fase não adiciona dependência nem altera pyproject.toml ou uv.lock: o runtime vem do uv, a compilação usa o build-system e o hook já existentes, e o cliente HTTP dos testes (httpx) já está no grupo dev; os testes Windows usam skipif, sem marcador novo no pytest. Se a montagem revelar uma dependência indispensável, ela entra só no grupo dev e o uv export --locked --no-dev tem de sair idêntico (27-SPEC.md AC-19). Falha visível: qualquer linha nova em [project].dependencies, versão do projeto alterada, ou lock com conjunto de produção diferente.
  evidence: pyproject.toml:5-25
  options: **Nenhuma dependência nova; pyproject e lock sem diff (recomendada)** (chosen) · Adicionar grupo 'montagem' com ferramentas de empacotamento
  question: A fase precisa de dependência nova ou de mudança no pyproject.toml/uv.lock?
  Manter pyproject e lock sem diff simplifica o AC-16 (tabelas do espelho iguais às de trabalho) e o AC-19. A versão v3.1 exibida vive no lançador, não no campo version (0.1.0).

### Reconciliação de testes existentes
- **D-23 [auto, R6, R8]:** Veredictos: clean-room/test_gate.py e clean-room/test_verify_pacote.py — manter (não referenciam MIRROR_DIRS nem supõem só src/tests); usos de MIRROR_DIRS em clean-room/ship.py (:61, :226, :271, :411, :552) — re-ancorar para a lista ampliada; tests/deploy/test_build_pacote.py, tests/deploy/test_bat_commands.py, tests/deploy/test_image_audit.py, pyproject.toml:97-98, src/parsing/_build_flags.py:14 e tests/golden/digest_relatorio_26.py — manter (os arquivos Windows ficam fora de deploy/ e do zip Docker; o resto é reuso). Tabela de origem: 27-SPEC.md §Regression Surface. Falha visível: qualquer teste existente editado para acomodar o pacote Windows fora das linhas re-ancoradas.
  evidence: clean-room/ship.py:61
  options: **Manter tudo, re-ancorar só os usos de MIRROR_DIRS em ship.py (recomendada)** (chosen) · Reescrever os testes da ferramenta de ship
  question: Quais asserções existentes a fase re-ancora e quais mantém?
  O SPEC deixou os testes da ferramenta de ship como 'manter ou re-anchor após leitura no discuss'. Medido com grep -rn 'MIRROR_DIRS|"src", "tests"' clean-room/test_*.py: zero ocorrências — nenhum deles fixa as subárvores, então ficam como estão; os testes novos da publicação ampliada são adicionais.

### Claude's Discretion
- Texto exato das mensagens da janela do console (aviso de não fechar, porta em uso, configuração inválida) — livre, desde que PT-BR legível e cumpra AC-08/AC-12/AC-07.
- Estilo visual do tutorial Windows — livre; pode seguir o do deploy/tutorial.html sem tocar nele.
- Nomes internos de funções e módulos auxiliares dentro de windows/ e tests/windows/ — livres.
- Nome do artefato do run e retenção no GitHub Actions — livres.

### Implementation Notes (sugestões — não normativas)
- D-11 · Gravação atômica: escrever em arquivo temporário na mesma pasta e os.replace. Senha pedida com getpass (sem eco), usuário com input. Validação na leitura: json válido, as 3 chaves presentes e não vazias, ADMIN_HASH começando com $argon2id$, SECRET_KEY com >= 32 bytes (ex.: secrets.token_urlsafe(48)). Modo de apagar: `lancador.py --redefinir`, que remove a pasta e imprime 'nada a apagar' quando ausente, saindo com código 0.
- D-12 · Sugestão: definir os.environ das 3 variáveis, só então `from web.app import app`; uvicorn.Server(uvicorn.Config(app, host='127.0.0.1', port=8000, workers=1, log_level='info')).run(). Checagem de porta: socket.bind(('127.0.0.1', 8000)) num socket de teste (no Windows, SO_EXCLUSIVEADDRUSE) e fechar antes de subir. Thread daemon que faz polling em http://127.0.0.1:8000/login e chama webbrowser.open('http://localhost:8000'); se webbrowser.open devolver False, imprimir o endereço. Supressão do navegador no CI: variável de ambiente BROWSER apontando para um comando nulo é mecanismo da stdlib (webbrowser), não um modo do lançador. Console: sys.stdout.reconfigure(encoding='utf-8') combinado com chcp 65001 no .bat.
- D-13 · Um teste estático (ast) sobre windows/lancador.py pode verificar a lista de imports e a ausência dos literais Urca/Botafogo/57616/57610.
- D-14 · iniciar.bat: @echo off, chcp 65001 >nul, "%~dp0programa\runtime\python.exe" -I "%~dp0programa\lancador.py", e pause se o código de saída for diferente de zero (para a mensagem de erro não sumir). redefinir-senha.bat: mesma chamada com --redefinir e pause no fim. No repositório os fontes ficam em windows/ (windows/iniciar.bat, windows/redefinir-senha.bat, windows/lancador.py); a receita os copia para a árvore entregue.
- D-15 · Ex.: uv python install 3.12 --install-dir <tmp> e copiar o diretório do interpretador; fixar o patch exato do 3.12 igual ao usado no runner Linux de referência.
- D-16 · Ex.: uv export --locked --no-dev --no-emit-project > req.txt; uv pip install --python programa/runtime/python.exe -r req.txt; HATCH_BUILD_HOOK_ENABLE_CYTHON=1 uv build --wheel; uv pip install --no-deps <wheel> no mesmo runtime; depois apagar *.py/*.pyc/*.pyx/*.c dos 7 pacotes e __pycache__. Auditoria: comparar nome a nome sem diferenciar maiúsculas, olhar dentro de .zip/.pyz, resultado independente da ordem (backstops do SPEC §Edge Coverage R5). Arquivos sugeridos: windows/montar.py e windows/auditar_pasta.py.
- D-18 · Usar actions/upload-artifact e download-artifact; setup do uv com a versão fixada; runner windows-latest tem MSVC para o Cython. No job de teste, o Python do runner só dirige o teste; o iniciar.bat roda com PATH filtrado (ver área de testes).
- D-19 · Pontos a tocar: ship.py:61 (definição), :226 (vocab), :271 (gate), :411/:415 (delta), :552 (diff-stat). _PACOTE_TEXT_EXTS (~ship.py:296) já inclui .bat e .yml — pode servir de base. Arquivos de caminho exato (não diretório) precisam de tratamento no rglob. Comparação ast sem docstrings do src/ (régua PS-12) também entra como verificação do ship.
- D-20 · Um módulo de fluxo HTTP comum (login → upload com a escola → download) serve aos dois lados: no Linux contra uvicorn subido da instalação compilada, no Windows contra o iniciar.bat. Atenção: se o py.exe do runner estiver em C:\Windows, o filtro de PATH precisa tirar esse diretório mantendo System32. Supressão do navegador via BROWSER no ambiente do processo filho.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked requirements
- `.planning/phases/INS-27-executavel-windows/27-SPEC.md` — Locked requirements — MUST read before planning

### Decisões travadas do dono (PS-01..PS-10) e fatos medidos (PS-11..PS-14)
- `.planning/phases/INS-27-executavel-windows/27-PRE-SPEC.md` — bloco gad:decisoes

### Leitura de SECRET_KEY/ADMIN_USER/ADMIN_HASH na importação (PS-13)
- `src/web/config.py` — linhas 38-40; ENVIRONMENT em :65

### Cookie de sessão https_only condicionado a ENVIRONMENT
- `src/web/app.py` — linha 102

### gerar_hash (argon2id) reusado pela primeira configuração
- `src/hash_password/__init__.py` — linha 19

### Hook Cython da Fase 26, exclude de fonte e force-include do __main__.py
- `pyproject.toml` — linhas 76, 97-98, 100-118

### Receita do builder (HATCH_BUILD_HOOK_ENABLE_CYTHON=1 uv sync --locked --no-dev --no-editable) usada como referência Linux
- `Dockerfile` — linhas 111-112, 162-166

### Postura de rede: publica só no loopback
- `docker-compose.yml` — linhas 14-17

### Publicação clean-room: MIRROR_DIRS, TEXT_SUFFIXES, gate_pii, pathspec do delta
- `clean-room/ship.py` — linhas 61, 63, 226, 258-290, 411-415, 552

### Como a ferramenta de ship funciona
- `clean-room/README.md` — leitura de apoio do plano da publicação

### Régua digest_abas do AC-18
- `tests/golden/digest_relatorio_26.py` — linha 87

### Fixtures de planilha fictícia coerente/renomeada
- `tests/web/conftest.py` — linhas 447-509

### _SETE_PACOTES e auditoria de fonte da Fase 26
- `tests/deploy/test_image_audit.py` — linha 41

### Tutorial Docker (referência visual; não muda)
- `deploy/tutorial.html` — R8

### *.bat text eol=crlf
- `.gitattributes` — linha 3

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `hash_password.gerar_hash` (src/hash_password/__init__.py:19) — hash argon2id compilado; a primeira configuração do lançador o chama em vez de `python -m hash_password`.
- `digest_abas` (tests/golden/digest_relatorio_26.py:87) — régua célula a célula das 3 abas; reuso direto no AC-18.
- Fixtures `xlsx_com_dados_minimos` e `xlsx_com_escola_renomeada` (tests/web/conftest.py:447-509) — planilhas fictícias coerente e renomeada, sem pessoa; só visíveis a testes sob tests/web/.
- `_SETE_PACOTES` (tests/deploy/test_image_audit.py:41) — lista fechada dos 7 pacotes da auditoria de fonte.
- Hook Cython (pyproject.toml:100-118) ligado por `HATCH_BUILD_HOOK_ENABLE_CYTHON=1`, a mesma chave do builder do Dockerfile (Dockerfile:111-112).
- `.gitattributes` do repo de trabalho já tem `*.bat text eol=crlf`.

### Established Patterns
