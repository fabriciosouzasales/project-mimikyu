import { CreditCard } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { MapeamentosCartasTable } from "@/components/pricing/mapeamentos-cartas-table";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import {
  PRICING_CARD_MAPPINGS_PAGE_SIZE,
  getPricingCardMappingIssues,
  getPricingCardSetOptions,
  getPricingSources,
  type PricingCardMappingIssueStatus,
} from "@/lib/pricing/queries";

const VALID_STATUS = new Set(["PENDING", "NOT_FOUND", "REJECTED"]);

/**
 * Mapeamentos de Cartas (Bloco 4 do Pricing Admin, migration 3942;
 * convergência com Pendências em 2026-08-27) — fila operacional de
 * exceções de `pricing_card_mapping`: PENDING/NOT_FOUND/REJECTED, nunca
 * CONFIRMED (nem por filtro — `admin_list_pricing_card_mapping_issues`
 * trava isso no próprio SQL). Absorveu o papel de `/pricing/pendencias`
 * (aposentada, redirect 307 para cá). Linhas PENDING/NOT_FOUND levam para
 * `/pricing/resolucao-mapeamentos` (fluxo de atribuição de identidades,
 * Bloco 2); linhas REJECTED abrem o dialog de reclassificação para
 * CONFIRMED, com hardening (migration 3962) que exige identity PRIMARY já
 * confirmada. CONFIRMED continua consultável só por SQL direto, via
 * `admin_list_pricing_card_mappings` (preservada sem consumidor de UI —
 * decisão de Fabrício de não perder a auditoria por completo).
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

  const statusFilter: PricingCardMappingIssueStatus[] | undefined = VALID_STATUS.has(status)
    ? [status as PricingCardMappingIssueStatus]
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
    getPricingCardMappingIssues(supabase, {
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
    paged = await getPricingCardMappingIssues(supabase, {
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
