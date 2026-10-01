// Plano de ações do instalador (D-10) e o único executor que escreve em HOME. O planejador de cada subcomando só lê
// e devolve um plano; `executar` o aplica; `--dry-run` imprime o mesmo plano com `imprimirPlano` e para. Toda recusa
// acontece no planejamento ou na validação de `executar`, antes da primeira escrita.
//
// Contrato:
// - Falha(codigo, mensagem): erro com código de saída numérico (tabela no cabeçalho de bin/go-and-do.mjs).
// - REL_RECIBO = 'go-and-do/recibo.json', relativo a <cfg>.
// - novoPlano({ subcomando, cfg, home, recibo, semRecibo }) → { subcomando, cfg, home, acoes: [], recibo, avisos: [],
//   fim: [] }. `recibo` (objeto lido por lerRecibo) é a base do recibo novo; `semRecibo: true` → recibo null e o
//   executor não grava recibo (uninstall, testes).
// - Ação = objeto de dado { tipo, raiz, caminho, … }, raiz ∈ {cfg, home} (padrão cfg), caminho relativo a ela
//   (validarCaminhoRelativo). Vocabulário (o mesmo para install, update, uninstall, v2 e a cópia de ~/.gsd):
//     diretorio { modo? }       cria o diretório (o pai tem de existir); com `modo`, nasce nele e recebe chmod
//     runtime   { temporario, origem, manifesto, bytes, hash }  copia o pacote para o temporário irmão, confere sha256,
//                               impõe o modo do manifesto (0o555/0o444), diretórios 0o555, e renomeia para `caminho`
//     link      { alvo }        cria ou troca o symlink por rename (trocarLink)
//     arquivo   { conteudo, modo }  escrita atômica com o temporário já no modo, e chmod
//     settings  { valor, backup? }  JSON com 2 espaços e newline final escrito no realpath do caminho (symlink continua
//                               symlink); `backup` (relativo à raiz) recebe antes a cópia byte a byte do alvo
//     remover-link / remover-arquivo   remove se existir; tipo errado → Falha(7) antes de escrever
//     remover-runtime           só abaixo de <cfg>/go-and-do/runtime/ (removerSomenteLeitura)
//   runtime e remover-runtime com <cfg>/go-and-do ou <cfg>/go-and-do/runtime symlink → Falha(7) na validação (CR-01)
//   pela régua exportada checarDiretoriosDoRuntime(plano, tipo); desde o 03-17 a mesma régua roda também na primeira
//   linha de planejarRuntime (install.mjs), então install e update com o mesmo hash recusam esse estado no planejamento
//   mesmo sem ação de runtime planejada
//     remover-diretorio-vazio   remove se existir e estiver vazio; com conteúdo, deixa como está
// - O executor registra no recibo só diretorio (criados / criados_home), runtime (runtime, runtime_temporario) e link
//   (links); os demais campos do recibo são do planejador, que os põe em plano.recibo antes de executar.
// - imprimirPlano(plano, escrever) → uma linha por ação: `<tipo> <caminho absoluto>[ → <alvo>]`.
// - executar(plano): valida todas as ações antes de escrever; grava o recibo (D-13) com completo: false logo que
//   <cfg>/go-and-do existe e antes de cada ação seguinte, aplica as ações na ordem e regrava com completo: true.
// - lerRecibo(cfg) → objeto do recibo ou null (ausente); JSON inválido ou formato ≠ 1 → Falha(8).
import fs from 'node:fs';
import path from 'node:path';
import {
  escreverAtomico, removerSomenteLeitura, sha256Hex, trocarLink, validarCaminhoRelativo,
} from './lib/arvore.mjs';

export class Falha extends Error {
  constructor(codigo, mensagem) {
    super(mensagem);
    this.codigo = codigo;
  }
}

export const REL_RECIBO = 'go-and-do/recibo.json';
const REL_DIR_PRODUTO = 'go-and-do';
const PREFIXO_RUNTIME = 'go-and-do/runtime/';
const RAIZES = new Set(['cfg', 'home']);
const TIPOS = new Set([
  'diretorio', 'runtime', 'link', 'arquivo', 'settings', 'remover-link', 'remover-arquivo', 'remover-runtime',
  'remover-diretorio-vazio',
]);

