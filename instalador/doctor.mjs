// Subcomando doctor (INST-06, CONV-01, D-22, PS-03): relata a convivência com o GSD Core na mesma casa — se ele está
// presente, a versão dele e os vigias em dobro — e só lê: não monta plano, não chama o executor, não chama gad-tools
// nem programa nenhum. Só importa node:* e módulos de instalador/ (vai no tarball, RESEARCH Pitfall 2).
//
// Contrato:
// - diagnosticar(ctx) → { core: { presente, versao }, pares: [{ evento, gad, gsd }], avisos: [] }. ctx = { cfg,
//   hooksJson? } (sem hooksJson, lê o dist/hooks.json do pacote ao lado deste arquivo).
//   Core presente = <cfg>/gsd-core é diretório (segue symlink); versao = conteúdo aparado de <cfg>/gsd-core/VERSION,
//   ou null (ausente, ilegível ou vazio). Vigias = o último script …/hooks/<arq> de cada entrada do bloco hooks do
//   hooks.json (os 16; nunca o bloco opcionais), com o evento da entrada. Par = gad-<s> de um vigia e gsd-<s> citado
//   num comando do settings.json no MESMO evento (nome do script como token de caminho, embrulhado ou não); ordem por
//   evento e por gad (bytes). settings.json ausente → nenhum par; ilegível ou inválido → aviso e nenhum par;
//   hooks.json do pacote ilegível → aviso e nenhum par. Nunca lança por causa do que lê.
// - executarSubcomando(opcoes): resolverCasa (Falha(3) de casa inválida é erro de uso, igual aos outros subcomandos)
//   → diagnosticar → imprime o relatório; sai 0 sempre depois de resolver a casa.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolverCasa } from './casa.mjs';
import { lerSettings, scriptsDoGrupo } from './settings.mjs';

const ehObjeto = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const porBytes = (a, b) => Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8'));
// Nome de script gsd-* citado como token de caminho num comando (depois de /, espaço, aspas ou no começo).
const RE_SCRIPT_GSD = /(?:^|[/\s"'`])(gsd-[A-Za-z0-9._-]+\.(?:js|cjs|mjs|sh))(?=$|[\s"'`])/g;

function raizDoPacote() {
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
}

function lerCore(cfg) {
  const dir = path.join(cfg, 'gsd-core');
  let presente = false;
  try {
    presente = fs.statSync(dir).isDirectory();
  } catch {
    presente = false;
  }
  if (!presente) return { presente: false, versao: null };
  let versao = null;
  try {
    versao = fs.readFileSync(path.join(dir, 'VERSION'), 'utf8').trim() || null;
  } catch {
    versao = null;
  }
  return { presente: true, versao };
}

function lerHooksDoPacote() {
  const abs = path.join(raizDoPacote(), 'dist', 'hooks.json');
  const h = JSON.parse(fs.readFileSync(abs, 'utf8'));
  if (!ehObjeto(h) || !ehObjeto(h.hooks)) throw new Error(`${abs} sem o objeto hooks`);
  return h;
}

/** Vigias do gad por evento: evento → Set de scripts gad-* (bloco hooks do hooks.json). */
function vigiasPorEvento(hooksJson) {
  const mapa = new Map();
  for (const [evento, lista] of Object.entries(hooksJson.hooks ?? {})) {
    for (const grupo of Array.isArray(lista) ? lista : []) {
      for (const s of scriptsDoGrupo(grupo)) {
        if (!s.startsWith('gad-')) continue;
        if (!mapa.has(evento)) mapa.set(evento, new Set());
        mapa.get(evento).add(s);
      }
    }
  }
  return mapa;
}

/** Scripts gsd-* citados nos comandos do settings.json, por evento. */
function gsdPorEvento(valor) {
  const mapa = new Map();
  for (const [evento, lista] of Object.entries(ehObjeto(valor.hooks) ? valor.hooks : {})) {
    const achados = new Set();
    for (const grupo of Array.isArray(lista) ? lista : []) {
      for (const hk of Array.isArray(grupo?.hooks) ? grupo.hooks : []) {
        for (const m of String(hk?.command ?? '').matchAll(RE_SCRIPT_GSD)) achados.add(m[1]);
      }
    }
    if (achados.size) mapa.set(evento, achados);
  }
  return mapa;
}

export function diagnosticar(ctx) {
  const { cfg } = ctx;
  const avisos = [];
  const core = lerCore(cfg);
  let hooksJson = ctx.hooksJson;
  if (hooksJson === undefined) {
    try {
      hooksJson = lerHooksDoPacote();
    } catch (e) {
      avisos.push(`não foi possível ler o dist/hooks.json do pacote (${e.code || e.message}); os pares não foram conferidos`);
      return { core, pares: [], avisos };
    }
  }
  let valor = {};
  try {
    ({ valor } = lerSettings({ cfg }));
  } catch (e) {
    avisos.push(`não foi possível ler ${path.join(cfg, 'settings.json')} (${e.message}); os pares não foram conferidos`);
    return { core, pares: [], avisos };
  }
  const gsd = gsdPorEvento(valor);
  const pares = [];
  for (const [evento, scripts] of vigiasPorEvento(hooksJson)) {
    const doCore = gsd.get(evento);
    if (!doCore) continue;
    for (const gad of scripts) {
      const par = `gsd-${gad.slice('gad-'.length)}`;
      if (doCore.has(par)) pares.push({ evento, gad, gsd: par });
    }
  }
  pares.sort((a, b) => porBytes(a.evento, b.evento) || porBytes(a.gad, b.gad));
  return { core, pares, avisos };
}

export async function executarSubcomando(opcoes) {
  const escrever = (s) => process.stdout.write(s);
  const { cfg } = resolverCasa({ configDir: opcoes.configDir, env: opcoes.env ?? process.env });
  const { core, pares, avisos } = diagnosticar({ cfg });
  const dirCore = path.join(cfg, 'gsd-core');
  if (core.presente) escrever(`Core presente em ${dirCore}, ${core.versao ? `versão ${core.versao}` : 'versão desconhecida'}.\n`);
  else escrever(`Core ausente: ${dirCore} não existe.\n`);
  for (const aviso of avisos) escrever(`aviso: ${aviso}\n`);
  if (pares.length === 0) {
    escrever('Nenhum vigia em dobro.\n');
    return;
  }
  escrever(`Vigias em dobro (o do gad e o do Core disparam juntos no mesmo evento): ${pares.length}\n`);
  for (const { evento, gad, gsd } of pares) escrever(`  ${evento}: ${gad} / ${gsd}\n`);
  escrever('O gad não edita as entradas gsd-* do Core; o risco de disparo em dobro é aceito e só relatado.\n');
}
