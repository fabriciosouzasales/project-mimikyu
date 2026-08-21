// Project Mimikyu — supabase/functions/_shared/pricing-justtcg/pagination.ts
// Paginação de GET /v1/cards por Set — extraída verbatim de
// scripts/sync-justtcg-pricing.ts (Incremento P14.2) para o Incremento de Atualização
// Diária JustTCG (2026-08-21), item A.
//
// Uma chamada por PÁGINA de até CARDS_PAGE_LIMIT cartas do Set, nunca uma por carta —
// substituiu a Fase B original de P8 (uma chamada HTTP por carta, inviável em escala).
// Usado tanto pelo CLI (matching/descoberta, `set` = external_set_id ainda a confirmar)
// quanto pelo núcleo de refresh diário (`set` = external_set_id já CONFIRMED, lido de
// pricing_set_mapping — mesma função, zero duplicação).

import type { JustTcgCard } from "./types.ts";
import { CARDS_PAGE_LIMIT, GAME_CODE, type JustTcgClient } from "./client.ts";

export async function fetchAllCardsForSet(
  client: JustTcgClient,
  externalSetId: string,
): Promise<{
  cards: JustTcgCard[];
  requestsUsed: number;
  aborted: "AUTH_FAILURE" | "TECHNICAL_FAILURE" | "BUDGET_STOPPED" | null;
}> {
  const cards: JustTcgCard[] = [];
  let offset = 0;
  let requestsUsed = 0;
  for (;;) {
    const result = await client.get<{ data: JustTcgCard[] }>("/cards", {
      game: GAME_CODE,
      set: externalSetId,
      limit: String(CARDS_PAGE_LIMIT),
      offset: String(offset),
    });
    if (result.status === "AUTH_FAILURE") {
      return { cards, requestsUsed, aborted: "AUTH_FAILURE" };
    }
    if (result.status === "BUDGET_STOPPED") {
      return { cards, requestsUsed, aborted: "BUDGET_STOPPED" };
    }
    if (result.status !== "SUCCESS") {
      return { cards, requestsUsed, aborted: "TECHNICAL_FAILURE" };
    }

    requestsUsed++;
    const page = result.data.data ?? [];
    cards.push(...page);

    // Fallback (ausência de meta.hasMore): página mais curta que o limite -> última.
    const hasMore = result.meta?.hasMore ?? page.length === CARDS_PAGE_LIMIT;
    if (!hasMore || page.length === 0) break;
    offset += CARDS_PAGE_LIMIT;
  }
  return { cards, requestsUsed, aborted: null };
}
