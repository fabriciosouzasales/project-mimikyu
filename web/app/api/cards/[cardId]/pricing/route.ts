import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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

type GetCardPricingSnapshotRow = {
  pricing_source_code: string;
  pricing_source_name: string;
  price_type: string;
  original_amount: number;
  original_currency_code: string;
  equivalent_brl_amount: number | null;
  fx_status: FxStatus;
  fx_rate: number | null;
  fx_rate_date: string | null;
  equivalent_label: string | null;
  condition_code: string;
  condition_name: string;
  printing_label: string;
  market_label: string | null;
  observed_at: string;
};

function mapLiveRow(row: GetCardPricingSnapshotRow): PricingSnapshotRow {
  return {
    sourceCode: row.pricing_source_code,
    sourceName: row.pricing_source_name,
    priceType: row.price_type,
    originalAmount: row.original_amount,
    originalCurrencyCode: row.original_currency_code,
    equivalentBrlAmount: row.equivalent_brl_amount,
    fxStatus: row.fx_status,
    fxRate: row.fx_rate,
    fxRateDate: row.fx_rate_date,
    equivalentLabel: row.equivalent_label,
    conditionCode: row.condition_code,
    conditionName: row.condition_name,
    printingLabel: row.printing_label,
    marketLabel: row.market_label,
    observedAt: row.observed_at,
  };
}

// --- Modo preview (admin, ?pricingPreview=1) ----------------------------
//
// Reaproveita exatamente as mesmas policies de RLS admin_select já concedidas
// desde P1-P6 (pricing_admin_select em pricing_observation/pricing_product/
// pricing_card_mapping/pricing_source/pricing_fx_rate, card_condition_admin_select
// em card_condition) via leitura direta nas tabelas com o client autenticado do
// próprio admin (cookies, nunca service_role). Nenhuma RPC nova, nenhum grant
// ampliado — a única diferença deste caminho para o contrato público
// (get_card_pricing_snapshot, P11) é NÃO aplicar o filtro pricing_source.is_active
// = TRUE, que é exatamente o que permite ver os dados reais do piloto JustTCG
// (is_active = FALSE) só quando is_admin() já confirmou o chamador como admin.
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

async function loadPreviewRows(
  supabase: Awaited<ReturnType<typeof createClient>>,
  cardId: string,
): Promise<PricingSnapshotRow[]> {
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
    .eq("pricing_product.pricing_card_mapping.card_id", cardId)
    .eq("pricing_product.pricing_card_mapping.match_status", "CONFIRMED")
    .eq("pricing_product.is_active", true);

  if (obsError) {
    console.error("[api/cards/[cardId]/pricing] preview pricing_observation error", obsError);
    throw obsError;
  }

  const rows = (obsData ?? []) as unknown as PreviewObservationRow[];

  // Snapshot mais recente por produto/condição/tipo de preço/mercado — mesmo
  // agrupamento e desempate determinístico do contrato público (P11), só que
  // reduzido em memória em vez de DISTINCT ON (leitura direta via PostgREST,
  // não uma função SQL).
  const latestByGroup = new Map<string, PreviewObservationRow>();
  for (const row of rows) {
    const key = `${row.pricing_product_id}::${row.condition_id}::${row.price_type}::${row.market_label ?? ""}`;
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
      console.error("[api/cards/[cardId]/pricing] preview pricing_fx_rate error", fxError);
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

  // Mesma ordenação determinística do contrato público (P11): condição,
  // tipo de preço, mercado (NULLS LAST), fonte, printing, produto.
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

  return sortable.map(({ conditionOrder: _co, sourceOrder: _so, pricingProductId: _pp, ...rest }) => rest);
}

/**
 * Painel de preços da carta (Incremento P12, ver ADR-029/ADR-030 e
 * 05f-pricing.md) — modo normal usa exclusivamente `get_card_pricing_snapshot`
 * (P11, contrato seguro para qualquer usuário autenticado). Modo prévia
 * (`?pricingPreview=1`) exige admin confirmado nesta rota via `is_admin()`
 * (RPC, mesmo client autenticado por cookies — nunca service_role) e lê as
 * tabelas base diretamente, sob as policies de RLS admin_select já existentes
 * desde P1-P6 — sem RPC nova, sem grant ampliado. Não-admin/anon que enviem
 * `?pricingPreview=1` recebem exatamente a mesma resposta do modo normal
 * (nenhum sinal de que o modo prévia existe).
 */
export async function GET(request: NextRequest, { params }: { params: Promise<{ cardId: string }> }) {
  const { cardId: cardIdRaw } = await params;

  if (!UUID_RE.test(cardIdRaw)) {
    return NextResponse.json({ error: "invalid_card_id" }, { status: 400 });
  }
  const cardId = cardIdRaw;

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
      console.error("[api/cards/[cardId]/pricing] is_admin RPC error", isAdminError);
    } else {
      isAdmin = Boolean(isAdminData);
    }
  }

  if (previewRequested && isAdmin) {
    try {
      const rows = await loadPreviewRows(supabase, cardId);
      return NextResponse.json({ mode: "preview", rows });
    } catch {
      return NextResponse.json({ error: "pricing_preview_failed" }, { status: 500 });
    }
  }

  const { data, error } = await supabase.rpc("get_card_pricing_snapshot", { p_card_id: cardId });

  if (error) {
    console.error("[api/cards/[cardId]/pricing] get_card_pricing_snapshot RPC error", error);
    return NextResponse.json({ error: "pricing_snapshot_failed" }, { status: 500 });
  }

  const rows = ((data ?? []) as GetCardPricingSnapshotRow[]).map(mapLiveRow);
  return NextResponse.json({ mode: "live", rows });
}
