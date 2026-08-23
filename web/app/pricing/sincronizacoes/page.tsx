import { RefreshCw } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { DispatcherStatusPanel } from "@/components/pricing/dispatcher-status-panel";
import { EstadoSetsTable } from "@/components/pricing/estado-sets-table";
import { PoliticaSincronizacaoPanel } from "@/components/pricing/politica-sincronizacao-panel";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import {
  PRICING_SET_REFRESH_STATES_PAGE_SIZE,
  getPricingAdminOverview,
  getPricingRefreshPolicy,
  getPricingSetRefreshStates,
  type PricingSetRefreshDerivedStatus,
} from "@/lib/pricing/queries";

const VALID_STATUS = new Set(["HEALTHY", "PROBLEM", "PAUSED"]);

/**
 * Sincronizações (Bloco 3 do Pricing Admin, grupo "Operações") — três
 * blocos: (1) Política de Sincronização, frequência editável por fonte via
 * `admin_set_pricing_refresh_frequency` (migrations 3937/3938, reusadas,
 * não novas); (2) Dispatcher, status só-leitura vindo de
 * `get_pricing_admin_overview()` (Bloco 1) — sem disparo manual nesta V1,
 * decisão explícita de Fabrício; (3) Estado dos Sets, visão operacional por
 * `pricing_set_refresh_state` via `admin_list_pricing_set_refresh_states`
 * (migration 3941), paginada/filtrada server-side.
 */
export default async function PricingSincronizacoesPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; status?: string; source?: string; page?: string }>;
}) {
  const { denied, supabase } = await requirePricingAdmin("Sincronizações", RefreshCw);
  if (denied) return denied;

  const { q: search, status: statusParam, source: pricingSourceId, page: pageParam } = await searchParams;
  const status = statusParam ?? "";
  const requestedPage = Math.max(0, Number.parseInt(pageParam ?? "0", 10) || 0);

  const statusFilter: PricingSetRefreshDerivedStatus[] | undefined = VALID_STATUS.has(status)
    ? [status as PricingSetRefreshDerivedStatus]
    : undefined;

  const setsFiltros = {
    search: search || undefined,
    status: statusFilter,
    pricingSourceId: pricingSourceId || undefined,
  };

  const [overview, policies, firstAttempt] = await Promise.all([
    getPricingAdminOverview(supabase),
    getPricingRefreshPolicy(supabase),
    getPricingSetRefreshStates(supabase, {
      ...setsFiltros,
      limit: PRICING_SET_REFRESH_STATES_PAGE_SIZE,
      offset: requestedPage * PRICING_SET_REFRESH_STATES_PAGE_SIZE,
    }),
  ]);

  let page = requestedPage;
  let paged = firstAttempt;
  const totalPages = Math.max(1, Math.ceil(firstAttempt.totalCount / PRICING_SET_REFRESH_STATES_PAGE_SIZE));
  if (requestedPage > 0 && requestedPage >= totalPages) {
    page = totalPages - 1;
    paged = await getPricingSetRefreshStates(supabase, {
      ...setsFiltros,
      limit: PRICING_SET_REFRESH_STATES_PAGE_SIZE,
      offset: page * PRICING_SET_REFRESH_STATES_PAGE_SIZE,
    });
  }

  return (
    <AppShell title="Sincronizações" icon={RefreshCw}>
      <PageContainer className="space-y-4">
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <RefreshCw className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Sincronizações</PageTitle>
            </div>
            <PageDescription>
              Política de refresh por fonte, status do dispatcher automático e estado operacional por Set.
            </PageDescription>
          </PageHeading>
        </PageHeader>

        <div className="grid gap-3 md:grid-cols-2">
          <PoliticaSincronizacaoPanel policies={policies} />
          {overview ? (
            <DispatcherStatusPanel overview={overview} />
          ) : (
            <div className="rounded-lg border border-border bg-surface p-4 text-xs text-muted-foreground">
              Não foi possível carregar o status do dispatcher.
            </div>
          )}
        </div>

        <EstadoSetsTable
          items={paged.items}
          totalCount={paged.totalCount}
          page={page}
          search={search ?? ""}
          status={status}
          pricingSourceId={pricingSourceId ?? ""}
          sources={policies}
        />
      </PageContainer>
    </AppShell>
  );
}
