// Project Mimikyu — supabase/functions/_shared/pricing-justtcg/types.ts
// Tipos puros do domínio JustTCG v1 — extraídos de scripts/sync-justtcg-pricing.ts
// (Incrementos P8/P14.2/P14.4.x) para o Incremento de Atualização Diária JustTCG
// (2026-08-21), item A do pedido de Fabrício.
//
// Ponto único de verdade: scripts/sync-justtcg-pricing.ts (CLI de descoberta/matching)
// e supabase/functions/justtcg-price-refresh (Edge Function de refresh diário) importam
// exclusivamente daqui — nenhum dos dois redeclara estes tipos. Mesma disciplina já
// aplicada a supabase/functions/_shared/pricing-ptax/types.ts.
//
// Nenhum tipo aqui depende de Deno.env, SupabaseClient ou qualquer runtime específico —
// só o formato de dado devolvido pela API JustTCG v1 (https://justtcg.com/docs).

// fetch injetável — mesmo padrão de FetchLike em _shared/pricing-ptax/types.ts. Permite
// testar paginação/retry/429 100% offline, sem depender de --allow-net nem de rede real.
export type FetchLike = typeof fetch;

export type CallOutcome = "SUCCESS" | "TECHNICAL_FAILURE" | "BUDGET_STOPPED";

export type CallLogEntry = {
  sequence_number: number;
  endpoint: string;
  http_status_code: number | null;
  outcome: CallOutcome;
  error_detail: string | null;
  api_requests_remaining: number | null;
};

export type JustTcgMeta =
  | { total?: number; limit?: number; offset?: number; hasMore?: boolean }
  | null;

export type JustTcgResult<T> =
  | {
    status: "SUCCESS";
    data: T;
    meta: JustTcgMeta;
    httpStatus: number;
    apiRequestsRemaining: number | null;
  }
  | { status: "TECHNICAL_FAILURE"; httpStatus: number | null; errorDetail: string }
  | { status: "BUDGET_STOPPED" }
  | { status: "AUTH_FAILURE" };

// Uma variante = um produto (card, printing, condição específica) na JustTCG — nunca uma
// agregação por carta. `uuid` é o identificador estável preferido (fallback `id`); ver
// externalProductId em extract.ts/pagination.ts de cada chamador.
export type JustTcgVariant = {
  uuid?: string;
  id?: string;
  condition?: string;
  printing?: string;
  price?: number;
  lastUpdated?: number; // epoch seconds, conforme documentado pela JustTCG
};

export type JustTcgCard = {
  id: string;
  uuid?: string;
  name: string;
  number?: string | null;
  rarity?: string;
  variants: JustTcgVariant[];
};

// GET /v1/sets — usado hoje só pelo CLI (resolução/plano de Sets); o refresh diário nunca
// chama /sets (opera só sobre pricing_set_mapping.external_set_id já CONFIRMED, lido do
// banco). Tipo compartilhado aqui mesmo assim, por ser parte do mesmo domínio de dado
// puro da API — evita uma segunda declaração divergente se um chamador futuro precisar.
export type JustTcgSet = {
  id: string;
  name: string;
  release_date?: string;
  release_date_raw?: string;
  variants_count?: number;
};
