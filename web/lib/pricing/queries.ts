import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Contrato de `get_pricing_admin_overview()` (migration 3939,
 * `CONFIRMADO EXECUTADO`) — RPC agregada admin-only que devolve, numa
 * única chamada, todos os KPIs da Visão Geral do Pricing Admin (Bloco 1,
 * 2026-08-22). Nenhum destes números é calculado no frontend — todas as
 * agregações (contagens, cobertura %, mínimo de next_due_at) são feitas em
 * SQL, dentro da própria função.
 */
export type PricingAdminOverview = {
  sources: { active: number; total: number };
  mappings: {
    confirmed: number;
    pending: number;
    not_found: number;
    total: number;
    coverage_pct: number | null;
  };
  products_count: number;
  observations_count: number;
  last_sync_run: {
    id: string;
    run_type: string;
    status: string;
    finished_at: string | null;
    triggered_by: string;
  } | null;
  sets: {
    total: number;
    healthy: number;
    problem: number;
    paused: number;
    next_due_at: string | null;
  };
  refresh_policy: Array<{
    pricing_source_id: string;
    pricing_source_code: string;
    pricing_source_name: string;
    frequency_days: number;
  }>;
  dispatcher: { active: boolean; schedule: string } | null;
};

/**
 * Busca a Visão Geral do Pricing Admin — `null` em caso de erro (RPC
 * rejeitada, rede) para que a página decida o estado de erro, nunca lança.
 * Chamador já passou por `requirePricingAdmin()`, então um `null` aqui é
 * sempre falha de rede/RPC, não falta de permissão.
 */
export async function getPricingAdminOverview(supabase: SupabaseClient): Promise<PricingAdminOverview | null> {
  const { data, error } = await supabase.rpc("get_pricing_admin_overview");

  if (error || !data) {
    return null;
  }

  return data as PricingAdminOverview;
}

// ---------------------------------------------------------------------------
// Visão Geral v2 (migration 3945/3946, 2026-08-23) — 2 RPCs de série
// temporal para a faixa de gráficos do "dashboard gerencial de verdade"
// pedido por Fabrício. `admin_get_pricing_coverage_trend` devolve só
// `cum_confirmed` por dia (SEM `cum_total`) — decisão explícita de
// Fabrício durante a implementação: `pricing_card_mapping.created_at` é
// ele mesmo um artefato de backfill em 3 dias (17/19/20-08), não
// crescimento orgânico do catálogo; reconstruir "total histórico" a
// partir dele enganaria mesmo sendo tecnicamente "real" (a curva sugeriria
// catálogo vazio antes do backfill). O frontend combina `cum_confirmed`
// com o total FIXO atual (`PricingAdminOverview.mappings.total`) e rotula
// o gráfico como "Evolução das Confirmações sobre a base atual", nunca
// como "cobertura histórica". `admin_get_pricing_sync_run_daily` devolve
// contagem diária por status (`COMPLETED`/`FAILED`/`COMPLETED_WITH_ERRORS`).
// Gráfico C (Saúde dos Sets) não tem RPC própria — é o retrato atual já
// presente em `PricingAdminOverview.sets`.
// ---------------------------------------------------------------------------

export type PricingCoverageTrendPoint = { day: string; cumConfirmed: number };

type PricingCoverageTrendRawPoint = { day: string; cum_confirmed: number };

/** Série diária cumulativa de confirmações — `null` em erro de rede/RPC (mesmo padrão de `getPricingAdminOverview`). */
export async function getPricingCoverageTrend(
  supabase: SupabaseClient,
  days = 30,
): Promise<PricingCoverageTrendPoint[] | null> {
  const { data, error } = await supabase.rpc("admin_get_pricing_coverage_trend", { p_days: days });
  if (error || !data) return null;
  return (data as PricingCoverageTrendRawPoint[]).map((row) => ({ day: row.day, cumConfirmed: row.cum_confirmed }));
}

export type PricingSyncRunDailyStatus = "COMPLETED" | "COMPLETED_WITH_ERRORS" | "FAILED";

export type PricingSyncRunDailyPoint = { day: string; status: PricingSyncRunDailyStatus; count: number };

/** Contagem diária de execuções por status — `null` em erro de rede/RPC. */
export async function getPricingSyncRunDaily(
  supabase: SupabaseClient,
  days = 14,
): Promise<PricingSyncRunDailyPoint[] | null> {
  const { data, error } = await supabase.rpc("admin_get_pricing_sync_run_daily", { p_days: days });
  if (error || !data) return null;
  return data as PricingSyncRunDailyPoint[];
}

/**
 * Consumo diário da API (migration 3947, Visão Geral v3.2, 2026-08-23) —
 * substitui "Saúde dos Sets" na faixa principal de gráficos (pedido de
 * Fabrício: essa informação já está suficientemente representada no Hero e
 * no KPI dedicado). `admin_get_pricing_api_usage_daily` soma
 * `pricing_sync_run.requests_made` por dia — mesmo padrão sem
 * `generate_series` de `admin_get_pricing_sync_run_daily`, então dias sem
 * execução simplesmente não aparecem (nenhum preenchimento artificial).
 */
export type PricingApiUsagePoint = { day: string; requests: number };

type PricingApiUsageRawPoint = { day: string; requests: number | null };

/** Série diária de requests feitos à API de preços — `null` em erro de rede/RPC. */
export async function getPricingApiUsageDaily(
  supabase: SupabaseClient,
  days = 30,
): Promise<PricingApiUsagePoint[] | null> {
  const { data, error } = await supabase.rpc("admin_get_pricing_api_usage_daily", { p_days: days });
  if (error || !data) return null;
  return (data as PricingApiUsageRawPoint[]).map((row) => ({ day: row.day, requests: row.requests ?? 0 }));
}

// ---------------------------------------------------------------------------
// Bloco 2 — Pendências + Resolução de Mapeamentos (migration 3940,
// CONFIRMADO EXECUTADO 2026-08-22). Três RPCs admin-only:
// admin_list_pricing_pending_mappings (listagem paginada/filtrada),
// admin_get_pricing_mapping_detail (detalhe completo de um mapping) e
// admin_resolve_pricing_mapping (write atômico, consumido via Server Action
// em app/pricing/resolucao-mapeamentos/actions.ts — não aqui, esta camada é
// só leitura, mesmo padrão de lib/catalogo/queries.ts).
// ---------------------------------------------------------------------------

export const PRICING_PENDING_MAPPINGS_PAGE_SIZE = 20;

/** Vocabulário fechado desta fila — REJECTED/CONFIRMED nunca aparecem em Pendências (decisão de Fabrício: "NOT_FOUND permanece dentro de Pendências"). */
export type PricingPendingMappingStatus = "PENDING" | "NOT_FOUND";

