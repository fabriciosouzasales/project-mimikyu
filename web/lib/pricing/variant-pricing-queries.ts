import type { SupabaseClient } from "@supabase/supabase-js";
import { type VariantPrice, type VariantPricesStatus, chunkVariantIds, parseVariantPrices } from "./variant-pricing.ts";

export type { VariantPricesStatus };

/**
 * Leitura no servidor do preço NM por variante (V1-09) — 3989
 * (`get_card_variants_pricing_summary`), com a sessão do próprio usuário
 * (nunca `service_role`). Blocos de até 100 ids.
 *
 * PRICING TIMEOUT CORRECTION-01 (2026-11-06): os blocos deixaram de sair todos
 * ao mesmo tempo — no máximo `VARIANT_PRICES_PARALLEL` (2) chamadas
 * simultâneas — e um bloco cancelado por `statement_timeout` (57014) ganha UMA
 * nova tentativa, depois de uma espera curta. Outros erros não são repetidos.
 *
 * Três estados por variante, nunca confundidos:
 *  - linha devolvida pela 3989 → cotação (ou ausência confirmada, `hasPricing = false`);
 *  - id de um bloco lido sem linha → ausência confirmada (nada na grade);
 *  - id de um bloco que falhou → `unavailableIds` (temporariamente indisponível).
 * Falha nunca vira preço zero.
 */

/** Teto de chamadas simultâneas da 3989 por leitura. */
export const VARIANT_PRICES_PARALLEL = 2;
/** Espera antes da única nova tentativa de um bloco cancelado por timeout. */
export const TIMEOUT_RETRY_DELAY_MS = 300;
const STATEMENT_TIMEOUT = "57014";

export type VariantPricesRead = {
  /** `complete` = todos os blocos lidos; `partial` = algum falhou; `unavailable` = nenhum lido. */
  status: VariantPricesStatus;
  /** Linhas dos blocos lidos (ordem dos blocos; determinística). */
  prices: Map<string, VariantPrice>;
  /** Ids dos blocos que falharam — preço temporariamente indisponível. */
  unavailableIds: string[];
};

type RpcResponse = { data: unknown; error: { code?: string } | null };
/** Só o que a leitura usa do cliente (testável sem Supabase). */
export type PricingRpc = { rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<RpcResponse> };

type ReadOptions = { wait?: (ms: number) => Promise<void> };

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/** Executa as tarefas com no máximo `limit` simultâneas; resultados na ordem das tarefas. */
export async function runLimited<T>(tasks: readonly (() => Promise<T>)[], limit: number): Promise<T[]> {
  const results = new Array<T>(tasks.length);
  let next = 0;
  const worker = async () => {
    while (next < tasks.length) {
      const index = next++;
      results[index] = await (tasks[index] as () => Promise<T>)();
    }
  };
  await Promise.all(Array.from({ length: Math.min(Math.max(1, limit), tasks.length) }, worker));
  return results;
}

async function callOnce(supabase: PricingRpc, chunk: string[]): Promise<RpcResponse> {
  try {
    return await supabase.rpc("get_card_variants_pricing_summary", { p_card_variant_ids: chunk });
  } catch {
    // Falha de transporte: mesma resposta segura de um erro (leitura indisponível).
    return { data: null, error: { code: "THROWN" } };
  }
}

/** Um bloco: até 2 chamadas (só 57014 repete). `null` = bloco indisponível. Logs sem ids. */
async function readChunk(supabase: PricingRpc, chunk: string[], wait: (ms: number) => Promise<void>): Promise<Map<string, VariantPrice> | null> {
  const startedAt = Date.now();
  let response = await callOnce(supabase, chunk);
  if (response.error?.code === STATEMENT_TIMEOUT) {
    const firstMs = Date.now() - startedAt;
    await wait(TIMEOUT_RETRY_DELAY_MS);
    const retryStartedAt = Date.now();
    response = await callOnce(supabase, chunk);
    console.warn(
      JSON.stringify({
        scope: "pricing.variants.retry",
        code: STATEMENT_TIMEOUT,
        firstMs,
        retryMs: Date.now() - retryStartedAt,
        outcome: response.error ? "failed" : "recovered",
        retryCode: response.error?.code ?? null,
        ids: chunk.length,
      }),
    );
  }
  if (response.error) {
    console.error(JSON.stringify({ scope: "pricing.variants.read", ms: Date.now() - startedAt, code: response.error.code ?? "UNKNOWN", ids: chunk.length }));
    return null;
  }
  const parsed = parseVariantPrices(response.data);
  if (!parsed) console.error(JSON.stringify({ scope: "pricing.variants.read", ms: Date.now() - startedAt, code: "BAD_SHAPE", ids: chunk.length }));
  return parsed;
}

/** Leitura com estado explícito (completa, parcial ou indisponível). */
export async function readVariantPrices(
  supabase: PricingRpc,
  ids: readonly (string | null | undefined)[],
  options: ReadOptions = {},
): Promise<VariantPricesRead> {
  const chunks = chunkVariantIds(ids);
  if (chunks.length === 0) return { status: "complete", prices: new Map(), unavailableIds: [] };
  const wait = options.wait ?? sleep;
  const results = await runLimited(
    chunks.map((chunk) => () => readChunk(supabase, chunk, wait)),
    VARIANT_PRICES_PARALLEL,
  );
  const prices = new Map<string, VariantPrice>();
  const unavailableIds: string[] = [];
  let failed = 0;
  results.forEach((map, index) => {
    if (!map) {
      failed += 1;
      unavailableIds.push(...(chunks[index] as string[]));
      return;
    }
    for (const [id, price] of map) prices.set(id, price);
  });
  const status: VariantPricesStatus = failed === 0 ? "complete" : failed === chunks.length ? "unavailable" : "partial";
  return { status, prices, unavailableIds };
}

/**
 * Contrato histórico (Acervo, Lista de desejos, coleção livre): tudo ou nada.
 * Qualquer bloco indisponível → `null` ("leitura indisponível"), para que o
 * consumidor nunca mostre "sem preço" para uma variante que só não foi lida.
 * Ganha a concorrência limitada e a nova tentativa de `readVariantPrices`.
 */
export async function getVariantPrices(
  supabase: SupabaseClient,
  ids: readonly (string | null | undefined)[],
): Promise<Map<string, VariantPrice> | null> {
  const read = await readVariantPrices(supabase, ids);
  return read.status === "complete" ? read.prices : null;
}

/** Forma serializável para Client Components (Map não atravessa a fronteira). */
export function pricesToRecord(map: Map<string, VariantPrice> | null): Record<string, VariantPrice> | null {
  if (!map) return null;
  return Object.fromEntries(map);
}
