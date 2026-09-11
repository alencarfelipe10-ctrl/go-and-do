#!/usr/bin/env bash
# test-mede-tokens.sh — bancada do mede-tokens.py (47a: escrita de cache por TTL).
#
# O script não tinha bancada. Os casos cobrem o que o 47a acrescentou: a escrita de cache de 1 h
# (`usage.cache_creation.ephemeral_1h_input_tokens`) sai num campo próprio, a 2× o input, sem
# mudar o TOTAL de escrita; turno multi-iteração soma as iterações (o objeto de topo reflete só a
# última); transcript antigo, sem o objeto, conta tudo como 5 min — o que já era.
#   bash tests/test-mede-tokens.sh      · exit 0 = verde
set -u
RAIZ="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
M="$RAIZ/skills/go-and-do/scripts/mede-tokens.py"
OK=0; FALHAS=0
ok()    { OK=$((OK+1)); printf '  ✔ %s\n' "$1"; }
falha() { FALHAS=$((FALHAS+1)); printf '  ✘ %s\n     %s\n' "$1" "${2:-}"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1" "esperado [$3], obtido [$2]"; fi; }

BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT
med() { python3 "$M" --transcript "$1" --sem-espelho 2>/dev/null | tail -1; }

# ── 1. só 5 min (transcript com cache_creation, ephemeral_1h = 0) ──
cat > "$BASE/t5m.jsonl" <<'EOF'
{"requestId":"r1","timestamp":"2026-09-09T15:00:00.000Z","message":{"model":"claude-opus-5","usage":{"input_tokens":100,"cache_creation_input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":1000,"ephemeral_1h_input_tokens":0},"cache_read_input_tokens":2000,"output_tokens":50}}}
EOF
J="$(med "$BASE/t5m.jsonl")"
eq "5m: cache_creation_tokens = 1000"     "$(printf '%s' "$J" | jq -r '.total.cache_creation_tokens')" "1000"
eq "5m: cache_creation_1h_tokens = 0"     "$(printf '%s' "$J" | jq -r '.total.cache_creation_1h_tokens')" "0"
# custo: 100*5 + 1000*6.25 + 2000*0.5 + 50*25 = 500+6250+1000+1250 = 9000 /1e6 = 0.009
eq "5m: custo usa cache_write (6.25/1M)"  "$(printf '%s' "$J" | jq -r '.total.custo_usd')" "0.009"

# ── 2. só 1 h ──
cat > "$BASE/t1h.jsonl" <<'EOF'
{"requestId":"r1","timestamp":"2026-09-09T15:00:00.000Z","message":{"model":"claude-opus-5","usage":{"input_tokens":100,"cache_creation_input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":1000},"cache_read_input_tokens":2000,"output_tokens":50}}}
EOF
J="$(med "$BASE/t1h.jsonl")"
eq "1h: cache_creation_tokens = 0"        "$(printf '%s' "$J" | jq -r '.total.cache_creation_tokens')" "0"
eq "1h: cache_creation_1h_tokens = 1000"  "$(printf '%s' "$J" | jq -r '.total.cache_creation_1h_tokens')" "1000"
# custo: 500 + 1000*10 + 1000 + 1250 = 12750 /1e6 = 0,01275 → arredondado a 4 casas pelo script
eq "1h: custo usa cache_write_1h (2× o input = 10/1M)" "$(printf '%s' "$J" | jq -r '.total.custo_usd')" "0.0128"

# ── 3. turno multi-iteração: o topo reflete só a última, o total é a soma ──
cat > "$BASE/titer.jsonl" <<'EOF'
{"requestId":"r1","timestamp":"2026-09-09T15:00:00.000Z","message":{"model":"claude-opus-5","usage":{"input_tokens":0,"cache_creation_input_tokens":3000,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":1000},"iterations":[{"cache_creation":{"ephemeral_1h_input_tokens":2000}},{"cache_creation":{"ephemeral_1h_input_tokens":1000}}],"cache_read_input_tokens":0,"output_tokens":0}}}
EOF
J="$(med "$BASE/titer.jsonl")"
eq "iterações: 1h soma as duas (2000+1000)" "$(printf '%s' "$J" | jq -r '.total.cache_creation_1h_tokens')" "3000"
eq "…e a sobra de 5 min é zero"             "$(printf '%s' "$J" | jq -r '.total.cache_creation_tokens')" "0"

# ── 4. transcript antigo, sem o objeto cache_creation → tudo 5 min (o que já era) ──
cat > "$BASE/tvelho.jsonl" <<'EOF'
{"requestId":"r1","timestamp":"2026-09-09T15:00:00.000Z","message":{"model":"claude-opus-5","usage":{"input_tokens":0,"cache_creation_input_tokens":1234,"cache_read_input_tokens":0,"output_tokens":0}}}
EOF
J="$(med "$BASE/tvelho.jsonl")"
eq "antigo: tudo em 5 min"       "$(printf '%s' "$J" | jq -r '.total.cache_creation_tokens')" "1234"
eq "antigo: 1h = 0"              "$(printf '%s' "$J" | jq -r '.total.cache_creation_1h_tokens')" "0"

# ── 5. o TOTAL de escrita nunca muda (é o invariante da retrocompatibilidade) ──
for f in t5m t1h titer tvelho; do
  J="$(med "$BASE/$f.jsonl")"
  soma=$(printf '%s' "$J" | jq -r '.total.cache_creation_tokens + .total.cache_creation_1h_tokens')
  bruto=$(jq -r '[.message.usage.cache_creation_input_tokens] | add' "$BASE/$f.jsonl")
  eq "$f: 5m + 1h = cache_creation_input_tokens bruto" "$soma" "$bruto"
done

echo
echo "── resumo: $OK ok / $FALHAS falhas ──"
[ "$FALHAS" -eq 0 ]
