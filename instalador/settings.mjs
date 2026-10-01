// Mescla do settings.json (D-14): a unidade de posse é o grupo inteiro { matcher, hooks } de cada entrada do
// dist/hooks.json do pacote, com o marcador de raiz trocado por <cfg>/go-and-do/current. Posse por igualdade profunda
// (util.isDeepStrictEqual) com o hooks.json ou com o recibo — nunca por prefixo de nome; grupo do usuário nunca é
// editado, nem com o mesmo matcher; sem mudança de valor, o arquivo não é reescrito (Pitfall 8). Só importa node:* e
// módulos de instalador/ (vai no tarball; o marcador é copiado de montagem/lib/hooks-json.mjs, Pitfall 2).
//
// Contrato:
// - MARCADOR_RAIZ: o mesmo literal de montagem/lib/hooks-json.mjs (a igualdade é conferida em teste).
// - lerSettings(ctx) → { existe, caminho, alvoReal, valor }: caminho = <cfg>/settings.json; alvoReal = realpath
//   quando é symlink (null se não é; symlink para fora de <cfg> é permitido, AC-12 — regra separada do AC-28);
//   valor = objeto lido ({} quando ausente). Symlink quebrado, ilegível, JSON inválido, raiz que não é objeto ou hooks
//   presente que não é objeto → Falha(6) nomeando o arquivo, nunca o conteúdo — sempre no planejamento.
// - gruposDoPacote(hooksJson, raizGad, opcionaisPedidos) → [{ evento, grupo }] na ordem do bloco hooks do hooks.json,
//   seguidos dos grupos do bloco opcionais cujo script está em opcionaisPedidos; em todo texto, MARCADOR_RAIZ vira
//   raizGad.
// - scriptsDoGrupo(grupo) → nomes dos scripts citados (o último …/hooks/<arq> de cada comando); opcionaisAceitos
//   (hooksJson) → os scripts do bloco opcionais (o bloco é por evento; --opcional recebe o nome do script).
// - mesclar(valor, desejados, registrados) → valor novo (pura, não muda a entrada): registrado que deixou de ser
//   desejado é trocado no mesmo índice pelo desejado de mesmo evento e mesmo script, ou removido por igualdade
//   profunda se não há substituto (registrado já ausente é ignorado); depois acrescenta ao fim do array do evento cada
//   desejado sem igual profundo, criando o array e o objeto hooks se faltarem; nunca reordena nem edita grupo do
//   usuário. Evento que existe e não é lista → Falha(6).
// - removerGrupos(valor, registrados, criados) → valor novo (pura), o inverso usado pelo uninstall (03-08).
// - planejarSettings(ctx, plano): valida ctx.opcionais (desconhecido → Falha(2) nomeando os aceitos; os do recibo
//   anterior continuam pedidos), lê o hooks.json do pacote e o settings.json, mescla e acrescenta a ação settings só
//   se o valor final difere do lido (sem mudança, nem bytes nem mtime mudam). Backup
//   <cfg>/settings.json.gad-backup-<AAAAMMDDTHHMMSSZ> só na primeira escrita sobre um settings.json que existia antes
//   do install (D-13), nomeado em plano.fim. Recibo: hooks (grupos acrescentados ou já registrados), opcionais e
//   settings { antes: 'ausente'|'existente', backup, hooks_criado, eventos_criados } — os campos de settings de uma
//   instalação anterior prevalecem.
// - Plano 03-13 (D-15, exceção da D-14): antes da mescla, cada entrada v2 da lista fechada (detectarV2) é trocada no
//   mesmo índice pelo grupo do produto de mesmo evento e mesmo script (trocarEntradasV2); a entrada v2 de um script
//   opcional passa a contar como pedida. recibo.v2.hooks guarda { evento, indice, valor_anterior, valor_novo } (sem
//   repetir o que a instalação anterior já registrou) e o valor_novo acompanha o grupo que o substitui num update.
import fs from 'node:fs';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { Falha } from './plano.mjs';
import { detectarV2, garantirReciboV2, trocarEntradasV2 } from './v2.mjs';

export const MARCADOR_RAIZ = '{{GAD_RAIZ}}';
const REL_SETTINGS = 'settings.json';
const REL_CURRENT = 'go-and-do/current';

const ehObjeto = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

function lstatOuNull(abs) {
  try {
    return fs.lstatSync(abs);
  } catch (e) {
    if (e.code === 'ENOENT') return null;
    throw e;
  }
}