export type PricingPendingMappingItem = {
  id: string;
  cardId: string;
  cardName: string;
  collectorNumber: string;
  collectorTotal: number | null;
  cardSetId: string;
  cardSetCode: string;
  cardSetName: string;
  pricingSourceId: string;
  pricingSourceCode: string;
  matchStatus: PricingPendingMappingStatus;
  identityCount: number;
  lastCheckedAt: string | null;
};

type PricingPendingMappingRawRow = {
  id: string;
  card_id: string;
  card_name: string;
  collector_number: string;
  collector_total: number | null;
  card_set_id: string;
  card_set_code: string;
  card_set_name: string;
  pricing_source_id: string;
  pricing_source_code: string;
  match_status: PricingPendingMappingStatus;
  identity_count: number;
  last_checked_at: string | null;
  total_count: number;
};

/**
 * Listagem paginada/filtrada server-side da fila de Pendências —
 * `admin_list_pricing_pending_mappings` já trava o vocabulário de status a
 * PENDING/NOT_FOUND no próprio SQL (defesa em profundidade: mesmo que este
 * chamador não filtre nada, a RPC nunca vaza CONFIRMED/REJECTED). Em erro,
 * retorna `{ items: [], totalCount: 0 }` — mesmo contrato de
 * `getLogAtualizacoes`, nunca lança.
 */
export async function getPricingPendingMappings(
  supabase: SupabaseClient,
  options: {
    status?: PricingPendingMappingStatus[];
    cardSetId?: string;
    search?: string;
    limit?: number;
    offset?: number;
  },
): Promise<{ items: PricingPendingMappingItem[]; totalCount: number }> {
  const { data, error } = await supabase.rpc("admin_list_pricing_pending_mappings", {
    p_status: options.status && options.status.length > 0 ? options.status : null,
    p_card_set_id: options.cardSetId || null,
    p_search: options.search?.trim() || null,
    p_limit: options.limit ?? PRICING_PENDING_MAPPINGS_PAGE_SIZE,
    p_offset: options.offset ?? 0,
  });

  if (error || !data) {
    return { items: [], totalCount: 0 };
  }

  const rows = data as PricingPendingMappingRawRow[];
  return {
    items: rows.map((row) => ({
      id: row.id,
      cardId: row.card_id,
      cardName: row.card_name,
      collectorNumber: row.collector_number,
      collectorTotal: row.collector_total,
      cardSetId: row.card_set_id,
      cardSetCode: row.card_set_code,
      cardSetName: row.card_set_name,
      pricingSourceId: row.pricing_source_id,
      pricingSourceCode: row.pricing_source_code,
      matchStatus: row.match_status,
      identityCount: row.identity_count,
      lastCheckedAt: row.last_checked_at,
    })),
    totalCount: rows[0]?.total_count ?? 0,
  };
}

export type PricingCardSetOption = { id: string; code: string; name: string };

/** Opções para o filtro "Set" de Pendências — mesmo padrão enxuto de `getGameOptions`. */
export async function getPricingCardSetOptions(supabase: SupabaseClient): Promise<PricingCardSetOption[]> {
  const { data, error } = await supabase
    .from("card_set")
    .select("id, code, name")
    .order("release_date", { ascending: false });

  if (error || !data) {
    return [];
  }

  return data as PricingCardSetOption[];
}

export type PricingMappingDetailPrice = {
  conditionId: string;
  priceType: string;
  currencyCode: string;
  marketLabel: string | null;
  price: number;
  observedAt: string;
};

export type PricingMappingDetailIdentity = {
  id: string;
  externalCardId: string;
  externalCardName: string;
  identityRole: string;
  canonicalIdentityId: string | null;
  matchStatus: string;
  matchMethod: string | null;
  matchEvidence: unknown;
  cardVariantTypeId: string | null;
  cardVariantTypeName: string | null;
  externalVariantKey: string | null;
  lastCheckedAt: string | null;
  prices: PricingMappingDetailPrice[];
};

export type PricingMappingDetail = {
  mapping: {
    id: string;
    matchStatus: string;
    matchMethod: string | null;
    externalCardId: string | null;
    externalCardName: string | null;
    lastCheckedAt: string | null;
    pricingSourceId: string;
    pricingSourceCode: string;
  };
  card: {
    id: string;
    name: string;
    collectorNumber: string;
    collectorTotal: number | null;
    cardSetId: string;
    cardSetCode: string;
    cardSetName: string;
  };
  localVariants: Array<{ id: string; variantTypeId: string; code: string; name: string; isDefault: boolean }>;
  identities: PricingMappingDetailIdentity[];
  /** true quando a carta não tem nenhum card_variant local — sinaliza a UI a mostrar o CTA para o Catálogo Editorial (nunca criado pelo Pricing). */
  missingVariant: boolean;
};

/**
 * Detalhe completo de um mapping para a tela de Resolução —
 * `admin_get_pricing_mapping_detail` já devolve tudo pré-montado em jsonb
 * (carta, variantes locais, candidatas externas com roles/qualifiers/preços,
 * flag missing_variant) numa única chamada. `null` em erro/não encontrado —
 * a página decide o estado (mapping removido/inacessível), nunca lança.
 */
