"use server";

import { createClient } from "@/lib/supabase/server";
import {
  CATALOGO_SEARCH_CARDS_PAGE_SIZE,
  getCardSetLogoUrls,
  searchCatalogo,
  type CatalogoCardResult,
  type CatalogoCardSetRow,
  type CatalogoCardSetRowWithLogo,
} from "@/lib/catalogo/queries";

/**
 * Server Actions somente-leitura da tela Catálogo (/catalogo/card-sets,
 * spec aprovada 2026-07-31) — chamadas diretamente do cliente (não são
 * mutações/formulário) para alimentar o "Carregar mais" sem recarregar a
 * página. Não fazem checagem própria de admin: dependem inteiramente da
 * política de RLS catalog_admin_select (ADR-022), mesmo padrão já usado por
 * toda a camada de leitura em lib/catalogo/queries.ts — a página que monta
 * o componente cliente já passou por requireCatalogoAdmin antes de existir.
 *
 * Ajuste 2026-08-02 (pedido de Fabrício: "separá-las por Expansão", mesmo
 * padrão de `getExpansoesGroupedByGame`): `CardSetWithLogo` passa a ser um
 * reexport de `CatalogoCardSetRowWithLogo` (definido em `lib/catalogo/
 * queries.ts`, mesmo lugar de `ExpansaoWithLogo`) — evita duplicar o tipo
 * agora que a galeria (modo sem busca) usa `getCardSetsGroupedByExpansion()`
 * em vez de paginação flat; os imports existentes em `card-set-gallery-card.
 * tsx`/`card-set-dialogs.tsx` continuam funcionando sem alteração. `loadMoreCardSets`
 * foi removida — modo galeria carrega tudo de uma vez (agrupado, sem
 * paginação incremental), mesma mudança já aplicada a `searchExpansoesAction`
 * quando Expansões ganhou agrupamento por Jogo. Só a busca (flat, sem
 * agrupamento) continua paginada.
 */
export type CardSetWithLogo = CatalogoCardSetRowWithLogo;

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
