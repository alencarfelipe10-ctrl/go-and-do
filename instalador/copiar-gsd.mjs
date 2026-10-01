// Cópia consentida de ~/.gsd para ~/.gad no install (SPEC R11, D-19, PS-07, PS-14). Só lê e monta um plano à parte;
// quem escreve é o executor de plano.mjs. Só importa node:* e módulos de instalador/ (vai no tarball, RESEARCH
// Pitfall 2). O que chega em ~/.gad é dado do usuário: as ações ficam num plano sem recibo (semRecibo), então nada de
// ~/.gad entra no recibo de remoção — o executor registraria diretorio de raiz home e todo link se as ações fossem
// para o plano do install.
//
// Contrato:
// - decidirConsentimento({ flag, tty, resposta }) → boolean: flag → sim; sem flag e sem terminal → não; em terminal,
//   sim só com a resposta s/sim/y/yes (padrão não: vazia, ausente ou qualquer outra).
// - obterConsentimento({ flag, env, entrada, saida }) → Promise<boolean>: flag → sim sem perguntar; sem terminal em
//   `entrada` ou sem <HOME>/.gsd → não, sem perguntar; senão pergunta por node:readline e decide com
//   decidirConsentimento. Roda antes do planejamento (planejarInstall é síncrono).
// - planejarCopiaGsd(ctx, plano): ctx = { home, copiarGsd }; <HOME>/.gsd ausente → nada. Sem consentimento → nada
//   (um aviso sugere --copiar-gsd quando ~/.gad ainda não existe). Com consentimento, caminha ~/.gsd por lstat (nunca
//   segue symlink abaixo da raiz) e põe em plano.copiaGsd um plano sem recibo com, em ordem de bytes: diretorio para
//   cada diretório de ~/.gad que falta, com o modo (& 0o777) do diretório de origem mais rwx do dono (CR-02; ~/.gsd é
//   a origem de ~/.gad, por stat); arquivo com os bytes e o modo (& 0o777) da origem; link com o mesmo texto de
//   alvo para cada symlink. Todas com raiz home e caminho .gad/<rel>. O defaults.json de topo sai sem a chave runtime
//   (JSON.stringify com 2 espaços e newline; ordem das chaves preservada); sem runtime, ou valor que não é objeto,
//   vai como bytes; JSON inválido não é copiado (aviso). plano.copiaGsd.fim nomeia cada caminho, nunca conteúdo.
// - Destino (c4-02, AC-38): antes de montar ações, realpath de ~/.gad (se existe) e de cada diretório existente no
//   caminho de cada destino tem de ficar em realpath(<HOME>)/.gad; fora, symlink quebrado ou entrada que não é
//   diretório → Falha(10) nomeando .gad/<rel> — no planejamento, então o install inteiro para antes da primeira
//   escrita. Entrada já existente no destino (qualquer tipo) é pulada e nomeada: nada é sobrescrito.
// - Symlink de origem (D-19, revisão c1 — Codex Achado 2): sempre recriado com o mesmo texto de alvo, nunca seguido;
//   quando o alvo, resolvido lexicalmente a partir do diretório do link em ~/.gad (absoluto tomado como está), sai de
//   <HOME>/.gad (alvoSaiDeGad, interna), plano.avisos nomeia .gad/<rel> e o install segue com saída 0. O defaults.json
//   de topo que é symlink também é recriado igual, com um aviso de que a chave runtime não foi removida.
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline/promises';
import { Falha, novoPlano } from './plano.mjs';
import { caminhar } from './lib/arvore.mjs';

const RESPOSTAS_SIM = new Set(['s', 'sim', 'y', 'yes']);
const NOME_DEFAULTS = 'defaults.json';
const ehObjeto = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

function lstatOuNull(abs) {
  try {
    return fs.lstatSync(abs);
  } catch (e) {
    if (e.code === 'ENOENT' || e.code === 'ENOTDIR') return null;
    throw e;
  }
}

function realOuNull(abs) {
  try {
    return fs.realpathSync(abs);
  } catch {
    return null;
  }
}

const dentroDe = (abs, raiz) => abs === raiz || abs.startsWith(raiz + path.sep);

/** Alvo do symlink `.gad/<rel>` resolvido lexicalmente a partir do diretório do link; verdadeiro se sai de raizGad. */
function alvoSaiDeGad(raizGad, rel, alvo) {
  const resolvido = path.resolve(path.dirname(path.join(raizGad, ...rel.split('/'))), alvo);
  return !dentroDe(resolvido, raizGad);
}

function recusa(rel, detalhe) {
  return new Falha(10, `cópia de ~/.gsd recusada: ${rel} ${detalhe}; a cópia nunca escreve fora de ~/.gad — nada foi escrito`);
}

function statOuNull(abs) {
  try {
    return fs.statSync(abs);
  } catch (e) {
    if (e.code === 'ENOENT' || e.code === 'ENOTDIR') return null;
    throw e;
  }
}

export function decidirConsentimento({ flag = false, tty = false, resposta } = {}) {
  if (flag === true) return true;
  if (tty !== true) return false;
  return typeof resposta === 'string' && RESPOSTAS_SIM.has(resposta.trim().toLowerCase());
}

export async function obterConsentimento({ flag = false, env = process.env, entrada = process.stdin, saida = process.stdout } = {}) {
  if (flag === true) return true;
  const tty = entrada?.isTTY === true;
  if (!tty) return false;
  if (typeof env.HOME !== 'string' || env.HOME.trim() === '') return false;
  if (!lstatOuNull(path.join(path.resolve(env.HOME), '.gsd'))) return false;
  const rl = readline.createInterface({ input: entrada, output: saida });
  let resposta;
  try {
    resposta = await rl.question('Copiar ~/.gsd (chaves e ajustes) para ~/.gad, sem a chave runtime do defaults.json? [s/N] ');
  } finally {
    rl.close();
  }
  return decidirConsentimento({ flag: false, tty, resposta });
}