export async function getPricingMappingDetail(
  supabase: SupabaseClient,
  mappingId: string,
): Promise<PricingMappingDetail | null> {
  const { data, error } = await supabase.rpc("admin_get_pricing_mapping_detail", { p_mapping_id: mappingId });

  if (error || !data) {
    return null;
  }

  const raw = data as {
    mapping: {
      id: string;
      match_status: string;
      match_method: string | null;
      external_card_id: string | null;
      external_card_name: string | null;
      last_checked_at: string | null;
      pricing_source_id: string;
      pricing_source_code: string;
    };
    card: {
      id: string;
      name: string;
      collector_number: string;
      collector_total: number | null;
      card_set_id: string;
      card_set_code: string;
      card_set_name: string;
    };
    local_variants: Array<{ id: string; variant_type_id: string; code: string; name: string; is_default: boolean }>;
    identities: Array<{
      id: string;
      external_card_id: string;
      external_card_name: string;
      identity_role: string;
      canonical_identity_id: string | null;
      match_status: string;
      match_method: string | null;
      match_evidence: unknown;
      card_variant_type_id: string | null;
      card_variant_type_name: string | null;
      external_variant_key: string | null;
      last_checked_at: string | null;
      prices: Array<{
        condition_id: string;
        price_type: string;
        currency_code: string;
        market_label: string | null;
        price: number;
        observed_at: string;
      }>;
    }>;
    missing_variant: boolean;
  };

  return {
    mapping: {
      id: raw.mapping.id,
      matchStatus: raw.mapping.match_status,
      matchMethod: raw.mapping.match_method,
      externalCardId: raw.mapping.external_card_id,
      externalCardName: raw.mapping.external_card_name,
      lastCheckedAt: raw.mapping.last_checked_at,
      pricingSourceId: raw.mapping.pricing_source_id,
      pricingSourceCode: raw.mapping.pricing_source_code,
    },
    card: {
      id: raw.card.id,
      name: raw.card.name,
      collectorNumber: raw.card.collector_number,
      collectorTotal: raw.card.collector_total,
      cardSetId: raw.card.card_set_id,
      cardSetCode: raw.card.card_set_code,
      cardSetName: raw.card.card_set_name,
    },
    localVariants: raw.local_variants.map((v) => ({
      id: v.id,
      variantTypeId: v.variant_type_id,
      code: v.code,
      name: v.name,
      isDefault: v.is_default,
    })),
    identities: raw.identities.map((i) => ({
      id: i.id,
      externalCardId: i.external_card_id,
      externalCardName: i.external_card_name,
      identityRole: i.identity_role,
      canonicalIdentityId: i.canonical_identity_id,
      matchStatus: i.match_status,
      matchMethod: i.match_method,
      matchEvidence: i.match_evidence,
      cardVariantTypeId: i.card_variant_type_id,
      cardVariantTypeName: i.card_variant_type_name,
      externalVariantKey: i.external_variant_key,
      lastCheckedAt: i.last_checked_at,
      prices: i.prices.map((p) => ({
        conditionId: p.condition_id,
        priceType: p.price_type,
        currencyCode: p.currency_code,
        marketLabel: p.market_label,
        price: p.price,
        observedAt: p.observed_at,
      })),
    })),
    missingVariant: raw.missing_variant,
  };
}

// ---------------------------------------------------------------------------
// Bloco 3 — Gerencial (Saúde das Fontes, Histórico de Execuções) + Operações
// (Sincronizações). Migration 3941, CONFIRMADO EXECUTADO 2026-08-22. Quatro
// RPCs admin-only de leitura: admin_get_pricing_source_health,
// admin_list_pricing_sync_runs, admin_get_pricing_sync_run_detail,
// admin_list_pricing_set_refresh_states. A política de sincronização em si
// (frequência por fonte) reusa get_pricing_refresh_policy/
// admin_set_pricing_refresh_frequency (migrations 3937/3938, já validadas —
// não são novas aqui).
// ---------------------------------------------------------------------------

export type PricingSourceHealth = {
  pricingSourceId: string;
  pricingSourceCode: string;
  pricingSourceName: string;
  isActive: boolean;
  lastRun: {
    id: string;
    runType: string;
    status: string;
    finishedAt: string | null;
    triggeredBy: string;
  } | null;
  mappings: { confirmed: number; pending: number; notFound: number; total: number; coveragePct: number | null };
  sets: { healthy: number; problem: number; paused: number; total: number };
  recentFailedRuns: number;
  recentRateLimitHits: number;
  lastErrorSummary: string | null;
};

type PricingSourceHealthRawRow = {
  pricing_source_id: string;
  pricing_source_code: string;
  pricing_source_name: string;
  is_active: boolean;
  last_run_id: string | null;
  last_run_type: string | null;
  last_run_status: string | null;
  last_run_finished_at: string | null;
  last_run_triggered_by: string | null;
  mappings_confirmed: number;
  mappings_pending: number;
  mappings_not_found: number;
  mappings_total: number;
  coverage_pct: number | null;
  sets_healthy: number;
  sets_problem: number;
  sets_paused: number;
  sets_total: number;
  recent_failed_runs: number;
  recent_rate_limit_hits: number;
  last_error_summary: string | null;
};

/**
 * Saúde por fonte de preço — `admin_get_pricing_source_health()`, uma linha
 * por `pricing_source` (hoje só JUSTTCG). `[]` em erro, nunca lança — a tela
 * decide o estado (mesmo contrato dos demais `get*` deste módulo).
 */
export async function getPricingSourceHealth(supabase: SupabaseClient): Promise<PricingSourceHealth[]> {
  const { data, error } = await supabase.rpc("admin_get_pricing_source_health");

  if (error || !data) {
    return [];
  }

  const rows = data as PricingSourceHealthRawRow[];
  return rows.map((row) => ({
    pricingSourceId: row.pricing_source_id,
    pricingSourceCode: row.pricing_source_code,
    pricingSourceName: row.pricing_source_name,
    isActive: row.is_active,
    lastRun: row.last_run_id
      ? {
          id: row.last_run_id,
          runType: row.last_run_type as string,
          status: row.last_run_status as string,
          finishedAt: row.last_run_finished_at,
          triggeredBy: row.last_run_triggered_by as string,
        }
      : null,
    mappings: {
      confirmed: row.mappings_confirmed,
      pending: row.mappings_pending,
      notFound: row.mappings_not_found,
      total: row.mappings_total,
      coveragePct: row.coverage_pct,
    },
    sets: { healthy: row.sets_healthy, problem: row.sets_problem, paused: row.sets_paused, total: row.sets_total },
    recentFailedRuns: row.recent_failed_runs,
    recentRateLimitHits: row.recent_rate_limit_hits,
    lastErrorSummary: row.last_error_summary,
  }));
}

export const PRICING_SYNC_RUNS_PAGE_SIZE = 20;

/** Vocabulário real de `pricing_sync_run.status` hoje (ver migrations 3082/3927). */
export type PricingSyncRunStatus = "COMPLETED" | "COMPLETED_WITH_ERRORS" | "FAILED";

export type PricingSyncRunItem = {
  id: string;
  pricingSourceId: string | null;
  pricingSourceCode: string | null;
  runType: string;
  status: string;
  cardSetId: string | null;
  cardSetCode: string | null;
  cardSetName: string | null;
  startedAt: string | null;
  finishedAt: string | null;
  durationSeconds: number | null;
  requestsMade: number | null;
  requestsRemainingAtEnd: number | null;
  rateLimitHits: number | null;
  errorSummary: string | null;
  triggeredBy: string;
};

type PricingSyncRunRawRow = {
  id: string;
  pricing_source_id: string | null;
  pricing_source_code: string | null;
  run_type: string;
  status: string;
  card_set_id: string | null;
  card_set_code: string | null;
  card_set_name: string | null;
  started_at: string | null;
  finished_at: string | null;
  duration_seconds: number | null;
  requests_made: number | null;
  requests_remaining_at_end: number | null;
  rate_limit_hits: number | null;
  error_summary: string | null;
  triggered_by: string;
  total_count: number;
};

