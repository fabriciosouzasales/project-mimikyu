"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { readWishedByCard } from "@/app/colecoes/lista-de-desejos/actions";

/**
 * Cartas com pelo menos uma variante na Lista de desejos, numa grade montada no
 * cliente (Pesquisa, V1-11 W1) — mesmo desenho de `useCardFavoriteIds`: uma leitura em
 * lote por conjunto novo de cartas, nunca por carta. Falha = conjunto vazio (os
 * marcadores não aparecem até uma leitura responder — nunca um marcador que não
 * funciona). `markCard` recebe o conjunto final confirmado pelo `WishlistController`.
 */
export function useWishedCards(cardIds: readonly string[]) {
  const [wished, setWished] = useState<ReadonlySet<string>>(() => new Set());
  // Marcadores só aparecem depois que a leitura responde: SQL ausente ou falha → sem marcador.
  const [available, setAvailable] = useState(false);
  const checked = useRef(new Set<string>());
  const idsKey = cardIds.join(",");

  useEffect(() => {
    const missing = cardIds.map((id) => id.toLowerCase()).filter((id) => !checked.current.has(id));
    if (missing.length === 0) return;
    missing.forEach((id) => checked.current.add(id));
    let cancelled = false;
    readWishedByCard(missing)
      .then((map) => {
        if (cancelled) return;
        if (!map) {
          missing.forEach((id) => checked.current.delete(id));
          return;
        }
        setAvailable(true);
        const cards = Object.entries(map)
          .filter(([, variants]) => variants.length > 0)
          .map(([card]) => card);
        if (cards.length > 0) setWished((prev) => new Set([...prev, ...cards]));
      })
      .catch(() => {
        missing.forEach((id) => checked.current.delete(id));
      });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `idsKey` é a representação estável de `cardIds`.
  }, [idsKey]);

  const markCard = useCallback((cardId: string, variantIds: string[]) => {
    const isWished = variantIds.length > 0;
    setWished((prev) => {
      if (prev.has(cardId) === isWished) return prev;
      const next = new Set(prev);
      if (isWished) next.add(cardId);
      else next.delete(cardId);
      return next;
    });
  }, []);

  return { wished, available, markCard };
}
