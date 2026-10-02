// Subcomando update (D-10, D-11, D-12, D-13, D-14): atualizar é trocar o ponteiro. Planeja tudo lendo, no mesmo molde
// do install, e executa pelo executor único de plano.mjs. O pacote é o dist/ ao lado deste arquivo (raizDoPacote de
// install.mjs, por import.meta.url — Pitfall 18). Só importa node:* e módulos de instalador/ (vai no tarball, Pitfall 2).
// Compõe as exportações do install, de destinos.mjs e de settings.mjs sem mudar aqueles módulos.
//
// Contrato:
// - planejarUpdate(opcoes) → plano, na ordem: resolverCasa (Falha 3) → checarPrereqs (Falha 4, D-11) → lerPacote do
//   pacote que roda (Falha 5) → checarAncestrais (Falha 7, AC-28) → lerRecibo: ausente → Falha(8) mandando usar
//   `go-and-do install`; completo: false → Falha(8) mandando rodar `go-and-do uninstall`; runtime que não é 64 hex →
//   Falha(8) → runtime B (planejarRuntime: temporário irmão + rename, ou reuso se runtime/<hashB> já existe e confere)
//   → link go-and-do/current → runtime/<hashB> (trocarLink: symlink temporário + rename; current que não aponta para o
//   runtime registrado → Falha 7) → gad-core → planejarAtalhos → remover-link dos atalhos registrados que o pacote B
//   não pede mais → planejarRecibosDoMotor → planejarSettings (mesclar com os grupos do pacote B e os registrados no
//   recibo anterior: grupo superado é trocado no mesmo índice) → remover-runtime de go-and-do/runtime/<hashA> por
//   último. O recibo novo nasce do anterior (novoPlano: settings, opcionais, criados, criados_home e v2 passam adiante)
//   com runtime = <hashB>; enquanto incompleto, leva runtime_anterior = <hashA> quando o runtime troca e
//   hooks_anteriores = os grupos registrados de A (recibo.hooks anterior) quando os grupos planejados diferem deles
//   (D-13, 03-15: o uninstall de um update interrompido tira os dois); o update nunca cria backup do settings.json
//   (D-13). Mesmo hash → nenhuma ação de runtime nem de current; plano.nadaAFazer quando não há ação e o recibo
//   planejado é igual ao lido.
// - executarSubcomando(opcoes): --dry-run imprime o plano (imprimirPlano) e para; nadaAFazer → não escreve nada, nem o
//   recibo; senão executa, tira runtime_anterior e hooks_anteriores do recibo completo numa regravação só e termina com
//   AVISO_REINICIAR (AC-07).
import fs from 'node:fs';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { Falha, REL_RECIBO, executar, imprimirPlano, lerRecibo, novoPlano } from './plano.mjs';
import { escreverAtomico } from './lib/arvore.mjs';
import { resolverCasa } from './casa.mjs';
import { limparOrfaos } from './orfaos.mjs';
import { checarPrereqs } from './prereqs.mjs';
import { AVISO_REINICIAR, lerPacote, planejarRuntime, raizDoPacote } from './install.mjs';
import { checarAncestrais, classificarDestino, planejarAtalhos, planejarRecibosDoMotor } from './destinos.mjs';
import { planejarSettings } from './settings.mjs';

const REL_CURRENT = 'go-and-do/current';
const PREFIXO_RUNTIME = 'go-and-do/runtime/';
const RE_SHA256 = /^[0-9a-f]{64}$/;

function lerLink(abs) {
  try {
    const st = fs.lstatSync(abs);
    return st.isSymbolicLink() ? fs.readlinkSync(abs) : undefined;
  } catch (e) {
    if (e.code === 'ENOENT') return null;
    throw e;
  }
}

/**
 * current → runtime/<hashB>: já certo → nenhuma ação; ausente ou symlink para o runtime registrado no recibo anterior →
 * ação link (o executor troca por symlink temporário + rename, o ponteiro nunca fica ausente); qualquer outra coisa →
 * Falha(7) nomeando o caminho.
 */
function planejarCurrent(ctx, plano) {
  const { cfg, pacote, reciboAnterior } = ctx;
  const alvo = `runtime/${pacote.hash}`;
  const abs = path.join(cfg, ...REL_CURRENT.split('/'));
  const atual = lerLink(abs);
  if (atual === alvo) return;
  if (atual !== null && atual !== `runtime/${reciboAnterior.runtime}`) {
    throw new Falha(
      7,
      `conflito de destino: <cfg>/${REL_CURRENT} ${atual === undefined ? 'não é symlink' : `aponta para ${atual}`}, não ` +
        `para o runtime registrado no recibo (runtime/${reciboAnterior.runtime}); o go-and-do não sobrescreve o que não é ` +
        'dele — nada foi escrito',
    );
  }
  plano.acoes.push({ tipo: 'link', raiz: 'cfg', caminho: REL_CURRENT, alvo });
}

