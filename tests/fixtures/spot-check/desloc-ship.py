def rodar_testes():
    step("x")
    env = dict(os.environ)
    env.pop("VIRTUAL_ENV", None)
    args = []
