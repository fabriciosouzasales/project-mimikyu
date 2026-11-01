import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type FavoriteCardsPage,
  type FavoriteReferenceValue,
  type VariantFavorite,
  FAVORITES_PAGE_SIZE,
  chunkIds,
  parseFavoriteCardsPage,
  parseFavoriteReferenceValue,
  toFavoriteIdSet,
  toVariantFavoriteMap,
} from "./card-favorites.ts";

/**
 * Leituras de favoritos de cartas (V1-10, Query 5336) — sempre como o usuário da
 * sessão (o banco resolve o dono por `auth.uid()`), em lote, nunca uma chamada por
 * carta. Falha de leitura = `null`: a grade continua, só sem corações marcados.
 * Função ausente no LIVE (`PGRST202`, 5336 ainda não aplicada) cai no mesmo caminho.
 */

function logFailure(fn: string, startedAt: number, error: { code?: string } | null) {
  console.error(JSON.stringify({ scope: "favorites.cards.read", fn, ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE" }));
}

/** Quais das cartas são favoritas (Pesquisa). Blocos de até 500 em paralelo. */
export async function getMyCardFavoriteIds(supabase: SupabaseClient, cardIds: readonly string[]): Promise<Set<string> | null> {
  const blocks = chunkIds(cardIds);
  if (blocks.length === 0) return new Set();
  const startedAt = Date.now();
  const results = await Promise.all(
    blocks.map(async (block) => {
      const { data, error } = await supabase.rpc("get_my_card_favorite_ids", { p_card_ids: block });
      if (error || !Array.isArray(data)) {
        logFailure("get_my_card_favorite_ids", startedAt, error);
        return null;
      }
      return toFavoriteIdSet(data);
    }),
  );
  if (results.some((set) => set === null)) return null;
  return new Set(results.flatMap((set) => [...(set as Set<string>)]));
}

/** Carta e estado favorito por variante (Acervo: a leitura do acervo só traz a variante). */
export async function getMyCardFavoritesByVariant(
  supabase: SupabaseClient,
  cardVariantIds: readonly (string | null | undefined)[],
): Promise<Map<string, VariantFavorite> | null> {
  const blocks = chunkIds(cardVariantIds);
  if (blocks.length === 0) return new Map();
  const startedAt = Date.now();
  const results = await Promise.all(
    blocks.map(async (block) => {
      const { data, error } = await supabase.rpc("get_my_card_favorites_by_variant", { p_card_variant_ids: block });
      if (error || !Array.isArray(data)) {
        logFailure("get_my_card_favorites_by_variant", startedAt, error);
        return null;
      }
      return toVariantFavoriteMap(data);
    }),
  );
  if (results.some((map) => map === null)) return null;
  return new Map(results.flatMap((map) => [...(map as Map<string, VariantFavorite>)]));
}

/** Uma página de "Cartas favoritas", mais recentes primeiro. */
export async function getMyFavoriteCards(supabase: SupabaseClient, page: number): Promise<FavoriteCardsPage | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_favorite_cards", {
    p_limit: FAVORITES_PAGE_SIZE,
    p_offset: (page - 1) * FAVORITES_PAGE_SIZE,
  });
  const parsed = error ? null : parseFavoriteCardsPage(data);
  if (!parsed) logFailure("get_my_favorite_cards", startedAt, error);
  return parsed;
}

/**
 * Card Sets com cartas favoritas (4º indicador de Cartas favoritas, CORRECTION-13):
 * quantos Card Sets distintos (`card.card_set_id`) têm pelo menos uma carta ativa
 * favoritada pelo usuário (`get_my_favorite_card_set_count`, Query 5338 — PROPOSTA).
 * Uma chamada agregada no servidor, um número; nada de paginar as favoritas no cliente.
 * `null` = falha ou função ainda ausente no LIVE (`PGRST202`): o painel mostra "—".
 */
export async function getMyFavoriteCardSetCount(supabase: SupabaseClient): Promise<number | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_favorite_card_set_count");
  if (error) {
    logFailure("get_my_favorite_card_set_count", startedAt, error);
    return null;
  }
  const total = typeof data === "number" ? data : Number(data);
  return Number.isInteger(total) && total >= 0 ? total : null;
}

/**
 * No meu acervo (3º indicador, DATA CONTRACTS-17): cartas favoritas ativas com pelo
 * menos um exemplar no Inventory do próprio usuário (`get_my_favorite_owned_count`,
 * Query 5339 — PROPOSTA). Uma chamada agregada; o acervo nunca é percorrido aqui.
 * `null` = falha ou função ainda ausente no LIVE (`PGRST202`): o painel mostra "—".
 */
export async function getMyFavoriteOwnedCount(supabase: SupabaseClient): Promise<number | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_favorite_owned_count");
  if (error) {
    logFailure("get_my_favorite_owned_count", startedAt, error);
    return null;
  }
  const total = typeof data === "number" ? data : Number(data);
  return Number.isInteger(total) && total >= 0 ? total : null;
}

/**
 * Valor de referência (2º indicador, DATA CONTRACTS-17): soma de uma referência NM por
 * carta favorita ativa, com cobertura (`get_my_favorite_reference_value`, Query 5340 —
 * PROPOSTA). Uma chamada; a hierarquia de preço continua só na função canônica.
 * `null` = falha, formato inesperado ou função ausente: o painel mostra "—".
 */
export async function getMyFavoriteReferenceValue(supabase: SupabaseClient): Promise<FavoriteReferenceValue | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_favorite_reference_value");
  if (error) {
    logFailure("get_my_favorite_reference_value", startedAt, error);
    return null;
  }
  const parsed = parseFavoriteReferenceValue(data);
  if (!parsed) logFailure("get_my_favorite_reference_value", startedAt, null);
  return parsed;
}
