// Project Mimikyu — supabase/functions/_shared/pricing-ptax/core.ts
// Orquestrador puro — Incremento P13.2.
//
// Núcleo puro: nunca lê variável de ambiente, nunca cria cliente Supabase, nunca
// referencia Deno.env/process.env. Recebe data de referência, fetch, espera e
// repositório inteiramente por parâmetro — exigência explícita desta rodada, para que
// o adapter manual (scripts/sync-ptax-fx-rate.ts) e uma futura Edge Function agendada
// (P13.3+) compartilhem exatamente esta mesma lógica, sem duplicação.

import type {
  CivilDate,
  FetchLike,
  PtaxRateRepository,
  PtaxRunResult,
  WaitLike,
} from "./types.ts";
import { resolveDefaultPeriod, resolveOverridePeriod } from "./period.ts";
import { buildPtaxPeriodUrl } from "./url.ts";
import { fetchPtaxPeriodWithRetry } from "./http.ts";
import { validatePtaxResponseShape } from "./validate.ts";
import { selectClosingRatesByDate } from "./select-closing.ts";
import { persistPtaxRates } from "./persist.ts";

export interface RunPtaxSyncInput {
  // Data civil (YYYY-MM-DD) de America/Sao_Paulo, calculada pelo chamador — o núcleo
  // nunca lê o relógio do sistema diretamente.
  referenceDate: CivilDate;
  // Se qualquer um dos dois for informado, o outro também deve ser (validado abaixo)
  // — override explícito de início/fim, substitui a janela padrão de 10 dias.
  overrideStartDate?: CivilDate;
  overrideEndDate?: CivilDate;
  fetchImpl: FetchLike;
  waitImpl: WaitLike;
  repository: PtaxRateRepository;
  dryRun: boolean;
  timeoutMs?: number;
}

export async function runPtaxSync(
  input: RunPtaxSyncInput,
): Promise<PtaxRunResult> {
  const usingOverride = input.overrideStartDate !== undefined ||
    input.overrideEndDate !== undefined;

  if (
    usingOverride &&
    (input.overrideStartDate === undefined ||
      input.overrideEndDate === undefined)
  ) {
    return {
      kind: "FUNCTIONAL_FAILURE",
      detail:
        "OVERRIDE_INCOMPLETO: override de período exige overrideStartDate E overrideEndDate juntos, nunca só um dos dois.",
      callLog: [],
    };
  }

  const periodResolution = usingOverride
    ? resolveOverridePeriod(
      input.overrideStartDate as string,
      input.overrideEndDate as string,
    )
    : resolveDefaultPeriod(input.referenceDate);

  if (periodResolution.status === "INVALID") {
    return {
      kind: "FUNCTIONAL_FAILURE",
      detail: periodResolution.reason,
      callLog: [],
    };
  }
  const period = periodResolution.period;

  const url = buildPtaxPeriodUrl(period.startDate, period.endDate);
  const httpResult = await fetchPtaxPeriodWithRetry(url, {
    fetchImpl: input.fetchImpl,
    waitImpl: input.waitImpl,
    timeoutMs: input.timeoutMs,
  });
  if (httpResult.status !== "SUCCESS") {
    return {
      kind: "TECHNICAL_FAILURE",
      detail: httpResult.detail,
      callLog: httpResult.callLog,
    };
  }

  const shapeResult = validatePtaxResponseShape(httpResult.json);
  if (shapeResult.status === "INVALID") {
    return {
      kind: "FUNCTIONAL_FAILURE",
      detail: shapeResult.reason,
      callLog: httpResult.callLog,
    };
  }

  const { rates, invalidDetails } = selectClosingRatesByDate(shapeResult.items);
  const persistResult = await persistPtaxRates(
    input.repository,
    rates,
    input.dryRun,
  );
  persistResult.counts.invalid = invalidDetails.length;

  return {
    kind: "COMPLETED",
    period,
    quotesReceived: shapeResult.items.length,
    counts: persistResult.counts,
    divergences: persistResult.divergences,
    invalidDetails,
    callLog: httpResult.callLog,
  };
}
