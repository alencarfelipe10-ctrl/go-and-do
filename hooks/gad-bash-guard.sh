#!/usr/bin/env bash
# gad-bash-guard.sh — hook PreToolUse (matcher Bash) da go-and-do: nega comando em segundo
# plano ou desprendido durante uma rodada ativa.
#
# Origem: F24.4 (30-31/08/2026). O executor disparou a suíte "para rodar enquanto isso"
# três vezes, esperou um aviso que nunca chega a um subagente, e depois da ordem de parar
# relançou com `setsid nohup … & disown` — o processo viveu 54 min a mais. O bloco
# <environment> do prompts/execute.md já proibia; prosa não segura. Este hook segura.
#
# Instalação (fora do repo — caminho absoluto, porque ~/.claude/hooks/ é do GSD e some no
# update):
#   ~/.claude/settings.json → hooks.PreToolUse += {matcher:"Bash", hooks:[{type:"command",
#     command:"bash $HOME/Projetos-Vox-AI/go-and-do/hooks/gad-bash-guard.sh", timeout:5}]}
#
# Escopo (fora dele: allow silencioso, exit 0, sem stdout):
#   (a) o projeto do `cwd` tem .planning/.gad-rodada-ativa.json (rodada em curso; o ponteiro
#       some no fim da rodada — fora dela o hook dorme e o dono trabalha em paz). Numa cópia
#       (worktree) o ponteiro está gitignored: procura-se também na árvore principal, via
#       `git rev-parse --git-common-dir`.
#   (b) a chamada vem de um subagente: o input do hook traz `agent_type` (Claude Code
#       ≥ 2.1.69). A sessão principal não traz o campo e fica fora. Não se restringe a
#       `gsd-executor` porque na F24.4 três dos `nohup` saíram do host de camada 1
#       (general-purpose "Execução da fase"), não do executor.
#
# Nega quando: tool_input.run_in_background === true · `nohup`/`setsid`/`disown`/`coproc`/
# `systemd-run`/`start-stop-daemon` como palavra de comando · `screen -dm`, `tmux new -d`,
# `at now` · `&` de fundo (não faz parte de &&, >&, <&, &>, |&; fora de aspas, heredoc e
# comentário). Exceção sancionada pelo <environment>: o waiter de disco
# `( <trabalho> ; touch <arquivo> ) &` — único `&` de fundo do comando, no fim.
# O corpo entre aspas de `bash -c "…"`, `sh -c '…'`, `bash -lc` e `eval "…"` passa pelas
# mesmas regras (um nível): `bash -c "uv run pytest &"` é a evasão seguinte ao `nohup`
# e custa uma linha (P21, D1).
#
# Resposta viva (contrato do CC 2.1.251): exit 0 + stdout
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
#    "permissionDecisionReason":"…"}}
# `{"decision":"block"}` de topo está deprecado — não usar.
# Ao negar, grava `incidente` no run-log da fase (origem=gad-bash-guard.sh) com timeout de
# 5 s; falha ao gravar não muda a decisão. Qualquer erro interno → allow (fail-open): um
# bug nosso não pode travar a sessão.
#
# Custo fora do escopo: o caminho rápido é um grep no stdin (~2 ms); o python3 só sobe
# quando o input traz `agent_type`. Sem dependência de jq (precedente: gsd-validate-commit.sh).

IN=$(cat 2>/dev/null) || exit 0
[ -n "$IN" ] || exit 0

# caminho rápido (sem python): sem `agent_type` não é subagente; sem ponteiro de rodada no
# cwd, na raiz do git ou na árvore principal (cópia/worktree) não há rodada → fora do escopo
printf '%s' "$IN" | grep -q '"agent_type"' || exit 0
CWD=$(printf '%s' "$IN" | sed -n 's/.*"cwd":"\([^"\\]*\)".*/\1/p' | head -n1)
if [ -n "$CWD" ] && [ ! -f "$CWD/.planning/.gad-rodada-ativa.json" ]; then
  ACHOU=0
  for d in $(git -C "$CWD" rev-parse --show-toplevel --path-format=absolute --git-common-dir 2>/dev/null); do
    d="${d%/.git}"
    [ -f "$d/.planning/.gad-rodada-ativa.json" ] && { ACHOU=1; break; }
  done
  [ "$ACHOU" = 1 ] || exit 0
fi

