"use server";

import { createClient } from "@/lib/supabase/server";
import { EXPANSOES_PAGE_SIZE, searchExpansoes } from "@/lib/catalogo/queries";

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
 */
export async function searchExpansoesAction(params: { query: string; offset: number }) {
  const supabase = await createClient();
  return searchExpansoes(supabase, params.query, { limit: EXPANSOES_PAGE_SIZE, offset: params.offset });
}
