"use server";

import { createClient } from "@/lib/supabase/server";
import {
  CATALOGO_PAGE_SIZE,
  CATALOGO_SEARCH_CARDS_PAGE_SIZE,
  getCardSetLogoUrls,
  getCardSetsForCatalogo,
  searchCatalogo,
  type CatalogoCardResult,
  type CatalogoCardSetRow,
} from "@/lib/catalogo/queries";

/**
 * Server Actions somente-leitura da tela Catálogo (/catalogo/card-sets,
 * spec aprovada 2026-07-31) — chamadas diretamente do cliente (não são
 * mutações/formulário) para alimentar o "Carregar mais" sem recarregar a
 * página. Não fazem checagem própria de admin: dependem inteiramente da
 * política de RLS catalog_admin_select (ADR-022), mesmo padrão já usado por
 * toda a camada de leitura em lib/catalogo/queries.ts — a página que monta
 * o componente cliente já passou por requireCatalogoAdmin antes de existir.
 */
export type CardSetWithLogo = CatalogoCardSetRow & { logoUrl: string | null };

async function attachLogoUrls(
  supabase: Awaited<ReturnType<typeof createClient>>,
  items: CatalogoCardSetRow[],
): Promise<CardSetWithLogo[]> {
  const urls = await getCardSetLogoUrls(
    supabase,
    items.map((item) => item.logoStoragePath),
  );
  return items.map((item) => ({
    ...item,
    logoUrl: item.logoStoragePath ? (urls.get(item.logoStoragePath) ?? null) : null,
  }));
}

export async function loadMoreCardSets(params: {
  gameCode?: string;
  expansionCode?: string;
  offset: number;
}): Promise<{ items: CardSetWithLogo[]; hasMore: boolean }> {
  const supabase = await createClient();
  const { items, hasMore } = await getCardSetsForCatalogo(supabase, {
    gameCode: params.gameCode,
    expansionCode: params.expansionCode,
    limit: CATALOGO_PAGE_SIZE,
    offset: params.offset,
  });
  return { items: await attachLogoUrls(supabase, items), hasMore };
}

export async function searchCatalogoAction(params: {
  query: string;
  cardsOffset: number;
}): Promise<{ cardSets: CardSetWithLogo[]; cards: CatalogoCardResult[]; hasMoreCards: boolean }> {
  const supabase = await createClient();
  const result = await searchCatalogo(supabase, params.query, {
    cardsLimit: CATALOGO_SEARCH_CARDS_PAGE_SIZE,
    cardsOffset: params.cardsOffset,
  });
  return {
    cardSets: await attachLogoUrls(supabase, result.cardSets),
    cards: result.cards,
    hasMoreCards: result.hasMoreCards,
  };
}
