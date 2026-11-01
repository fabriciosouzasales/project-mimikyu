"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { readCardFavoriteIds } from "@/app/colecoes/favoritos/actions";

/**
 * Favoritos entre as cartas de uma grade montada no cliente (Pesquisa, V1-10).
 *
 * Uma leitura em lote por conjunto novo de cartas (só as ainda não consultadas — "Carregar
 * mais" pergunta apenas pelas novas), nunca por carta. Falha = conjunto vazio: os
 * corações aparecem vazios e o clique continua funcionando (o servidor é a autoridade).
 * `markConfirmed` recebe o estado final confirmado pelo `CardFavoritesController`.
 */
export function useCardFavoriteIds(cardIds: readonly string[]) {
  const [favorites, setFavorites] = useState<ReadonlySet<string>>(() => new Set());
  const checked = useRef(new Set<string>());
  const idsKey = cardIds.join(",");

  useEffect(() => {
    const missing = cardIds.map((id) => id.toLowerCase()).filter((id) => !checked.current.has(id));
    if (missing.length === 0) return;
    missing.forEach((id) => checked.current.add(id));
    let cancelled = false;
    readCardFavoriteIds(missing)
      .then((ids) => {
        if (cancelled || !ids || ids.length === 0) return;
        setFavorites((prev) => new Set([...prev, ...ids]));
      })
      .catch(() => {
        // Sem favoritos marcados nesta leva; permite nova tentativa numa próxima busca.
        missing.forEach((id) => checked.current.delete(id));
      });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `idsKey` é a representação estável de `cardIds`.
  }, [idsKey]);

  const markConfirmed = useCallback((cardId: string, isFavorite: boolean) => {
    setFavorites((prev) => {
      if (prev.has(cardId) === isFavorite) return prev;
      const next = new Set(prev);
      if (isFavorite) next.add(cardId);
      else next.delete(cardId);
      return next;
    });
  }, []);

  return { favorites, markConfirmed };
}