const porBytes = (a, b) => Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8'));

function lstatOuNull(abs) {
  try {
    return fs.lstatSync(abs);
  } catch (e) {
    if (e.code === 'ENOENT') return null;
    throw e;
  }
}

function reciboVazio() {
  return { formato: 1, completo: false, runtime: null, runtime_temporario: null, criados_home: [], criados: [], links: [] };
}

export function novoPlano({ subcomando, cfg, home, recibo, semRecibo = false }) {
  let base = null;
  if (!semRecibo) {
    base = recibo ? structuredClone(recibo) : reciboVazio();
    base.completo = false;
    for (const campo of ['criados_home', 'criados', 'links']) if (!Array.isArray(base[campo])) base[campo] = [];
  }
  return { subcomando, cfg, home, acoes: [], recibo: base, avisos: [], fim: [] };
}

function raizAbs(plano, raiz) {
  return raiz === 'home' ? plano.home : plano.cfg;
}

function absDe(plano, acao, rel = acao.caminho) {
  return path.join(raizAbs(plano, acao.raiz ?? 'cfg'), ...rel.split('/'));
}

/**
 * Régua do runtime (CR-01 do code review da fase 3, D-10): <cfg>/go-and-do e <cfg>/go-and-do/runtime não podem ser
 * symlink (para dentro ou para fora de <cfg>) quando uma ação escreve ou remove o runtime — a cópia, o rename e o
 * rmSync atravessariam o link. checarAncestrais (destinos.mjs) só recusa o symlink que sai de <cfg>.
 * Desde o 03-17 (UAT 16, D-12) ela é também a primeira barreira do planejamento: planejarRuntime (install.mjs) a chama
 * antes de tudo, para que o install e o update com o mesmo hash recusem, mesmo sem ação de runtime planejada, o estado
 * que o verify reprova. A chamada em validarAcao continua como segunda barreira, contra a troca entre o planejamento e
 * a execução.
 */
export function checarDiretoriosDoRuntime(plano, tipo) {
  for (const rel of [REL_DIR_PRODUTO, PREFIXO_RUNTIME.slice(0, -1)]) {
    let st;
    try {
      st = fs.lstatSync(path.join(plano.cfg, ...rel.split('/')));
    } catch (e) {
      if (e.code === 'ENOENT' || e.code === 'ENOTDIR') continue;
      throw e;
    }
    if (st.isSymbolicLink()) {
      throw new Falha(7, `${tipo}: <cfg>/${rel} é symlink; o runtime não é escrito nem removido através dele — nada foi escrito`);
    }
  }
}

function validarAcao(plano, acao) {
  if (!acao || !TIPOS.has(acao.tipo)) throw new Falha(1, `ação de tipo desconhecido: ${acao?.tipo}`);
  const raiz = acao.raiz ?? 'cfg';
  if (!RAIZES.has(raiz)) throw new Falha(1, `ação ${acao.tipo} com raiz desconhecida: ${raiz}`);
  try {
    validarCaminhoRelativo(acao.caminho);
    if (acao.tipo === 'runtime') validarCaminhoRelativo(acao.temporario);
    if (acao.tipo === 'settings' && acao.backup !== undefined) validarCaminhoRelativo(acao.backup);
  } catch (e) {
    throw new Falha(1, `ação ${acao.tipo}: ${e.message}`);
  }
  if (acao.tipo === 'remover-runtime') {
    const rel = acao.caminho;
    if (raiz !== 'cfg' || !rel.startsWith(PREFIXO_RUNTIME) || rel.slice(PREFIXO_RUNTIME.length).includes('/')) {
      throw new Falha(1, `remover-runtime só remove <cfg>/${PREFIXO_RUNTIME}<hash>; recusado: ${rel}`);
    }
  }
  if (acao.tipo === 'runtime' || acao.tipo === 'remover-runtime') checarDiretoriosDoRuntime(plano, acao.tipo);
  if (acao.tipo === 'remover-link' || acao.tipo === 'remover-arquivo') {
    const st = lstatOuNull(absDe(plano, acao));
    if (st && acao.tipo === 'remover-link' && !st.isSymbolicLink()) {
      throw new Falha(7, `remover-link: ${acao.caminho} não é symlink; nada foi removido`);
    }
    if (st && acao.tipo === 'remover-arquivo' && !st.isFile()) {
      throw new Falha(7, `remover-arquivo: ${acao.caminho} não é arquivo regular; nada foi removido`);
    }
  }
}