/**
 * Histórico de Execuções — `admin_list_pricing_sync_runs`, paginado/filtrado
 * server-side. Filtro por Set usa `pricing_sync_run.pricing_set_mapping_id`
 * (decisão explícita de Fabrício, não `pricing_source_id`); runs FX_REFRESH
 * (sem fonte por desenho) continuam visíveis quando nenhum filtro de Set
 * está ativo — ver nota na migration 3941 sobre o LEFT JOIN.
 */
export async function getPricingSyncRuns(
  supabase: SupabaseClient,
  options: {
    status?: PricingSyncRunStatus[];
    pricingSourceId?: string;
    cardSetId?: string;
    dateFrom?: string;
    dateTo?: string;
    limit?: number;
    offset?: number;
  },
): Promise<{ items: PricingSyncRunItem[]; totalCount: number }> {
  const { data, error } = await supabase.rpc("admin_list_pricing_sync_runs", {
    p_status: options.status && options.status.length > 0 ? options.status : null,
    p_pricing_source_id: options.pricingSourceId || null,
    p_card_set_id: options.cardSetId || null,
    p_date_from: options.dateFrom || null,
    p_date_to: options.dateTo || null,
    p_limit: options.limit ?? PRICING_SYNC_RUNS_PAGE_SIZE,
    p_offset: options.offset ?? 0,
  });

  if (error || !data) {
    return { items: [], totalCount: 0 };
  }

  const rows = data as PricingSyncRunRawRow[];
  return {
    items: rows.map((row) => ({
      id: row.id,
      pricingSourceId: row.pricing_source_id,
      pricingSourceCode: row.pricing_source_code,
      runType: row.run_type,
      status: row.status,
      cardSetId: row.card_set_id,
      cardSetCode: row.card_set_code,
      cardSetName: row.card_set_name,
      startedAt: row.started_at,
      finishedAt: row.finished_at,
      durationSeconds: row.duration_seconds,
      requestsMade: row.requests_made,
      requestsRemainingAtEnd: row.requests_remaining_at_end,
      rateLimitHits: row.rate_limit_hits,
      errorSummary: row.error_summary,
      triggeredBy: row.triggered_by,
    })),
    totalCount: rows[0]?.total_count ?? 0,
  };
}

export type PricingSyncRunCall = {
  id: string;
  sequenceNumber: number;
  endpoint: string;
  httpStatusCode: number | null;
  outcome: string;
  errorDetail: string | null;
  apiRequestsRemaining: number | null;
  calledAt: string;
};

export type PricingSyncRunDetail = {
  run: PricingSyncRunItem & { requestsRemainingAtEnd: number | null; fxSourceCode: string | null };
  calls: PricingSyncRunCall[];
};

/**
 * Detalhe de uma execução (run + `pricing_sync_run_call`s) para o Dialog de
 * Histórico de Execuções — `null` em erro/não encontrado, nunca lança.
 */
export async function getPricingSyncRunDetail(
  supabase: SupabaseClient,
  runId: string,
): Promise<PricingSyncRunDetail | null> {
  const { data, error } = await supabase.rpc("admin_get_pricing_sync_run_detail", { p_run_id: runId });

  if (error || !data) {
    return null;
  }

  const raw = data as {
    run: {
      id: string;
      pricing_source_id: string | null;
      pricing_source_code: string | null;
      run_type: string;
      status: string;
      card_set_id: string | null;
      card_set_code: string | null;
      card_set_name: string | null;
      started_at: string | null;
      finished_at: string | null;
      requests_made: number | null;
      requests_remaining_at_end: number | null;
      rate_limit_hits: number | null;
      error_summary: string | null;
      triggered_by: string;
      fx_source_code: string | null;
    };
    calls: Array<{
      id: string;
      sequence_number: number;
      endpoint: string;
      http_status_code: number | null;
      outcome: string;
      error_detail: string | null;
      api_requests_remaining: number | null;
      called_at: string;
    }>;
  };

  return {
    run: {
      id: raw.run.id,
      pricingSourceId: raw.run.pricing_source_id,
      pricingSourceCode: raw.run.pricing_source_code,
      runType: raw.run.run_type,
      status: raw.run.status,
      cardSetId: raw.run.card_set_id,
      cardSetCode: raw.run.card_set_code,
      cardSetName: raw.run.card_set_name,
      startedAt: raw.run.started_at,
      finishedAt: raw.run.finished_at,
      durationSeconds: null,
      requestsMade: raw.run.requests_made,
      requestsRemainingAtEnd: raw.run.requests_remaining_at_end,
      rateLimitHits: raw.run.rate_limit_hits,
      errorSummary: raw.run.error_summary,
      triggeredBy: raw.run.triggered_by,
      fxSourceCode: raw.run.fx_source_code,
    },
    calls: raw.calls.map((c) => ({
      id: c.id,
      sequenceNumber: c.sequence_number,
      endpoint: c.endpoint,
      httpStatusCode: c.http_status_code,
      outcome: c.outcome,
      errorDetail: c.error_detail,
      apiRequestsRemaining: c.api_requests_remaining,
      calledAt: c.called_at,
    })),
  };
}

export const PRICING_SET_REFRESH_STATES_PAGE_SIZE = 20;

export type PricingSetRefreshDerivedStatus = "HEALTHY" | "PROBLEM" | "PAUSED";

export type PricingSetRefreshStateItem = {
  id: string;
  cardSetId: string;
  cardSetCode: string;
  cardSetName: string;
  pricingSourceId: string;
  pricingSourceCode: string;
  derivedStatus: PricingSetRefreshDerivedStatus;
  lastStartedAt: string | null;
  lastSuccessAt: string | null;
  nextDueAt: string | null;
  lastOutcome: string | null;
  attemptCount: number;
  isPaused: boolean;
  pauseReason: string | null;
  pausedAt: string | null;
  leaseUntil: string | null;
  leasedBy: string | null;
  resumeOffset: number;
  cycleExpectedCardCount: number | null;
  mappingsConfirmed: number;
  mappingsTotal: number;
};

type PricingSetRefreshStateRawRow = {
  id: string;
  card_set_id: string;
  card_set_code: string;
  card_set_name: string;
  pricing_source_id: string;
  pricing_source_code: string;
  derived_status: PricingSetRefreshDerivedStatus;
  last_started_at: string | null;
  last_success_at: string | null;
  next_due_at: string | null;
  last_outcome: string | null;
  attempt_count: number;
  is_paused: boolean;
  pause_reason: string | null;
  paused_at: string | null;
  lease_until: string | null;
  leased_by: string | null;
  resume_offset: number;
  cycle_expected_card_count: number | null;
  mappings_confirmed: number;
  mappings_total: number;
  total_count: number;
};

