# Convivência do go-and-do com o Core

Este documento explica como o go-and-do divide a mesma casa do Claude Code com o Core (o pacote
`@opengsd/gsd-core`) quando os dois estão instalados, e o que você pode esperar de cada um.

## 1. Os vigias gad só agem em projeto marcado

Os vigias do go-and-do (os hooks registrados no `settings.json` pelo `go-and-do install`) só agem num projeto que tem
o marcador de projeto gad: o arquivo regular `.planning/gad-projeto.json` na raiz do projeto. Ele é criado pela
primeira rodada da `/go-and-do` naquele projeto, sobrevive ao fim da rodada e entra no git junto com os artefatos da
etapa, então fica versionado com o projeto.

Fora de um projeto marcado os vigias gad ficam quietos: saem sem imprimir nada e sem bloquear nada. Dentro dele, cada
vigia segue o critério que já tinha.

## 2. O gad nunca edita o que é do Core

O go-and-do nunca edita, reordena nem remove as entradas de hook do Core no `settings.json`, nem os arquivos do Core
na pasta de configuração. O `install`, o `update` e o `uninstall` só mexem nas entradas e nos arquivos que o próprio
go-and-do criou e registrou no recibo dele. Atualizar ou desinstalar o Core também não muda o runtime do go-and-do.

## 3. Dentro de projeto gad, os vigias do Core continuam disparando junto

Os vigias do Core não conhecem o marcador. Num projeto gad, os vigias do Core continuam disparando junto com os do
go-and-do, no mesmo evento: um mesmo comando pode ser conferido duas vezes, e um aviso pode aparecer em dobro. Esse é
um risco residual conhecido e aceito pelo dono do produto: resolvê-lo exigiria editar a configuração do Core, o que o
item 2 proíbe.

## 4. O `go-and-do doctor` relata a convivência

O comando `go-and-do doctor` só lê e sempre sai 0. Ele relata:

- se o Core está presente na pasta de configuração e a versão dele (ou "versão desconhecida", sem o arquivo de versão);
- cada vigia em dobro: um vigia gad e o vigia correspondente do Core registrados no mesmo evento do `settings.json`.

Nada disso impede o uso: o doctor serve para você saber o que está rodando junto.
