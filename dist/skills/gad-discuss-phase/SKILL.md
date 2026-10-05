---
name: gad-discuss-phase
description: "Comando único de intenção: entrevista o dono só sobre negócio e grava o documento único da fase (NN-CONTEXT.md) com o «ok» dele."
argument-hint: "<phase> [--insumo <arquivo>] [--text]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
---


<objective>
Comando único de intenção da fase: entrevista o dono só sobre negócio (o que é entregue, o que fica público, o que é irreversível, custo, prazo, risco de perder algo), grava cada resposta assim que ela é dada e escreve o documento único «Especificação da fase NN — <nome>» (`NN-CONTEXT.md`). Antes de gravar, explica em linguagem leiga o que a fase entrega, o que fica de fora e o que o dono decidiu, e só grava com o «ok» dele.

**Como funciona:**
1. Confere a barreira sem dono e o estado da intenção (nova, retomada, gravação interrompida, documento existente)
2. Abre a fase se ela ainda não está no ROADMAP
3. Explica a fase, investiga e mede o código, lê os insumos como texto de apoio
4. Entrevista o dono pela consequência, com a recomendação primeiro
5. Escreve as seções, roda as sondas de bordas e proibições e a régua interna de ambiguidade
6. Explica, recebe o «ok», promove o documento e faz o commit

**Saída:** `{phase_num}-CONTEXT.md` — o único documento de intenção da fase; nunca `NN-SPEC.md` nem `NN-PRE-SPEC.md`.

**Barreira sem dono:** com `--auto`, `--chain`, `--batch`, `--assumptions`, `--power`, `--all`, `--analyze` ou numa cadeia automática, o comando não grava nada e para com a frase «Este comando só roda com você presente: rode `/gad-discuss-phase N` você mesmo, sem modo automático.»
</objective>

<execution_context>
O workflow é carregado sob demanda no <process> abaixo — não antes.
</execution_context>

<runtime_note>
**Copilot (VS Code):** Use `vscode_askquestions` wherever this workflow calls `AskUserQuestion`. They are equivalent — `vscode_askquestions` is the VS Code Copilot implementation of the same interactive question API.
</runtime_note>

<context>
Número da fase: $ARGUMENTS (obrigatório), mais `--insumo <arquivo>` (repetível) e `--text`.

O contexto da fase é resolvido dentro do workflow (`discuss-init.sh`).
</context>

<process>
**Roteamento (único):**
```bash
# Fast path: reuse the gad-tools location resolved earlier this session (state file namespaced per config-home [C2-31][C3-39]; never PATH) before the full cascade.
GAD_TOOLS=""; _GAD_STATE=""; _GAD_HOME=""
for _c in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/gad-tools.cjs"; do [ -n "$_c" ] && [ -f "$_c" ] && _GAD_HOME="$(readlink -f "$(dirname "$(dirname "$(dirname "$(readlink -f "$_c")")")")" 2>/dev/null)" && break; done
[ -n "$_GAD_HOME" ] && _GAD_STATE="${TMPDIR:-/tmp}/gad-tools-path.$(id -u).$(printf '%s' "$_GAD_HOME" | md5sum | cut -c1-8)"
if [ -n "$_GAD_STATE" ] && [ -f "$_GAD_STATE" ]; then _GAD_CAND="$(cat "$_GAD_STATE" 2>/dev/null)"; case "$(readlink -f "$_GAD_CAND" 2>/dev/null)" in "$_GAD_HOME"/*) [ -f "$_GAD_CAND" ] && GAD_TOOLS="$_GAD_CAND" ;; esac; fi
if [ -n "$GAD_TOOLS" ]; then case "$GAD_TOOLS" in *.cjs) gad_run() { node "$GAD_TOOLS" "$@"; } ;; *) gad_run() { "$GAD_TOOLS" "$@"; } ;; esac; else
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
fi
[ -n "$_GAD_STATE" ] && { printf '%s\n' "$GAD_TOOLS" > "$_GAD_STATE" 2>/dev/null || true; }
```

Leia e execute `$HOME/.claude/gad-core/workflows/discuss-phase.md` do começo ao fim — sempre, qualquer que seja o `workflow.discuss_mode` da config (ignorado: é sempre o comando único). O workflow é a fonte da verdade; este arquivo é só o resumo.

As flags da barreira não são tratadas aqui: o `discuss-init.sh` do workflow para antes de qualquer escrita e o workflow dá a mensagem ao dono.
</process>
