import sys
p = "/home/alencar/Projetos-Vox-AI/grupo-inspired/.planning/phases/INS-27-executavel-windows/27-CONTEXT.md"
s = open(p, encoding="utf-8").read()
def rep(old, new, cid):
    global s
    assert s.count(old) == 1, (cid, s.count(old))
    s = s.replace(old, new)
# c1-01: publicação por delta não leva arquivo sem diff (pyproject/uv.lock/.gitattributes)
rep("senão o ship falha. Ver 27-SPEC.md R6 · AC-16, AC-17. Falha visível: arquivo publicado que o gate não leu,",
    "senão o ship falha. Os caminhos extras chegam ao espelho mesmo quando não têm diff no repo de trabalho dentro do intervalo do ship (pyproject.toml, uv.lock e .gitattributes ficam sem diff pela D-22 e o espelho hoje tem versão divergente ou nenhuma — PS-11): o estado publicado desses caminhos é o do commit de trabalho anonimizado, nunca o resultado de um merge com a versão antiga do espelho. [c1-01] Ver 27-SPEC.md R6 · AC-16, AC-17. Falha visível: arquivo publicado que o gate não leu, caminho extra ausente ou antigo no espelho depois do ship por não ter diff no delta, ship que morre em conflito com o pyproject.toml antigo do espelho,",
    "c1-01")
# c1-03: revert_clean limpa só src/tests
rep("usos de MIRROR_DIRS em clean-room/ship.py (:61, :226, :271, :411, :552) — re-ancorar para a lista ampliada;",
    "usos de MIRROR_DIRS em clean-room/ship.py (:61, :226, :271, :411, :552) e a limpeza de revert_clean (`git clean -fd src tests`, :541, literal fora de MIRROR_DIRS) — re-ancorar para a lista ampliada, de modo que um ship abortado não deixe arquivo novo dos caminhos extras no espelho; [c1-03]",
    "c1-03")
# c1-02: D-16 (conserto do hook no pyproject) x D-22 (pyproject sem diff)
rep("Falha visível: qualquer linha nova em [project].dependencies, versão do projeto alterada, ou lock com conjunto de produção diferente.",
    "Exceção única: se a auditoria do AC-13 provar que o hook Cython não compila no Windows (D-16), o pyproject.toml pode mudar só na configuração do hook, com a saída do build Docker idêntica e o `uv export --locked --no-dev` idêntico (AC-19). [c1-02] Falha visível: qualquer linha nova em [project].dependencies, versão do projeto alterada, mudança no pyproject fora da configuração do hook, ou lock com conjunto de produção diferente.",
    "c1-02")
open(p, "w", encoding="utf-8").write(s)
print("ok")
