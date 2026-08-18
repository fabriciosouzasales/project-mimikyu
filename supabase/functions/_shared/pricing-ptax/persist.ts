// Project Mimikyu — supabase/functions/_shared/pricing-ptax/persist.ts
// Persistência idempotente — Incremento P13.2.
//
// Regras (decisão registrada nesta rodada): insere só datas ausentes; taxa existente e
// idêntica é "unchanged"; taxa existente e divergente é "divergent" e NUNCA é
// sobrescrita — este módulo não emite nenhum UPDATE em pricing_fx_rate em nenhuma
// circunstância, preservando a garantia de append-only já registrada em 05f-pricing.md.
// `invalid` é decidido antes deste módulo (ver select-closing.ts) — aqui já chegam só
// PtaxRate estruturalmente válidos.

import type {
  DivergenceDetail,
  PersistCounts,
  PtaxRate,
  PtaxRateRepository,
} from "./types.ts";

export interface PersistResult {
  counts: PersistCounts;
  divergences: DivergenceDetail[];
}

export async function persistPtaxRates(
  repository: PtaxRateRepository,
  rates: PtaxRate[],
  dryRun: boolean,
): Promise<PersistResult> {
  const counts: PersistCounts = {
    inserted: 0,
    unchanged: 0,
    divergent: 0,
    invalid: 0,
  };
  const divergences: DivergenceDetail[] = [];
  if (rates.length === 0) return { counts, divergences };

  const dates = rates.map((r) => r.rateDate);
  const existing = await repository.findExistingRates(dates);

  for (const rate of rates) {
    const existingRate = existing.get(rate.rateDate);

    if (existingRate === undefined) {
      if (dryRun) {
        // Dry-run nunca escreve — a contagem aqui é só a previsão do que seria
        // inserido, nunca uma escrita real (ver também a garantia em persist não
        // chamar repository.insertRate quando dryRun é verdadeiro).
        counts.inserted++;
        continue;
      }
      const outcome = await repository.insertRate(rate);
      if (outcome === "INSERTED") counts.inserted++;
      else counts.unchanged++; // CONFLICT_IGNORED: outra execução gravou entre a leitura e a escrita
      continue;
    }

    if (existingRate === rate.rate) {
      counts.unchanged++;
    } else {
      counts.divergent++;
      divergences.push({
        rateDate: rate.rateDate,
        existingRate,
        incomingRate: rate.rate,
      });
    }
  }

  return { counts, divergences };
}
