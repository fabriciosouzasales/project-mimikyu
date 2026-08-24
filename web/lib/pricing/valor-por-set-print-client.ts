import { createClient } from "@/lib/supabase/client";
import {
  mapPricingReportSetCardRow,
  type PricingReportCurrency,
  type PricingReportSetCardItem,
  type PricingReportSetCardRawRow,
} from "@/lib/pricing/queries";

// `admin_get_pricing_report_set_cards` (migration 3944/3949) trava `p_limit`
// em 1-100 no banco (`v_limit := LEAST(GREATEST(..., 1), 100)`) — nenhuma
// migration nova aqui, só respeitamos o teto que já existe. A tela normal
// usa PRICING_REPORT_SET_CARDS_PAGE_SIZE=20; a impressão precisa do Set
// inteiro, então busca em lotes de 100 (o maior permitido), nunca 1
// chamada por página de 20 (isso sim seria ingênuo — até 7x mais
// round-trips para um Set de 130 cartas).
const PRINT_FETCH_BATCH_SIZE = 100;

// Teto de segurança contra loop infinito se a RPC devolver um total_count
// inconsistente — nenhum Set real do catálogo chega perto disso
// (20 lotes x 100 = 2000 cartas).
const MAX_BATCHES = 20;

/**
 * Busca TODAS as cartas do relatório "Valor por Set" para a folha impressa —
 * usada exclusivamente pelo fluxo de impressão (`ValorPorSetPrintProvider`,
 * acionado pelo botão "Imprimir"), nunca na carga normal da tela intera-
 * tiva (que continua paginada em 20 via `getPricingReportSetCards`,
 * server-side, em `page.tsx`). Chama a MESMA RPC
 * `admin_get_pricing_report_set_cards` diretamente do navegador — mesmo
 * padrão já usado em `users-table.tsx` (`supabase.rpc(...)` client-side,
 * autorização via RLS/`is_admin()` na sessão do próprio usuário, nenhum
 * Route Handler novo, nenhuma migration nova).
 *
 * Número de chamadas = ceil(totalCount / 100) — para a grande maioria dos
 * Sets (<=100 cartas ativas) é 1 única chamada; só Sets muito grandes
 * (>100) precisam de uma 2ª/3ª chamada. Nunca 1 chamada por carta nem 1
 * chamada por página de 20 — não é N+1.
 */
export async function fetchAllPricingReportSetCards(options: {
  cardSetId: string;
  conditionId: string;
  currency: PricingReportCurrency;
}): Promise<{ items: PricingReportSetCardItem[]; totalCount: number } | null> {
  const supabase = createClient();

  const items: PricingReportSetCardItem[] = [];
  let totalCount = 0;

  for (let batch = 0; batch < MAX_BATCHES; batch++) {
    const offset = batch * PRINT_FETCH_BATCH_SIZE;
    const { data, error } = await supabase.rpc("admin_get_pricing_report_set_cards", {
      p_card_set_id: options.cardSetId,
      p_condition_id: options.conditionId,
      p_currency: options.currency,
      p_limit: PRINT_FETCH_BATCH_SIZE,
      p_offset: offset,
    });

    if (error || !data) {
      return null;
    }

    const rows = data as PricingReportSetCardRawRow[];
    if (rows.length === 0) break;

    totalCount = rows[0]?.total_count ?? 0;
    items.push(...rows.map(mapPricingReportSetCardRow));

    if (items.length >= totalCount || rows.length < PRINT_FETCH_BATCH_SIZE) break;
  }

  return { items, totalCount };
}
