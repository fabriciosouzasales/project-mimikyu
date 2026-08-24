import { Activity } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { PricingFontesHero } from "@/components/pricing/pricing-fontes-hero";
import { SaudeFontesList } from "@/components/pricing/saude-fontes-list";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { getPricingSourceHealth } from "@/lib/pricing/queries";
import { computePricingSourceHealthStatus } from "@/lib/pricing/pricing-source-health-status";

/**
 * Saúde das Fontes (Bloco 3 do Pricing Admin, migration 3941) — uma linha
 * por fonte de preço com status/última sincronização/cobertura/Sets
 * saudáveis-com problema-pausados/erros recentes, toda a agregação em SQL
 * via `admin_get_pricing_source_health()`. Sem paginação/filtro nesta tela
 * (pedido de Fabrício não inclui — o volume é 1 linha por fonte, hoje só
 * JUSTTCG).
 *
 * Hero Gerencial (2026-08-23) — retomada do refinamento visual logo após o
 * encerramento do P0 de performance de `/pricing`, "tratamento Hero
 * completo" explicitamente escolhido por Fabrício (mesmo padrão da Visão
 * Geral). `PricingFontesHero` faz o roll-up dos mesmos campos já mostrados
 * por fonte em `SaudeFontesList` — nenhuma RPC nova, nenhum dado novo. Ver
 * `pricing-fontes-hero.tsx` e `pricing-source-health-status.ts`.
 */
export default async function PricingSaudeFontesPage() {
  const { denied, supabase } = await requirePricingAdmin("Saúde das Fontes", Activity);
  if (denied) return denied;

  const sources = await getPricingSourceHealth(supabase);
  const status = computePricingSourceHealthStatus(sources);

  return (
    <AppShell title="Saúde das Fontes" icon={Activity}>
      <PageContainer className="space-y-4">
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <Activity className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Saúde das Fontes</PageTitle>
            </div>
            <PageDescription>
              Disponibilidade, cobertura, erros e qualidade/atualização por fonte de preço.
            </PageDescription>
          </PageHeading>
        </PageHeader>

        <PricingFontesHero sources={sources} status={status} />

        <SaudeFontesList sources={sources} />
      </PageContainer>
    </AppShell>
  );
}
