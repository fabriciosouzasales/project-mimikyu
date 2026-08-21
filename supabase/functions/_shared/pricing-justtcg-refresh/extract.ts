// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-refresh/extract.ts
// Extração pura de candidatos de observação de preço a partir de JustTcgCard já
// paginados — Incremento de Atualização Diária JustTCG (2026-08-21), item B.
//
// Diferença estrutural deliberada frente a classifyCardMatch()/persistBatchedResults()
// do CLI: aqui NUNCA há matching. A correlação carta-externa -> identidade local é uma
// busca exata por chave (external_card_id = JustTcgCard.id, o mesmo campo gravado em
// pricing_source_card_identity.external_card_id no momento da confirmação original) —
// nunca número de coleção, nunca nome, nunca heurística de desempate. Uma carta cujo id
// não está no índice de identidades confirmadas é ignorada nesta rodada, nunca gera um
// registro PENDING/NOT_FOUND novo (regra 12: "o refresh... nunca refaz matching"; regra
// 11: nunca escreve em pricing_card_mapping/pricing_source_card_identity).
//
// A extração de variante em si (externalProductId/price/observedAt/rawPayload/
// conditionId) é EXATAMENTE a mesma lógica já usada em persistBatchedResults() do CLI
// (Fase 2, ver scripts/sync-justtcg-pricing.ts) — reproduzida aqui porque a fonte real
// (o loop de matching do CLI) não é reaproveitável como função (está embutida em
// executeExpansionWave/executeBackfillWave/executeRepairMappings/
// executeRepairMultiIdentities, cada uma com sua própria orquestração de matching), mas o
// CONTRATO de saída (mesmos campos, mesma validação: externalProductId não-vazio,
// printing não-vazio, price numérico, condição mapeada) é idêntico.

import type { JustTcgCard } from "../pricing-justtcg/mod.ts";
import { sanitizeJson, splitPrintingLanguage } from "../pricing-justtcg/mod.ts";

export type ConfirmedIdentityRole = "PRIMARY" | "ALTERNATE";

// Índice de identidades CONFIRMED (PRIMARY/ALTERNATE) de um Set, por external_card_id —
// construído pelo chamador (core.ts) a partir de RefreshPort.listConfirmedIdentitiesForSet().
// Nunca contém PENDING/REJECTED/ALIAS (regra 17 — filtrados na origem, antes deste módulo).
export type RefreshIdentityIndex = Map<
  string,
  {
    identityId: string;
    identityRole: ConfirmedIdentityRole;
    pricingCardMappingId: string;
  }
>;

export type RefreshObservationCandidate = {
  identityId: string;
  identityRole: ConfirmedIdentityRole;
  pricingCardMappingId: string;
  externalCardId: string;
  externalProductId: string;
  sourcePrintingLabel: string;
  conditionId: string;
  price: number;
  observedAt: string;
  rawPayload: unknown;
};

export type ExtractResult = {
  candidates: RefreshObservationCandidate[];
  // Cartas paginadas cujo id não corresponde a nenhuma identidade confirmada nossa —
  // esperado e comum (a JustTCG pode listar cartas do Set que ainda não mapeamos, ou que
  // estão PENDING/NOT_FOUND) — nunca um erro, só contagem informativa para telemetria.
  cardsUnmatchedCount: number;
  // Variantes descartadas por dado inválido/condição sem mapeamento — sinalizadas, nunca
  // silenciosas (mesma disciplina do CLI).
  skippedReasons: string[];
};

export function extractRefreshObservationCandidates(
  cards: readonly JustTcgCard[],
  identityIndex: RefreshIdentityIndex,
  conditionMap: ReadonlyMap<string, string>,
): ExtractResult {
  const candidates: RefreshObservationCandidate[] = [];
  const skippedReasons: string[] = [];
  let cardsUnmatchedCount = 0;

  for (const card of cards) {
    const externalCardId = String(card.id ?? "");
    if (!externalCardId) continue; // defensivo — a JustTCG sempre documenta `id` obrigatório

    const identity = identityIndex.get(externalCardId);
    if (!identity) {
      cardsUnmatchedCount++;
      continue; // nunca matching — só ignora cartas fora do nosso índice de identidades confirmadas
    }

    for (const variant of card.variants ?? []) {
      const externalProductId = String(variant.uuid ?? variant.id ?? "");
      const printingRaw = String(variant.printing ?? "");
      const conditionRaw = String(variant.condition ?? "");
      const price = variant.price;
      const lastUpdated = variant.lastUpdated;

      if (!externalProductId || !printingRaw || typeof price !== "number") {
        skippedReasons.push(
          `VARIANT_INVALID_DATA(card=${externalCardId})`,
        );
        continue;
      }

      const conditionId = conditionMap.get(conditionRaw);
      if (!conditionId) {
        skippedReasons.push(`CONDICAO_SEM_MAPEAMENTO(${conditionRaw})`);
        continue;
      }

      const { printingTipo } = splitPrintingLanguage(printingRaw);
      const observedAt = typeof lastUpdated === "number"
        ? new Date(lastUpdated * 1000).toISOString()
        : new Date().toISOString();
      const rawPayload = sanitizeJson({
        condition: conditionRaw,
        printing: printingRaw,
        price,
        lastUpdated,
      });

      candidates.push({
        identityId: identity.identityId,
        identityRole: identity.identityRole,
        pricingCardMappingId: identity.pricingCardMappingId,
        externalCardId,
        externalProductId,
        sourcePrintingLabel: printingTipo ?? printingRaw,
        conditionId,
        price,
        observedAt,
        rawPayload,
      });
    }
  }

  return { candidates, cardsUnmatchedCount, skippedReasons };
}
