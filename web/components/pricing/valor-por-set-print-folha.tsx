import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { PRICING_REPORT_SET_CARDS_PAGE_SIZE, type PricingReportSet, type PricingReportSetCardItem } from "@/lib/pricing/queries";

const TITULO = "Valor por Set";
const SUBTITULO = "Valor estimado coberto e cobertura de preço das Cartas ativas de um Set.";

const STATUS_LABEL: Record<string, string> = {
  PRICED: "Com preço",
  FX_UNAVAILABLE: "Câmbio indisponível",
  NO_PRICE: "Sem cotação",
};

function formatMoney(value: number, currencyCode: string): string {
  try {
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency: currencyCode }).format(value);
  } catch {
    return `${currencyCode} ${value.toFixed(2)}`;
  }
}

function formatPercent(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 }).format(value) + "%";
}

/**
 * Folha imprimível de "Valor por Set" — requisito transversal da Central de
 * Relatórios (2026-08-22), mesmo mecanismo do Catálogo Editorial
 * (`RelatorioFolha`/`RelatorioCabecalho`/`RelatorioRodape`, acionado por
 * `RelatorioPrintButton` no `PageHeader`). `hidden print:block` — só existe
 * na saída de impressão; o dashboard interativo (seletores, `StatCard`s,
 * `ValorPorSetCardsTable` com paginação) recebe `print:hidden` no ponto de
 * uso (`page.tsx`).
 *
 * Consome exatamente o `report` (agregado) e a página atual de `cards`
 * (`admin_get_pricing_report_set_cards`) já carregados para a tela — nenhuma
 * chamada extra. Como o ranking é paginado (20 cartas/página), a impressão
 * reflete só a página exibida no momento — mesmo princípio de "a impressão
 * reflete exatamente o estado filtrado exibido na tela": não busca as
 * páginas restantes por trás, e o texto "Mostrando X–Y de Z" deixa isso
 * explícito na folha, replicando a legenda de paginação já usada em tela.
 */
export function ValorPorSetPrintFolha({
  report,
  cardSet,
  cards,
  page,
}: {
  report: PricingReportSet;
  cardSet: { code: string; name: string; expansionName: string | null; logoUrl: string | null } | null;
  cards: { items: PricingReportSetCardItem[]; totalCount: number };
  page: number;
}) {
  const totalPages = Math.max(1, Math.ceil(cards.totalCount / PRICING_REPORT_SET_CARDS_PAGE_SIZE));
  const primeiraLinha = cards.totalCount === 0 ? 0 : page * PRICING_REPORT_SET_CARDS_PAGE_SIZE + 1;
  const ultimaLinha = Math.min((page + 1) * PRICING_REPORT_SET_CARDS_PAGE_SIZE, cards.totalCount);

  return (
    <div className="hidden print:block">
      <RelatorioFolha>
        <RelatorioCabecalho
          titulo={TITULO}
          subtitulo={SUBTITULO}
          identificacaoColecao={cardSet ? `${cardSet.code} · ${cardSet.name}` : undefined}
          colecaoLogoUrl={cardSet?.logoUrl ?? null}
        />

        <div className="space-y-3 px-6 pb-6 print:px-0">
          <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 border-b border-neutral-200 pb-2 text-[10px] text-neutral-500">
            <span>{cardSet?.expansionName ?? ""}</span>
            <span>
              Condição {report.condition.name} · Moeda {report.currency}
            </span>
          </div>

          <div className="grid grid-cols-3 gap-x-4 gap-y-2 text-xs">
            <div>
              <p className="text-[10px] text-neutral-500">Valor estimado coberto</p>
              <p className="font-medium text-neutral-900">{formatMoney(report.estimatedValueCovered, report.currency)}</p>
            </div>
            <div>
              <p className="text-[10px] text-neutral-500">Cobertura</p>
              <p className="font-medium text-neutral-900">
                {formatPercent(report.coveragePct)} · {report.pricedConvertibleCount}/{report.totalActiveCards}
              </p>
            </div>
            <div>
              <p className="text-[10px] text-neutral-500">Sem cotação</p>
              <p className="font-medium text-neutral-900">{report.noPriceCount}</p>
            </div>
          </div>

          {report.isPartial && (
            <p className="border-l-2 border-neutral-400 pl-2 text-[10px] text-neutral-600">
              Valor parcial — {report.noPriceCount} carta(s) ativa(s) deste Set não têm cotação confirmada nesta
              condição/moeda. O valor acima soma só as cartas com preço, nunca trata a ausência de cotação como zero.
            </p>
          )}

          {cards.items.length === 0 ? (
            <p className="text-xs text-neutral-500">Nenhuma carta ativa neste Set.</p>
          ) : (
            <>
              <table className="w-full text-[10px]">
                <thead>
                  <tr className="border-b border-neutral-300 text-left uppercase tracking-wide text-neutral-500">
                    <th className="py-1 pr-2 text-center font-normal">#</th>
                    <th className="py-1 pr-2 font-normal">Carta</th>
                    <th className="py-1 pr-2 font-normal">Variante</th>
                    <th className="py-1 pr-2 text-center font-normal">Status</th>
                    <th className="py-1 pr-2 text-right font-normal">Preço</th>
                    <th className="py-1 text-right font-normal">Participação</th>
                  </tr>
                </thead>
                <tbody>
                  {cards.items.map((item) => (
                    <tr key={item.cardId} className="border-b border-neutral-100">
                      <td className="py-1 pr-2 text-center tabular-nums text-neutral-500">{item.ranking ?? "—"}</td>
                      <td className="py-1 pr-2 text-neutral-900">
                        {item.cardName}{" "}
                        <span className="tabular-nums text-neutral-500">
                          ({item.collectorNumber}
                          {item.collectorTotal ? `/${item.collectorTotal}` : ""})
                        </span>
                      </td>
                      <td className="py-1 pr-2 text-neutral-700">
                        {item.printingLabel ?? "—"}
                        {item.pricingSourceCode ? ` (${item.pricingSourceCode})` : ""}
                      </td>
                      <td className="py-1 pr-2 text-center text-neutral-700">{STATUS_LABEL[item.status] ?? item.status}</td>
                      <td className="py-1 pr-2 text-right font-medium text-neutral-900">
                        {item.priceDisplay !== null ? formatMoney(item.priceDisplay, item.currency) : "—"}
                      </td>
                      <td className="py-1 text-right tabular-nums text-neutral-500">
                        {item.participationPct !== null ? formatPercent(item.participationPct) : "—"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <p className="text-[9px] text-neutral-400">
                Mostrando {primeiraLinha}–{ultimaLinha} de {cards.totalCount} · página {page + 1}/{totalPages}
              </p>
            </>
          )}
        </div>

        <RelatorioRodape />
      </RelatorioFolha>
    </div>
  );
}
