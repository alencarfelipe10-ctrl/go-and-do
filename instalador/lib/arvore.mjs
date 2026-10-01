// Uma implementação de árvore e manifesto para o instalador (vai no tarball, D-09; RESEARCH Pitfall 2). Só importa
// node:*. As funções caminhar, sha256Hex, validarCaminhoRelativo, entradaDe, escreverAtomico, descrever e
// conferirManifesto são cópias de montagem/lib/{caminhar,arquivos,manifesto}.mjs sem mudar mensagem nem código; o caso
// de paridade de testes/unidade/plano.test.mjs mantém as duas cópias iguais até a montagem passar a importar daqui
// (plano 03-05).
//
// Contrato (além das cópias):
// - trocarLink(link, alvo): cria <link>.tmp-<pid>-<8 hex> apontando para `alvo` e o renomeia sobre `link` — o link
//   nunca fica ausente (RESEARCH Code Examples, Pattern 4).
// - removerSomenteLeitura(raiz, limite): recusa (lança) se `raiz` não fica estritamente dentro de `limite` ou se algum
//   ancestral entre os dois é symlink; dá u+w só a diretórios caminhando por lstat (nunca segue symlink) e remove a
//   árvore (Pitfall 4). `raiz` ausente → nada a fazer.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export const NOME_MANIFESTO = 'manifest.json';

// Comparador por bytes UTF-8 (localeCompare depende de locale; sort() compara unidades UTF-16).
const porBytes = (a, b) => Buffer.compare(Buffer.from(a.rel, 'utf8'), Buffer.from(b.rel, 'utf8'));

// Devolve [{ rel, tipo }] com tipo ∈ {'arquivo', 'symlink'}, rel separado por '/', ordenado por bytes.
// Diretório vazio não gera entrada. FIFO, socket ou dispositivo lançam erro nomeando o caminho.
export function caminhar(raiz) {
  const entradas = [];
  const descer = (absDir, relDir) => {
    for (const nome of fs.readdirSync(absDir)) {
      const abs = path.join(absDir, nome);
      const rel = relDir ? `${relDir}/${nome}` : nome;
      const st = fs.lstatSync(abs);
      if (st.isSymbolicLink()) entradas.push({ rel, tipo: 'symlink' });
      else if (st.isDirectory()) descer(abs, rel);
      else if (st.isFile()) entradas.push({ rel, tipo: 'arquivo' });
      else throw new Error(`tipo de entrada não suportado (FIFO, socket ou dispositivo): ${abs}`);
    }
  };
  descer(raiz, '');
  return entradas.sort(porBytes);
}

