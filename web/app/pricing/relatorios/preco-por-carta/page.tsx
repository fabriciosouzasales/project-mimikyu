import { CreditCard } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { RelatorioPrintButton } from "@/components/catalogo/relatorio-print-button";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { CardPicker } from "@/components/pricing/card-picker";
import { PrecoPorCartaFiltros } from "@/components/pricing/preco-por-carta-filtros";
import { PrecoPorCartaPrintFolha, PrecoPorCartaReport } from "@/components/pricing/preco-por-carta-report";
import { EmptyState } from "@/components/ui/empty-state";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { getCardConditions, getPricingReportCard, type PricingReportCurrency } from "@/lib/pricing/queries";

const DAY_PRESETS = [30, 90, 180, 365] as const;
const VALID_CURRENCIES = new Set(["BRL", "USD"]);

/**
 * Preço por Carta (Bloco 5, migration 3943) — busca/seleção de Carta,
 * condição (padrão NM), moeda (padrão BRL, opção USD), preço atual por
 * fonte/variante e série temporal. Consome só `admin_get_pricing_report_card`
 * — nenhuma agregação no frontend, tudo já vem pronto do RPC (pedido
 * explícito de Fabrício ao autorizar este bloco).
 *
 * Impressão (requisito transversal, 2026-08-22): mesmo padrão dos 8
 * relatórios do Catálogo Editorial — `RelatorioPrintButton` no `PageHeader`
 * (`print:hidden`), busca/filtros também `print:hidden`, e uma
 * `PrecoPorCartaPrintFolha` (`RelatorioFolha`/`Cabecalho`/`Rodape`) que só
 * aparece em impressão, consumindo o mesmo `report` já filtrado exibido em
 * tela — nunca uma segunda busca.
 */
export default async function PrecoPorCartaPage({
  searchParams,
}: {
  searchParams: Promise<{ card?: string; condition?: string; currency?: string; days?: string }>;
}) {
  const { denied, supabase } = await requirePricingAdmin("Preço por Carta", CreditCard);
  if (denied) return denied;

  const { card: cardId, condition: conditionParam, currency: currencyParam, days: daysParam } = await searchParams;

  const conditions = await getCardConditions(supabase);
  const defaultConditionId = conditions.find((c) => c.code === "NM")?.id ?? conditions[0]?.id ?? "";
  const conditionId = conditionParam || defaultConditionId;
  const currency: PricingReportCurrency = VALID_CURRENCIES.has(currencyParam ?? "")
    ? (currencyParam as PricingReportCurrency)
    : "BRL";
  const parsedDays = Number.parseInt(daysParam ?? "", 10);
  const historyDays = (DAY_PRESETS as readonly number[]).includes(parsedDays) ? parsedDays : 90;

  const report = cardId
    ? await getPricingReportCard(supabase, { cardId, conditionId: conditionId || undefined, currency, historyDays })
    : null;

  return (
    <AppShell title="Preço por Carta" icon={CreditCard}>
      <PageContainer className="space-y-4">
        <PageHeader className="print:hidden">
          <PageHeading>
            <div className="flex items-center gap-2">
              <CreditCard className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Preço por Carta</PageTitle>
            </div>
            <PageDescription>Preço atual por fonte/variante e série temporal de uma Carta específica.</PageDescription>
          </PageHeading>
          {report && <RelatorioPrintButton />}
        </PageHeader>

        <div className="print:hidden">
          <CardPicker />
        </div>

        {!cardId ? (
          <EmptyState
            title="Busque uma Carta para ver o relatório"
            description="Use o campo acima para localizar a Carta pelo nome ou número."
          />
        ) : !report ? (
          <EmptyState
            title="Carta não encontrada"
            description="A Carta buscada pode ter sido removida, ou o filtro de condição/moeda ficou inválido."
          />
        ) : (
          <>
            <div className="print:hidden">
              <PrecoPorCartaFiltros
                conditions={conditions}
                conditionId={report.condition.id}
                currency={report.currency}
                historyDays={report.historyDays}
              />
            </div>
            <div className="print:hidden">
              <PrecoPorCartaReport report={report} />
            </div>
            <PrecoPorCartaPrintFolha report={report} />
          </>
        )}
      </PageContainer>
    </AppShell>
  );
}
