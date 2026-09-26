base="/home/alencar/Projetos-Vox-AI/grupo-inspired/.planning/phases/INS-27-executavel-windows/"
def edit(f, pairs):
    p=base+f; s=open(p,encoding="utf-8").read()
    for old,new in pairs:
        assert s.count(old)==1,(f,old[:40],s.count(old)); s=s.replace(old,new)
    open(p,"w",encoding="utf-8").write(s)
# c1-07: SPEC Regression Surface ganha revert_clean; CONTEXT D-19/D-23 alinhados
edit("27-SPEC.md",[(
"| clean-room/test_gate.py, clean-room/test_verify_pacote.py — testes da ferramenta de ship |",
"| clean-room/ship.py:541 — `revert_clean` limpa só `git clean -fd src tests` (literal, fora de `MIRROR_DIRS`) | um ship abortado pode deixar no espelho arquivo novo dos caminhos extras (R6) | re-anchor — a limpeza cobre os mesmos caminhos publicados | plano da publicação |\n| clean-room/test_gate.py, clean-room/test_verify_pacote.py — testes da ferramenta de ship |")])
edit("27-CONTEXT.md",[
("(pyproject.toml, uv.lock e .gitattributes ficam sem diff pela D-22 e o espelho hoje tem versão divergente ou nenhuma — PS-11)",
 "(pyproject.toml e uv.lock tendem a ficar sem diff pela D-22, .gitattributes já existe no trabalho sem mudança pendente, e o espelho hoje tem versão divergente ou nenhuma — PS-11)"),
("options: **Manter tudo, re-ancorar só os usos de MIRROR_DIRS em ship.py (recomendada)** (chosen)",
 "options: **Manter tudo, re-ancorar só os usos de MIRROR_DIRS e a limpeza de revert_clean em ship.py (recomendada)** (chosen)")])
print("ok")
