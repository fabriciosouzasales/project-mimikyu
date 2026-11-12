"use client";

import { createContext, type ReactNode, useCallback, useEffect, useRef, useState } from "react";
import { readCardFavoriteIds } from "@/app/colecoes/favoritos/actions";
import { CardFavoritesController } from "@/components/favorites/card-favorites-controller";
import type { BinderPage } from "@/lib/colecoes/binder";
import { FAVORITE_READ_MAX, binderFavoriteReadIds } from "@/lib/colecoes/binder-favorites";

/**
 * Estado dos corações de Favorito no Fichário (V1-10, extensão). `null` fora do
 * fichário do titular (compartilhado em só leitura, vitrine): nenhum coração.
 * `known` = cartas cobertas por uma leitura bem-sucedida — sem leitura, o bolso não
 * mostra coração (nunca "não favorita" por falta de dado).
 */
export type BinderFavoriteValue = { favorites: ReadonlySet<string>; known: ReadonlySet<string> };

export const BinderFavoriteContext = createContext<BinderFavoriteValue | null>(null);

const EMPTY: BinderFavoriteValue = { favorites: new Set(), known: new Set() };

function allSlots(pages: ReadonlyMap<number, BinderPage>) {
  return [...pages.values()].flatMap((page) => page.slots);
}

/**
 * Camada de Favoritos no Fichário — o mesmo desenho da Lista de desejos (V1-11 W5):
 * UMA leitura em lote por conjunto novo de cartas das páginas carregadas
 * (`readCardFavoriteIds`, a mesma da Pesquisa), e o `CardFavoritesController` da V1-10
 * por delegação (nenhum componente cliente por bolso; todos os corações da mesma
 * carta pintados juntos; otimista, uma gravação por vez, última intenção vence,
 * reversão + aviso no toast do Fichário).
 *
 * Nunca grava nada no fichário: só lê qual carta cada bolso mostra. Raiz
 * `display: contents` para não mexer na grade.
 */
export function BinderFavoriteLayer({
  pages,
  onFeedback,
  children,
}: {
  pages: ReadonlyMap<number, BinderPage>;
  onFeedback: (feedback: { tone: "error"; text: string }) => void;
  children: ReactNode;
}) {
  const [state, setState] = useState<BinderFavoriteValue>(EMPTY);
  // Cartas já pedidas (com sucesso ou em voo): cada uma é lida uma vez, nunca por bolso.
  const requested = useRef(new Set<string>());
  // Só a desmontagem descarta respostas: páginas mudam a cada gesto e a leitura em voo continua valendo.
  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  useEffect(() => {
    const ids = binderFavoriteReadIds(allSlots(pages), requested.current).slice(0, FAVORITE_READ_MAX);
    if (ids.length === 0) return;
    for (const id of ids) requested.current.add(id);
    void readCardFavoriteIds(ids)
      .catch(() => null)
      .then((result) => {
        if (!result) {
          // Falha: libera para uma próxima tentativa (nova página carregada).
          for (const id of ids) requested.current.delete(id);
          return;
        }
        if (!mounted.current) return;
        const favored = new Set(result.map((id) => id.toLowerCase()));
        setState((prev) => {
          const favorites = new Set(prev.favorites);
          const known = new Set(prev.known);
          for (const id of ids) {
            known.add(id);
            if (favored.has(id)) favorites.add(id);
            else favorites.delete(id);
          }
          return { favorites, known };
        });
      });
  }, [pages]);

  // Estado confirmado pelo servidor: bolsos montados depois (outra página) nascem certos.
  const onConfirmed = useCallback((cardId: string, isFavorite: boolean) => {
    const id = cardId.toLowerCase();
    setState((prev) => {
      if (prev.favorites.has(id) === isFavorite && prev.known.has(id)) return prev;
      const favorites = new Set(prev.favorites);
      if (isFavorite) favorites.add(id);
      else favorites.delete(id);
      return { favorites, known: new Set(prev.known).add(id) };
    });
  }, []);

  return (
    <BinderFavoriteContext.Provider value={state}>
      <CardFavoritesController className="contents" onConfirmed={onConfirmed} onFeedback={onFeedback}>
        {children}
      </CardFavoritesController>
    </BinderFavoriteContext.Provider>
  );
}
