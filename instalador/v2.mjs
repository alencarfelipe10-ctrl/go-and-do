// Troca da instalação v2 da go-and-do pelo produto e devolução no uninstall (D-15, exceção da D-14, INST-05). A v2 é
// reconhecida só pela lista fechada instalador/v2-lista.json (14 atalhos e 7 entradas de hook, medidos, escritos com os
// marcadores {{HOME}} e {{CFG}} — nunca o caminho real, Pitfall 10). Só lê e acrescenta ações ao plano; quem escreve é
// o executor de plano.mjs, e só em <cfg>: a pasta v2.11.0 nunca é escrita (os links são trocados por trocarLink, que
// não os segue). Só importa node:* e módulos de instalador/ (vai no tarball, RESEARCH Pitfall 2).
//
// Contrato:
// - carregarListaV2(home, cfg = <home>/.claude) → { raiz, atalhos: [{ caminho, alvo, par }], entradas: [{ evento,
//   matcher, script, caminho, destino }] } com os marcadores trocados (alvo e caminho absolutos). Lista ausente ou fora
//   do formato → Falha(5).
// - reconhecerComandoV2(comando, home, cfg) → a entrada da lista cujo caminho o comando cita, ou null. Comando =
//   `bash` + caminho entre aspas ou sem aspas; o caminho vale na forma absoluta ou com $HOME (ou ${HOME}) literal no
//   lugar da casa. Script v2 fora da lista, ou comando de outra forma → null (limitação declarada do PS-15).
// - detectarV2(ctx, settings) → { links, entradas }: links = atalhos da lista presentes em <cfg> como symlink que
//   resolve no alvo da lista (pai real dentro de <cfg> e fora da pasta v2): [{ caminho, alvo (readlink cru), par }];
//   entradas = grupos do settings.json (valor, opcional) com exatamente um hook reconhecido de mesmo evento e matcher
//   da lista: [{ evento, indice, grupo, entrada }]. Recusas, antes de qualquer escrita (Falha 7 nomeando): symlink em
//   <cfg> ou <cfg>/{skills,agents,hooks} que resolve na pasta v2 e não é item da lista (AC-27); grupo com mais de um
//   hook em que algum comando é da lista (trocá-lo apagaria hook do usuário, T-03-133), nomeando evento e índice.
// - recusaV2ForaDaLista(ctx, rel) → a Falha(7) do AC-27 quando <cfg>/<rel> é symlink para a pasta v2, senão null.
// - atalhoV2(ctx, rel) → o item da lista quando <cfg>/<rel> é um atalho v2 da lista (usado por classificarDestino para
//   devolver 'trocar-v2'), senão null.
// - garantirReciboV2(plano) → plano.recibo.v2 com links e hooks listas (objeto solto se o plano não tem recibo).
// - planejarTrocaV2(ctx, plano): para cada atalho v2 presente, o link do produto já planejado (planejarAtalhos o
//   planeja por 'trocar-v2') faz dele 'trocado'; sem ele, remover-link e 'removido'. recibo.v2.links recebe { caminho,
//   alvo_anterior, acao } de cada um que ainda não está lá (install repetido não registra de novo).
// - trocarEntradasV2(valor, entradas, desejados, scriptsDoGrupo) → { valor, itens } (pura): cada entrada v2 vira, no
//   mesmo índice, o grupo desejado de mesmo evento cujo script é o da lista; se esse grupo já está no array, a entrada
//   v2 só sai (valor_novo null). itens = [{ evento, indice, valor_anterior, valor_novo }] em ordem de evento e índice.
// - planejarDevolucaoV2(ctx, plano, recibo) e devolverEntradasV2(valor, itens): o inverso, usado pelo uninstall — os
//   atalhos voltam aos alvos anteriores e as entradas aos índices registrados (detalhes nas funções). caminhosV2(recibo)
//   → os caminhos de recibo.v2.links, que o uninstall devolve em vez de remover.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { Falha } from './plano.mjs';

const ABS_LISTA = path.join(path.dirname(fileURLToPath(import.meta.url)), 'v2-lista.json');
const M_CASA = '{{HOME}}';
const M_CFG = '{{CFG}}';
const DESTINOS = new Set(['obrigatoria', 'opcional']);

const ehObjeto = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const porBytes = (a, b) => Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8'));

let listaCrua = null;

