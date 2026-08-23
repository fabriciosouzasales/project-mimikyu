import { Layers } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { MapeamentosSetsTable } from "@/components/pricing/mapeamentos-sets-table";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import {
  PRICING_SET_MAPPINGS_PAGE_SIZE,
  getPricingSetMappings,
  getPricingSources,
  type PricingSetMappingStatus,
} from "@/lib/pricing/queries";

const VALID_STATUS = new Set(["CONFIRMED", "PENDING", "NOT_FOUND", "REJECTED"]);

/**
 * Mapeamentos de Sets (Bloco 4 do Pricing Admin, migration 3942) — cadastro
 * completo de `pricing_set_mapping`, todos os 4 status (diferente de
 * `/pricing/pendencias`, que só mostra PENDING/NOT_FOUND). Paginado/filtrado
 * server-side, mesmo padrão de `/pricing/pendencias` e `/pricing/sincronizacoes`.
 */
export default async function PricingMapeamentosSetsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; status?: string; source?: string; page?: string }>;
}) {
  const { denied, supabase } = await requirePricingAdmin("Mapeamentos de Sets", Layers);
  if (denied) return denied;

  const { q, status: statusParam, source: pricingSourceId, page: pageParam } = await searchParams;
  const search = q?.trim() ?? "";
  const status = statusParam ?? "";
  const requestedPage = Math.max(0, Number.parseInt(pageParam ?? "0", 10) || 0);

  const statusFilter: PricingSetMappingStatus[] | undefined = VALID_STATUS.has(status)
    ? [status as PricingSetMappingStatus]
    : undefined;

  const filtros = {
    search: search || undefined,
    status: statusFilter,
    pricingSourceId: pricingSourceId || undefined,
  };

  const [sources, firstAttempt] = await Promise.all([
    getPricingSources(supabase),
    getPricingSetMappings(supabase, {
      ...filtros,
      limit: PRICING_SET_MAPPINGS_PAGE_SIZE,
      offset: requestedPage * PRICING_SET_MAPPINGS_PAGE_SIZE,
    }),
  ]);

  let page = requestedPage;
  let paged = firstAttempt;
  const totalPages = Math.max(1, Math.ceil(firstAttempt.totalCount / PRICING_SET_MAPPINGS_PAGE_SIZE));
  if (requestedPage > 0 && requestedPage >= totalPages) {
    page = totalPages - 1;
    paged = await getPricingSetMappings(supabase, {
      ...filtros,
      limit: PRICING_SET_MAPPINGS_PAGE_SIZE,
      offset: page * PRICING_SET_MAPPINGS_PAGE_SIZE,
    });
  }

  return (
    <AppShell title="Mapeamentos de Sets" icon={Layers}>
      <PageContainer className="space-y-4">
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <Layers className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Mapeamentos de Sets</PageTitle>
            </div>
            <PageDescription>
              Correspondência entre Card Set local e Set externo por fonte de preço (pricing_set_mapping).
            </PageDescription>
          </PageHeading>
        </PageHeader>

        <MapeamentosSetsTable
          items={paged.items}
          totalCount={paged.totalCount}
          page={page}
          search={search}
          status={status}
          pricingSourceId={pricingSourceId ?? ""}
          sources={sources}
        />
      </PageContainer>
    </AppShell>
  );
}
