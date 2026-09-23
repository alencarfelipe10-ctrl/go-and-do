#!/usr/bin/env bash
# confere-user-setup.sh — confere EXISTÊNCIA (nunca valor) do setup humano declarado nos
# planos da fase (S-8, tarefa 48i). Molde: confere-precondicoes.sh (mesmo par de
# argumentos, mesmo shape de saída, mesmos exit codes) — script solto, sem lib/gsd-shim.sh
# (é um conferente de leitura, não um passo que grava evento).
#
# Por que existe: `user_setup:` no frontmatter do PLAN.md (schema do gsd-core,
# `templates/user-setup.md`) e `<precondition>` (agents/gsd-planner.md) DECLARAM setup que
# um humano precisa terminar antes da fase rodar de verdade — chave de API, secret do
# GitHub Actions, servidor MCP, arquivo de credencial. Ninguém conferia se o que foi
# declarado de fato existe: o 2.4b (workflow.md, "flip the plan to autonomous: true") podia
# fechar o checkpoint por resposta em texto sem o item físico ter sido criado.
#
# Uso: confere-user-setup.sh <phase_dir> <project_root>
#
# Fontes lidas por plano (`<phase_dir>/*-PLAN.md`), quatro canais, cada um só por
# EXISTÊNCIA — nunca lê nem imprime o valor de nada:
#   (1) env  — `user_setup: […]  env_vars: [{name: X}]` → existe `^X=` em `.env` OU
#              `.env.local` na raiz do projeto (qualquer um dos dois basta).
#   (2) github_secret — o MESMO nome de (1), conferido também contra `gh secret list`
#              (existência do nome na lista, nunca o valor). Requer o binário `gh` E que
#              o comando não falhe (fora de um repo, sem remoto, sem auth) — qualquer uma
#              dessas condições vira `gh_medido: false` (pula com aviso, nunca falha por
#              isso: PC-6 já veta a fase sem revisor, aqui o instrumento ausente é só
#              informativo). Um item de env conta como satisfeito se (1) OU (2) for true.
#   (3) mcp — `user_setup: […]  service: <nome>`, só quando o MESMO item do YAML menciona
#              "mcp" em algum campo (`why`, `dashboard_config`, etc — nem todo `service:` é
#              um servidor MCP: Stripe/SendGrid não são) → alguma chave de `.mcp.json`
#              (raiz do projeto, `mcpServers`) contém o nome do serviço (comparação sem
#              caixa, substring — nomes de servidor MCP variam de convenção).
#   (4) arquivo — `<precondition>` cujo texto cita um caminho com cara de credencial
#              (extensão .json/.pem/.key/.p12/.pfx/.crt/.env) → existe no projeto
#              (absoluto, ou relativo à raiz).
#
# Saída: JSON de 1 linha
#   {"fase_dir":…, "planos":N, "itens":[{"plano":"NN-01","tipo":"env"|"mcp"|"arquivo",
#     "nome":…, "satisfeito":bool, …campos do canal…}], "gh_disponivel":bool,
#    "pendentes":[…subconjunto de itens com satisfeito:false…],
#    "veredito":"ok|falha|nao_se_aplica", "codigos":["USER-SETUP-PENDENTE"]}
# Exit: 0 ok/nao_se_aplica · 1 falha (>=1 item declarado e ausente) · 2 uso inválido.
# nao_se_aplica = nenhum plano da fase declara `user_setup`/`service`/arquivo-com-cara-de-
# -credencial em `<precondition>` — não é este script quem decide se DEVERIA haver setup.
set -euo pipefail
shopt -s nullglob
PD="${1:-}"; ROOT="${2:-}"
[ -n "$PD" ] && [ -d "$PD" ] && [ -n "$ROOT" ] && [ -d "$ROOT" ] \
  || { echo "uso: confere-user-setup.sh <phase_dir> <project_root>" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq ausente" >&2; exit 2; }

# ── frontmatter (entre a 1ª e a 2ª linha `---`) e o sub-bloco `user_setup:` dentro dele ──
frontmatter() { awk 'NR==1 && $0!="---"{exit 1} NR>1 && $0=="---"{exit 0} NR>1{print}' "$1" 2>/dev/null; }
bloco_user_setup() { # lê o frontmatter do stdin, ecoa só as linhas de dentro de `user_setup:`
  awk '
    /^user_setup:/ { dentro=1; next }
    dentro && /^[A-Za-z_][A-Za-z0-9_]*:/ { dentro=0 }
    dentro { print }
  '
}

# ── canal (2): gh secret list, uma vez só (nomes, nunca valor) ──────────────────────────
GH_OK=false; GH_NOMES=""
if command -v gh >/dev/null 2>&1; then
  if GH_NOMES=$(cd "$ROOT" && gh secret list 2>/dev/null | awk '{print $1}'); then
    GH_OK=true
  fi
fi
tem_gh_secret() { # <nome>
  [ "$GH_OK" = true ] || return 1
  printf '%s\n' "$GH_NOMES" | grep -qxF "$1"
}

# ── canal (3): .mcp.json (comparação sem caixa, substring) ──────────────────────────────
MCP_CHAVES=""
if [ -f "$ROOT/.mcp.json" ] && jq -e . "$ROOT/.mcp.json" >/dev/null 2>&1; then
  MCP_CHAVES=$(jq -r '(.mcpServers // {}) | keys[]' "$ROOT/.mcp.json" 2>/dev/null | tr '[:upper:]' '[:lower:]')
fi
tem_mcp() { # <nome>
  local alvo; alvo=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  [ -n "$MCP_CHAVES" ] || return 1
  printf '%s\n' "$MCP_CHAVES" | grep -qF "$alvo"
}

ITENS='[]'; N=0
for f in "$PD"/*-PLAN.md; do
  N=$((N+1))
  plan=$(basename "$f" | sed 's/-PLAN\.md$//')
  US=$(frontmatter "$f" | bloco_user_setup)

  # (1)+(2) env_vars declarados
  if [ -n "$US" ]; then
    while IFS= read -r nome; do
      [ -n "$nome" ] || continue
      env_local=false
      for envf in "$ROOT/.env" "$ROOT/.env.local"; do
        [ -f "$envf" ] || continue
        grep -qE "^${nome}=" "$envf" 2>/dev/null && env_local=true
      done
      gh_secret=false; tem_gh_secret "$nome" && gh_secret=true
      sat=false
      if [ "$env_local" = true ] || [ "$gh_secret" = true ]; then sat=true; fi
      ITENS=$(jq -cn --argjson prev "$ITENS" --arg p "$plan" --arg n "$nome" \
        --argjson el "$env_local" --argjson gs "$gh_secret" --argjson gm "$GH_OK" --argjson s "$sat" \
        '$prev + [{plano:$p, tipo:"env", nome:$n, env_local:$el, github_secret:$gs, gh_medido:$gm, satisfeito:$s}]')
    done < <(printf '%s\n' "$US" | grep -oE '^[[:space:]]*-[[:space:]]*name:[[:space:]]*[A-Za-z0-9_]+' \
              | sed -E 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*//')

    # (3) service declarado → candidato a entrada MCP, só quando o PRÓPRIO item menciona
    # "mcp" em algum campo (why/dashboard_config/…) — nem todo `service:` é um servidor
    # MCP (Stripe/SendGrid não são), então o gatilho é a menção, não a mera presença do
    # campo. Segmentação por item feita em awk (um `- service:` inicia item novo);
    # emite "<service>\t<0|1 menciona mcp>" por item, tab-separado.
    while IFS=$'\t' read -r servico tem_mcp_flag; do
      [ -n "$servico" ] || continue
      [ "$tem_mcp_flag" = 1 ] || continue
      pres=false; tem_mcp "$servico" && pres=true
      ITENS=$(jq -cn --argjson prev "$ITENS" --arg p "$plan" --arg n "$servico" --argjson pr "$pres" \
        '$prev + [{plano:$p, tipo:"mcp", nome:$n, satisfeito:$pr}]')
    done < <(printf '%s\n' "$US" | awk '
      function flush() { if (servico != "") printf "%s\t%s\n", servico, (mcpv ? 1 : 0) }
      /^[[:space:]]*-[[:space:]]*service:/ {
        flush(); servico=$0; mcpv=0
        sub(/^[[:space:]]*-[[:space:]]*service:[[:space:]]*/, "", servico)
        sub(/[[:space:]]+$/, "", servico)
        next
      }
      tolower($0) ~ /mcp/ { mcpv=1 }
      END { flush() }
    ')
  fi

  # (4) <precondition> com cara de arquivo de credencial
  while IFS= read -r pre; do
    [ -n "$pre" ] || continue
    while IFS= read -r caminho; do
      [ -n "$caminho" ] || continue
      alvo="$caminho"; [ "${caminho#/}" = "$caminho" ] && alvo="$ROOT/$caminho"
      pres=false; [ -e "$alvo" ] && pres=true
      ITENS=$(jq -cn --argjson prev "$ITENS" --arg p "$plan" --arg n "$caminho" --argjson pr "$pres" \
        '$prev + [{plano:$p, tipo:"arquivo", nome:$n, satisfeito:$pr}]')
    done < <(printf '%s' "$pre" | grep -oE '[[:alnum:]_./-]+\.(json|pem|key|p12|pfx|crt|env)')
  done < <(tr '\n' ' ' < "$f" | grep -oi '<precondition>[^<]*</precondition>')
done

PEND=$(jq -c 'map(select(.satisfeito == false))' <<<"$ITENS")
if [ "$(jq 'length' <<<"$ITENS")" = 0 ]; then
  VER=nao_se_aplica; COD='[]'
elif [ "$(jq 'length' <<<"$PEND")" -gt 0 ]; then
  VER=falha; COD='["USER-SETUP-PENDENTE"]'
else
  VER=ok; COD='[]'
fi

jq -cn --arg pd "$PD" --argjson n "$N" --argjson itens "$ITENS" --argjson gh "$GH_OK" \
  --argjson pend "$PEND" --arg v "$VER" --argjson cod "$COD" \
  '{fase_dir:$pd, planos:$n, itens:$itens, gh_disponivel:$gh, pendentes:$pend, veredito:$v, codigos:$cod}'
[ "$VER" = falha ] && exit 1
exit 0