/** Recusa do settings.json: nomeia o arquivo e o motivo, nunca o conteúdo (T-03-045). */
function invalido(caminho, motivo) {
  return new Falha(6, `settings.json inválido: ${caminho} ${motivo}; corrija o arquivo e rode de novo — nada foi escrito`);
}

export function lerSettings(ctx) {
  const caminho = path.join(ctx.cfg, REL_SETTINGS);
  const st = lstatOuNull(caminho);
  if (!st) return { existe: false, caminho, alvoReal: null, valor: {} };
  let alvoReal = null;
  if (st.isSymbolicLink()) {
    try {
      alvoReal = fs.realpathSync(caminho);
    } catch (e) {
      throw invalido(caminho, `é symlink quebrado (${e.code || 'erro'})`);
    }
  }
  const real = alvoReal ?? caminho;
  let texto;
  try {
    if (!fs.statSync(real).isFile()) throw invalido(caminho, 'não é arquivo regular');
    texto = fs.readFileSync(real, 'utf8');
  } catch (e) {
    if (e instanceof Falha) throw e;
    throw invalido(caminho, `está ilegível (${e.code || 'erro'})`);
  }
  let valor;
  try {
    valor = JSON.parse(texto);
  } catch {
    // A mensagem do JSON.parse cita um trecho do arquivo; só a posição do problema não é necessária aqui.
    throw invalido(caminho, 'não é JSON válido');
  }
  if (!ehObjeto(valor)) throw invalido(caminho, 'não tem um objeto JSON na raiz');
  if (Object.hasOwn(valor, 'hooks') && !ehObjeto(valor.hooks)) throw invalido(caminho, 'tem "hooks" que não é objeto');
  return { existe: true, caminho, alvoReal, valor };
}

function trocarMarcador(valor, raiz) {
  if (typeof valor === 'string') return valor.split(MARCADOR_RAIZ).join(raiz);
  if (Array.isArray(valor)) return valor.map((v) => trocarMarcador(v, raiz));
  if (ehObjeto(valor)) return Object.fromEntries(Object.entries(valor).map(([k, v]) => [k, trocarMarcador(v, raiz)]));
  return valor;
}

