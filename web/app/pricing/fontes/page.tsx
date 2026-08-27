import { Globe } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { PricingSourcesTable } from "@/components/pricing/pricing-sources-table";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { getPricingSources } from "@/lib/pricing/queries";

/**
 * Fontes de Preço (Bloco 4 do Pricing Admin, migration 3942) — cadastro e
 * configuração de metadados de `pricing_source` (hoje só JUSTTCG). Sem
 * criação/exclusão nesta V1 — só edição via `admin_update_pricing_source`;
 * `frequency_days` continua vivendo em /pricing/sincronizacoes, não aqui.
 */
export default async function PricingFontesPage() {
  const { denied, supabase } = await requirePricingAdmin("Fontes de Preço", Globe);
  if (denied) return denied;

  const sources = await getPricingSources(supabase);

  return (
    <AppShell title="Fontes de Preço" icon={Globe}>
      <PageContainer className="space-y-4">
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <Globe className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Fontes de Preço</PageTitle>
            </div>
            <PageDescription>Gerencie as fontes externas utilizadas para obtenção de preços de mercado.</PageDescription>
          </PageHeading>
        </PageHeader>

        <PricingSourcesTable sources={sources} />
      </PageContainer>
    </AppShell>
  );
}
