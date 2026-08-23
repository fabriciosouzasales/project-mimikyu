import { Package } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { RelatorioPrintButton } from "@/components/catalogo/relatorio-print-button";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { ValorPorSetSelector } from "@/components/pricing/valor-por-set-selector";
import { ValorPorSetFiltros } from "@/components/pricing/valor-por-set-filtros";
import { ValorPorSetReport } from "@/components/pricing/valor-por-set-report";
import { ValorPorSetCardsTable } from "@/components/pricing/valor-por-set-cards-table";
import { ValorPorSetPrintFolha } from "@/components/pricing/valor-por-set-print-folha";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import {
  PRICING_REPORT_SET_CARDS_PAGE_SIZE,
  getCardConditions,
  getPricingReportSet,
  getPricingReportSetCards,
  type PricingReportCurrency,
} from "@/lib/pricing/queries";
import { getCardSetsForCartas, getExpansoes, getGameOptions } from "@/lib/catalogo/queries";

const VALID_CURRENCIES = new Set(["BRL", "USD"]);

/**
 * Valor por Set (Bloco 5, migrations 3943 + 3944) — seleção Jogo/Expansão/Set,
 * condição (padrão NM), moeda (padrão BRL, opção USD), valor estimado
 * coberto + cobertura + `isPartial` explícito (agregado, `admin_get_pricing_
 * report_set`), seguido da lista/ranking de cartas que compõem o valuation
 * (`admin_get_pricing_report_set_cards`, migration 3944 — RPC dedicada
 * set-based, sem N chamadas por carta, reconciliação por construção com o
 * agregado via helper compartilhada no banco). Nenhuma agregação no
 * frontend em nenhum dos dois casos.
 *
 * Impressão (requisito transversal, 2026-08-22): mesmo padrão dos 8
 * relatórios do Catálogo Editorial — `RelatorioPrintButton` no `PageHeader`
 * (`print:hidden`), seletores/filtros/dashboard também `print:hidden`, e uma
 * `ValorPorSetPrintFolha` que só aparece em impressão, consumindo
 * exatamente `report`/`cards`/`cardsPage` já filtrados e paginados em tela
 * (nenhuma chamada extra — a impressão reflete só a página do ranking
 * exibida no momento).
 */
export default async function ValorPorSetPage({
  searchParams,
}: {
  searchParams: Promise<{
    game?: string;
    expansion?: string;
    set?: string;
    condition?: string;
    currency?: string;
    page?: string;
  }>;
}) {
  const { denied, supabase } = await requirePricingAdmin("Valor por Set", Package);
  if (denied) return denied;

  const {
    game: gameIdParam,
    expansion: expansionIdParam,
    set: cardSetId,
    condition: conditionParam,
    currency: currencyParam,
    page: pageParam,
  } = await searchParams;

  const [games, expansions, cardSets, conditions] = await Promise.all([
    getGameOptions(supabase),
    getExpansoes(supabase),
    getCardSetsForCartas(supabase),
    getCardConditions(supabase),
  ]);

  const selectedCardSet = cardSetId ? (cardSets.find((set) => set.id === cardSetId) ?? null) : null;
  const selectedGameId = gameIdParam || selectedCardSet?.gameId || "";
  const selectedExpansionId = expansionIdParam || selectedCardSet?.expansionId || "";

  const defaultConditionId = conditions.find((c) => c.code === "NM")?.id ?? conditions[0]?.id ?? "";
  const conditionId = conditionParam || defaultConditionId;
  const currency: PricingReportCurrency = VALID_CURRENCIES.has(currencyParam ?? "")
    ? (currencyParam as PricingReportCurrency)
    : "BRL";

  const requestedPage = Math.max(0, Number.parseInt(pageParam ?? "0", 10) || 0);

  const report = cardSetId
    ? await getPricingReportSet(supabase, { cardSetId, conditionId: conditionId || undefined, currency })
    : null;

  let cardsPage = requestedPage;
  let cards = { items: [] as Awaited<ReturnType<typeof getPricingReportSetCards>>["items"], totalCount: 0 };
  if (cardSetId && report) {
    cards = await getPricingReportSetCards(supabase, {
      cardSetId,
      conditionId: conditionId || undefined,
      currency,
      limit: PRICING_REPORT_SET_CARDS_PAGE_SIZE,
      offset: requestedPage * PRICING_REPORT_SET_CARDS_PAGE_SIZE,
    });

    const totalPages = Math.max(1, Math.ceil(cards.totalCount / PRICING_REPORT_SET_CARDS_PAGE_SIZE));
    if (requestedPage > 0 && requestedPage >= totalPages) {
      cardsPage = totalPages - 1;
      cards = await getPricingReportSetCards(supabase, {
        cardSetId,
        conditionId: conditionId || undefined,
        currency,
        limit: PRICING_REPORT_SET_CARDS_PAGE_SIZE,
        offset: cardsPage * PRICING_REPORT_SET_CARDS_PAGE_SIZE,
      });
    }
  }

  return (
    <AppShell title="Valor por Set" icon={Package}>
      <PageContainer className="space-y-4">
        <PageHeader className="print:hidden">
          <PageHeading>
            <div className="flex items-center gap-2">
              <Package className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Valor por Set</PageTitle>
            </div>
            <PageDescription>Valor estimado coberto e cobertura de preço das Cartas ativas de um Set.</PageDescription>
          </PageHeading>
          {report && <RelatorioPrintButton />}
        </PageHeader>

        <div className="print:hidden">
          <ValorPorSetSelector
            games={games}
            expansions={expansions}
            cardSets={cardSets}
            selectedGameId={selectedGameId}
            selectedExpansionId={selectedExpansionId}
            selectedCardSetId={cardSetId ?? ""}
          />
        </div>

        {!cardSetId ? (
          <EmptyState title="Selecione um Set para ver o relatório" description="Use os seletores acima — Jogo, Expansão e Set." />
        ) : !report ? (
          <EmptyState
            title="Set não encontrado"
            description="O Set pode ter sido removido, ou o filtro de condição/moeda ficou inválido."
          />
        ) : (
          <>
            <div className="space-y-4 print:hidden">
              {selectedCardSet && (
                <Card density="compact">
                  <CardContent density="compact" className="flex flex-wrap items-center justify-between gap-3 pt-4">
                    <div>
                      <p className="text-base font-semibold text-foreground">{selectedCardSet.name}</p>
                      <p className="text-xs text-muted-foreground">
                        {selectedCardSet.expansionName} ({selectedCardSet.code}) · {report.totalActiveCards} cartas ativas
                      </p>
                    </div>
                  </CardContent>
                </Card>
              )}

              <ValorPorSetFiltros conditions={conditions} conditionId={report.condition.id} currency={report.currency} />
              <ValorPorSetReport report={report} />
              <ValorPorSetCardsTable
                items={cards.items}
                totalCount={cards.totalCount}
                page={cardsPage}
                baseParams={{
                  game: selectedGameId,
                  expansion: selectedExpansionId,
                  set: cardSetId,
                  condition: report.condition.id,
                  currency: report.currency,
                }}
              />
            </div>

            <ValorPorSetPrintFolha
              report={report}
              cardSet={
                selectedCardSet
                  ? {
                      code: selectedCardSet.code,
                      name: selectedCardSet.name,
                      expansionName: selectedCardSet.expansionName,
                      logoUrl: null,
                    }
                  : null
              }
              cards={cards}
              page={cardsPage}
            />
          </>
        )}
      </PageContainer>
    </AppShell>
  );
}
