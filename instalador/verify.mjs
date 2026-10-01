// Subcomando verify (INST-06, AC-23, D-12, c1-01): confere a instalação contra o manifesto do próprio runtime, sem
// escrever nada (não monta plano nem chama o executor). Só importa node:* e módulos de instalador/ (vai no tarball,
// RESEARCH Pitfall 2).
//
// Contrato:
// - verificar(ctx) → lista de divergências { caminho, campo, esperado, achado }, `caminho` relativo a <cfg>, ordenada
//   pelos bytes do caminho (desempate por campo e por esperado — saída estável para diff). ctx = { cfg, recibo }.
//   Camada (a), por c1-01: sha256 dos bytes de runtime/<hash>/manifest.json === <hash> do nome do diretório (vem
//   antes da árvore: é o que pega um byte alterado com o manifesto reescrito) e depois conferirManifesto da árvore
//   runtime/<hash> contra esse manifest.json (faltando, sobrando, tipo, modo, sha256). Camada (b): go-and-do/current é
//   symlink com alvo runtime/<hash>; cada link do recibo (gad-core e os atalhos de skills e agentes) é symlink com o
//   alvo registrado e resolve para o mesmo lugar que o caminho correspondente dentro de runtime/<hash> (ancorado no
//   hash, não em current); cada grupo de recibo.hooks está no settings.json por igualdade profunda. Camada extra (fora
//   da lista do AC-23): os recibos do motor em <cfg>/ (recibo.arquivos) com o sha256 registrado.
//   runtime/<hash> ausente ou que não é diretório, manifest.json ausente ou ilegível viram divergência (nunca exceção).
// - executarSubcomando(opcoes): resolverCasa → recibo (ausente, completo ≠ true ou sem runtime de 64 hex → Falha(8),
//   antes de conferir) → verificar. Sem divergência imprime a linha final de que a instalação confere e sai 0; com
//   divergência imprime uma linha por divergência no stdout e lança Falha(9). settings.json ilegível ou inválido é
//   uma divergência de settings.json (saída 9), não a Falha(6) do install.
import fs from 'node:fs';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { Falha, lerRecibo } from './plano.mjs';
import { NOME_MANIFESTO, conferirManifesto, sha256Hex } from './lib/arvore.mjs';
import { resolverCasa } from './casa.mjs';
import { lerSettings, scriptsDoGrupo } from './settings.mjs';

const REL_CURRENT = 'go-and-do/current';
const PREFIXO_RUNTIME = 'go-and-do/runtime/';
const RE_SHA256 = /^[0-9a-f]{64}$/;

const bytes = (s) => Buffer.from(String(s ?? ''), 'utf8');
const porDivergencia = (a, b) =>
  Buffer.compare(bytes(a.caminho), bytes(b.caminho)) ||
  Buffer.compare(bytes(a.campo), bytes(b.campo)) ||
  Buffer.compare(bytes(a.esperado), bytes(b.esperado));

const absDe = (cfg, rel) => path.join(cfg, ...rel.split('/'));

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

