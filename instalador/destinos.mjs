// Destinos que o install cria em <cfg> fora do runtime (D-12): atalhos de skills e agentes pelo nome estável e os
// recibos do motor. Só lê e acrescenta ações ao plano; quem escreve é o executor de plano.mjs. Só importa node:* e
// módulos de instalador/ (vai no tarball, RESEARCH Pitfall 2).
//
// Contrato:
// - classificarDestino(ctx, rel, esperado) → 'criar' | 'manter' | 'regravar' | 'trocar-v2', ou Falha(7) nomeando `rel`.
//   `esperado` string = alvo do symlink que o produto quer em <cfg>/<rel>: ausente → 'criar'; symlink com exatamente
//   esse alvo → 'manter'; atalho da lista fechada da v2 (caminho e alvo da lista, plano 03-13, D-15) → 'trocar-v2';
//   symlink para a pasta v2 que não é item da lista → Falha(7) dizendo isso (AC-27); qualquer outra coisa (arquivo,
//   diretório, symlink para outro alvo) → Falha(7).
//   `esperado` { sha256, registrado } = arquivo regular que o produto grava (recibo do motor): ausente → 'criar';
//   arquivo regular cujo sha256 é o `registrado` no recibo anterior → 'manter' se já é o `sha256` desejado, senão
//   'regravar'; qualquer outra coisa → Falha(7) (o recibo anterior é a única fonte de «nosso»).
// - checarAncestrais(ctx): skills, agents, go-and-do e go-and-do/runtime de <cfg> symlink para fora de realpath(<cfg>),
//   quebrados ou que não são diretório → Falha(7) nomeando o caminho (AC-28, c3-01, D-10); roda antes de qualquer
//   planejamento de ação.
// - planejarAtalhos(ctx, plano): nomes de skills (primeiro segmento de skills/<nome>/…) e agentes (agents/<arquivo>)
//   do manifesto do pacote; ação diretorio para skills/agents que faltam; uma ação link por atalho com alvo relativo
//   que passa por go-and-do/current (nunca pelo hash) — ../go-and-do/current/<tipo>/<nome> no caso normal. Atalho
//   que já está certo não gera ação, mas fica em plano.recibo.links. Atalho v2 ('trocar-v2') recebe a mesma ação
//   link (troca atômica por symlink temporário + rename); no fim, planejarTrocaV2 (v2.mjs) remove os só-v2 e registra
//   o estado anterior de cada atalho v2 em plano.recibo.v2.links.
// - planejarRecibosDoMotor(ctx, plano): ações arquivo (modo 0o644) para gad-file-manifest.json e .gad-profile
//   copiados do dist/ do pacote; plano.recibo.arquivos = [{ caminho, sha256 }].
import fs from 'node:fs';
import path from 'node:path';
import { Falha } from './plano.mjs';
import { sha256Hex } from './lib/arvore.mjs';
import { atalhoV2, planejarTrocaV2, recusaV2ForaDaLista } from './v2.mjs';

export const RECIBOS_DO_MOTOR = Object.freeze(['gad-file-manifest.json', '.gad-profile']);
const REL_CURRENT = 'go-and-do/current';

const porBytes = (a, b) => Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8'));

function lstatOuNull(abs) {
  try {
    return fs.lstatSync(abs);
  } catch (e) {
    if (e.code === 'ENOENT' || e.code === 'ENOTDIR') return null;
    throw e;
  }
}

function descreverTipo(st) {
  if (st.isSymbolicLink()) return 'symlink';
  if (st.isDirectory()) return 'diretório';
  if (st.isFile()) return 'arquivo';
  return 'entrada especial';
}

function recusa(rel, detalhe) {
  return new Falha(7, `conflito de destino: <cfg>/${rel} ${detalhe}; o go-and-do não sobrescreve o que não é dele — nada foi escrito`);
}

export function classificarDestino(ctx, rel, esperado) {
  const abs = path.join(ctx.cfg, ...rel.split('/'));
  const st = lstatOuNull(abs);
  if (!st) return 'criar';
  if (typeof esperado === 'string') {
    if (st.isSymbolicLink()) {
      const alvo = fs.readlinkSync(abs);
      if (alvo === esperado) return 'manter';
      if (atalhoV2(ctx, rel)) return 'trocar-v2';
      const foraDaLista = recusaV2ForaDaLista(ctx, rel);
      if (foraDaLista) throw foraDaLista;
      throw recusa(rel, `já existe como symlink para ${alvo} (o do go-and-do aponta para ${esperado})`);
    }
    throw recusa(rel, `já existe como ${descreverTipo(st)}`);
  }
  if (st.isFile() && esperado.registrado) {
    const atual = sha256Hex(fs.readFileSync(abs));
    if (atual === esperado.registrado) return atual === esperado.sha256 ? 'manter' : 'regravar';
    throw recusa(rel, 'já existe e foi mudado depois da instalação registrada no recibo');
  }
  throw recusa(rel, `já existe como ${descreverTipo(st)} que o recibo não cita`);
}

