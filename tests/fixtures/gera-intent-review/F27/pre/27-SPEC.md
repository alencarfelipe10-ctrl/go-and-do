# Phase 27: Executável Windows — Specification

**Created:** 2026-09-25
**Ambiguity score:** 0.18 (gate: ≤ 0.20)
**Requirements:** 9 locked
<!-- spec-origem: v1 -->
<!-- spec-classe: v1 -->

## Goal

Hoje o único pacote entregue ao cliente é o `.zip` da Fase 26 (Docker + `subir.bat`), que não roda no notebook corporativo do Átila: o Docker Desktop está instalado, mas virtualização e WSL estão desligados e ligá-los depende do TI. Depois desta fase: (1) existe um segundo pacote, uma pasta zipada para Windows que sobe o aplicativo com dois cliques no `iniciar.bat`, sem Docker, virtualização, WSL nem Python instalado; (2) na primeira abertura o programa pede usuário e senha e se configura sozinho; (3) a pasta entregue não traz código-fonte legível dos 7 pacotes e a trava de escolas da Fase 26 continua ligada; (4) o relatório gerado no Windows é igual, célula a célula, ao gerado no Linux pela mesma instalação compilada que a imagem Docker usa, provado por um teste automático no GitHub Actions; (5) o pacote Docker e o motor não mudam.

Promessas do Goal do ROADMAP, uma a uma:
- "roda o aplicativo no Windows dele só extraindo uma pasta e dando dois cliques" → **dentro** (R1, R2, R4).
- "sem Docker, sem virtualização, sem WSL, sem instalar Python" → **dentro** (R1; AC-01, AC-02).
- "com o relatório idêntico ao gerado pelo pacote Docker" → **dentro, pela régua travada no PS-08**: comparação célula a célula (`digest_abas`, Fase 26) entre o relatório do pacote Windows e o relatório gerado no Linux, da mesma planilha fictícia e do mesmo commit, pela mesma instalação compilada que o `Dockerfile` executa (R7; AC-18). A comparação com dado real contra o pacote Docker acontece **depois** do fechamento e não trava o UAT (PS-08). Reconciliado no ROADMAP no mesmo commit (linha "Régua do idêntico" na entrada da Phase 27).
- "e a proteção de código da Phase 26 preservada" → **dentro** (R5; AC-13, AC-14).

## Background

- [medido:PS-11] O `pyproject.toml` do espelho não tem o hook Cython nem o exclude de fonte da Fase 26; montar lá hoje sairia sem proteção.
  - Detalhe [auto]: no repo de trabalho o hook está em `pyproject.toml:100-162` (`enable-by-default = false`, ligado só por `HATCH_BUILD_HOOK_ENABLE_CYTHON=1`), o exclude de fonte em `pyproject.toml:76` e a exceção `hash_password/__main__.py` em `pyproject.toml:97-98`. O clone local do espelho (`../motor-reconhecimento-receita`, HEAD `a34539b`) tem `pyproject.toml` de 1.010 B, `Dockerfile` de 4,4 KB (o de trabalho tem 9,1 KB) e **não tem** `.gitattributes` nem `.github/`.
- [medido:PS-12] O código de `src/` do espelho é idêntico ao de trabalho; só comentários/docstrings diferem.
- [medido:PS-13] SECRET_KEY, ADMIN_USER e ADMIN_HASH são lidos via `os.environ` sem padrão na importação; o lançador precisa defini-los antes de importar `web.app`.
  - Detalhe [auto]: tipo `str` (`src/web/config.py:38-40`, atributos de classe de `Settings`, avaliados na importação de `web.config`, que `web.app` importa em `src/web/app.py:38`); ausente → `KeyError` na importação e o app não sobe (fail-closed, D-03 de `config.py:4-5`). `ENVIRONMENT` ausente → `"dev"` (`config.py:65`), e com isso o cookie de sessão **não** é `https_only` (`src/web/app.py:102`) — condição para o login funcionar em `http://localhost`.