/** Scripts citados por um grupo: o último "…/hooks/<arq>" de cada comando (forma A cita o runner antes do .js). */
export function scriptsDoGrupo(grupo) {
  const scripts = [];
  for (const hk of Array.isArray(grupo?.hooks) ? grupo.hooks : []) {
    const achados = [...String(hk?.command ?? '').matchAll(/\/hooks\/([A-Za-z0-9][A-Za-z0-9._-]*)"/g)];
    if (achados.length) scripts.push(achados.at(-1)[1]);
  }
  return scripts;
}

export function gruposDoPacote(hooksJson, raizGad, opcionaisPedidos = []) {
  const grupos = [];
  for (const [evento, lista] of Object.entries(hooksJson.hooks ?? {})) {
    for (const grupo of lista) grupos.push({ evento, grupo: trocarMarcador(grupo, raizGad) });
  }
  const pedidos = new Set(opcionaisPedidos);
  for (const [evento, lista] of Object.entries(hooksJson.opcionais ?? {})) {
    for (const grupo of lista) {
      if (scriptsDoGrupo(grupo).some((s) => pedidos.has(s))) grupos.push({ evento, grupo: trocarMarcador(grupo, raizGad) });
    }
  }
  return grupos;
}

const igual = (a, b) => isDeepStrictEqual(a, b);
const temIgual = (arr, grupo) => arr.some((g) => igual(g, grupo));

export function mesclar(valor, desejados, registrados = []) {
  const novo = structuredClone(valor);
  const ehDesejado = (evento, grupo) => desejados.some((d) => d.evento === evento && igual(d.grupo, grupo));
  // 1. Registrado que deixou de ser desejado: troca no mesmo índice pelo desejado de mesmo evento e mesmo script
  //    (update entre versões do hooks.json); sem substituto, sai por igualdade profunda; já ausente, é ignorado.
  for (const reg of registrados) {
    if (!reg || typeof reg.evento !== 'string' || ehDesejado(reg.evento, reg.grupo)) continue;
    const arr = ehObjeto(novo.hooks) && Array.isArray(novo.hooks[reg.evento]) ? novo.hooks[reg.evento] : null;
    const i = arr ? arr.findIndex((g) => igual(g, reg.grupo)) : -1;
    if (i < 0) continue;
    const scripts = scriptsDoGrupo(reg.grupo);
    const substituto = desejados.find(
      (d) => d.evento === reg.evento && scripts.length > 0 && igual(scriptsDoGrupo(d.grupo), scripts) && !temIgual(arr, d.grupo),
    );
    if (substituto) arr[i] = structuredClone(substituto.grupo);
    else arr.splice(i, 1);
  }
  // 2. Desejado sem igual profundo no array do evento: vai para o fim; array e objeto hooks nascem se faltarem.
  for (const { evento, grupo } of desejados) {
    if (!ehObjeto(novo.hooks)) novo.hooks = {};
    if (novo.hooks[evento] === undefined) novo.hooks[evento] = [];
    const arr = novo.hooks[evento];
    if (!Array.isArray(arr)) throw new Falha(6, `settings.json: hooks.${evento} não é lista; nada foi escrito`);
    if (!temIgual(arr, grupo)) arr.push(structuredClone(grupo));
  }
  return novo;
}

/**
 * removerGrupos(valor, registrados, criados) → valor novo (pura): tira uma ocorrência de cada grupo registrado (igualdade
 * profunda; ausente é ignorado), depois os arrays de criados.eventos_criados que ficaram vazios e, se
 * criados.hooks_criado, o objeto hooks que ficou vazio. Array de evento do usuário que fica vazio continua ([]).
 */
export function removerGrupos(valor, registrados, criados = {}) {
  const novo = structuredClone(valor);
  if (!ehObjeto(novo.hooks)) return novo;
  for (const reg of registrados ?? []) {
    const arr = reg && Array.isArray(novo.hooks[reg.evento]) ? novo.hooks[reg.evento] : null;
    const i = arr ? arr.findIndex((g) => igual(g, reg.grupo)) : -1;
    if (i >= 0) arr.splice(i, 1);
  }
  for (const evento of criados?.eventos_criados ?? []) {
    if (Array.isArray(novo.hooks[evento]) && novo.hooks[evento].length === 0) delete novo.hooks[evento];
  }
  if (criados?.hooks_criado === true && Object.keys(novo.hooks).length === 0) delete novo.hooks;
  return novo;
}

/** Scripts aceitos por --opcional: os citados pelos grupos do bloco opcionais do hooks.json, na ordem do arquivo. */
export function opcionaisAceitos(hooksJson) {
  const aceitos = [];
  for (const lista of Object.values(hooksJson.opcionais ?? {})) {
    for (const grupo of lista) for (const s of scriptsDoGrupo(grupo)) if (!aceitos.includes(s)) aceitos.push(s);
  }
  return aceitos;
}

/** Instante do backup no formato AAAAMMDDTHHMMSSZ (UTC). */
function instante(data = new Date()) {
  return data.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
}

function nomeDoBackup(cfg) {
  const base = `${REL_SETTINGS}.gad-backup-${instante()}`;
  let nome = base;
  for (let n = 2; lstatOuNull(path.join(cfg, nome)); n++) nome = `${base}-${n}`;
  return nome;
}

function lerHooksJson(pacote) {
  const abs = path.join(pacote.origem, 'hooks.json');
  let h;
  try {
    h = JSON.parse(fs.readFileSync(abs, 'utf8'));
  } catch (e) {
    throw new Falha(5, `pacote sem dist/hooks.json legível (${e.code || e.message}); nada foi escrito`);
  }
  if (!ehObjeto(h) || !ehObjeto(h.hooks)) throw new Falha(5, 'dist/hooks.json sem o objeto hooks; nada foi escrito');
  return h;
}

/** --opcional validado contra os scripts do bloco opcionais; os pedidos numa instalação anterior continuam pedidos. */
function opcionaisDoPlano(hooksJson, pedidos, reciboAnterior) {
  const aceitos = opcionaisAceitos(hooksJson);
  for (const p of pedidos) {
    if (!aceitos.includes(p)) {
      throw new Falha(2, `uso inválido — --opcional ${p} desconhecido; aceitos: ${aceitos.join(', ') || '(nenhum)'}`);
    }
  }
  const anteriores = Array.isArray(reciboAnterior?.opcionais) ? reciboAnterior.opcionais.filter((o) => aceitos.includes(o)) : [];
  return [...new Set([...anteriores, ...pedidos])];
}

/** Opcionais que as entradas v2 usavam: contam como pedidos (D-15); o pacote tem de aceitá-los. */
function opcionaisDaV2(hooksJson, entradasV2) {
  const aceitos = opcionaisAceitos(hooksJson);
  const scripts = entradasV2.filter((e) => e.entrada.destino === 'opcional').map((e) => e.entrada.script);
  for (const s of scripts) {
    if (!aceitos.includes(s)) throw new Falha(5, `pacote sem o opcional ${s}, que substitui uma entrada v2; nada foi escrito`);
  }
  return scripts;
}

/** recibo.v2.hooks: acrescenta os itens novos e acompanha o valor_novo que um update trocou pelo grupo de mesmo script. */
function registrarHooksV2(plano, itens, desejados) {
  const v2 = garantirReciboV2(plano);
  for (const item of itens) {
    const jaTem = v2.hooks.some(
      (h) => h && h.evento === item.evento && h.indice === item.indice && isDeepStrictEqual(h.valor_anterior, item.valor_anterior),
    );
    if (!jaTem) v2.hooks.push(item);
  }
  for (const h of v2.hooks) {
    if (!h || !ehObjeto(h.valor_novo) || desejados.some((d) => d.evento === h.evento && isDeepStrictEqual(d.grupo, h.valor_novo))) continue;
    const scripts = scriptsDoGrupo(h.valor_novo);
    const atual = desejados.find((d) => d.evento === h.evento && scripts.length > 0 && isDeepStrictEqual(scriptsDoGrupo(d.grupo), scripts));
    if (atual) h.valor_novo = structuredClone(atual.grupo);
  }
}

export function planejarSettings(ctx, plano) {
  const hooksJson = lerHooksJson(ctx.pacote);
  const lido = lerSettings(ctx);
  // Plano 03-13 (D-15): entradas v2 da lista fechada presentes no settings.json lido.
  const entradasV2 = ctx.home ? detectarV2(ctx, lido.valor).entradas : [];
  const opcionais = [
    ...new Set([...opcionaisDoPlano(hooksJson, ctx.opcionais ?? [], ctx.reciboAnterior), ...opcionaisDaV2(hooksJson, entradasV2)]),
  ];
  const raizGad = path.join(ctx.cfg, ...REL_CURRENT.split('/'));
  const desejados = gruposDoPacote(hooksJson, raizGad, opcionais);
  for (const { evento } of desejados) {
    const v = lido.valor.hooks?.[evento];
    if (v !== undefined && !Array.isArray(v)) throw invalido(lido.caminho, `tem hooks.${evento} que não é lista`);
  }
  const anteriores = plano.recibo?.settings && ehObjeto(plano.recibo.settings) ? plano.recibo.settings : null;
  const registrados = Array.isArray(ctx.reciboAnterior?.hooks) ? ctx.reciboAnterior.hooks : [];
  const trocaV2 = trocarEntradasV2(lido.valor, entradasV2, desejados, scriptsDoGrupo);
  const novo = mesclar(trocaV2.valor, desejados, registrados);
  const muda = lido.existe ? !isDeepStrictEqual(novo, lido.valor) : Object.keys(novo).length > 0;
  // D-13: backup só na primeira escrita sobre um settings.json que já era do usuário antes do install.
  const antes = anteriores?.antes ?? (lido.existe ? 'existente' : 'ausente');
  const backup = lido.existe && muda && !anteriores?.backup && antes === 'existente' ? nomeDoBackup(ctx.cfg) : null;

  const hooksAntes = ehObjeto(lido.valor.hooks) ? lido.valor.hooks : null;
  const presenteAntes = ({ evento, grupo }) =>
    Array.isArray(hooksAntes?.[evento]) && hooksAntes[evento].some((g) => isDeepStrictEqual(g, grupo));
  const eraRegistrado = ({ evento, grupo }) =>
    registrados.some((r) => r && r.evento === evento && isDeepStrictEqual(r.grupo, grupo));
  const eventosCriados = Object.keys(novo.hooks ?? {}).filter((ev) => !Array.isArray(hooksAntes?.[ev]));

  if (plano.recibo) {
    registrarHooksV2(plano, trocaV2.itens, desejados);
    plano.recibo.hooks = desejados.filter((d) => eraRegistrado(d) || !presenteAntes(d));
    plano.recibo.opcionais = opcionais;
    plano.recibo.settings = {
      antes,
      backup: anteriores?.backup ?? backup,
      hooks_criado: anteriores?.hooks_criado === true || (hooksAntes === null && ehObjeto(novo.hooks)),
      eventos_criados: [...new Set([...(anteriores?.eventos_criados ?? []), ...eventosCriados])],
    };
  }
  if (!muda) return;
  const acao = { tipo: 'settings', raiz: 'cfg', caminho: REL_SETTINGS, valor: novo };
  if (backup) {
    acao.backup = backup;
    plano.fim.push(`Backup do settings.json anterior: ${path.join(ctx.cfg, backup)}`);
  }
  plano.acoes.push(acao);
}