export function imprimirPlano(plano, escrever = (s) => process.stdout.write(s)) {
  for (const acao of plano.acoes) {
    const abs = absDe(plano, acao);
    escrever(acao.tipo === 'link' ? `${acao.tipo} ${abs} → ${acao.alvo}\n` : `${acao.tipo} ${abs}\n`);
  }
}

export function lerRecibo(cfg) {
  const abs = path.join(cfg, ...REL_RECIBO.split('/'));
  let texto;
  try {
    texto = fs.readFileSync(abs, 'utf8');
  } catch (e) {
    if (e.code === 'ENOENT') return null;
    throw new Falha(8, `recibo ilegível: ${abs} (${e.code || e.message})`);
  }
  let recibo;
  try {
    recibo = JSON.parse(texto);
  } catch (e) {
    throw new Falha(8, `recibo não é JSON válido: ${abs} (${e.message})`);
  }
  if (!recibo || typeof recibo !== 'object' || Array.isArray(recibo) || recibo.formato !== 1) {
    throw new Falha(8, `recibo com formato desconhecido (esperado formato 1): ${abs}`);
  }
  return recibo;
}

function registrar(recibo, acao) {
  if (!recibo) return;
  const raiz = acao.raiz ?? 'cfg';
  if (acao.tipo === 'diretorio') {
    const lista = raiz === 'home' ? recibo.criados_home : recibo.criados;
    if (!lista.includes(acao.caminho)) lista.push(acao.caminho);
  } else if (acao.tipo === 'runtime') {
    recibo.runtime = acao.hash;
    recibo.runtime_temporario = acao.temporario;
  } else if (acao.tipo === 'link') {
    const i = recibo.links.findIndex((l) => l.caminho === acao.caminho);
    const entrada = { caminho: acao.caminho, alvo: acao.alvo };
    if (i >= 0) recibo.links[i] = entrada;
    else recibo.links.push(entrada);
  }
}

function aplicarRuntime(plano, acao) {
  const tmp = path.join(plano.cfg, ...acao.temporario.split('/'));
  const destino = absDe(plano, acao);
  const limite = path.dirname(tmp);
  fs.mkdirSync(tmp);
  try {
    for (const rel of Object.keys(acao.manifesto.arquivos).sort(porBytes)) {
      const e = acao.manifesto.arquivos[rel];
      const dst = path.join(tmp, ...rel.split('/'));
      fs.mkdirSync(path.dirname(dst), { recursive: true });
      fs.copyFileSync(path.join(acao.origem, ...rel.split('/')), dst, fs.constants.COPYFILE_EXCL);
      if (sha256Hex(fs.readFileSync(dst)) !== e.sha256) {
        throw new Falha(5, `arquivo do pacote diverge do manifesto: ${rel}`);
      }
      fs.chmodSync(dst, e.modo === '755' ? 0o555 : 0o444);
    }
    const man = path.join(tmp, 'manifest.json');
    fs.writeFileSync(man, acao.bytes, { flag: 'wx' });
    if (sha256Hex(fs.readFileSync(man)) !== acao.hash) throw new Falha(5, 'manifest.json copiado diverge do hash do runtime');
    fs.chmodSync(man, 0o444);
    const dirs = [];
    const coletar = (abs, prof) => {
      dirs.push({ abs, prof });
      for (const nome of fs.readdirSync(abs)) {
        const p = path.join(abs, nome);
        if (fs.lstatSync(p).isDirectory()) coletar(p, prof + 1);
      }
    };
    coletar(tmp, 0);
    dirs.sort((a, b) => b.prof - a.prof);
    for (const { abs } of dirs) fs.chmodSync(abs, 0o555);
    fs.renameSync(tmp, destino);
  } catch (e) {
    removerSomenteLeitura(tmp, limite);
    throw e;
  }
}