AQUI="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)" || exit 0
RUNLOG_SH="$AQUI/../skills/go-and-do/scripts/run-log.sh"
[ -f "$RUNLOG_SH" ] || RUNLOG_SH="$HOME/.claude/skills/go-and-do/scripts/run-log.sh"
export GAD_RUNLOG_SH="$RUNLOG_SH" GAD_IN="$IN"

python3 - <<'PY' || exit 0
import json, os, re, subprocess, sys

RUN_IN_BG_MOTIVO = "run_in_background=true"
PALAVRAS = ("nohup", "setsid", "disown", "coproc", "systemd-run", "start-stop-daemon")
# corpo entre aspas de `bash -c`, `sh -lc`, `eval` etc.: o grupo 1 é a aspa de abertura
INTERNO = re.compile(r"(?:^|[\s;|&(){}])(?:(?:bash|sh|zsh|dash)\s+(?:-\S+\s+)*?-[A-Za-z]*c[A-Za-z]*\s+|eval\s+)(['\"])")
PREFIXOS = {"time", "exec", "sudo", "command", "builtin", "env", "nice", "ionice", "timeout", "stdbuf", "unbuffer"}
BG = re.compile(r"(?<![&><|])&(?![&>])")
WAITER = re.compile(r"\(\s*[^()]*;\s*touch\s+\S+\s*\)\s*&\s*$")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1")


def sem_heredoc(cmd):
    """Remove o corpo (e a linha delimitadora) de cada heredoc; o operador fica."""
    pos = 0
    while True:
        m = HEREDOC.search(cmd, pos)
        if not m:
            return cmd
        delim = m.group(2)
        nl = cmd.find("\n", m.end())
        if nl < 0:
            return cmd
        linhas = cmd[nl + 1:].split("\n")
        fim = None
        for i, l in enumerate(linhas):
            if l.strip("\t") == delim:
                fim = i
                break
        if fim is None:
            return cmd[:nl]
        cmd = cmd[:nl + 1] + "\n".join(linhas[fim + 1:])
        pos = nl + 1


def sem_aspas(cmd):
    """Troca cada string entre aspas por Q, descarta escapes e comentários."""
    out, i, n = [], 0, len(cmd)
    while i < n:
        c = cmd[i]
        if c == "\\":
            out.append("x"); i += 2; continue
        if c == "'":
            j = cmd.find("'", i + 1)
            j = n if j < 0 else j
            out.append("Q"); i = j + 1; continue
        if c == '"':
            j = i + 1
            while j < n and cmd[j] != '"':
                j += 2 if cmd[j] == "\\" else 1
            out.append("Q"); i = j + 1; continue
        if c == "#" and (i == 0 or cmd[i - 1] in " \t\n;|&("):
            j = cmd.find("\n", i)
            i = n if j < 0 else j
            continue
        out.append(c); i += 1
    return "".join(out)


def corpos_internos(cmd):
    """Conteúdo de cada string entre aspas que é corpo de `bash -c`/`sh -c`/`eval`."""
    corpos, pos = [], 0
    while True:
        m = INTERNO.search(cmd, pos)
        if not m:
            return corpos
        q, i, n = m.group(1), m.end(), len(cmd)
        j = i
        while j < n and cmd[j] != q:
            j += 2 if (q == '"' and cmd[j] == "\\") else 1
        corpo = cmd[i:j]
        if q == '"':
            corpo = corpo.replace('\\"', '"')
        corpos.append(corpo)
        pos = j + 1


def palavra_de_comando(texto):
    for seg in re.split(r"[;\n|&(){}]+", texto):
        toks = seg.split()
        for k, tok in enumerate(toks):
            if tok in PALAVRAS:
                return tok
            if tok == "screen" and any(re.match(r"^-\w*dm", t) for t in toks[k + 1:]):
                return "screen -dm"
            if tok == "tmux" and k + 1 < len(toks) and re.match(r"^new(-session)?$", toks[k + 1]) \
                    and "-d" in toks[k + 2:]:
                return "tmux new -d"
            if tok == "at" and k + 1 < len(toks) and toks[k + 1] == "now":
                return "at now"
            if "=" in tok and re.match(r"^[A-Za-z_]\w*=", tok):
                continue
            if tok in PREFIXOS or tok.startswith("-") or tok.isdigit():
                continue
            break
    return None


