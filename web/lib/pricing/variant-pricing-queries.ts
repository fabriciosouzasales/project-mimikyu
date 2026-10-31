import type { SupabaseClient } from "@supabase/supabase-js";
import { type VariantPrice, chunkVariantIds, parseVariantPrices } from "./variant-pricing";

/**
 * Leitura no servidor do preço NM por variante (V1-09) — 3983, com a sessão
 * do próprio usuário (nunca `service_role`). Blocos de até 100 ids em
 * paralelo. Qualquer falha devolve `null` ("leitura indisponível"): a página
 * continua funcionando, só sem preço — nunca bloqueia Acervo ou coleção.
 */
export async function getVariantPrices(
  supabase: SupabaseClient,
  ids: readonly (string | null | undefined)[],
): Promise<Map<string, VariantPrice> | null> {
  const chunks = chunkVariantIds(ids);
  if (chunks.length === 0) return new Map();
  const startedAt = Date.now();
  const results = await Promise.all(
    chunks.map(async (chunk) => {
      const { data, error } = await supabase.rpc("get_card_variants_pricing_summary", { p_card_variant_ids: chunk });
      if (error) {
        console.error(JSON.stringify({ scope: "pricing.variants.read", ms: Date.now() - startedAt, code: error.code ?? "UNKNOWN", ids: chunk.length }));
        return null;
      }
      const parsed = parseVariantPrices(data);
      if (!parsed) console.error(JSON.stringify({ scope: "pricing.variants.read", ms: Date.now() - startedAt, code: "BAD_SHAPE", ids: chunk.length }));
      return parsed;
    }),
  );
  if (results.some((result) => result === null)) return null;
  const merged = new Map<string, VariantPrice>();
  for (const map of results) for (const [id, price] of map as Map<string, VariantPrice>) merged.set(id, price);
  return merged;
}

/** Forma serializável para Client Components (Map não atravessa a fronteira). */
export function pricesToRecord(map: Map<string, VariantPrice> | null): Record<string, VariantPrice> | null {
  if (!map) return null;
  return Object.fromEntries(map);
}
