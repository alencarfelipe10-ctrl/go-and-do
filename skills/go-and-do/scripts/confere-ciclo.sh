#!/usr/bin/env bash
# confere-ciclo.sh — piso mecânico contra omissão de achados em resumo de ciclo.
#
# Uso: confere-ciclo.sh <parecer-bruto.md> <resumo-do-ciclo(arquivo)>
#
# O que faz: extrai do parecer bruto tudo que é ESTRUTURALMENTE um achado
# (linhas/headings com marcador de severidade, IDs cN-XN, refs arquivo:linha em
# seções de risco) e confere se cada um tem rastro no resumo do ciclo
# (CYCLE_SUMMARY). Saída: coberto / NAO-COBERTO por achado + contagem final.
# Exit 0 = tudo coberto · exit 1 = há NAO-COBERTO (a regra do prompt manda ler
# o parecer bruto na íntegra) · exit 2 = uso/arquivo inválido.
#
# Limite honesto (por desenho): achado escrito em prosa pura, sem marcador, sem
# ID e sem ref de arquivo, é INDETECTÁVEL aqui — foi exatamente o caso do HIGH
# omitido no ciclo 2 da F20-ox (02/08). Por isso este script é o PISO, não o
# teto: qualquer NAO-COBERTO, contagem menor que a do parecer, ou série de
# achados em redução → leitura obrigatória do parecer bruto (regra no prompt).

set -u

PARECER="${1:-}"; RESUMO="${2:-}"
[ -r "$PARECER" ] && [ -r "$RESUMO" ] || {
  echo "uso: confere-ciclo.sh <parecer-bruto.md> <resumo-do-ciclo>" >&2; exit 2; }

SEV='HIGH|MEDIUM|LOW|CRITICAL|BLOCKER|ALTA|ALTO|M[ÉE]DIA|M[ÉE]DIO|BAIXA|BAIXO|CR[ÍI]TIC'

# 1) Linhas-achado do parecer: heading ou bullet com severidade, ou linha com ID cN-XN.
ACHADOS=$(grep -nE "(^#{2,4} .*\\[?(${SEV})|^[*-] .*\`?\\*{0,2}(${SEV})|c[0-9]+-[A-Z]+[0-9]*)" "$PARECER" \
  | grep -viE '^\s*[0-9]+:\s*(#{2,4} )?[0-9.]*\s*(pontos? fortes|strengths|sugest|suggestion)' )

[ -n "$ACHADOS" ] || { echo "achados_estruturais: 0 (nada detectável no parecer — aplique a regra de leitura do bruto)"; exit 0; }

TOTAL=0; NAOCOB=0
while IFS= read -r linha; do
  TOTAL=$((TOTAL+1))
  NLINHA="${linha%%:*}"; TEXTO="${linha#*:}"
  # 2) Tokens distintivos do achado: IDs, refs arquivo:linha, spans de código.
  TOKENS=$(printf '%s\n' "$TEXTO" | grep -oE 'c[0-9]+-[A-Z]+[0-9]*|[A-Za-z0-9_.-]+\.(ts|tsx|js|jsx|py|sh|mjs|cjs|md|sql|yml|yaml|json)(:[0-9]+)?|`[^`]{4,60}`' \
    | tr -d '`' | sort -u)
  COBERTO=false
  if [ -n "$TOKENS" ]; then
    while IFS= read -r t; do
      [ -n "$t" ] && grep -qF "$t" "$RESUMO" && { COBERTO=true; break; }
      # ref com :linha não bateu → tente só o arquivo (o resumo pode omitir a linha)
      base="${t%%:*}"
      [ "$base" != "$t" ] && grep -qF "$base" "$RESUMO" && { COBERTO=true; break; }
    done <<< "$TOKENS"
  fi
  if $COBERTO; then
    echo "coberto      L${NLINHA}: $(printf '%s' "$TEXTO" | cut -c1-90)"
  else
    NAOCOB=$((NAOCOB+1))
    echo "NAO-COBERTO  L${NLINHA}: $(printf '%s' "$TEXTO" | cut -c1-90)"
  fi
done <<< "$ACHADOS"

echo "---"
echo "achados_estruturais: ${TOTAL} · nao_cobertos: ${NAOCOB}"
[ "$NAOCOB" -eq 0 ] && exit 0 || exit 1
