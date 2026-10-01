#!/usr/bin/env node
// Ponto de entrada do produto go-and-do (D-10): só lê os argumentos e despacha o subcomando. Cada subcomando mora em
// instalador/<sub>.mjs, é importado sob demanda e exporta executarSubcomando(opcoes). Este arquivo não importa nada de
// montagem/, nomes/ nem testes/ (vai no tarball; RESEARCH Pitfall 2).
//
// Uso: go-and-do [install|update|uninstall|verify|doctor] [--config-dir <dir>] [--dry-run] [--opcional <script>]…
//      [--copiar-gsd]
//      Sem subcomando vale install.
// Saída: 0 ok · 1 inesperado · 2 uso inválido · 3 casa ou config-dir recusados · 4 pré-requisito faltando ·
//        5 pacote ou manifesto inválido · 6 settings.json inválido · 7 conflito de destino ·
//        8 recibo ausente, incompleto ou inválido · 9 verify reprovou · 10 cópia de ~/.gsd recusada
import { parseArgs } from 'node:util';

const SUBCOMANDOS = Object.freeze({
  install: '../instalador/install.mjs',
  update: '../instalador/update.mjs',
  uninstall: '../instalador/uninstall.mjs',
  verify: '../instalador/verify.mjs',
  doctor: '../instalador/doctor.mjs',
});

class ErroDeUso extends Error {
  constructor(mensagem) {
    super(mensagem);
    this.codigo = 2;
  }
}

function lerArgs(argv) {
  let values;
  let positionals;
  try {
    ({ values, positionals } = parseArgs({
      args: argv,
      strict: true,
      allowPositionals: true,
      options: {
        'config-dir': { type: 'string' },
        'dry-run': { type: 'boolean' },
        opcional: { type: 'string', multiple: true },
        'copiar-gsd': { type: 'boolean' },
      },
    }));
  } catch (e) {
    throw new ErroDeUso(`uso inválido — ${e.message}`);
  }
  if (positionals.length > 1) throw new ErroDeUso(`uso inválido — um subcomando só (recebidos: ${positionals.join(' ')})`);
  const subcomando = positionals[0] ?? 'install';
  if (!Object.hasOwn(SUBCOMANDOS, subcomando)) {
    throw new ErroDeUso(`uso inválido — subcomando desconhecido: ${subcomando} (use ${Object.keys(SUBCOMANDOS).join(', ')})`);
  }
  return {
    subcomando,
    configDir: values['config-dir'],
    dryRun: values['dry-run'] === true,
    opcional: values.opcional ?? [],
    copiarGsd: values['copiar-gsd'] === true,
    env: process.env,
  };
}

async function principal(argv) {
  const opcoes = lerArgs(argv);
  let modulo;
  try {
    modulo = await import(SUBCOMANDOS[opcoes.subcomando]);
  } catch (e) {
    if (e.code === 'ERR_MODULE_NOT_FOUND') throw new Error(`subcomando ${opcoes.subcomando} ainda não disponível nesta versão`);
    throw e;
  }
  await modulo.executarSubcomando(opcoes);
}

try {
  await principal(process.argv.slice(2));
  process.exitCode ??= 0;
} catch (e) {
  process.stderr.write(`go-and-do: ${e.message}\n`);
  process.exitCode = typeof e.codigo === 'number' ? e.codigo : 1;
}
