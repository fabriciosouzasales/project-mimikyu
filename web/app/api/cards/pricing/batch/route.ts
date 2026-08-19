import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Teto defensivo de quantidade de cartas por chamada — precisa ser <= 100
// porque `get_cards_pricing_summary` (P12 v4) rejeita explicitamente arrays
// maiores que 100 elementos (`PRICING_SUMMARY_TOO_MANY_CARD_IDS`). Ainda bem
// acima de qualquer página real do grid (paginação do Catálogo/Pesquisa nunca
// renderiza mais que algumas dezenas de cards por vez).
const MAX_CARD_IDS = 100;

type FxStatus = "CONVERTED" | "FX_RATE_UNAVAILABLE";

type PricingSnapshotRow = {
  sourceCode: string;
  sourceName: string;
  priceType: string;
  originalAmount: number;
  originalCurrencyCode: string;
  equivalentBrlAmount: number | null;
  fxStatus: FxStatus;
  fxRate: number | null;
  fxRateDate: string | null;
  equivalentLabel: string | null;
  conditionCode: string;
  conditionName: string;
  printingLabel: string;
  marketLabel: string | null;
  observedAt: string;
};

// Resumo mínimo do modo live (P12 v4, hierarquia de printing na revisão
// 3904) — espelha exatamente o retorno de `get_cards_pricing_summary(p_card_ids
// uuid[])`: uma única consulta SQL, condição NM e price_type MARKET fixos,
// mas agora com hierarquia de printing (Normal > Holofoil > Reverse
// Holofoil) em vez de só Normal — sem as colunas de detalhe (fonte, mercado,
// observado em, PTAX) que o contrato por-carta (P11) ainda traz, por isso
// não reaproveita `PricingSnapshotRow`. `printingLabel` (novo, 3904) devolve
// qual dos três printings foi efetivamente escolhido pela função — o
// frontend usa isso para não ter de assumir "Normal" nem recalcular a
// hierarquia por conta própria a partir de um resumo que não a carrega.
type PricingSummaryRow = {
  hasPricing: boolean;
  brlAmount: number | null;
  fxStatus: FxStatus | null;
  printingLabel: string | null;
};

type GetCardsPricingSummaryRow = {
  card_id: string;
  has_pricing: boolean;
  brl_amount: number | null;
  fx_status: FxStatus | null;
  printing_label: string | null;
};

// --- Modo prévia técnica (admin, ?pricingPreview=1) ---------------------
//
// Mesma lógica de `app/api/cards/[cardId]/pricing/route.ts` (P12), só que
// filtrando por uma LISTA de `card_id` numa única consulta (`.in(...)` em vez
// de `.eq(...)`) — é essa única query, não N chamadas por carta, que resolve
// "sem N+1" para o modo prévia. Reaproveita exatamente as mesmas policies de
// RLS admin_select já concedidas desde P1-P6, com o client autenticado do
// próprio admin (cookies, nunca service_role). Nenhuma RPC nova, nenhum grant
// ampliado — omite deliberadamente, só aqui, o filtro `pricing_source.is_active
// = TRUE` que o contrato público (P11) aplica.
type PreviewObservationRow = {
  id: string;
  pricing_product_id: string;
  condition_id: string;
  price: number;
  currency_code: string;
  price_type: string;
  market_label: string | null;
  observed_at: string;
  created_at: string;
  condition: { code: string; name: string; condition_order: number } | null;
  pricing_product: {
    source_printing_label: string;
    pricing_card_mapping: {
      match_status: string;
      card_id: string;
      pricing_source: { code: string; name: string; source_order: number } | null;
    } | null;
  } | null;
};

type FxRateRow = { rate: number; rate_date: string };

