import { CreditCard } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { MapeamentosCartasTable } from "@/components/pricing/mapeamentos-cartas-table";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import {
  PRICING_CARD_MAPPINGS_PAGE_SIZE,
  getPricingCardMappings,
  getPricingCardSetOptions,
  getPricingSources,
  type PricingCardMappingStatus,
} from "@/lib/pricing/queries";

const VALID_STATUS = new Set(["CONFIRMED", "PENDING", "NOT_FOUND", "REJECTED"]);

/**
 * Mapeamentos de Cartas (Bloco 4 do Pricing Admin, migration 3942) —
 * cadastro completo de `pricing_card_mapping`, todos os 4 status (diferente
 * de `/pricing/pendencias`, que só mostra PENDING/NOT_FOUND). Linhas
 * PENDING/NOT_FOUND continuam levando para `/pricing/resolucao-mapeamentos`
 * (fluxo de atribuição de identidades, Bloco 2) — esta tela nunca duplica
 * aquele fluxo, só oferece reclassificação pontual para CONFIRMED/REJECTED.
 */
export default async function PricingMapeamentosCartasPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; status?: string; set?: string; source?: string; page?: string }>;
}) {
  const { denied, supabase } = await requirePricingAdmin("Mapeamentos de Cartas", CreditCard);
  if (denied) return denied;

  const { q, status: statusParam, set: cardSetId, source: pricingSourceId, page: pageParam } = await searchParams;
  const search = q?.trim() ?? "";
  const status = statusParam ?? "";
  const requestedPage = Math.max(0, Number.parseInt(pageParam ?? "0", 10) || 0);

  const statusFilter: PricingCardMappingStatus[] | undefined = VALID_STATUS.has(status)
    ? [status as PricingCardMappingStatus]
    : undefined;

  const filtros = {
    search: search || undefined,
    status: statusFilter,
    cardSetId: cardSetId || undefined,
    pricingSourceId: pricingSourceId || undefined,
  };

  const [cardSets, sources, firstAttempt] = await Promise.all([
    getPricingCardSetOptions(supabase),
    getPricingSources(supabase),
    getPricingCardMappings(supabase, {
      ...filtros,
      limit: PRICING_CARD_MAPPINGS_PAGE_SIZE,
      offset: requestedPage * PRICING_CARD_MAPPINGS_PAGE_SIZE,
    }),
  ]);

  let page = requestedPage;
  let paged = firstAttempt;
  const totalPages = Math.max(1, Math.ceil(firstAttempt.totalCount / PRICING_CARD_MAPPINGS_PAGE_SIZE));
  if (requestedPage > 0 && requestedPage >= totalPages) {
    page = totalPages - 1;
    paged = await getPricingCardMappings(supabase, {
      ...filtros,
      limit: PRICING_CARD_MAPPINGS_PAGE_SIZE,
      offset: page * PRICING_CARD_MAPPINGS_PAGE_SIZE,
    });
  }

  return (
    <AppShell title="Mapeamentos de Cartas" icon={CreditCard}>
      <PageContainer className="space-y-4">
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <CreditCard className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Mapeamentos de Cartas</PageTitle>
            </div>
            <PageDescription>
              Correspondência entre carta local e produto externo por fonte de preço (pricing_card_mapping).
            </PageDescription>
          </PageHeading>
        </PageHeader>

        <MapeamentosCartasTable
          items={paged.items}
          totalCount={paged.totalCount}
          page={page}
          search={search}
          status={status}
          cardSetId={cardSetId ?? ""}
          pricingSourceId={pricingSourceId ?? ""}
          cardSets={cardSets}
          sources={sources}
        />
      </PageContainer>
    </AppShell>
  );
}