/** defaults.json de topo: { conteudo, semRuntime } ou null quando não é JSON válido (nunca devolve o erro, que ecoa texto). */
function defaultsSemRuntime(bytes) {
  let valor;
  try {
    valor = JSON.parse(bytes.toString('utf8'));
  } catch {
    return null;
  }
  if (!ehObjeto(valor) || !Object.hasOwn(valor, 'runtime')) return { conteudo: bytes, semRuntime: false };
  delete valor.runtime;
  return { conteudo: `${JSON.stringify(valor, null, 2)}\n`, semRuntime: true };
}

export function planejarCopiaGsd(ctx, plano) {
  const { home } = ctx;
  const raizGsd = path.join(home, '.gsd');
  const raizGad = path.join(home, '.gad');
  if (!lstatOuNull(raizGsd)) return;
  if (ctx.copiarGsd !== true) {
    if (!lstatOuNull(raizGad)) {
      plano.avisos.push('~/.gsd não foi copiado para ~/.gad (sem consentimento); para copiar, rode go-and-do install --copiar-gsd');
    }
    return;
  }
  const stGsd = statOuNull(raizGsd);
  if (!stGsd || !stGsd.isDirectory()) {
    plano.avisos.push('~/.gsd não é diretório; nada foi copiado para ~/.gad');
    return;
  }
  let entradas;
  try {
    entradas = caminhar(raizGsd);
  } catch (e) {
    throw new Falha(10, `cópia de ~/.gsd recusada: ${e.message} — nada foi escrito`);
  }
  const copia = novoPlano({ subcomando: 'copiar-gsd', cfg: plano.cfg, home, semRecibo: true });
  const raizGadReal = path.join(realOuNull(home) ?? home, '.gad');
  const conferidos = new Set();
  // c4-02: cada diretório existente no caminho do destino tem de resolver dentro de ~/.gad; o que falta vira ação.
  const garantirDiretorio = (relDir) => {
    const segs = relDir.split('/');
    for (let i = 1; i <= segs.length; i++) {
      const rel = segs.slice(0, i).join('/');
      if (conferidos.has(rel)) continue;
      conferidos.add(rel);
      const abs = path.join(home, ...segs.slice(0, i));
      if (!lstatOuNull(abs)) {
        // CR-02: o diretório leva os bits de grupo e outros da origem (~/.gsd em 0700 vira ~/.gad em 0700, nunca
        // 0775); o dono sempre fica com rwx para a cópia conseguir escrever dentro.
        const origem = path.join(raizGsd, ...segs.slice(1, i));
        const modo = ((statOuNull(origem)?.mode ?? 0o700) & 0o777) | 0o700;
        copia.acoes.push({ tipo: 'diretorio', raiz: 'home', caminho: rel, modo });
        continue;
      }
      const real = realOuNull(abs);
      if (!real) throw recusa(rel, 'é symlink quebrado');
      if (!dentroDe(real, raizGadReal)) throw recusa(rel, 'resolve para fora de ~/.gad');
      if (!statOuNull(abs)?.isDirectory()) throw recusa(rel, 'existe e não é diretório, mas a cópia precisa de um diretório ali');
    }
  };
  garantirDiretorio('.gad');
  for (const { rel, tipo } of entradas) {
    const relGad = `.gad/${rel}`;
    const origem = path.join(raizGsd, ...rel.split('/'));
    garantirDiretorio(path.posix.dirname(relGad));
    if (lstatOuNull(path.join(home, ...relGad.split('/')))) {
      copia.fim.push(`~/.gsd → ~/.gad: ${relGad} já existia e não foi sobrescrito`);
      continue;
    }
    if (tipo === 'symlink') {
      const alvo = fs.readlinkSync(origem);
      copia.acoes.push({ tipo: 'link', raiz: 'home', caminho: relGad, alvo });
      copia.fim.push(`~/.gsd → ~/.gad: ${relGad} (symlink com o mesmo alvo)`);
      if (alvoSaiDeGad(raizGad, rel, alvo)) {
        plano.avisos.push(`${relGad} é symlink cujo alvo fica fora de ~/.gad; foi recriado igual, com o mesmo alvo do original em ~/.gsd`);
      }
      if (rel === NOME_DEFAULTS) {
        plano.avisos.push(`${relGad} é symlink e foi recriado com o mesmo alvo; a chave runtime não foi removida do arquivo apontado`);
      }
      continue;
    }
    const modo = fs.lstatSync(origem).mode & 0o777;
    let conteudo = fs.readFileSync(origem);
    let nota = '';
    if (rel === NOME_DEFAULTS) {
      const d = defaultsSemRuntime(conteudo);
      if (!d) {
        plano.avisos.push(`~/.gsd/${rel} não é JSON válido; não foi copiado para ~/.gad (a chave runtime não pôde ser removida)`);
        continue;
      }
      conteudo = d.conteudo;
      if (d.semRuntime) nota = ' (a chave runtime ficou de fora)';
    }
    copia.acoes.push({ tipo: 'arquivo', raiz: 'home', caminho: relGad, conteudo, modo });
    copia.fim.push(`~/.gsd → ~/.gad: ${relGad}${nota}`);
  }
  plano.copiaGsd = copia;
}
