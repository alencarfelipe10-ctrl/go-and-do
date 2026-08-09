<!-- ============================================================ -->
<!-- workflow-dev-server.md — Sub-rotina B completa (dev server). -->
<!-- Leitura SOB DEMANDA (T.3): a camada 0 (ou a janela que vai   -->
<!-- gerenciar server — UI review / UAT) lê este arquivo quando a -->
<!-- fase tem server para subir. Fase sem UI/server: não leia.    -->
<!-- ============================================================ -->

# Sub-rotina B — subir / derrubar o dev server (UI review e UAT)

Mecanizada no `scripts/dev-server.sh` (decisão 4.B + adendo 5.A):

- **`dev-server.sh up <project_root>`** — consulta a receita persistida
  (`run-<nome>/SKILL.md`, probe por descrição subindo até a raiz git) ou cai na
  heurística por tipo de projeto (Expo web 8081 com `CI=1 BROWSER=none`; web comum
  `dev`/`start` em 3000/5173/8080), espera a porta responder, e — cold-start limpo sem
  receita — **auto-persiste a receita** com os valores constatados (P15: a adivinhação
  de subida acontece no máximo 1×; das rodadas seguintes em diante é replay).
- **`dev-server.sh down`** — encerra pelo PID gravado: `pkill -s <PID>` (sessão) +
  `kill <PID>` + fallback `fuser -k <porta>/tcp` se a porta seguir viva. O Metro do
  Expo abre filhos — por isso a morte é por sessão, nunca "matar o que parecer
  relacionado". (Guarda permanente no próprio script: NUNCA derivar pgid via `ps` — em
  shell não-interativo o pgid devolvido é o do shell PAI, e um `kill -- -PGID` mata o
  próprio orquestrador; caso real no aceite de 09/08, exit 144.)
- Estado em `.planning/.gad-dev-server.json` (PID, porta, receita usada, `ja_estava`).

Regras que o script não muda:

- **Quem sobe/derruba é a janela que USA o server** — no UI review e no UAT, a
  janela do subagente (ela roda `up` no início e `down` no fim; o server morre com a
  janela que o criou). O subagente recebe só a instrução — o script resolve o resto.
- O subagente de UAT/UI review **só navega**: recebe a URL `http://localhost:<porta>`
  constatada pelo `up`.
- `up` exit 1 (não subiu no timeout) → siga em **code-only com a ressalva declarada**;
  no UAT, sem server os cenários de UI viram balde 3 — nunca silencie a degradação.
- **Cold-start primeiro:** se há cenário de cold-start (boot do zero), rode-o ANTES do
  server persistente — brigam pela porta.