function foraDoFormato(detalhe) {
  return new Falha(5, `instalador/v2-lista.json fora do formato (${detalhe}); nada foi escrito`);
}

function lerListaCrua() {
  if (listaCrua) return listaCrua;
  let l;
  try {
    l = JSON.parse(fs.readFileSync(ABS_LISTA, 'utf8'));
  } catch (e) {
    throw new Falha(5, `pacote sem instalador/v2-lista.json legível (${e.code || e.message}); nada foi escrito`);
  }
  if (!ehObjeto(l) || l.formato !== 1 || typeof l.raiz !== 'string') throw foraDoFormato('formato 1 e raiz');
  if (!Array.isArray(l.atalhos) || !Array.isArray(l.entradas)) throw foraDoFormato('atalhos e entradas');
  for (const a of l.atalhos) {
    if (!ehObjeto(a) || typeof a.caminho !== 'string' || typeof a.alvo !== 'string' || (a.par !== null && typeof a.par !== 'string')) {
      throw foraDoFormato(`atalho ${JSON.stringify(a?.caminho)}`);
    }
  }
  for (const e of l.entradas) {
    if (
      !ehObjeto(e) || typeof e.evento !== 'string' || (e.matcher !== null && typeof e.matcher !== 'string') ||
      typeof e.script !== 'string' || typeof e.caminho !== 'string' || !DESTINOS.has(e.destino)
    ) {
      throw foraDoFormato(`entrada ${JSON.stringify(e?.evento)} ${JSON.stringify(e?.script)}`);
    }
  }
  listaCrua = l;
  return l;
}

export function carregarListaV2(home, cfg = path.join(home, '.claude')) {
  const l = lerListaCrua();
  const trocar = (s) => s.split(M_CASA).join(home).split(M_CFG).join(cfg);
  return {
    raiz: trocar(l.raiz),
    atalhos: l.atalhos.map((a) => ({ caminho: a.caminho, alvo: trocar(a.alvo), par: a.par })),
    entradas: l.entradas.map((e) => ({
      evento: e.evento, matcher: e.matcher, script: e.script, caminho: trocar(e.caminho), destino: e.destino,
    })),
  };
}

/** Caminho citado por `bash "<caminho>"` ou `bash <caminho>`; outra forma → null. */
function caminhoDoComando(comando) {
  if (typeof comando !== 'string') return null;
  const m = /^bash\s+(?:"([^"]+)"|([^\s"]+))\s*$/.exec(comando);
  return m ? (m[1] ?? m[2]) : null;
}

/** Formas em que um caminho absoluto aparece num comando: absoluto e, se está na casa, com $HOME ou ${HOME}. */
function formasDoCaminho(abs, home) {
  const formas = [abs];
  if (abs.startsWith(home + path.sep)) {
    const resto = abs.slice(home.length);
    formas.push(`$HOME${resto}`, `\${HOME}${resto}`);
  }
  return formas;
}

const citaCaminho = (comando, entrada, home) => {
  const p = caminhoDoComando(comando);
  return p !== null && formasDoCaminho(entrada.caminho, home).includes(p);
};

export function reconhecerComandoV2(comando, home, cfg) {
  const lista = carregarListaV2(home, cfg);
  return lista.entradas.find((e) => citaCaminho(comando, e, home)) ?? null;
}

const dentro = (abs, raiz) => abs === raiz || abs.startsWith(raiz + path.sep);

function realOuNull(abs) {
  try {
    return fs.realpathSync(abs);
  } catch {
    return null;
  }
}

function lerLinkOuNull(abs) {
  try {
    return fs.lstatSync(abs).isSymbolicLink() ? fs.readlinkSync(abs) : null;
  } catch (e) {
    if (e.code === 'ENOENT' || e.code === 'ENOTDIR') return null;
    throw e;
  }
}

/** O pai do link é diretório real dentro de <cfg> e fora da pasta v2 (nunca se remove nada através de um symlink para ela). */
function paiConfiavel(ctx, abs, raizV2) {
  const realCfg = realOuNull(ctx.cfg);
  const realPai = realOuNull(path.dirname(abs));
  if (!realCfg || !realPai) return false;
  const realV2 = realOuNull(raizV2) ?? raizV2;
  return dentro(realPai, realCfg) && !dentro(realPai, realV2);
}

