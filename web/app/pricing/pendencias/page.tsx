import { AlertTriangle } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { PendenciasTable } from "@/components/pricing/pendencias-table";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import {
  PRICING_PENDING_MAPPINGS_PAGE_SIZE,
  getPricingCardSetOptions,
  getPricingPendingMappings,
  type PricingPendingMappingStatus,
} from "@/lib/pricing/queries";

/**
 * Pendências (Bloco 2 do Pricing Admin, migration 3940) — fila única de
 * mapeamentos PENDING + NOT_FOUND, sempre paginada/filtrada server-side via
 * `admin_list_pricing_pending_mappings` (decisão explícita de Fabrício:
 * "NOT_FOUND permanece dentro de Pendências"; a RPC trava esse vocabulário
 * no próprio SQL, então nem um filtro incorreto aqui conseguiria vazar
 * CONFIRMED/REJECTED). Mesmo padrão de paginação/URL de
 * `app/catalogo/log-atualizacoes/page.tsx`: `searchParams` como `Promise`
 * (Next 15), reconsulta com offset corrigido se a página pedida ficou fora
 * do intervalo depois de um filtro reduzir o total.
 */
export default async function PricingPendenciasPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; status?: string; set?: string; page?: string }>;
}) {
  const { denied, supabase } = await requirePricingAdmin("Pendências", AlertTriangle);
  if (denied) return denied;

  const { q, status: statusParam, set: cardSetId, page: pageParam } = await searchParams;
  const search = q?.trim() ?? "";
  const status = statusParam ?? "";
  const requestedPage = Math.max(0, Number.parseInt(pageParam ?? "0", 10) || 0);

  const statusFilter: PricingPendingMappingStatus[] | undefined =
    status === "PENDING" || status === "NOT_FOUND" ? [status] : undefined;

  const filtros = {
    search: search || undefined,
    status: statusFilter,
    cardSetId: cardSetId || undefined,
  };

  const [cardSets, firstAttempt] = await Promise.all([
    getPricingCardSetOptions(supabase),
    getPricingPendingMappings(supabase, {
      ...filtros,
      limit: PRICING_PENDING_MAPPINGS_PAGE_SIZE,
      offset: requestedPage * PRICING_PENDING_MAPPINGS_PAGE_SIZE,
    }),
  ]);

  let page = requestedPage;
  let paged = firstAttempt;
  const totalPages = Math.max(1, Math.ceil(firstAttempt.totalCount / PRICING_PENDING_MAPPINGS_PAGE_SIZE));
  if (requestedPage > 0 && requestedPage >= totalPages) {
    page = totalPages - 1;
    paged = await getPricingPendingMappings(supabase, {
      ...filtros,
      limit: PRICING_PENDING_MAPPINGS_PAGE_SIZE,
      offset: page * PRICING_PENDING_MAPPINGS_PAGE_SIZE,
    });
  }

  return (
    <AppShell title="Pendências" icon={AlertTriangle}>
      <PageContainer className="space-y-4">
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Pendências</PageTitle>
            </div>
            <PageDescription>
              Mapeamentos PENDING e NOT_FOUND aguardando resolução, por Set e por carta.
            </PageDescription>
          </PageHeading>
        </PageHeader>

        <PendenciasTable
          items={paged.items}
          totalCount={paged.totalCount}
          page={page}
          search={search}
          status={status}
          cardSetId={cardSetId ?? ""}
          cardSets={cardSets}
        />
      </PageContainer>
    </AppShell>
  );
}