/**
 * Visão operacional por Set — `admin_list_pricing_set_refresh_states`,
 * paginada/filtrada server-side mesmo com só 45 Sets hoje (mesma disciplina
 * do resto do módulo: nunca fetch integral). Usada pela seção "Estado dos
 * Sets" de `/pricing/sincronizacoes`.
 */
export async function getPricingSetRefreshStates(
  supabase: SupabaseClient,
  options: {
    search?: string;
    status?: PricingSetRefreshDerivedStatus[];
    pricingSourceId?: string;
    limit?: number;
    offset?: number;
  },
): Promise<{ items: PricingSetRefreshStateItem[]; totalCount: number }> {
  const { data, error } = await supabase.rpc("admin_list_pricing_set_refresh_states", {
    p_search: options.search?.trim() || null,
    p_status: options.status && options.status.length > 0 ? options.status : null,
    p_pricing_source_id: options.pricingSourceId || null,
    p_limit: options.limit ?? PRICING_SET_REFRESH_STATES_PAGE_SIZE,
    p_offset: options.offset ?? 0,
  });

  if (error || !data) {
    return { items: [], totalCount: 0 };
  }

  const rows = data as PricingSetRefreshStateRawRow[];
  return {
    items: rows.map((row) => ({
      id: row.id,
      cardSetId: row.card_set_id,
      cardSetCode: row.card_set_code,
      cardSetName: row.card_set_name,
      pricingSourceId: row.pricing_source_id,
      pricingSourceCode: row.pricing_source_code,
      derivedStatus: row.derived_status,
      lastStartedAt: row.last_started_at,
      lastSuccessAt: row.last_success_at,
      nextDueAt: row.next_due_at,
      lastOutcome: row.last_outcome,
      attemptCount: row.attempt_count,
      isPaused: row.is_paused,
      pauseReason: row.pause_reason,
      pausedAt: row.paused_at,
      leaseUntil: row.lease_until,
      leasedBy: row.leased_by,
      resumeOffset: row.resume_offset,
      cycleExpectedCardCount: row.cycle_expected_card_count,
      mappingsConfirmed: row.mappings_confirmed,
      mappingsTotal: row.mappings_total,
    })),
    totalCount: rows[0]?.total_count ?? 0,
  };
}

export type PricingRefreshPolicyItem = {
  pricingSourceId: string;
  pricingSourceCode: string;
  pricingSourceName: string;
  frequencyDays: number;
  updatedAt: string | null;
  updatedBy: string | null;
};

type PricingRefreshPolicyRawRow = {
  pricing_source_id: string;
  pricing_source_code: string;
  pricing_source_name: string;
  frequency_days: number;
  updated_at: string | null;
  updated_by: string | null;
};

/**
 * Política de Sincronização vigente por fonte — reusa
 * `get_pricing_refresh_policy()` (migration 3937, já validada), não é uma
 * RPC nova deste Bloco 3.
 */
export async function getPricingRefreshPolicy(supabase: SupabaseClient): Promise<PricingRefreshPolicyItem[]> {
  const { data, error } = await supabase.rpc("get_pricing_refresh_policy");

  if (error || !data) {
    return [];
  }

  const rows = data as PricingRefreshPolicyRawRow[];
  return rows.map((row) => ({
    pricingSourceId: row.pricing_source_id,
    pricingSourceCode: row.pricing_source_code,
    pricingSourceName: row.pricing_source_name,
    frequencyDays: row.frequency_days,
    updatedAt: row.updated_at,
    updatedBy: row.updated_by,
  }));
}

// ---------------------------------------------------------------------------
// Bloco 4 — Cadastros (Fontes de Preço, Mapeamentos de Sets, Mapeamentos de
// Cartas — todos os status, não só Pendências —, Condições). Migration 3942,
// CONFIRMADO EXECUTADO 2026-08-22. Quatro RPCs admin-only de leitura
// (admin_list_pricing_sources, admin_list_pricing_set_mappings,
// admin_list_pricing_card_mappings, admin_list_card_conditions) + seis de
// write, consumidas via Server Actions em
// app/pricing/{fontes,mapeamentos-sets,mapeamentos-cartas,condicoes}/actions.ts
// — esta camada é só leitura, mesmo padrão do resto do módulo. Duas RPCs
// helper (pricing_set_mapping_dependency_exists,
// pricing_card_mapping_dependency_exists) nunca são chamadas diretamente do
// frontend — são internas, o campo `hasDependency` já vem pronto embutido
// nas listagens.
// ---------------------------------------------------------------------------

export type PricingSource = {
  id: string;
  code: string;
  name: string;
  sourceType: string;
  defaultMarketScope: string;
  baseCurrency: string;
  baseUrl: string | null;
  apiBaseUrl: string | null;
  documentationUrl: string | null;
  termsUrl: string | null;
  attributionText: string | null;
  requiresCommercialAgreement: boolean;
  supportsApi: boolean;
  isActive: boolean;
  sourceOrder: number;
  updatedAt: string;
};

type PricingSourceRawRow = {
  id: string;
  code: string;
  name: string;
  source_type: string;
  default_market_scope: string;
  base_currency: string;
  base_url: string | null;
  api_base_url: string | null;
  documentation_url: string | null;
  terms_url: string | null;
  attribution_text: string | null;
  requires_commercial_agreement: boolean;
  supports_api: boolean;
  is_active: boolean;
  source_order: number;
  updated_at: string;
};

/** Cadastro de Fontes de Preço — `admin_list_pricing_sources()`, sem paginação (hoje só JUSTTCG). `[]` em erro, nunca lança. */
export async function getPricingSources(supabase: SupabaseClient): Promise<PricingSource[]> {
  const { data, error } = await supabase.rpc("admin_list_pricing_sources");

  if (error || !data) {
    return [];
  }

  const rows = data as PricingSourceRawRow[];
  return rows.map((row) => ({
    id: row.id,
    code: row.code,
    name: row.name,
    sourceType: row.source_type,
    defaultMarketScope: row.default_market_scope,
    baseCurrency: row.base_currency,
    baseUrl: row.base_url,
    apiBaseUrl: row.api_base_url,
    documentationUrl: row.documentation_url,
    termsUrl: row.terms_url,
    attributionText: row.attribution_text,
    requiresCommercialAgreement: row.requires_commercial_agreement,
    supportsApi: row.supports_api,
    isActive: row.is_active,
    sourceOrder: row.source_order,
    updatedAt: row.updated_at,
  }));
}

