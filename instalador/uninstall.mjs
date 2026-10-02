// Subcomando uninstall (D-10, D-13, INST-04): lê o recibo, planeja as remoções só lendo e as aplica pelo executor
// único de plano.mjs. Remove só o que o recibo registra, e só enquanto continua sendo do gad: link com o alvo
// registrado, recibo do motor com o sha256 registrado, grupo de hook por igualdade profunda. O que o usuário mudou
// fica e vira aviso nomeando o caminho. Não checa pré-requisitos (c4-01): desinstalar não depende de claude, python3,
// bash, git, gh nem jq. Só importa node:* e módulos de instalador/ (vai no tarball, RESEARCH Pitfall 2).
//
// Contrato:
// - validarRecibo(ctx, recibo): recibo ausente, campo de tipo errado ou qualquer caminho a remover fora de <cfg>
//   (absoluto, com . ou .., atravessando symlink intermediário; criados_home que não é o próprio <cfg>; runtime, runtime
//   anterior ou temporário fora de go-and-do/runtime/<um segmento>) → Falha(8) nomeando o caminho. Roda antes da primeira ação (c1-02, AC-14).
//   Recibo com completo: false é aceito (D-13): item registrado que não existe vira «nada a fazer».
// - planejarUninstall(opcoes) → plano (novoPlano com semRecibo: o executor não regrava o recibo). Ordem das ações:
//   settings (removerGrupos sobre a união sem repetição de hooks e hooks_anteriores, sem backup novo; remover-arquivo quando o install o criou e ele ficou {}) → remover-link dos links do recibo, do último registrado ao primeiro
//   (atalhos, gad-core, go-and-do/current) → remover-arquivo dos recibos do motor → remover-runtime do runtime, do
//   runtime anterior (update interrompido) e do temporário registrados → remover-diretorio-vazio dos diretórios criados, do mais fundo ao mais raso, menos
//   go-and-do → remover-arquivo do próprio recibo → go-and-do (se foi criado) → diretórios criados em HOME.
// - executarSubcomando(opcoes): imprime o plano e para no --dry-run; senão executa e diz o que foi removido, o que
//   ficou por ter sido mudado pelo usuário, que o backup do settings.json ficou (com o caminho) e, se <HOME>/.gad
//   existe, que ~/.gad ficou como dado do usuário (D-19). O recibo é o último conteúdo registrado a sair; só os
//   diretórios go-and-do e <cfg>, que o contêm, são removidos depois dele (se foram criados e ficaram vazios).
// - Plano 03-13 (D-15, INST-04): o que o install trocou da v2 é devolvido, não removido. No settings.json,
//   devolverEntradasV2 (v2.mjs) recoloca cada entrada v2 no índice registrado antes de removerGrupos; os caminhos de
//   recibo.v2.links saem da remoção de links e planejarDevolucaoV2 os devolve ao alvo anterior (link). validarRecibo
//   valida o caminho de cada item de recibo.v2.links (o alvo anterior aponta para fora de <cfg> por definição).
import fs from 'node:fs';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { Falha, REL_RECIBO, executar, imprimirPlano, lerRecibo, novoPlano } from './plano.mjs';
import { sha256Hex, validarCaminhoRelativo } from './lib/arvore.mjs';
import { resolverCasa } from './casa.mjs';
import { limparOrfaos } from './orfaos.mjs';
import { lerSettings, removerGrupos } from './settings.mjs';
import { caminhosV2, devolverEntradasV2, planejarDevolucaoV2 } from './v2.mjs';

const REL_SETTINGS = 'settings.json';
const REL_DIR_PRODUTO = 'go-and-do';
const REL_RUNTIME = 'go-and-do/runtime';

const ehObjeto = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const porBytes = (a, b) => Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8'));
const profundidade = (rel) => rel.split('/').length;

function lstatOuNull(abs) {
  try {
    return fs.lstatSync(abs);
  } catch (e) {
    if (e.code === 'ENOENT' || e.code === 'ENOTDIR') return null;
    throw e;
  }
}

const absCfg = (cfg, rel) => path.join(cfg, ...rel.split('/'));

