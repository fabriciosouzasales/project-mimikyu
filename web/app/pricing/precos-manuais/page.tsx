import { PencilLine } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { PrecosManuaisTable } from "@/components/pricing/precos-manuais-table";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import {
  PRICING_MANUAL_PRICE_CANDIDATES_PAGE_SIZE,
  getCardConditions,
  getPricingCardSetOptions,
  getPricingManualPriceCandidates,
} from "@/lib/pricing/queries";

/**
 * Preços Manuais (migrations 3967-3970, frontend 2026-08-27) — fallback
 * manual do preço automático: lista cartas elegíveis via
 * `admin_list_pricing_manual_price_candidates`, sempre escopada a UMA
 * condição por vez (seletor no topo, default Near Mint) para exibir/editar o
 * preço manual daquela condição.
 *
 * Elegibilidade (corrigida em 2026-08-27, migration 3970): estritamente
 * `pricing_card_mapping.match_status = 'NOT_FOUND'` — reconcilia com o KPI
 * "Não encontrados" da Visão Geral. Nunca PENDING, REJECTED, CONFIRMED sem
 * preço automático, ou carta sem mapping. Carta só sai da lista quando o
 * mapping deixa de ser NOT_FOUND (resolvido em Mapeamentos de Cartas) — não
 * quando surge um preço automático utilizável (isso é regra de precedência
 * de LEITURA, AUTOMATIC > MANUAL, migrations 3968/3969, não de listagem).
 * Escrita é sempre append-only via `admin_set_manual_price` (Dialog na
 * tabela) — nunca toca `pricing_card_mapping` nem cria produto/mapping
 * fictício.
 */
export default async function PrecosManuaisPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; condition?: string; set?: string; page?: string }>;
}) {
  const { denied, supabase } = await requirePricingAdmin("Preços Manuais", PencilLine);
  if (denied) return denied;

  const { q, condition: conditionParam, set: cardSetId, page: pageParam } = await searchParams;
  const search = q?.trim() ?? "";
  const requestedPage = Math.max(0, Number.parseInt(pageParam ?? "0", 10) || 0);

  const [conditions, cardSets] = await Promise.all([getCardConditions(supabase), getPricingCardSetOptions(supabase)]);

  const defaultCondition = conditions.find((c) => c.code === "NM") ?? conditions[0];
  const conditionId = conditionParam && conditions.some((c) => c.id === conditionParam) ? conditionParam : (defaultCondition?.id ?? "");

  const filtros = {
    conditionId: conditionId || undefined,
    search: search || undefined,
    cardSetId: cardSetId || undefined,
  };

  const firstAttempt = await getPricingManualPriceCandidates(supabase, {
    ...filtros,
    limit: PRICING_MANUAL_PRICE_CANDIDATES_PAGE_SIZE,
    offset: requestedPage * PRICING_MANUAL_PRICE_CANDIDATES_PAGE_SIZE,
  });

  let page = requestedPage;
  let paged = firstAttempt;
  const totalPages = Math.max(1, Math.ceil(firstAttempt.totalCount / PRICING_MANUAL_PRICE_CANDIDATES_PAGE_SIZE));
  if (requestedPage > 0 && requestedPage >= totalPages) {
    page = totalPages - 1;
    paged = await getPricingManualPriceCandidates(supabase, {
      ...filtros,
      limit: PRICING_MANUAL_PRICE_CANDIDATES_PAGE_SIZE,
      offset: page * PRICING_MANUAL_PRICE_CANDIDATES_PAGE_SIZE,
    });
  }

  return (
    <AppShell title="Preços Manuais" icon={PencilLine}>
      <PageContainer className="space-y-4">
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <PencilLine className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Preços Manuais</PageTitle>
            </div>
            <PageDescription>
              Fallback manual de preço para cartas sem automático utilizável na condição selecionada — cada definição gera
              um novo registro, preservando o histórico anterior.
            </PageDescription>
          </PageHeading>
        </PageHeader>

        <PrecosManuaisTable
          items={paged.items}
          totalCount={paged.totalCount}
          page={page}
          search={search}
          conditionId={conditionId}
          cardSetId={cardSetId ?? ""}
          conditions={conditions}
          cardSets={cardSets}
        />
      </PageContainer>
    </AppShell>
  );
}