async function loadPreviewRowsBatch(
  supabase: Awaited<ReturnType<typeof createClient>>,
  cardIds: string[],
): Promise<Record<string, PricingSnapshotRow[]>> {
  const { data: obsData, error: obsError } = await supabase
    .from("pricing_observation")
    .select(
      `
      id,
      pricing_product_id,
      condition_id,
      price,
      currency_code,
      price_type,
      market_label,
      observed_at,
      created_at,
      condition:card_condition!inner ( code, name, condition_order ),
      pricing_product!inner (
        source_printing_label,
        is_active,
        pricing_card_mapping!inner (
          match_status,
          card_id,
          pricing_source!inner ( code, name, source_order )
        )
      )
    `,
    )
    .in("pricing_product.pricing_card_mapping.card_id", cardIds)
    .eq("pricing_product.pricing_card_mapping.match_status", "CONFIRMED")
    .eq("pricing_product.is_active", true);

  if (obsError) {
    console.error("[api/cards/pricing/batch] preview pricing_observation error", obsError);
    throw obsError;
  }

  const rows = (obsData ?? []) as unknown as PreviewObservationRow[];

  // Snapshot mais recente por carta/produto/condição/tipo de preço/mercado —
  // mesmo agrupamento e desempate determinístico do contrato público (P11) e
  // do modo prévia por carta (P12), só que com `card_id` como primeiro nível
  // da chave, para separar o resultado de volta por carta ao final.
  const latestByGroup = new Map<string, PreviewObservationRow>();
  for (const row of rows) {
    const cardId = row.pricing_product?.pricing_card_mapping?.card_id;
    if (!cardId) continue;
    const key = `${cardId}::${row.pricing_product_id}::${row.condition_id}::${row.price_type}::${row.market_label ?? ""}`;
    const current = latestByGroup.get(key);
    if (!current) {
      latestByGroup.set(key, row);
      continue;
    }
    const rowKey = [row.observed_at, row.created_at, row.id];
    const currentKey = [current.observed_at, current.created_at, current.id];
    if (rowKey.join("") > currentKey.join("")) {
      latestByGroup.set(key, row);
    }
  }

  const usdDates = new Set<string>();
  for (const row of latestByGroup.values()) {
    if (row.currency_code === "USD") {
      usdDates.add(row.observed_at.slice(0, 10));
    }
  }

  let fxRates: FxRateRow[] = [];
  if (usdDates.size > 0) {
    const { data: fxData, error: fxError } = await supabase
      .from("pricing_fx_rate")
      .select("rate, rate_date")
      .eq("from_currency", "USD")
      .eq("to_currency", "BRL")
      .eq("rate_source_code", "BCB_PTAX")
      .order("rate_date", { ascending: false });

    if (fxError) {
      console.error("[api/cards/pricing/batch] preview pricing_fx_rate error", fxError);
      throw fxError;
    }
    fxRates = (fxData ?? []) as FxRateRow[];
  }

  function latestApplicableRate(observedAt: string): FxRateRow | null {
    const observedDate = observedAt.slice(0, 10);
    for (const rate of fxRates) {
      if (rate.rate_date <= observedDate) return rate;
    }
    return null;
  }

  type SortableRow = PricingSnapshotRow & {
    cardId: string;
    conditionOrder: number;
    sourceOrder: number;
    pricingProductId: string;
  };

  const sortable: SortableRow[] = [];
  for (const row of latestByGroup.values()) {
    const product = row.pricing_product;
    const mapping = product?.pricing_card_mapping;
    const source = mapping?.pricing_source;
    const condition = row.condition;
    if (!product || !mapping || !source || !condition) continue;

    const fx = row.currency_code === "USD" ? latestApplicableRate(row.observed_at) : null;

    sortable.push({
      cardId: mapping.card_id,
      sourceCode: source.code,
      sourceName: source.name,
      priceType: row.price_type,
      originalAmount: row.price,
      originalCurrencyCode: row.currency_code,
      equivalentBrlAmount: fx ? Math.round(row.price * fx.rate * 100) / 100 : null,
      fxStatus: fx ? "CONVERTED" : "FX_RATE_UNAVAILABLE",
      fxRate: fx ? fx.rate : null,
      fxRateDate: fx ? fx.rate_date : null,
      equivalentLabel: fx ? "Equivalente em BRL pela PTAX Venda" : null,
      conditionCode: condition.code,
      conditionName: condition.name,
      printingLabel: product.source_printing_label,
      marketLabel: row.market_label,
      observedAt: row.observed_at,
      conditionOrder: condition.condition_order,
      sourceOrder: source.source_order,
      pricingProductId: row.pricing_product_id,
    });
  }

  // Mesma ordenação determinística do contrato público (P11) e do modo
  // prévia por carta: condição, tipo de preço, mercado (NULLS LAST), fonte,
  // printing, produto.
  sortable.sort((a, b) => {
    if (a.conditionOrder !== b.conditionOrder) return a.conditionOrder - b.conditionOrder;
    if (a.priceType !== b.priceType) return a.priceType.localeCompare(b.priceType);
    const ma = a.marketLabel ?? "￿";
    const mb = b.marketLabel ?? "￿";
    if (ma !== mb) return ma.localeCompare(mb);
    if (a.sourceOrder !== b.sourceOrder) return a.sourceOrder - b.sourceOrder;
    if (a.printingLabel !== b.printingLabel) return a.printingLabel.localeCompare(b.printingLabel);
    return a.pricingProductId.localeCompare(b.pricingProductId);
  });

  const result: Record<string, PricingSnapshotRow[]> = {};
  for (const cardId of cardIds) result[cardId] = [];
  for (const { cardId, conditionOrder: _co, sourceOrder: _so, pricingProductId: _pp, ...rest } of sortable) {
    result[cardId] ??= [];
    result[cardId].push(rest);
  }
  return result;
}

