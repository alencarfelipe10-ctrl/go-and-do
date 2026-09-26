# Fixture — DESLOCAMENTO de conteúdo (t59/L13, FM-F27INS-03PLAN)

Molde da tabela real do `27-REVIEWS.md` (source-grounding pass).

| Citação | Fonte | Status | Correção |
| --- | --- | --- | --- |
| `@@ABS@@/desloc-ship.py:3` (`VIRTUAL_ENV` removido) | plano | VERIFIED | `@@ABS@@/desloc-ship.py:4` (`env.pop("VIRTUAL_ENV", None)`) |
| `@@ABS@@/desloc-conftest.py:3 e :8` (credencial `admin` / `senha-de-teste`) | plano | VERIFIED (ponteiro deslocado) | `_TEST_PASSWORD = "senha-de-teste"` está em `:5`; `:8` confere |
| `@@ABS@@/no-desloc.py:2` (`FLAG` presente) | plano | VERIFIED | confere direto, sem deslocamento |
| `@@ABS@@/bat-paraphrase.py:3-5` (docstrings "espelho só leva src/ e tests/") | plano | VERIFIED | linha real 5-6, texto parafraseado no documento |
