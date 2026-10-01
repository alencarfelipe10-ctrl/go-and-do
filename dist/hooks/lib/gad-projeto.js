'use strict';
// hooks/lib/gad-projeto.js — ajudante do marcador de projeto gad (D-16, CONV-01).
//
// Um vigia do produto só age em projeto gad: o que tem o arquivo regular `.planning/gad-projeto.json` no cwd do
// hook, na raiz do git do cwd ou na árvore principal (worktree ligada). Fora dele o vigia sai 0 calado.
//
// Contrato:
//   - projetoGad(texto) → boolean. `texto` é o JSON cru que o hook recebeu no stdin. Usa o `cwd` do payload tal
//     como veio (nunca o diretório do processo): `cwd` ausente, vazio ou que não é string, e texto que não é JSON,
//     dão false. Candidatos, nesta ordem: o cwd; `git -C <cwd> rev-parse --show-toplevel`; `git -C <cwd> rev-parse
//     --path-format=absolute --git-common-dir` sem o `/.git` final (só quando termina nele — em submódulo não termina
//     e o candidato é descartado). O cwd é checado antes de subir qualquer processo. Cada git roda sem shell, com
//     limite de 1 s (SIGKILL), stdin fechado e stderr descartado. Presença = lstat(...).isFile(): symlink e
//     diretório não contam.
//   - Rodado direto (`node gad-projeto.js`, como o gad-projeto.sh o chama), lê o stdin inteiro e sai 0 marcado, 1
//     não marcado (inclusive erro de leitura). Carregado por require, não lê o stdin nem mexe no código de saída.
//   - Nunca imprime nada e nunca escreve arquivo.
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const MARCADOR = path.join('.planning', 'gad-projeto.json');
const OPCOES_GIT = { encoding: 'utf8', timeout: 1000, killSignal: 'SIGKILL', stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true };

function temMarcador(dir) {
  try {
    return fs.lstatSync(path.join(dir, MARCADOR)).isFile();
  } catch {
    return false;
  }
}

/** Saída de `git -C <cwd> rev-parse <args…>` em uma linha, ou '' se o git falhou, estourou o limite ou não existe. */
function revParse(cwd, args) {
  let r;
  try {
    r = spawnSync('git', ['-C', cwd, 'rev-parse', ...args], OPCOES_GIT);
  } catch {
    return '';
  }
  if (r.error || r.status !== 0 || typeof r.stdout !== 'string') return '';
  return r.stdout.replace(/\r?\n$/, '');
}

function projetoGad(texto) {
  let dados;
  try {
    dados = JSON.parse(String(texto));
  } catch {
    return false;
  }
  const cwd = dados !== null && typeof dados === 'object' && typeof dados.cwd === 'string' ? dados.cwd : '';
  if (!cwd) return false;
  if (temMarcador(cwd)) return true;
  const raiz = revParse(cwd, ['--show-toplevel']);
  if (raiz && temMarcador(raiz)) return true;
  const comum = revParse(cwd, ['--path-format=absolute', '--git-common-dir']);
  if (comum.endsWith('/.git')) {
    const principal = comum.slice(0, -'/.git'.length);
    if (principal && temMarcador(principal)) return true;
  }
  return false;
}

module.exports = { projetoGad };

if (require.main === module) {
  // Leitura por eventos, como os vigias fazem (readFileSync(0) pode lançar EAGAIN num pipe).
  let texto = '';
  let falhou = false;
  process.exitCode = 1;
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (pedaco) => {
    texto += pedaco;
  });
  process.stdin.on('error', () => {
    falhou = true;
    process.exitCode = 1;
  });
  process.stdin.on('end', () => {
    if (!falhou) process.exitCode = projetoGad(texto) ? 0 : 1;
  });
}