function planejarSettingsUninstall(ctx, plano, recibo) {
  // D-13 (03-15): união sem repetição de recibo.hooks e recibo.hooks_anteriores (grupos de A no recibo incompleto de
  // um update). removerGrupos tira uma ocorrência por item, por igualdade profunda: um item repetido na lista levaria
  // também a cópia que o usuário pôs (T-03-156).
  const hooks = [...(Array.isArray(recibo.hooks) ? recibo.hooks : [])];
  for (const item of Array.isArray(recibo.hooks_anteriores) ? recibo.hooks_anteriores : []) {
    if (!hooks.some((h) => isDeepStrictEqual(h, item))) hooks.push(item);
  }
  const criados = ehObjeto(recibo.settings) ? recibo.settings : {};
  const lido = lerSettings(ctx);
  if (!lido.existe) return;
  // Plano 03-13: as entradas v2 voltam ao lugar antes de removerGrupos (que tiraria o grupo trocado do índice dela).
  const itensV2 = ehObjeto(recibo.v2) && Array.isArray(recibo.v2.hooks) ? recibo.v2.hooks : [];
  const novo = removerGrupos(devolverEntradasV2(lido.valor, itensV2), hooks, criados);
  // AC-17: o settings.json que o install criou (antes: ausente) e que ficou vazio sai inteiro, em vez de virar {}.
  // Symlink fica (é do usuário, AC-12); o que o usuário pôs nele fica e é gravado sozinho.
  if (criados.antes === 'ausente' && Object.keys(novo).length === 0 && !lido.alvoReal) {
    plano.acoes.push({ tipo: 'remover-arquivo', raiz: 'cfg', caminho: REL_SETTINGS });
    return;
  }
  if (isDeepStrictEqual(novo, lido.valor)) return;
  plano.acoes.push({ tipo: 'settings', raiz: 'cfg', caminho: REL_SETTINGS, valor: novo });
}

function planejarLinks(ctx, plano, recibo) {
  const links = Array.isArray(recibo.links) ? recibo.links : [];
  const v2 = caminhosV2(recibo);
  for (const { caminho, alvo } of [...links].reverse()) {
    if (v2.has(caminho)) continue;
    const abs = absCfg(ctx.cfg, caminho);
    const st = lstatOuNull(abs);
    if (!st) continue;
    if (st.isSymbolicLink() && fs.readlinkSync(abs) === alvo) {
      plano.acoes.push({ tipo: 'remover-link', raiz: 'cfg', caminho });
    } else {
      plano.avisos.push(`${abs} ficou: foi mudado depois do install (não é mais o symlink para ${alvo})`);
    }
  }
}

function planejarArquivos(ctx, plano, recibo) {
  const arquivos = Array.isArray(recibo.arquivos) ? recibo.arquivos : [];
  for (const { caminho, sha256 } of arquivos) {
    const abs = absCfg(ctx.cfg, caminho);
    const st = lstatOuNull(abs);
    if (!st) continue;
    if (st.isFile() && sha256Hex(fs.readFileSync(abs)) === sha256) {
      plano.acoes.push({ tipo: 'remover-arquivo', raiz: 'cfg', caminho });
    } else {
      plano.avisos.push(`${abs} ficou: foi mudado depois do install (conteúdo diferente do registrado)`);
    }
  }
}

function planejarRuntime(ctx, plano, recibo) {
  // Set: runtime_anterior igual a runtime não vira dois remover-runtime do mesmo caminho (T-03-154).
  const caminhos = new Set();
  if (typeof recibo.runtime === 'string') caminhos.add(`${REL_RUNTIME}/${recibo.runtime}`);
  // D-13 (03-15): o recibo incompleto de um update interrompido cita o runtime A em runtime_anterior.
  if (typeof recibo.runtime_anterior === 'string') caminhos.add(`${REL_RUNTIME}/${recibo.runtime_anterior}`);
  if (typeof recibo.runtime_temporario === 'string') caminhos.add(recibo.runtime_temporario);
  for (const caminho of caminhos) {
    if (lstatOuNull(absCfg(ctx.cfg, caminho))) plano.acoes.push({ tipo: 'remover-runtime', raiz: 'cfg', caminho });
  }
}

function recusaRecibo(detalhe) {
  return new Falha(8, `recibo inválido: ${detalhe}; o uninstall só remove caminhos relativos a <cfg> — nada foi removido`);
}

function listaOuVazia(recibo, campo) {
  const v = recibo[campo];
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v)) throw recusaRecibo(`o campo ${campo} não é lista`);
  return v;
}

function caminhoDe(campo, item) {
  if (!ehObjeto(item) || typeof item.caminho !== 'string') throw recusaRecibo(`item de ${campo} sem caminho em texto`);
  return item.caminho;
}

