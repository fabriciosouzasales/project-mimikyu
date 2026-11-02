import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type WishlistPage,
  type WishlistSummary,
  WISHLIST_PAGE_SIZE,
  chunkIds,
  parseWishlistPage,
  parseWishlistSummary,
  toWishedByCardMap,
  toWishedVariantSet,
} from "./wishlist.ts";

/**
 * Leituras da Lista de desejos (V1-11 W1, Queries 5346/5347) — sempre como o usuário
 * da sessão (o banco resolve o dono por `auth.uid()`), em lote, nunca uma chamada por
 * carta. Falha = `null`: a grade continua, só sem marcadores pintados. Função ausente
 * no LIVE (`PGRST202`, SQL ainda não aplicado) cai no mesmo caminho.
 */

function logFailure(fn: string, startedAt: number, error: { code?: string } | null) {
  console.error(JSON.stringify({ scope: "wishlist.read", fn, ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE" }));
}

/** Variantes com pelo menos um desejo (Acervo; futuras entradas Fichário/Master Set). */
export async function getMyWishedVariants(
  supabase: SupabaseClient,
  variantIds: readonly (string | null | undefined)[],
): Promise<Set<string> | null> {
  const blocks = chunkIds(variantIds);
  if (blocks.length === 0) return new Set();
  const startedAt = Date.now();
  const results = await Promise.all(
    blocks.map(async (block) => {
      const { data, error } = await supabase.rpc("get_my_wishlist_state_by_variant", { p_card_variant_ids: block });
      if (error || !Array.isArray(data)) {
        logFailure("get_my_wishlist_state_by_variant", startedAt, error);
        return null;
      }
      return toWishedVariantSet(data);
    }),
  );
  if (results.some((set) => set === null)) return null;
  return new Set(results.flatMap((set) => [...(set as Set<string>)]));
}

/** Carta → variantes desejadas (Pesquisa; futuras entradas Set/Pokédex). */
export async function getMyWishedByCard(supabase: SupabaseClient, cardIds: readonly string[]): Promise<Map<string, Set<string>> | null> {
  const blocks = chunkIds(cardIds);
  if (blocks.length === 0) return new Map();
  const startedAt = Date.now();
  const results = await Promise.all(
    blocks.map(async (block) => {
      const { data, error } = await supabase.rpc("get_my_wishlist_state_by_card", { p_card_ids: block });
      if (error || !Array.isArray(data)) {
        logFailure("get_my_wishlist_state_by_card", startedAt, error);
        return null;
      }
      return toWishedByCardMap(data);
    }),
  );
  if (results.some((map) => map === null)) return null;
  const merged = new Map<string, Set<string>>();
  for (const map of results as Map<string, Set<string>>[]) for (const [card, set] of map) merged.set(card, set);
  return merged;
}

/** Uma página da Lista de desejos, mais recentes primeiro. */
export async function getMyWishlistPage(supabase: SupabaseClient, page: number): Promise<WishlistPage | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_wishlist", {
    p_limit: WISHLIST_PAGE_SIZE,
    p_offset: (page - 1) * WISHLIST_PAGE_SIZE,
  });
  const parsed = error ? null : parseWishlistPage(data);
  if (!parsed) logFailure("get_my_wishlist", startedAt, error);
  return parsed;
}

/** Indicadores (5347): desejos, variantes distintas e valor de referência com cobertura. */
export async function getMyWishlistSummary(supabase: SupabaseClient): Promise<WishlistSummary | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_wishlist_summary");
  if (error) {
    logFailure("get_my_wishlist_summary", startedAt, error);
    return null;
  }
  const parsed = parseWishlistSummary(data);
  if (!parsed) logFailure("get_my_wishlist_summary", startedAt, null);
  return parsed;
}