/**
 * checarAncestrais(ctx): para cada diretório de <cfg> por onde o produto escreve (skills, agents, go-and-do e
 * go-and-do/runtime, onde o runtime nasce e é renomeado — CR-01 do code review da fase 3) que exista, recusa com Falha(7) nomeando-o se é symlink cujo realpath não fica estritamente dentro de realpath(<cfg>)
 * (AC-28, c3-01), se é symlink quebrado ou se não é diretório. O settings.json não passa por aqui: symlink dele para
 * fora de <cfg> é permitido (AC-12, Pitfall 6 — regra separada em settings.mjs).
 */
export const ANCESTRAIS = Object.freeze(['skills', 'agents', 'go-and-do', 'go-and-do/runtime']);

export function checarAncestrais(ctx) {
  const { cfg } = ctx;
  if (!lstatOuNull(cfg)) return;
  const realCfg = fs.realpathSync(cfg);
  for (const rel of ANCESTRAIS) {
    const abs = path.join(cfg, ...rel.split('/'));
    const st = lstatOuNull(abs);
    if (!st) continue;
    let real;
    try {
      real = fs.realpathSync(abs);
    } catch (e) {
      throw new Falha(7, `conflito de destino: ${abs} é symlink quebrado (${e.code || 'erro'}); nada foi escrito`);
    }
    if (st.isSymbolicLink() && !real.startsWith(realCfg + path.sep)) {
      throw new Falha(
        7,
        `conflito de destino: ${abs} é symlink que resolve para fora de ${realCfg} (${real}); o go-and-do não escreve ` +
          'através dele — nada foi escrito',
      );
    }
    if (!fs.statSync(real).isDirectory()) {
      throw new Falha(7, `conflito de destino: ${abs} já existe e não é diretório; nada foi escrito`);
    }
  }
}

/** Nomes dos atalhos pedidos pelo pacote, por tipo, na ordem de bytes. */
function nomesDosAtalhos(manifesto) {
  const skills = new Set();
  const agents = new Set();
  for (const rel of Object.keys(manifesto.arquivos)) {
    const s = rel.split('/');
    if (s[0] === 'skills' && s.length >= 3) skills.add(s[1]);
    else if (s[0] === 'agents' && s.length === 2) agents.add(s[1]);
  }
  return { skills: [...skills].sort(porBytes), agents: [...agents].sort(porBytes) };
}

function realOu(abs, alternativa) {
  try {
    return fs.realpathSync(abs);
  } catch {
    return alternativa;
  }
}

function registrarLink(plano, caminho, alvo) {
  if (!plano.recibo) return;
  const i = plano.recibo.links.findIndex((l) => l.caminho === caminho);
  const entrada = { caminho, alvo };
  if (i >= 0) plano.recibo.links[i] = entrada;
  else plano.recibo.links.push(entrada);
}

export function planejarAtalhos(ctx, plano) {
  const { cfg, pacote } = ctx;
  const nomes = nomesDosAtalhos(pacote.manifesto);
  const realCfg = realOu(cfg, cfg);
  for (const tipo of ['skills', 'agents']) {
    if (nomes[tipo].length === 0) continue;
    const dirAbs = path.join(cfg, tipo);
    const existe = lstatOuNull(dirAbs) !== null;
    if (!existe) plano.acoes.push({ tipo: 'diretorio', raiz: 'cfg', caminho: tipo });
    // Alvo relativo ao diretório real onde o link mora; sem symlink no meio vale ../go-and-do/current/<tipo>/<nome>.
    const dirReal = existe ? realOu(dirAbs, path.join(realCfg, tipo)) : path.join(realCfg, tipo);
    for (const nome of nomes[tipo]) {
      const rel = `${tipo}/${nome}`;
      const alvo = path.relative(dirReal, path.join(realCfg, ...REL_CURRENT.split('/'), tipo, nome)).split(path.sep).join('/');
      const classe = classificarDestino(ctx, rel, alvo);
      if (classe === 'criar' || classe === 'trocar-v2') plano.acoes.push({ tipo: 'link', raiz: 'cfg', caminho: rel, alvo });
      else registrarLink(plano, rel, alvo);
    }
  }
  // Plano 03-13 (D-15): os atalhos v2 trocados acima e os só-v2 (que não são caminho do produto) vão para recibo.v2.
  planejarTrocaV2(ctx, plano);
}

export function planejarRecibosDoMotor(ctx, plano) {
  const { pacote } = ctx;
  const anteriores = Array.isArray(ctx.reciboAnterior?.arquivos) ? ctx.reciboAnterior.arquivos : [];
  const arquivos = [];
  for (const caminho of RECIBOS_DO_MOTOR) {
    let conteudo;
    try {
      conteudo = fs.readFileSync(path.join(pacote.origem, caminho));
    } catch (e) {
      throw new Falha(5, `pacote sem dist/${caminho} legível (${e.code || e.message}); nada foi escrito`);
    }
    const sha256 = sha256Hex(conteudo);
    const registrado = anteriores.find((a) => a && a.caminho === caminho)?.sha256 ?? null;
    const classe = classificarDestino(ctx, caminho, { sha256, registrado });
    if (classe !== 'manter') plano.acoes.push({ tipo: 'arquivo', raiz: 'cfg', caminho, conteudo, modo: 0o644 });
    arquivos.push({ caminho, sha256 });
  }
  if (plano.recibo) plano.recibo.arquivos = arquivos;
}