/** Camada (a): manifest.json contra o <hash> do nome do diretório, depois a árvore contra esse manifest.json. */
function conferirRuntime(cfg, hash, divergencias) {
  const relRuntime = `${PREFIXO_RUNTIME}${hash}`;
  // CR-01 (fase 3): o lstat de runtime/<hash> segue um go-and-do ou go-and-do/runtime que virou symlink; o runtime
  // estaria fora do lugar que o recibo cita, então isso é divergência e a árvore não é conferida através do link.
  for (const rel of ['go-and-do', PREFIXO_RUNTIME.slice(0, -1)]) {
    if (lstatOuNull(absDe(cfg, rel))?.isSymbolicLink()) {
      divergencias.push({ caminho: rel, campo: 'tipo', esperado: 'diretório', achado: 'symlink' });
      return;
    }
  }
  const runtimeAbs = absDe(cfg, relRuntime);
  const st = lstatOuNull(runtimeAbs);
  if (!st) {
    divergencias.push({ caminho: relRuntime, campo: 'faltando', esperado: 'presente', achado: 'ausente' });
    return;
  }
  if (!st.isDirectory()) {
    divergencias.push({ caminho: relRuntime, campo: 'tipo', esperado: 'diretório', achado: st.isSymbolicLink() ? 'symlink' : 'arquivo' });
    return;
  }
  const relManifesto = `${relRuntime}/${NOME_MANIFESTO}`;
  let bytesManifesto;
  try {
    bytesManifesto = fs.readFileSync(path.join(runtimeAbs, NOME_MANIFESTO));
  } catch (e) {
    divergencias.push({ caminho: relManifesto, campo: 'faltando', esperado: 'presente', achado: e.code || 'ilegível' });
    return;
  }
  const achado = sha256Hex(bytesManifesto);
  if (achado !== hash) divergencias.push({ caminho: relManifesto, campo: 'sha256', esperado: hash, achado });
  let arvore;
  try {
    arvore = conferirManifesto(runtimeAbs, bytesManifesto);
  } catch (e) {
    // manifest.json que não é JSON com o objeto arquivos (codigo 13) ou entrada ilegível na árvore: vira divergência.
    divergencias.push({ caminho: relManifesto, campo: 'conteudo', esperado: 'manifesto legível', achado: e.message });
    return;
  }
  for (const d of arvore) divergencias.push({ ...d, caminho: `${relRuntime}/${d.caminho}` });
}

/** Um symlink que o produto criou: tipo, alvo registrado e para onde resolve (ancorado em runtime/<hash>). */
function conferirLink(cfg, { caminho, alvo, destino }, divergencias) {
  const abs = absDe(cfg, caminho);
  const st = lstatOuNull(abs);
  if (!st) {
    divergencias.push({ caminho, campo: 'faltando', esperado: 'presente', achado: 'ausente' });
    return;
  }
  if (!st.isSymbolicLink()) {
    divergencias.push({ caminho, campo: 'tipo', esperado: 'symlink', achado: st.isDirectory() ? 'diretório' : 'arquivo' });
    return;
  }
  const lido = fs.readlinkSync(abs);
  if (lido !== alvo) {
    divergencias.push({ caminho, campo: 'alvo', esperado: alvo, achado: lido });
    return;
  }
  if (destino === undefined) return;
  const real = realOuNull(abs);
  const esperado = realOuNull(absDe(cfg, destino));
  if (real === null || real !== esperado) {
    divergencias.push({ caminho, campo: 'resolve', esperado: destino, achado: real ?? 'quebrado' });
  }
}

/** Links a conferir: current e gad-core sempre; os demais do recibo, cada um ancorado no caminho dentro do runtime. */
function linksEsperados(recibo, hash) {
  const relRuntime = `${PREFIXO_RUNTIME}${hash}`;
  const links = new Map();
  links.set(REL_CURRENT, { caminho: REL_CURRENT, alvo: `runtime/${hash}`, destino: relRuntime });
  links.set('gad-core', { caminho: 'gad-core', alvo: `${REL_CURRENT}/gad-core`, destino: `${relRuntime}/gad-core` });
  for (const l of Array.isArray(recibo.links) ? recibo.links : []) {
    if (!l || typeof l.caminho !== 'string' || typeof l.alvo !== 'string' || links.has(l.caminho)) continue;
    const s = l.caminho.split('/');
    const destino = (s[0] === 'skills' || s[0] === 'agents') && s.length === 2 ? `${relRuntime}/${l.caminho}` : undefined;
    links.set(l.caminho, { caminho: l.caminho, alvo: l.alvo, destino });
  }
  return [...links.values()];
}