function planejarGadCore(ctx, plano) {
  const caminho = 'gad-core';
  const alvo = `${REL_CURRENT}/gad-core`;
  if (classificarDestino(ctx, caminho, alvo) === 'criar') plano.acoes.push({ tipo: 'link', raiz: 'cfg', caminho, alvo });
}

/** Recibo anterior: ausente → install; incompleto → uninstall; runtime que não é um hash de 64 hex → recusa (T-03-071). */
function checarReciboAnterior(cfg, recibo) {
  if (!recibo) {
    throw new Falha(
      8,
      `nenhuma instalação do go-and-do em ${cfg} (sem recibo); use go-and-do install --config-dir ${cfg} — nada foi escrito`,
    );
  }
  if (recibo.completo !== true) {
    throw new Falha(
      8,
      `instalação anterior incompleta em ${cfg} (recibo com completo: false); rode go-and-do uninstall --config-dir ` +
        `${cfg} e instale de novo — nada foi escrito`,
    );
  }
  if (typeof recibo.runtime !== 'string' || !RE_SHA256.test(recibo.runtime)) {
    throw new Falha(8, `recibo em ${cfg} sem runtime registrado válido (64 hex); nada foi escrito`);
  }
}

/** Nomes dos atalhos que o pacote pede (a mesma regra de destinos.mjs): skills/<nome>/… e agents/<arquivo>. */
function atalhosDoPacote(manifesto) {
  const atalhos = new Set();
  for (const rel of Object.keys(manifesto.arquivos)) {
    const s = rel.split('/');
    if (s[0] === 'skills' && s.length >= 3) atalhos.add(`skills/${s[1]}`);
    else if (s[0] === 'agents' && s.length === 2) atalhos.add(`agents/${s[1]}`);
  }
  return atalhos;
}

/**
 * Atalho registrado no recibo anterior que o pacote B não pede mais: symlink com o alvo registrado → remover-link;
 * já ausente → só sai do recibo; qualquer outra coisa (o usuário trocou) → Falha(7), nada é escrito.
 */
function planejarAtalhosQueSairam(ctx, plano) {
  const { cfg, pacote } = ctx;
  const pedidos = atalhosDoPacote(pacote.manifesto);
  const sairam = plano.recibo.links.filter(
    (l) => (l.caminho.startsWith('skills/') || l.caminho.startsWith('agents/')) && !pedidos.has(l.caminho),
  );
  for (const link of sairam) {
    const atual = lerLink(path.join(cfg, ...link.caminho.split('/')));
    if (atual === link.alvo) plano.acoes.push({ tipo: 'remover-link', raiz: 'cfg', caminho: link.caminho });
    else if (atual !== null) {
      throw new Falha(
        7,
        `conflito de destino: <cfg>/${link.caminho} não é mais o atalho registrado no recibo (${link.alvo}); o ` +
          'go-and-do não remove o que não é dele — nada foi escrito',
      );
    }
  }
  plano.recibo.links = plano.recibo.links.filter((l) => !sairam.includes(l));
}

/** D-13: o update nunca cria backup; o registrado na primeira instalação (ou a falta dele) passa adiante. */
function manterBackupAnterior(ctx, plano) {
  const anterior = ctx.reciboAnterior.settings?.backup ?? null;
  for (const acao of plano.acoes) {
    if (acao.tipo !== 'settings' || acao.backup === undefined) continue;
    const linha = `Backup do settings.json anterior: ${path.join(ctx.cfg, acao.backup)}`;
    plano.fim = plano.fim.filter((l) => l !== linha);
    delete acao.backup;
  }
  if (plano.recibo.settings && typeof plano.recibo.settings === 'object') plano.recibo.settings.backup = anterior;
}

