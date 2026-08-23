import { Package } from "lucide-react";
import Link from "next/link";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { Card, CardContent } from "@/components/ui/card";
import {
  DataTable,
  DataTableCell,
  DataTableHead,
  DataTableHeadCell,
  DataTableHeadRow,
  DataTableRow,
} from "@/components/ui/data-table";
import { EmptyState } from "@/components/ui/empty-state";
import { StateBadge } from "@/components/catalogo/state-badge";
import { PriceHistoryChart } from "@/components/pricing/price-history-chart";
import type { PricingReportCard } from "@/lib/pricing/queries";

const TITULO_IMPRESSAO = "Preço por Carta";
const SUBTITULO_IMPRESSAO = "Preço atual por fonte/variante e série temporal de uma Carta específica.";

// Mesmo mapa de `card-price-summary.tsx` (P12) — duplicado deliberadamente,
// não importado de lá: mesma decisão já registrada em
// `lib/pesquisa/format.ts` ("pequena duplicação de funções puras,
// preferível a acoplar" dois módulos que evoluem por pedidos diferentes de
// Fabrício). Rótulos técnicos nunca chegam à tela (pedido de Fabrício,
// 2026-08-18).
const PRINTING_LABEL_PT: Record<string, string> = {
  Normal: "Normal",
  Holofoil: "Holográfica",
  "Reverse Holofoil": "Holográfica reversa",
  Unlimited: "Ilimitada",
  "Unlimited Holofoil": "Ilimitada Holográfica",
  "1st Edition": "1ª Edição",
  "1st Edition Holofoil": "1ª Edição Holográfica",
};

const FX_STATUS_LABEL: Record<string, string> = {
  NATIVE: "Moeda nativa da fonte",
  CONVERTED: "Convertido",
  FX_RATE_UNAVAILABLE: "Câmbio indisponível",
  UNSUPPORTED_CONVERSION: "Conversão não suportada",
};

const dateFormatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });

function translatePrintingLabel(label: string): string {
  return PRINTING_LABEL_PT[label] ?? label;
}

function formatMoney(value: number, currencyCode: string): string {
  try {
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency: currencyCode }).format(value);
  } catch {
    return `${currencyCode} ${value.toFixed(2)}`;
  }
}

/**
 * Relatório "Preço por Carta" (Bloco 5, migration 3943) — puramente
 * apresentacional: recebe o contrato já pronto de
 * `admin_get_pricing_report_card`, nenhuma agregação/cálculo aqui além de
 * formatação. Estados sem cotação (preço atual e histórico) são sinalizados
 * separadamente — a ausência de uma fonte nunca vira "zero" nem some
 * silenciosamente da tabela.
 */
