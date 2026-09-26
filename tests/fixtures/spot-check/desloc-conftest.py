# comentario
_HASH = (
    "valorhashnaorelevante"
)
_TEST_PASSWORD = "senha-de-teste"

def login(client):
    client.post("/login", data={"username": "admin"})
    return client
