import { Tag } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { CardConditionsTable } from "@/components/pricing/card-conditions-table";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { getCardConditions, getPricingSources } from "@/lib/pricing/queries";

/**
 * Condições (Bloco 4 do Pricing Admin, migration 3942) — vocabulário
 * canônico de conservação (`card_condition`) e seu vínculo por fonte externa
 * (`pricing_condition_mapping`). Sem paginação (hoje 5 condições × 1 fonte).
 */
export default async function PricingCondicoesPage() {
  const { denied, supabase } = await requirePricingAdmin("Condições", Tag);
  if (denied) return denied;

  const [conditions, sources] = await Promise.all([getCardConditions(supabase), getPricingSources(supabase)]);

  return (
    <AppShell title="Condições" icon={Tag}>
      <PageContainer className="space-y-4">
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <Tag className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Condições</PageTitle>
            </div>
            <PageDescription>Vocabulário canônico de condição de conservação (card_condition) e mapeamento por fonte.</PageDescription>
          </PageHeading>
        </PageHeader>

        <CardConditionsTable conditions={conditions} sources={sources} />
      </PageContainer>
    </AppShell>
  );
}
