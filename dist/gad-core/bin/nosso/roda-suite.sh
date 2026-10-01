#!/usr/bin/env bash
# roda-suite.sh — lança uma suíte de testes uma vez, espera em pedaços e devolve o vermelho
# por arquivo (fork gen5-patches, plano 4 / A2, 05/09/2026).
#
# Por que existe: na F24.4 dez lançamentos de suíte foram perdidos (~2 h) porque o waiter de
# 1800 s do plano estourava dentro de uma tool que morre aos 600 s, o executor concluía que a
# suíte tinha morrido e relançava por cima — duas rodadas `-n 4` disputando 4 núcleos param
# as duas. Aqui o lançamento é um só por repositório (lock), a espera é em pedaços de até
# 590 s e o resultado vem pronto para o host mandar o conserto ao plano dono do arquivo.
#
# Uso:
#   roda-suite.sh --lancar  --cmd "<comando>" [--tag <nome>] [--dir <raiz>]
#   roda-suite.sh --esperar [--tag <nome>] [--teto 590] [--dir <raiz>]
#   roda-suite.sh --status  [--tag <nome>] [--dir <raiz>]
#   roda-suite.sh --matar   [--tag <nome>] [--dir <raiz>]
#   roda-suite.sh --gate-onda [--fase N] [--onda W] [--cmd-base "<prefixo>"] [--dir <raiz>]
#   roda-suite.sh --aceitar-assinatura [--dir <raiz>]
#
# Estado em `$(git rev-parse --git-common-dir)/gad-suite/<tag>/` (cmd, pid, log, rc, iniciado, recusados):
# o common-dir é o mesmo para todos os worktrees do repositório e não é versionado — em
# `.planning/` cada cópia teria o próprio lock e dois executores paralelos lançariam duas
# suítes, que é o que este script existe para impedir.
#
# Exit: 0 terminou (--esperar/--gate-onda devolvem também `rc=<n>` no stdout) · 3 já há uma
# suíte rodando (--lancar) · 4 ainda rodando, chame --esperar de novo · 5 o processo morreu
# sem gravar rc · 6 a planilha de teste mudou desde a última suíte verde (--lancar, ver
# abaixo) · 2 uso inválido. `--esperar` é chamado com `timeout: 600000` na tool — o
# default de 120 s mataria a própria espera.
#
# FM-F27INS-01EXE (26/09/2026): a planilha real de dado de aluno fica fora do git (LGPD) —
# o git não avisa quando alguém a salva por cima fora da fase (F27: 32m24s de suíte vermelha
# por uma aba perdida). `--lancar` confere, ANTES de lançar, a assinatura (sha256) de cada
# arquivo que casa `workflow.suite_planilhas_glob` (lista de globs em `.planning/config.json`
# do PROJETO — nunca hard-coded aqui, cada projeto declara as próprias planilhas; sem a
# chave, o recurso fica desligado e nunca acusa nada). A assinatura é gravada em
# `.planning/.gad/suite/assinaturas.json` (estado efêmero, `.gitignore` de gad-caminhos.sh)
# só quando uma suíte lançada por --lancar termina com rc=0 (suíte verde valida o estado
# atual como referência). Mudou desde a última suíte verde → --lancar sai 6 com uma
# mensagem curta, sem lançar; `--aceitar-assinatura` grava a assinatura atual como nova
# referência de propósito (ex.: o dono atualizou a planilha), sem rodar suíte nenhuma.
#
# O lançamento é `( eval "$CMD" > log 2>&1 ; echo $? > rc ) &`, a única forma que o hook
# `gad-bash-guard.sh` sanciona; nenhuma das quatro palavras de desprendimento que ele nega
# aparece aqui, e o processo fica no grupo da sessão — `--matar` e a varredura de órfãos o
# alcançam. Teto de stdout de 20 KB (regra do P18): acima disso saem os 40 primeiros node
# IDs e o caminho do log.
set -u

