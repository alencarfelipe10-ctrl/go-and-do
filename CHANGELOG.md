# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/) · Versionamento: [SemVer](https://semver.org/lang/pt-BR/).

## [1.0.0] — 2026-07-22

Primeira release pública. 🎉

### Skills incluídas

- **go-and-do** — fase GSD de ponta a ponta (intenção → plano → execução → auditorias → UAT automatizado → resumo → PR).
- **close-phase** — fechamento de fase (extract-learnings → verificação → PR).
- **end-mile** — finalização de milestone (audit → summary → complete).

### Adicionado nesta release

- **Modo degradado dos revisores adversariais**: quando nenhum revisor externo (Codex/`agy`) está instalado, a revisão adversarial de intenção e a convergência do plano são **puladas com aviso destacado no resumo executivo** (`intent_review: skipped`), em vez de bloquear a fase. Setups com revisor instalado que falha em runtime continuam fail-closed (`blocked`), como antes.
