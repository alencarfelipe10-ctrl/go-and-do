#!/usr/bin/env bash
# context-check.sh — sensor do gate de contexto da skill go-and-do.
#
# Imprime UMA linha parseável:
#   tokens=<int> limit=<int> pct=<int> status=<ok|stop|unknown> [reason=...]
#
#   - tokens : tokens em uso na janela de contexto da sessão (ABSOLUTO).
#   - limit  : teto absoluto que dispara o gate (TOKEN_LIMIT).
#   - pct    : tokens em uso como % do teto (0-100+; só pra leitura humana da trajetória).
#   - status : ok      -> abaixo do teto, pode seguir.
#              stop    -> >= teto, hora de checkpoint + pausa.
#              unknown -> não deu pra medir (sem jq / sem transcript) -> a skill segue.
#
# ── POR QUE TETO ABSOLUTO (e não % da janela) ─────────────────────────────────
# O gate protege a QUALIDADE do raciocínio numa orquestração longa: parar antes de o
# contexto encher demais e retomar numa janela fresh. O que importa pra isso é a
# QUANTIDADE ABSOLUTA de tokens carregados, não a fração de uma janela que varia 5x
# entre sessões (200k vs 1M). Gatear por tokens absolutos:
#   • lê só o numerador (tokens em uso), que ESTÁ no transcript de forma confiável;
#   • dispensa saber o tamanho da janela — que NÃO é legível por uma skill (o id do
#     modelo no transcript vem sem o sufixo [1m]; nenhuma env var expõe a janela).
#   Assim mata de vez o bug em que 1M era lido como 200k e inflava o pct ~5x (parando
#   o gate aos ~11% reais de uso).
#
# TETO: 400000 tokens. Calibrado ABAIXO do auto-compact do harness (observado a ~460k
#       numa janela de ~510k, fase real de 05/07/2026): o gate só cumpre o papel — pausa
#       graciosa, retomável, sob controle da skill — se agir ANTES do compact (que é com
#       perdas). A folga também absorve o crescimento de uma etapa inteira entre duas
#       checagens (o gate mede só ENTRE comandos; já se observou +82k numa única etapa).
#       Numa sessão de 200k o autocompact nativo (~166k) age bem antes, então na prática
#       isto governa sessões de janela grande. Sobrescreva via env CONTEXT_TOKEN_LIMIT
#       ou editando TOKEN_LIMIT abaixo.
#
# Tokens em uso = input_tokens + cache_creation_input_tokens + cache_read_input_tokens
#   (SEM output_tokens; mesma fórmula da statusline) da ÚLTIMA entrada assistant da
#   CADEIA PRINCIPAL (isSidechain==false) — ignora subagentes, que têm janela própria.
#
# FILTRO DO ADVISOR (bug real, AOS-10 07/07/2026): um turno que consulta o advisor nativo do
#   CC injeta payload EFÊMERO (~118k observados) que conta no usage de TODAS as entradas
#   daquele requestId e some no turno seguinte. Medir durante/logo após esse turno infla a
#   leitura (234k medidos vs ~119k reais) e gera falso-positivo no detector de compact do
#   run-log.sh (a leitura seguinte "cai" >100k sem compact algum). Por isso entradas cujo
#   requestId contém blocos server_tool_use/advisor_tool_result são EXCLUÍDAS da medição —
#   vale a última entrada de um turno normal (a medição pode ficar ≥1 turno atrás do real;
#   sub-medir atrasa o freio — fail-open, coerente com a filosofia do gate: a
#   retomabilidade cobre).
#
# Entrada (env): CLAUDE_CODE_SESSION_ID (nativo; casa com o nome do transcript).
#                Fallback: CLAUDE_SESSION_ID. CONTEXT_TOKEN_LIMIT (opcional) sobrescreve o teto.
# Exit:          sempre 0 — quem decide é a skill, lendo a linha.

set -uo pipefail
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/lib/gsd-shim.sh" 2>/dev/null && trap 'gad_autoregistro "context-check.sh" "$?"' EXIT || true

TOKEN_LIMIT=400000

emit() { echo "tokens=${1} limit=${TOKEN_LIMIT} pct=${2} status=${3}${4:+ reason=$4}"; exit 0; }

# 0. Teto: env sobrescreve o default.
if [ -n "${CONTEXT_TOKEN_LIMIT:-}" ] && [ "${CONTEXT_TOKEN_LIMIT}" -gt 0 ] 2>/dev/null; then
  TOKEN_LIMIT="$CONTEXT_TOKEN_LIMIT"
fi

# 1. Pré-requisitos.
command -v jq >/dev/null 2>&1 || emit 0 0 unknown no-jq
sid="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
[ -n "$sid" ] || emit 0 0 unknown no-session-id

# Acha o transcript pelo ID da sessão (não montar o caminho na mão — o encoding do
# diretório não é documentado).
transcript="$(find "$HOME/.claude/projects" -name "${sid}.jsonl" -type f 2>/dev/null | head -n1)"
[ -n "$transcript" ] && [ -f "$transcript" ] || emit 0 0 unknown no-transcript

# 2. Tokens em uso = última entrada assistant da cadeia principal, EXCLUINDO turnos do
#    advisor (requestIds com blocos server_tool_use/advisor_tool_result — usage efêmero).
used="$(jq -s '
  ( [ .[]
      | select(type=="object")
      | select(.type=="assistant")
      | select( ( .message.content // [] )
                | if type=="array" then . else [] end
                | any(.type? == "server_tool_use" or .type? == "advisor_tool_result") )
      | .requestId // empty
    ] | unique ) as $advisor_reqs
  | [ .[]
      | select(type=="object")
      | select(.type=="assistant")
      | select((.isSidechain // false) == false)
      | (.requestId // "") as $r
      | select( ($advisor_reqs | index($r)) | not )
      | .message.usage
      | select(. != null)
      | ( (.input_tokens // 0)
        + (.cache_creation_input_tokens // 0)
        + (.cache_read_input_tokens // 0) )
    ] | last // 0
' "$transcript" 2>/dev/null)" || used=""

# Falha do jq (ex.: linha truncada por escrita concorrente) ≠ zero real: rotule como
# unknown/parse-fail — "post-compact" aqui seria um rótulo mentiroso e esconderia que o
# gate está às cegas.
[ -n "$used" ] || emit 0 0 unknown parse-fail
case "$used" in
  ''|*[!0-9]*) emit 0 0 unknown bad-usage ;;
esac
# Zero real (sem nenhuma entrada medível ainda — ex.: só turnos advisor no início da
# sessão, ou logo após um compact nativo) -> abaixo do teto, siga.
[ "$used" -gt 0 ] 2>/dev/null || emit 0 0 ok post-compact

# 3. Veredito por teto absoluto.
pct=$(( used * 100 / TOKEN_LIMIT ))
if [ "$used" -ge "$TOKEN_LIMIT" ]; then
  emit "$used" "$pct" stop
else
  emit "$used" "$pct" ok
fi