/** sha256 em hex de um Buffer ou string. */
export function sha256Hex(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

/**
 * Valida um caminho relativo em forma POSIX. Lança se for vazio, tiver NUL, for absoluto, usar '\',
 * ou tiver segmento vazio, '.' ou '..'. Devolve o próprio caminho.
 */
export function validarCaminhoRelativo(rel) {
  if (typeof rel !== 'string' || rel.length === 0) throw new Error('caminho relativo inválido: vazio');
  if (rel.includes('\0')) throw new Error('caminho relativo inválido: contém NUL');
  if (rel.startsWith('/') || path.isAbsolute(rel)) throw new Error(`caminho relativo inválido: absoluto (${rel})`);
  if (rel.includes('\\')) throw new Error(`caminho relativo inválido: contém barra invertida (${rel})`);
  for (const seg of rel.split('/')) {
    if (seg === '' || seg === '.' || seg === '..') {
      throw new Error(`caminho relativo inválido: segmento "${seg}" (${rel})`);
    }
  }
  return rel;
}

/**
 * Identidade de uma entrada de árvore: { exec, sha256, tipo }. Usa lstat — symlink nunca é seguido:
 * o sha256 é o do texto do alvo e exec é 0. Outro tipo (diretório, fifo…) lança.
 */
export function entradaDe(raiz, rel) {
  validarCaminhoRelativo(rel);
  const abs = path.join(raiz, ...rel.split('/'));
  const st = fs.lstatSync(abs);
  if (st.isSymbolicLink()) {
    return { exec: 0, sha256: sha256Hex(Buffer.from(fs.readlinkSync(abs), 'utf8')), tipo: 'symlink' };
  }
  if (st.isFile()) {
    return { exec: st.mode & 0o111 ? 1 : 0, sha256: sha256Hex(fs.readFileSync(abs)), tipo: 'arquivo' };
  }
  throw new Error(`entrada de tipo não suportado (nem arquivo nem symlink): ${rel}`);
}

const MAX_TENTATIVAS = 16;
let contador = 0;

/**
 * Escrita atômica: temporário `<destino>.tmp-<pid>-<n>` no mesmo diretório (flag 'wx', não segue symlink
 * plantado) e renameSync. Em erro remove o temporário e relança — nunca deixa arquivo parcial.
 * Com `{ mode }` (CR-02 do code review da fase 3), o temporário já nasce com esse modo e recebe chmod exato antes do
 * rename: o destino nunca existe com um modo mais aberto que o pedido, nem por um instante. Sem `mode`, o
 * comportamento é o de antes (modo padrão do processo), que a montagem usa.
 */
export function escreverAtomico(destino, conteudo, { mode } = {}) {
  for (let tentativa = 0; ; tentativa++) {
    const tmp = `${destino}.tmp-${process.pid}-${++contador}`;
    try {
      fs.writeFileSync(tmp, conteudo, mode === undefined ? { flag: 'wx' } : { flag: 'wx', mode });
    } catch (e) {
      if (e.code === 'EEXIST' && tentativa < MAX_TENTATIVAS) continue;
      if (e.code !== 'EEXIST') fs.rmSync(tmp, { force: true });
      throw e;
    }
    try {
      if (mode !== undefined) fs.chmodSync(tmp, mode);
      fs.renameSync(tmp, destino);
    } catch (e) {
      fs.rmSync(tmp, { force: true });
      throw e;
    }
    return;
  }
}

function falha(codigo, mensagem) {
  const e = new Error(`manifesto: ${mensagem}`);
  e.codigo = codigo;
  return e;
}

const ehObjeto = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

/** Descreve a árvore: { <rel>: { modo, sha256, tipo } } na ordem de bytes de caminhar, sem o manifest.json de topo. */
export function descrever(raiz) {
  const arquivos = {};
  for (const { rel } of caminhar(raiz)) {
    if (rel === NOME_MANIFESTO) continue;
    const { exec, sha256, tipo } = entradaDe(raiz, rel);
    arquivos[rel] = { modo: exec ? '755' : '644', sha256, tipo };
  }
  return arquivos;
}

function carregarManifesto(raiz, manifesto) {
  let m = manifesto;
  if (m === undefined) {
    try {
      m = fs.readFileSync(path.join(raiz, NOME_MANIFESTO), 'utf8');
    } catch (e) {
      throw falha(13, `${NOME_MANIFESTO} ilegível ou ausente em ${raiz} (${e.code || e.message})`);
    }
  }
  if (typeof m === 'string' || Buffer.isBuffer(m)) {
    try {
      m = JSON.parse(m.toString());
    } catch (e) {
      throw falha(13, `${NOME_MANIFESTO} não é JSON válido (${e.message})`);
    }
  }
  if (!ehObjeto(m) || !ehObjeto(m.arquivos)) throw falha(13, `${NOME_MANIFESTO} sem o objeto arquivos`);
  return m;
}

/** Confere a árvore `raiz` contra o manifesto; devolve a lista de divergências (vazia = confere). */
export function conferirManifesto(raiz, manifesto) {
  const m = carregarManifesto(raiz, manifesto);
  const achado = descrever(raiz);
  const divergencias = [];
  for (const [caminho, esperado] of Object.entries(m.arquivos)) {
    const real = achado[caminho];
    if (!real) {
      divergencias.push({ caminho, campo: 'faltando', esperado: 'presente', achado: 'ausente' });
      continue;
    }
    for (const campo of ['tipo', 'modo', 'sha256']) {
      if (!ehObjeto(esperado) || esperado[campo] !== real[campo]) {
        divergencias.push({ caminho, campo, esperado: ehObjeto(esperado) ? esperado[campo] : undefined, achado: real[campo] });
      }
    }
  }
  for (const caminho of Object.keys(achado)) {
    if (!Object.hasOwn(m.arquivos, caminho)) {
      divergencias.push({ caminho, campo: 'sobrando', esperado: 'ausente', achado: 'presente' });
    }
  }
  return divergencias;
}

/** Troca (ou cria) o symlink `link` para `alvo` por rename de um temporário irmão: o link nunca fica ausente. */
export function trocarLink(link, alvo) {
  const tmp = `${link}.tmp-${process.pid}-${crypto.randomBytes(4).toString('hex')}`;
  fs.symlinkSync(alvo, tmp);
  try {
    fs.renameSync(tmp, link);
  } catch (e) {
    fs.rmSync(tmp, { force: true });
    throw e;
  }
}

/** Remove uma árvore sem bit de escrita que fica estritamente dentro de `limite`, sem seguir symlink. */
export function removerSomenteLeitura(raiz, limite) {
  const r = path.resolve(raiz);
  const l = path.resolve(limite);
  const rel = path.relative(l, r);
  if (rel === '' || rel === '..' || rel.startsWith(`..${path.sep}`) || path.isAbsolute(rel)) {
    throw new Error(`removerSomenteLeitura: ${r} fora do limite ${l}`);
  }
  const segs = rel.split(path.sep);
  let atual = l;
  for (const seg of segs.slice(0, -1)) {
    atual = path.join(atual, seg);
    let st;
    try {
      st = fs.lstatSync(atual);
    } catch {
      return;
    }
    if (st.isSymbolicLink()) throw new Error(`removerSomenteLeitura: ancestral symlink dentro do limite ${l}: ${atual}`);
  }
  let st;
  try {
    st = fs.lstatSync(r);
  } catch {
    return;
  }
  const liberar = (abs) => {
    const s = fs.lstatSync(abs);
    if (!s.isDirectory()) return;
    fs.chmodSync(abs, (s.mode & 0o7777) | 0o700);
    for (const nome of fs.readdirSync(abs)) liberar(path.join(abs, nome));
  };
  if (st.isDirectory()) liberar(r);
  fs.rmSync(r, { recursive: true, force: true });
}