def motivo_texto(cmd, nivel=0):
    """Devolve None ou o motivo; no nível 0 desce um nível nos corpos de bash -c/eval."""
    sem_hd = sem_heredoc(cmd)
    texto = sem_aspas(sem_hd)
    p = palavra_de_comando(texto)
    if p:
        return f"`{p}` como palavra de comando"
    fundos = BG.findall(texto)
    if fundos and not (len(fundos) == 1 and WAITER.search(texto.rstrip())):
        return "`&` de fundo"
    if nivel == 0:
        for corpo in corpos_internos(sem_hd):
            m = motivo_texto(corpo, 1)
            if m:
                return m + " dentro de bash -c/eval"
    return None


def decide(cmd, run_in_background):
    """Devolve None (allow) ou o motivo da negativa."""
    if run_in_background is True:
        return RUN_IN_BG_MOTIVO
    return motivo_texto(cmd)


def acha_ponteiro(cwd):
    cands = [cwd]
    try:
        r = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel",
                            "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True, timeout=3)
        if r.returncode == 0:
            linhas = [l.strip() for l in r.stdout.splitlines() if l.strip()]
            if linhas:
                cands.append(linhas[0])
            if len(linhas) > 1:
                cands.append(os.path.dirname(linhas[1]))
    except Exception:
        pass
    for c in cands:
        p = os.path.join(c, ".planning", ".gad-rodada-ativa.json")
        if os.path.isfile(p):
            return p
    return None


def etapa_aberta(runlog):
    et = "0 abertura"
    try:
        with open(runlog, encoding="utf-8") as f:
            for linha in f:
                if '"evento":"checkpoint"' in linha:
                    m = re.search(r'"etapa":"([^"]*)"', linha)
                    if m:
                        et = m.group(1)
    except Exception:
        pass
    return et


def registra(pont, agente, detalhe, motivo):
    sh = os.environ.get("GAD_RUNLOG_SH", "")
    pd, nn, rl = pont.get("phase_dir", ""), pont.get("nn", ""), pont.get("runlog", "")
    if not (sh and os.path.isfile(sh) and pd and nn):
        return
    det = re.sub(r"\s+", " ", detalhe).strip()[:120]
    try:
        subprocess.run(["bash", sh, pd, str(nn), "incidente", etapa_aberta(rl),
                        "--kv", "origem=gad-bash-guard.sh", "--kv", f"detalhe={det}",
                        "--kv", f"agente={agente}", "--kv", f"motivo={motivo}"],
                       capture_output=True, timeout=5)
    except Exception:
        pass


def main():
    d = json.loads(os.environ["GAD_IN"])
    if d.get("tool_name") != "Bash" or d.get("hook_event_name", "PreToolUse") != "PreToolUse":
        return
    agente = d.get("agent_type")
    if not agente:
        return
    cwd = d.get("cwd") or os.getcwd()
    caminho = acha_ponteiro(cwd)
    if not caminho:
        return
    with open(caminho, encoding="utf-8") as f:
        pont = json.load(f)
    sess, psess = d.get("session_id") or "", pont.get("session_id") or ""
    if sess and psess and sess != psess:
        return
    rl = pont.get("runlog") or ""
    if rl and os.path.isfile(rl):
        try:
            with open(rl, "rb") as f:
                f.seek(0, 2); tam = f.tell(); f.seek(max(0, tam - 4096))
                ultima = f.read().decode("utf-8", "replace").rstrip("\n").split("\n")[-1]
            if '"evento":"stop"' in ultima:
                return
        except Exception:
            pass
    ti = d.get("tool_input") or {}
    cmd = ti.get("command") or ""
    motivo = decide(cmd, ti.get("run_in_background"))
    if not motivo:
        return
    razao = (f"[gad-bash-guard] comando negado ({motivo}): dentro de uma rodada da go-and-do "
             "um subagente não recebe aviso de trabalho em segundo plano, e processo desprendido "
             "sobrevive ao TaskStop. Rode em primeiro plano com timeout <= 600000; para mais de "
             "10 min use o waiter de disco `( trabalho ; touch marcador ) &` e espere pelo arquivo "
             "com `timeout 590 bash -c 'until [ -s marcador ]; do sleep 15; done'`, chamado de novo "
             "enquanto o arquivo não existir. Teste ou suíte longa vai por `bash roda-suite.sh "
             "--lancar --cmd '…'` e `--esperar` (gsd-core/bin/nosso/): um lançamento só, espera em "
             "pedaços e o vermelho por arquivo.")
    registra(pont, agente, cmd, motivo)
    sys.stderr.write(f"gad-bash-guard: negado ({motivo}) agente={agente}\n")
    sys.stdout.write(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": razao}}, ensure_ascii=False) + "\n")


try:
    main()
except Exception:
    pass
PY
exit 0
