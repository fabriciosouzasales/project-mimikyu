"use client";

import { useEffect, useMemo, useState } from "react";
import { type VariantPrice, chunkVariantIds } from "./variant-pricing";

/**
 * Cliente do preço por variante (V1-09) — usado só pelo fichário do dono,
 * cujas páginas chegam em lotes no navegador. Acervo e coleções leem no
 * servidor (`variant-pricing-queries.ts`).
 *
 * Cache em memória por variante, válido pela sessão da página (o preço muda no
 * máximo uma vez por dia); falha de rede não envenena o cache. Chamadas
 * simultâneas para a mesma variante são deduplicadas. Blocos de até 100 ids.
 */
const cache = new Map<string, VariantPrice | null>();
const inFlight = new Map<string, Promise<void>>();

async function fetchChunk(ids: string[]): Promise<void> {
  try {
    const response = await fetch("/api/colecoes/precos", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ variantIds: ids }),
    });
    if (!response.ok) return;
    const payload = (await response.json()) as { results?: Record<string, VariantPrice> };
    if (!payload.results) return;
    for (const id of ids) cache.set(id, payload.results[id] ?? null);
  } catch {
    // Rede indisponível: nada é gravado; a próxima vista tenta de novo.
  }
}

export function loadVariantPrices(ids: readonly (string | null | undefined)[]): Promise<void> {
  const missing = chunkVariantIds(ids.filter((id) => typeof id === "string" && !cache.has(id.toLowerCase()) && !inFlight.has(id.toLowerCase())));
  const waits: Promise<void>[] = [];
  for (const id of chunkVariantIds(ids).flat()) {
    const pending = inFlight.get(id);
    if (pending) waits.push(pending);
  }
  for (const chunk of missing) {
    const request = fetchChunk(chunk).finally(() => {
      for (const id of chunk) inFlight.delete(id);
    });
    for (const id of chunk) inFlight.set(id, request);
    waits.push(request);
  }
  return Promise.all(waits).then(() => undefined);
}

/**
 * Preços das variantes informadas. Entrada ausente = ainda não lida (ou
 * leitura falhou): a interface simplesmente não mostra a etiqueta.
 * `enabled = false` não busca nada (preferência desligada).
 */
export function useVariantPrices(ids: readonly (string | null | undefined)[], enabled: boolean): ReadonlyMap<string, VariantPrice> {
  const key = chunkVariantIds(ids).flat().join(",");
  const [version, bump] = useState(0);
  useEffect(() => {
    if (!enabled || key === "") return;
    let cancelled = false;
    void loadVariantPrices(key.split(",")).then(() => {
      if (!cancelled) bump((n) => n + 1);
    });
    return () => {
      cancelled = true;
    };
  }, [enabled, key]);
  // Identidade estável entre renderizações (só muda com novos ids ou novos
  // preços): os bolsos não re-renderizam durante arraste/seleção por causa do preço.
  return useMemo(() => {
    const map = new Map<string, VariantPrice>();
    if (!enabled || key === "") return map;
    for (const id of key.split(",")) {
      const price = cache.get(id);
      if (price) map.set(id, price);
    }
    return map;
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `version` sinaliza preços recém-chegados ao cache do módulo.
  }, [enabled, key, version]);
}
