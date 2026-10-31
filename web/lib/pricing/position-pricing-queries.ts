import type { SupabaseClient } from "@supabase/supabase-js";
import type { VariantPrice } from "./variant-pricing";
import { getVariantPrices } from "./variant-pricing-queries";
import {
  type CardVariantRow,
  type PositionVariant,
  type RepresentativeVariantRow,
  masterPositionVariants,
  parseCardVariantRows,
  parseRepresentativeRows,
  pokedexPositionVariants,
  positionVariantIds,
  setPositionVariants,
} from "./position-pricing";

/** Preço pronto para a etiqueta de uma posição: variante resolvida + preço da 3983. */
export type PositionPrice = PositionVariant & { price: VariantPrice };

/** Forma serializável (Record) — atravessa a fronteira de Client Components. */
export type PositionPrices = Record<string, PositionPrice>;

/** Teto por chamada de 5333/5334. */
const IDS_PER_CALL = 500;

function logFailure(fn: string, startedAt: number, error: { code?: string } | null) {
  console.error(JSON.stringify({ scope: "pricing.positions.read", fn, ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE" }));
}

function chunks(ids: readonly string[]): string[][] {
  const unique = [...new Set(ids.map((id) => id.toLowerCase()))];
  const out: string[][] = [];
  for (let i = 0; i < unique.length; i += IDS_PER_CALL) out.push(unique.slice(i, i + IDS_PER_CALL));
  return out;
}

/** 5333 em blocos de até 500 cartas. `null` = falha (a grade segue sem preço). */
async function readCardVariants(supabase: SupabaseClient, collectionId: string, cardIds: readonly string[]): Promise<CardVariantRow[] | null> {
  const blocks = chunks(cardIds);
  if (blocks.length === 0) return [];
  const startedAt = Date.now();
  const results = await Promise.all(
    blocks.map(async (block) => {
      const { data, error } = await supabase.rpc("get_my_collection_card_variants", { p_collection_id: collectionId, p_card_ids: block });
      const rows = error ? null : parseCardVariantRows(data);
      if (!rows) logFailure("get_my_collection_card_variants", startedAt, error);
      return rows;
    }),
  );
  if (results.some((rows) => rows === null)) return null;
  return results.flat() as CardVariantRow[];
}

/** 5334 em blocos de até 500 posições. `null` = falha. */
async function readRepresentatives(
  supabase: SupabaseClient,
  collectionId: string,
  positionIds: readonly string[],
): Promise<RepresentativeVariantRow[] | null> {
  const blocks = chunks(positionIds);
  if (blocks.length === 0) return [];
  const startedAt = Date.now();
  const results = await Promise.all(
    blocks.map(async (block) => {
      const { data, error } = await supabase.rpc("get_my_pokedex_representative_variants", {
        p_collection_id: collectionId,
        p_position_ids: block,
      });
      const rows = error ? null : parseRepresentativeRows(data);
      if (!rows) logFailure("get_my_pokedex_representative_variants", startedAt, error);
      return rows;
    }),
  );
  if (results.some((rows) => rows === null)) return null;
  return results.flat() as RepresentativeVariantRow[];
}

/** Variantes resolvidas + um lote de preços (3983, blocos de 100). Sem preço válido, a posição fica de fora. */
async function attachPrices(supabase: SupabaseClient, variants: Map<string, PositionVariant>): Promise<PositionPrices | null> {
  if (variants.size === 0) return {};
  const prices = await getVariantPrices(supabase, positionVariantIds(variants));
  if (!prices) return null;
  const out: PositionPrices = {};
  for (const [key, variant] of variants) {
    const price = prices.get(variant.cardVariantId);
    if (price) out[key] = { ...variant, price };
  }
  return out;
}

/**
 * Set padrão: preços das posições exibidas que têm exemplar (chave = card_id).
 * Uma leitura de variantes da página + um lote de preços. `null` = leitura
 * indisponível (a grade continua, só sem etiquetas).
 */
export async function getSetPositionPrices(
  supabase: SupabaseClient,
  collectionId: string,
  positions: readonly { cardId: string; copiesInCollection: number }[],
): Promise<PositionPrices | null> {
  const owned = positions.filter((position) => position.copiesInCollection > 0).map((position) => position.cardId);
  if (owned.length === 0) return {};
  const rows = await readCardVariants(supabase, collectionId, owned);
  if (!rows) return null;
  return attachPrices(supabase, setPositionVariants(rows));
}

/** Master Set: chave = `positionKey` (carta + acabamento, ou secreta genérica). */
export async function getMasterSetPositionPrices(
  supabase: SupabaseClient,
  collectionId: string,
  positions: readonly { key: string; cardId: string; variantTypeId: string | null; copiesInCollection: number }[],
): Promise<PositionPrices | null> {
  const owned = positions.filter((position) => position.copiesInCollection > 0);
  if (owned.length === 0) return {};
  const rows = await readCardVariants(supabase, collectionId, owned.map((position) => position.cardId));
  if (!rows) return null;
  return attachPrices(supabase, masterPositionVariants(rows, owned));
}

/** Pokédex: chave = pokedex_position_id; preço da variante do exemplar representante. */
export async function getPokedexPositionPrices(
  supabase: SupabaseClient,
  collectionId: string,
  positions: readonly {
    positionId: string;
    isSatisfied: boolean;
    representative: { collectorNumber: string | null; setCode: string | null } | null;
  }[],
): Promise<PositionPrices | null> {
  const owned = positions.filter((position) => position.isSatisfied && position.representative);
  if (owned.length === 0) return {};
  const rows = await readRepresentatives(supabase, collectionId, owned.map((position) => position.positionId));
  if (!rows) return null;
  return attachPrices(supabase, pokedexPositionVariants(rows, owned));
}