export const PRICING_SET_MAPPINGS_PAGE_SIZE = 20;

/** Vocabulário completo de `pricing_set_mapping.match_status` — ao contrário de Pendências, esta tela mostra os 4 estados. */
export type PricingSetMappingStatus = "CONFIRMED" | "PENDING" | "NOT_FOUND" | "REJECTED";

export type PricingSetMappingItem = {
  id: string;
  cardSetId: string;
  cardSetCode: string;
  cardSetName: string;
  pricingSourceId: string;
  pricingSourceCode: string;
  externalSetId: string | null;
  externalSetName: string | null;
  matchStatus: PricingSetMappingStatus;
  matchMethod: string | null;
  lastCheckedAt: string | null;
  /** true quando existe mapeamento de carta confirmado ou dado de preço vinculado a este Set+fonte — `external_set_id` e a reclassificação CONFIRMED→REJECTED ficam bloqueados na RPC de write quando true (mesma fonte única de verdade da migration 3942). */
  hasDependency: boolean;
};

type PricingSetMappingRawRow = {
  id: string;
  card_set_id: string;
  card_set_code: string;
  card_set_name: string;
  pricing_source_id: string;
  pricing_source_code: string;
  external_set_id: string | null;
  external_set_name: string | null;
  match_status: PricingSetMappingStatus;
  match_method: string | null;
  last_checked_at: string | null;
  has_dependency: boolean;
  total_count: number;
};

/** Cadastro de Mapeamentos de Sets — `admin_list_pricing_set_mappings`, paginado/filtrado server-side, todos os 4 status. */
export async function getPricingSetMappings(
  supabase: SupabaseClient,
  options: {
    status?: PricingSetMappingStatus[];
    pricingSourceId?: string;
    search?: string;
    limit?: number;
    offset?: number;
  },
): Promise<{ items: PricingSetMappingItem[]; totalCount: number }> {
  const { data, error } = await supabase.rpc("admin_list_pricing_set_mappings", {
    p_status: options.status && options.status.length > 0 ? options.status : null,
    p_pricing_source_id: options.pricingSourceId || null,
    p_search: options.search?.trim() || null,
    p_limit: options.limit ?? PRICING_SET_MAPPINGS_PAGE_SIZE,
    p_offset: options.offset ?? 0,
  });

  if (error || !data) {
    return { items: [], totalCount: 0 };
  }

  const rows = data as PricingSetMappingRawRow[];
  return {
    items: rows.map((row) => ({
      id: row.id,
      cardSetId: row.card_set_id,
      cardSetCode: row.card_set_code,
      cardSetName: row.card_set_name,
      pricingSourceId: row.pricing_source_id,
      pricingSourceCode: row.pricing_source_code,
      externalSetId: row.external_set_id,
      externalSetName: row.external_set_name,
      matchStatus: row.match_status,
      matchMethod: row.match_method,
      lastCheckedAt: row.last_checked_at,
      hasDependency: row.has_dependency,
    })),
    totalCount: rows[0]?.total_count ?? 0,
  };
}

export const PRICING_CARD_MAPPINGS_PAGE_SIZE = 20;

/** Vocabulário completo de `pricing_card_mapping.match_status` — ao contrário de Pendências, esta tela mostra os 4 estados. */
export type PricingCardMappingStatus = "CONFIRMED" | "PENDING" | "NOT_FOUND" | "REJECTED";

export type PricingCardMappingItem = {
  id: string;
  cardId: string;
  cardName: string;
  collectorNumber: string;
  collectorTotal: number | null;
  cardSetId: string;
  cardSetCode: string;
  cardSetName: string;
  pricingSourceId: string;
  pricingSourceCode: string;
  externalCardId: string | null;
  externalCardName: string | null;
  matchStatus: PricingCardMappingStatus;
  matchMethod: string | null;
  identityCount: number;
  lastCheckedAt: string | null;
  /** true quando existe `pricing_product` vinculado — reclassificação CONFIRMED→REJECTED fica bloqueada na RPC de write quando true. */
  hasDependency: boolean;
};

type PricingCardMappingRawRow = {
  id: string;
  card_id: string;
  card_name: string;
  collector_number: string;
  collector_total: number | null;
  card_set_id: string;
  card_set_code: string;
  card_set_name: string;
  pricing_source_id: string;
  pricing_source_code: string;
  external_card_id: string | null;
  external_card_name: string | null;
  match_status: PricingCardMappingStatus;
  match_method: string | null;
  identity_count: number;
  last_checked_at: string | null;
  has_dependency: boolean;
  total_count: number;
};

/** Cadastro de Mapeamentos de Cartas — `admin_list_pricing_card_mappings`, paginado/filtrado server-side, todos os 4 status (diferente de Pendências, que trava em PENDING/NOT_FOUND). */
export async function getPricingCardMappings(
  supabase: SupabaseClient,
  options: {
    status?: PricingCardMappingStatus[];
    pricingSourceId?: string;
    cardSetId?: string;
    search?: string;
    limit?: number;
    offset?: number;
  },
): Promise<{ items: PricingCardMappingItem[]; totalCount: number }> {
  const { data, error } = await supabase.rpc("admin_list_pricing_card_mappings", {
    p_status: options.status && options.status.length > 0 ? options.status : null,
    p_pricing_source_id: options.pricingSourceId || null,
    p_card_set_id: options.cardSetId || null,
    p_search: options.search?.trim() || null,
    p_limit: options.limit ?? PRICING_CARD_MAPPINGS_PAGE_SIZE,
    p_offset: options.offset ?? 0,
  });

  if (error || !data) {
    return { items: [], totalCount: 0 };
  }

  const rows = data as PricingCardMappingRawRow[];
  return {
    items: rows.map((row) => ({
      id: row.id,
      cardId: row.card_id,
      cardName: row.card_name,
      collectorNumber: row.collector_number,
      collectorTotal: row.collector_total,
      cardSetId: row.card_set_id,
      cardSetCode: row.card_set_code,
      cardSetName: row.card_set_name,
      pricingSourceId: row.pricing_source_id,
      pricingSourceCode: row.pricing_source_code,
      externalCardId: row.external_card_id,
      externalCardName: row.external_card_name,
      matchStatus: row.match_status,
      matchMethod: row.match_method,
      identityCount: row.identity_count,
      lastCheckedAt: row.last_checked_at,
      hasDependency: row.has_dependency,
    })),
    totalCount: rows[0]?.total_count ?? 0,
  };
}

export type CardConditionMapping = {
  id: string;
  pricingSourceId: string;
  pricingSourceCode: string;
  externalConditionCode: string;
};