export function PrecoPorCartaReport({ report }: { report: PricingReportCard }) {
  const chartSeries = groupHistoryBySeries(report.history);

  return (
    <div className="space-y-4">
      <Card density="compact">
        <CardContent density="compact" className="flex flex-wrap items-center justify-between gap-3 pt-4">
          <div>
            <div className="flex items-center gap-2">
              <p className="text-base font-semibold text-foreground">{report.card.name}</p>
              {!report.card.isActive && <StateBadge tone="muted">Inativa</StateBadge>}
            </div>
            <p className="text-xs text-muted-foreground">
              {report.card.cardSetName} ({report.card.cardSetCode}) · {report.card.collectorNumber.padStart(3, "0")}/
              {report.card.collectorTotal != null ? String(report.card.collectorTotal).padStart(3, "0") : "???"}
            </p>
            <Link
              href={`/pricing/relatorios/valor-por-set?set=${report.card.cardSetId}`}
              className="mt-1 inline-flex items-center gap-1 text-xs text-primary-ink hover:underline"
            >
              <Package className="h-3 w-3" aria-hidden="true" />
              Ver valor do Set {report.card.cardSetCode}
            </Link>
          </div>
          <p className="text-xs text-muted-foreground">
            Condição avaliada: <span className="font-medium text-foreground">{report.condition.name}</span>
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-0">
          {report.currentPrices.length === 0 ? (
            <EmptyState
              title="Sem cotação disponível"
              description={`Nenhuma fonte tem preço confirmado para ${report.condition.name} em ${report.currency}.`}
            />
          ) : (
            <DataTable>
              <DataTableHead>
                <DataTableHeadRow>
                  <DataTableHeadCell>Fonte</DataTableHeadCell>
                  <DataTableHeadCell>Variante</DataTableHeadCell>
                  <DataTableHeadCell align="right">Preço ({report.currency})</DataTableHeadCell>
                  <DataTableHeadCell>Câmbio</DataTableHeadCell>
                  <DataTableHeadCell>Observado em</DataTableHeadCell>
                </DataTableHeadRow>
              </DataTableHead>
              <tbody>
                {report.currentPrices.map((price, index) => (
                  <DataTableRow key={`${price.pricingSourceId}-${price.printingLabel}-${index}`}>
                    <DataTableCell className="font-medium text-foreground">{price.pricingSourceCode}</DataTableCell>
                    <DataTableCell>{translatePrintingLabel(price.printingLabel)}</DataTableCell>
                    <DataTableCell align="right" className="font-medium text-foreground">
                      {price.priceDisplay !== null ? (
                        formatMoney(price.priceDisplay, report.currency)
                      ) : (
                        <span className="font-normal text-muted-foreground">Sem cotação em {report.currency}</span>
                      )}
                    </DataTableCell>
                    <DataTableCell>
                      <div className="space-y-0.5">
                        <p>{FX_STATUS_LABEL[price.fxStatus] ?? price.fxStatus}</p>
                        {price.fxStatus === "CONVERTED" && price.fxRate !== null && (
                          <p className="text-[11px] text-muted-foreground">
                            {formatMoney(price.priceNative, price.currencyNative)} · taxa {price.fxRate.toFixed(4)}
                            {price.fxRateDate ? ` (${dateFormatter.format(new Date(price.fxRateDate))})` : ""}
                            {price.fxSource ? ` · ${price.fxSource}` : ""}
                          </p>
                        )}
                      </div>
                    </DataTableCell>
                    <DataTableCell>{dateFormatter.format(new Date(price.observedAt))}</DataTableCell>
                  </DataTableRow>
                ))}
              </tbody>
            </DataTable>
          )}
        </CardContent>
      </Card>

      <Card density="compact">
        <CardContent density="compact" className="space-y-3 pt-4">
          <p className="text-sm font-medium text-foreground">
            Histórico de preço — últimos {report.historyDays} dias
          </p>
          {chartSeries.length === 0 ? (
            <EmptyState title="Sem histórico no período selecionado" description="Amplie o período ou aguarde novas observações." />
          ) : (
            <PriceHistoryChart series={chartSeries} />
          )}
        </CardContent>
      </Card>
    </div>
  );
}

/**
 * Folha imprimível de "Preço por Carta" — requisito transversal da Central
 * de Relatórios (2026-08-22): mesmo mecanismo já adotado nos 8 relatórios do
 * Catálogo Editorial (`RelatorioFolha`/`RelatorioCabecalho`/`RelatorioRodape`,
 * `window.print()` via `RelatorioPrintButton` no `PageHeader`), sem CSS de
 * impressão paralelo. Fica `hidden print:block` — nunca aparece na tela, só
 * no preview/saída de impressão — enquanto `PrecoPorCartaReport` (dashboard
 * interativo) recebe `print:hidden` no ponto de uso (`page.tsx`). Consome o
 * mesmo `report` já filtrado que está em tela — nenhuma chamada extra, então
 * a impressão reflete exatamente condição/moeda/período selecionados no
 * momento do clique em Imprimir. Reaproveita os mesmos helpers de formatação
 * de `PrecoPorCartaReport` (nenhuma duplicação de lógica de apresentação).
 *
 * Ressalva registrada: `PriceHistoryChart` usa `currentColor`/tokens de tema
 * (`text-border`, `text-muted-foreground`) nos eixos/grade do SVG — cores que
 * acompanham claro/escuro do app, ao contrário do resto da folha
 * (`neutral-*` fixo, sempre branco). Reaproveitado sem alteração (o
 * componente é o mesmo usado em tela, "sem solução paralela"); se o eixo
 * ficar pouco legível impresso a partir do tema escuro, é um ajuste futuro
 * no próprio `PriceHistoryChart`, não deste incremento.
 */
