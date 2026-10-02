// Limpeza de temporários órfãos do próprio instalador (todo 2026-09-30, UAT da Fase 03, cenários 13 e 15). Só
// importa node:* (vai no tarball, D-09).
//
// O instalador troca atalhos e grava arquivos por «temporário irmão + rename» (lib/arvore.mjs): trocarLink cria
// `<nome>.tmp-<pid>-<8 hex>` (symlink) e escreverAtomico cria `<nome>.tmp-<pid>-<n>` (arquivo, n decimal). Um SIGKILL
// entre a criação e o rename deixa o temporário órfão, fora do recibo — o uninstall não o veria.
//
// Contrato:
// - limparOrfaos({ cfg, home }) → lista dos caminhos absolutos removidos. Varre <cfg>/skills, <cfg>/agents,
//   <cfg>/hooks e <cfg>/go-and-do só no primeiro nível (é onde os atalhos e os arquivos do produto nascem) e ~/.gad
//   em profundidade, por lstat (nunca segue symlink nem desce por symlink). Remove só symlink ou arquivo comum cujo
//   nome casa RE_TEMPORARIO e cujo pid está morto (process.kill(pid, 0) → ESRCH). Pid vivo, EPERM, o próprio pid,
//   diretório (o temporário do runtime é outro caso) ou nome fora do padrão: fica como está. Raiz que é
//   symlink não é varrida. Diretório ausente ou ilegível: nada a fazer. Uma falha ao remover um órfão não interrompe o subcomando.
import fs from 'node:fs';
import path from 'node:path';

// <nome>.tmp-<pid>-<8 hex> (trocarLink) ou <nome>.tmp-<pid>-<n decimal> (escreverAtomico); <nome> não vazio.
export const RE_TEMPORARIO = /^.+\.tmp-([1-9][0-9]{0,9})-(?:[0-9a-f]{8}|[1-9][0-9]*)$/;

const RASOS = Object.freeze(['skills', 'agents', 'hooks', 'go-and-do']);

/** true só quando o sistema diz que o processo não existe (ESRCH); na dúvida, vivo. */
export function pidMorto(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0 || pid === process.pid) return false;
  try {
    process.kill(pid, 0);
    return false;
  } catch (e) {
    return e.code === 'ESRCH';
  }
}

function lerDir(abs) {
  try {
    return fs.readdirSync(abs);
  } catch {
    return [];
  }
}

function varrer(dirAbs, profundo, removidos) {
  for (const nome of lerDir(dirAbs)) {
    const abs = path.join(dirAbs, nome);
    let st;
    try {
      st = fs.lstatSync(abs);
    } catch {
      continue;
    }
    if (st.isDirectory()) {
      if (profundo) varrer(abs, true, removidos);
      continue;
    }
    if (!st.isSymbolicLink() && !st.isFile()) continue;
    const m = RE_TEMPORARIO.exec(nome);
    if (!m || !pidMorto(Number(m[1]))) continue;
    try {
      fs.unlinkSync(abs);
      removidos.push(abs);
    } catch {
      // Sem permissão ou já removido por outro processo: o órfão fica; não vale derrubar o subcomando por ele.
    }
  }
}

// Raiz da varredura só se for diretório de verdade: raiz symlink (para onde quer que aponte) não é varrida.
function ehDiretorioReal(abs) {
  try {
    return fs.lstatSync(abs).isDirectory();
  } catch {
    return false;
  }
}

export function limparOrfaos({ cfg, home }) {
  const removidos = [];
  for (const dir of RASOS) {
    const abs = path.join(cfg, dir);
    if (ehDiretorioReal(abs)) varrer(abs, false, removidos);
  }
  const gad = home ? path.join(home, '.gad') : null;
  if (gad && ehDiretorioReal(gad)) varrer(gad, true, removidos);
  return removidos;
}
