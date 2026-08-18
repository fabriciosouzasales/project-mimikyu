"use client";

/**
 * Cliente de leitura de Pricing em lote (P12, redesenho 2026-08-18) — nunca
 * chama Supabase diretamente, só `POST /api/cards/pricing/batch` (Route
 * Handler autenticado por cookies, `web/app/api/cards/pricing/batch/route.ts`).
 * Substitui o cliente por-carta da versão anterior deste incremento
 * (`fetchCardPricing`, ícone+popover só-no-hover, descartado — o resumo
 * agora precisa existir antes de qualquer interação, então o fetch também
 * precisa ser eager, não lazy-on-interact).
 *
 * Redesenho 2026-08-18 (rodada 2, "P12 v4") — elimina o N+1 real (servidor→
 * Postgres) do modo live: o Route Handler agora chama `get_cards_pricing_summary`
 * (RPC nova, uma única consulta SQL para todos os `card_id`) em vez de
 * `get_card_pricing_snapshot` uma vez por carta. Como contrapartida, o modo
 * live deixa de trazer o detalhe completo (todas condição/tipo/mercado) — só
 * o resumo determinístico (NM + Normal + MARKET, regra do próprio RPC). O
 * modo prévia (`?pricingPreview=1`, admin) continua com o detalhe completo,
 * inalterado (mesma consulta `.in()` de sempre). `PricingCacheEntry` virou
 * union discriminada por `mode` para refletir essa assimetria de contrato.
 */

export type PricingSnapshotRow = {
  sourceCode: string;
  sourceName: string;
  priceType: string;
  originalAmount: number;
  originalCurrencyCode: string;
  equivalentBrlAmount: number | null;
  fxStatus: "CONVERTED" | "FX_RATE_UNAVAILABLE";
  fxRate: number | null;
  fxRateDate: string | null;
  equivalentLabel: string | null;
  conditionCode: string;
  conditionName: string;
  printingLabel: string;
  marketLabel: string | null;
  observedAt: string;
};

// Resumo mínimo do modo live — espelha o retorno de `get_cards_pricing_summary`
// (card_id, has_pricing, brl_amount, fx_status). `fxStatus` é `null` quando
// não existe nenhuma linha NM+Normal+MARKET para a carta (não confundir com
// `FX_RATE_UNAVAILABLE`, que significa "existe a linha, mas sem PTAX aplicável").
export type PricingLiveSummary = {
  hasPricing: boolean;
  brlAmount: number | null;
  fxStatus: "CONVERTED" | "FX_RATE_UNAVAILABLE" | null;
};

export type PricingCacheEntry =
  | { mode: "live"; summary: PricingLiveSummary }
  | { mode: "preview"; rows: PricingSnapshotRow[] };

// Mesmo racional já usado no cliente por-carta anterior: `?pricingPreview=1`
// só tem efeito se o servidor confirmar `is_admin()` (nunca decidido aqui);
// lido de `window.location.search` (não `useSearchParams()`) porque este
// código só roda no cliente, nunca durante SSR/geração estática.
let cachedPreviewFlag: boolean | null = null;
function isPricingPreviewRequested(): boolean {
  if (cachedPreviewFlag === null) {
    cachedPreviewFlag =
      typeof window !== "undefined" && new URLSearchParams(window.location.search).get("pricingPreview") === "1";
  }
  return cachedPreviewFlag;
}

// Cache em memória por `card_id`, válido pela duração da sessão da página —
// uma carta já resolvida (por qualquer grid, em qualquer página) nunca é
// buscada de novo. Só grava em caso de sucesso: uma falha de rede não
// "envenena" a carta para sempre, a próxima montagem do grid (nova página,
// nova navegação) tenta de novo.
const cache = new Map<string, PricingCacheEntry>();

export function getCachedPricingEntry(cardId: string): PricingCacheEntry | undefined {
  return cache.get(cardId);
}

/**
 * Busca o resumo de preço de uma lista de cartas numa única requisição —
 * "sem N+1 no carregamento do grid" só é cumprido porque isto é UMA chamada
 * de rede do navegador para N cartas, nunca uma por carta; e, desde a rodada
 * 2 (P12 v4), o próprio servidor resolve isso numa única consulta SQL, não
 * mais N chamadas paralelas de RPC. Ids já presentes no cache são
 * responsabilidade do chamador filtrar antes (`usePricingBatch` já faz isso);
 * chamar de novo com um id já cacheado simplesmente sobrescreve a entrada com
 * a mesma informação.
 */
export async function fetchPricingBatch(cardIds: string[]): Promise<void> {
  if (cardIds.length === 0) return;

  const preview = isPricingPreviewRequested();

  try {
    const response = await fetch(`/api/cards/pricing/batch${preview ? "?pricingPreview=1" : ""}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ cardIds }),
    });

    if (!response.ok) return;

    const payload = (await response.json()) as {
      mode?: "live" | "preview";
      results?: Record<string, PricingSnapshotRow[]> | Record<string, PricingLiveSummary>;
      error?: string;
    };

    if (payload.error || !payload.mode || !payload.results) return;

    if (payload.mode === "preview") {
      const results = payload.results as Record<string, PricingSnapshotRow[]>;
      for (const cardId of cardIds) {
        cache.set(cardId, { mode: "preview", rows: results[cardId] ?? [] });
      }
    } else {
      const results = payload.results as Record<string, PricingLiveSummary>;
      for (const cardId of cardIds) {
        cache.set(cardId, {
          mode: "live",
          summary: results[cardId] ?? { hasPricing: false, brlAmount: null, fxStatus: null },
        });
      }
    }
  } catch {
    // Falha de rede — nada é gravado no cache, próxima montagem tenta de novo.
  }
}

// --- Detalhe completo sob demanda (modo live) ---------------------------
//
// Desde a rodada 2 (P12 v4), o resumo em lote do modo live não traz mais o
// detalhe completo (só NM+Normal+MARKET). O popover de detalhe, quando aberto
// para uma carta em modo live, busca sob demanda pelo contrato por-carta já
// existente e inalterado (`GET /api/cards/[cardId]/pricing`, P11/P12) — nunca
// eager, só na interação (hover/foco/toque que abre o popover). Cache
// separado do resumo em lote, também por `card_id`, para não refazer a busca
// se o mesmo popover for reaberto na mesma sessão da página.
const liveDetailCache = new Map<string, PricingSnapshotRow[]>();

export function getCachedLiveDetail(cardId: string): PricingSnapshotRow[] | undefined {
  return liveDetailCache.get(cardId);
}

export async function fetchLiveDetail(cardId: string): Promise<PricingSnapshotRow[]> {
  const cached = liveDetailCache.get(cardId);
  if (cached) return cached;

  try {
    const response = await fetch(`/api/cards/${cardId}/pricing`);
    if (!response.ok) return [];

    const payload = (await response.json()) as { mode?: "live" | "preview"; rows?: PricingSnapshotRow[]; error?: string };
    if (payload.error || !payload.rows) return [];

    liveDetailCache.set(cardId, payload.rows);
    return payload.rows;
  } catch {
    return [];
  }
}
