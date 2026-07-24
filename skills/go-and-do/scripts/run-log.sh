#!/usr/bin/env bash
# run-log.sh — telemetria da go-and-do (sugestão 6.2 do roadmap de evolução).
# Uso: run-log.sh <phase_dir> <NN> <evento> <etapa> [tokens] [pct] [subagent_tokens] [limit]
#   limit (8º arg, opcional) = teto do gate usado no cálculo do pct (o `limit=` que o
#   context-check.sh emite). Gravá-lo torna a telemetria autodescritiva — sem ele, uma
#   auditoria futura tem que adivinhar o denominador do pct (aconteceu: leitura de "27%"
#   foi conferida contra 500k/1M quando o teto real era 400k).
#   evento ∈ {run, checkpoint, end, stop, skip, compact} — ver Sub-rotina G do workflow.md
#   (skip = passo que não rodou por gate de config off ou ferramenta indisponível, declarado;
#    compact = auto-compact do harness detectado no meio de uma etapa)
# DETECTOR MECÂNICO DE COMPACT (desde 07/07/2026): ao gravar um `checkpoint` com tokens, o
#   script compara com o último valor de tokens registrado PELA MESMA SESSÃO neste JSONL;
#   queda > 100k (contexto não encolhe sozinho) → grava um evento `compact` automaticamente
#   antes do checkpoint. Motivo: na AOS-10 o modelo DETECTOU o compact verbalmente e esqueceu
#   de logar — detecção não pode depender de disciplina. Só compara dentro da mesma sessão
#   (retomada cross-sessão sempre "cai" e não é compact). Falso-positivo por leitura inflada
#   do advisor foi eliminado na origem (filtro no context-check.sh).
#   subagent_tokens (7º arg, opcional) = tokens gastos por um subagente da camada 1, no `end`
#   da etapa que o despachou (Sub-rotina H); omita se o harness não reportar.
# Appenda 1 linha JSON em <phase_dir>/<NN>-RUN-LOG.jsonl.
# Telemetria é instrumento, não gate: este script NUNCA falha o pipeline (exit 0 sempre).
{
  dir="$1"; nn="$2"; evento="$3"; etapa="$4"; tokens="${5:-}"; pct="${6:-}"; subt="${7:-}"; lim="${8:-}"
  [ -n "$dir" ] && [ -n "$nn" ] && [ -n "$evento" ] || exit 0
  # Caminho relativo é resolvido contra a raiz do repo, não contra o cwd — um subagente
  # parado na pasta errada criava uma árvore .planning/ DUPLICADA (caso real, F16.1).
  case "$dir" in
    /*) ;;
    *) _root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$_root" ] && dir="$_root/$dir" ;;
  esac
  mkdir -p "$dir" 2>/dev/null || exit 0

  ts=$(date -Is 2>/dev/null || date +%s)
  sess="${CLAUDE_CODE_SESSION_ID:-desconhecida}"
  sess="${sess:0:8}"

  # etapa é o único campo de texto livre — escapa aspas e barras pro JSON não quebrar
  etapa=$(printf '%s' "$etapa" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r\t')

  # Detector mecânico de auto-compact (ver cabeçalho): só em checkpoint com tokens > 0
  # (0 = medição falhou, não compact) e com session id real (sem id, duas rodadas viram a
  # mesma "sessão" e uma retomada pareceria queda). prev = último valor > 0 da mesma sessão
  # (pular zeros evita que uma medição falha mascare um compact real logo depois).
  if [ "$evento" = "checkpoint" ] && [ "$sess" != "desconhe" ]; then
    case "$tokens" in
      (''|*[!0-9]*|0) ;;
      (*)
        prev=$(grep "\"sessao\":\"$sess\"" "$dir/$nn-RUN-LOG.jsonl" 2>/dev/null \
               | sed -n 's/.*"tokens":\([0-9]*\).*/\1/p' | awk '$0+0 > 0' | tail -n1)
        if [ -n "$prev" ] && [ "$prev" -gt 0 ] 2>/dev/null && [ $(( prev - tokens )) -gt 100000 ]; then
          printf '%s\n' "{\"ts\":\"$ts\",\"sessao\":\"$sess\",\"evento\":\"compact\",\"etapa\":\"auto-detectado: queda ${prev} -> ${tokens} tokens\"}" \
            >> "$dir/$nn-RUN-LOG.jsonl"
          # Sinal no stdout — é assim que o orquestrador fica sabendo (o append é silencioso).
          echo "compact-detectado: queda ${prev} -> ${tokens} tokens"
        fi
        ;;
    esac
  fi

  # Versão da skill no evento `run` (mecânico — sem depender de disciplina do modelo):
  # `git describe` no clone (o script vive dentro dele; pwd -P resolve o symlink).
  # Motivo: na F19 uma release saiu com a fase em voo e a auditoria teve que reconstruir
  # por timestamps de commit qual versão regia cada etapa. Falhou o git → campo omitido.
  ver=""
  if [ "$evento" = "run" ]; then
    _sd=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P)
    [ -n "$_sd" ] && ver=$(git -C "$_sd" describe --tags --always 2>/dev/null | tr -cd 'A-Za-z0-9._-' | head -c 40)
  fi

  linha="{\"ts\":\"$ts\",\"sessao\":\"$sess\",\"evento\":\"$evento\",\"etapa\":\"$etapa\""
  [ -n "$ver" ] && linha="$linha,\"skill_version\":\"$ver\""
  case "$tokens" in (*[!0-9]*|'') ;; (*) linha="$linha,\"tokens\":$tokens";; esac
  case "$pct" in (*[!0-9]*|'') ;; (*) linha="$linha,\"pct\":$pct";; esac
  case "$lim" in (*[!0-9]*|'') ;; (*) linha="$linha,\"limit\":$lim";; esac
  case "$subt" in (*[!0-9]*|'') ;; (*) linha="$linha,\"subagent_tokens\":$subt";; esac
  linha="$linha}"

  printf '%s\n' "$linha" >> "$dir/$nn-RUN-LOG.jsonl"
} 2>/dev/null
exit 0
