#!/usr/bin/env bash
# test-confere-user-setup.sh — bancada do confere-user-setup.sh (S-8, tarefa 48i).
# Molde: tests/test-confere-precondicoes.sh.
set -u
AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"; REPO="$(dirname -- "$AQUI")"
S="$REPO/skills/go-and-do/scripts/confere-user-setup.sh"
falhas=0; okc=0
ok()  { okc=$((okc+1)); echo "PASS: $1"; }
bad() { falhas=$((falhas+1)); echo "FAIL: $1${2:+ — $2}"; }
eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1" "esperado [$3] obtido [$2]"; }
PAI=$(mktemp -d); trap 'rm -rf "$PAI"' EXIT

monta() { # <nome> → ecoa "root|pd" (root vazio de .env/.mcp.json/gh — cada teste povoa o que quer)
  local root="$PAI/$1" pd="$PAI/$1/.planning/phases/24.5-x"; mkdir -p "$pd"
  printf '%s|%s' "$root" "$pd"
}
plano_us() { # <pd> <id> <user_setup-yaml (linhas, indentado com 2 espaços já)> [precondition]
  { printf -- '---\nphase: "24.5"\nplan: "%s"\nwave: 1\n' "$2"
    if [ -n "${3:-}" ]; then printf 'user_setup:\n%s\n' "$3"; fi
    printf 'autonomous: true\n---\n\n# Plano\n\n<task type="auto">\n'
    [ -n "${4:-}" ] && printf '  <precondition>%s</precondition>\n' "$4"
    printf '  <action>x</action>\n</task>\n'; } > "$1/24.5-$2-PLAN.md"
}
# PATH sem gh: garante GH_OK=false de forma determinística nos testes de env (o resto do
# repo pode ou não ter `gh` instalado/autenticado — não depender disso).
SEM_GH="$PAI/bin-sem-gh"; mkdir -p "$SEM_GH"
for b in bash jq awk grep sed tr basename dirname cat mktemp cd; do
  p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$SEM_GH/$b" 2>/dev/null
done
roda() { OUT=$(PATH="$SEM_GH:$PATH" bash "$S" "$1" "$2" 2>/dev/null); RC=$?; }

echo "── sem nenhum plano com user_setup/precondition-arquivo: nao_se_aplica ──"
IFS='|' read -r R PD <<<"$(monta vazia)"
printf -- '---\nphase: "24.5"\nplan: "01"\nwave: 1\nautonomous: true\n---\n\n# Plano\n' > "$PD/24.5-01-PLAN.md"
roda "$PD" "$R"
eq "exit 0" "$RC" 0
eq "veredito nao_se_aplica" "$(jq -r .veredito <<<"$OUT")" nao_se_aplica
eq "itens vazio" "$(jq -r '.itens|length' <<<"$OUT")" 0

echo "── env_vars: .env satisfaz, ausência reprova ──"
IFS='|' read -r R PD <<<"$(monta env_local)"
plano_us "$PD" 01 '  - service: stripe
    env_vars:
      - name: STRIPE_SECRET_KEY
      - name: STRIPE_WEBHOOK_SECRET'
printf 'STRIPE_SECRET_KEY=sk_test_x\n' > "$R/.env"
roda "$PD" "$R"
eq "exit 1 (1 pendente)" "$RC" 1
eq "veredito falha" "$(jq -r .veredito <<<"$OUT")" falha
eq "STRIPE_SECRET_KEY satisfeito via .env" \
  "$(jq -r '.itens[] | select(.nome=="STRIPE_SECRET_KEY") | .satisfeito' <<<"$OUT")" true
eq "STRIPE_WEBHOOK_SECRET pendente (sem .env, sem gh)" \
  "$(jq -r '.itens[] | select(.nome=="STRIPE_WEBHOOK_SECRET") | .satisfeito' <<<"$OUT")" false
eq "gh_disponivel false (PATH sem gh)" "$(jq -r .gh_disponivel <<<"$OUT")" false
eq "gh_medido false no item pendente" \
  "$(jq -r '.itens[] | select(.nome=="STRIPE_WEBHOOK_SECRET") | .gh_medido' <<<"$OUT")" false
eq "pendentes lista só o que falta (stripe não menciona mcp — sem item mcp)" "$(jq -r '.pendentes|length' <<<"$OUT")" 1
eq "…e nenhum item tipo=mcp foi criado (service sem menção a mcp)" "$(jq -r '[.itens[]|select(.tipo=="mcp")]|length' <<<"$OUT")" 0
eq "codigos = USER-SETUP-PENDENTE" "$(jq -c .codigos <<<"$OUT")" '["USER-SETUP-PENDENTE"]'