- [medido:PS-14] Todas as dependências nativas do lock têm wheel `win_amd64`; `uvloop` é pulado no Windows por marcador (`uv.lock:780`).
- O servidor da imagem Docker é `gunicorn -k uvicorn_worker.UvicornWorker -w 1 --bind 0.0.0.0:8000 --timeout 600` (`Dockerfile:162-166`); o `docker-compose.yml` publica só em `127.0.0.1:8000`. Gunicorn não roda no Windows; a direção do ROADMAP (item 3) é Uvicorn escutando só em `127.0.0.1`.
- A trava de identidade lê `PROTECAO_IDENTIDADE_LIGADA` de `src/parsing/_build_flags.py:14`, commitado `True`; no Docker o `case` de `Dockerfile:83-94` reescreve o arquivo antes da compilação. Rejeição por identidade: `ERR_IDENTIDADE_ESCOLA_DIVERGENTE = "A planilha não corresponde à escola selecionada."` (`src/parsing/identidade.py:73`).
- Régua de igualdade do relatório: `tests/golden/digest_relatorio_26.py::digest_abas` (valores + estrutura das 3 abas; exclui nome do arquivo e `wb.properties`). A Fase 26 varreu `today()/datetime.now` em `src/`: só o nome do arquivo depende da data (`src/report/report_generator.py:1515`).
- `tests/web/conftest.py` já gera planilhas sintéticas coerentes com a trava de identidade (Fase 26), só com códigos de unidade e nomes de escola, sem pessoa — o CI do espelho pode usá-las sem planilha real.
- Publicação clean-room: `MIRROR_DIRS = ("src", "tests")` (`clean-room/ship.py:61`), usado como fonte do espelhamento (`:226`, `:271`) e como pathspec do delta (`:411`, `:552`). Tudo fora disso nunca chega ao espelho hoje.

## Requirements

1. **Pasta zipada que sobe com dois cliques**: A entrega é um `.zip` que, extraído, é uma pasta com `iniciar.bat`, `redefinir-senha.bat` e o runtime Python embutido; o app sobe com dois cliques no `iniciar.bat` numa máquina sem Docker, virtualização, WSL ou Python.
   - [pre-spec:PS-01] Entrega em pasta zipada com atalho .bat; o cliente não instala Docker, Python nem habilita virtualização/WSL. Não é .exe único autoextraível.
   - [auto] O runtime Python embutido é CPython 3.12 (`pyproject.toml:4`, `requires-python = ">=3.12"`), o mesmo minor da imagem Docker (`python:3.12-slim`) — as extensões compiladas só carregam no minor para o qual foram compiladas. Nenhum `.bat` da pasta chama `docker`, `wsl` nem um `python` fora da pasta.
   - Current: só existe o pacote Docker (`inspired-piloto.zip`).
   - Target: um segundo `.zip`, só para Windows, gerado pelo CI (R6).
   - Acceptance: AC-01, AC-02, AC-21.
   - Trigger: pedido-do-dono — PS-01; origem no ROADMAP (Docker travado no notebook do cliente).

2. **Primeira configuração sozinha, em AppData**: Na primeira abertura o programa pede usuário e senha e grava a configuração na pasta do usuário do Windows.
   - [pre-spec:PS-03] Na primeira abertura o programa pede usuário e senha e grava tudo sozinho, inclusive a chave secreta; a tela de login do app não muda.
   - [pre-spec:PS-04] A configuração fica na pasta do usuário do Windows (AppData), fora da pasta do programa; versão nova = extrair o zip novo sem recriar senha.
   - [auto] Conteúdo da configuração: `ADMIN_USER` (texto), `ADMIN_HASH` (argon2id, gerado por `hash_password.gerar_hash`, a mesma função compilada do `criar-senha.bat`) e `SECRET_KEY` aleatória de pelo menos 32 bytes (`secrets`); a senha em claro nunca é gravada. O lançador define as três variáveis antes de importar `web.app` (PS-13) e **não** define `ENVIRONMENT=production` (quebraria o cookie em `http`, ver Background). A senha é pedida duas vezes sem eco; vazia ou diferente → pergunta de novo (mesma regra do `hash_password`).
   - [auto] A gravação é atômica (arquivo temporário + troca): interromper a primeira configuração no meio nunca deixa uma configuração parcial aceita.
   - Current: senha via `.env` + `criar-senha.bat` (Docker).
   - Target: configuração automática na primeira abertura; nenhuma edição de arquivo pelo usuário.
   - Acceptance: AC-03, AC-04, AC-06, AC-07, AC-24.
   - Trigger: pedido-do-dono — PS-03/PS-04.

3. **Redefinir senha**: `redefinir-senha.bat` apaga a configuração e a próxima abertura pede usuário e senha de novo.
   - [pre-spec:PS-05] Um redefinir-senha.bat apaga a configuração; a próxima abertura pede usuário e senha de novo.
   - [auto] Rodar sem configuração existente não é erro (mensagem "nada a apagar"). Com o programa aberto, o servidor em execução segue com a configuração que já leu até ser fechado; a próxima abertura pede de novo.
   - Current: não existe (no Docker, trocar senha é editar o `.env`).
   - Target: um `.bat` que recomeça a configuração.
   - Acceptance: AC-05.
   - Trigger: pedido-do-dono — PS-05.