export function PrecoPorCartaPrintFolha({ report }: { report: PricingReportCard }) {
  const chartSeries = groupHistoryBySeries(report.history);
  const identificacaoCarta = `${report.card.name} · ${report.card.collectorNumber.padStart(3, "0")}/${
    report.card.collectorTotal != null ? String(report.card.collectorTotal).padStart(3, "0") : "???"
  }`;

  return (
    <div className="hidden print:block">
      <RelatorioFolha>
        <RelatorioCabecalho
          titulo={TITULO_IMPRESSAO}
          subtitulo={SUBTITULO_IMPRESSAO}
          identificacaoColecao={identificacaoCarta}
        />

        <div className="space-y-3 px-6 pb-6 print:px-0">
          <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 border-b border-neutral-200 pb-2 text-[10px] text-neutral-500">
            <span>
              {report.card.cardSetName} ({report.card.cardSetCode})
              {!report.card.isActive ? " · Inativa" : ""}
            </span>
            <span>
              Condição {report.condition.name} · Moeda {report.currency} · Histórico {report.historyDays} dias
            </span>
          </div>

          {report.currentPrices.length === 0 ? (
            <p className="text-xs text-neutral-500">
              Nenhuma fonte tem preço confirmado para {report.condition.name} em {report.currency}.
            </p>
          ) : (
            <table className="w-full text-[10px]">
              <thead>
                <tr className="border-b border-neutral-300 text-left uppercase tracking-wide text-neutral-500">
                  <th className="py-1 pr-2 font-normal">Fonte</th>
                  <th className="py-1 pr-2 font-normal">Variante</th>
                  <th className="py-1 pr-2 text-right font-normal">Preço ({report.currency})</th>
                  <th className="py-1 pr-2 font-normal">Câmbio</th>
                  <th className="py-1 font-normal">Observado em</th>
                </tr>
              </thead>
              <tbody>
                {report.currentPrices.map((price, index) => (
                  <tr key={`${price.pricingSourceId}-${price.printingLabel}-${index}`} className="border-b border-neutral-100">
                    <td className="py-1 pr-2 font-medium text-neutral-900">{price.pricingSourceCode}</td>
                    <td className="py-1 pr-2 text-neutral-700">{translatePrintingLabel(price.printingLabel)}</td>
                    <td className="py-1 pr-2 text-right font-medium text-neutral-900">
                      {price.priceDisplay !== null ? (
                        formatMoney(price.priceDisplay, report.currency)
                      ) : (
                        <span className="font-normal text-neutral-500">Sem cotação em {report.currency}</span>
                      )}
                    </td>
                    <td className="py-1 pr-2 text-neutral-700">
                      {FX_STATUS_LABEL[price.fxStatus] ?? price.fxStatus}
                      {price.fxStatus === "CONVERTED" && price.fxRate !== null && (
                        <span className="block text-[9px] text-neutral-500">
                          {formatMoney(price.priceNative, price.currencyNative)} · taxa {price.fxRate.toFixed(4)}
                          {price.fxRateDate ? ` (${dateFormatter.format(new Date(price.fxRateDate))})` : ""}
                        </span>
                      )}
                    </td>
                    <td className="py-1 text-neutral-700">{dateFormatter.format(new Date(price.observedAt))}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

          <div className="space-y-1.5 border-t border-neutral-200 pt-2">
            <p className="text-[10px] font-medium text-neutral-700">
              Histórico de preço — últimos {report.historyDays} dias
            </p>
            {chartSeries.length === 0 ? (
              <p className="text-[10px] text-neutral-500">Sem histórico no período selecionado.</p>
            ) : (
              <PriceHistoryChart series={chartSeries} />
            )}
          </div>
        </div>

        <RelatorioRodape />
      </RelatorioFolha>
    </div>
  );
}

function groupHistoryBySeries(history: PricingReportCard["history"]) {
  const bySeries = new Map<string, { label: string; points: Array<{ observedAt: string; price: number }> }>();
  for (const point of history) {
    const label = `${point.pricingSourceCode} · ${translatePrintingLabel(point.printingLabel)}`;
    const key = `${point.pricingSourceId}-${point.printingLabel}`;
    let series = bySeries.get(key);
    if (!series) {
      series = { label, points: [] };
      bySeries.set(key, series);
    }
    series.points.push({ observedAt: point.observedAt, price: point.price });
  }
  return Array.from(bySeries.values());
}