function aplicarSettings(plano, acao) {
  const abs = absDe(plano, acao);
  const st = lstatOuNull(abs);
  let alvo = abs;
  if (st) {
    try {
      alvo = fs.realpathSync(abs);
    } catch (e) {
      throw new Falha(6, `${acao.caminho} é symlink quebrado (${e.code || e.message}); nada foi escrito`);
    }
  }
  const modoAntes = st ? fs.statSync(alvo).mode & 0o7777 : null;
  if (acao.backup !== undefined && st) {
    fs.copyFileSync(alvo, absDe(plano, acao, acao.backup), fs.constants.COPYFILE_EXCL);
  }
  // CR-02: o settings.json existente (0600 com um bloco env com token, por exemplo) é regravado já no modo de antes;
  // o chmod depois do rename continua como conferência.
  escreverAtomico(alvo, `${JSON.stringify(acao.valor, null, 2)}\n`, modoAntes === null ? {} : { mode: modoAntes });
  if (modoAntes !== null) fs.chmodSync(alvo, modoAntes);
}

function aplicar(plano, acao) {
  const abs = absDe(plano, acao);
  switch (acao.tipo) {
    case 'diretorio':
      // CR-02: com `modo` (a cópia de ~/.gsd), o diretório já nasce nele e o chmod tira o efeito da umask; sem `modo`,
      // o de antes (skills, agents, go-and-do do install).
      if (acao.modo === undefined) {
        fs.mkdirSync(abs);
      } else {
        fs.mkdirSync(abs, { mode: acao.modo });
        fs.chmodSync(abs, acao.modo);
      }
      break;
    case 'runtime':
      aplicarRuntime(plano, acao);
      break;
    case 'link':
      trocarLink(abs, acao.alvo);
      break;
    case 'arquivo':
      // CR-02: o arquivo nasce no modo final (chaves de ~/.gsd em 0600 nunca passam por 0664); o chmod fica.
      escreverAtomico(abs, acao.conteudo, { mode: acao.modo ?? 0o644 });
      fs.chmodSync(abs, acao.modo ?? 0o644);
      break;
    case 'settings':
      aplicarSettings(plano, acao);
      break;
    case 'remover-link':
    case 'remover-arquivo':
      if (lstatOuNull(abs)) fs.unlinkSync(abs);
      break;
    case 'remover-runtime':
      removerSomenteLeitura(abs, path.join(plano.cfg, ...PREFIXO_RUNTIME.slice(0, -1).split('/')));
      break;
    case 'remover-diretorio-vazio':
      try {
        fs.rmdirSync(abs);
      } catch (e) {
        if (!['ENOENT', 'ENOTEMPTY', 'EEXIST'].includes(e.code)) throw e;
      }
      break;
    default:
      throw new Falha(1, `ação de tipo desconhecido: ${acao.tipo}`);
  }
}

export function executar(plano) {
  for (const acao of plano.acoes) validarAcao(plano, acao);
  const dirProduto = path.join(plano.cfg, ...REL_DIR_PRODUTO.split('/'));
  const reciboAbs = path.join(plano.cfg, ...REL_RECIBO.split('/'));
  const gravar = () => {
    if (plano.recibo && fs.existsSync(dirProduto)) {
      escreverAtomico(reciboAbs, `${JSON.stringify(plano.recibo, null, 2)}\n`);
    }
  };
  for (const acao of plano.acoes) {
    registrar(plano.recibo, acao);
    gravar();
    aplicar(plano, acao);
    if (acao.tipo === 'diretorio') gravar();
  }
  if (plano.recibo) plano.recibo.completo = true;
  gravar();
}
