import { History } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { HistoricoExecucoesTable } from "@/components/pricing/historico-execucoes-table";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import {
  PRICING_SYNC_RUNS_PAGE_SIZE,
  getPricingCardSetOptions,
  getPricingSyncRuns,
  type PricingSyncRunStatus,
} from "@/lib/pricing/queries";

const VALID_STATUS = new Set(["COMPLETED", "COMPLETED_WITH_ERRORS", "FAILED"]);

/**
 * Histórico de Execuções (Bloco 3 do Pricing Admin, migration 3941) —
 * `pricing_sync_run` paginado/filtrado server-side via
 * `admin_list_pricing_sync_runs` (status/Set/período), mesmo padrão de
 * paginação/URL de `PricingPendenciasPage`. O filtro de Set usa
 * `pricing_set_mapping_id` internamente (decisão de Fabrício) — runs sem Set
 * associado (ex.: FX_REFRESH) continuam visíveis sem esse filtro ativo.
 */
export default async function PricingHistoricoExecucoesPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; set?: string; de?: string; ate?: string; page?: string }>;
}) {
  const { denied, supabase } = await requirePricingAdmin("Histórico de Execuções", History);
  if (denied) return denied;

  const { status: statusParam, set: cardSetId, de: dateFrom, ate: dateTo, page: pageParam } = await searchParams;
  const status = statusParam ?? "";
  const requestedPage = Math.max(0, Number.parseInt(pageParam ?? "0", 10) || 0);

  const statusFilter: PricingSyncRunStatus[] | undefined = VALID_STATUS.has(status)
    ? [status as PricingSyncRunStatus]
    : undefined;

  const filtros = {
    status: statusFilter,
    cardSetId: cardSetId || undefined,
    dateFrom: dateFrom || undefined,
    dateTo: dateTo || undefined,
  };

  const [cardSets, firstAttempt] = await Promise.all([
    getPricingCardSetOptions(supabase),
    getPricingSyncRuns(supabase, {
      ...filtros,
      limit: PRICING_SYNC_RUNS_PAGE_SIZE,
      offset: requestedPage * PRICING_SYNC_RUNS_PAGE_SIZE,
    }),
  ]);

  let page = requestedPage;
  let paged = firstAttempt;
  const totalPages = Math.max(1, Math.ceil(firstAttempt.totalCount / PRICING_SYNC_RUNS_PAGE_SIZE));
  if (requestedPage > 0 && requestedPage >= totalPages) {
    page = totalPages - 1;
    paged = await getPricingSyncRuns(supabase, {
      ...filtros,
      limit: PRICING_SYNC_RUNS_PAGE_SIZE,
      offset: page * PRICING_SYNC_RUNS_PAGE_SIZE,
    });
  }

  return (
    <AppShell title="Histórico de Execuções" icon={History}>
      <PageContainer className="space-y-4">
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <History className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Histórico de Execuções</PageTitle>
            </div>
            <PageDescription>
              Execuções de sincronização: status, duração, requisições, rate limits e erros.
            </PageDescription>
          </PageHeading>
        </PageHeader>

        <HistoricoExecucoesTable
          items={paged.items}
          totalCount={paged.totalCount}
          page={page}
          status={status}
          cardSetId={cardSetId ?? ""}
          dateFrom={dateFrom ?? ""}
          dateTo={dateTo ?? ""}
          cardSets={cardSets}
        />
      </PageContainer>
    </AppShell>
  );
}