export type CardCondition = {
  id: string;
  code: string;
  name: string;
  conditionOrder: number;
  isActive: boolean;
  /** true quando existe `pricing_observation` usando esta condição — nunca bloqueia `is_active=false` (decisão de Fabrício: desativação preserva histórico), só informa a UI. */
  hasDependentObservations: boolean;
  mappings: CardConditionMapping[];
};

type CardConditionRawRow = {
  id: string;
  code: string;
  name: string;
  condition_order: number;
  is_active: boolean;
  has_dependent_observations: boolean;
  mappings: Array<{ id: string; pricing_source_id: string; pricing_source_code: string; external_condition_code: string }>;
};

/** Cadastro de Condições — `admin_list_card_conditions()`, sem paginação (hoje 5 linhas), cada condição já traz seus `pricing_condition_mapping` aninhados. */
export async function getCardConditions(supabase: SupabaseClient): Promise<CardCondition[]> {
  const { data, error } = await supabase.rpc("admin_list_card_conditions");

  if (error || !data) {
    return [];
  }

  const rows = data as CardConditionRawRow[];
  return rows.map((row) => ({
    id: row.id,
    code: row.code,
    name: row.name,
    conditionOrder: row.condition_order,
    isActive: row.is_active,
    hasDependentObservations: row.has_dependent_observations,
    mappings: row.mappings.map((m) => ({
      id: m.id,
      pricingSourceId: m.pricing_source_id,
      pricingSourceCode: m.pricing_source_code,
      externalConditionCode: m.external_condition_code,
    })),
  }));
}

// ---------------------------------------------------------------------------
// Bloco 5 — Central de Relatórios (migration 3943): Preço por Carta e Valor
// por Set. Duas RPCs de leitura já agregada — toda soma/cobertura/conversão
// cambial acontece no banco, nenhuma agregação pesada no frontend (pedido
// explícito de Fabrício, 2026-08-23). Ver
// docs/development/HANDOFF-2026-08-21.md, seção 14, para o contrato completo
// e o débito de performance aceito para Valor por Set (~650-1080ms no maior
// Set atual, ME2.5 — sob demanda, gatilho de revisão em ~2s).
// ---------------------------------------------------------------------------

export type PricingReportCurrency = "BRL" | "USD";
export type PricingReportFxStatus = "NATIVE" | "CONVERTED" | "FX_RATE_UNAVAILABLE" | "UNSUPPORTED_CONVERSION";

export type PricingReportConditionRef = { id: string; code: string; name: string };

export type PricingReportCurrentPrice = {
  pricingSourceId: string;
  pricingSourceCode: string;
  printingLabel: string;
  priceNative: number;
  currencyNative: string;
  priceDisplay: number | null;
  fxStatus: PricingReportFxStatus;
  fxSource: string | null;
  fxRate: number | null;
  fxRateDate: string | null;
  observedAt: string;
};

export type PricingReportHistoryPoint = {
  pricingSourceId: string;
  pricingSourceCode: string;
  printingLabel: string;
  price: number;
  currencyCode: string;
  observedAt: string;
};

export type PricingReportCard = {
  card: {
    id: string;
    name: string;
    collectorNumber: string;
    collectorTotal: number | null;
    isActive: boolean;
    cardSetId: string;
    cardSetCode: string;
    cardSetName: string;
  };
  condition: PricingReportConditionRef;
  currency: PricingReportCurrency;
  historyDays: number;
  currentPrices: PricingReportCurrentPrice[];
  history: PricingReportHistoryPoint[];
};

type PricingReportCardRawRow = {
  card: {
    id: string;
    name: string;
    collector_number: string;
    collector_total: number | null;
    is_active: boolean;
    card_set_id: string;
    card_set_code: string;
    card_set_name: string;
  };
  condition: { id: string; code: string; name: string };
  currency: PricingReportCurrency;
  history_days: number;
  current_prices: Array<{
    pricing_source_id: string;
    pricing_source_code: string;
    printing_label: string;
    price_native: number;
    currency_native: string;
    price_display: number | null;
    fx_status: PricingReportFxStatus;
    fx_source: string | null;
    fx_rate: number | null;
    fx_rate_date: string | null;
    observed_at: string;
  }>;
  history: Array<{
    pricing_source_id: string;
    pricing_source_code: string;
    printing_label: string;
    price: number;
    currency_code: string;
    observed_at: string;
  }>;
};

/**
 * Relatório "Preço por Carta" — `admin_get_pricing_report_card` (migration
 * 3943). `null` em qualquer erro da RPC (carta/condição inexistente, moeda
 * inválida, sem permissão) — mesmo padrão enxuto de `getPricingMappingDetail`/
 * `getPricingSyncRunDetail`: a tela mostra um estado "não encontrado"
 * genérico, sem tentar distinguir a causa exata (nenhuma dessas RPCs de
 * detalhe traduz erro para o usuário, só as de escrita).
 */
export async function getPricingReportCard(
  supabase: SupabaseClient,
  options: { cardId: string; conditionId?: string; currency?: PricingReportCurrency; historyDays?: number },
): Promise<PricingReportCard | null> {
  const { data, error } = await supabase.rpc("admin_get_pricing_report_card", {
    p_card_id: options.cardId,
    p_condition_id: options.conditionId || null,
    p_currency: options.currency ?? "BRL",
    p_history_days: options.historyDays ?? 90,
  });

  if (error || !data) {
    return null;
  }

  const raw = data as PricingReportCardRawRow;
  return {
    card: {
      id: raw.card.id,
      name: raw.card.name,
      collectorNumber: raw.card.collector_number,
      collectorTotal: raw.card.collector_total,
      isActive: raw.card.is_active,
      cardSetId: raw.card.card_set_id,
      cardSetCode: raw.card.card_set_code,
      cardSetName: raw.card.card_set_name,
    },
    condition: { id: raw.condition.id, code: raw.condition.code, name: raw.condition.name },
    currency: raw.currency,
    historyDays: raw.history_days,
    currentPrices: raw.current_prices.map((p) => ({
      pricingSourceId: p.pricing_source_id,
      pricingSourceCode: p.pricing_source_code,
      printingLabel: p.printing_label,
      priceNative: p.price_native,
      currencyNative: p.currency_native,
      priceDisplay: p.price_display,
      fxStatus: p.fx_status,
      fxSource: p.fx_source,
      fxRate: p.fx_rate,
      fxRateDate: p.fx_rate_date,
      observedAt: p.observed_at,
    })),
    history: raw.history.map((h) => ({
      pricingSourceId: h.pricing_source_id,
      pricingSourceCode: h.pricing_source_code,
      printingLabel: h.printing_label,
      price: h.price,
      currencyCode: h.currency_code,
      observedAt: h.observed_at,
    })),
  };
}

