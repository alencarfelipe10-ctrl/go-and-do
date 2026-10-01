// Pré-requisitos do install e do update (D-11, SPEC Requirement 2, AC-19, AC-20, borda R2). Uma tabela única em ordem
// fixa; cada ferramenta é procurada no PATH do ambiente dado (o node checado é o do PATH, que é quem roda os hooks —
// nunca process.version); todas as faltas saem numa Falha(4) só. Codex e agy são opcionais: a falta vira aviso por
// etapa da /go-and-do (fonte: dist/skills/go-and-do/scripts/pre-despacho.sh, detecção de codex e agy).
//
// Contrato:
// - MINIMO_CLAUDE: constante única da versão mínima do Claude Code (RESEARCH §Q6).
// - PREREQS: [{ ferramenta, minimo? }] — sem `minimo` = presença com versão legível.
// - OPCIONAIS_CONSULTORIA: [{ ferramenta, etapas }].
// - lerVersao(saida) → [major, minor, patch] da primeira ocorrência de N.N[.N] na primeira linha; patch ausente = 0;
//   sem casamento → null (reprovado).
// - naoMenor(a, b) → número < 0, 0 ou > 0 comparando por componentes numéricos.
// - checarPrereqs(env) → avisos (lista de frases) das opcionais ausentes; qualquer obrigatória ausente, ilegível ou
//   abaixo do mínimo → Falha(4) com uma linha por falta: `<ferramenta> (mínimo <x>): …` ou
//   `<ferramenta> (presente, versão legível): …`.
// - A sondagem roda com XDG_STATE_HOME e XDG_CACHE_HOME num diretório temporário go-and-do-sonda-* em os.tmpdir(),
//   fora de HOME, removido no fim (UAT 12, AC-08: o `gh --version` grava state/gh/device-id). A configuração e os dados
//   XDG do usuário (XDG_CONFIG_HOME, XDG_DATA_HOME) ficam como estão, porque são entrada da ferramenta sondada.
//   Sem como criar esse temporário (TMPDIR inexistente ou sem escrita) → Falha(4) antes de sondar e de escrever.
// - A sondagem também leva CODEX_HOME = <tmp>/codex, no mesmo go-and-do-sonda-*, porque o codex-cli grava
//   <CODEX_HOME ou HOME/.codex>/tmp/arg0/codex-arg0* a cada execução (verificação 5.5, AC-08). O `--version` não lê o
//   CODEX_HOME, e o que o codex gravar fica no temporário removido no finally (<tmp>/codex não é criado aqui). O aviso
//   que o codex escreve no stderr não conta, porque `sondar` lê o stdout quando ele não está vazio.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Falha } from './plano.mjs';

export const MINIMO_CLAUDE = '2.1.280';

export const PREREQS = Object.freeze([
  { ferramenta: 'claude', minimo: MINIMO_CLAUDE },
  { ferramenta: 'node', minimo: '24.0.0' },
  { ferramenta: 'python3' },
  { ferramenta: 'bash' },
  { ferramenta: 'git' },
  { ferramenta: 'gh' },
  { ferramenta: 'jq' },
]);

export const OPCIONAIS_CONSULTORIA = Object.freeze([
  { ferramenta: 'codex', etapas: ['1', '2.5', '4'] },
  { ferramenta: 'agy', etapas: ['1', '2.5'] },
]);

const RE_VERSAO = /(\d+)\.(\d+)(?:\.(\d+))?/;

export function lerVersao(saida) {
  const linha = String(saida ?? '').split('\n', 1)[0];
  const m = RE_VERSAO.exec(linha);
  return m ? [Number(m[1]), Number(m[2]), Number(m[3] ?? 0)] : null;
}

export function naoMenor(a, b) {
  return a[0] - b[0] || a[1] - b[1] || a[2] - b[2];
}

/** Roda `<ferramenta> --version` pelo PATH do env; devolve { versao, texto, motivo } (versao null = reprovada). */
function sondar(ferramenta, env) {
  const r = spawnSync(ferramenta, ['--version'], { encoding: 'utf8', timeout: 10000, env });
  if (r.error) {
    const motivo = r.error.code === 'ENOENT' ? 'ausente do PATH' : `não rodou (${r.error.code || r.error.message})`;
    return { versao: null, motivo };
  }
  if (r.status !== 0) return { versao: null, motivo: `--version saiu ${r.status ?? r.signal}` };
  const texto = (r.stdout || '').trim() ? r.stdout : r.stderr;
  const versao = lerVersao((texto || '').trim());
  if (!versao) return { versao: null, motivo: 'saída de --version sem versão reconhecível' };
  return { versao, motivo: null };
}

const juntarEtapas = (etapas) =>
  etapas.length === 1 ? etapas[0] : `${etapas.slice(0, -1).join(', ')} e ${etapas.at(-1)}`;

export function checarPrereqs(env = process.env) {
  // UAT 12 e verificação 5.5 (AC-08, D-10): o estado, o cache e o CODEX_HOME que a ferramenta grava ao rodar --version
  // vão para um temporário fora de HOME. O PATH continua o do env recebido (o node checado é o do PATH, D-11).
  let tmp;
  try {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'go-and-do-sonda-'));
  } catch (e) {
    throw new Falha(
      4,
      `não foi possível criar o diretório temporário da sondagem de pré-requisitos em ${os.tmpdir()} (${e.code || e.message}) — nada foi escrito`,
    );
  }
  const envSonda = {
    ...env,
    XDG_STATE_HOME: path.join(tmp, 'state'),
    XDG_CACHE_HOME: path.join(tmp, 'cache'),
    CODEX_HOME: path.join(tmp, 'codex'),
  };
  try {
    const faltas = [];
    for (const { ferramenta, minimo } of PREREQS) {
      const rotulo = minimo ? `${ferramenta} (mínimo ${minimo})` : `${ferramenta} (presente, versão legível)`;
      const { versao, motivo } = sondar(ferramenta, envSonda);
      if (!versao) {
        faltas.push(`${rotulo}: ${motivo}`);
        continue;
      }
      if (minimo && naoMenor(versao, lerVersao(minimo)) < 0) faltas.push(`${rotulo}: achado ${versao.join('.')}`);
    }
    if (faltas.length > 0) {
      throw new Falha(4, `pré-requisitos faltando — nada foi escrito:\n${faltas.map((f) => `  ${f}`).join('\n')}`);
    }
    const avisos = [];
    for (const { ferramenta, etapas } of OPCIONAIS_CONSULTORIA) {
      if (sondar(ferramenta, envSonda).versao) continue;
      avisos.push(
        `${ferramenta} ausente do PATH: as Etapas ${juntarEtapas(etapas)} da /go-and-do perdem a consultoria externa do ${ferramenta}.`,
      );
    }
    return avisos;
  } finally {
    // A remoção nunca troca o resultado da sondagem nem o código de saída; um órfão fica no temporário do sistema.
    try {
      fs.rmSync(tmp, { recursive: true, force: true });
    } catch {
      /* engolido de propósito */
    }
  }
}