echo "── .env.local também satisfaz (qualquer um dos dois basta) ──"
IFS='|' read -r R PD <<<"$(monta env_dotlocal)"
plano_us "$PD" 01 '  - service: x
    env_vars:
      - name: X_KEY'
printf 'X_KEY=abc\n' > "$R/.env.local"
roda "$PD" "$R"
eq "exit 0 via .env.local" "$RC" 0
eq "veredito ok" "$(jq -r .veredito <<<"$OUT")" ok

echo "── entrada MCP em .mcp.json (só quando o item menciona 'mcp') ──"
IFS='|' read -r R PD <<<"$(monta mcp_ok)"
plano_us "$PD" 01 '  - service: supabase
    why: "servidor MCP do supabase para a fase"
    env_vars:
      - name: SUPABASE_KEY'
printf 'SUPABASE_KEY=x\n' > "$R/.env"
printf '{"mcpServers":{"supabase":{"command":"x"}}}\n' > "$R/.mcp.json"
roda "$PD" "$R"
eq "exit 0 (env satisfeito + mcp presente)" "$RC" 0
eq "item mcp satisfeito=true" "$(jq -r '.itens[] | select(.tipo=="mcp") | .satisfeito' <<<"$OUT")" true

IFS='|' read -r R PD <<<"$(monta mcp_ausente)"
plano_us "$PD" 01 '  - service: supabase
    why: "servidor MCP do supabase para a fase"
    env_vars:
      - name: SUPABASE_KEY'
printf 'SUPABASE_KEY=x\n' > "$R/.env"
roda "$PD" "$R"
eq "sem .mcp.json → item mcp pendente" "$(jq -r '.itens[] | select(.tipo=="mcp") | .satisfeito' <<<"$OUT")" false
eq "…e o veredito falha por causa dele (env já satisfeito)" "$(jq -r .veredito <<<"$OUT")" falha

echo "── service SEM menção a 'mcp' nunca vira item mcp (regressão do gate por menção) ──"
IFS='|' read -r R PD <<<"$(monta sem_mcp_mencao)"
plano_us "$PD" 01 '  - service: stripe
    why: "processar pagamentos"
    env_vars:
      - name: STRIPE_KEY'
printf 'STRIPE_KEY=x\n' > "$R/.env"
roda "$PD" "$R"
eq "exit 0 — sem menção a mcp, só o env conta" "$RC" 0
eq "nenhum item tipo=mcp" "$(jq -r '[.itens[]|select(.tipo=="mcp")]|length' <<<"$OUT")" 0

echo "── arquivo declarado via <precondition> ──"
IFS='|' read -r R PD <<<"$(monta arquivo_ok)"
plano_us "$PD" 01 "" "Arquivo config/service-account.json existe em disco"
mkdir -p "$R/config"; touch "$R/config/service-account.json"
roda "$PD" "$R"
eq "exit 0 arquivo presente" "$RC" 0
eq "item arquivo satisfeito" "$(jq -r '.itens[0].satisfeito' <<<"$OUT")" true
eq "tipo arquivo" "$(jq -r '.itens[0].tipo' <<<"$OUT")" arquivo

IFS='|' read -r R PD <<<"$(monta arquivo_ausente)"
plano_us "$PD" 01 "" "Arquivo config/service-account.json existe em disco"
roda "$PD" "$R"
eq "exit 1 arquivo ausente" "$RC" 1
eq "item arquivo pendente" "$(jq -r '.itens[0].satisfeito' <<<"$OUT")" false

echo "── vários planos: contagem e agregação ──"
IFS='|' read -r R PD <<<"$(monta multiplos)"
plano_us "$PD" 01 '  - service: a
    env_vars:
      - name: A_KEY'
plano_us "$PD" 02 '  - service: b
    env_vars:
      - name: B_KEY'
printf 'A_KEY=1\nB_KEY=2\n' > "$R/.env"
roda "$PD" "$R"
eq "planos=2" "$(jq -r .planos <<<"$OUT")" 2
eq "2 itens env, ambos satisfeitos" \
  "$(jq -r '[.itens[] | select(.tipo=="env" and .satisfeito==true)] | length' <<<"$OUT")" 2
eq "veredito ok (nenhum service menciona mcp, nenhuma precondition de arquivo)" "$(jq -r .veredito <<<"$OUT")" ok

echo "── uso inválido ──"
bash "$S" /nao/existe /tmp >/dev/null 2>&1; eq "phase_dir inexistente → exit 2" "$?" 2
bash "$S" "$PAI" /nao/existe >/dev/null 2>&1; eq "project_root inexistente → exit 2" "$?" 2
bash "$S" >/dev/null 2>&1; eq "sem argumentos → exit 2" "$?" 2

echo "--------------------------------------------------"; echo "$okc ok / $falhas falhas"; [ "$falhas" -eq 0 ]