function atalhoPresente(ctx, lista, item) {
  const abs = path.join(ctx.cfg, ...item.caminho.split('/'));
  const alvo = lerLinkOuNull(abs);
  if (alvo === null || !paiConfiavel(ctx, abs, lista.raiz)) return null;
  return path.resolve(path.dirname(abs), alvo) === item.alvo ? { caminho: item.caminho, alvo, par: item.par } : null;
}

export function atalhoV2(ctx, rel) {
  if (!ctx?.home) return null;
  const lista = carregarListaV2(ctx.home, ctx.cfg);
  const item = lista.atalhos.find((a) => a.caminho === rel);
  return item ? atalhoPresente(ctx, lista, item) : null;
}

const matcherIgual = (esperado, grupo) =>
  esperado === null ? grupo.matcher === undefined || grupo.matcher === '' : grupo.matcher === esperado;

function detectarEntradas(ctx, lista, valor) {
  const achadas = [];
  if (!ehObjeto(valor) || !ehObjeto(valor.hooks)) return achadas;
  for (const [evento, arr] of Object.entries(valor.hooks)) {
    if (!Array.isArray(arr)) continue;
    arr.forEach((grupo, indice) => {
      if (!ehObjeto(grupo) || !Array.isArray(grupo.hooks)) return;
      if (grupo.hooks.length > 1) {
        // T-03-133: trocar o grupo inteiro apagaria o outro hook, que é do usuário.
        const v2 = grupo.hooks.map((h) => lista.entradas.find((e) => citaCaminho(h?.command, e, ctx.home))).find(Boolean);
        if (v2) {
          throw new Falha(
            7,
            `settings.json: hooks.${evento}[${indice}] tem a entrada v2 ${v2.script} junto com outro(s) hook(s) no mesmo ` +
              'grupo; trocá-la pelo grupo do go-and-do apagaria hook que não é da v2 — separe-a num grupo só dela e rode ' +
              'de novo; nada foi escrito',
          );
        }
        return;
      }
      if (grupo.hooks.length !== 1) return;
      const hook = grupo.hooks[0];
      if (!ehObjeto(hook) || hook.type !== 'command') return;
      const entrada = lista.entradas.find(
        (e) => e.evento === evento && matcherIgual(e.matcher, grupo) && citaCaminho(hook.command, e, ctx.home),
      );
      if (entrada) achadas.push({ evento, indice, grupo, entrada });
    });
  }
  return achadas;
}

/** Diretórios de <cfg> varridos atrás de symlink para a pasta v2 (a própria <cfg> e os que a v2 usava). */
const VARRIDOS = Object.freeze(['', 'skills', 'agents', 'hooks']);

/** O symlink <abs> (texto `alvo`) resolve dentro da pasta v2 da lista? */
function apontaParaV2(abs, alvo, raizV2) {
  const resolvido = path.resolve(path.dirname(abs), alvo);
  const realV2 = realOuNull(raizV2);
  return dentro(resolvido, raizV2) || (realV2 !== null && dentro(realOuNull(resolvido) ?? resolvido, realV2));
}

function recusaForaDaLista(rel, alvo) {
  return new Falha(
    7,
    `conflito de destino: <cfg>/${rel} é symlink para a instalação v2 (${alvo}) que não está na lista fechada da v2 ` +
      '(instalador/v2-lista.json); o go-and-do não troca nem remove o que não conhece — nada foi escrito',
  );
}

/**
 * AC-27 (borda R8 adjacency, T-03-132): symlink em <cfg> ou em <cfg>/{skills,agents,hooks} que resolve dentro da pasta
 * v2 e não é item da lista (caminho e alvo) → Falha(7) nomeando-o. Só varre diretório real dentro de <cfg>.
 */
function recusarLinksForaDaLista(ctx, lista) {
  const itens = new Set(lista.atalhos.map((a) => a.caminho));
  for (const dirRel of VARRIDOS) {
    const dirAbs = dirRel ? path.join(ctx.cfg, dirRel) : ctx.cfg;
    const st = lstatOuNull(dirAbs);
    if (!st || !st.isDirectory()) continue;
    for (const nome of fs.readdirSync(dirAbs).sort(porBytes)) {
      const rel = dirRel ? `${dirRel}/${nome}` : nome;
      const abs = path.join(dirAbs, nome);
      const alvo = lerLinkOuNull(abs);
      if (alvo === null || !apontaParaV2(abs, alvo, lista.raiz)) continue;
      if (itens.has(rel) && atalhoPresente(ctx, lista, lista.atalhos.find((a) => a.caminho === rel))) continue;
      throw recusaForaDaLista(rel, alvo);
    }
  }
}

