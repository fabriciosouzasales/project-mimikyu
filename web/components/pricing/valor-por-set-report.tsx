import { CheckCircle2, CircleDollarSign, Package } from "lucide-react";
import { Alert } from "@/components/ui/alert";
import { StatCard, StatsRow } from "@/components/catalogo/stat-card";
import type { PricingReportSet } from "@/lib/pricing/queries";

function formatMoney(value: number, currencyCode: string): string {
  try {
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency: currencyCode }).format(value);
  } catch {
    return `${currencyCode} ${value.toFixed(2)}`;
  }
}

function formatPercent(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 1 }).format(value) + "%";
}

/**
 * Relatório "Valor por Set" (Bloco 5, migration 3943) — puramente
 * apresentacional, agregado. `estimatedValueCovered` é sempre o valor
 * COBERTO, nunca uma estimativa do Set inteiro — `isPartial`/`noPriceCount`
 * tornam essa distinção explícita na tela, nunca escondida atrás de um
 * número só. A lista/ranking de cartas que compõem este valuation é
 * renderizada separadamente por `ValorPorSetCardsTable` (migration 3944).
 */
export function ValorPorSetReport({ report }: { report: PricingReportSet }) {
  const coverageCaption = `${report.pricedConvertibleCount}/${report.totalActiveCards} cartas ativas`;
  const noPriceCaption =
    report.pricedFxUnavailableCount > 0
      ? `Inclui ${report.pricedFxUnavailableCount} com câmbio indisponível`
      : "Nenhuma fonte tem preço confirmado";

  return (
    <div className="space-y-4">
      <StatsRow>
        <StatCard
          label="Valor Estimado Coberto"
          value={formatMoney(report.estimatedValueCovered, report.currency)}
          caption={`Condição ${report.condition.name}`}
          icon={CircleDollarSign}
        />
        <StatCard label="Cobertura" value={formatPercent(report.coveragePct)} caption={coverageCaption} icon={CheckCircle2} />
        <StatCard
          label="Sem Cotação"
          value={report.noPriceCount}
          caption={noPriceCaption}
          icon={Package}
          tone={report.noPriceCount > 0 ? "danger" : "default"}
        />
      </StatsRow>

      {report.isPartial && (
        <Alert variant="warning">
          <p className="font-medium">Valor parcial — cobertura incompleta</p>
          <p className="mt-1 text-xs">
            {report.noPriceCount} carta(s) ativa(s) deste Set não têm cotação confirmada nesta condição/moeda — o valor
            acima soma só as cartas com preço, nunca trata a ausência de cotação como zero.
          </p>
        </Alert>
      )}
    </div>
  );
}
