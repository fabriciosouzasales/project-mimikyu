"use server";

import {
  ANY_FINISH,
  type SetWishResult,
  type SpeciesWishCardsPage,
  SPECIES_CARDS_PAGE_SIZE,
  type WishFailureReason,
  type WishVariantOption,
  entryIdsOfVariant,
  variantRemovalPlan,
  normalizeId,
  normalizeLanguageCode,
  parseFinishKey,
  parseFinishVariantOptions,
  parseSpeciesCardsPage,
  parseVariantOptions,
  wishFailureReason,
  wishFinishKey,
  wishedCardIds,
} from "@/lib/wishlist/wishlist";
import { getMyWishedByCard, getMyWishedPositionKeys, getMyWishedVariants } from "@/lib/wishlist/wishlist-queries";
import {
  BULK_WISH_LIMIT,
  type BulkConfirmationSummary,
  type BulkItem,
  type BulkPosition,
  type BulkScope,
  type BulkSelectionRequest,
  buildBulkItems,
  parseBulkSelectionRequests,
  parseCatalogVariantsByCard,
  resolveBulkConfirmation,
  summarizeBulkAdd,
  summarizeBulkConfirmation,
} from "@/lib/wishlist/wishlist-bulk";
import { getMyCollection, getMyCollectionPositions } from "@/lib/colecoes/colecoes-queries";
import { type WishRemoveSummary, parseWishRemoveIds, summarizeWishRemove } from "@/lib/wishlist/wishlist-selection";
import { finishBadge, parseMasterSetPositions } from "@/lib/colecoes/master-set";
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

export type RemoveSelectedWishesResult = { ok: true; summary: WishRemoveSummary } | { ok: false; reason: WishFailureReason };

/**
 * W8: remove os desejos SELECIONADOS na Lista de desejos — por id exato do registro
 * (variante + idioma), nunca por carta ou variante: outros idiomas da mesma variante ficam.
 * Uma chamada só (5346 `remove_my_wishlist_entries`, até 500; aqui até 100): o banco remove
 * apenas linhas do usuário da sessão e ignora ids alheios ou inexistentes sem revelar nada.
 * Pedido malformado (vazio, id inválido, acima do teto) não remove nada. Repetir é seguro:
 * o que já saiu volta como "já não estava na lista". Só toca a Lista de desejos.
 */