export type PricingReportSet = {
  cardSetId: string;
  condition: PricingReportConditionRef;
  currency: PricingReportCurrency;
  totalActiveCards: number;
  pricedConvertibleCount: number;
  pricedFxUnavailableCount: number;
  noPriceCount: number;
  coveragePct: number;
  estimatedValueCovered: number;
  isPartial: boolean;
};

type PricingReportSetRawRow = {
  card_set_id: string;
  condition: { id: string; code: string; name: string };
  currency: PricingReportCurrency;
  total_active_cards: number;
  priced_convertible_count: number;
  priced_fx_unavailable_count: number;
  no_price_count: number;
  coverage_pct: number;
  estimated_value_covered: number;
  is_partial: boolean;
};

/**
 * Relatório "Valor por Set" — `admin_get_pricing_report_set` (migration
 * 3943). Agregado puro: soma/cobertura já vêm prontas do banco, nunca
 * recalculadas no frontend. `estimatedValueCovered` é o valor coberto, nunca
 * uma estimativa do total do Set — ausência de preço nunca vira zero (ver
 * `noPriceCount`/`isPartial`). Esta RPC é só o agregado — a lista/ranking de
 * cartas que compõem o valuation vem de `getPricingReportSetCards`
 * (migration 3944, RPC dedicada set-based, sem N chamadas por carta).
 */
export async function getPricingReportSet(
  supabase: SupabaseClient,
  options: { cardSetId: string; conditionId?: string; currency?: PricingReportCurrency },
): Promise<PricingReportSet | null> {
  const { data, error } = await supabase.rpc("admin_get_pricing_report_set", {
    p_card_set_id: options.cardSetId,
    p_condition_id: options.conditionId || null,
    p_currency: options.currency ?? "BRL",
  });

  if (error || !data) {
    return null;
  }

  const raw = data as PricingReportSetRawRow;
  return {
    cardSetId: raw.card_set_id,
    condition: { id: raw.condition.id, code: raw.condition.code, name: raw.condition.name },
    currency: raw.currency,
    totalActiveCards: raw.total_active_cards,
    pricedConvertibleCount: raw.priced_convertible_count,
    pricedFxUnavailableCount: raw.priced_fx_unavailable_count,
    noPriceCount: raw.no_price_count,
    coveragePct: raw.coverage_pct,
    estimatedValueCovered: raw.estimated_value_covered,
    isPartial: raw.is_partial,
  };
}

export const PRICING_REPORT_SET_CARDS_PAGE_SIZE = 20;

/** Vocabulário fechado da lista por carta do relatório "Valor por Set" — nunca trata ausência de preço como zero. */
export type PricingReportSetCardStatus = "PRICED" | "FX_UNAVAILABLE" | "NO_PRICE";

export type PricingReportSetCardItem = {
  cardId: string;
  cardName: string;
  collectorNumber: string;
  collectorTotal: number | null;
  status: PricingReportSetCardStatus;
  pricingSourceId: string | null;
  pricingSourceCode: string | null;
  printingLabel: string | null;
  priceNative: number | null;
  currencyNative: string | null;
  priceDisplay: number | null;
  currency: PricingReportCurrency;
  fxStatus: PricingReportFxStatus | null;
  fxSource: string | null;
  fxRate: number | null;
  fxRateDate: string | null;
  observedAt: string | null;
  participationPct: number | null;
  ranking: number | null;
  setCoveredValue: number;
};

type PricingReportSetCardRawRow = {
  card_id: string;
  card_name: string;
  collector_number: string;
  collector_total: number | null;
  status: PricingReportSetCardStatus;
  pricing_source_id: string | null;
  pricing_source_code: string | null;
  printing_label: string | null;
  price_native: number | null;
  currency_native: string | null;
  price_display: number | null;
  currency: PricingReportCurrency;
  fx_status: PricingReportFxStatus | null;
  fx_source: string | null;
  fx_rate: number | null;
  fx_rate_date: string | null;
  observed_at: string | null;
  participation_pct: number | null;
  ranking: number | null;
  set_covered_value: number;
  total_count: number;
};

/**
 * Lista/ranking de cartas do relatório "Valor por Set" —
 * `admin_get_pricing_report_set_cards` (migration 3944). RPC dedicada
 * set-based, reusa exatamente a mesma regra econômica de
 * `admin_get_pricing_report_set` (helper compartilhada
 * `admin_pricing_report_set_price_candidates` no banco — reconciliação por
 * construção, não coincidência). Paginação server-side (`p_limit`
 * clamped 1-100 no banco, `total_count` via `count(*) OVER()`). Status de 3
 * vias: PRICED (`priceDisplay` não nulo), FX_UNAVAILABLE (candidato existe
 * mas câmbio indisponível) e NO_PRICE (nenhum candidato) — nunca colapsado
 * em "sem preço = zero". Em erro, retorna `{ items: [], totalCount: 0 }`,
 * mesmo contrato de `getPricingPendingMappings`.
 */
export async function getPricingReportSetCards(
  supabase: SupabaseClient,
  options: {
    cardSetId: string;
    conditionId?: string;
    currency?: PricingReportCurrency;
    limit?: number;
    offset?: number;
  },
): Promise<{ items: PricingReportSetCardItem[]; totalCount: number }> {
  const { data, error } = await supabase.rpc("admin_get_pricing_report_set_cards", {
    p_card_set_id: options.cardSetId,
    p_condition_id: options.conditionId || null,
    p_currency: options.currency ?? "BRL",
    p_limit: options.limit ?? PRICING_REPORT_SET_CARDS_PAGE_SIZE,
    p_offset: options.offset ?? 0,
  });

  if (error || !data) {
    return { items: [], totalCount: 0 };
  }

  const rows = data as PricingReportSetCardRawRow[];
  return {
    items: rows.map((row) => ({
      cardId: row.card_id,
      cardName: row.card_name,
      collectorNumber: row.collector_number,
      collectorTotal: row.collector_total,
      status: row.status,
      pricingSourceId: row.pricing_source_id,
      pricingSourceCode: row.pricing_source_code,
      printingLabel: row.printing_label,
      priceNative: row.price_native,
      currencyNative: row.currency_native,
      priceDisplay: row.price_display,
      currency: row.currency,
      fxStatus: row.fx_status,
      fxSource: row.fx_source,
      fxRate: row.fx_rate,
      fxRateDate: row.fx_rate_date,
      observedAt: row.observed_at,
      participationPct: row.participation_pct,
      ranking: row.ranking,
      setCoveredValue: row.set_covered_value,
    })),
    totalCount: rows[0]?.total_count ?? 0,
  };
}
