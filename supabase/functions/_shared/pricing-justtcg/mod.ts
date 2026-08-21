// Project Mimikyu — supabase/functions/_shared/pricing-justtcg/mod.ts
// Ponto único de importação do núcleo compartilhado do cliente JustTCG v1 — Incremento
// de Atualização Diária JustTCG (2026-08-21), item A do pedido de Fabrício. Consumidores
// (scripts/sync-justtcg-pricing.ts e supabase/functions/justtcg-price-refresh) devem
// importar só por aqui — nunca os módulos internos diretamente. Mesmo padrão já usado em
// supabase/functions/_shared/pricing-ptax/mod.ts.

export type {
  CallLogEntry,
  CallOutcome,
  FetchLike,
  JustTcgCard,
  JustTcgMeta,
  JustTcgResult,
  JustTcgSet,
  JustTcgVariant,
} from "./types.ts";

export { sanitize, sanitizeJson } from "./sanitize.ts";

export { splitPrintingLanguage } from "./variant.ts";

export {
  CARDS_PAGE_LIMIT,
  DELAY_BETWEEN_REQUESTS_MS,
  GAME_CODE,
  JUSTTCG_API_BASE,
  JustTcgClient,
  MAX_REQUESTS_PER_RUN,
  RATE_LIMIT_BACKOFF_MS,
  REQUEST_TIMEOUT_MS,
} from "./client.ts";

export { fetchAllCardsForSet } from "./pagination.ts";