export function planejarUpdate(opcoes) {
  const env = opcoes.env ?? process.env;
  // Ordem do D-10/D-11: config-dir, pré-requisitos, pacote e recusas — todas antes da primeira escrita.
  const { home, cfg } = resolverCasa({ configDir: opcoes.configDir, env });
  const avisos = checarPrereqs(env);
  const pacote = lerPacote(raizDoPacote());
  checarAncestrais({ cfg });
  const reciboAnterior = lerRecibo(cfg);
  checarReciboAnterior(cfg, reciboAnterior);
  const ctx = { cfg, home, pacote, reciboAnterior, opcionais: opcoes.opcional ?? [] };
  const plano = novoPlano({ subcomando: 'update', cfg, home, recibo: reciboAnterior });
  plano.avisos.push(...avisos);
  const hashA = reciboAnterior.runtime;
  const troca = hashA !== pacote.hash;
  // runtime vale B desde o primeiro registro (também quando runtime/<hashB> é reusado, sem ação runtime); o anterior
  // fica em runtime_anterior só enquanto o recibo está incompleto (T-03-073).
  plano.recibo.runtime = pacote.hash;
  if (troca) plano.recibo.runtime_anterior = hashA;
  else delete plano.recibo.runtime_anterior;
  planejarRuntime(ctx, plano);
  planejarCurrent(ctx, plano);
  planejarGadCore(ctx, plano);
  planejarAtalhos(ctx, plano);
  planejarAtalhosQueSairam(ctx, plano);
  planejarRecibosDoMotor(ctx, plano);
  planejarSettings(ctx, plano);
  manterBackupAnterior(ctx, plano);
  // D-13 (03-15): planejarSettings já regravou plano.recibo.hooks com os grupos de B. Enquanto o recibo está incompleto,
  // os grupos registrados de A ficam em hooks_anteriores, para o uninstall de um update interrompido tirá-los também.
  // O delete é obrigatório: novoPlano clona o recibo anterior, que pode trazer um campo velho.
  if (Array.isArray(reciboAnterior.hooks) && !isDeepStrictEqual(reciboAnterior.hooks, plano.recibo.hooks)) {
    plano.recibo.hooks_anteriores = structuredClone(reciboAnterior.hooks);
  } else delete plano.recibo.hooks_anteriores;
  // Depois da troca de current: só o runtime registrado, abaixo de go-and-do/runtime/ (o executor confere o prefixo e
  // devolve u+w só aos diretórios dele antes de remover — Pitfall 4).
  if (troca) plano.acoes.push({ tipo: 'remover-runtime', raiz: 'cfg', caminho: `${PREFIXO_RUNTIME}${hashA}` });
  plano.fim.push(`go-and-do atualizado em ${cfg} (runtime ${pacote.hash}).`);
  // Sem ação e com o recibo planejado igual ao lido: nada a escrever, nem o recibo (AC-09, Pitfall 8).
  plano.nadaAFazer = plano.acoes.length === 0 && isDeepStrictEqual({ ...plano.recibo, completo: true }, reciboAnterior);
  return plano;
}

export async function executarSubcomando(opcoes) {
  const escrever = (s) => process.stdout.write(s);
  const plano = planejarUpdate(opcoes);
  if (opcoes.dryRun) {
    // D-10/AC-08: o mesmo plano, impresso antes de qualquer executar.
    escrever(`Plano do update em ${plano.cfg} (--dry-run: nada foi escrito):\n`);
    imprimirPlano(plano, escrever);
    for (const aviso of plano.avisos) escrever(`aviso: ${aviso}\n`);
    return;
  }
  // Todo 2026-09-30: temporários .tmp-<pid>-* de pid morto (SIGKILL entre o temporário e o rename) saem antes de
  // executar; o --dry-run já voltou acima e não remove nada.
  for (const orfao of limparOrfaos({ cfg: plano.cfg, home: plano.home })) escrever(`temporário órfão removido: ${orfao}\n`);
  if (plano.nadaAFazer) {
    escrever(`go-and-do já está no runtime ${plano.recibo.runtime} em ${plano.cfg}; nada foi escrito.\n`);
  } else {
    executar(plano);
    // O executor grava o recibo completo com o que plano.recibo tem; runtime_anterior e hooks_anteriores só valem
    // enquanto incompleto: saem os dois numa regravação só.
    if (plano.recibo.runtime_anterior !== undefined || plano.recibo.hooks_anteriores !== undefined) {
      delete plano.recibo.runtime_anterior;
      delete plano.recibo.hooks_anteriores;
      escreverAtomico(path.join(plano.cfg, ...REL_RECIBO.split('/')), `${JSON.stringify(plano.recibo, null, 2)}\n`);
    }
    for (const linha of plano.fim) escrever(`${linha}\n`);
  }
  for (const aviso of plano.avisos) escrever(`aviso: ${aviso}\n`);
  escrever(`${AVISO_REINICIAR}\n`);
}
