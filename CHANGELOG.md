# Histórico de versões

Todas as versões da go-and-do como produto próprio. Cada entrada diz qual GSD Core vai vendorizado dentro do pacote
(a cópia congelada e renomeada para o namespace `gad`), conferido por hash na montagem.

## [3.1.0] — 2026-10-02

Primeiro ciclo real de atualização do Core vendorizado: o **Core 1.15.0** foi absorvido pela receita de ciclo —
montar, triar, rebasear, remontar, conferir — sem regressão no script de prova da v3.0.0.

### Core vendorizado

- `@opengsd/gsd-core 1.15.0` (antes 1.14.0), tarball conferido por sha256
  `33cbfc408523e34a701209bf57c2f4b0e01a20f7a2289768ea6a56fa66fe4590` e pela `integrity` publicada no registro npm.
- O manifesto do runtime (`dist/manifest.json`) registra `core.versao` 1.15.0 e `produto.versao` 3.1.0.

### Mudanças que vêm do Core 1.15.0

- Inventário diferencial da instalação 1.14.0 × 1.15.0: 950 → 932 arquivos, 285 alterados, 11 novos e 29 removidos.
- Novidades da 1.15.0 mantidas no runtime: os passos novos do `execute-phase` (`code-review-disposition`,
  `ready-wave-gate`, `stale-reverification`, `threat-id-gate`, `worktree-base-check`), a convenção de identificador de
  fase (`phase-id-convention`) e as bibliotecas novas do motor que a acompanham.
- Saem do runtime os 29 `agents/*.compact.md`, retirados pelo próprio Core 1.15.0.
- O lançador do motor que a skill `/go-and-do` carrega (as cópias em `execute.md`, `close-phase/workflow.md` e
  `intent-discuss.md`) passa a ser a linha canônica do lançador da 1.15.0, sem sonda própria.

### Fork rebaseado

- O fork aplicado sobre o Core foi rebaseado por merge 3-way (`git merge-file --diff3`) só sobre as entradas
  marcadas na triagem: 16 arquivos, 8 fundidos sem conflito, 7 com conflito resolvido antes da remontagem e 1
  recebendo a cópia instalada da 1.15.0.
- A triagem na forma instalada classificou 64 linhas: 47 🟢 (sem ação), 6 🟡 e 11 🔴.

### Receita de ciclo

- Triagem feita sobre a instalação real das duas versões (não sobre o tarball cru).
- Inventário diferencial gravado por ciclo, com cada alteração explicada e o ruído do instalador separado.
- Teste de contrato: os 20 verbos do motor que a skill `/go-and-do` chama rodam nas duas versões e as respostas são
  comparadas campo a campo.
- A trava das entradas da montagem passa a guardar a versão do Core do ciclo; a remontagem é reproduzível a partir
  dela.

### Pacote

- Este `CHANGELOG.md` passa a ir dentro do pacote publicado.
- Instalação pela tag nova: `npx github:alencarfelipe10-ctrl/go-and-do#v3.1.0`.

## [3.0.0] — 2026-10-01

Primeira versão da go-and-do como produto próprio, isolado do GSD Core instalado na mesma máquina.

### Core vendorizado

- `@opengsd/gsd-core 1.14.0`, tarball conferido por sha256
  `9831fe309179021f82e01998108d43784625364a8a7af33efbfc7525b3da2d95`, com o fork do produto aplicado e tudo
  renomeado para o namespace `gad` (skills, agentes, hooks e o motor `gad-tools`) por script reproduzível.

### Produto

- Instalador `npx` com os subcomandos `install`, `update`, `uninstall`, `verify` e `doctor`.
- Runtime em `~/.claude/go-and-do/runtime/<hash>`, com `~/.claude/go-and-do/current` apontando para ele e o
  manifesto conferido na instalação.
- Hooks `gad-*` registrados no `settings.json` sem tocar nas entradas existentes; o `uninstall` remove só o que a
  go-and-do registrou no recibo dela.
- Convivência com o GSD Core: atualizar o Core instalado não muda nem quebra a go-and-do instalada.