MODO=""; CMD=""; TAG="suite"; DIR=""; TETO=590; FASE=""; ONDA=""; CMD_BASE="uv run pytest -n 4 -q"
while [ $# -gt 0 ]; do
  case "$1" in
    --lancar|--esperar|--status|--matar|--gate-onda|--aceitar-assinatura) MODO="${1#--}"; shift ;;
    --cmd)      CMD="${2:-}"; shift 2 ;;
    --tag)      TAG="${2:-}"; shift 2 ;;
    --dir)      DIR="${2:-}"; shift 2 ;;
    --teto)     TETO="${2:-590}"; shift 2 ;;
    --fase)     FASE="${2:-}"; shift 2 ;;
    --onda)     ONDA="${2:-}"; shift 2 ;;
    --cmd-base) CMD_BASE="${2:-}"; shift 2 ;;
    -h|--help)  sed -n '2,46p' "$0"; exit 0 ;;
    *) echo "roda-suite.sh: flag desconhecida: $1" >&2; exit 2 ;;
  esac
done
[ -n "$MODO" ] || { echo "uso: roda-suite.sh --lancar --cmd '<comando>' | --esperar | --status | --matar | --gate-onda | --aceitar-assinatura" >&2; exit 2; }
DIR="${DIR:-$PWD}"
[ -d "$DIR" ] || { echo "roda-suite.sh: --dir inexistente: $DIR" >&2; exit 2; }
printf '%s' "$TAG" | grep -qE '^[A-Za-z0-9._-]+$' || { echo "roda-suite.sh: --tag inválida: $TAG" >&2; exit 2; }
COMMON=$(git -C "$DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || { echo "roda-suite.sh: $DIR não é um repositório git" >&2; exit 2; }
ST="$COMMON/gad-suite/$TAG"; mkdir -p "$ST"
F_CMD="$ST/cmd"; F_PID="$ST/pid"; F_LOG="$ST/log"; F_RC="$ST/rc"; F_INI="$ST/iniciado"

vivo() { # <pid> → 0 se o processo existe
  [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}
pid_atual() { cat "$F_PID" 2>/dev/null || true; }

# FM-F4RLR-09EXE→FM-F4RLR-07EXE (fork gen5-patches, 22/09/2026): grava o próprio evento `script`
# no run-log quando a suíte termina de verdade (rc gravado, não em --lancar nem a cada poll de
# --esperar). Reusa a mesma `gad_autoregistro` que os 13 scripts da go-and-do já chamam — SEM
# `trap … EXIT` (achado §6.1 do executor 1: um segundo trap EXIT no mesmo script substitui o
# primeiro em silêncio); é uma chamada direta, no ponto de saída bem-sucedido de --esperar.
# roda-suite.sh vive no fork do GAD, não na skill go-and-do: degrada para no-op se o shim não
# existir (ex.: gad standalone sem a skill instalada) ou fora de uma rodada ativa (a própria
# gad_autoregistro já faz esse segundo check).
gad_registra_suite() { # <rc>
  # Dispara UMA vez por suíte (não a cada --esperar chamado depois do rc já gravado — o
  # sentinel some com $ST se a tag for relançada, então a próxima suíte volta a registrar).
  local sentinel="$ST/registrado"
  [ -e "$sentinel" ] && return 0
  local shim="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/go-and-do/scripts/lib/gad-shim.sh"
  [ -r "$shim" ] || return 0
  # shellcheck disable=SC1090
  . "$shim" 2>/dev/null || return 0
  command -v gad_autoregistro >/dev/null 2>&1 || return 0
  local sumario passed failed skipped
  sumario=$(grep -E '\b(passed|failed|error|errors|no tests ran|skipped)\b.* in [0-9.]+s' "$F_LOG" 2>/dev/null | tail -n1 | sed -E 's/^=+ *| *=+$//g')
  passed=$(grep -oE '[0-9]+ passed' <<<"$sumario" | grep -oE '^[0-9]+'); passed="${passed:-0}"
  failed=$(grep -oE '[0-9]+ failed' <<<"$sumario" | grep -oE '^[0-9]+'); failed="${failed:-0}"
  skipped=$(grep -oE '[0-9]+ skipped' <<<"$sumario" | grep -oE '^[0-9]+'); skipped="${skipped:-0}"
  gad_autoregistro "roda-suite.sh" "$1" "tag=$TAG rc=$1 passed=$passed skipped=$skipped duracao=$(( $(date +%s) - $(date -d "$(cat "$F_INI" 2>/dev/null || echo now)" +%s 2>/dev/null || date +%s) ))s falhas=$failed" || true
  : > "$sentinel"
}

# Lê o log e imprime: rc=<n>, a linha de sumário do pytest e os node IDs vermelhos por arquivo.
relatorio() { # <rc> <log>
  RC_VAL="$1" LOG_PATH="$2" python3 - <<'PY'
import os, re, sys
rc = os.environ["RC_VAL"]; log = os.environ["LOG_PATH"]
try:
    linhas = open(log, encoding="utf-8", errors="replace").read().splitlines()
except OSError:
    linhas = []
sumario = ""
for l in reversed(linhas):
    if re.search(r"\b(passed|failed|error|errors|no tests ran|skipped)\b.* in [0-9.]+s", l):
        sumario = re.sub(r"^=+\s*|\s*=+$", "", l).strip(); break
vermelhos = []
dentro = False
for l in linhas:
    if "short test summary info" in l:
        dentro = True; continue
    if dentro:
        if l.startswith("=") and "short test summary" not in l:
            break
        m = re.match(r"^(FAILED|ERROR)\s+(\S+)", l)
        if m:
            vermelhos.append(m.group(2))
por_arquivo = {}
for nid in vermelhos:
    arq = nid.split("::", 1)[0]
    por_arquivo.setdefault(arq, []).append(nid)
out = [f"rc={rc}", sumario or "(sem linha de sumário no log)"]
if vermelhos:
    out.append(f"vermelhos: {len(vermelhos)} em {len(por_arquivo)} arquivo(s)")
    for arq in sorted(por_arquivo):
        out.append(f"  {arq} ({len(por_arquivo[arq])})")
        out.extend(f"    {n}" for n in por_arquivo[arq])
texto = "\n".join(out)
if len(texto.encode()) > 20000:
    out = [f"rc={rc}", sumario or "(sem linha de sumário no log)",
           f"vermelhos: {len(vermelhos)} em {len(por_arquivo)} arquivo(s) — os 40 primeiros; lista completa em {log}"]
    out.extend(f"  {n}" for n in vermelhos[:40])
    texto = "\n".join(out)
print(texto)
PY
}

# FM-F27INS-01EXE: pasta de estado da assinatura das planilhas — usa gad_estado_dir do
# gad-caminhos.sh da skill INSTALADA (mesmo padrão de degradação de gad_registra_suite:
# no-op/fallback se a skill não estiver presente, nunca falha o script). NUNCA cria a
# árvore por si só: só quando `gad_planilhas()` já confirmou que há globs configurados
# (projeto sem `workflow.suite_planilhas_glob` não ganha `.planning/.gad/suite/` do nada).
gad_planilhas_dir() { # <raiz> → .../.gad/suite (sem criar)
  local raiz="$1" caminhos d
  caminhos="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/go-and-do/scripts/lib/gad-caminhos.sh"
  if [ -r "$caminhos" ]; then
    # shellcheck disable=SC1090
    . "$caminhos" 2>/dev/null
    command -v gad_estado_dir >/dev/null 2>&1 && d="$(gad_estado_dir "$raiz")"
  fi
  [ -n "${d:-}" ] || d="$raiz/.planning/.gad"
  printf '%s/suite' "$d"
}

# <raiz> <modo: checar|gravar> → rc 0 (ok, sem config, ou 1ª vez) · 1 (mudou, mensagem curta
# já impressa) — só examina o que `.planning/config.json: workflow.suite_planilhas_glob`
# (lista de globs relativos à raiz) declarar; sem a chave, no-op sempre, e SEM tocar o disco
# (nunca é hard-coded a um projeto específico, por design).
gad_planilhas() {
  DIR_PL="$1" MODO_PL="$2" ESTADO_DIR_PL="$(gad_planilhas_dir "$1")" python3 - <<'PY'
import glob, hashlib, json, os, sys
raiz = os.environ["DIR_PL"]; modo = os.environ["MODO_PL"]; estado_dir = os.environ["ESTADO_DIR_PL"]
try:
    cfg = json.load(open(os.path.join(raiz, ".planning", "config.json"), encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    cfg = {}
globs = (cfg.get("workflow") or {}).get("suite_planilhas_glob") or []
if not globs:
    sys.exit(0)
os.makedirs(estado_dir, exist_ok=True)
atual = {}
for g in globs:
    for f in glob.glob(os.path.join(raiz, g), recursive=True):
        if not os.path.isfile(f):
            continue
        h = hashlib.sha256()
        with open(f, "rb") as fh:
            for bloco in iter(lambda: fh.read(65536), b""):
                h.update(bloco)
        atual[os.path.relpath(f, raiz)] = h.hexdigest()
f_assin = os.path.join(estado_dir, "assinaturas.json")
if modo == "gravar":
    json.dump({"arquivos": atual}, open(f_assin, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"assinatura de {len(atual)} planilha(s) de teste gravada ({f_assin})")
    sys.exit(0)
try:
    anterior = json.load(open(f_assin, encoding="utf-8")).get("arquivos", {})
except (OSError, json.JSONDecodeError):
    sys.exit(0)          # ainda não há suíte verde de referência — nada a comparar
if not anterior or atual == anterior:
    sys.exit(0)
mudou = sorted(set(atual) ^ set(anterior)
               | {r for r in atual if r in anterior and atual[r] != anterior[r]})
resumo = ", ".join(mudou[:8]) + (f" (+{len(mudou) - 8})" if len(mudou) > 8 else "")
print(f"roda-suite.sh: planilha(s) de teste mudou(aram) desde a última suíte verde: {resumo}")
print(f"Se foi de propósito: roda-suite.sh --aceitar-assinatura --dir '{raiz}'")
sys.exit(1)
PY
}

case "$MODO" in
  aceitar-assinatura)
    gad_planilhas "$DIR" gravar
    exit 0 ;;
  lancar)
    [ -n "$CMD" ] || { echo "roda-suite.sh --lancar exige --cmd" >&2; exit 2; }
    if ! gad_planilhas "$DIR" checar; then exit 6; fi
    # mutex do lançamento: dois executores da mesma onda chamando --lancar no mesmo segundo
    # passariam ambos pela checagem do pid (nenhum gravado ainda) e lançariam duas suítes
    if ! mkdir "$ST/.lancando" 2>/dev/null; then
      echo "lançamento em curso por outro chamador (tag $TAG); use --esperar"; date -Is >> "$ST/recusados"; exit 3
    fi
    trap 'rmdir "$ST/.lancando" 2>/dev/null' EXIT
    p=$(pid_atual)
    if vivo "$p"; then
      echo "já há uma suíte rodando (pid $p, iniciada às $(cut -c12-16 "$F_INI" 2>/dev/null || echo '?')); use --esperar ou --matar. Nunca relance por cima: duas rodadas -n 4 em 4 núcleos param as duas."
      date -Is >> "$ST/recusados"   # a régua (confere-etapa.sh 3, extrai.suite) conta os relançamentos evitados
      exit 3
    fi
    # pytest sem lista de vermelhos no fim não serve ao host: acrescenta -rf quando falta
    if printf '%s' "$CMD" | grep -qE '(^|[[:space:]/])pytest([[:space:]]|$)' && ! printf '%s' "$CMD" | grep -qE '(^|[[:space:]])-r[A-Za-z]*[fa]'; then
      CMD="$CMD -rf"
    fi
    rm -f "$F_RC" "$F_LOG" "$F_PID"
    printf '%s\n' "$CMD" > "$F_CMD"; date -Is > "$F_INI"
    # os três fds fechados: o subshell não pode herdar o stdout da tool, senão a chamada
    # que lançou só volta quando a suíte acabar
    # o eval roda num subshell próprio: um `exit N` dentro do comando não pode pular o `echo $? > rc`
    ( cd "$DIR" && ( eval "$CMD" ) > "$F_LOG" 2>&1 ; echo $? > "$F_RC" ) </dev/null >/dev/null 2>&1 &
    echo $! > "$F_PID"
    echo "lançado: pid $! · tag $TAG · log $F_LOG · espere com: roda-suite.sh --esperar --tag $TAG (timeout da tool 600000)"
    exit 0 ;;
  esperar)
    [ "$TETO" -le 590 ] 2>/dev/null || TETO=590
    if [ ! -f "$F_PID" ] && [ ! -f "$F_RC" ]; then echo "nenhuma suíte lançada com a tag $TAG"; exit 5; fi
    if [ ! -s "$F_RC" ]; then
      POLL="${GAD_SUITE_POLL:-15}"
      timeout "$TETO" bash -c 'until [ -s "$1" ]; do sleep "$2"; done' _ "$F_RC" "$POLL" || true
    fi
    if [ -s "$F_RC" ]; then
      RC_ESPERAR="$(tr -d ' \n' < "$F_RC")"
      relatorio "$RC_ESPERAR" "$F_LOG"
      gad_registra_suite "$RC_ESPERAR"
      # FM-F27INS-01EXE: só grava a assinatura quando a suíte fechou VERDE — é o que
      # valida o estado atual das planilhas como a nova referência.
      [ "$RC_ESPERAR" = 0 ] && gad_planilhas "$DIR" gravar >/dev/null 2>&1
      exit 0
    fi
    p=$(pid_atual)
    if vivo "$p"; then
      echo "ainda rodando (pid $p, desde $(cat "$F_INI" 2>/dev/null)); chame --esperar de novo — encadear waiters é seu, o processo não morreu"
      exit 4
    fi
    echo "o processo (pid ${p:-?}) morreu sem gravar rc; veja $F_LOG"; exit 5 ;;
  status)
    p=$(pid_atual)
    if [ -s "$F_RC" ]; then echo "terminado: rc=$(tr -d ' \n' < "$F_RC") · log $F_LOG · iniciado $(cat "$F_INI" 2>/dev/null)"
    elif vivo "$p"; then echo "rodando: pid $p · iniciado $(cat "$F_INI" 2>/dev/null) · log $F_LOG"
    elif [ -f "$F_PID" ]; then echo "morto sem rc: pid $p · log $F_LOG"
    else echo "nenhuma suíte com a tag $TAG"; fi
    exit 0 ;;
  matar)
    p=$(pid_atual)
    if ! vivo "$p"; then echo "nada a matar (tag $TAG)"; exit 0; fi
    # descendentes do subshell, recursivamente — nunca o grupo de processos: sem desprender,
    # o grupo é o do shell da tool corrente e mataria quem chamou
    arvore() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do arvore "$c"; echo "$c"; done; }
    lista="$(arvore "$p") $p"
    kill $lista 2>/dev/null || true
    sleep 1
    for x in $lista; do vivo "$x" && kill -9 "$x" 2>/dev/null; done
    [ -s "$F_RC" ] || echo 143 > "$F_RC"
    echo "matado: pid $p e $(printf '%s\n' $lista | grep -vc "^$p\$") descendente(s); rc=143 gravado"
    exit 0 ;;
  gate-onda)
    # Gate por onda barato (post-merge-gate roda `workflow.test_command` em primeiro plano com
    # teto de 600 s): roda só os arquivos de teste que os planos da onda declaram em
    # `files_modified`. A suíte completa é do host, uma vez, depois da última onda.
    GAD="${GAD_TOOLS:-}"; [ -f "$GAD" ] || GAD="$(dirname "$(readlink -f "$0")")/../gad-tools.cjs"
    [ -f "$GAD" ] || GAD="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/gad-tools.cjs"
    [ -f "$GAD" ] || { echo "roda-suite.sh --gate-onda: gad-tools.cjs não encontrado" >&2; exit 2; }
    # Ponteiro da rodada da go-and-do: .planning/.gad/rodada-ativa.json desde a v2.10.1 (tem
    # precedência); o legado .planning/.gad-rodada-ativa.json vale por uma release.
    if [ -z "$FASE" ]; then
      for _p in "$DIR/.planning/.gad/rodada-ativa.json" "$DIR/.planning/.gad-rodada-ativa.json"; do
        [ -f "$_p" ] || continue
        FASE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("fase",""))' "$_p" 2>/dev/null || true)
        break
      done
    fi
    [ -n "$FASE" ] || { echo "roda-suite.sh --gate-onda: informe --fase N (sem ponteiro de rodada em .planning/)" >&2; exit 2; }
    IDX=$(cd "$DIR" && node "$GAD" phase-plan-index "$FASE" --raw 2>/dev/null) || IDX=""
    printf '%s' "$IDX" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null || { echo "roda-suite.sh --gate-onda: índice da fase $FASE ilegível" >&2; exit 2; }
    # (3A-20, decisão do dono 12/09/2026, opção d) a varredura de importadores fica atrás de
    # `workflow.gate_onda_importadores` (default false): medida na onda 3 da F24.5, ela leva a lista
    # de 4 para 81 arquivos (src/parsing/base.py é hub) e o gate estoura o teto de 600 s do
    # post-merge-gate em toda onda. Ligue a chave no .planning/config.json do projeto para ter a cobertura.
    IMPORTADORES=$(cd "$DIR" && node "$GAD" config-get workflow.gate_onda_importadores --default false --raw 2>/dev/null) || IMPORTADORES=false
    LISTA=$(IDX_JSON="$IDX" ONDA_ARG="$ONDA" RAIZ="$DIR" IMPORTADORES="$IMPORTADORES" python3 - <<'PY'
import glob, json, os, re
idx = json.loads(os.environ["IDX_JSON"]); raiz = os.environ["RAIZ"]
planos = {p["id"]: p for p in idx.get("plans", [])}
waves = {int(k): v for k, v in (idx.get("waves") or {}).items()}
onda = os.environ.get("ONDA_ARG") or ""
if onda:
    onda = int(onda)
else:
    # a onda mais alta cujos planos já têm SUMMARY: é a que acabou de fechar
    fechadas = [w for w, ids in waves.items() if ids and all(planos.get(i, {}).get("has_summary") for i in ids)]
    onda = max(fechadas) if fechadas else 0
arqs = []
modulos = set()      # "parsing.base" para src/parsing/base.py
pacotes = set()      # "parsing" — usado para "todos os golden do módulo"
for pid in waves.get(onda, []):
    for f in (planos.get(pid, {}).get("files_modified") or []):
        if not f.endswith(".py"):
            continue
        base = os.path.basename(f); d = os.path.dirname(f)
        if re.match(r"^(test_.*|.*_test)\.py$", base):
            arqs.append(f)
        elif d.split("/")[0] == "tests":
            irmao = os.path.join(d, "test_" + base)   # módulo auxiliar sob tests/: roda o teste homônimo
            if os.path.isfile(os.path.join(raiz, irmao)):
                arqs.append(irmao)
        else:
            # módulo de produção tocado: deriva o caminho de import do projeto
            # (src/parsing/base.py -> parsing.base; o src/ não entra no import — convenção
            # medida no inspired: `from parsing.base import ...` em 43 arquivos de teste).
            # Guarda as DUAS formas: um projeto que importe `from src.parsing.base` também casa.
            partes = f[:-3].split("/")
            modulos.add(".".join(partes))
            if partes and partes[0] in ("src", "lib", "app"):
                partes = partes[1:]
            if partes:
                modulos.add(".".join(partes))
                pacotes.add(partes[0])

# (46s) importadores: todo arquivo de teste que importa um módulo tocado + todos os goldens do
# pacote. Na F24.5 o gate da onda 3 saiu verde com 61 testes enquanto 2 goldens do mesmo módulo,
# fora da lista, já estavam vermelhos — o gate não olhou o cômodo ao lado.
if (modulos or pacotes) and os.environ.get("IMPORTADORES", "false").strip().lower() == "true":
    alvos = []
    for base_dir in ("tests",):
        for r, _dirs, fs in os.walk(os.path.join(raiz, base_dir)):
            for fn in fs:
                if not fn.endswith(".py") or not re.match(r"^(test_.*|.*_test)\.py$", fn):
                    continue
                alvos.append(os.path.relpath(os.path.join(r, fn), raiz))
    for cam in alvos:
        try:
            txt = open(os.path.join(raiz, cam), encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        casou = any(re.search(r"(^|\n)\s*(from|import)\s+" + re.escape(m) + r"\b", txt) for m in modulos)
        if not casou and cam.startswith("tests/golden/"):
            casou = any(re.search(r"(^|\n)\s*(from|import)\s+" + re.escape(p) + r"[.\s]", txt) for p in pacotes)
        if casou:
            arqs.append(cam)

# (46s) vermelho previsto por plano: o índice do GAD expõe só chaves conhecidas de frontmatter,
# então a lista vem do próprio PLAN.md. Formato: `vermelho_esperado:` com itens `- <alvo> — até o
# plano NN`, ou a forma inline `["a", "b"]`.
def _frontmatter_lista(caminho, chave):
    itens, dentro, fm = [], False, False
    try:
        linhas = open(caminho, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return itens
    for i, l in enumerate(linhas):
        if i == 0 and l.strip() == "---":
            fm = True
            continue
        if fm and l.strip() == "---":
            break
        if not fm:
            continue
        if l.startswith(chave + ":"):
            resto = l[len(chave) + 1:].strip()
            if resto.startswith("["):
                for x in resto.strip("[]").split(","):
                    x = x.strip().strip("\"'")
                    if x:
                        itens.append(x)
                break
            dentro = True
            continue
        if dentro:
            if l.lstrip().startswith("#") or not l.strip():
                continue
            if l.startswith((" ", "\t")) and l.lstrip().startswith("-"):
                itens.append(l.lstrip()[1:].strip().strip("\"'"))
                continue
            break
    return itens


esperados = []
for pid in waves.get(onda, []):
    # o índice não expõe `path` (medido 11/09 na 24.5: as chaves são agent_hint, autonomous,
    # blocked_by, depends_on, files_deleted, files_modified, halted, has_summary, id, objective,
    # task_count, wave) — o caminho do PLAN vem por glob.
    achados = glob.glob(os.path.join(raiz, ".planning/phases/*/" + pid + "-PLAN.md"))
    if not achados:
        continue
    esperados += [(pid, e) for e in _frontmatter_lista(achados[0], "vermelho_esperado")]
alvo_esperado = {e.split("—")[0].strip() for _pid, e in esperados}

vistos = []
for a in arqs:
    if a in alvo_esperado:
        continue
    if a not in vistos and os.path.isfile(os.path.join(raiz, a)):
        vistos.append(a)
print(onda)
print(" ".join(vistos))
print(" · ".join("%s: %s" % (pid, e) for pid, e in esperados))
PY
)
    ONDA_R=$(printf '%s\n' "$LISTA" | sed -n 1p); ARQS=$(printf '%s\n' "$LISTA" | sed -n 2p)
    ESPERADOS=$(printf '%s\n' "$LISTA" | sed -n 3p)
    [ -z "$ESPERADOS" ] || echo "vermelho esperado (declarado no PLAN.md, fora do gate): $ESPERADOS"
    if [ -z "$ARQS" ]; then
      echo "gate da onda $ONDA_R (fase $FASE): nenhum arquivo de teste em files_modified — nada a rodar; a suíte completa é do host, depois da última onda"
      echo "rc=0"; exit 0
    fi
    TAG="gate-onda-$ONDA_R"; ST="$COMMON/gad-suite/$TAG"; mkdir -p "$ST"; F_LOG="$ST/log"; F_RC="$ST/rc"
    CMD="$CMD_BASE $ARQS"
    printf '%s' "$CMD" | grep -qE '(^|[[:space:]])-r[A-Za-z]*[fa]' || CMD="$CMD -rf"
    printf '%s\n' "$CMD" > "$ST/cmd"; date -Is > "$ST/iniciado"
    if [ "$IMPORTADORES" = "true" ]; then
      echo "gate da onda $ONDA_R (fase $FASE): $(printf '%s\n' $ARQS | wc -w) arquivo(s) de teste (declarados + importadores dos módulos tocados + goldens do pacote — 46s)"
    else
      echo "gate da onda $ONDA_R (fase $FASE): $(printf '%s\n' $ARQS | wc -w) arquivo(s) de teste (declarados em files_modified; importadores desligados — workflow.gate_onda_importadores)"
    fi
    ( cd "$DIR" && ( eval "$CMD" ) > "$F_LOG" 2>&1 ); rc=$?; echo "$rc" > "$F_RC"
    relatorio "$rc" "$F_LOG"
    exit "$rc" ;;
esac