export async function removeSelectedWishes(entryIds: string[]): Promise<RemoveSelectedWishesResult> {
  const ids = parseWishRemoveIds(entryIds);
  if (!ids) return { ok: false, reason: "invalid" };

  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("remove_my_wishlist_entries", { p_entry_ids: ids });
  const summary = error ? null : summarizeWishRemove(ids.length, data);
  if (!summary) {
    logWrite("remove_my_wishlist_entries", startedAt, error?.code);
    return { ok: false, reason: wishFailureReason(error?.code) };
  }
  return { ok: true, summary };
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

export type BinderWishRead = { variants: string[]; positions: string[] };

/**
 * W5 (Fichário): estado agregado dos marcadores dos bolsos carregados — uma chamada por
 * lote de páginas, nunca por bolso. Variantes (5346) para bolsos ocupados e reservas de
 * variante exata; posições carta + acabamento (5348) para as demais reservas. Só lê:
 * nada aqui conhece fichário, bolso ou exemplar. `null` = indisponível.
 */
export async function readBinderWishState(variantIds: string[], cardIds: string[]): Promise<BinderWishRead | null> {
  if (!Array.isArray(variantIds) || !Array.isArray(cardIds)) return null;
  if (variantIds.length > 2000 || cardIds.length > 2000) return null;
  if (variantIds.length === 0 && cardIds.length === 0) return { variants: [], positions: [] };
  const supabase = await createClient();
  const [variants, positions] = await Promise.all([getMyWishedVariants(supabase, variantIds), getMyWishedPositionKeys(supabase, cardIds)]);
  if (!variants || !positions) return null;
  return { variants: [...variants], positions: [...positions] };
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

// ---------------------------------------------------------------------------
// W7 — faltantes em lote (Set padrão e Master Set)
// ---------------------------------------------------------------------------

export type MissingWishPreview =
  | { ok: true; scope: BulkScope; total: number; items: BulkItem[] }
  | { ok: false; reason: WishFailureReason };

/**
 * W7: prévia dos faltantes de uma coleção do usuário (Set padrão ou Master Set) para a
 * inclusão em lote. Só LÊ, sempre em lote (nunca uma chamada por carta):
 *  1. posições que faltam (5169 ou 5189/5198, filtro MISSING, até 500);
 *  2. variantes ativas candidatas de todas as cartas (5352, uma chamada);
 *  3. o que já está na lista (5346 por carta no Set; 5348 por carta + acabamento no Master Set).
 * Classifica cada posição em direta / escolha / já na lista / sem variante. Nada é gravado
 * e nada liga desejo a coleção (C-211). Coleção alheia = "invalid" (o banco não distingue).
 * `unavailable` = alguma leitura falhou ou a 5352 ainda não existe no LIVE.
 */
export async function previewMissingWishes(collectionId: string): Promise<MissingWishPreview> {
  const id = normalizeId(collectionId);
  if (!id) return { ok: false, reason: "invalid" };
  const supabase = await createClient();
  return loadMissingWishItems(supabase, id);
}

/**
 * Núcleo da prévia, usado também pela confirmação (FIX-03): a coleção precisa ser do
 * usuário da sessão (`get_my_collection` só devolve as próprias); as posições faltantes, as
 * variantes candidatas e o estado da Lista são sempre lidos AGORA, no servidor.
 */
async function loadMissingWishItems(supabase: Awaited<ReturnType<typeof createClient>>, id: string): Promise<MissingWishPreview> {
  const startedAt = Date.now();
  const collection = await getMyCollection(supabase, id);
  if (collection === null) return { ok: false, reason: "unavailable" };
  if (collection === undefined) return { ok: false, reason: "invalid" };

  let scope: BulkScope;
  let total: number;
  let positions: BulkPosition[];
  if (collection.completionPolicy === "MASTER_SET") {
    const { data, error } = await supabase.rpc("get_my_master_set_positions", {
      p_collection_id: id,
      p_filter: "MISSING",
      p_limit: BULK_WISH_LIMIT,
      p_offset: 0,
    });
    if (error || !Array.isArray(data)) {
      console.error(JSON.stringify({ scope: "wishlist.read", fn: "get_my_master_set_positions", ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE" }));
      return { ok: false, reason: "unavailable" };
    }
    const page = parseMasterSetPositions(data);
    scope = "master";
    total = page.total;
    positions = page.items
      .filter((position) => !position.isSatisfied)
      .map((position) => ({
        key: position.key,
        cardId: position.cardId,
        cardName: position.cardName,
        collectorNumber: position.collectorNumber,
        collectorTotal: position.collectorTotal,
        imagePath: position.imagePath,
        finishKey: wishFinishKey(position.variantTypeId) ?? ANY_FINISH,
        finishLabel: finishBadge(position),
        isSecret: position.isSecret,
      }));
  } else if (collection.completionPolicy === "STANDARD_SET" && collection.cardSetCode) {
    const page = await getMyCollectionPositions(supabase, id, "faltam");
    if (!page) return { ok: false, reason: "unavailable" };
    scope = "set";
    total = page.total;
    positions = page.items
      .filter((position) => !position.isSatisfied)
      .map((position) => ({
        key: position.cardId.toLowerCase(),
        cardId: position.cardId.toLowerCase(),
        cardName: position.cardName,
        collectorNumber: position.collectorNumber,
        collectorTotal: position.collectorTotal,
        imagePath: position.imagePath,
        finishKey: null,
        finishLabel: null,
        isSecret: false,
      }));
  } else {
    return { ok: false, reason: "invalid" };
  }

  if (positions.length === 0) return { ok: true, scope, total: 0, items: [] };

  const cardIds = [...new Set(positions.map((position) => position.cardId))];
  const [variantsRead, wishedCards, wishedPositions] = await Promise.all([
    supabase.rpc("get_catalog_card_variants_for_cards", { p_card_ids: cardIds }),
    scope === "set" ? getMyWishedByCard(supabase, cardIds) : Promise.resolve(null),
    scope === "master" ? getMyWishedPositionKeys(supabase, cardIds) : Promise.resolve(null),
  ]);
  const variantsByCard = variantsRead.error ? null : parseCatalogVariantsByCard(variantsRead.data);
  if (!variantsByCard) {
    console.error(JSON.stringify({ scope: "wishlist.read", fn: "get_catalog_card_variants_for_cards", ms: Date.now() - startedAt, code: variantsRead.error?.code ?? "BAD_SHAPE" }));
    return { ok: false, reason: wishFailureReason(variantsRead.error?.code) };
  }
  if (scope === "set" ? wishedCards === null : wishedPositions === null) return { ok: false, reason: "unavailable" };

  return { ok: true, scope, total, items: buildBulkItems(positions, variantsByCard, { cards: wishedCardIds(wishedCards), positions: wishedPositions }) };
}

export type AddMissingWishesResult = { ok: true; summary: BulkConfirmationSummary } | { ok: false; reason: WishFailureReason };

/**
 * W7 (FIX-03): confirma o lote. O navegador envia só a coleção e, por posição, a variante
 * escolhida; a elegibilidade é refeita aqui, sem confiar no navegador:
 *  1. a coleção precisa ser do usuário da sessão;
 *  2. as posições faltantes, as candidatas e o estado da Lista são recalculados (mesmas
 *     leituras em lote da prévia);
 *  3. só entram posições que ainda faltam, sem desejo, com a variante entre as candidatas da
 *     posição (no Master Set, só do acabamento da posição).
 * Posição preenchida desde a prévia → ignorada; desejo incluído em outra aba → "já existia";
 * variante incompatível ou pedido repetido → recusado. Uma gravação (5352), idempotente,
 * sempre "qualquer idioma"; só toca a Lista de desejos. Nada recusado conta como incluído.
 */
export async function addMissingWishes(input: { collectionId: string; selections: BulkSelectionRequest[] }): Promise<AddMissingWishesResult> {
  const id = normalizeId(input?.collectionId);
  const requests = parseBulkSelectionRequests(input?.selections);
  if (!id || !requests) return { ok: false, reason: "invalid" };

  const supabase = await createClient();
  const fresh = await loadMissingWishItems(supabase, id);
  if (!fresh.ok) return fresh;

  const plan = resolveBulkConfirmation(fresh.items, requests);
  if (plan.variantIds.length === 0) return { ok: true, summary: summarizeBulkConfirmation(plan, null) };

  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("add_my_wishlist_entries", { p_card_variant_ids: plan.variantIds });
  const added = error ? null : summarizeBulkAdd(plan.variantIds, data);
  if (!added) {
    logWrite("add_my_wishlist_entries", startedAt, error?.code);
    return { ok: false, reason: wishFailureReason(error?.code) };
  }
  const summary = summarizeBulkConfirmation(plan, added);
  if (!summary.complete) logWrite("add_my_wishlist_entries", startedAt, added.missing > 0 ? "PARTIAL_MISSING" : summary.rejected > 0 ? "REJECTED_SELECTION" : "PARTIAL_UNAVAILABLE");
  return { ok: true, summary };
}

export type SpeciesWishCards = SpeciesWishCardsPage & { wished: string[] };

/**
 * W4 (Pokédex, lacuna L3): uma página das cartas ativas de uma espécie (5349) e quais
 * delas já têm desejo (5346, em lote para a página) — base da escolha EXPLÍCITA da
 * carta; a variante segue a regra da W1 (5163). Nada é gravado aqui e nada liga o
 * desejo à Pokédex. `null` = indisponível (inclusive antes de 5349 existir no LIVE).
 */
export async function readSpeciesWishCards(speciesId: string, offset: number): Promise<SpeciesWishCards | null> {
  const id = normalizeId(speciesId);
  if (!id || !Number.isInteger(offset) || offset < 0 || offset > 10000) return null;
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_catalog_cards_for_species", {
    p_species_id: id,
    p_limit: SPECIES_CARDS_PAGE_SIZE,
    p_offset: offset,
  });
  const page = error ? null : parseSpeciesCardsPage(data);
  if (!page) {
    console.error(JSON.stringify({ scope: "wishlist.read", fn: "get_catalog_cards_for_species", ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE" }));
    return null;
  }
  if (page.items.length === 0) return { ...page, wished: [] };
  const map = await getMyWishedByCard(supabase, page.items.map((card) => card.cardId));
  if (!map) return null;
  const wished = page.items.filter((card) => (map.get(card.cardId)?.size ?? 0) > 0).map((card) => card.cardId);
  return { ...page, wished };
}