/** Para classificarDestino: symlink de <cfg>/<rel> que aponta para a pasta v2 fora da lista → a recusa nomeando-o. */
export function recusaV2ForaDaLista(ctx, rel) {
  if (!ctx?.home) return null;
  const lista = carregarListaV2(ctx.home, ctx.cfg);
  const abs = path.join(ctx.cfg, ...rel.split('/'));
  const alvo = lerLinkOuNull(abs);
  return alvo !== null && apontaParaV2(abs, alvo, lista.raiz) ? recusaForaDaLista(rel, alvo) : null;
}

export function detectarV2(ctx, settings) {
  const lista = carregarListaV2(ctx.home, ctx.cfg);
  recusarLinksForaDaLista(ctx, lista);
  const links = lista.atalhos.map((item) => atalhoPresente(ctx, lista, item)).filter(Boolean);
  return { links, entradas: settings ? detectarEntradas(ctx, lista, settings) : [] };
}

export function garantirReciboV2(plano) {
  if (!plano.recibo) return { links: [], hooks: [] };
  if (!ehObjeto(plano.recibo.v2)) plano.recibo.v2 = { links: [], hooks: [] };
  for (const campo of ['links', 'hooks']) if (!Array.isArray(plano.recibo.v2[campo])) plano.recibo.v2[campo] = [];
  return plano.recibo.v2;
}

export function planejarTrocaV2(ctx, plano) {
  const v2 = garantirReciboV2(plano);
  for (const link of detectarV2(ctx, null).links) {
    const trocado = plano.acoes.some((a) => a.tipo === 'link' && (a.raiz ?? 'cfg') === 'cfg' && a.caminho === link.caminho);
    if (!trocado) plano.acoes.push({ tipo: 'remover-link', raiz: 'cfg', caminho: link.caminho });
    if (v2.links.some((l) => l && l.caminho === link.caminho)) continue;
    v2.links.push({ caminho: link.caminho, alvo_anterior: link.alvo, acao: trocado ? 'trocado' : 'removido' });
  }
}

export function trocarEntradasV2(valor, entradas, desejados, scriptsDoGrupo) {
  if (entradas.length === 0) return { valor, itens: [] };
  const novo = structuredClone(valor);
  const itens = [];
  // Do maior índice para o menor em cada evento: uma entrada que só sai não desloca as que faltam trocar.
  const ordem = [...entradas].sort((a, b) => porBytes(a.evento, b.evento) || b.indice - a.indice);
  for (const { evento, indice, grupo, entrada } of ordem) {
    const arr = novo.hooks[evento];
    const par = desejados.find((d) => d.evento === evento && isDeepStrictEqual(scriptsDoGrupo(d.grupo), [entrada.script]));
    if (!par) {
      throw new Falha(
        5,
        `pacote sem o grupo de hook que substitui a entrada v2 hooks.${evento}[${indice}] (${entrada.script}); nada foi escrito`,
      );
    }
    if (arr.some((g, i) => i !== indice && isDeepStrictEqual(g, par.grupo))) {
      arr.splice(indice, 1);
      itens.push({ evento, indice, valor_anterior: structuredClone(grupo), valor_novo: null });
    } else {
      arr[indice] = structuredClone(par.grupo);
      itens.push({ evento, indice, valor_anterior: structuredClone(grupo), valor_novo: structuredClone(par.grupo) });
    }
  }
  itens.sort((a, b) => porBytes(a.evento, b.evento) || a.indice - b.indice);
  return { valor: novo, itens };
}

function lstatOuNull(abs) {
  try {
    return fs.lstatSync(abs);
  } catch (e) {
    if (e.code === 'ENOENT' || e.code === 'ENOTDIR') return null;
    throw e;
  }
}

/** Caminhos de recibo.v2.links (o uninstall não os remove como atalho do produto: devolve a v2 no lugar). */
export function caminhosV2(recibo) {
  const links = ehObjeto(recibo?.v2) && Array.isArray(recibo.v2.links) ? recibo.v2.links : [];
  return new Set(links.filter((l) => ehObjeto(l) && typeof l.caminho === 'string').map((l) => l.caminho));
}