4. **Janela visível, loopback, navegador sozinho**: Enquanto roda, uma janela avisa para não fechá-la e mostra `v3.1`; o servidor escuta só em `127.0.0.1:8000`; o navegador abre sozinho; fechar a janela desliga o programa.
   - [pre-spec:PS-06] Janela visível enquanto roda, avisando para não fechar; o navegador abre sozinho; fechar a janela desliga o programa.
   - [pre-spec:PS-07] A janela exibe a versão como v3.1; as telas do app não mudam.
   - [auto] Um único processo servidor Uvicorn, um worker (o throttle e o `_store` de download vivem na memória do processo — `docker-compose.yml`, comentário de réplica única), escutando só em `127.0.0.1` porta `8000` (mesma postura do `docker-compose.yml`: publica só no loopback). O navegador só é aberto depois que o servidor responde; sem navegador padrão, a janela mostra o endereço para abrir à mão. As mensagens da janela ficam legíveis no console do Windows (sem caractere quebrado).
   - Current: `gunicorn … --bind 0.0.0.0:8000` dentro do container (`Dockerfile:162-166`).
   - Target: Uvicorn direto no Windows, loopback, janela visível.
   - Acceptance: AC-08, AC-09, AC-10, AC-11, AC-12.
   - Trigger: pedido-do-dono — PS-06/PS-07; direção 3 do ROADMAP.

5. **Proteção da Fase 26 na pasta entregue**: Os 7 pacotes vão só compilados, sem fonte legível, e a trava de escolas fica ligada.
   - [pre-spec:PS-10] A proteção da Fase 26 vale para o executável: os 7 pacotes do motor compilados para Windows antes do empacotamento, nenhum .py/.c deles legível na pasta entregue, trava de escolas ligada. O lançador novo fica fora desse conjunto, salvo decisão contrária no spec.
   - [auto] Sem isenção no Windows: a exceção `hash_password/__main__.py` da Fase 26 (`pyproject.toml:97-98`) existe porque o `criar-senha.bat` roda `python -m hash_password`; o pacote Windows não roda isso (a primeira configuração chama `gerar_hash()` compilado — R2), então o arquivo sai da pasta entregue. "Legível" inclui `.py`, `.pyc`, `.pyx` e `.c`, soltos ou dentro de arquivo-contêiner do empacotador (ex.: arquivo de bytecode embutido).
   - [auto] A trava fica ligada por construção: o `_build_flags.py` commitado (`True`) é compilado como está; o pacote Windows não tem opção de desligar (nem no build, nem em execução).
   - [auto] O lançador fica fora do conjunto compilado (PS-10) e legível; por isso não contém nome nem código de escola, nem lógica de identidade, de cálculo ou de relatório — só configura o ambiente, sobe o servidor e abre o navegador.
   - Current: proteção existe só na imagem Docker.
   - Target: a mesma proteção na pasta Windows.
   - Acceptance: AC-13, AC-14, AC-15.
   - Trigger: pedido-do-dono — PS-10.

6. **Montagem no GitHub Actions do espelho**: O pacote é montado por workflow do GitHub Actions no repositório espelho, em máquina Windows, por disparo manual.
   - [pre-spec:PS-02] Montagem no GitHub Actions (Windows) no repositório espelho existente; a publicação clean-room passa a levar os arquivos de montagem (pyproject, uv.lock, script e receita), sob o gate de PII.
   - [auto] O que a publicação passa a levar, além de `src/` e `tests/`: `pyproject.toml`, `uv.lock`, o lançador, os dois `.bat`, a receita de montagem, o tutorial Windows, o workflow e `.gitattributes` (o espelho não tem — sem `*.bat text eol=crlf` os `.bat` chegam com LF e o `cmd.exe` quebra). No CI só entra planilha fictícia (direção 2 do ROADMAP); nenhum arquivo de `initial-data/`, `.planning/`, `other-files/` nem `.env*` é publicado.
   - Current: `MIRROR_DIRS = ("src", "tests")` (`clean-room/ship.py:61`); espelho sem hook Cython (PS-11) e sem workflow.
   - Target: workflow manual no espelho que devolve o `.zip` como artefato do run.
   - Acceptance: AC-16, AC-17.
   - Trigger: pedido-do-dono — PS-02; evidência — PS-11.

