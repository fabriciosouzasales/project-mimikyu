// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-refresh/wave-plan.ts
// Cálculo determinístico das ondas do refresh diário JustTCG — Incremento de Atualização
// Diária JustTCG (2026-08-21), item B do pedido de Fabrício.
//
// Função pura — recebe só dados já lidos do banco pelo chamador (nenhum SupabaseClient,
// nenhum Deno.env, nenhuma chamada de rede). Decisões fechadas por Fabrício, aplicadas
// aqui sem margem de interpretação:
//   3. Ondas independentes — um Set nunca é dividido entre ondas (mesma unidade atômica
//      já usada em buildExpansionWaves()/buildBackfillWaves() do CLI).
//   5. Cada onda tem teto autoritativo de WAVE_PAGE_CAP=10 requisições (reduzido de 30
//      nesta rodada — 2026-08-21, correção pós-incidente: o piloto real com
//      WAVE_PAGE_CAP=30 disparou o shutdown_reason=WallClockTime do worker aos 150s,
//      HTTP 546, run 6c2ca781-099d-4087-89bf-4cbd4818341c preso em PROCESSING. Confirmado
//      via Management API que o Supabase/Mimikyu Labs está no plano Free — logs de
//      function_edge_logs/function_logs correlacionados no mesmo function_id provaram
//      encerramento do próprio worker, não apenas timeout do cliente HTTP).
//   7. Capacidade automática até MAX_WAVES(30) * WAVE_PAGE_CAP(10) = 300 páginas (mesmo
//      teto diário de 300 páginas da rodada de escalabilidade anterior — 2026-08-21 — só
//      o empacotamento por onda mudou, de 10 ondas de até 30 páginas para 30 ondas de até
//      10 páginas, para manter cada execução da Edge Function bem abaixo do deadline
//      interno de segurança de 110s). Se o plano superar 300 páginas OU precisar de mais
//      de 30 ondas (empacotamento guloso pode exigir mais ondas que o número mínimo
//      teórico quando Sets grandes não cabem juntos em uma onda de 10), o resultado é
//      SCHEDULE_CAPACITY_EXCEEDED — nenhuma onda escreve, nunca uma 31ª onda silenciosa.
//
// Ordenação por card_set.code (nunca por volume/prioridade) — mesmo critério já usado em
// buildExpansionWaves()/buildBackfillWaves(): determinístico, reproduzível entre
// execuções, e garante inclusão automática de qualquer novo Set confirmado (aparece na
// posição alfabética correta na próxima leitura de listRefreshCandidateSets()).

import { CARDS_PAGE_LIMIT } from "../pricing-justtcg/mod.ts";

export const WAVE_PAGE_CAP = 10;
export const MAX_WAVES = 30;
export const MAX_CAPACITY_PAGES = WAVE_PAGE_CAP * MAX_WAVES; // 300

// Um Set candidato ao refresh — já filtrado pelo chamador (port) para conter só Sets com
// pelo menos 1 identidade PRIMARY/ALTERNATE CONFIRMED da fonte JUSTTCG.
export type RefreshSetCandidate = {
  cardSetId: string;
  setCode: string;
  externalSetId: string;
  // Contagem de external_card_id DISTINTOS entre as identidades PRIMARY/ALTERNATE
  // CONFIRMED deste Set — proxy determinístico (só leitura local, nunca uma chamada à
  // JustTCG) de quantas páginas fetchAllCardsForSet() consumirá para este Set. PENDING/
  // NOT_FOUND/REJECTED/ALIAS nunca entram nesta contagem (regra 17).
  confirmedCardCount: number;
};

export type RefreshWaveSetEntry = RefreshSetCandidate & {
  estimatedPages: number;
};

export type RefreshWave = {
  waveNumber: number;
  sets: RefreshWaveSetEntry[];
  estimatedPages: number;
};

export type RefreshWavePlan =
  | {
    status: "OK";
    waves: RefreshWave[]; // sempre <= MAX_WAVES; cada onda com estimatedPages <= WAVE_PAGE_CAP
    totalEstimatedPages: number;
    totalSets: number;
  }
  | {
    status: "SCHEDULE_CAPACITY_EXCEEDED";
    totalEstimatedPages: number;
    totalSets: number;
  };

export function buildRefreshWavePlan(
  candidates: readonly RefreshSetCandidate[],
): RefreshWavePlan {
  // Ordenação determinística por código do Set — nunca por volume/prioridade.
  const sorted = [...candidates]
    .filter((c) => c.confirmedCardCount > 0) // defensivo — um Set sem nenhuma identidade confirmada nunca deveria chegar aqui
    .sort((a, b) => a.setCode.localeCompare(b.setCode));

  const entries: RefreshWaveSetEntry[] = sorted.map((c) => ({
    ...c,
    // Mínimo de 1 página por Set com pelo menos 1 identidade confirmada — mesma regra de
    // arredondamento para cima já usada no orçamento calculado na auditoria arquitetural
    // (item 4 da rodada anterior).
    estimatedPages: Math.max(
      1,
      Math.ceil(c.confirmedCardCount / CARDS_PAGE_LIMIT),
    ),
  }));

  const totalEstimatedPages = entries.reduce(
    (sum, e) => sum + e.estimatedPages,
    0,
  );
  const totalSets = entries.length;

  if (totalEstimatedPages > MAX_CAPACITY_PAGES) {
    return {
      status: "SCHEDULE_CAPACITY_EXCEEDED",
      totalEstimatedPages,
      totalSets,
    };
  }

  // Empacotamento guloso — um Set nunca é dividido entre ondas. Um Set cujas próprias
  // páginas excedem WAVE_PAGE_CAP forma sua própria onda "oversized" (mesmo precedente de
  // buildBackfillWaves() no CLI, que também nunca fragmenta um Set).
  const waves: RefreshWave[] = [];
  let current: RefreshWaveSetEntry[] = [];
  let currentPages = 0;
  for (const entry of entries) {
    if (
      currentPages > 0 && currentPages + entry.estimatedPages > WAVE_PAGE_CAP
    ) {
      waves.push({
        waveNumber: waves.length + 1,
        sets: current,
        estimatedPages: currentPages,
      });
      current = [];
      currentPages = 0;
    }
    current.push(entry);
    currentPages += entry.estimatedPages;
  }
  if (current.length > 0) {
    waves.push({
      waveNumber: waves.length + 1,
      sets: current,
      estimatedPages: currentPages,
    });
  }

  // Rede de segurança final: mesmo com totalEstimatedPages <= 300, um empacotamento guloso
  // patológico (vários Sets grandes que não cabem juntos numa onda de 10) pode em teoria
  // exigir mais de 30 ondas — nunca uma 31ª onda silenciosa, sempre capacidade excedida.
  if (waves.length > MAX_WAVES) {
    return {
      status: "SCHEDULE_CAPACITY_EXCEEDED",
      totalEstimatedPages,
      totalSets,
    };
  }

  return { status: "OK", waves, totalEstimatedPages, totalSets };
}
