import { CircleDollarSign, LayoutDashboard } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Alert } from "@/components/ui/alert";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { PricingOverviewStats } from "@/components/pricing/pricing-overview-stats";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import {
  getPricingAdminOverview,
  getPricingApiUsageDaily,
  getPricingCoverageTrend,
  getPricingSyncRunDaily,
} from "@/lib/pricing/queries";

/**
 * Visão Geral de Valor de Mercado — v3 (2026-08-23), REDESENHO VISUAL da
 * v2 (rejeitada por Fabrício: "funcionalmente correta, mas VISUALMENTE
 * REPROVADA" — hierarquia fraca, gráficos pequenos, pouca "sensação de
 * cockpit gerencial"). Nenhuma RPC/regra/dado mudou nesta rodada — ver
 * `PricingOverviewStats` para o desenho completo dos 5 blocos (Hero
 * Gerencial, 4 KPIs, gráficos em 2 linhas assimétricas, Atenções e Ações
 * acionável, inventário técnico discreto no rodapé).
 *
 * `PageContainer width="wide"` (era o default `max-w-6xl`) — mesma largura
 * já usada pela Visão Geral do Catálogo Editorial para telas com múltiplas
 * colunas de conteúdo (ver `components/ui/page.tsx`); a v2 usava a largura
 * padrão de listagem simples, contribuindo para a sensação de espaço
 * desperdiçado apontada por Fabrício.
 *
 * 4 chamadas RPC, todas agregação server-side (nunca fetch integral de
 * tabela para o frontend calcular indicador): `get_pricing_admin_overview()`
 * (migration 3939), `admin_get_pricing_coverage_trend()` e
 * `admin_get_pricing_sync_run_daily()` (migration 3945/3946 — a segunda
 * NUNCA devolve `cum_total` retroativo, ver `pricing-coverage-trend-chart.tsx`)
 * e `admin_get_pricing_api_usage_daily()` (migration 3947, v3.2 — soma de
 * `pricing_sync_run.requests_made` por dia, alimenta "Consumo da API").
 * As 4 rodam em paralelo (`Promise.all`) — nenhuma depende do resultado da
 * outra.
 *
 * Nomenclatura "Valor de Mercado" (singular, v3.5 — 2026-08-23, ajuste de
 * concordância sobre o teste visual aprovado em 2026-08-22; era "Valores de
 * Mercado" no plural) — `id`/rotas/domínio técnico "Pricing" no banco
 * continuam inalterados, ver `nav-config.ts` e `CLAUDE.md`.
 */
export default async function PricingVisaoGeralPage() {
  const { denied, supabase } = await requirePricingAdmin("Valor de Mercado", CircleDollarSign);
  if (denied) return denied;

  const [overview, trend, syncDaily, apiUsage] = await Promise.all([
    getPricingAdminOverview(supabase),
    getPricingCoverageTrend(supabase, 30),
    getPricingSyncRunDaily(supabase, 14),
    getPricingApiUsageDaily(supabase, 30),
  ]);

  return (
    <AppShell title="Valor de Mercado" icon={CircleDollarSign}>
      <PageContainer width="wide">
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <LayoutDashboard className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Visão Geral</PageTitle>
            </div>
            <PageDescription>
              Acompanhe cobertura de preços, saúde das sincronizações e evolução operacional de Valor de Mercado.
            </PageDescription>
          </PageHeading>
        </PageHeader>

        {overview ? (
          <PricingOverviewStats overview={overview} trend={trend} syncDaily={syncDaily} apiUsage={apiUsage} />
        ) : (
          <Alert variant="destructive">
            Não foi possível carregar os indicadores de Valor de Mercado agora. Tente recarregar a página.
          </Alert>
        )}
      </PageContainer>
    </AppShell>
  );
}
