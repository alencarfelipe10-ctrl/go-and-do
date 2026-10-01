// Subcomando install (D-10, D-12): planeja tudo lendo, depois executa pelo executor único de plano.mjs.
// O pacote é o dist/ ao lado deste arquivo (raizDoPacote por import.meta.url; sem variável de ambiente que troque o
// dist/ — RESEARCH Pitfall 18). Só importa node:* e módulos de instalador/ (vai no tarball, Pitfall 2).
//
// Contrato:
// - raizDoPacote() → raiz do pacote (pasta que contém bin/, instalador/ e dist/).
// - lerPacote(raiz) → { manifesto, bytes, hash, origem } de <raiz>/dist/manifest.json; ausente, JSON inválido, sem
//   `arquivos` ou entrada fora do formato → Falha(5), antes de qualquer escrita. hash = sha256 hex (64) dos bytes.
// - planejarRuntime(ctx, plano): diretórios que faltam (<cfg>, go-and-do, go-and-do/runtime) e a ação runtime com o
//   temporário go-and-do/runtime/.tmp-<pid>-<8 hex> escolhido aqui. Se runtime/<hash> já existe (D-12): reusa (nenhuma
//   ação) quando conferirManifesto dele é vazio e o sha256 do manifest.json dele é o <hash>; senão Falha(5) nomeando a
//   primeira divergência em ordem de bytes — runtime sem escrita nunca é regravado por cima. Antes de tudo (03-17,
//   CR-01, D-12), checarDiretoriosDoRuntime (plano.mjs) recusa com Falha(7) <cfg>/go-and-do ou <cfg>/go-and-do/runtime
//   symlink, para dentro ou para fora de <cfg>; vale também para o update, que importa esta função. E (CR-01 da
//   rodada 4) runtime/<hash> que é symlink, para dentro ou para fora de <cfg>, sai Falha(7) antes de conferir — nunca
//   é reusado através do link, porque o verify reprova esse estado.
// - planejarPonteiros(ctx, plano): link go-and-do/current → runtime/<hash> e link gad-core → go-and-do/current/gad-core;
//   link já existente com o alvo esperado → nenhuma ação.
// - planejarInstall(opcoes) → plano: resolverCasa (PS-04) e checarPrereqs (R2) antes de ler o pacote; os avisos de
//   consultoria vão para plano.avisos e saem antes da linha de reiniciar; executarSubcomando(opcoes) imprime o plano e para no --dry-run, ou executa e
//   termina com AVISO_REINICIAR (AC-07). Depois do runtime e dos ponteiros (plano 03-04): planejarAtalhos e
//   planejarRecibosDoMotor (destinos.mjs) e planejarSettings (settings.mjs), nessa ordem; recibo.v2 começa vazio.
//   Antes de planejar: checarAncestrais (Falha 7) e o recibo anterior — incompleto → Falha(8) mandando rodar
//   `go-and-do uninstall`; completo de outro runtime → Falha(8) mandando usar `go-and-do update`. Os ponteiros passam
//   por classificarDestino (pasta, arquivo ou symlink alheio → Falha 7).
// - Plano 03-10 (R11, D-19): no fim de planejarInstall, planejarCopiaGsd (copiar-gsd.mjs) põe em plano.copiaGsd o
//   plano sem recibo da cópia ~/.gsd → ~/.gad quando há consentimento (opcoes.consentimentoGsd, decidido antes do
//   planejamento por obterConsentimento; na falta dele, opcoes.copiarGsd). executarSubcomando executa esse plano depois
//   do plano do install (nada de ~/.gad entra no recibo) e o --dry-run imprime as ações dele junto.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Falha, checarDiretoriosDoRuntime, executar, imprimirPlano, lerRecibo, novoPlano } from './plano.mjs';
import { NOME_MANIFESTO, conferirManifesto, sha256Hex, validarCaminhoRelativo } from './lib/arvore.mjs';
import { resolverCasa } from './casa.mjs';
import { checarPrereqs } from './prereqs.mjs';
import { checarAncestrais, classificarDestino, planejarAtalhos, planejarRecibosDoMotor } from './destinos.mjs';
import { planejarSettings } from './settings.mjs';
import { obterConsentimento, planejarCopiaGsd } from './copiar-gsd.mjs';

export const AVISO_REINICIAR =
  'Reinicie a sessão do Claude Code para que as skills, os agentes e os hooks do go-and-do passem a valer.';

const RE_SHA256 = /^[0-9a-f]{64}$/;
const ehObjeto = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const porBytes = (a, b) => Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8'));

export function raizDoPacote() {
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
}

function caminhoValido(rel) {
  try {
    validarCaminhoRelativo(rel);
    return true;
  } catch {
    return false;
  }
}