/**
 * Variante em lote de `GET /api/cards/[cardId]/pricing` (Incremento P12,
 * redesenho 2026-08-18 — resumo inline no grid, nunca dependente de hover
 * para existir). Recebe uma lista de `card_id` e devolve o preço de todas de
 * uma vez, numa única chamada de rede do navegador — "sem N+1 no carregamento
 * do grid" só faz sentido com um endpoint em lote; o contrato por carta (P11/
 * P12) continua existindo e inalterado, só não é mais chamado um a um pelo
 * grid.
 *
 * Modo normal (`live`) — rodada 2 (P12 v4, mesmo dia): `get_card_pricing_snapshot`
 * (P11) não aceita lista de IDs, então a primeira versão deste endpoint
 * chamava-a uma vez por carta em paralelo (`Promise.all`) — isso resolvia o
 * N+1 client→servidor (uma única requisição do navegador), mas não o N+1
 * servidor→Postgres (ainda N consultas). Fabrício apontou que esse N+1 real
 * continuava existindo e pediu a eliminação completa: `get_cards_pricing_summary`
 * (nova RPC, `p_card_ids uuid[]`, máx. 100 elementos) resolve o lote inteiro
 * numa única consulta SQL (`DISTINCT ON` + `LEFT JOIN LATERAL` para PTAX),
 * validado via `EXPLAIN (ANALYZE, BUFFERS)` em 100 ids reais — 12,9ms, um
 * único `Function Scan`, sem laço nenhum. Retorno deliberadamente mínimo
 * (`card_id`, `has_pricing`, `brl_amount`, `fx_status`, `printing_label`) sob
 * condição NM e `price_type` MARKET fixos.
 *
 * Hierarquia de printing (revisão 3904, 2026-08-18, correção pós-teste
 * "Reverse-only"; estendida na revisão 3918, 2026-08-19, correção da onda 1
 * do P14.4.2): a primeira versão desta função (3903) exigia printing
 * "Normal" — cartas cujo único printing catalogado é Holofoil (ex.: "ex"
 * quase sempre holo-exclusivas) nunca mostravam resumo, mesmo com preço real
 * sob outro printing; um teste transacional confirmou o mesmo problema para
 * Reverse Holofoil (3904). A onda 1 do P14.4.2 (BASE2/BASE3/BASE5/GYM2, era
 * clássica WOTC) revelou o mesmo problema para printings "Unlimited"/"1st
 * Edition" (3918). Hierarquia aprovada atual — Normal > Holofoil > Reverse
 * Holofoil > Unlimited > Unlimited Holofoil > 1st Edition > 1st Edition
 * Holofoil — aplicada só dentro de NM+MARKET: `has_pricing=true` se QUALQUER
 * um dos sete tiver preço elegível, e `printing_label` devolve qual foi
 * efetivamente escolhido.
 *
 * Modo prévia (`?pricingPreview=1`, só com `is_admin()` confirmado no
 * servidor): inalterado desde a primeira versão — uma única consulta
 * `.in(card_id, [...])` nas tabelas base, reaproveitando as mesmas policies
 * `pricing_admin_select`/`card_condition_admin_select` já concedidas desde
 * P1-P6 — nenhuma RPC nova, nenhum grant ampliado, mesmo racional do modo
 * prévia por carta. Continua trazendo o detalhe completo (todas condição/
 * tipo/mercado), não só o resumo — é por isso que preview e live têm formatos
 * de retorno diferentes (`results` é `Record<cardId, PricingSnapshotRow[]>`
 * em preview, `Record<cardId, PricingSummaryRow>` em live).
 */
export async function POST(request: NextRequest) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const cardIdsRaw = (body as { cardIds?: unknown } | null)?.cardIds;
  if (!Array.isArray(cardIdsRaw) || cardIdsRaw.length === 0) {
    return NextResponse.json({ error: "missing_card_ids" }, { status: 400 });
  }
  if (cardIdsRaw.length > MAX_CARD_IDS) {
    return NextResponse.json({ error: "too_many_card_ids" }, { status: 400 });
  }

  const cardIds = Array.from(new Set(cardIdsRaw));
  if (!cardIds.every((id): id is string => typeof id === "string" && UUID_RE.test(id))) {
    return NextResponse.json({ error: "invalid_card_id" }, { status: 400 });
  }

  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  }

  const previewRequested = request.nextUrl.searchParams.get("pricingPreview") === "1";

  let isAdmin = false;
  if (previewRequested) {
    const { data: isAdminData, error: isAdminError } = await supabase.rpc("is_admin");
    if (isAdminError) {
      console.error("[api/cards/pricing/batch] is_admin RPC error", isAdminError);
    } else {
      isAdmin = Boolean(isAdminData);
    }
  }

  if (previewRequested && isAdmin) {
    try {
      const results = await loadPreviewRowsBatch(supabase, cardIds);
      return NextResponse.json({ mode: "preview", results });
    } catch {
      return NextResponse.json({ error: "pricing_preview_failed" }, { status: 500 });
    }
  }

  const { data, error } = await supabase.rpc("get_cards_pricing_summary", { p_card_ids: cardIds });

  if (error) {
    console.error("[api/cards/pricing/batch] get_cards_pricing_summary RPC error", error);
    return NextResponse.json({ error: "pricing_summary_failed" }, { status: 500 });
  }

  const results: Record<string, PricingSummaryRow> = {};
  for (const row of (data ?? []) as GetCardsPricingSummaryRow[]) {
    results[row.card_id] = {
      hasPricing: row.has_pricing,
      brlAmount: row.brl_amount,
      fxStatus: row.fx_status,
      printingLabel: row.printing_label,
    };
  }

  return NextResponse.json({ mode: "live", results });
}