/**
 * planejarDevolucaoV2(ctx, plano, recibo): para cada item de recibo.v2.links, uma ação link com o alvo anterior
 * (troca atômica por cima do atalho do produto, ou recriação do só-v2 removido). Já com o alvo anterior (install
 * interrompido antes da troca) → nada; mudado pelo usuário (nem o atalho do produto registrado, nem ausente) ou pai que
 * não é diretório confiável em <cfg> → aviso nomeando o caminho, nada escrito ali.
 */
export function planejarDevolucaoV2(ctx, plano, recibo) {
  const links = ehObjeto(recibo?.v2) && Array.isArray(recibo.v2.links) ? recibo.v2.links : [];
  if (links.length === 0) return;
  const doProduto = new Map(
    (Array.isArray(recibo.links) ? recibo.links : []).filter((l) => ehObjeto(l)).map((l) => [l.caminho, l.alvo]),
  );
  const raizV2 = ctx.home ? carregarListaV2(ctx.home, ctx.cfg).raiz : null;
  for (const item of [...links].reverse()) {
    if (!ehObjeto(item) || typeof item.caminho !== 'string' || typeof item.alvo_anterior !== 'string') continue;
    const abs = path.join(ctx.cfg, ...item.caminho.split('/'));
    const st = lstatOuNull(abs);
    const atual = st && st.isSymbolicLink() ? fs.readlinkSync(abs) : undefined;
    if (atual === item.alvo_anterior) continue;
    if (st && (atual === undefined || atual !== doProduto.get(item.caminho))) {
      plano.avisos.push(
        `${abs} ficou: foi mudado depois do install (não é o atalho do go-and-do); o atalho v2 para ${item.alvo_anterior} não foi devolvido`,
      );
      continue;
    }
    const pai = lstatOuNull(path.dirname(abs));
    if (!pai || !pai.isDirectory() || (raizV2 && !paiConfiavel(ctx, abs, raizV2))) {
      plano.avisos.push(`${abs} não foi devolvido: o diretório dele não existe mais em <cfg> como diretório`);
      continue;
    }
    plano.acoes.push({ tipo: 'link', raiz: 'cfg', caminho: item.caminho, alvo: item.alvo_anterior });
  }
}

/**
 * devolverEntradasV2(valor, itens) → valor novo (pura): cada item de recibo.v2.hooks volta ao que era. Primeiro as
 * trocas no lugar: o grupo do produto registrado (valor_novo, no índice registrado ou achado por igualdade profunda no
 * array do evento) vira de novo o valor_anterior. Depois, em ordem crescente de índice, a entrada cujo grupo do produto
 * sumiu (o usuário o tirou, ou valor_novo null) é reinserida no índice registrado, limitado ao tamanho do array. Item
 * cujo valor_anterior já está no array não muda nada. Roda antes de removerGrupos, que tiraria o grupo trocado do lugar.
 */
export function devolverEntradasV2(valor, itens) {
  const lista = (Array.isArray(itens) ? itens : []).filter(
    (h) => ehObjeto(h) && typeof h.evento === 'string' && Number.isInteger(h.indice) && h.indice >= 0 && ehObjeto(h.valor_anterior),
  );
  if (lista.length === 0 || !ehObjeto(valor)) return valor;
  const novo = structuredClone(valor);
  if (!ehObjeto(novo.hooks)) novo.hooks = {};
  const faltam = [];
  for (const item of lista) {
    const arr = Array.isArray(novo.hooks[item.evento]) ? novo.hooks[item.evento] : null;
    if (arr && arr.some((g) => isDeepStrictEqual(g, item.valor_anterior))) continue;
    let i = -1;
    if (arr && ehObjeto(item.valor_novo)) {
      i = item.indice < arr.length && isDeepStrictEqual(arr[item.indice], item.valor_novo)
        ? item.indice
        : arr.findIndex((g) => isDeepStrictEqual(g, item.valor_novo));
    }
    if (i >= 0) arr[i] = structuredClone(item.valor_anterior);
    else faltam.push(item);
  }
  faltam.sort((a, b) => a.indice - b.indice);
  for (const item of faltam) {
    if (novo.hooks[item.evento] === undefined) novo.hooks[item.evento] = [];
    const arr = novo.hooks[item.evento];
    if (!Array.isArray(arr)) continue;
    arr.splice(Math.min(item.indice, arr.length), 0, structuredClone(item.valor_anterior));
  }
  return novo;
}
