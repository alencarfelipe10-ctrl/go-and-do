// Resolução da casa e do diretório de config (SPEC Requirement 3, PS-04, AC-21, AC-22, borda R3; Pitfall 19).
// O instalador só aceita $HOME/.claude: os 585 anexos @~/.claude/ do dist/ só resolvem lá. A comparação é feita
// depois de resolver os dois lados (barra final e symlink não contam como diferença), inclusive com a casa ainda
// vazia: cada lado é resolvido segmento a segmento, seguindo symlink mesmo quando o alvo ainda não existe.
//
// Contrato:
// - resolverCasa({ configDir, env }) → { home, cfg } com cfg = <HOME>/.claude (forma canônica onde se escreve).
//   HOME vazio ou ausente → Falha(3). Alvo pedido = configDir ?? env.CLAUDE_CONFIG_DIR ?? <HOME>/.claude; alvo ou
//   CLAUDE_CONFIG_DIR definido que não resolve para <HOME>/.claude → Falha(3) com a forma do teste
//   (HOME=<casa> … --config-dir <casa>/.claude). Caminho de <cfg> com ", $, crase, \ ou quebra de linha → Falha(3)
//   nomeando o caractere (o caminho entra entre aspas duplas nos comandos de hook).
import fs from 'node:fs';
import path from 'node:path';
import { Falha } from './plano.mjs';

const METACARACTERES = [
  ['"', 'aspas duplas'],
  ['$', 'cifrão'],
  ['`', 'crase'],
  ['\\', 'barra invertida'],
  ['\n', 'quebra de linha'],
  ['\r', 'retorno de carro'],
];

const MAX_SALTOS = 40;
const FORMA_DO_TESTE = 'use HOME=<casa> go-and-do install --config-dir <casa>/.claude';

/** Resolve um caminho absoluto segmento a segmento, seguindo symlinks (mesmo pendentes); o resto inexistente é somado. */
function resolver(caminho, saltos = { n: 0 }) {
  const abs = path.resolve(caminho);
  const segs = abs.split(path.sep).filter(Boolean);
  let atual = path.parse(abs).root;
  for (let i = 0; i < segs.length; i++) {
    const prox = path.join(atual, segs[i]);
    let st;
    try {
      st = fs.lstatSync(prox);
    } catch {
      return path.join(prox, ...segs.slice(i + 1));
    }
    if (st.isSymbolicLink()) {
      if (++saltos.n > MAX_SALTOS) throw new Falha(3, `symlinks demais ao resolver ${abs}`);
      atual = resolver(path.resolve(atual, fs.readlinkSync(prox)), saltos);
    } else {
      atual = prox;
    }
  }
  return atual;
}

function recusarMetacaractere(rotulo, caminho) {
  for (const [car, nome] of METACARACTERES) {
    if (caminho.includes(car)) {
      throw new Falha(
        3,
        `${rotulo} tem ${nome} no caminho (${JSON.stringify(caminho)}); o caminho entra nos comandos de hook e não pode ` +
          'ter aspas duplas, cifrão, crase, barra invertida nem quebra de linha — nada foi escrito',
      );
    }
  }
}

export function resolverCasa({ configDir, env = process.env } = {}) {
  const homeBruto = env.HOME;
  if (typeof homeBruto !== 'string' || homeBruto.trim() === '') {
    throw new Falha(3, `HOME vazio ou ausente; ${FORMA_DO_TESTE} — nada foi escrito`);
  }
  const home = path.resolve(homeBruto);
  const cfg = path.join(home, '.claude');
  recusarMetacaractere('a casa', cfg);
  const esperado = resolver(cfg);
  const candidatos = [];
  if (configDir !== undefined) candidatos.push(['--config-dir', configDir]);
  if (env.CLAUDE_CONFIG_DIR !== undefined && env.CLAUDE_CONFIG_DIR !== '') {
    candidatos.push(['CLAUDE_CONFIG_DIR', env.CLAUDE_CONFIG_DIR]);
  }
  for (const [origem, valor] of candidatos) {
    if (valor === '' || resolver(valor) !== esperado) {
      throw new Falha(
        3,
        `${origem}=${valor} não é $HOME/.claude (${cfg}); o go-and-do só instala em $HOME/.claude, onde os anexos ` +
          `@~/.claude/ resolvem. Para testar numa casa separada, ${FORMA_DO_TESTE} (sem CLAUDE_CONFIG_DIR diferente) ` +
          '— nada foi escrito',
      );
    }
  }
  recusarMetacaractere('o diretório de config', esperado);
  return { home, cfg };
}
