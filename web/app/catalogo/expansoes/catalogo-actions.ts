"use server";

import { createClient } from "@/lib/supabase/server";
import {
  EXPANSOES_PAGE_SIZE,
  getExpansionLogoUrls,
  searchExpansoes,
  type ExpansaoWithLogo,
} from "@/lib/catalogo/queries";

/**
 * Server Actions somente-leitura da galeria de Expansões (redesenho
 * 2026-07-31, mesma linguagem visual/comportamento da tela Catálogo) —
 * chamadas do cliente para o "Carregar mais" da busca. Sem checagem própria
 * de admin, mesmo padrão de card-sets/catalogo-actions.ts: a política de RLS
 * catalog_admin_select já garante isso, e a página que monta o componente
 * cliente já passou por requireCatalogoAdmin antes de existir.
 *
 * Ajuste 2026-07-31, rodada seguinte (agrupamento por Jogo): `loadMoreExpansoes`
 * foi removida — o modo galeria (sem busca) passou a carregar tudo de uma vez
 * via `getExpansoesGroupedByGame()` (chamada só no Server Component, `page.tsx`),
 * sem paginação incremental. Só a busca (flat, sem agrupamento) continua
 * paginada.
 *
 * Ajuste 2026-07-31, mesmo dia (logo de Expansão): resultado da busca passa
 * a incluir `logoUrl` (URL assinada, mesmo padrão de `attachLogoUrls` em
 * card-sets/catalogo-actions.ts) — necessário aqui porque cada página do
 * "Carregar mais" da busca chega direto do cliente, sem passar pelo Server
 * Component de `page.tsx`.
 */
export async function searchExpansoesAction(
  params: { query: string; offset: number },
): Promise<{ items: ExpansaoWithLogo[]; hasMore: boolean }> {
  const supabase = await createClient();
  const { items, hasMore } = await searchExpansoes(supabase, params.query, {
    limit: EXPANSOES_PAGE_SIZE,
    offset: params.offset,
  });
  const logoUrls = await getExpansionLogoUrls(
    supabase,
    items.map((item) => item.logoStoragePath),
  );
  return {
    items: items.map((item) => ({
      ...item,
      logoUrl: item.logoStoragePath ? (logoUrls.get(item.logoStoragePath) ?? null) : null,
    })),
    hasMore,
  };
}