7. **Aceitação automática no CI**: No mesmo run, um teste no Windows sobre a pasta extraída sobe o app, faz login, gera o relatório de uma planilha fictícia, confirma a recusa de escola não licenciada e compara célula a célula com o relatório Linux da mesma planilha.
   - [pre-spec:PS-08] Fecha a fase o teste automático no Windows do GitHub com planilha fictícia: abre, login, relatório gerado, escola não licenciada recusada e comparação célula a célula (régua digest_relatorio_26) com o relatório gerado no Linux da mesma planilha. A comparação com dado real ocorre após o fechamento e não trava o UAT.
   - [auto] "Relatório gerado no Linux" = mesmo commit, runner Linux, Python 3.12, instalação compilada pela receita do builder do `Dockerfile` (`HATCH_BUILD_HOOK_ENABLE_CYTHON=1 uv sync --locked --no-dev --no-editable`, `Dockerfile:111-112`), mesma planilha fictícia, mesma escola. Não é a imagem Docker em si: o `Dockerfile` não vai ao espelho (PS-09 mantém o Docker no processo local) — ver Limitações.
   - [auto] O teste roda com o `PATH` sem nenhum Python do runner, para provar que o app usa só o runtime da pasta. As credenciais do teste entram por um arquivo de configuração pré-gravado no formato da R2 (sem prompt, sem modo especial no lançador); o prompt da primeira abertura é provado por teste do lançador com entrada injetada, rodando no runner Windows. A abertura do navegador é suprimida no runner.
   - Current: nenhum teste roda no Windows.
   - Target: o run do workflow falha se qualquer etapa ou qualquer aba divergir.
   - Acceptance: AC-18, AC-24.
   - Trigger: pedido-do-dono — PS-08.

8. **Pacote Docker e motor intocados**: O pacote Docker continua sendo gerado como hoje e os 7 pacotes de `src/` não mudam.
   - [pre-spec:PS-09] O pacote Docker continua sendo gerado pelo processo atual, sem mudança; só o executável é enviado ao cliente.
   - [auto] Os diretórios existentes dos 7 pacotes (`src/{web,hash_password,parsing,comparison,report,calculation,domain}`) ficam sem diff — é o que garante o "relatório idêntico" do Goal e a "tela de login do app não muda" do PS-03; o lançador vive fora deles (PS-10). Dependência nova só de montagem entra em grupo de desenvolvimento/montagem, nunca no conjunto de produção que o `Dockerfile` instala (`uv sync --no-dev`).
   - Current: `Dockerfile`, `docker-compose.yml`, `deploy/`, `docs/DEPLOY.md`, `scripts/build_pacote.py` da Fase 26.
   - Target: os mesmos, sem diff.
   - Acceptance: AC-19, AC-20.
   - Trigger: não-regressão — PS-09.

9. **Tutorial do caminho sem Docker**: Um tutorial novo, separado do tutorial Docker, vai dentro do `.zip` Windows.
   - [auto] Direção 6 do ROADMAP: cobre extrair, dois cliques no `iniciar.bat`, a primeira configuração, `redefinir-senha.bat`, fechar a janela para desligar, e — se o TI ou o antivírus bloquear o executável — pedir liberação ao TI (sem executável de teste prévio). Não cita Docker como pré-requisito. `docs/DEPLOY.md` e `deploy/tutorial.html` não mudam (R8).
   - Current: só o tutorial Docker.
   - Target: tutorial Windows em arquivo próprio.
   - Acceptance: AC-22.
   - Trigger: pedido-do-dono — direção 6 do ROADMAP (WIN-v3x-01).

## Boundaries

**In scope:**
- Pasta zipada para Windows com runtime Python 3.12 embutido, `iniciar.bat` e `redefinir-senha.bat`
- Lançador fora dos 7 pacotes: primeira configuração em AppData, variáveis de ambiente antes do import, Uvicorn em 127.0.0.1:8000, janela com aviso e v3.1, abertura do navegador
- Compilação dos 7 pacotes para Windows e auditoria de ausência de fonte na pasta entregue
- Workflow manual do GitHub Actions no espelho que monta e testa (Windows) e gera a referência (Linux)
- Ampliação da publicação clean-room para levar os arquivos de montagem, sob o gate de PII
- Tutorial Windows novo, dentro do zip
- Testes do lançador e do pacote (os que dependem de Windows pulam fora dele)

**Out of scope:**
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

## Constraints

- **Mesmo CPython minor:** extensões compiladas só carregam no minor para o qual foram compiladas; runtime embutido e compilação Windows em 3.12 (`pyproject.toml:4`), o mesmo da imagem.
- **Import com ambiente pronto (PS-13):** `web.config` lê as três variáveis na importação (`src/web/config.py:38-40`); o lançador as define antes de qualquer `import web.*`, e ausência continua sendo erro fail-closed.
- **Processo único:** throttle de login e `_store` de download vivem na memória do processo; um worker só, como no Docker.
- **Espelho clean-room (lições 5 e 10):** tudo o que o workflow e os testes do CI leem precisa existir no espelho; testes que leem `initial-data/`, `imagem.tar`, `Dockerfile` ou `deploy/` seguem com `skipif` pela ausência; o gate de PII do ship roda sobre os arquivos novos publicados.
- **Suíte (CLAUDE.md):** suíte rápida com `-n 4` em background via `roda-suite.sh`; testes que exigem Windows ficam fora da suíte rápida no Linux (skip), e rodam no runner Windows.
- **Precisão contábil / Decimal:** inalterada — a fase não toca valor monetário.
- **Caminhos no Windows:** pasta extraída e pasta do usuário podem ter espaço e acento; `.bat` com CRLF (`.gitattributes`: `*.bat text eol=crlf`).

