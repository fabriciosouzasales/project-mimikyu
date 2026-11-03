"use server";

import {
  ANY_FINISH,
  type SetWishResult,
  type WishFailureReason,
  type WishVariantOption,
  entryIdsOfVariant,
  variantRemovalPlan,
  normalizeId,
  normalizeLanguageCode,
  parseFinishKey,
  parseFinishVariantOptions,
  parseVariantOptions,
  wishFailureReason,
} from "@/lib/wishlist/wishlist";
import { getMyWishedByCard, getMyWishedVariants } from "@/lib/wishlist/wishlist-queries";
import { createClient } from "@/lib/supabase/server";

/**
 * Server Actions da Lista de desejos (V1-11 W1, Queries 5346/5347 — propostas).
 * - Identidade só pela sessão; o cliente envia variante/idioma/ids de desejo, nunca um
 *   `user_id`. Sem `service_role`. A autoridade é o banco (RLS + SECURITY DEFINER).
 * - Inclusão idempotente (unicidade variante + idioma); remoção idempotente.
 * - Nenhuma action toca coleção, fichário, alocação ou exemplar (C-211).
 * - Sem `revalidatePath`: a tela já mostra o novo estado; as páginas relêem na próxima
 *   navegação (mesma decisão dos favoritos).
 */

function logWrite(fn: string, startedAt: number, code: string | undefined) {
  console.error(JSON.stringify({ scope: "wishlist.write", fn, ms: Date.now() - startedAt, code: code ?? "NO_DATA" }));
}

/**
 * Marcador de VARIANTE nas grades: DEFINE o estado (não alterna).
 * - `true`: inclui "qualquer idioma" (repetir não duplica);
 * - `false`: remove o desejo da variante quando há exatamente UM; com desejos em mais de
 *   um idioma, não remove nada e responde `multiple_entries` (CORRECTION-02: nunca uma
 *   exclusão agregada silenciosa — a escolha fica na Lista de desejos).
 */
export async function setVariantWished(cardVariantId: string, wished: boolean): Promise<SetWishResult> {
  const id = normalizeId(cardVariantId);
  if (!id || typeof wished !== "boolean") return { ok: false, reason: "invalid" };

  const startedAt = Date.now();
  const supabase = await createClient();

  if (wished) {
    const { data, error } = await supabase.rpc("add_my_wishlist_entry", { p_card_variant_id: id, p_language_code: null });
    const row = Array.isArray(data) && data.length === 1 ? (data[0] as Record<string, unknown>) : null;
    // Sem id devolvido (corrida rara com uma remoção simultânea) = não confirmado.
    if (error || !row || !normalizeId(row.entry_id)) {
      logWrite("add_my_wishlist_entry", startedAt, error?.code);
      return { ok: false, reason: wishFailureReason(error?.code) };
    }
    return { ok: true, wished: true };
  }

  const state = await supabase.rpc("get_my_wishlist_state_by_variant", { p_card_variant_ids: [id] });
  if (state.error || !Array.isArray(state.data)) {
    logWrite("get_my_wishlist_state_by_variant", startedAt, state.error?.code);
    return { ok: false, reason: wishFailureReason(state.error?.code) };
  }
  const entryIds = entryIdsOfVariant(state.data, id);
  const plan = variantRemovalPlan(entryIds);
  if (plan === "none") return { ok: true, wished: false };
  if (plan === "blocked") return { ok: false, reason: "multiple_entries" };

  const { error } = await supabase.rpc("remove_my_wishlist_entries", { p_entry_ids: entryIds });
  if (error) {
    logWrite("remove_my_wishlist_entries", startedAt, error.code);
    return { ok: false, reason: wishFailureReason(error.code) };
  }
  return { ok: true, wished: false };
}

export type AddWishResult = { ok: true; entryId: string; created: boolean } | { ok: false; reason: WishFailureReason };

/** Inclusão com idioma explícito (ou `null` = qualquer). Usada no "Desfazer" da página. */
export async function addWishlistEntry(cardVariantId: string, languageCode: string | null): Promise<AddWishResult> {
  const id = normalizeId(cardVariantId);
  const language = languageCode === null ? null : normalizeLanguageCode(languageCode);
  if (!id || (languageCode !== null && language === null)) return { ok: false, reason: "invalid" };

  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("add_my_wishlist_entry", { p_card_variant_id: id, p_language_code: language });
  const row = Array.isArray(data) && data.length === 1 ? (data[0] as Record<string, unknown>) : null;
  const entryId = normalizeId(row?.entry_id);
  if (error || !row || !entryId) {
    logWrite("add_my_wishlist_entry", startedAt, error?.code);
    return { ok: false, reason: wishFailureReason(error?.code) };
  }
  return { ok: true, entryId, created: row.created === true };
}

