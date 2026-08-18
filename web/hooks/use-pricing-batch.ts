"use client";

import { useEffect, useState } from "react";
import { fetchPricingBatch, getCachedPricingEntry, type PricingCacheEntry } from "@/lib/pricing/pricing-batch-client";

/**
 * Resumo de preço de todas as cartas atualmente renderizadas num grid — uma
 * única chamada em lote (`fetchPricingBatch`), disparada assim que a lista de
 * `card_id` está disponível, nunca esperando hover/foco/toque (pedido
 * explícito de Fabrício, 2026-08-18: "o elemento não pode depender de hover
 * para existir. A chamada batch fornece o resumo antes da interação").
 *
 * Cartas ainda sem entrada no mapa retornado = ainda não resolvidas (nem
 * carregando nem confirmadas vazias) — o card correspondente simplesmente não
 * renderiza nada até a próxima re-renderização deste hook, sem estado de
 * "loading" visível: o resumo já deve estar pronto por volta do momento em
 * que o usuário efetivamente vê o grid, e não há necessidade de comunicar um
 * intervalo de carregamento que dura uma fração de segundo.
 */
export function usePricingBatch(cardIds: readonly string[]): ReadonlyMap<string, PricingCacheEntry> {
  const idsKey = cardIds.join(",");
  const [, bump] = useState(0);

  useEffect(() => {
    if (cardIds.length === 0) return;
    const missing = cardIds.filter((id) => getCachedPricingEntry(id) === undefined);
    if (missing.length === 0) return;

    let cancelled = false;
    fetchPricingBatch(missing).then(() => {
      if (!cancelled) bump((n) => n + 1);
    });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `idsKey` é a representação estável de `cardIds`.
  }, [idsKey]);

  const map = new Map<string, PricingCacheEntry>();
  for (const id of cardIds) {
    const entry = getCachedPricingEntry(id);
    if (entry) map.set(id, entry);
  }
  return map;
}