export function lerPacote(raiz) {
  const origem = path.join(raiz, 'dist');
  const abs = path.join(origem, NOME_MANIFESTO);
  let bytes;
  try {
    bytes = fs.readFileSync(abs);
  } catch (e) {
    throw new Falha(5, `pacote sem dist/manifest.json legível (${e.code || e.message})`);
  }
  let manifesto;
  try {
    manifesto = JSON.parse(bytes.toString('utf8'));
  } catch (e) {
    throw new Falha(5, `dist/manifest.json não é JSON válido (${e.message})`);
  }
  if (!ehObjeto(manifesto) || !ehObjeto(manifesto.arquivos)) throw new Falha(5, 'dist/manifest.json sem o objeto arquivos');
  for (const [rel, e] of Object.entries(manifesto.arquivos)) {
    if (!caminhoValido(rel) || rel === NOME_MANIFESTO) throw new Falha(5, `dist/manifest.json com caminho inválido: ${rel}`);
    if (!ehObjeto(e) || e.tipo !== 'arquivo' || (e.modo !== '755' && e.modo !== '644') || !RE_SHA256.test(e.sha256 ?? '')) {
      throw new Falha(5, `dist/manifest.json com entrada fora do formato (tipo arquivo, modo 755|644, sha256): ${rel}`);
    }
  }
  return { manifesto, bytes, hash: sha256Hex(bytes), origem };
}

const existe = (abs) => {
  try {
    fs.lstatSync(abs);
    return true;
  } catch {
    return false;
  }
};

/** Runtime já presente com o mesmo hash: reusa se confere, recusa nomeando a divergência se não (D-12). */
function conferirRuntimeExistente(runtimeAbs, relRuntime, pacote) {
  let divergencias;
  try {
    divergencias = conferirManifesto(runtimeAbs, pacote.manifesto);
  } catch (e) {
    throw new Falha(5, `${relRuntime} existente não pôde ser conferido (${e.message}); nada foi regravado`);
  }
  if (divergencias.length > 0) {
    const ordenadas = [...divergencias].sort((a, b) => porBytes(a.caminho, b.caminho));
    const d = ordenadas[0];
    throw new Falha(
      5,
      `${relRuntime} existente diverge do manifesto do pacote em ${d.caminho} (${d.campo}: esperado ${d.esperado}, ` +
        `achado ${d.achado})${ordenadas.length > 1 ? ` e em mais ${ordenadas.length - 1} caminho(s)` : ''}; ` +
        'runtime sem escrita não é regravado por cima — nada foi escrito',
    );
  }
  let bytes;
  try {
    bytes = fs.readFileSync(path.join(runtimeAbs, NOME_MANIFESTO));
  } catch (e) {
    throw new Falha(5, `${relRuntime}/${NOME_MANIFESTO} ilegível ou ausente (${e.code || e.message}); nada foi escrito`);
  }
  if (sha256Hex(bytes) !== pacote.hash) {
    throw new Falha(5, `${relRuntime}/${NOME_MANIFESTO} tem sha256 diferente do nome do runtime; nada foi escrito`);
  }
}

export function planejarRuntime(ctx, plano) {
  checarDiretoriosDoRuntime(plano, 'runtime');
  const { cfg, home, pacote } = ctx;
  if (!existe(cfg)) {
    const rel = path.relative(home, cfg).split(path.sep).join('/');
    plano.acoes.push({ tipo: 'diretorio', raiz: 'home', caminho: rel });
  }
  for (const rel of ['go-and-do', 'go-and-do/runtime']) {
    if (!existe(path.join(cfg, ...rel.split('/')))) plano.acoes.push({ tipo: 'diretorio', raiz: 'cfg', caminho: rel });
  }
  const relRuntime = `go-and-do/runtime/${pacote.hash}`;
  const runtimeAbs = path.join(cfg, ...relRuntime.split('/'));
  let st;
  try {
    st = fs.lstatSync(runtimeAbs);
  } catch (e) {
    if (e.code !== 'ENOENT') throw e;
    st = null;
  }
  if (st) {
    // CR-01 (rodada 4, D-12/D-10): runtime/<hash> symlink (para dentro ou para fora de <cfg>) é o estado que o verify
    // reprova (tipo: esperado diretório, achado symlink). conferirManifesto seguiria o link, então a recusa vem antes
    // de conferir — com o mesmo código 7 da régua do 03-17 para go-and-do e go-and-do/runtime.
    if (st.isSymbolicLink()) {
      throw new Falha(7, `runtime: <cfg>/${relRuntime} é symlink; o runtime não é reusado através dele — nada foi escrito`);
    }
    conferirRuntimeExistente(runtimeAbs, relRuntime, pacote);
    return;
  }
  const temporario = `go-and-do/runtime/.tmp-${process.pid}-${crypto.randomBytes(4).toString('hex')}`;
  plano.acoes.push({
    tipo: 'runtime',
    raiz: 'cfg',
    caminho: relRuntime,
    temporario,
    origem: pacote.origem,
    manifesto: pacote.manifesto,
    bytes: pacote.bytes,
    hash: pacote.hash,
  });
}