export type RemoveWishResult = { ok: true; removed: number } | { ok: false; reason: WishFailureReason };

/** Remove desejos por id (um ou vários). Idempotente; ids alheios são ignorados pelo banco. */
export async function removeWishlistEntries(entryIds: string[]): Promise<RemoveWishResult> {
  if (!Array.isArray(entryIds)) return { ok: false, reason: "invalid" };
  const ids = [...new Set(entryIds.map(normalizeId).filter((id): id is string => id !== null))];
  if (ids.length === 0 || ids.length > 500) return { ok: false, reason: "invalid" };

  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("remove_my_wishlist_entries", { p_entry_ids: ids });
  const removed = typeof data === "number" ? data : Number(data);
  if (error || !Number.isInteger(removed) || removed < 0) {
    logWrite("remove_my_wishlist_entries", startedAt, error?.code);
    return { ok: false, reason: wishFailureReason(error?.code) };
  }
  return { ok: true, removed };
}

/** Carta → variantes desejadas, para uma grade montada no cliente (Pesquisa). `null` = indisponível. */
export async function readWishedByCard(cardIds: string[]): Promise<Record<string, string[]> | null> {
  if (!Array.isArray(cardIds) || cardIds.length === 0) return {};
  if (cardIds.length > 2000) return null;
  const supabase = await createClient();
  const map = await getMyWishedByCard(supabase, cardIds);
  if (!map) return null;
  return Object.fromEntries([...map].map(([card, set]) => [card, [...set]]));
}

/** Variantes desejadas entre as pedidas. `null` = indisponível. */
export async function readWishedVariantIds(variantIds: string[]): Promise<string[] | null> {
  if (!Array.isArray(variantIds) || variantIds.length === 0) return [];
  if (variantIds.length > 2000) return null;
  const supabase = await createClient();
  const set = await getMyWishedVariants(supabase, variantIds);
  return set ? [...set] : null;
}

export type CardWishOptions = { options: WishVariantOption[]; wished: string[] };

/**
 * Variantes ativas de uma carta (5163, leitura de catálogo para usuário autenticado) e
 * quais já estão na lista — base da escolha explícita (C-212). `null` = indisponível.
 */
export async function readCardWishOptions(cardId: string): Promise<CardWishOptions | null> {
  const id = normalizeId(cardId);
  if (!id) return null;
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_catalog_card_variants_for_picker", { p_card_id: id });
  const options = error ? null : parseVariantOptions(data);
  if (!options) {
    console.error(JSON.stringify({ scope: "wishlist.read", fn: "get_catalog_card_variants_for_picker", ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE" }));
    return null;
  }
  if (options.length === 0) return { options, wished: [] };
  const wished = await getMyWishedVariants(supabase, options.map((option) => option.variantId));
  if (!wished) return null;
  return { options, wished: [...wished] };
}

/**
 * W3 (Master Set): variantes ativas COMPATÍVEIS com a posição (carta + acabamento; 5348)
 * e quais já estão na lista. `finishKey` = id do acabamento, ou `"*"` para a posição de
 * carta secreta (qualquer acabamento). Nunca devolve variante de outro acabamento.
 * `null` = indisponível (inclusive antes de 5348 existir no LIVE).
 */
export async function readPositionWishOptions(cardId: string, finishKey: string): Promise<CardWishOptions | null> {
  const id = normalizeId(cardId);
  const finish = parseFinishKey(finishKey);
  if (!id || !finish) return null;
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_catalog_card_variants_for_finish", {
    p_card_id: id,
    p_variant_type_id: finish === ANY_FINISH ? null : finish,
  });
  const options = error ? null : parseFinishVariantOptions(data, finish);
  if (!options) {
    console.error(JSON.stringify({ scope: "wishlist.read", fn: "get_catalog_card_variants_for_finish", ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE" }));
    return null;
  }
  if (options.length === 0) return { options, wished: [] };
  const wished = await getMyWishedVariants(supabase, options.map((option) => option.variantId));
  if (!wished) return null;
  return { options, wished: [...wished] };
}