/** Caminho de runtime do recibo: go-and-do/runtime/<um segmento>; outra forma → recusa. */
function caminhoDeRuntime(campo, rel) {
  if (!rel.startsWith(`${REL_RUNTIME}/`) || rel.slice(REL_RUNTIME.length + 1).includes('/')) {
    throw recusaRecibo(`${campo} fora de <cfg>/${REL_RUNTIME}/ (${rel})`);
  }
  return rel;
}

/** Recusa (Falha 8) se algum diretório intermediário de <raiz>/<rel> é symlink; para no primeiro ausente. */
function checarIntermediarios(raizAbs, rel) {
  const segs = rel.split('/');
  let atual = raizAbs;
  for (const seg of segs.slice(0, -1)) {
    atual = path.join(atual, seg);
    const st = lstatOuNull(atual);
    if (!st || !st.isDirectory()) {
      if (st && st.isSymbolicLink()) {
        throw recusaRecibo(`${rel} atravessa o symlink ${atual} (o diretório foi trocado por symlink depois do install)`);
      }
      return;
    }
  }
}

/**
 * validarRecibo(ctx, recibo): todo caminho que o uninstall vai remover ou escrever — links, arquivos, runtime,
 * runtime anterior, temporário, criados, criados_home, settings.json e o próprio recibo — passa por
 * validarCaminhoRelativo (recusa vazio, NUL, absoluto, barra invertida, . e ..) e por lstat segmento a segmento a partir
 * da raiz (symlink intermediário → recusa). criados_home só aceita o próprio <cfg> relativo a HOME; runtime, runtime
 * anterior (texto) e temporário só aceitam go-and-do/runtime/<um segmento>. links, arquivos, criados, criados_home,
 * hooks e hooks_anteriores presentes têm de ser listas. Recibo ausente → Falha(8). Tudo antes da primeira ação (c1-02,
 * AC-14).
 */
export function validarRecibo(ctx, recibo) {
  const { cfg, home } = ctx;
  if (!recibo) {
    throw new Falha(
      8,
      `sem recibo do go-and-do em ${absCfg(cfg, REL_RECIBO)}: nada a desinstalar (o uninstall só remove o que o recibo ` +
        'registra) — nada foi removido',
    );
  }
  if (!ehObjeto(recibo)) throw recusaRecibo('o recibo não é objeto');
  const aValidar = [];
  const naCfg = (rel) => aValidar.push({ raizAbs: cfg, rel });
  for (const item of listaOuVazia(recibo, 'links')) naCfg(caminhoDe('links', item));
  for (const item of listaOuVazia(recibo, 'arquivos')) naCfg(caminhoDe('arquivos', item));
  for (const rel of listaOuVazia(recibo, 'criados')) naCfg(rel);
  listaOuVazia(recibo, 'hooks');
  // D-13 (03-15): hooks_anteriores só existe no recibo incompleto de um update; presente e não lista → recusa.
  listaOuVazia(recibo, 'hooks_anteriores');
  if (recibo.v2 !== undefined && recibo.v2 !== null) {
    if (!ehObjeto(recibo.v2)) throw recusaRecibo('o campo v2 não é objeto');
    for (const item of listaOuVazia(recibo.v2, 'links')) naCfg(caminhoDe('v2.links', item));
    listaOuVazia(recibo.v2, 'hooks');
  }
  if (recibo.runtime !== undefined && recibo.runtime !== null) {
    if (typeof recibo.runtime !== 'string') throw recusaRecibo('o campo runtime não é texto');
    naCfg(caminhoDeRuntime('runtime', `${REL_RUNTIME}/${recibo.runtime}`));
  }
  // D-13, c1-02 (03-15): o runtime anterior de um update interrompido tem o mesmo confinamento do runtime.
  if (recibo.runtime_anterior !== undefined && recibo.runtime_anterior !== null) {
    if (typeof recibo.runtime_anterior !== 'string') throw recusaRecibo('o campo runtime_anterior não é texto');
    naCfg(caminhoDeRuntime('runtime_anterior', `${REL_RUNTIME}/${recibo.runtime_anterior}`));
  }
  if (recibo.runtime_temporario !== undefined && recibo.runtime_temporario !== null) {
    if (typeof recibo.runtime_temporario !== 'string') throw recusaRecibo('o campo runtime_temporario não é texto');
    naCfg(caminhoDeRuntime('runtime_temporario', recibo.runtime_temporario));
  }
  if (recibo.settings !== undefined && recibo.settings !== null && !ehObjeto(recibo.settings)) {
    throw recusaRecibo('o campo settings não é objeto');
  }
  naCfg(REL_SETTINGS);
  naCfg(REL_RECIBO);
  const relCfg = path.relative(home, cfg).split(path.sep).join('/');
  for (const rel of listaOuVazia(recibo, 'criados_home')) {
    if (rel !== relCfg) throw recusaRecibo(`criados_home cita ${JSON.stringify(rel)}, que não é o <cfg> (${relCfg})`);
    aValidar.push({ raizAbs: home, rel });
  }
  for (const { raizAbs, rel } of aValidar) {
    if (typeof rel !== 'string') throw recusaRecibo(`caminho que não é texto: ${JSON.stringify(rel)}`);
    try {
      validarCaminhoRelativo(rel);
    } catch (e) {
      throw recusaRecibo(`caminho a remover fora de <cfg>: ${rel} (${e.message})`);
    }
    checarIntermediarios(raizAbs, rel);
  }
}