/** Cada grupo de hook registrado no recibo presente no settings.json, no mesmo evento, por igualdade profunda. */
function conferirHooks(cfg, recibo, divergencias) {
  const registrados = Array.isArray(recibo.hooks) ? recibo.hooks : [];
  if (registrados.length === 0) return;
  let valor;
  try {
    ({ valor } = lerSettings({ cfg }));
  } catch (e) {
    divergencias.push({ caminho: 'settings.json', campo: 'conteudo', esperado: 'JSON legível', achado: e.message });
    return;
  }
  for (const reg of registrados) {
    if (!reg || typeof reg.evento !== 'string') continue;
    const arr = Array.isArray(valor.hooks?.[reg.evento]) ? valor.hooks[reg.evento] : [];
    if (arr.some((g) => isDeepStrictEqual(g, reg.grupo))) continue;
    const scripts = scriptsDoGrupo(reg.grupo).join(', ') || '(grupo sem script)';
    divergencias.push({ caminho: 'settings.json', campo: `hooks.${reg.evento}`, esperado: scripts, achado: 'ausente' });
  }
}

/** Camada extra: os recibos do motor em <cfg>/ com o sha256 registrado. */
function conferirRecibosDoMotor(cfg, recibo, divergencias) {
  for (const a of Array.isArray(recibo.arquivos) ? recibo.arquivos : []) {
    if (!a || typeof a.caminho !== 'string') continue;
    const abs = absDe(cfg, a.caminho);
    const st = lstatOuNull(abs);
    if (!st) divergencias.push({ caminho: a.caminho, campo: 'faltando', esperado: 'presente', achado: 'ausente' });
    else if (!st.isFile()) divergencias.push({ caminho: a.caminho, campo: 'tipo', esperado: 'arquivo', achado: 'outro' });
    else {
      const achado = sha256Hex(fs.readFileSync(abs));
      if (achado !== a.sha256) divergencias.push({ caminho: a.caminho, campo: 'sha256', esperado: a.sha256, achado });
    }
  }
}

export function verificar(ctx) {
  const { cfg, recibo } = ctx;
  const hash = recibo.runtime;
  const divergencias = [];
  conferirRuntime(cfg, hash, divergencias);
  for (const link of linksEsperados(recibo, hash)) conferirLink(cfg, link, divergencias);
  conferirHooks(cfg, recibo, divergencias);
  conferirRecibosDoMotor(cfg, recibo, divergencias);
  return divergencias.sort(porDivergencia);
}

export function linhaDe(d) {
  return `divergência: ${d.caminho} (${d.campo}: esperado ${d.esperado}, achado ${d.achado})`;
}

/** Recibo ausente, incompleto ou sem um runtime de 64 hex → Falha(8): não há o que conferir. */
function exigirRecibo(cfg) {
  const recibo = lerRecibo(cfg);
  if (!recibo) {
    throw new Falha(8, `sem recibo do go-and-do em ${cfg}/go-and-do/recibo.json; nada a conferir — rode go-and-do install`);
  }
  if (recibo.completo !== true) {
    throw new Falha(
      8,
      `instalação incompleta em ${cfg} (recibo com completo: false); rode go-and-do uninstall e instale de novo`,
    );
  }
  if (typeof recibo.runtime !== 'string' || !RE_SHA256.test(recibo.runtime)) {
    throw new Falha(8, `recibo sem o hash do runtime (64 hex) em ${cfg}/go-and-do/recibo.json`);
  }
  return recibo;
}

export async function executarSubcomando(opcoes) {
  const escrever = (s) => process.stdout.write(s);
  const { cfg } = resolverCasa({ configDir: opcoes.configDir, env: opcoes.env ?? process.env });
  const recibo = exigirRecibo(cfg);
  const divergencias = verificar({ cfg, recibo });
  if (divergencias.length === 0) {
    escrever(`A instalação em ${cfg} confere com o manifesto do runtime ${recibo.runtime}.\n`);
    return;
  }
  for (const d of divergencias) escrever(`${linhaDe(d)}\n`);
  throw new Falha(9, `verify reprovou: ${divergencias.length} divergência(s) em ${cfg}`);
}