## Acceptance Criteria

- [ ] AC-01 — O `.zip` gerado pelo workflow, extraído, é uma pasta que contém `iniciar.bat`, `redefinir-senha.bat` (ambos CRLF), o tutorial Windows e um runtime CPython 3.12; não contém `Dockerfile`, `docker-compose.yml`, `imagem.tar`, `.env*` nem planilha `.xlsx`; o `.zip` não é um executável único autoextraível; nenhum `.bat` da pasta contém `docker`, `wsl` ou chamada a `python` fora da pasta; FAIL = qualquer item ausente ou proibido presente. [exigido: é a forma de entrega travada pelo dono] [origem: PS-01, Goal]
- [ ] AC-02 — No runner Windows, com o `PATH` sem nenhum interpretador Python (`where python` e `where py` sem resultado) e sem Docker em uso, rodar o `iniciar.bat` da pasta extraída faz `GET http://127.0.0.1:8000/login` responder 200, e o executável do processo servidor está dentro da pasta extraída; FAIL = app não sobe ou roda com Python de fora da pasta. [exigido: o Goal promete rodar sem instalar Python e sem Docker] [origem: Goal, PS-01]
- [ ] AC-03 — Com a pasta de configuração ausente, a primeira abertura pede usuário e senha (senha duas vezes, sem eco) e grava, só em `%APPDATA%` (nada dentro da pasta do programa), `ADMIN_USER`, um `ADMIN_HASH` que começa com `$argon2id$` e verifica a senha digitada, e uma `SECRET_KEY` com pelo menos 32 bytes aleatórios; a senha em claro não aparece em nenhum arquivo gravado; o login do app com essas credenciais funciona e a página de login é a mesma do Docker; FAIL = qualquer um desses falhar. [exigido: é a primeira configuração travada pelo dono] [origem: PS-03, PS-04, PS-13]
- [ ] AC-04 — A segunda abertura não pergunta nada; extrair o mesmo `.zip` em outra pasta e abrir não pergunta nada e o login com a senha já criada funciona; FAIL = nova pergunta ou senha perdida. [exigido: versão nova = extrair o zip novo sem recriar senha] [origem: PS-04]
- [ ] AC-05 — Depois de `redefinir-senha.bat`, a configuração em `%APPDATA%` não existe, a abertura seguinte pede usuário e senha de novo, e a senha antiga deixa de logar; rodar `redefinir-senha.bat` sem configuração termina sem erro; FAIL = configuração sobrevive, sem nova pergunta, senha antiga ainda loga ou erro na segunda execução. [exigido: é o atalho de esqueci a senha travado pelo dono] [origem: PS-05]
- [ ] AC-06 — Na primeira configuração, usuário vazio, senha vazia ou confirmação diferente fazem a pergunta se repetir e nenhum arquivo de configuração é gravado até uma entrada válida; FAIL = configuração gravada com entrada inválida. [desejável] [origem: PS-03]
- [ ] AC-07 — Configuração existente mas incompleta ou inválida (chave faltando, hash que não é argon2id, arquivo truncado por interrupção) faz o programa **não** subir e a janela dizer para rodar `redefinir-senha.bat`; o programa não regrava a configuração sozinho nesse caso; FAIL = sobe com configuração inválida ou troca a senha em silêncio. [desejável] [origem: PS-04, PS-05]
- [ ] AC-08 — Enquanto o programa roda, a janela do console está visível, mostra o texto `v3.1` e um aviso para não fechá-la, legíveis no console do Windows; FAIL = janela oculta, sem versão ou sem aviso. [desejável] [origem: PS-06, PS-07]
- [ ] AC-09 — O servidor é um único processo Uvicorn escutando só em `127.0.0.1:8000`: nenhum socket do programa escuta em `0.0.0.0` nem em outra interface; FAIL = qualquer escuta fora do loopback ou mais de um processo servidor. [exigido: o pacote Docker publica só no loopback e o Windows não pode expor o app na rede do cliente] [origem: WIN-v3x-01, Goal]
- [ ] AC-10 — Depois que o servidor responde, o programa abre o navegador padrão em `http://localhost:8000`; sem navegador disponível, a janela mostra esse endereço; FAIL = navegador aberto antes do servidor responder ou nenhum dos dois. [desejável] [origem: PS-06]
- [ ] AC-11 — Encerrar a janela (o processo do console do `iniciar.bat`) faz, em até 10 s, nada mais escutar em `127.0.0.1:8000` e nenhum processo da pasta continuar rodando; FAIL = processo órfão ou porta ocupada. [exigido: um servidor órfão ocupa a porta e a próxima abertura falha] [origem: PS-06, Goal]
- [ ] AC-12 — Com a porta 8000 já ocupada (ex.: segunda abertura), a janela mostra uma mensagem legível dizendo que o programa já está aberto ou a porta está em uso, sem traceback, e não abre o navegador; FAIL = traceback ou navegador aberto para outro serviço. [desejável] [origem: AC-11, PS-06]
- [ ] AC-13 — Na pasta extraída, cada módulo `.py` dos 7 pacotes em `src/` (exceto `hash_password/__main__.py`) tem a extensão nativa `.pyd` correspondente, e uma varredura da pasta inteira, inclusive dentro de arquivos-contêiner do empacotador, não acha nenhum `.py`, `.pyc`, `.pyx` ou `.c` dos 7 pacotes — sem isenção, `hash_password/__main__.py` incluso; FAIL = módulo sem `.pyd` (build que "passa" sem compilar) ou qualquer fonte achada. [exigido: sem isso a proteção de código da Fase 26 não está preservada] [origem: PS-10, Goal]
- [ ] AC-14 — No pacote Windows não existe caminho para desligar a trava de identidade: nenhuma variável de ambiente, arquivo na pasta ou em `%APPDATA%` faz a planilha fictícia de escola não licenciada renomeada gerar relatório; FAIL = algum caminho desliga. [exigido: o PS-10 pede a trava de escolas ligada] [origem: PS-10]
- [ ] AC-15 — O lançador (fora do conjunto compilado) não contém nome nem código de escola (`Urca`, `Botafogo`, `57616`, `57610`), não importa `parsing`, `calculation`, `comparison`, `report` nem `domain`, e só importa `web.app`, `hash_password` e biblioteca padrão/servidor; FAIL = qualquer ocorrência. [desejável] [origem: PS-10]
- [ ] AC-16 — O espelho tem um workflow do GitHub Actions com disparo manual que, num runner Windows, compila os 7 pacotes pelo hook Cython do `pyproject.toml`, monta a pasta, roda a auditoria do AC-13 e publica o `.zip` como artefato do run; o `pyproject.toml` do espelho no commit montado, lido como TOML (`tomllib`), tem as tabelas `[project]`, `[build-system]` e `[tool.hatch.*]` iguais às do repo de trabalho no commit publicado (a anonimização do ship só pode tocar comentários, `clean-room/ship.py:63` inclui `.toml`); FAIL = workflow ausente, disparo automático em push, tabela divergente, ou run verde com a auditoria do AC-13 reprovando. [exigido: montar no espelho com o pyproject antigo sairia sem proteção] [origem: PS-02, PS-11]
- [ ] AC-17 — A publicação clean-room leva ao espelho `pyproject.toml`, `uv.lock`, o lançador, os dois `.bat`, a receita, o tutorial Windows, o workflow e `.gitattributes` com `*.bat text eol=crlf`, além de tudo que os testes do CI leem (`tests/golden/digest_relatorio_26.py`, os geradores de planilha fictícia); o gate de PII do ship passa sobre esses arquivos; nenhum arquivo de `initial-data/`, `.planning/`, `other-files/`, `.env*` nem `.xlsx` real é publicado; o `src/` publicado continua igual ao de trabalho em código (comparação `ast` sem docstrings, régua do PS-12); FAIL = arquivo faltando no espelho, gate de PII reprovado, arquivo proibido publicado ou `src/` divergente em código. [exigido: o workflow só monta o que existe no espelho] [origem: PS-02, PS-12]
- [ ] AC-18 — No mesmo run, num runner Windows, sobre a pasta extraída do `.zip` recém-gerado: o app sobe, o login funciona, o upload de uma planilha fictícia coerente de Eleva Urca gera e baixa o relatório `.xlsx`, uma planilha fictícia de escola não licenciada com o nome trocado para Eleva Urca é recusada com `ERR_IDENTIDADE_ESCOLA_DIVERGENTE` sem relatório, e `digest_abas` de cada uma das 3 abas do relatório Windows é igual ao do relatório da mesma planilha gerado num runner Linux do mesmo run, mesmo commit, Python 3.12, pela instalação `HATCH_BUILD_HOOK_ENABLE_CYTHON=1 uv sync --locked --no-dev --no-editable`; FAIL = qualquer etapa falha ou qualquer aba (valor, estilo, estrutura, ordem) difere, e o run fica vermelho. [exigido: é o teste que fecha a fase pela régua do dono] [origem: PS-08, Goal]
- [ ] AC-19 — `git diff <commit-âncora>..HEAD` é vazio em `Dockerfile`, `docker-compose.yml`, `deploy/`, `docs/DEPLOY.md` e `scripts/build_pacote.py`; `uv export --locked --no-dev` (conjunto de produção) é idêntico ao do commit-âncora; o `inspired-piloto.zip` segue com o manifesto de 7 artefatos e nenhum arquivo do pacote Windows; FAIL = qualquer diff, dependência de produção nova ou arquivo Windows no pacote Docker. [exigido: o dono travou o pacote Docker sem mudança] [origem: PS-09]
- [ ] AC-20 — `git diff <commit-âncora>..HEAD` é vazio nos diretórios `src/web`, `src/hash_password`, `src/parsing`, `src/comparison`, `src/report`, `src/calculation` e `src/domain`; FAIL = qualquer diff. [exigido: motor e telas inalterados sustentam o relatório idêntico e a tela de login igual] [origem: Goal, PS-03, PS-13]
- [ ] AC-21 — O teste do AC-18 roda com a pasta extraída num caminho com espaço e acento (ex.: `C:\Pasta Teste\Relatório Átila\`) e com `%APPDATA%` apontando para um caminho com espaço e acento; o app sobe, configura e gera o relatório igual; FAIL = qualquer etapa quebra por causa do caminho. [exigido: pasta de usuário do Windows com espaço ou acento não pode impedir os dois cliques] [origem: Goal]
- [ ] AC-22 — O tutorial Windows está dentro do `.zip`, cita `iniciar.bat`, `redefinir-senha.bat`, a primeira configuração, fechar a janela para desligar e o pedido de liberação ao TI em caso de bloqueio, e não cita Docker como pré-requisito; FAIL = qualquer item ausente. [desejável] [origem: WIN-v3x-01]
- [ ] AC-23 — A suíte rápida pós-merge fica verde; os testes novos que exigem Windows pulam no Linux e os que leem artefato ausente no espelho pulam lá; FAIL = teste que falha fora do Windows ou no espelho. [desejável] [origem: AC-18, AC-19]
- [ ] AC-24 — O prompt da primeira configuração é provado por teste do lançador com entrada injetada (usuário/senha válidos, vazios e divergentes), rodando no runner Windows; o CI entra no app com um arquivo de configuração pré-gravado no formato da R2, sem variável ou modo especial que pule a senha no lançador; FAIL = lançador com atalho de teste que dispense a configuração, ou prompt sem teste. [desejável] [origem: PS-08, PS-03]

## Critérios exigidos

| AC | Régua (origem) | Motivo | Efeito do Goal que cobre |
|----|----------------|--------|--------------------------|
| AC-01 | PS-01, Goal | é a forma de entrega travada pelo dono | extrair uma pasta, sem Docker/WSL/virtualização |
| AC-02 | Goal, PS-01 | o Goal promete rodar sem instalar Python e sem Docker | sem instalar Python, dois cliques |
| AC-03 | PS-03, PS-04, PS-13 | é a primeira configuração travada pelo dono | dois cliques sem editar arquivo |
| AC-04 | PS-04 | versão nova = extrair o zip novo sem recriar senha | dois cliques nas aberturas seguintes |
| AC-05 | PS-05 | é o atalho de esqueci a senha travado pelo dono | uso contínuo sem suporte técnico |
| AC-09 | WIN-v3x-01, Goal | o pacote Docker publica só no loopback e o Windows não pode expor o app na rede do cliente | roda no Windows com a postura do Docker |
| AC-11 | PS-06, Goal | um servidor órfão ocupa a porta e a próxima abertura falha | dois cliques em toda abertura |
| AC-13 | PS-10, Goal | sem isso a proteção de código da Fase 26 não está preservada | proteção da Phase 26 preservada |
| AC-14 | PS-10 | o PS-10 pede a trava de escolas ligada | proteção da Phase 26 preservada |
| AC-16 | PS-02, PS-11 | montar no espelho com o pyproject antigo sairia sem proteção | proteção da Phase 26 preservada |
| AC-17 | PS-02, PS-12 | o workflow só monta o que existe no espelho | relatório idêntico (mesmo código) |
| AC-18 | PS-08, Goal | é o teste que fecha a fase pela régua do dono | relatório idêntico; escola não licenciada recusada |
| AC-19 | PS-09 | o dono travou o pacote Docker sem mudança | pacote Docker segue sendo a referência |
| AC-20 | Goal, PS-03, PS-13 | motor e telas inalterados sustentam o relatório idêntico e a tela de login igual | relatório idêntico |
| AC-21 | Goal | pasta de usuário do Windows com espaço ou acento não pode impedir os dois cliques | dois cliques no Windows dele |

## Cobertura do Goal

| Efeito medido do Goal | ACs exigidos que o cobrem | Veredito |
|-----------------------|---------------------------|----------|
| extrair uma pasta e dar dois cliques no Windows do cliente | AC-01, AC-02, AC-03, AC-04, AC-05, AC-11, AC-21 | coberto |
| sem Docker, sem virtualização, sem WSL, sem instalar Python | AC-01, AC-02 | coberto |
| relatório idêntico ao do pacote Docker (régua do PS-08: Windows × Linux compilado, planilha fictícia) | AC-17, AC-18, AC-20 | coberto pela régua do PS-08; dado real após o fechamento (Limitações) |
| proteção de código da Phase 26 preservada | AC-13, AC-14, AC-16 | coberto |
| pacote Docker e postura de rede inalterados | AC-09, AC-19 | coberto |

**Efeitos sem cobertura:** nenhum

## Artefatos novos commitados

| Caminho | Conteúdo |
|---------|----------|
| windows/lancador.py (caminho final no discuss; fora dos 7 pacotes) | lançador: primeira configuração em AppData, variáveis de ambiente, Uvicorn em 127.0.0.1:8000, janela, navegador — sem nome/código de escola |
| windows/iniciar.bat, windows/redefinir-senha.bat | atalhos do cliente, CRLF |
| windows/ (receita de montagem — script e especificação do empacotador) | como compilar os 7 pacotes para Windows, montar a pasta, remover `hash_password/__main__.py` e auditar a ausência de fonte |
| windows/tutorial-windows.html (ou .md + .html) | tutorial do caminho sem Docker, sem dado de pessoa |
| .github/workflows/executavel-windows.yml | workflow manual: Linux (referência) + Windows (montagem, auditoria, teste, artefato) |
| tests/windows/ (testes do lançador e do pacote) | testes; os de Windows pulam no Linux; usam só planilha fictícia gerada em memória, sem pessoa |
| clean-room/ship.py (alteração) + espelho `.gitattributes` | publicação ampliada aos arquivos de montagem |

## Regression Surface

**Sweep:** `grep -rn "MIRROR_DIRS" clean-room/`; `grep -rln gunicorn tests/`; `grep -n "bat\|7 artefatos" tests/deploy/test_build_pacote.py tests/deploy/test_bat_commands.py`; `grep -n "_SETE_PACOTES" tests/deploy/test_image_audit.py`; `grep -rn "digest_relatorio_26" src tests scripts`; `cat .gitattributes` — 2026-09-25.

| Existing assertion (file:line) | What this phase changes | Verdict | Reconciliation |
|--------------------------------|-------------------------|---------|----------------|
| clean-room/ship.py:61 — `MIRROR_DIRS = ("src", "tests")`, usado em :226, :271 (espelhamento/PII), :411 (pathspec do delta, `die` se vazio em :415) e :552 | a publicação passa a levar arquivos de montagem fora de `src/`/`tests/` (R6) | re-anchor — os novos caminhos entram no espelhamento, no gate de PII e no pathspec do delta | plano da publicação |
| clean-room/test_gate.py, clean-room/test_verify_pacote.py — testes da ferramenta de ship | podem supor só `src/`/`tests/` | manter ou re-anchor após leitura no discuss | plano da publicação |
| tests/deploy/test_build_pacote.py:168 — "7 artefatos exatamente" no `inspired-piloto.zip`; :183-201 CRLF dos 3 `.bat`; :273-303 os 3 `.bat` citados no tutorial | nada, se os arquivos Windows ficarem fora de `deploy/` e do zip Docker (R8) | manter | plano do pacote Windows |
| tests/deploy/test_bat_commands.py — `BAT_EXPECTED_COMMANDS` com os 3 `.bat` do Docker | nada, pelo mesmo motivo | manter | — |
| tests/deploy/test_image_audit.py:41 — `_SETE_PACOTES` | a auditoria Windows reusa a mesma lista | manter (reuso) | plano da auditoria |
| pyproject.toml:97-98 — force-include de `hash_password/__main__.py` no wheel | o wheel segue igual (Docker); a montagem Windows remove o arquivo da pasta | manter | plano da montagem |
| pyproject.toml:17-25 / uv.lock — grupo `dev` | dependência de montagem nova muda o lock | manter o conjunto de produção idêntico (AC-19) | plano da montagem |
| src/parsing/_build_flags.py:14 — `PROTECAO_IDENTIDADE_LIGADA = True` | nada — o Windows compila o arquivo commitado | manter | — |
| tests/golden/digest_relatorio_26.py — `digest_abas` | reusado como régua do AC-18 | manter (reuso) | plano do CI |
| .gitattributes (trabalho) — `*.bat text eol=crlf`; ausente no espelho | passa a ser publicado | re-anchor no espelho | plano da publicação |

## Edge Coverage

**Coverage:** 24/24 applicable edges resolved · 0 unresolved

| Category | Requirement | Status | Resolution / Reason |
|----------|-------------|--------|---------------------|
| empty | R1 | ✅ covered | AC-01 — pasta sem runtime ou sem `.bat` reprova o conteúdo do zip |
| encoding | R1 | ✅ covered | AC-21 — pasta extraída em caminho com espaço e acento |