function planejarDiretorio(plano, raizAbs, raiz, caminho) {
  const st = lstatOuNull(path.join(raizAbs, ...caminho.split('/')));
  if (st && st.isDirectory()) plano.acoes.push({ tipo: 'remover-diretorio-vazio', raiz, caminho });
}

export function planejarUninstall(opcoes) {
  const env = opcoes.env ?? process.env;
  const { home, cfg } = resolverCasa({ configDir: opcoes.configDir, env });
  const recibo = lerRecibo(cfg);
  const ctx = { cfg, home };
  // c1-02, AC-14: todo caminho do recibo é validado antes da primeira ação; recibo incompleto é aceito (D-13).
  validarRecibo(ctx, recibo);
  const plano = novoPlano({ subcomando: 'uninstall', cfg, home, semRecibo: true });
  planejarSettingsUninstall(ctx, plano, recibo);
  planejarLinks(ctx, plano, recibo);
  planejarDevolucaoV2(ctx, plano, recibo);
  planejarArquivos(ctx, plano, recibo);
  planejarRuntime(ctx, plano, recibo);
  const criados = (Array.isArray(recibo.criados) ? recibo.criados : []).filter((c) => c !== REL_DIR_PRODUTO);
  criados.sort((a, b) => profundidade(b) - profundidade(a) || porBytes(b, a));
  for (const caminho of criados) planejarDiretorio(plano, cfg, 'cfg', caminho);
  if (lstatOuNull(absCfg(cfg, REL_RECIBO))) plano.acoes.push({ tipo: 'remover-arquivo', raiz: 'cfg', caminho: REL_RECIBO });
  if (Array.isArray(recibo.criados) && recibo.criados.includes(REL_DIR_PRODUTO)) {
    planejarDiretorio(plano, cfg, 'cfg', REL_DIR_PRODUTO);
  }
  for (const caminho of Array.isArray(recibo.criados_home) ? recibo.criados_home : []) {
    planejarDiretorio(plano, home, 'home', caminho);
  }
  const backup = ehObjeto(recibo.settings) && typeof recibo.settings.backup === 'string' ? recibo.settings.backup : null;
  if (backup) plano.fim.push(`O backup do settings.json ficou: ${absCfg(cfg, backup)}`);
  // D-19: ~/.gad é dado do usuário — fora do recibo, nunca removido; a saída diz que ficou.
  const gad = path.join(home, '.gad');
  if (lstatOuNull(gad)) plano.fim.push(`~/.gad ficou (${gad}): é dado do usuário e o uninstall não o apaga.`);
  return plano;
}

export async function executarSubcomando(opcoes) {
  const escrever = (s) => process.stdout.write(s);
  const plano = planejarUninstall(opcoes);
  if (opcoes.dryRun) {
    escrever(`Plano do uninstall em ${plano.cfg} (--dry-run: nada foi removido):\n`);
    imprimirPlano(plano, escrever);
    for (const aviso of plano.avisos) escrever(`aviso: ${aviso}\n`);
    return;
  }
  // Todo 2026-09-30: temporários .tmp-<pid>-* de pid morto (SIGKILL entre o temporário e o rename) saem antes de
  // executar; o --dry-run já voltou acima e não remove nada.
  for (const orfao of limparOrfaos({ cfg: plano.cfg, home: plano.home })) escrever(`temporário órfão removido: ${orfao}\n`);
  executar(plano);
  escrever(`go-and-do desinstalado de ${plano.cfg} (${plano.acoes.length} ação(ões) aplicada(s)).\n`);
  for (const linha of plano.fim) escrever(`${linha}\n`);
  for (const aviso of plano.avisos) escrever(`aviso: ${aviso}\n`);
}