function linkJaCerto(abs, alvo) {
  try {
    return fs.lstatSync(abs).isSymbolicLink() && fs.readlinkSync(abs) === alvo;
  } catch {
    return false;
  }
}

export function planejarPonteiros(ctx, plano) {
  const { cfg, pacote } = ctx;
  const ponteiros = [
    { caminho: 'go-and-do/current', alvo: `runtime/${pacote.hash}` },
    { caminho: 'gad-core', alvo: 'go-and-do/current/gad-core' },
  ];
  for (const { caminho, alvo } of ponteiros) {
    if (linkJaCerto(path.join(cfg, ...caminho.split('/')), alvo)) continue;
    // Plano 03-04 (AC-28): pasta, arquivo ou symlink alheio no caminho do ponteiro é recusado antes de escrever.
    if (classificarDestino(ctx, caminho, alvo) !== 'criar') continue;
    plano.acoes.push({ tipo: 'link', raiz: 'cfg', caminho, alvo });
  }
}

/** Recibo anterior: incompleto → uninstall; completo de outro runtime → update (o install não faz o trabalho do update). */
function checarReciboAnterior(cfg, recibo, pacote) {
  if (!recibo) return;
  if (recibo.completo !== true) {
    throw new Falha(
      8,
      `instalação anterior incompleta em ${cfg} (recibo com completo: false); rode go-and-do uninstall --config-dir ` +
        `${cfg} e instale de novo — nada foi escrito`,
    );
  }
  if (recibo.runtime !== pacote.hash) {
    throw new Falha(
      8,
      `já há outro runtime do go-and-do instalado em ${cfg} (${recibo.runtime ?? 'sem runtime no recibo'}); use ` +
        `go-and-do update para trocar pelo runtime ${pacote.hash} — nada foi escrito`,
    );
  }
}

export function planejarInstall(opcoes) {
  const env = opcoes.env ?? process.env;
  // Ordem do D-10: config-dir, pré-requisitos, pacote — todas antes da primeira escrita.
  const { home, cfg } = resolverCasa({ configDir: opcoes.configDir, env });
  const avisos = checarPrereqs(env);
  const pacote = lerPacote(raizDoPacote());
  // Plano 03-04 (AC-28, c3-01, D-13): diretório ancestral que sai de <cfg> e recibo incompleto ou de outro runtime
  // são recusados antes de planejar qualquer ação.
  checarAncestrais({ cfg });
  const reciboAnterior = lerRecibo(cfg);
  checarReciboAnterior(cfg, reciboAnterior, pacote);
  const ctx = {
    cfg,
    home,
    pacote,
    reciboAnterior,
    opcionais: opcoes.opcional ?? [],
    copiarGsd: opcoes.consentimentoGsd ?? opcoes.copiarGsd === true,
  };
  const plano = novoPlano({ subcomando: 'install', cfg, home, recibo: reciboAnterior });
  plano.avisos.push(...avisos);
  planejarRuntime(ctx, plano);
  planejarPonteiros(ctx, plano);
  // Plano 03-04 (D-12, D-13, D-14): atalhos pelo nome estável, recibos do motor em <cfg>/ e a mescla do settings.json.
  planejarAtalhos(ctx, plano);
  planejarRecibosDoMotor(ctx, plano);
  planejarSettings(ctx, plano);
  if (plano.recibo && !ehObjeto(plano.recibo.v2)) plano.recibo.v2 = { links: [], hooks: [] };
  plano.fim.push(`go-and-do instalado em ${cfg} (runtime ${pacote.hash}).`);
  // Plano 03-10 (R11, D-19): a cópia de ~/.gsd é decidida aqui, antes do executor; as recusas dela param o install
  // inteiro antes da primeira escrita.
  planejarCopiaGsd(ctx, plano);
  return plano;
}

export async function executarSubcomando(opcoes) {
  const escrever = (s) => process.stdout.write(s);
  const consentimentoGsd = await obterConsentimento({ flag: opcoes.copiarGsd === true, env: opcoes.env ?? process.env });
  const plano = planejarInstall({ ...opcoes, consentimentoGsd });
  const copia = plano.copiaGsd ?? null;
  if (opcoes.dryRun) {
    escrever(`Plano do install em ${plano.cfg} (--dry-run: nada foi escrito):\n`);
    imprimirPlano(plano, escrever);
    if (copia) {
      imprimirPlano(copia, escrever);
      for (const linha of copia.fim) escrever(`${linha}\n`);
    }
    for (const aviso of plano.avisos) escrever(`aviso: ${aviso}\n`);
    return;
  }
  executar(plano);
  if (copia) executar(copia);
  for (const linha of plano.fim) escrever(`${linha}\n`);
  if (copia) for (const linha of copia.fim) escrever(`${linha}\n`);
  for (const aviso of plano.avisos) escrever(`aviso: ${aviso}\n`);
  escrever(`${AVISO_REINICIAR}\n`);
}
